import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_protocol.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late ResourceTreeRepositoryImpl treeRepo;
  late ResourceCreationPipeline pipeline;
  late ResourceBlueprintRepositoryImpl blueprintRepo;
  late PartGenerationTaskRepositoryImpl taskRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_gen_task_repo_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();

    treeRepo =
        ResourceTreeRepositoryImpl(getDb: () => DatabaseService.database);
    pipeline = ResourceCreationPipeline(
      getDb: () => DatabaseService.database,
      hasAiCredentials: () => true,
      treeRepository: treeRepo,
    );
    blueprintRepo = ResourceBlueprintRepositoryImpl(
      getDb: () => DatabaseService.database,
      treeRepository: treeRepo,
    );
    taskRepo = PartGenerationTaskRepositoryImpl(
      getDb: () => DatabaseService.database,
    );
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<({ResourceBlueprint blueprint, ResourceId resourceId})>
      setupConfirmedBlueprint() async {
    final sessionResult = await pipeline.create(ResourceCreationRequest(
      resourceType: ResourceType.worldview,
      method: CreationMethod.aiReference,
      name: '极星编年史',
      idempotencyKey: 'idemp_${DateTime.now().microsecondsSinceEpoch}',
      referenceSource: ReferenceSource.text('极星世界的参考传说...'),
    ));

    final bp = ResourceBlueprint(
      blueprintId: 'bp_chronicles_1',
      sessionId: sessionResult.sessionId!,
      resourceType: ResourceType.worldview,
      suggestedName: '极星编年史',
      summary: '关于极星的大纲',
      sections: [
        BlueprintSection(
          id: 'sec_1',
          title: '纪元起源',
          parts: const [
            BlueprintPart(
              id: 'part_1',
              sectionId: 'sec_1',
              title: '创生纪',
              generationGoal: '描写世界诞生',
              estimatedLength: 1000,
              dependencies: [],
            ),
            BlueprintPart(
              id: 'part_2',
              sectionId: 'sec_1',
              title: '诸神黄昏',
              generationGoal: '描写旧神陨落',
              estimatedLength: 1200,
              dependencies: ['part_1'],
            ),
          ],
        ),
      ],
    );

    await blueprintRepo.saveBlueprint(bp);
    final confirmResult = await blueprintRepo.confirmBlueprint(
      blueprintId: bp.blueprintId,
    );
    return (
      blueprint: confirmResult.blueprint,
      resourceId: confirmResult.resourceId
    );
  }

  group('PartGenerationTaskRepository', () {
    test('loads tasks created upon blueprint confirmation', () async {
      final setup = await setupConfirmedBlueprint();
      final tasks = await taskRepo.findTasksForResource(setup.resourceId.value);

      expect(tasks.length, 2);
      expect(tasks[0].partId, '${setup.resourceId.value}_part_1');
      expect(tasks[0].dependencies, isEmpty);
      expect(tasks[0].status, 'pending');

      expect(tasks[1].partId, '${setup.resourceId.value}_part_2');
      expect(tasks[1].dependencies, ['${setup.resourceId.value}_part_1']);
      expect(tasks[1].status, 'pending');
    });

    test(
        'DAG scheduling: marks independent tasks ready and satisfies dependencies sequentially',
        () async {
      final setup = await setupConfirmedBlueprint();
      final resId = setup.resourceId.value;

      // 1. Initial check: part_1 has 0 dependencies, so it becomes ready
      final ready1 = await taskRepo.findReadyTasks(resId);
      expect(ready1.length, 1);
      expect(ready1.first.partId, '${resId}_part_1');

      // 2. Start attempt for part_1
      final att1 = await taskRepo.startAttempt(
        taskId: ready1.first.taskId,
        generationId: 'gen_run_1',
        attemptNumber: 1,
      );
      expect(att1, isNotEmpty);

      // Part 1 is generating, so ready list is now empty
      final readyDuring1 = await taskRepo.findReadyTasks(resId);
      expect(readyDuring1, isEmpty);

      // 3. Commit part_1 content
      final part1Response = PartGenerationResponse(
        protocolVersion: 1,
        generationId: 'gen_run_1',
        resourceId: setup.resourceId,
        sectionId: SectionId('${resId}_sec_1'),
        partId: PartId('${resId}_part_1'),
        attemptId: att1,
        content: '这是创生纪的详细正文，世界由虚空凝聚。',
        status: 'completed',
      );
      await taskRepo.commitPartContent(
        response: part1Response,
        taskId: ready1.first.taskId,
        attemptId: att1,
      );

      // Verify part_1 is completed in database and in resource_parts
      final part1Task = await taskRepo.findTask(ready1.first.taskId);
      expect(part1Task?.status, 'completed');

      final contentMap = await taskRepo.getPartsContent(['${resId}_part_1']);
      expect(contentMap['${resId}_part_1']?.content, contains('创生纪的详细正文'));

      // 4. Now part_2 dependencies are satisfied! It should become ready
      final ready2 = await taskRepo.findReadyTasks(resId);
      expect(ready2.length, 1);
      expect(ready2.first.partId, '${resId}_part_2');
    });

    test(
        'commitPartContent race protection: rejects late commit after cancellation',
        () async {
      final setup = await setupConfirmedBlueprint();
      final resId = setup.resourceId.value;
      final ready = await taskRepo.findReadyTasks(resId);
      final task1 = ready.first;

      final att = await taskRepo.startAttempt(
        taskId: task1.taskId,
        generationId: 'gen_1',
        attemptNumber: 1,
      );

      // User cancels task
      await taskRepo.cancelTasks(
          resourceId: resId, specificTaskId: task1.taskId);

      final resp = PartGenerationResponse(
        protocolVersion: 1,
        generationId: 'gen_1',
        resourceId: setup.resourceId,
        sectionId: SectionId('${resId}_sec_1'),
        partId: PartId(task1.partId),
        attemptId: att,
        content: '迟到的正文，不应写入',
      );

      expect(
        () => taskRepo.commitPartContent(
          response: resp,
          taskId: task1.taskId,
          attemptId: att,
        ),
        throwsA(isA<StateError>()),
      );

      // Content was NOT committed
      final contentMap = await taskRepo.getPartsContent([task1.partId]);
      expect(contentMap[task1.partId]?.content, isEmpty);
    });

    test('commitPartContent race protection: rejects superseded attempt',
        () async {
      final setup = await setupConfirmedBlueprint();
      final resId = setup.resourceId.value;
      final ready = await taskRepo.findReadyTasks(resId);
      final task1 = ready.first;

      final att1 = await taskRepo.startAttempt(
        taskId: task1.taskId,
        generationId: 'gen_1',
        attemptNumber: 1,
      );

      // Start attempt 2 (e.g. after retry)
      final att2 = await taskRepo.startAttempt(
        taskId: task1.taskId,
        generationId: 'gen_1',
        attemptNumber: 2,
      );

      // Attempt 1 arrives late
      final resp1 = PartGenerationResponse(
        protocolVersion: 1,
        generationId: 'gen_1',
        resourceId: setup.resourceId,
        sectionId: SectionId('${resId}_sec_1'),
        partId: PartId(task1.partId),
        attemptId: att1,
        content: '来自旧尝试的正文',
      );

      expect(
        () => taskRepo.commitPartContent(
          response: resp1,
          taskId: task1.taskId,
          attemptId: att1,
        ),
        throwsA(isA<StateError>()),
      );

      // Attempt 2 succeeds
      final resp2 = PartGenerationResponse(
        protocolVersion: 1,
        generationId: 'gen_1',
        resourceId: setup.resourceId,
        sectionId: SectionId('${resId}_sec_1'),
        partId: PartId(task1.partId),
        attemptId: att2,
        content: '来自新尝试的正文',
      );

      await taskRepo.commitPartContent(
        response: resp2,
        taskId: task1.taskId,
        attemptId: att2,
      );

      final contentMap = await taskRepo.getPartsContent([task1.partId]);
      expect(contentMap[task1.partId]?.content, '来自新尝试的正文');
    });

    test('recordFailedAttempt marks attempt and task failed', () async {
      final setup = await setupConfirmedBlueprint();
      final resId = setup.resourceId.value;
      final ready = await taskRepo.findReadyTasks(resId);
      final task1 = ready.first;

      final att = await taskRepo.startAttempt(
        taskId: task1.taskId,
        generationId: 'gen_1',
        attemptNumber: 1,
      );

      await taskRepo.recordFailedAttempt(
        taskId: task1.taskId,
        attemptId: att,
        errorMessage: '网络超时',
      );

      final updatedTask = await taskRepo.findTask(task1.taskId);
      expect(updatedTask?.status, 'failed');
      expect(updatedTask?.errorMessage, contains('网络超时'));
    });

    test(
        'recoverInterruptedTasks resets generating tasks back to ready/pending',
        () async {
      final setup = await setupConfirmedBlueprint();
      final resId = setup.resourceId.value;
      final ready = await taskRepo.findReadyTasks(resId);
      final task1 = ready.first;

      await taskRepo.startAttempt(
        taskId: task1.taskId,
        generationId: 'gen_crash',
        attemptNumber: 1,
      );

      // System restarts: task1 was in 'generating' status
      final recovered = await taskRepo.recoverInterruptedTasks(resId);
      expect(recovered, 1);

      final recoveredTask = await taskRepo.findTask(task1.taskId);
      // Because part_1 has 0 dependencies, it resets to ready
      expect(recoveredTask?.status, 'ready');
    });
  });
}
