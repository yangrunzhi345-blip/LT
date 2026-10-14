import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/part_generation_coordinator.dart';
import 'package:lt_dialogue/application/resources/part_generation_validator.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_service.dart';
import 'package:lt_dialogue/domain/resources/content_requirements.dart';
import 'package:lt_dialogue/domain/resources/generation_budget_allocation.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_protocol.dart';
import '../../helpers/phase10_fixture.dart';
import '../../helpers/r01_streaming_fixture.dart';

/// R1 (预算可行性与容量预留) 生产链回归。
///
/// 全部使用真实 SQLite（临时 fixture 数据库）、真实 Blueprint/Repository/
/// Coordinator；只替换模型网络输出。任何"不可行"场景都必须断言
/// 0 次 gateway 调用与 0 条 attempt，且已保存正文逐表不变。
void main() {
  final fixture = Phase10Fixture();
  setUp(() => fixture.setUp(prefix: 'lt_reserve_'));
  tearDown(fixture.tearDown);

  /// 角色卡 T=1000 → C=1200（默认 20% 弹性）。每个 Part 带显式 narrative
  /// 契约 minimum=estimated=300。契约是测试显式提供的 fixture，不是产品默认阈值。
  Future<
      ({
        ResourceId id,
        ResourceBlueprint blueprint,
        PartGenerationTaskRepositoryImpl tasks
      })> createWithContracts({
    required int partCount,
    required int minimum,
    required int estimated,
  }) async {
    final pipeline = ResourceCreationPipeline(
        getDb: () async => fixture.db,
        treeRepository: fixture.treeRepository,
        hasAiCredentials: () => true);
    final session = await pipeline.create(ResourceCreationRequest(
        resourceType: ResourceType.character,
        method: CreationMethod.aiReference,
        name: '预留角色',
        referenceSource: ReferenceSource.text('测试参考'),
        targetCharacters: 1000,
        idempotencyKey: 'reserve_${partCount}_$minimum'));
    final requirements = ContentRequirements(
      kind: PartContentKind.narrative,
      minimumCharacters: minimum,
      validationProfile: PartValidationProfile.narrativeSectionsV1,
    );
    final blueprint = ResourceBlueprint(
        blueprintId: 'reserve_plan_${partCount}_$minimum',
        sessionId: session.sessionId!,
        resourceType: ResourceType.character,
        suggestedName: '预留角色',
        summary: '',
        targetCapacity: 1000,
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

  /// Marks the first [count] ready Parts as completed with pre-existing bodies,
  /// simulating early over-expansion that already consumed the shared ceiling.
  Future<void> prefill(
    List<ResourceGenerationTask> tasks,
    List<int> lengths,
  ) async {
    for (var i = 0; i < lengths.length; i++) {
      await fixture.db.update('resource_parts', {'content': '文' * lengths[i]},
          where: 'id = ?', whereArgs: [tasks[i].partId]);
      await fixture.db.update(
          'resource_generation_tasks', {'status': 'completed'},
          where: 'task_id = ?', whereArgs: [tasks[i].taskId]);
    }
  }

  test(
      'an infeasible tail Part is refused before dispatch: 0 requests, 0 attempts, text preserved',
      () async {
    final stack =
        await createWithContracts(partCount: 4, minimum: 300, estimated: 300);
    final tasks = await stack.tasks.findReadyTasks(stack.id.value);
    // 399 + 399 + 400 = 1198 of C=1200 → 2 units left; the tail minimum is 300.
    await prefill(tasks, const [399, 399, 400]);

    var calls = 0;
    final generator = coordinator(
        stack.tasks, r01Completer('文' * 300, onCall: () => calls++));
    expect(
        await generator.generateAllParts(
            blueprintId: stack.blueprint.blueprintId, maxRetriesPerPart: 1),
        isFalse);
    expect(calls, 0, reason: '不可满足预算不得发起任何模型请求');

    final tail = await stack.tasks.findTask(tasks.last.taskId);
    expect(tail!.status, 'failed');
    final attempts = await fixture.db.query('resource_generation_attempts',
        where: 'task_id = ?', whereArgs: [tasks.last.taskId]);
    expect(attempts, isEmpty, reason: '不可行派发不得创建生成 lease');

    final tree = (await fixture.treeRepository.readTree(stack.id))!;
    expect(tree.parts.fold<int>(0, (sum, p) => sum + p.content.length), 1198);
  });

  test('a feasible tail Part still generates within the reserved budget',
      () async {
    final stack =
        await createWithContracts(partCount: 4, minimum: 300, estimated: 300);
    final tasks = await stack.tasks.findReadyTasks(stack.id.value);
    await prefill(tasks, const [100, 100, 100]);

    var calls = 0;
    final generator = coordinator(
        stack.tasks, r01Completer('文' * 300, onCall: () => calls++));
    expect(
        await generator.generateAllParts(
            blueprintId: stack.blueprint.blueprintId, maxRetriesPerPart: 1),
        isTrue);
    expect(calls, 1);

    final tree = (await fixture.treeRepository.readTree(stack.id))!;
    expect(tree.parts.fold<int>(0, (sum, p) => sum + p.content.length), 600);
  });

  test(
      'the commit refuses a body that would starve a later required Part and preserves prior content',
      () async {
    final stack =
        await createWithContracts(partCount: 3, minimum: 300, estimated: 300);
    final tasks = await stack.tasks.findReadyTasks(stack.id.value);
    final task = tasks.first;
    final attempt =
        await stack.tasks.startAttempt(taskId: task.taskId, generationId: 'g');
    final response = PartGenerationResponse(
        protocolVersion: 1,
        generationId: 'g',
        resourceId: stack.id,
        sectionId: SectionId(task.sectionId),
        partId: PartId(task.partId),
        attemptId: attempt.attemptId,
        // 1000 fits C=1200 alone, but reserving p1+p2 (600 more) does not.
        content: '文' * 1000);

    await expectLater(
        stack.tasks.commitPartContent(
            response: response,
            taskId: task.taskId,
            attemptId: attempt.attemptId,
            expectedSourceToken: attempt.sourceToken),
        throwsA(isA<PartGenerationValidationException>()));

    final contents =
        await stack.tasks.getPartsContent(tasks.map((t) => t.partId).toList());
    expect(contents[task.partId]!.content, isEmpty, reason: '被拒绝的候选不得写入正文');
    expect(
        await fixture.revisionRepository
            .readHead(stack.id, ResourceRevisionKind.latestHead),
        isNull,
        reason: '被拒绝的提交不得留下 revision head');
  });

  test(
      'manual retry of an infeasible Part makes no request and leaves the task untouched',
      () async {
    final stack =
        await createWithContracts(partCount: 4, minimum: 300, estimated: 300);
    final tasks = await stack.tasks.findReadyTasks(stack.id.value);
    await prefill(tasks, const [399, 399, 400]);

    var calls = 0;
    final generator = coordinator(
        stack.tasks, r01Completer('文' * 300, onCall: () => calls++));
    await expectLater(
        generator.retrySinglePart(
            blueprintId: stack.blueprint.blueprintId,
            partId: tasks.last.partId),
        throwsA(isA<PartGenerationBudgetInfeasibleException>()));
    expect(calls, 0);

    final tail = await stack.tasks.findTask(tasks.last.taskId);
    expect(tail!.status, 'ready', reason: '不可行的手动重试不得改变任务状态');
    final attempts = await fixture.db.query('resource_generation_attempts',
        where: 'task_id = ?', whereArgs: [tasks.last.taskId]);
    expect(attempts, isEmpty);
  });

  test(
      'a legacy Part without a confirmed contract keeps the historical floor and can still complete',
      () async {
    final stack =
        await createWithContracts(partCount: 3, minimum: 300, estimated: 300);
    // Strip the contracts from the stored blueprint to simulate a legacy plan.
    final row = (await fixture.db.query('resource_blueprints',
            where: 'blueprint_id = ?',
            whereArgs: [stack.blueprint.blueprintId]))
        .single;
    final raw = row['blueprint_json'] as String;
    final legacyJson =
        raw.replaceAll(RegExp(r',"contentRequirements":\{[^}]*\}'), '');
    await fixture.db.update(
        'resource_blueprints', {'blueprint_json': legacyJson},
        where: 'blueprint_id = ?', whereArgs: [stack.blueprint.blueprintId]);

    var calls = 0;
    final generator = coordinator(
        stack.tasks, r01Completer('文' * 300, onCall: () => calls++));
    expect(
        await generator.generateAllParts(
            blueprintId: stack.blueprint.blueprintId, maxRetriesPerPart: 1),
        isTrue);
    expect(calls, 3);
  });
}
