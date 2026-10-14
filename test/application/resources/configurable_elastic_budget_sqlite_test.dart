import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/blueprint_budget_normalizer.dart';
import 'package:lt_dialogue/application/resources/part_generation_coordinator.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_service.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/application/resources/part_generation_validator.dart';
import 'package:lt_dialogue/domain/resources/resource_limits.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';

import '../../helpers/phase10_fixture.dart';
import '../../helpers/r01_streaming_fixture.dart';

/// ADR-0003 production-path coverage: the confirm transaction freezes the
/// effective elastic percent onto the blueprint row, and both budget
/// consumption points (remaining budget + atomic-commit aggregate check) use
/// the frozen value. The global setting is only read at confirm time.
void main() {
  final fixture = Phase10Fixture();
  setUp(() => fixture.setUp(prefix: 'lt_elastic_cfg_'));
  tearDown(fixture.tearDown);

  Future<ResourceCreationResult> createSession(
    String key, {
    required String origin,
    ResourceId? explicitResourceId,
  }) {
    final pipeline = ResourceCreationPipeline(
        getDb: () async => fixture.db,
        treeRepository: fixture.treeRepository,
        hasAiCredentials: () => true);
    return pipeline.create(ResourceCreationRequest(
        resourceType: ResourceType.character,
        method: CreationMethod.aiReference,
        name: '弹性角色',
        referenceSource: ReferenceSource.text('测试参考'),
        targetCharacters: 8000,
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
            suggestedName: '弹性角色',
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

  String envelope({int? elasticPercent, String targetResource = ''}) =>
      ResourceCreationOriginEnvelope(
        origin: 'test',
        libraryMode: 'adventure',
        targetResourceId: targetResource,
        elasticPercent: elasticPercent,
      ).encode();

  test('confirm freezes the run-scoped origin override into the blueprint',
      () async {
    final session =
        await createSession('freeze_50', origin: envelope(elasticPercent: 50));
    final stack = await confirmAndPrepare(session);
    expect(await frozenPercent(stack.blueprintId), 50);

    // Changing the global setting afterwards must not touch the frozen run.
    await fixture.db.insert('settings',
        {'key': 'generation_elastic_percent', 'value': '0', 'updated_at': ''});
    expect(await frozenPercent(stack.blueprintId), 50);
  });

  test('a run without an explicit choice freezes the resource override',
      () async {
    final resource = await fixture.treeRepository.createResource(
      type: ResourceType.character,
      name: '既有角色',
      metadata: const {
        ResourceTreeSchema.metadataGenerationElasticPercentKey: 35,
      },
    );
    final state = await fixture.treeRepository.readNodeState(resource.id);
    final session = await createSession('meta_35',
        origin: envelope(targetResource: resource.id.value));
    final stack = await confirmAndPrepare(session,
        explicitResourceId: resource.id,
        expectedResourceUpdatedAt: state!.updatedAt);
    expect(await frozenPercent(stack.blueprintId), 35);
  });

  test('a run without any override freezes the global setting', () async {
    await fixture.db.insert('settings',
        {'key': 'generation_elastic_percent', 'value': '10', 'updated_at': ''});
    final session = await createSession('global_10', origin: envelope());
    final stack = await confirmAndPrepare(session);
    expect(await frozenPercent(stack.blueprintId), 10);
  });

  test('a legacy blueprint row without a snapshot keeps the fixed 20% budget',
      () async {
    final session = await createSession('legacy_20', origin: envelope());
    final stack = await confirmAndPrepare(session);
    await fixture.db.update('resource_blueprints', {'elastic_percent': null},
        where: 'blueprint_id = ?', whereArgs: [stack.blueprintId]);
    // C = min(floor(8000*1.20), 24000) = 9600.
    final tasks = await stack.tasks.findReadyTasks(stack.id.value);
    final allocation = await stack.tasks.budgetAllocation(
        resourceId: stack.id.value,
        blueprintId: stack.blueprintId,
        partId: tasks.first.partId);
    expect(allocation!.remaining, 9600);
  });

  group('frozen 0% collapses the ceiling onto the target', () {
    test('remaining budget equals T', () async {
      final session = await createSession('zero_remaining',
          origin: envelope(elasticPercent: 0));
      final stack = await confirmAndPrepare(session);
      expect(await frozenPercent(stack.blueprintId), 0);
      final tasks = await stack.tasks.findReadyTasks(stack.id.value);
      final allocation = await stack.tasks.budgetAllocation(
          resourceId: stack.id.value,
          blueprintId: stack.blueprintId,
          partId: tasks.first.partId);
      expect(allocation!.remaining, 8000);
    });

    test('commit at exactly C is accepted and C+1 rejected', () async {
      final session = await createSession('zero_commit',
          origin: envelope(elasticPercent: 0));
      final stack = await confirmAndPrepare(session);
      final tasks = await stack.tasks.findReadyTasks(stack.id.value);

      // Three siblings at 7500 total leave exactly 500 under C = 8000.
      await fixture.db.update('resource_parts', {'content': '原' * 2500},
          where: 'id = ?', whereArgs: [tasks[0].partId]);
      await fixture.db.update('resource_parts', {'content': '原' * 2500},
          where: 'id = ?', whereArgs: [tasks[1].partId]);
      await fixture.db.update('resource_parts', {'content': '原' * 2500},
          where: 'id = ?', whereArgs: [tasks[2].partId]);
      // The tested Part's old body is excluded from the aggregate.
      await fixture.db.update('resource_parts', {'content': '旧' * 400},
          where: 'id = ?', whereArgs: [tasks[3].partId]);

      final generator = PartGenerationCoordinator(
          taskRepository: stack.tasks,
          blueprintRepository: ResourceBlueprintRepositoryImpl(
              getDb: () async => fixture.db,
              treeRepository: fixture.treeRepository),
          pipeline: ResourceCreationPipeline(
              getDb: () async => fixture.db,
              treeRepository: fixture.treeRepository,
              hasAiCredentials: () => true),
          completer: r01Completer('文' * 500));

      // 7500 + 500 = 8000 = C: accepted.
      expect(
          await generator.retrySinglePart(
              blueprintId: stack.blueprintId, partId: tasks[3].partId),
          isTrue);

      // Reset the Part and attempt C+1: rejected, nothing persisted.
      await fixture.db.update('resource_parts', {'content': '旧' * 400},
          where: 'id = ?', whereArgs: [tasks[3].partId]);
      await fixture.db.update('resource_generation_tasks',
          {'status': 'ready', 'current_attempt_id': ''},
          where: 'task_id = ?', whereArgs: [tasks[3].taskId]);
      final rejected = PartGenerationCoordinator(
          taskRepository: stack.tasks,
          blueprintRepository: ResourceBlueprintRepositoryImpl(
              getDb: () async => fixture.db,
              treeRepository: fixture.treeRepository),
          pipeline: ResourceCreationPipeline(
              getDb: () async => fixture.db,
              treeRepository: fixture.treeRepository,
              hasAiCredentials: () => true),
          completer: r01Completer('文' * 501));
      await expectLater(
          rejected.retrySinglePart(
              blueprintId: stack.blueprintId, partId: tasks[3].partId),
          throwsA(isA<PartGenerationValidationException>()));
      expect(
          (await stack.tasks
                  .getPartsContent([tasks[3].partId]))[tasks[3].partId]!
              .content,
          '旧' * 400,
          reason: '被拒绝的提交不得覆盖已保存正文');
    });
  });

  group('frozen 50% widens the ceiling but never past absolute capacity', () {
    test('C = 12000 accepts exactly C and rejects C+1', () async {
      final session = await createSession('fifty_commit',
          origin: envelope(elasticPercent: 50));
      final stack = await confirmAndPrepare(session);
      final tasks = await stack.tasks.findReadyTasks(stack.id.value);

      // The per-Part cap stays 3000 (matrix item L), so exactly C is reached
      // with three 3000-char siblings plus a 3000-char Part: 12000 = C(50%).
      for (var i = 0; i < 3; i++) {
        await fixture.db.update('resource_parts', {'content': '原' * 3000},
            where: 'id = ?', whereArgs: [tasks[i].partId]);
      }
      await fixture.db.update('resource_parts', {'content': '旧' * 400},
          where: 'id = ?', whereArgs: [tasks[3].partId]);

      final generator = PartGenerationCoordinator(
          taskRepository: stack.tasks,
          blueprintRepository: ResourceBlueprintRepositoryImpl(
              getDb: () async => fixture.db,
              treeRepository: fixture.treeRepository),
          pipeline: ResourceCreationPipeline(
              getDb: () async => fixture.db,
              treeRepository: fixture.treeRepository,
              hasAiCredentials: () => true),
          completer: r01Completer('文' * 3000));
      expect(
          await generator.retrySinglePart(
              blueprintId: stack.blueprintId, partId: tasks[3].partId),
          isTrue);

      // C+1: 9200 siblings + 2800 = 12001, still under the per-Part cap but
      // rejected by the aggregate check with the frozen 50% ceiling.
      await fixture.db.update('resource_parts', {'content': '原' * 3000},
          where: 'id = ?', whereArgs: [tasks[0].partId]);
      await fixture.db.update('resource_parts', {'content': '原' * 3000},
          where: 'id = ?', whereArgs: [tasks[1].partId]);
      await fixture.db.update('resource_parts', {'content': '原' * 3201},
          where: 'id = ?', whereArgs: [tasks[2].partId]);
      await fixture.db.update('resource_parts', {'content': '旧' * 400},
          where: 'id = ?', whereArgs: [tasks[3].partId]);
      await fixture.db.update('resource_generation_tasks',
          {'status': 'ready', 'current_attempt_id': ''},
          where: 'task_id = ?', whereArgs: [tasks[3].taskId]);
      final rejected = PartGenerationCoordinator(
          taskRepository: stack.tasks,
          blueprintRepository: ResourceBlueprintRepositoryImpl(
              getDb: () async => fixture.db,
              treeRepository: fixture.treeRepository),
          pipeline: ResourceCreationPipeline(
              getDb: () async => fixture.db,
              treeRepository: fixture.treeRepository,
              hasAiCredentials: () => true),
          completer: r01Completer('文' * 2800));
      await expectLater(
          rejected.retrySinglePart(
              blueprintId: stack.blueprintId, partId: tasks[3].partId),
          throwsA(isA<PartGenerationValidationException>()));
    });

    test('a tiny target never crosses the absolute capacity', () async {
      // T = 24000 with E = 50 would ask for 36000; A = 24000 must clamp.
      final ceiling = GenerationBudgetPolicy.cumulativeCeiling(
        target: 24000,
        absolute: ResourceLimits.characterAbsoluteCharacters,
        elasticPercent: 50,
      );
      expect(ceiling, ResourceLimits.characterAbsoluteCharacters);
    });
  });
}
