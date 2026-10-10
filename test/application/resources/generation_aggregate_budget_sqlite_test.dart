import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/blueprint_budget_normalizer.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_service.dart';
import 'package:lt_dialogue/application/resources/resource_capacity_repository.dart';
import 'package:lt_dialogue/application/resources/part_generation_validator.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_protocol.dart';
import 'package:lt_dialogue/domain/resources/resource_revision.dart';
import '../../helpers/phase10_fixture.dart';

void main() {
  final fixture = Phase10Fixture();
  setUp(() => fixture.setUp(prefix: 'lt_budget_'));
  tearDown(fixture.tearDown);

  Future<
      ({
        ResourceId id,
        ResourceBlueprint blueprint,
        PartGenerationTaskRepositoryImpl tasks
      })> create(int target) async {
    final pipeline = ResourceCreationPipeline(
        getDb: () async => fixture.db,
        treeRepository: fixture.treeRepository,
        hasAiCredentials: () => true);
    final session = await pipeline.create(ResourceCreationRequest(
        resourceType: ResourceType.character,
        method: CreationMethod.aiReference,
        name: '预算角色',
        referenceSource: ReferenceSource.text('测试参考'),
        targetCharacters: target,
        idempotencyKey: 'budget_$target'));
    final blueprint = BlueprintBudgetNormalizer.normalizeToGenerationTarget(
        ResourceBlueprint(
            blueprintId: 'budget_plan_$target',
            sessionId: session.sessionId!,
            resourceType: ResourceType.character,
            suggestedName: '预算角色',
            summary: '',
            targetCapacity: target,
            sections: [
              BlueprintSection(id: 's', title: '背景', parts: [
                for (var i = 0; i < target ~/ 2000; i++)
                  BlueprintPart(
                      id: 'p$i',
                      sectionId: 's',
                      title: '背景$i',
                      generationGoal: '角色背景',
                      estimatedLength: 2000),
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
    return (id: result.resourceId, blueprint: blueprint, tasks: tasks);
  }

  for (final target in [8000, 18000, 20000]) {
    test(
        'generation target $target: actual commits stay within budget and immutable assembly readies',
        () async {
      final stack = await create(target);
      final tasks = await stack.tasks.findReadyTasks(stack.id.value);
      for (final task in tasks) {
        final attempt = await stack.tasks
            .startAttempt(taskId: task.taskId, generationId: 'g');
        final request = PartGenerationRequest(
            generationId: 'g',
            resourceId: stack.id,
            sectionId: SectionId(task.sectionId),
            partId: PartId(task.partId),
            attemptId: attempt.attemptId,
            targetBudget: task.estimatedLength,
            promptGoal: '背景',
            context: const PartGenerationContext(
                resourceName: '预算角色',
                resourceType: ResourceType.character,
                resourceSummary: '',
                sectionTitle: '背景',
                sectionSummary: '',
                partTitle: '背景'));
        final response = PartGenerationResponse(
            protocolVersion: 1,
            generationId: 'g',
            resourceId: stack.id,
            sectionId: request.sectionId,
            partId: request.partId,
            attemptId: attempt.attemptId,
            content: '文' * task.estimatedLength);
        PartGenerationValidator.validate(request: request, response: response);
        await stack.tasks.commitPartContent(
            response: response,
            taskId: task.taskId,
            attemptId: attempt.attemptId,
            expectedSourceToken: attempt.sourceToken);
      }
      final actual =
          await ResourceCapacityRepositoryImpl(getDb: () async => fixture.db)
              .measureResource(stack.id);
      final head = (await fixture.revisionRepository
          .readHead(stack.id, ResourceRevisionKind.latestHead))!;
      final state = await fixture.revisionRepository.readState(head.revisionId);
      expect(actual.activeCharacters, target);
      expect(
          state.nodes.values
              .where((node) => node.kind == RevisionNodeKind.part)
              .fold<int>(0, (sum, node) => sum + node.content.length),
          target);
      expect((await fixture.coordinator.prepare(stack.id)).record.state,
          ReadinessState.ready);
      final sessions = await fixture.db
          .query('resource_creation_sessions', columns: ['target_characters']);
      expect(sessions.single['target_characters'], target);
      debugPrint(
          'SQLITE_BUDGET sessionTarget=$target blueprintTarget=${stack.blueprint.targetCapacity} '
          'planned=${stack.blueprint.totalEstimatedLength} parts=${tasks.length} actual=${actual.activeCharacters} revision=$target ready=true');
    });
  }

  test(
      'aggregate guard rejects concurrent budget overspend and preserves prior content',
      () async {
    final stack = await create(8000);
    final tasks = await stack.tasks.findReadyTasks(stack.id.value);
    // Three historical / edited Parts already occupy 7,500 characters.
    for (final task in tasks.take(3)) {
      await fixture.db.update('resource_parts', {'content': '文' * 2500},
          where: 'id = ?', whereArgs: [task.partId]);
    }
    final task = tasks.last;
    expect(
        await stack.tasks.remainingBudget(
            resourceId: stack.id.value,
            blueprintId: task.blueprintId,
            partId: task.partId),
        500);
    final attempt =
        await stack.tasks.startAttempt(taskId: task.taskId, generationId: 'g');
    final response = PartGenerationResponse(
        protocolVersion: 1,
        generationId: 'g',
        resourceId: stack.id,
        sectionId: SectionId(task.sectionId),
        partId: PartId(task.partId),
        attemptId: attempt.attemptId,
        content: '文' * 501);
    await expectLater(
        stack.tasks.commitPartContent(
            response: response,
            taskId: task.taskId,
            attemptId: attempt.attemptId,
            expectedSourceToken: attempt.sourceToken),
        throwsA(isA<PartGenerationValidationException>()));
    final contents = await stack.tasks
        .getPartsContent(tasks.map((task) => task.partId).toList());
    expect(contents[task.partId]!.content, isEmpty);
    expect(contents[tasks.first.partId]!.content.length, 2500);
    expect(
        await fixture.revisionRepository
            .readHead(stack.id, ResourceRevisionKind.latestHead),
        isNull);
  });
}
