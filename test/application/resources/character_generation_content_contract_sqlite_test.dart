import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/part_generation_coordinator.dart';
import 'package:lt_dialogue/application/resources/part_generation_validator.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_service.dart';
import 'package:lt_dialogue/domain/resources/content_requirements.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_protocol.dart';
import 'package:lt_dialogue/domain/resources/resource_limits.dart';
import '../../helpers/phase10_fixture.dart';
import '../../helpers/r01_streaming_fixture.dart';

/// R2 (正文有效性与完成状态) 生产链回归。
///
/// 真实 SQLite（临时 fixture 数据库）、真实 Blueprint/Repository/Coordinator；
/// 只替换模型网络输出。契约是测试显式提供的 fixture，不是产品默认阈值（U6）。
/// 无契约的 legacy Part 必须保持历史行为，绝不被自动拒绝或改写。
void main() {
  final fixture = Phase10Fixture();
  setUp(() => fixture.setUp(prefix: 'lt_content_'));
  tearDown(fixture.tearDown);

  ContentRequirements narrative(
          {int minimum = 180, List<String> headings = const []}) =>
      ContentRequirements(
        kind: PartContentKind.narrative,
        minimumCharacters: minimum,
        validationProfile: PartValidationProfile.narrativeSectionsV1,
        requiredHeadings: headings,
      );

  ContentRequirements scalar({int minimum = 1}) => ContentRequirements(
        kind: PartContentKind.scalar,
        minimumCharacters: minimum,
        validationProfile: PartValidationProfile.scalarTextV1,
      );

  ContentRequirements structured({required List<String> fields}) =>
      ContentRequirements(
        kind: PartContentKind.structured,
        minimumCharacters: 1,
        validationProfile: PartValidationProfile.structuredObjectV1,
        requiredFields: fields,
      );

  Future<
      ({
        ResourceId id,
        ResourceBlueprint blueprint,
        PartGenerationTaskRepositoryImpl tasks
      })> createResource({
    required ContentRequirements? requirements,
    int partCount = 1,
    int estimated = 300,
    int targetCharacters = 1000,
    required String suffix,
  }) async {
    final pipeline = ResourceCreationPipeline(
        getDb: () async => fixture.db,
        treeRepository: fixture.treeRepository,
        hasAiCredentials: () => true);
    final session = await pipeline.create(ResourceCreationRequest(
        resourceType: ResourceType.character,
        method: CreationMethod.aiReference,
        name: '契约角色 $suffix',
        referenceSource: ReferenceSource.text('测试参考'),
        targetCharacters: targetCharacters,
        idempotencyKey: 'content_$suffix'));
    final blueprint = ResourceBlueprint(
        blueprintId: 'content_plan_$suffix',
        sessionId: session.sessionId!,
        resourceType: ResourceType.character,
        suggestedName: '契约角色 $suffix',
        summary: '',
        targetCapacity: targetCharacters,
        sections: [
          BlueprintSection(id: 's', title: '背景', parts: [
            for (var i = 0; i < partCount; i++)
              BlueprintPart(
                  id: 'p$i',
                  sectionId: 's',
                  title: '背景$i',
                  generationGoal: '角色背景',
                  estimatedLength: estimated,
                  contentRequirements: requirements),
          ])
        ]);
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

  PartGenerationCoordinator coordinator(
          PartGenerationTaskRepositoryImpl tasks, PartRawCompleter completer) =>
      PartGenerationCoordinator(
          taskRepository: tasks,
          blueprintRepository: ResourceBlueprintRepositoryImpl(
              getDb: () async => fixture.db,
              treeRepository: fixture.treeRepository),
          pipeline: ResourceCreationPipeline(
              getDb: () async => fixture.db,
              treeRepository: fixture.treeRepository,
              hasAiCredentials: () => true),
          completer: completer,
          maxConcurrency: 1);

  test(
      'narrative contract: a 1-char complete_part body is refused, never completed',
      () async {
    final stack = await createResource(
        requirements: narrative(minimum: 180), estimated: 300, suffix: 'n1');
    var calls = 0;
    final generator =
        coordinator(stack.tasks, r01Completer('荒', onCall: () => calls++));
    expect(
        await generator.generateAllParts(
            blueprintId: stack.blueprint.blueprintId, maxRetriesPerPart: 0),
        isFalse);
    expect(calls, 1);

    final tasks = await stack.tasks.findTasksForResource(stack.id.value);
    expect(tasks.single.status, 'failed', reason: '极短叙述不得 marked completed');

    final contents =
        await stack.tasks.getPartsContent(tasks.map((t) => t.partId).toList());
    expect(contents[tasks.single.partId]!.content, isEmpty,
        reason: '无效正文不得写入 resource_parts');

    expect(
        await fixture.revisionRepository
            .readHead(stack.id, ResourceRevisionKind.latestHead),
        isNull,
        reason: '被拒绝的候选不得留下 revision head');

    final attempts = await fixture.db.query('resource_generation_attempts',
        where: 'task_id = ?', whereArgs: [tasks.single.taskId]);
    expect(attempts, isNotEmpty, reason: '失败必须保留可追溯的 attempt');
    expect(attempts.single['status'], 'failed');
  });

  test(
      'narrative contract: a 2-char body is refused (complete_part is not proof)',
      () async {
    final stack = await createResource(
        requirements: narrative(minimum: 180), estimated: 300, suffix: 'n2');
    final generator = coordinator(stack.tasks, r01Completer('导师'));
    expect(
        await generator.generateAllParts(
            blueprintId: stack.blueprint.blueprintId, maxRetriesPerPart: 0),
        isFalse);
    final tasks = await stack.tasks.findTasksForResource(stack.id.value);
    expect(tasks.single.status, 'failed');
    final contents = await stack.tasks.getPartsContent([tasks.single.partId]);
    expect(contents[tasks.single.partId]!.content, isEmpty);
  });

  test('narrative contract: a body meeting the confirmed minimum completes',
      () async {
    final stack = await createResource(
        requirements: narrative(minimum: 180), estimated: 300, suffix: 'n3');
    var calls = 0;
    final generator = coordinator(
        stack.tasks, r01Completer('文' * 180, onCall: () => calls++));
    expect(
        await generator.generateAllParts(
            blueprintId: stack.blueprint.blueprintId, maxRetriesPerPart: 0),
        isTrue);
    expect(calls, 1);
    final tasks = await stack.tasks.findTasksForResource(stack.id.value);
    expect(tasks.single.status, 'completed');
    final contents = await stack.tasks.getPartsContent([tasks.single.partId]);
    expect(contents[tasks.single.partId]!.content.length, 180);
  });

  test('narrative contract: a long body missing a required heading is refused',
      () async {
    final stack = await createResource(
        requirements: narrative(minimum: 10, headings: ['开端', '发展']),
        estimated: 300,
        suffix: 'n4');
    // Long enough by length, but only one of the two required sections exists.
    final body = '# 开端\n${'很久以前。' * 30}';
    final generator = coordinator(stack.tasks, r01Completer(body));
    expect(
        await generator.generateAllParts(
            blueprintId: stack.blueprint.blueprintId, maxRetriesPerPart: 0),
        isFalse);
    final tasks = await stack.tasks.findTasksForResource(stack.id.value);
    expect(tasks.single.status, 'failed');
  });

  test('narrative contract: a body with every required heading completes',
      () async {
    final stack = await createResource(
        requirements: narrative(minimum: 10, headings: ['开端', '发展']),
        estimated: 300,
        suffix: 'n5');
    final body = '# 开端\n${'很久以前。' * 10}\n# 发展\n${'后来。' * 10}';
    final generator = coordinator(stack.tasks, r01Completer(body));
    expect(
        await generator.generateAllParts(
            blueprintId: stack.blueprint.blueprintId, maxRetriesPerPart: 0),
        isTrue);
    final tasks = await stack.tasks.findTasksForResource(stack.id.value);
    expect(tasks.single.status, 'completed');
  });

  test('scalar contract: a legal two-character value completes', () async {
    final stack = await createResource(
        requirements: scalar(minimum: 1), estimated: 10, suffix: 's1');
    var calls = 0;
    final generator =
        coordinator(stack.tasks, r01Completer('导师', onCall: () => calls++));
    expect(
        await generator.generateAllParts(
            blueprintId: stack.blueprint.blueprintId, maxRetriesPerPart: 0),
        isTrue,
        reason: '合法短 scalar 不得被误拒');
    expect(calls, 1);
    final tasks = await stack.tasks.findTasksForResource(stack.id.value);
    expect(tasks.single.status, 'completed');
    final contents = await stack.tasks.getPartsContent([tasks.single.partId]);
    expect(contents[tasks.single.partId]!.content, '导师');
  });

  test('scalar contract: a multi-line value is refused', () async {
    final stack = await createResource(
        requirements: scalar(minimum: 1), estimated: 10, suffix: 's2');
    final generator = coordinator(stack.tasks, r01Completer('导师\n其他'));
    expect(
        await generator.generateAllParts(
            blueprintId: stack.blueprint.blueprintId, maxRetriesPerPart: 0),
        isFalse);
    final tasks = await stack.tasks.findTasksForResource(stack.id.value);
    expect(tasks.single.status, 'failed');
  });

  test('structured contract: a missing required field is refused', () async {
    final stack = await createResource(
        requirements: structured(fields: ['name', 'role']),
        estimated: 50,
        suffix: 'st1');
    final generator = coordinator(stack.tasks, r01Completer('{"name":"林恩"}'));
    expect(
        await generator.generateAllParts(
            blueprintId: stack.blueprint.blueprintId, maxRetriesPerPart: 0),
        isFalse);
    final tasks = await stack.tasks.findTasksForResource(stack.id.value);
    expect(tasks.single.status, 'failed');
    final contents = await stack.tasks.getPartsContent([tasks.single.partId]);
    expect(contents[tasks.single.partId]!.content, isEmpty);
  });

  test('structured contract: a complete object completes', () async {
    final stack = await createResource(
        requirements: structured(fields: ['name', 'role']),
        estimated: 50,
        suffix: 'st2');
    final generator =
        coordinator(stack.tasks, r01Completer('{"name":"林恩","role":"法师"}'));
    expect(
        await generator.generateAllParts(
            blueprintId: stack.blueprint.blueprintId, maxRetriesPerPart: 0),
        isTrue);
    final tasks = await stack.tasks.findTasksForResource(stack.id.value);
    expect(tasks.single.status, 'completed');
  });

  test('a refused candidate never overwrites an existing committed body',
      () async {
    final stack = await createResource(
        requirements: narrative(minimum: 180), estimated: 300, suffix: 'ow');
    final task = (await stack.tasks.findReadyTasks(stack.id.value)).single;
    final original = '文' * 200;
    await fixture.db.update('resource_parts', {'content': original},
        where: 'id = ?', whereArgs: [task.partId]);
    final attempt =
        await stack.tasks.startAttempt(taskId: task.taskId, generationId: 'g');
    final response = PartGenerationResponse(
        protocolVersion: 1,
        generationId: 'g',
        resourceId: stack.id,
        sectionId: SectionId(task.sectionId),
        partId: PartId(task.partId),
        attemptId: attempt.attemptId,
        content: '荒');

    await expectLater(
        stack.tasks.commitPartContent(
            response: response,
            taskId: task.taskId,
            attemptId: attempt.attemptId,
            expectedSourceToken: attempt.sourceToken),
        throwsA(predicate<PartGenerationValidationException>(
            (e) => e.field == 'content_requirements')));

    final contents = await stack.tasks.getPartsContent([task.partId]);
    expect(contents[task.partId]!.content, original,
        reason: '被拒绝的候选不得覆盖已提交的有效正文');
    expect(
        await fixture.revisionRepository
            .readHead(stack.id, ResourceRevisionKind.latestHead),
        isNull,
        reason: '被拒绝的提交不得留下 revision head');
  });

  test('the commit re-checks the single-Part transport cap K', () async {
    final stack = await createResource(
        requirements: null,
        estimated: 300,
        targetCharacters: 20000,
        suffix: 'k');
    final task = (await stack.tasks.findReadyTasks(stack.id.value)).single;
    final attempt =
        await stack.tasks.startAttempt(taskId: task.taskId, generationId: 'g');
    final response = PartGenerationResponse(
        protocolVersion: 1,
        generationId: 'g',
        resourceId: stack.id,
        sectionId: SectionId(task.sectionId),
        partId: PartId(task.partId),
        attemptId: attempt.attemptId,
        content: 'A' * (ResourceLimits.maxPartCharacters + 1));

    await expectLater(
        stack.tasks.commitPartContent(
            response: response,
            taskId: task.taskId,
            attemptId: attempt.attemptId,
            expectedSourceToken: attempt.sourceToken),
        throwsA(predicate<PartGenerationValidationException>(
            (e) => e.field == 'content_length')));

    final contents = await stack.tasks.getPartsContent([task.partId]);
    expect(contents[task.partId]!.content, isEmpty);
  });

  test('a legacy completed short body is never auto-modified', () async {
    final stack = await createResource(
        requirements: null, estimated: 300, suffix: 'legacy');
    final task = (await stack.tasks.findReadyTasks(stack.id.value)).single;
    await fixture.db.update('resource_parts', {'content': '荒'},
        where: 'id = ?', whereArgs: [task.partId]);
    await fixture.db.update(
        'resource_generation_tasks', {'status': 'completed'},
        where: 'task_id = ?', whereArgs: [task.taskId]);

    var calls = 0;
    final generator = coordinator(
        stack.tasks, r01Completer('文' * 300, onCall: () => calls++));
    expect(
        await generator.generateAllParts(
            blueprintId: stack.blueprint.blueprintId, maxRetriesPerPart: 0),
        isTrue);
    expect(calls, 0, reason: '已完成的 legacy Part 不得被重新生成');

    final contents = await stack.tasks.getPartsContent([task.partId]);
    expect(contents[task.partId]!.content, '荒',
        reason: '历史短正文必须逐字保留，不得自动删除或改写');
    final tasks = await stack.tasks.findTasksForResource(stack.id.value);
    expect(tasks.single.status, 'completed');
  });
}
