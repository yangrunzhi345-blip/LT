import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_protocol.dart';
import 'package:lt_dialogue/domain/resources/section_control.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/section_control_repository_impl.dart';
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
      expect(att1.attemptId, isNotEmpty);
      expect(att1.sourceToken, isNotEmpty);

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
        attemptId: att1.attemptId,
        content: '这是创生纪的详细正文，世界由虚空凝聚。',
        status: 'completed',
      );
      await taskRepo.commitPartContent(
        response: part1Response,
        taskId: ready1.first.taskId,
        attemptId: att1.attemptId,
        expectedSourceToken: att1.sourceToken,
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
        attemptId: att.attemptId,
        content: '迟到的正文，不应写入',
      );

      expect(
        () => taskRepo.commitPartContent(
          response: resp,
          taskId: task1.taskId,
          attemptId: att.attemptId,
          expectedSourceToken: att.sourceToken,
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

      // Exclusive lease check: starting another attempt while generating is forbidden
      expect(
        () => taskRepo.startAttempt(
          taskId: task1.taskId,
          generationId: 'gen_1',
          attemptNumber: 2,
        ),
        throwsA(isA<StateError>()),
      );

      // Attempt 1 fails/times out, releasing lease
      await taskRepo.recordFailedAttempt(
        taskId: task1.taskId,
        attemptId: att1.attemptId,
        errorMessage: '尝试 1 超时',
      );
      await taskRepo.markTaskReady(task1.taskId);

      // Start attempt 2 (after retry)
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
        attemptId: att1.attemptId,
        content: '来自旧尝试的正文',
      );

      expect(
        () => taskRepo.commitPartContent(
          response: resp1,
          taskId: task1.taskId,
          attemptId: att1.attemptId,
          expectedSourceToken: att1.sourceToken,
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
        attemptId: att2.attemptId,
        content: '来自新尝试的正文',
      );

      await taskRepo.commitPartContent(
        response: resp2,
        taskId: task1.taskId,
        attemptId: att2.attemptId,
        expectedSourceToken: att2.sourceToken,
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
        attemptId: att.attemptId,
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

  group('Section consistency on streaming commit (B1)', () {
    late SectionControlRepositoryImpl sectionRepo;

    setUp(() {
      sectionRepo = SectionControlRepositoryImpl(
        getDb: () => DatabaseService.database,
      );
    });

    Future<
        ({
          ResourceId resourceId,
          SectionId sectionId,
          String taskId,
          String partId,
        })> readySectionAndTask() async {
      final setup = await setupConfirmedBlueprint();
      final resId = setup.resourceId.value;
      final ready = await taskRepo.findReadyTasks(resId);
      final task = ready.first;
      return (
        resourceId: setup.resourceId,
        sectionId: SectionId('${resId}_sec_1'),
        taskId: task.taskId,
        partId: task.partId,
      );
    }

    Future<void> commitContent({
      required ResourceId resourceId,
      required SectionId sectionId,
      required String taskId,
      required String partId,
      required String content,
    }) async {
      final attempt = await taskRepo.startAttempt(
        taskId: taskId,
        generationId: 'gen_b1',
        attemptNumber: 1,
      );
      await taskRepo.commitPartContent(
        response: PartGenerationResponse(
          protocolVersion: 1,
          generationId: 'gen_b1',
          resourceId: resourceId,
          sectionId: sectionId,
          partId: PartId(partId),
          attemptId: attempt.attemptId,
          content: content,
        ),
        taskId: taskId,
        attemptId: attempt.attemptId,
        expectedSourceToken: attempt.sourceToken,
      );
    }

    test('Case 1: invalidates a valid verdict and moves the section token',
        () async {
      final fixture = await readySectionAndTask();

      final before = (await sectionRepo.findSectionControlRow(
        fixture.sectionId,
      ))!;
      await sectionRepo.updateSectionValidation(
        id: fixture.sectionId,
        expectedUpdatedAt: before.updatedAt,
        state: SectionValidationState.valid,
        message: '人工确认无误',
      );
      final validated = (await sectionRepo.findSectionControlRow(
        fixture.sectionId,
      ))!;
      expect(validated.validationState, SectionValidationState.valid);

      await commitContent(
        resourceId: fixture.resourceId,
        sectionId: fixture.sectionId,
        taskId: fixture.taskId,
        partId: fixture.partId,
        content: 'AI 重新生成的正文',
      );

      final after = (await sectionRepo.findSectionControlRow(
        fixture.sectionId,
      ))!;
      expect(
        after.validationState,
        isNot(SectionValidationState.valid),
        reason: '内容已被改写，valid 不得继续存在',
      );
      expect(after.validationState, SectionValidationState.stale);
      expect(after.validationMessage, isEmpty);
      expect(
        after.updatedAt,
        isNot(validated.updatedAt),
        reason: 'Section 令牌必须随内容变化推进',
      );
    });

    test('Case 2: a section token read before the commit is rejected',
        () async {
      final fixture = await readySectionAndTask();
      final staleToken = (await sectionRepo.findSectionControlRow(
        fixture.sectionId,
      ))!
          .updatedAt;

      await commitContent(
        resourceId: fixture.resourceId,
        sectionId: fixture.sectionId,
        taskId: fixture.taskId,
        partId: fixture.partId,
        content: '流式提交的正文',
      );

      final current = (await sectionRepo.findSectionControlRow(
        fixture.sectionId,
      ))!;
      expect(current.updatedAt, isNot(staleToken));

      await expectLater(
        sectionRepo.updateSectionValidation(
          id: fixture.sectionId,
          expectedUpdatedAt: staleToken,
          state: SectionValidationState.valid,
          message: '',
        ),
        throwsA(isA<ResourceTreeConflictException>()),
      );

      // The guard is not broken outright: the current token still writes.
      await sectionRepo.updateSectionValidation(
        id: fixture.sectionId,
        expectedUpdatedAt: current.updatedAt,
        state: SectionValidationState.valid,
        message: '',
      );
      expect(
        (await sectionRepo.findSectionControlRow(fixture.sectionId))!
            .validationState,
        SectionValidationState.valid,
      );
    });

    test('Case 3: a section sync failure rolls the whole commit back',
        () async {
      final fixture = await readySectionAndTask();
      final sectionTokenBefore = (await sectionRepo.findSectionControlRow(
        fixture.sectionId,
      ))!
          .updatedAt;
      final contentBefore =
          (await taskRepo.getPartsContent([fixture.partId]))[fixture.partId]
              ?.content;
      expect(contentBefore, isEmpty, reason: '蓝图确认时正文应为占位空串');

      final attempt = await taskRepo.startAttempt(
        taskId: fixture.taskId,
        generationId: 'gen_b1',
        attemptNumber: 1,
      );

      // Force the section sync inside the transaction to fail, so the Part
      // write that already succeeded must be rolled back with it.
      final db = await DatabaseService.database;
      await db.execute(
        'CREATE TRIGGER b1_block_section_update '
        'BEFORE UPDATE ON resource_sections '
        "BEGIN SELECT RAISE(ABORT, 'B1 simulated section write failure'); END",
      );
      try {
        await expectLater(
          taskRepo.commitPartContent(
            response: PartGenerationResponse(
              protocolVersion: 1,
              generationId: 'gen_b1',
              resourceId: fixture.resourceId,
              sectionId: fixture.sectionId,
              partId: PartId(fixture.partId),
              attemptId: attempt.attemptId,
              content: '不应落库的正文',
            ),
            taskId: fixture.taskId,
            attemptId: attempt.attemptId,
            expectedSourceToken: attempt.sourceToken,
          ),
          throwsA(isA<DatabaseException>()),
        );
      } finally {
        await db.execute('DROP TRIGGER IF EXISTS b1_block_section_update');
      }

      expect(
        (await taskRepo.getPartsContent([fixture.partId]))[fixture.partId]
            ?.content,
        contentBefore,
        reason: 'Part 写入必须随事务回滚',
      );
      expect(
        (await taskRepo.findTask(fixture.taskId))!.status,
        isNot(PartTaskStatus.completed.storageValue),
        reason: '任务状态必须随事务回滚',
      );
      expect(
        (await sectionRepo.findSectionControlRow(fixture.sectionId))!.updatedAt,
        sectionTokenBefore,
        reason: 'Section 版本必须随事务回滚',
      );
    });
  });
}
