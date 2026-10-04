import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/assembly_readiness_coordinator.dart';
import 'package:lt_dialogue/application/resources/assembly_readiness_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_lifecycle_projection.dart';
import 'package:lt_dialogue/application/resources/resource_lifecycle_reconciler.dart';
import 'package:lt_dialogue/application/resources/streaming_generation_session_repository.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/streaming_generation_runtime_contracts.dart';

import '../../helpers/phase10_fixture.dart';

/// Reports one already-`completed` generation session for its resource, which
/// is exactly the durable state a finished (possibly interrupted) generation
/// leaves behind.
final class _CompletedGenerationRepository
    implements IStreamingGenerationSessionRepository {
  _CompletedGenerationRepository(this._sessions);

  final List<StreamingGenerationSession> _sessions;

  @override
  Future<StreamingGenerationSession?> findLatestSessionForResource(
    String resourceId,
  ) async {
    for (final session in _sessions.reversed) {
      if (session.resourceId.value == resourceId) return session;
    }
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used in test');
}

final class _NoCreationReader implements ResourceCreationSessionReader {
  @override
  Future<ResourceCreationSession?> latestCreationSessionForResource(
    ResourceId id,
  ) async =>
      null;
}

StreamingGenerationSession _completedSession(String resourceId,
        {int seq = 0}) =>
    StreamingGenerationSession(
      sessionId: 'gen_${seq}_$resourceId',
      resourceId: ResourceId(resourceId),
      blueprintId: 'bp_$resourceId',
      status: StreamingLifecycleStatus.completed,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  late Phase10Fixture fixture;

  setUp(() async {
    fixture = Phase10Fixture();
    await fixture.setUp(prefix: 'lt_reconcile_');
  });

  tearDown(() => fixture.tearDown());

  ResourceLifecycleProjection projectionFor(Phase10Fixture f) =>
      ResourceLifecycleProjection(
        resourceReader: f.treeRepository,
        creationReader: _NoCreationReader(),
        generationReader: _CompletedGenerationRepository(
          <StreamingGenerationSession>[
            _completedSession('res_missing'),
            _completedSession('res_stale'),
            _completedSession('res_failed'),
            _completedSession('res_restart'),
            _completedSession('res_race'),
            _completedSession('res_oldrev'),
          ],
        ),
        revisionReader: f.revisionRepository,
        readinessReader: f.readinessRepository,
      );

  ResourceLifecycleReconciler reconcilerFor(
    Phase10Fixture f, {
    ResourceLifecycleProjection? projection,
    AssemblyReadinessCoordinator? coordinator,
  }) =>
      ResourceLifecycleReconciler(
        projection: projection ?? projectionFor(f),
        readiness: coordinator ?? f.coordinator,
      );

  group('ResourceLifecycleReconciler', () {
    test(
        'completed generation with no readiness row: validating before, ready '
        'and consumable after one reconciliation', () async {
      final id = await fixture.createWorldview(
          'res_missing',
          [
            ['创世']
          ],
          summary: '概览');
      final projection = projectionFor(fixture);

      final before = await projection.read(id);
      expect(before.state, ResourceLifecycleState.validating);
      expect(before.isConsumable, isFalse);

      final result =
          await reconcilerFor(fixture, projection: projection).read(id);
      expect(result.state, ResourceLifecycleState.ready);
      expect(result.isConsumable, isTrue);

      final persisted = await fixture.readinessRepository.read(id.value);
      expect(persisted!.state, ReadinessState.ready);
    });

    test('completed generation with stale readiness re-prepares to ready',
        () async {
      final id = await fixture.createWorldview(
          'res_stale',
          [
            ['初版']
          ],
          summary: '概览');
      await fixture.coordinator.prepare(id);
      await fixture.editResourceBody(id, '修改后的内容');
      final stale = await fixture.coordinator.refresh(id);
      expect(stale!.state, ReadinessState.stale);

      final result = await reconcilerFor(fixture).read(id);
      expect(result.state, ResourceLifecycleState.ready);
      final head = await fixture.latestHeadRevision(id);
      final persisted = await fixture.readinessRepository.read(id.value);
      expect(persisted!.assemblyContentHash, head.contentHash);
    });

    test('terminal failure is left alone by read (no auto-retry)', () async {
      final id = await fixture.createWorldview(
          'res_failed',
          [
            ['正文']
          ],
          summary: '概览');
      await fixture.db.transaction((txn) {
        return fixture.readinessRepository.writeInTransaction(
          txn,
          AssemblyReadinessRecord(
            resourceId: id.value,
            state: ReadinessState.failed,
            attemptToken: 'attempt_terminal_failure',
            failureReason: 'test',
          ),
        );
      });

      final result = await reconcilerFor(fixture).read(id);
      expect(result.state, ResourceLifecycleState.failed);

      final persisted = await fixture.readinessRepository.read(id.value);
      expect(persisted!.state, ReadinessState.failed);
      // No preparation ran: the ownership token is untouched.
      expect(persisted.attemptToken, 'attempt_terminal_failure');
    });

    test('a preparation exception ends terminal, never stuck validating',
        () async {
      final id = await fixture.createWorldview(
          'res_failed',
          [
            ['正文']
          ],
          summary: '概览');

      fixture.coordinator.debugInterleaveHook = () async {
        throw const ResourceContractException('注入的校验异常');
      };
      final result = await reconcilerFor(fixture).read(id);
      fixture.coordinator.debugInterleaveHook = null;

      expect(result.state, ResourceLifecycleState.failed);
      final persisted = await fixture.readinessRepository.read(id.value);
      expect(persisted!.state, ReadinessState.failed);
    });

    test('explicit revalidate retries a terminal failure through the authority',
        () async {
      final id = await fixture.createWorldview(
          'res_failed',
          [
            ['正文']
          ],
          summary: '概览');
      await fixture.db.transaction((txn) {
        return fixture.readinessRepository.writeInTransaction(
          txn,
          AssemblyReadinessRecord(
            resourceId: id.value,
            state: ReadinessState.failed,
            attemptToken: 'attempt_terminal_failure',
          ),
        );
      });

      final result = await reconcilerFor(fixture).revalidate(id);
      expect(result.state, ResourceLifecycleState.ready);
    });

    test('restart recovery converges a historical stuck-validating resource',
        () async {
      final id = await fixture.createWorldview(
          'res_restart',
          [
            ['正文']
          ],
          summary: '概览');
      // Simulate a fresh process: a brand-new coordinator (no in-flight map)
      // over the same persisted state.
      final fresh = reconcilerFor(
        fixture,
        coordinator: fixture.secondCoordinator(),
      );
      final result = await fresh.read(id);
      expect(result.state, ResourceLifecycleState.ready);
    });

    test('concurrent reads coalesce into exactly one preparation run',
        () async {
      final id = await fixture.createWorldview(
          'res_race',
          [
            ['正文']
          ],
          summary: '概览');
      final reconciler = reconcilerFor(fixture);

      var hookCalls = 0;
      final gate = Completer<void>();
      fixture.coordinator.debugInterleaveHook = () async {
        hookCalls++;
        await gate.future;
      };

      // One run is already in flight; the reads must await it, not start
      // another validator.
      final manual = fixture.coordinator.prepare(id);
      final first = reconciler.read(id);
      final second = reconciler.read(id);
      expect(fixture.coordinator.isPreparationInFlight(id.value), isTrue);

      gate.complete();
      await manual;
      final a = await first;
      final b = await second;

      expect(a.state, ResourceLifecycleState.ready);
      expect(b.state, ResourceLifecycleState.ready);
      expect(hookCalls, 1);
      fixture.coordinator.debugInterleaveHook = null;
    });

    test(
        'a result for an obsolete head becomes stale, then converges to the '
        'new head on the next read', () async {
      final id = await fixture.createWorldview(
          'res_oldrev',
          [
            ['初版']
          ],
          summary: '概览');
      final reconciler = reconcilerFor(fixture);

      final gate = Completer<void>();
      fixture.coordinator.debugInterleaveHook = () async {
        await gate.future;
      };
      final stale = fixture.coordinator.prepare(id);
      // Head moves while the run is in flight.
      await fixture.editResourceBody(id, '运行期间被编辑');
      gate.complete();
      final staleOutcome = await stale;
      expect(staleOutcome.record.state, ReadinessState.stale);
      fixture.coordinator.debugInterleaveHook = null;

      // The reconciler converges to the NEW head, never to the obsolete one.
      final converged = await reconciler.read(id);
      expect(converged.state, ResourceLifecycleState.ready);
      final head = await fixture.latestHeadRevision(id);
      final persisted = await fixture.readinessRepository.read(id.value);
      expect(persisted!.state, ReadinessState.ready);
      expect(persisted.assemblyContentHash, head.contentHash);
    });

    test('read of a ready resource is a no-op (idempotent)', () async {
      final id = await fixture.createWorldview(
          'res_missing',
          [
            ['正文']
          ],
          summary: '概览');
      final reconciler = reconcilerFor(fixture);

      final first = await reconciler.read(id);
      final token = first.assemblyReadiness?.attemptToken;
      final second = await reconciler.read(id);
      expect(second.state, ResourceLifecycleState.ready);
      // Ready is returned untouched; no new preparation overwrote the row.
      expect(second.assemblyReadiness?.attemptToken, token);
    });

    test('a full multi-section / multi-part worldview converges to ready',
        () async {
      final id = await fixture.createWorldview(
        'res_missing',
        [
          ['概览一', '概览二', '概览三'],
          ['规则一', '规则二', '规则三'],
          ['地点一', '地点二'],
        ],
        summary: '大型世界观',
      );

      final result = await reconcilerFor(fixture).read(id);
      expect(result.state, ResourceLifecycleState.ready);
      expect(result.isConsumable, isTrue);
      final persisted = await fixture.readinessRepository.read(id.value);
      expect(persisted!.state, ReadinessState.ready);
      expect(persisted.hasAssemblyRevision, isTrue);
    });
  });
}
