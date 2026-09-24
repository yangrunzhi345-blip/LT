import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/core/localization/app_error_localizer.dart';
import 'package:lt_dialogue/domain/resources/resource_revision.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/controllers/resource_crud_controller.dart';
import 'package:lt_dialogue/domain/errors/app_error.dart';
import 'package:lt_dialogue/domain/resources/resource_capacity.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/section_control.dart';
import 'package:lt_dialogue/domain/resources/section_control_events.dart';
import 'package:lt_dialogue/domain/resources/streaming_generation_runtime_contracts.dart';
import 'package:lt_dialogue/features/resource_studio/application/use_cases/resource_capacity_runtime.dart';
import 'package:lt_dialogue/features/resource_studio/application/use_cases/resource_revision_runtime.dart';
import 'package:lt_dialogue/features/resource_studio/application/use_cases/resource_studio_runtime.dart';
import 'package:lt_dialogue/features/resource_studio/application/use_cases/section_control_runtime.dart';
import 'package:lt_dialogue/features/resource_studio/domain/models/resource_capacity_view_state.dart';
import 'package:lt_dialogue/features/resource_studio/domain/models/resource_revision_view_state.dart';
import 'package:lt_dialogue/features/resource_studio/domain/models/resource_studio_state.dart';
import 'package:lt_dialogue/features/resource_studio/domain/models/section_control_view_state.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/controllers/resource_capacity_controller.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/controllers/resource_revision_controller.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/controllers/resource_studio_controller.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/controllers/section_control_controller.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/services/repositories/library_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/resource_studio_fakes.dart';

/// R05-A regression: every async publish is bound to a request generation and
/// the target identity, so a late completion or late error of an older request
/// can never overwrite the current one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('R05-A SectionControlController', () {
    test('A1 load(A) then load(B): late A first page cannot overwrite B',
        () async {
      final gateA = Completer<SectionControlPage>();
      final gateB = Completer<SectionControlPage>();
      var requestIndex = 0;
      final runtime = _ScriptedSectionRuntime(onListSections: (resourceId) {
        requestIndex += 1;
        return requestIndex == 1 ? gateA.future : gateB.future;
      });
      final controller = SectionControlController(runtime: runtime);

      // Both loads reach the runtime synchronously; A is the stale request.
      final loadA = controller.load(const ResourceId('res_a'));
      final loadB = controller.load(const ResourceId('res_b'));
      expect(requestIndex, 2);

      gateB.complete(_page('res_b', ['s-b1']));
      await loadB;
      expect(controller.state.resourceId, const ResourceId('res_b'));
      expect(
        controller.state.entries.map((e) => e.id.value),
        ['s-b1'],
      );

      // A completes late: its result is bound to the stale generation and
      // must be discarded instead of replacing B's entries.
      gateA.complete(_page('res_a', ['s-a1']));
      await loadA;
      await pumpEventQueue();
      expect(controller.state.resourceId, const ResourceId('res_b'));
      expect(
        controller.state.entries.map((e) => e.id.value),
        ['s-b1'],
      );
    });

    test('A3 stale load error cannot mark the current resource failed',
        () async {
      final gateA = Completer<SectionControlPage>();
      final gateB = Completer<SectionControlPage>();
      var requestIndex = 0;
      final runtime = _ScriptedSectionRuntime(onListSections: (_) {
        requestIndex += 1;
        return requestIndex == 1 ? gateA.future : gateB.future;
      });
      final controller = SectionControlController(runtime: runtime);

      final loadA = controller.load(const ResourceId('res_a'));
      final loadB = controller.load(const ResourceId('res_b'));

      gateB.complete(_page('res_b', ['s-b1']));
      await loadB;
      expect(controller.state.status, SectionControlViewStatus.ready);

      gateA.completeError(StateError('stale failure'));
      await loadA;
      await pumpEventQueue();
      expect(controller.state.status, SectionControlViewStatus.ready);
      expect(controller.state.errorMessage, '');
      expect(controller.state.resourceId, const ResourceId('res_b'));
    });

    test('A5b loadMore during resource switch discards the merged page',
        () async {
      final gate = Completer<SectionControlPage>();
      var call = 0;
      final runtime = _ScriptedSectionRuntime(onListSections: (_) {
        call += 1;
        if (call == 2) {
          // The loadMore read is held back until after the resource switch.
          return gate.future;
        }
        return Future.value(
          call == 1
              ? _page('res_a', ['s-a1', 's-a2', 's-a3'], total: 4)
              : _page('res_b', ['s-b1']),
        );
      });
      final controller = SectionControlController(runtime: runtime);
      await controller.load(const ResourceId('res_a'));
      expect(controller.state.hasMore, isTrue);

      final more = controller.loadMore();
      final switched = controller.load(const ResourceId('res_b'));
      gate.complete(_page('res_a', ['s-a1', 's-a2', 's-a3'], total: 4));
      await more;
      await switched;
      await pumpEventQueue();

      expect(controller.state.resourceId, const ResourceId('res_b'));
      expect(
        controller.state.entries.map((e) => e.resourceId),
        everyElement(const ResourceId('res_b')),
      );
      expect(
        controller.state.entries.map((e) => e.id.value),
        ['s-b1'],
      );
    });
  });

  group('R05-A ResourceCapacityController', () {
    test('A2 stale summarize success discarded after resource switch',
        () async {
      final gateA = Completer<ResourceCapacitySummary>();
      final gateB = Completer<ResourceCapacitySummary>();
      var requestIndex = 0;
      final runtime = _ScriptedCapacityRuntime(onSummarize: (_) {
        requestIndex += 1;
        return requestIndex == 1 ? gateA.future : gateB.future;
      });
      final controller = ResourceCapacityController(runtime: runtime);

      final loadA = controller.load('res_a');
      final loadB = controller.load('res_b');
      expect(requestIndex, 2);

      gateB.complete(_summary('res_b'));
      await loadB;
      expect(controller.state.resourceId, const ResourceId('res_b'));
      expect(controller.state.status, ResourceCapacityViewStatus.ready);

      gateA.complete(_summary('res_a'));
      await loadA;
      await pumpEventQueue();
      expect(controller.state.resourceId, const ResourceId('res_b'));
      expect(
        controller.state.summary?.snapshot.resourceId,
        const ResourceId('res_b'),
      );
    });

    test('A7 dispose then late success does not notify', () async {
      final gate = Completer<ResourceCapacitySummary>();
      final runtime = _ScriptedCapacityRuntime(onSummarize: (_) => gate.future);
      final controller = ResourceCapacityController(runtime: runtime);
      final loadFuture = controller.load('res_a');
      expect(controller.state.status, ResourceCapacityViewStatus.loading);

      controller.dispose();
      gate.complete(_summary('res_a'));
      await loadFuture;
      await pumpEventQueue();
      // notifyListeners after dispose throws a FlutterError that fails this
      // test; surviving without an error proves the late result was dropped
      // instead of published.
      expect(controller.state.status, ResourceCapacityViewStatus.loading);
    });

    test('A8 dispose then late error does not notify', () async {
      final gate = Completer<ResourceCapacitySummary>();
      final runtime = _ScriptedCapacityRuntime(onSummarize: (_) => gate.future);
      final controller = ResourceCapacityController(runtime: runtime);
      final loadFuture = controller.load('res_a');
      expect(controller.state.status, ResourceCapacityViewStatus.loading);

      controller.dispose();
      gate.completeError(StateError('late failure'));
      await loadFuture;
      await pumpEventQueue();
      expect(controller.state.status, ResourceCapacityViewStatus.loading);
    });
  });

  group('R05-A ResourceRevisionController', () {
    test('A4 resource switch: late history of A cannot overwrite B', () async {
      final gateA = Completer<List<ResourceRevisionItem>>();
      final gateB = Completer<List<ResourceRevisionItem>>();
      var requestIndex = 0;
      final runtime = _ScriptedRevisionRuntime(
        onListHistory: (_) {
          requestIndex += 1;
          return requestIndex == 1 ? gateA.future : gateB.future;
        },
        onRestore: (_) => throw UnimplementedError(),
      );
      final controller = ResourceRevisionController(runtime: runtime);

      final loadA = controller.load('res_a');
      final loadB = controller.load('res_b');
      expect(requestIndex, 2);

      gateB.complete([_revisionItem('rev-b1')]);
      await loadB;
      expect(controller.state.resourceId, 'res_b');
      expect(controller.state.items.single.revisionId, 'rev-b1');

      gateA.complete([_revisionItem('rev-a1')]);
      await loadA;
      await pumpEventQueue();
      expect(controller.state.resourceId, 'res_b');
      expect(controller.state.items.single.revisionId, 'rev-b1');
    });

    test('A9 committed restore is reconciled, not faked back', () async {
      final restoreGate = Completer<RevisionRestoreSummary>();
      final runtime = _ScriptedRevisionRuntime(
        onListHistory: (_) async => [_revisionItem('rev-2')],
        onRestore: (_) => restoreGate.future,
      );
      final controller = ResourceRevisionController(runtime: runtime);
      await controller.load('res_a');

      final restoreFuture =
          controller.restore('rev-1', expectedUpdatedAt: 'token-1');
      restoreGate.complete(const RevisionRestoreSummary(
        alreadyAtRevision: false,
        sourceCause: RevisionCause.restore,
        headRevisionId: 'rev-2',
      ));
      final summary = await restoreFuture;

      // The destructive side effect went through exactly once and its real
      // result is reported; the controller reloads authoritative state instead
      // of pretending the operation did not happen.
      expect(summary, isNotNull);
      expect(runtime.restoreCalls, ['rev-1']);
      expect(runtime.historyCalls, ['res_a', 'res_a']);
      expect(
        controller.state.notice?.type,
        RevisionRestoreNoticeType.restored,
      );
      expect(controller.state.canRestore, isTrue);
    });
  });

  group('R05-A ResourceStudioController', () {
    test('load inversion: late first load cannot overwrite second', () async {
      final gateA = Completer<StreamingGenerationSession?>();
      final gateB = Completer<StreamingGenerationSession?>();
      var requestIndex = 0;
      final runtime = _ScriptedStudioRuntime(onLatestSession: (_) {
        requestIndex += 1;
        return requestIndex == 1 ? gateA.future : gateB.future;
      });
      final controller = ResourceStudioController(
        runtime: runtime,
        resourceId: 'res_studio_test',
      );

      final load1 = controller.load();
      final load2 = controller.load();
      expect(requestIndex, 2);

      final tree = buildStudioTestTree();
      final session = buildStudioTestSession(tree);
      gateB.complete(session);
      await load2;
      expect(controller.state.status, ResourceStudioStatus.paused);

      // Late stale completion for the superseded request is discarded.
      gateA.complete(null);
      await load1;
      await pumpEventQueue();
      expect(controller.state.session?.sessionId, session.sessionId);
      expect(controller.state.status, ResourceStudioStatus.paused);
    });

    test('double createAndStart runs the creation command once', () async {
      final creationGate = Completer<StreamingGenerationSession>();
      final runtime = _ScriptedStudioRuntime(onLatestSession: (_) async => null)
        ..onCreateAndStart = () => creationGate.future;
      final controller = ResourceStudioController(runtime: runtime);

      final first = controller.createAndStart(
        resourceType: ResourceType.worldview,
        name: '测试资源',
        referenceSource: ReferenceSource.none,
        targetCharacters: 12000,
      );
      final second = controller.createAndStart(
        resourceType: ResourceType.worldview,
        name: '测试资源',
        referenceSource: ReferenceSource.none,
        targetCharacters: 12000,
      );

      expect(runtime.createAndStartCalls, 1,
          reason: 'second tap while the first command is active is rejected');
      creationGate.complete(buildStudioTestSession(buildStudioTestTree()));
      await first;
      await second;
      expect(runtime.createAndStartCalls, 1);
    });
  });

  group('R05-A ResourceCrudController', () {
    late _MockLibraryRepository repository;

    setUp(() {
      repository = _MockLibraryRepository();
      registerFallbackValue(ResourceLibraryMode.adventure);
    });

    test('disposed mutation returns a typed, locale-neutral failure', () async {
      final controller = ResourceCrudController(repository: repository);
      controller.dispose();

      final result = await controller.deleteWorldviewPreset('wv-1');

      expect(result.success, isFalse);
      expect(result.error?.code, AppErrorCode.unknown);
      expect(result.errorMessage, isEmpty);
      final en = lookupAppLocalizations(const Locale('en'));
      final zh = lookupAppLocalizations(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      );
      expect(localizeAppError(en, result.error!), en.errorUnknown);
      expect(localizeAppError(zh, result.error!), zh.errorUnknown);
      expect(en.errorUnknown, isNot(zh.errorUnknown));
      verifyNever(() => repository.deleteWorldviewPreset(
            any(),
            mode: any(named: 'mode'),
          ));
    });

    test('A5 concurrent deletes are serialised, never interleaved', () async {
      final gateA = Completer<void>();
      final gateB = Completer<void>();
      final callLog = <String>[];
      when(() =>
              repository.deleteWorldviewPreset(any(), mode: any(named: 'mode')))
          .thenAnswer((_) async {
        callLog.add('enter-a');
        await gateA.future;
        callLog.add('exit-a');
      });
      when(() =>
              repository.deleteCharacterCard(any(), mode: any(named: 'mode')))
          .thenAnswer((_) async {
        callLog.add('enter-b');
        await gateB.future;
        callLog.add('exit-b');
      });

      final controller = ResourceCrudController(repository: repository);
      final deleteA = controller.deleteWorldviewPreset('wv-1');
      final deleteB = controller.deleteCharacterCard('card-1');
      await pumpEventQueue();
      expect(callLog, ['enter-a'],
          reason: 'B must wait until A finished (serialise policy)');

      gateA.complete();
      await pumpEventQueue();
      expect(callLog, ['enter-a', 'exit-a', 'enter-b']);
      gateB.complete();

      final resultA = await deleteA;
      final resultB = await deleteB;
      expect(resultA.success, isTrue);
      expect(resultB.success, isTrue);
    });

    test(
        'A6 double delete of the same target converges without a second '
        'overlapping write', () async {
      var inFlight = 0;
      var overlapDetected = false;
      final gate = Completer<void>();
      when(() => repository.deleteNpcCard(any(), mode: any(named: 'mode')))
          .thenAnswer((_) async {
        if (inFlight > 0) overlapDetected = true;
        inFlight += 1;
        await gate.future;
        inFlight -= 1;
      });

      final controller = ResourceCrudController(repository: repository);
      final first = controller.deleteNpcCard('npc-1');
      final second = controller.deleteNpcCard('npc-1');
      gate.complete();
      final results = await Future.wait([first, second]);

      expect(overlapDetected, isFalse,
          reason: 'serialisation must prevent overlapping destructive writes');
      for (final result in results) {
        expect(result.success, isTrue);
      }
    });

    test('a failed mutation does not stall the serialised queue', () async {
      when(() =>
              repository.deleteWorldviewPreset(any(), mode: any(named: 'mode')))
          .thenThrow(StateError('boom'));
      when(() => repository.deleteNpcCard(any(), mode: any(named: 'mode')))
          .thenAnswer((_) async {});

      final controller = ResourceCrudController(repository: repository);
      final failing = controller.deleteWorldviewPreset('wv-1');
      final following = controller.deleteNpcCard('npc-1');

      final failure = await failing;
      final success = await following;
      expect(failure.success, isFalse);
      expect(success.success, isTrue);
      expect(controller.error, isNull,
          reason: 'the second operation must own the error surface');
    });
  });
}

SectionControlPage _page(
  String resourceId,
  List<String> sectionIds, {
  int? total,
}) {
  final rid = ResourceId(resourceId);
  return SectionControlPage(
    entries: [
      for (var i = 0; i < sectionIds.length; i++)
        SectionControlEntry(
          id: SectionId(sectionIds[i]),
          resourceId: rid,
          title: 'Section ${sectionIds[i]}',
          orderIndex: i,
        ),
    ],
    totalCount: total ?? sectionIds.length,
    offset: 0,
  );
}

ResourceCapacitySummary _summary(String resourceId) {
  return ResourceCapacitySummary(
    snapshot: ResourceCapacitySnapshot(
      resourceId: ResourceId(resourceId),
      type: ResourceType.worldview,
      totalCharacters: 100,
      activeCharacters: 100,
      archivedCharacters: 0,
      estimatedTokens: 80,
      sectionCount: 1,
      partCount: 1,
      historicalRevisionCount: 0,
      status: CapacityStatus.normal,
    ),
  );
}

ResourceRevisionItem _revisionItem(String revisionId) {
  return ResourceRevisionItem(
    revisionId: revisionId,
    cause: RevisionCause.manualSave,
    label: '测试版本',
    createdAt: DateTime(2026, 9, 19),
    nodeCount: 1,
    charCount: 10,
    isHead: true,
  );
}

class _MockLibraryRepository extends Mock implements ILibraryRepository {}

/// Gated [SectionControlRuntime] double; unreachable members throw.
class _ScriptedSectionRuntime implements SectionControlRuntime {
  _ScriptedSectionRuntime({
    required Future<SectionControlPage> Function(ResourceId) onListSections,
  }) : _onListSections = onListSections;

  final Future<SectionControlPage> Function(ResourceId) _onListSections;

  @override
  Stream<SectionControlEvent> get events => const Stream.empty();

  @override
  Future<SectionControlPage> listSections({
    required ResourceId resourceId,
    int limit = 20,
    int offset = 0,
  }) =>
      _onListSections(resourceId);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}

class _ScriptedCapacityRuntime implements ResourceCapacityRuntime {
  _ScriptedCapacityRuntime({
    required Future<ResourceCapacitySummary> Function(String) onSummarize,
  }) : _onSummarize = onSummarize;

  final Future<ResourceCapacitySummary> Function(String) _onSummarize;

  @override
  Future<ResourceCapacitySummary> summarize(String resourceId) =>
      _onSummarize(resourceId);

  @override
  Future<ResourceCapacitySummary> refresh(String resourceId) =>
      _onSummarize(resourceId);

  @override
  Future<int> onEditorLeave(String resourceId) async => 0;

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}

class _ScriptedRevisionRuntime implements ResourceRevisionRuntime {
  _ScriptedRevisionRuntime({
    required Future<List<ResourceRevisionItem>> Function(String) onListHistory,
    required Future<RevisionRestoreSummary> Function(String) onRestore,
  })  : _onListHistory = onListHistory,
        _onRestore = onRestore;

  final Future<List<ResourceRevisionItem>> Function(String) _onListHistory;
  final Future<RevisionRestoreSummary> Function(String) _onRestore;
  final List<String> historyCalls = [];
  final List<String> restoreCalls = [];

  @override
  Future<List<ResourceRevisionItem>> listHistory(
    String resourceId, {
    int limit = 30,
  }) {
    historyCalls.add(resourceId);
    return _onListHistory(resourceId);
  }

  @override
  Future<RevisionRestoreSummary> restoreRevision(
    String revisionId, {
    String expectedUpdatedAt = '',
  }) {
    restoreCalls.add(revisionId);
    return _onRestore(revisionId);
  }

  @override
  Future<String?> readResourceUpdatedAt(String resourceId) async => 'token';

  @override
  void dispose() {}
}

class _ScriptedStudioRuntime implements ResourceStudioRuntime {
  _ScriptedStudioRuntime({
    required Future<StreamingGenerationSession?> Function(String)
        onLatestSession,
  }) : _onLatestSession = onLatestSession;

  final Future<StreamingGenerationSession?> Function(String) _onLatestSession;
  Future<StreamingGenerationSession> Function()? onCreateAndStart;
  int createAndStartCalls = 0;
  StreamingGenerationSession? session;

  @override
  Stream<GenerationRuntimeEvent> get events => const Stream.empty();

  @override
  Future<StreamingGenerationSession?> getLatestSessionForResource(
    String resourceId,
  ) =>
      _onLatestSession(resourceId);

  @override
  Future<StreamingGenerationSession?> getSession(String sessionId) async =>
      session?.sessionId == sessionId ? session : null;

  @override
  Future<StreamingGenerationSession?> ensureSession(
    ResourceId resourceId,
  ) async =>
      session?.resourceId == resourceId ? session : null;

  @override
  Future<StreamingGenerationSession> createAndStart({
    required ResourceType resourceType,
    required String name,
    required ReferenceSource referenceSource,
    required int targetCharacters,
    String origin = 'resource-studio',
    String libraryMode = 'adventure',
    String? idempotencyKey,
    ResourceId? targetResourceId,
    String originWorldviewId = '',
  }) {
    createAndStartCalls += 1;
    return onCreateAndStart?.call() ?? (throw UnimplementedError());
  }

  @override
  Future<ResourceTree?> readTree(ResourceId resourceId) async =>
      buildStudioTestTree();

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}
