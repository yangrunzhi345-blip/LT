import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/application/resources/resource_autosave_service.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/domain/resources/resource_autosave.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/section_control.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/pages/resource_studio_page.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';

import '../helpers/resource_capacity_fakes.dart';
import '../helpers/resource_studio_fakes.dart';
import '../helpers/responsive_test_helper.dart';
import '../helpers/section_control_fakes.dart';

/// Minimal autosave session that records the flushes the editor issues.
///
/// The debounce/journal/CAS rules live in the service tests; this fake exists
/// so the widget test can prove what the Studio toolbar does with the answers.
final class RecordingAutosaveSession implements AutosaveSession {
  final List<AutosaveFlushTrigger> flushes = <AutosaveFlushTrigger>[];

  /// Response builder for the next flush; defaults to an applied write.
  AutosaveFlushResult Function(AutosaveFlushTrigger trigger)? responder;

  /// When set, the next flush waits until it completes — used to assert the
  /// loading state without racing the test clock.
  Completer<void>? gate;

  bool disposed = false;
  int _pending = 0;

  @override
  void Function(AutosaveFlushResult result)? onFlushed;

  @override
  int get pendingCount => _pending;

  @override
  void schedule({
    required ResourceId resourceId,
    required PartId partId,
    required String content,
    required String expectedUpdatedAt,
  }) {
    _pending = 1;
  }

  @override
  Future<AutosaveFlushResult> flush({
    AutosaveFlushTrigger trigger = AutosaveFlushTrigger.manual,
  }) async {
    flushes.add(trigger);
    final waiting = gate;
    if (waiting != null) {
      await waiting.future;
      gate = null;
    }
    final result = responder?.call(trigger) ?? appliedResult(trigger);
    if (result.applied > 0) _pending = 0;
    onFlushed?.call(result);
    return result;
  }

  @override
  Future<AutosaveFlushResult> dispose() async {
    disposed = true;
    return const AutosaveFlushResult(
      trigger: AutosaveFlushTrigger.dispose,
      outcomes: <AutosaveWriteOutcome>[],
    );
  }

  @override
  Future<List<AutosaveRecoveryOutcome>> reconcilePendingDrafts({
    ResourceId? resourceId,
  }) async =>
      const <AutosaveRecoveryOutcome>[];

  @override
  Future<ResourceAutosaveDraft?> pendingDraft(PartId partId) async => null;

  @override
  Future<void> discardDraft(ResourceAutosaveDraft draft) async {}

  @override
  Future<AutosaveWriteOutcome> resolveConflictKeepMine({
    required ResourceId resourceId,
    required PartId partId,
    required String content,
  }) async =>
      AutosaveWriteOutcome(
        partId: partId.value,
        status: AutosaveWriteStatus.applied,
        checkpointId: 'auto_resolved',
      );

  @override
  Future<AutosaveWriteOutcome> resolveConflictDiscardMine({
    required ResourceId resourceId,
    required PartId partId,
  }) async =>
      AutosaveWriteOutcome(
        partId: partId.value,
        status: AutosaveWriteStatus.adoptedLive,
        checkpointId: '',
        adoptedLiveContent: '外部最新内容',
      );
}

AutosaveFlushResult appliedResult(AutosaveFlushTrigger trigger) =>
    AutosaveFlushResult(
      trigger: trigger,
      outcomes: const <AutosaveWriteOutcome>[
        AutosaveWriteOutcome(
          partId: 'part_studio_test',
          status: AutosaveWriteStatus.applied,
          checkpointId: 'auto_1',
          contentCharacters: 4,
        ),
      ],
    );

AutosaveFlushResult failedResult(AutosaveFlushTrigger trigger) =>
    AutosaveFlushResult(
      trigger: trigger,
      outcomes: const <AutosaveWriteOutcome>[
        AutosaveWriteOutcome(
          partId: 'part_studio_test',
          status: AutosaveWriteStatus.failed,
          checkpointId: '',
          code: AutosaveOutcomeCode.writeFailed,
        ),
      ],
    );

const _saveActionKey = Key('studio-save-action');

void main() {
  late FakeResourceStudioRuntime runtime;
  late ResourceTree tree;
  late RecordingAutosaveHolder holder;

  setUp(() {
    tree = buildStudioTestTree();
    runtime = FakeResourceStudioRuntime(
      tree: tree,
      session: buildStudioTestSession(tree),
    );
    holder = RecordingAutosaveHolder();
  });

  tearDown(() {
    runtime.dispose();
  });

  Widget app({
    Locale locale = const Locale('zh'),
    double textScale = 1,
  }) {
    return ProviderScope(
      overrides: [
        resourceStudioRuntimeProvider.overrideWithValue(runtime),
        sectionControlRuntimeProvider.overrideWithValue(
          FakeSectionControlRuntime(entries: [
            SectionControlEntry(
              id: tree.sections.single.id,
              resourceId: tree.resource.id,
              title: '第一章',
              orderIndex: 0,
              content: '已有正文。',
              partCount: 1,
              generationState: SectionGenerationState.generated,
              updatedAtToken: 'token-1',
            ),
          ]),
        ),
        resourceCapacityRuntimeProvider
            .overrideWithValue(FakeResourceCapacityRuntime()),
        resourceAutosaveServiceFactoryProvider.overrideWithValue(() {
          final session = RecordingAutosaveSession();
          holder.session = session;
          return session;
        }),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const ResourceStudioPage(sessionId: 'gen_studio_test'),
      ),
    );
  }

  Future<void> openPartEditor(WidgetTester tester, String editLabel) async {
    final editButton = find.text(editLabel);
    await tester.ensureVisible(editButton);
    await tester.tap(editButton);
    await tester.pumpAndSettle();
  }

  testWidgets('the worldview workbench exposes a Save action', (tester) async {
    setViewport(tester, width: 1280, height: 800);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byKey(_saveActionKey), findsOneWidget);
    expect(
      find.descendant(
          of: find.byKey(_saveActionKey), matching: find.text('保存')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a manual save flushes the open Part and reports Saved',
      (tester) async {
    setViewport(tester, width: 1280, height: 800);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await openPartEditor(tester, '编辑正文');

    await tester.enterText(find.byType(TextField), '新的世界观正文');
    await tester.pump();
    await tester.tap(find.byKey(_saveActionKey));
    await tester.pumpAndSettle();

    expect(holder.session!.flushes, contains(AutosaveFlushTrigger.manual));
    expect(
      find.descendant(
          of: find.byKey(_saveActionKey), matching: find.text('已保存')),
      findsOneWidget,
    );
    expect(find.text('已保存'), findsWidgets,
        reason: 'the page reports the saved confirmation to the user');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Save action shows a loading state and blocks a second write',
      (tester) async {
    setViewport(tester, width: 1280, height: 800);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await openPartEditor(tester, '编辑正文');

    final session = holder.session!;
    final gate = Completer<void>();
    session.gate = gate;

    await tester.enterText(find.byType(TextField), '第一条');
    await tester.pump();
    await tester.tap(find.byKey(_saveActionKey));
    await tester.pump();

    expect(
      find.descendant(
          of: find.byKey(_saveActionKey), matching: find.text('保存中...')),
      findsOneWidget,
    );

    // A disabled action must ignore the second tap.
    await tester.tap(find.byKey(_saveActionKey));
    await tester.pump();
    expect(
      session.flushes
          .where((trigger) => trigger == AutosaveFlushTrigger.manual),
      hasLength(1),
    );

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a refused save is reported as failed, never as success',
      (tester) async {
    setViewport(tester, width: 1280, height: 800);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await openPartEditor(tester, '编辑正文');

    holder.session!.responder = failedResult;
    await tester.enterText(find.byType(TextField), '保存会失败');
    await tester.pump();
    await tester.tap(find.byKey(_saveActionKey));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
          of: find.byKey(_saveActionKey), matching: find.text('保存失败')),
      findsOneWidget,
    );
    expect(find.text('保存失败'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Save action collapses to an icon button on narrow screens',
      (tester) async {
    setViewport(tester, width: 320, height: 568);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byKey(_saveActionKey), findsOneWidget);
    expect(
      find.descendant(
          of: find.byKey(_saveActionKey), matching: find.byType(IconButton)),
      findsOneWidget,
    );
    expect(find.byTooltip('保存'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Save action is localized in English', (tester) async {
    setViewport(tester, width: 1280, height: 800);
    await tester.pumpWidget(app(locale: const Locale('en')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
          of: find.byKey(_saveActionKey), matching: find.text('Save')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an AI-generated character Part saves through the same authority',
      (tester) async {
    final characterTree = buildStudioCharacterTree();
    runtime.dispose();
    runtime = FakeResourceStudioRuntime(
      tree: characterTree,
      session: buildStudioTestSession(characterTree),
    );
    setViewport(tester, width: 1280, height: 800);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await openPartEditor(tester, '编辑正文');

    await tester.enterText(find.byType(TextField), '林恩的AI设定补充');
    await tester.pump();
    await tester.tap(find.byKey(_saveActionKey));
    await tester.pumpAndSettle();

    expect(holder.session!.flushes, contains(AutosaveFlushTrigger.manual));
    expect(
      find.descendant(
          of: find.byKey(_saveActionKey), matching: find.text('已保存')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

/// A character resource created by the AI generation pipeline (it carries a
/// `creation_session_id`), so the test exercises the generated-character edit
/// surface rather than a hand-authored worldview.
ResourceTree buildStudioCharacterTree() {
  const resourceId = ResourceId('res_studio_character');
  const sectionId = SectionId('section_studio_character');
  const partId = PartId('part_studio_character');
  return ResourceTree(
    resource: const Resource(
      id: resourceId,
      type: ResourceType.character,
      name: '林恩',
      metadata: <String, Object?>{'creation_session_id': 'cs_studio_character'},
    ),
    sections: const <ResourceSection>[
      ResourceSection(
        id: sectionId,
        resourceId: resourceId,
        title: '角色设定',
        sortOrder: 0,
      ),
    ],
    parts: const <ResourcePart>[
      ResourcePart(
        id: partId,
        sectionId: sectionId,
        title: '性格',
        content: '冷静',
        sortOrder: 0,
      ),
    ],
  );
}

/// Captures the session the factory handed to the open editor.
final class RecordingAutosaveHolder {
  RecordingAutosaveSession? session;
}
