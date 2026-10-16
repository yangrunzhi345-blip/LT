import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/authorized_generation_budget.dart';
import 'package:lt_dialogue/application/resources/blueprint_budget_normalizer.dart';
import 'package:lt_dialogue/application/resources/part_generation_validator.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_capacity_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_service.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_protocol.dart';
import 'package:lt_dialogue/domain/resources/resource_limits.dart';

import '../../helpers/phase10_fixture.dart';

/// End-to-end elastic breakout on the real production persistence path
/// (SQLite + repositories + coordinator).
///
/// An authorized AI generation run may commit a cumulative body above the
/// resource type's ordinary absolute capacity (worldview 60000, character/NPC
/// 24000) up to its frozen ceiling C = floor(T*(100+E)/100). These tests prove
/// the breakout reaches persistence, capacity classification, and assembly —
/// and that unauthorized writes and genuine over-budget writes stay rejected.
void main() {
  final fixture = Phase10Fixture();
  setUp(() => fixture.setUp(prefix: 'lt_breakout_'));
  tearDown(fixture.tearDown);

  String envelope({int? elasticPercent}) => ResourceCreationOriginEnvelope(
        origin: 'test',
        libraryMode: 'adventure',
        elasticPercent: elasticPercent,
      ).encode();

  Future<
      ({
        ResourceId id,
        String blueprintId,
        PartGenerationTaskRepositoryImpl tasks,
        List<String> partIds,
      })> confirm(
    ResourceType type, {
    required int target,
    required int elasticPercent,
    required int partCount,
  }) async {
    final pipeline = ResourceCreationPipeline(
        getDb: () async => fixture.db,
        treeRepository: fixture.treeRepository,
        hasAiCredentials: () => true);
    final session = await pipeline.create(ResourceCreationRequest(
        resourceType: type,
        method: CreationMethod.aiReference,
        name: '突破资源',
        referenceSource: ReferenceSource.text('测试参考'),
        targetCharacters: target,
        idempotencyKey: 'breakout_${type.storageValue}_$target',
        origin: envelope(elasticPercent: elasticPercent)));
    final blueprint = BlueprintBudgetNormalizer.normalizeToGenerationTarget(
        ResourceBlueprint(
            blueprintId: 'bp_breakout_${type.storageValue}',
            sessionId: session.sessionId!,
            resourceType: type,
            suggestedName: '突破资源',
            summary: '',
            targetCapacity: target,
            sections: [
              BlueprintSection(id: 's', title: '背景', parts: [
                for (var i = 0; i < partCount; i++)
                  BlueprintPart(
                      id: 'p$i',
                      sectionId: 's',
                      title: '背景$i',
                      generationGoal: '内容',
                      estimatedLength: target ~/ partCount),
              ])
            ]),
        targetCharacters: target);
    final repo = ResourceBlueprintRepositoryImpl(
        getDb: () async => fixture.db, treeRepository: fixture.treeRepository);
    await repo.saveBlueprint(blueprint);
    final result =
        await repo.confirmBlueprint(blueprintId: blueprint.blueprintId);
    final tasks = PartGenerationTaskRepositoryImpl(
        getDb: () async => fixture.db,
        revisionBoundary: RevisionCaptureEngine(
            revisionRepository: fixture.revisionRepository,
            treeBoundary: fixture.treeRepository));
    final ready = await tasks.findReadyTasks(result.resourceId.value);
    return (
      id: result.resourceId,
      blueprintId: blueprint.blueprintId,
      tasks: tasks,
      partIds: ready.map((t) => t.partId).toList(),
    );
  }

  Future<void> commit(
    PartGenerationTaskRepositoryImpl tasks,
    ResourceId resourceId,
    String partId,
    int length,
  ) async {
    final task = await tasks.findTaskByPartId(partId);
    final attempt = await tasks.startAttempt(
        taskId: task!.taskId, generationId: 'g_${partId}_$length');
    final response = PartGenerationResponse(
        protocolVersion: 1,
        generationId: 'g_${partId}_$length',
        resourceId: resourceId,
        sectionId: SectionId(task.sectionId),
        partId: PartId(partId),
        attemptId: attempt.attemptId,
        content: '文' * length);
    await tasks.commitPartContent(
        response: response,
        taskId: task.taskId,
        attemptId: attempt.attemptId,
        expectedSourceToken: attempt.sourceToken);
  }

  Future<int> measure(ResourceId id) async =>
      (await ResourceCapacityRepositoryImpl(getDb: () async => fixture.db)
              .measureResource(id))
          .activeCharacters;

  test('character: commits up to C = 30000 (> old 24000) and assembles ready',
      () async {
    final stack = await confirm(ResourceType.character,
        target: 20000, elasticPercent: 50, partCount: 10);
    expect(stack.partIds, hasLength(10));

    // The frozen authorization is C = floor(20000 * 1.5) = 30000.
    expect(
      await AuthorizedGenerationBudgetReader(getDb: () async => fixture.db)
          .authorizedCeiling(stack.id.value),
      30000,
    );

    // Commit every Part at the per-Part transport cap K = 3000: 10 * 3000 =
    // 30000 = C, which is above the old 24000 absolute.
    for (final partId in stack.partIds) {
      await commit(
          stack.tasks, stack.id, partId, ResourceLimits.maxPartCharacters);
    }

    final active = await measure(stack.id);
    expect(active, 30000);
    expect(active, greaterThan(ResourceLimits.characterAbsoluteCharacters));

    final snapshot =
        await ResourceCapacityRepositoryImpl(getDb: () async => fixture.db)
            .measureResource(stack.id);
    expect(snapshot.status, CapacityStatus.elastic,
        reason: 'an authorized body above the old absolute is not overflow');
    expect(snapshot.effectiveCeiling, 30000);

    // Assembly must publish, not force compression back below A.
    final outcome = await fixture.coordinator.prepare(stack.id);
    expect(outcome.record.state, ReadinessState.ready);
  });

  test('character: exactly C is accepted but C + 1 is rejected', () async {
    final stack = await confirm(ResourceType.character,
        target: 20000, elasticPercent: 50, partCount: 10);
    // Pin every Part but the last at a fixed 3000 so the tail carries the
    // remainder of the total under test. Direct writes keep the aggregate
    // boundary as the only variable (the commit K-cap would mask it).
    for (var i = 0; i < 9; i++) {
      await fixture.db.update('resource_parts', {'content': '文' * 3000},
          where: 'id = ?', whereArgs: [stack.partIds[i]]);
    }
    // 27000 + 3000 = 30000 = C → accepted.
    await commit(stack.tasks, stack.id, stack.partIds[9], 3000);
    expect(await measure(stack.id), 30000);

    // Rewind the tail, push the siblings one unit over: 27001 + 3000 = 30001.
    await fixture.db.update('resource_parts', {'content': ''},
        where: 'id = ?', whereArgs: [stack.partIds[9]]);
    await fixture.db.update('resource_generation_tasks',
        {'status': 'ready', 'current_attempt_id': ''},
        where: 'part_id = ?', whereArgs: [stack.partIds[9]]);
    await fixture.db.update('resource_parts', {'content': '文' * 27001},
        where: 'id = ?', whereArgs: [stack.partIds[0]]);
    for (var i = 1; i < 9; i++) {
      await fixture.db.update('resource_parts', {'content': ''},
          where: 'id = ?', whereArgs: [stack.partIds[i]]);
    }
    await expectLater(commit(stack.tasks, stack.id, stack.partIds[9], 3000),
        throwsA(isA<PartGenerationValidationException>()));
    expect(await measure(stack.id), 27001,
        reason: 'the rejected commit must not persist anything');
  });

  test('worldview: commits up to 63000 (> old 60000) and assembles ready',
      () async {
    final stack = await confirm(ResourceType.worldview,
        target: 50000, elasticPercent: 50, partCount: 21);
    expect(
      await AuthorizedGenerationBudgetReader(getDb: () async => fixture.db)
          .authorizedCeiling(stack.id.value),
      75000,
    );
    // 21 * 3000 = 63000 > 60000, still within C = 75000.
    for (final partId in stack.partIds) {
      await commit(
          stack.tasks, stack.id, partId, ResourceLimits.maxPartCharacters);
    }
    final active = await measure(stack.id);
    expect(active, 63000);
    expect(active, greaterThan(ResourceLimits.worldviewAbsoluteCharacters));

    final snapshot =
        await ResourceCapacityRepositoryImpl(getDb: () async => fixture.db)
            .measureResource(stack.id);
    expect(snapshot.status, CapacityStatus.elastic);
    expect(snapshot.effectiveCeiling, 75000);

    final outcome = await fixture.coordinator.prepare(stack.id);
    expect(outcome.record.state, ReadinessState.ready);
  });

  test('npc: commits up to 27000 (> old 24000) and stays elastic', () async {
    final stack = await confirm(ResourceType.npc,
        target: 20000, elasticPercent: 50, partCount: 10);
    expect(
      await AuthorizedGenerationBudgetReader(getDb: () async => fixture.db)
          .authorizedCeiling(stack.id.value),
      30000,
    );
    // Nine siblings at the cap (27000) exceed the old 24000 absolute.
    for (var i = 0; i < 9; i++) {
      await commit(stack.tasks, stack.id, stack.partIds[i],
          ResourceLimits.maxPartCharacters);
    }
    final active = await measure(stack.id);
    expect(active, 27000);
    expect(active, greaterThan(ResourceLimits.npcAbsoluteCharacters));

    final snapshot =
        await ResourceCapacityRepositoryImpl(getDb: () async => fixture.db)
            .measureResource(stack.id);
    expect(snapshot.status, CapacityStatus.elastic);
    expect(snapshot.effectiveCeiling, 30000);
  });

  test('a legacy-frozen run keeps the historical min(..., A) budget', () async {
    final stack = await confirm(ResourceType.worldview,
        target: 50000, elasticPercent: 50, partCount: 25);
    // Simulate a row confirmed before the policy-version column existed.
    await fixture.db.update('resource_blueprints', {'budget_policy_version': 1},
        where: 'blueprint_id = ?', whereArgs: [stack.blueprintId]);

    // Legacy semantics: min(floor(50000*1.5), 60000) = 60000, not 75000.
    expect(
      await AuthorizedGenerationBudgetReader(getDb: () async => fixture.db)
          .authorizedCeiling(stack.id.value),
      60000,
    );
    // A body above 60000 stays overflow for a legacy run, so assembly would
    // require compression (fail-closed against retroactive widening).
    final policy = ResourceLimits.policyFor(ResourceType.worldview);
    expect(policy.effectiveCharacters(60000), 60000);
    expect(
      policy.statusForEffective(61000, policy.effectiveCharacters(60000)),
      CapacityStatus.overflow,
    );
  });

  test('unauthorized writes above the old absolute stay rejected', () async {
    final stack = await confirm(ResourceType.character,
        target: 8000, elasticPercent: 0, partCount: 10);
    // E = 0 freezes C = 8000. A write that would exceed it is rejected exactly
    // as before; the breakout never relaxes an unauthorized run.
    for (var i = 0; i < 9; i++) {
      await fixture.db.update('resource_parts', {'content': '文' * 900},
          where: 'id = ?', whereArgs: [stack.partIds[i]]);
    }
    await expectLater(commit(stack.tasks, stack.id, stack.partIds[9], 500),
        throwsA(isA<PartGenerationValidationException>()));
  });
}
