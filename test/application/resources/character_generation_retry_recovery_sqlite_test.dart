import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/part_generation_coordinator.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/application/resources/resource_generation_error.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_service.dart';
import 'package:lt_dialogue/application/resources/streaming_generation_session_repository.dart';
import 'package:lt_dialogue/application/resources/streaming_resource_generation_service.dart';
import 'package:lt_dialogue/domain/errors/app_error.dart';
import 'package:lt_dialogue/domain/resources/content_requirements.dart';
import 'package:lt_dialogue/domain/resources/generation_budget_allocation.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import '../../helpers/phase10_fixture.dart';
import '../../helpers/r01_streaming_fixture.dart';

/// R5（错误分类、安全预算诊断、有限重试及恢复保护）生产链回归。
///
/// 真实 SQLite、真实 Blueprint/Repository/Coordinator/StreamingService；只替换模型
/// 网络输出。核心断言：不可行任务在自动、手动、恢复三条路径下都 0 次模型请求，且
/// 持久化的安全码可跨“重启”（新实例重建）解码出安全数字。
void main() {
  final fixture = Phase10Fixture();
  setUp(() => fixture.setUp(prefix: 'lt_r5_'));
  tearDown(fixture.tearDown);

  Future<
      ({
        ResourceId id,
        ResourceBlueprint blueprint,
        PartGenerationTaskRepositoryImpl tasks,
        String creationSessionId,
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
        name: 'R5 角色',
        referenceSource: ReferenceSource.text('测试参考'),
        targetCharacters: 1000,
        idempotencyKey: 'r5_${partCount}_$minimum'));
    final requirements = ContentRequirements(
      kind: PartContentKind.narrative,
      minimumCharacters: minimum,
      validationProfile: PartValidationProfile.narrativeSectionsV1,
    );
    final blueprint = ResourceBlueprint(
        blueprintId: 'r5_plan_${partCount}_$minimum',
        sessionId: session.sessionId!,
        resourceType: ResourceType.character,
        suggestedName: 'R5 角色',
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
    return (
      id: result.resourceId,
      blueprint: blueprint,
      tasks: tasks,
      creationSessionId: session.sessionId!,
    );
  }

  ResourceBlueprintRepositoryImpl blueprintRepository() =>
      ResourceBlueprintRepositoryImpl(
          getDb: () async => fixture.db,
          treeRepository: fixture.treeRepository);

  PartGenerationCoordinator coordinator(
          PartGenerationTaskRepositoryImpl tasks, PartRawCompleter completer) =>
      PartGenerationCoordinator(
          taskRepository: tasks,
          blueprintRepository: blueprintRepository(),
          pipeline: ResourceCreationPipeline(
              getDb: () async => fixture.db,
              treeRepository: fixture.treeRepository,
              hasAiCredentials: () => true),
          completer: completer,
          maxConcurrency: 1);

  Future<void> prefill(
      List<ResourceGenerationTask> tasks, List<int> lengths) async {
    for (var i = 0; i < lengths.length; i++) {
      await fixture.db.update('resource_parts', {'content': '文' * lengths[i]},
          where: 'id = ?', whereArgs: [tasks[i].partId]);
      await fixture.db.update(
          'resource_generation_tasks', {'status': 'completed'},
          where: 'task_id = ?', whereArgs: [tasks[i].taskId]);
    }
  }

  test(
      'auto pass: an infeasible Part makes 0 calls and persists a safe budget code',
      () async {
    final stack =
        await createWithContracts(partCount: 4, minimum: 300, estimated: 300);
    final tasks = await stack.tasks.findReadyTasks(stack.id.value);
    await prefill(tasks, const [399, 399, 400]);

    var calls = 0;
    final generator = coordinator(
        stack.tasks, r01Completer('文' * 300, onCall: () => calls++));
    expect(
        await generator.generateAllParts(
            blueprintId: stack.blueprint.blueprintId, maxRetriesPerPart: 1),
        isFalse);
    expect(calls, 0, reason: '不可行任务不得发起任何模型请求');

    // Restart-like re-read: the persisted diagnostic decodes to the infeasible
    // code with its safe numbers intact.
    final tail = await stack.tasks.findTask(tasks.last.taskId);
    expect(tail!.status, 'failed');
    final decoded = resourceGenerationErrorFromCode(tail.errorMessage);
    expect(decoded.code, AppErrorCode.resourceGenerationBudgetInfeasible);
    expect(decoded.parameters['minimum'], 300);
    expect(decoded.parameters['ceiling'], 1200);
  });

  test('manual retry: an infeasible Part makes 0 calls and stays untouched',
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
    expect(
        await fixture.db.query('resource_generation_attempts',
            where: 'task_id = ?', whereArgs: [tasks.last.taskId]),
        isEmpty);
  });

  test(
      'resume: an infeasible run makes 0 calls on start and on explicit resume',
      () async {
    final stack =
        await createWithContracts(partCount: 4, minimum: 300, estimated: 300);
    final tasks = await stack.tasks.findReadyTasks(stack.id.value);
    await prefill(tasks, const [399, 399, 400]);

    var calls = 0;
    final service = StreamingResourceGenerationService(
      sessionRepository: StreamingGenerationSessionRepositoryImpl(
          getDb: () async => fixture.db),
      taskRepository: stack.tasks,
      blueprintRepository: blueprintRepository(),
      coordinator: coordinator(
          stack.tasks, r01Completer('文' * 300, onCall: () => calls++)),
    );
    final session = await service.createSession(
      resourceId: stack.id.value,
      blueprintId: stack.blueprint.blueprintId,
      creationSessionId: stack.creationSessionId,
    );
    expect(
        await service.startGeneration(sessionId: session.sessionId), isFalse);
    expect(calls, 0, reason: '不可行任务在 start 路径也不得调用模型');

    expect(await service.resumeGeneration(session.sessionId), isFalse);
    expect(calls, 0, reason: '恢复路径必须复用同一预算守卫，仍是 0 请求');
  });

  test(
      'content-incomplete: a short narrative persists a content code with numbers',
      () async {
    final stack =
        await createWithContracts(partCount: 1, minimum: 180, estimated: 300);
    var calls = 0;
    final generator =
        coordinator(stack.tasks, r01Completer('荒', onCall: () => calls++));
    expect(
        await generator.generateAllParts(
            blueprintId: stack.blueprint.blueprintId, maxRetriesPerPart: 0),
        isFalse);
    expect(calls, 1);
    final task =
        (await stack.tasks.findTasksForResource(stack.id.value)).single;
    expect(task.status, 'failed');
    final decoded = resourceGenerationErrorFromCode(task.errorMessage);
    expect(decoded.code, AppErrorCode.resourceContentIncomplete);
    expect(decoded.parameters['minimum'], 180);
    expect(decoded.parameters['actual'], 1);
  });

  test('over-budget output is retried within the bounded budget, not stopped',
      () async {
    // C = 1200 for T = 1000; a 1201-unit body is ≤ K but above the authorized
    // maximum, so it is a bounded correction rather than a hard stop.
    final stack =
        await createWithContracts(partCount: 1, minimum: 10, estimated: 300);
    var calls = 0;
    final generator = coordinator(
        stack.tasks, r01Completer('文' * 1201, onCall: () => calls++));
    expect(
        await generator.generateAllParts(
            blueprintId: stack.blueprint.blueprintId, maxRetriesPerPart: 1),
        isFalse);
    expect(calls, 2, reason: '偶发超预算属于有限纠正：1 次原始 + 1 次重试');
    final task =
        (await stack.tasks.findTasksForResource(stack.id.value)).single;
    expect(task.status, 'failed');
  });
}
