import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/blueprint_budget_normalizer.dart';
import 'package:lt_dialogue/application/resources/part_generation_coordinator.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/application/resources/part_generation_validator.dart';
import 'package:lt_dialogue/application/resources/resource_revision_service.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';

import '../../helpers/phase10_fixture.dart';
import '../../helpers/r01_streaming_fixture.dart';

/// ADR-0003 matrix items H / I / J / R, on the real production persistence
/// path (SQLite + repositories + coordinator). The pure-policy matrix and the
/// confirm-freeze coverage live in `generation_budget_policy_test.dart` and
/// `configurable_elastic_budget_sqlite_test.dart`.
///
/// - H: restart recovery — a fresh repository stack (new instances over the
///   same persisted DB) keeps the frozen snapshot, recovery never rewrites the
///   budget, and a recovered Part does not double-consume.
/// - I: failed Part retry — always uses the original frozen percent, even
///   after the global setting changed; completed Parts stay untouched.
/// - J: cumulative budget — sequential commits share one pool; exactly C is
///   accepted, C+1 rejected, and a rejected transaction leaves the already
///   saved Parts intact.
/// - R: project inherit switching — a persisted override freezes on confirm,
///   clearing it restores inheritance for later runs only, other projects and
///   already-frozen runs are unaffected.
void main() {
  final fixture = Phase10Fixture();
  setUp(() => fixture.setUp(prefix: 'lt_elastic_matrix_'));
  tearDown(fixture.tearDown);

  String envelope({int? elasticPercent, String targetResource = ''}) =>
      ResourceCreationOriginEnvelope(
        origin: 'test',
        libraryMode: 'adventure',
        targetResourceId: targetResource,
        elasticPercent: elasticPercent,
      ).encode();

  Future<ResourceCreationResult> createSession(
    String key, {
    required String origin,
    ResourceId? explicitResourceId,
    int targetCharacters = 8000,
  }) {
    final pipeline = ResourceCreationPipeline(
        getDb: () async => fixture.db,
        treeRepository: fixture.treeRepository,
        hasAiCredentials: () => true);
    return pipeline.create(ResourceCreationRequest(
        resourceType: ResourceType.character,
        method: CreationMethod.aiReference,
        name: '矩阵角色',
        referenceSource: ReferenceSource.text('测试参考'),
        targetCharacters: targetCharacters,
        idempotencyKey: key,
        origin: origin));
  }

  Future<
      ({
        ResourceId id,
        String blueprintId,
        PartGenerationTaskRepositoryImpl tasks
      })> confirmAndPrepare(
    ResourceCreationResult session, {
    ResourceId? explicitResourceId,
    String? expectedResourceUpdatedAt,
  }) async {
    final blueprint = BlueprintBudgetNormalizer.normalizeToGenerationTarget(
        ResourceBlueprint(
            blueprintId: 'bp_${session.idempotencyKey}',
            sessionId: session.sessionId!,
            resourceType: ResourceType.character,
            suggestedName: '矩阵角色',
            summary: '',
            targetCapacity: 8000,
            sections: [
              BlueprintSection(id: 's', title: '背景', parts: [
                for (var i = 0; i < 4; i++)
                  BlueprintPart(
                      id: 'p$i',
                      sectionId: 's',
                      title: '背景$i',
                      generationGoal: '角色背景',
                      estimatedLength: 2000),
              ]),
            ]),
        targetCharacters: 8000);
    final repo = ResourceBlueprintRepositoryImpl(
        getDb: () async => fixture.db, treeRepository: fixture.treeRepository);
    await repo.saveBlueprint(blueprint);
    final result = await repo.confirmBlueprint(
        blueprintId: blueprint.blueprintId,
        explicitResourceId: explicitResourceId,
        expectedResourceUpdatedAt: expectedResourceUpdatedAt);
    final tasks = PartGenerationTaskRepositoryImpl(
        getDb: () async => fixture.db,
        revisionBoundary: RevisionCaptureEngine(
            revisionRepository: fixture.revisionRepository,
            treeBoundary: fixture.treeRepository));
    return (
      id: result.resourceId,
      blueprintId: blueprint.blueprintId,
      tasks: tasks
    );
  }

  Future<int?> frozenPercent(String blueprintId) async {
    final rows = await fixture.db.query('resource_blueprints',
        columns: ['elastic_percent'],
        where: 'blueprint_id = ?',
        whereArgs: [blueprintId],
        limit: 1);
    return (rows.single['elastic_percent'] as num?)?.toInt();
  }

  PartGenerationCoordinator coordinator(
    PartGenerationTaskRepositoryImpl tasks,
    String content,
  ) =>
      PartGenerationCoordinator(
          taskRepository: tasks,
          blueprintRepository: ResourceBlueprintRepositoryImpl(
              getDb: () async => fixture.db,
              treeRepository: fixture.treeRepository),
          pipeline: ResourceCreationPipeline(
              getDb: () async => fixture.db,
              treeRepository: fixture.treeRepository,
              hasAiCredentials: () => true),
          completer: r01Completer(content));

  group('H: restart recovery keeps the frozen budget', () {
    test('a fresh repository stack recovers without rewriting the snapshot',
        () async {
      final session = await createSession('h_recover',
          origin: envelope(elasticPercent: 35));
      final stack = await confirmAndPrepare(session);
      expect(await frozenPercent(stack.blueprintId), 35);

      // Simulate a crash mid-generation: one Part is stuck in `generating`.
      final tasksBefore = await stack.tasks.findReadyTasks(stack.id.value);
      await fixture.db.update('resource_generation_tasks',
          {'status': 'generating', 'current_attempt_id': ''},
          where: 'task_id = ?', whereArgs: [tasksBefore.first.taskId]);

      // "Restart": brand-new repository instances over the same DB. The
      // global setting also changed while the app was down — it must not
      // retro-apply to the frozen run.
      await fixture.db.insert('settings', {
        'key': 'generation_elastic_percent',
        'value': '0',
        'updated_at': ''
      });
      final recoveredTasks = PartGenerationTaskRepositoryImpl(
          getDb: () async => fixture.db,
          revisionBoundary: RevisionCaptureEngine(
              revisionRepository: fixture.revisionRepository,
              treeBoundary: fixture.treeRepository));
      expect(await recoveredTasks.recoverInterruptedTasks(stack.id.value), 1);
      expect(await frozenPercent(stack.blueprintId), 35, reason: '恢复不得重写任务快照');

      // The recovered Part's budget still reads the frozen 35% ceiling
      // (C = 10800), not the new global 0% (C = 8000).
      final tasks = await recoveredTasks.findReadyTasks(stack.id.value);
      final allocation = await recoveredTasks.budgetAllocation(
          resourceId: stack.id.value,
          blueprintId: stack.blueprintId,
          partId: tasks.first.partId);
      expect(allocation!.remaining, (8000 * 135) ~/ 100);

      // Committing the recovered Part consumes the pool exactly once.
      await coordinator(recoveredTasks, '文' * 2000).retrySinglePart(
          blueprintId: stack.blueprintId, partId: tasks.first.partId);
      final afterAllocation = await recoveredTasks.budgetAllocation(
          resourceId: stack.id.value,
          blueprintId: stack.blueprintId,
          partId: tasks[1].partId);
      expect(afterAllocation!.remaining, (8000 * 135) ~/ 100 - 2000,
          reason: '恢复后的提交不得重复消费预算');
    });
  });

  group('I: failed Part retry uses the original frozen percent', () {
    test('a global change never makes a frozen retry fail or over-limit',
        () async {
      final session =
          await createSession('i_retry', origin: envelope(elasticPercent: 50));
      final stack = await confirmAndPrepare(session);
      final tasks = await stack.tasks.findReadyTasks(stack.id.value);

      // Three completed siblings at the per-Part cap.
      for (var i = 0; i < 3; i++) {
        await fixture.db.update('resource_parts', {'content': '原' * 3000},
            where: 'id = ?', whereArgs: [tasks[i].partId]);
      }
      await fixture.db.update('resource_parts', {'content': '旧' * 400},
          where: 'id = ?', whereArgs: [tasks[3].partId]);

      // The global setting shrinks to 0% AFTER the run froze 50%: the retry
      // must still judge against C(50) = 12000, not C(0) = 8000.
      await fixture.db.update('settings', {'value': '0'},
          where: 'key = ?', whereArgs: ['generation_elastic_percent']);

      // 9000 siblings + 3000 = exactly C(50): accepted under the frozen
      // snapshot; under the new global 0% it would be rejected.
      expect(
          await coordinator(stack.tasks, '文' * 3000).retrySinglePart(
              blueprintId: stack.blueprintId, partId: tasks[3].partId),
          isTrue);

      // Completed siblings were not touched by the retry.
      final contents = await stack.tasks
          .getPartsContent(tasks.map((t) => t.partId).toList());
      for (var i = 0; i < 3; i++) {
        expect(contents[tasks[i].partId]!.content, '原' * 3000);
      }
    });
  });

  group('J: cumulative budget is one shared pool', () {
    test('sequential commits share C; C accepted, C+1 rejected atomically',
        () async {
      final session = await createSession('j_pool', origin: envelope());
      final stack = await confirmAndPrepare(session);
      final tasks = await stack.tasks.findReadyTasks(stack.id.value);
      // E inherits the default 20%: C = 9600, four Parts planned at 2000.
      //
      // Each Part may take its plan plus a share of the elastic headroom, but
      // never so much that a later required Part can no longer reach its own
      // plan. 2400 each is inside every Part's dispatchable maximum and fills
      // C exactly across the three siblings plus the tail.
      for (final task in tasks.take(3)) {
        expect(
            await coordinator(stack.tasks, '文' * 2400).retrySinglePart(
                blueprintId: stack.blueprintId, partId: task.partId),
            isTrue);
      }

      // The last Part at exactly C = 9600 is still accepted.
      await fixture.db.update('resource_parts', {'content': '旧' * 400},
          where: 'id = ?', whereArgs: [tasks[3].partId]);
      await coordinator(stack.tasks, '文' * 2400).retrySinglePart(
          blueprintId: stack.blueprintId, partId: tasks[3].partId);

      // Rewind and attempt C+1: rejected with no partial write.
      await fixture.db.update('resource_parts', {'content': '旧' * 400},
          where: 'id = ?', whereArgs: [tasks[3].partId]);
      await fixture.db.update('resource_generation_tasks',
          {'status': 'ready', 'current_attempt_id': ''},
          where: 'task_id = ?', whereArgs: [tasks[3].taskId]);
      await expectLater(
          coordinator(stack.tasks, '文' * 2401).retrySinglePart(
              blueprintId: stack.blueprintId, partId: tasks[3].partId),
          throwsA(isA<PartGenerationValidationException>()));

      // The rejected transaction left every saved Part intact.
      final contents = await stack.tasks
          .getPartsContent(tasks.map((t) => t.partId).toList());
      for (var i = 0; i < 3; i++) {
        expect(contents[tasks[i].partId]!.content, '文' * 2400,
            reason: '被拒绝的提交不得破坏其他已保存正文');
      }
      expect(contents[tasks[3].partId]!.content, '旧' * 400);
    });
  });

  group('R: project inherit switching', () {
    test(
        'override freezes new runs; clearing restores inheritance; '
        'other projects and frozen runs are untouched', () async {
      // Project A carries its own 35% override; project B inherits.
      await fixture.db.insert('settings', {
        'key': 'generation_elastic_percent',
        'value': '10',
        'updated_at': ''
      });
      final resourceA = await fixture.treeRepository.createResource(
        type: ResourceType.character,
        name: '项目A',
        metadata: const {
          ResourceTreeSchema.metadataGenerationElasticPercentKey: 35,
        },
      );
      final resourceB = await fixture.treeRepository.createResource(
        type: ResourceType.character,
        name: '项目B',
      );

      // A's first run freezes the project override.
      final stateA = await fixture.treeRepository.readNodeState(resourceA.id);
      final sessionA1 = await createSession('r_a1',
          origin: envelope(targetResource: resourceA.id.value));
      final runA1 = await confirmAndPrepare(sessionA1,
          explicitResourceId: resourceA.id,
          expectedResourceUpdatedAt: stateA!.updatedAt);
      expect(await frozenPercent(runA1.blueprintId), 35);

      // B's run freezes the global 10% — A's override does not leak.
      final stateB = await fixture.treeRepository.readNodeState(resourceB.id);
      final sessionB = await createSession('r_b1',
          origin: envelope(targetResource: resourceB.id.value));
      final runB = await confirmAndPrepare(sessionB,
          explicitResourceId: resourceB.id,
          expectedResourceUpdatedAt: stateB!.updatedAt);
      expect(await frozenPercent(runB.blueprintId), 10);

      // A switches back to inherit: the next run freezes the global 10%.
      await fixture.treeRepository.updateGenerationElasticOverride(
        id: resourceA.id,
        expectedUpdatedAt:
            (await fixture.treeRepository.readNodeState(resourceA.id))!
                .updatedAt,
        percent: null,
      );
      final sessionA2 = await createSession('r_a2',
          origin: envelope(targetResource: resourceA.id.value));
      final runA2 = await confirmAndPrepare(sessionA2,
          explicitResourceId: resourceA.id,
          expectedResourceUpdatedAt:
              (await fixture.treeRepository.readNodeState(resourceA.id))!
                  .updatedAt);
      expect(await frozenPercent(runA2.blueprintId), 10);

      // B's snapshot is untouched by any of A's switches.
      expect(await frozenPercent(runB.blueprintId), 10);
      // A's already-frozen run keeps its 35% budget.
      expect(await frozenPercent(runA1.blueprintId), 35);
    });
  });
}
