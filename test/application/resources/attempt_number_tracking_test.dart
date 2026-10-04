import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/part_generation_coordinator.dart';
import 'package:lt_dialogue/application/resources/part_generation_prompt_builder.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/application/resources/streaming_generation_session_repository.dart';
import 'package:lt_dialogue/application/resources/streaming_resource_generation_service.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_protocol.dart';
import 'package:lt_dialogue/domain/resources/streaming_generation_runtime_contracts.dart';
import 'package:lt_dialogue/models/llm_task.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String _ndjson(String systemPrompt, String content) {
  String id(String field) =>
      RegExp('"$field": "(.*?)"').firstMatch(systemPrompt)?.group(1) ?? '';
  final common = <String, Object>{
    'protocol_version': 1,
    'generation_id': id('generation_id'),
    'resource_id': id('resource_id'),
    'section_id': id('section_id'),
    'part_id': id('part_id'),
    'attempt_id': id('attempt_id'),
  };
  return [
    {...common, 'sequence': 0, 'op': 'start_part', 'cursor': 0},
    {
      ...common,
      'sequence': 1,
      'op': 'append_text',
      'text_delta': content,
      'cursor': 0,
    },
    {
      ...common,
      'sequence': 2,
      'op': 'complete_part',
      'cursor': content.length,
      'summary': '摘要',
    },
  ].map(jsonEncode).join('\n');
}

String _partIdOf(String systemPrompt) =>
    RegExp(r'"part_id": "(.*?)"').firstMatch(systemPrompt)?.group(1) ?? '';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late ResourceTreeRepositoryImpl treeRepo;
  late ResourceCreationPipeline pipeline;
  late ResourceBlueprintRepositoryImpl blueprintRepo;
  late PartGenerationTaskRepositoryImpl taskRepo;
  late StreamingGenerationSessionRepositoryImpl sessionRepo;
  late Database db;

  late Map<String, int> calls;
  late Set<String> failParts;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_attempt_number_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    db = await DatabaseService.database;

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
    taskRepo =
        PartGenerationTaskRepositoryImpl(getDb: () => DatabaseService.database);
    sessionRepo = StreamingGenerationSessionRepositoryImpl(
      getDb: () => DatabaseService.database,
    );
    calls = <String, int>{};
    failParts = <String>{};
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  PartRawCompleter completer() => ({
        required String systemPrompt,
        required String instruction,
        required LlmTask task,
        GenerationTaskHandle? taskHandle,
      }) async {
        final partId = _partIdOf(systemPrompt);
        calls.update(partId, (count) => count + 1, ifAbsent: () => 1);
        if (failParts.contains(partId)) {
          throw StateError('Simulated provider failure for $partId');
        }
        return _ndjson(systemPrompt, '内容 $partId');
      };

  Future<({String resourceId, String blueprintId, String sessionId})> setup({
    int partCount = 1,
  }) async {
    final creation = await pipeline.create(ResourceCreationRequest(
      resourceType: ResourceType.worldview,
      method: CreationMethod.aiReference,
      name: 'Attempt 编号测试资源',
      idempotencyKey: 'attempt_${DateTime.now().microsecondsSinceEpoch}',
      referenceSource: ReferenceSource.text('Attempt 编号参考材料'),
    ));
    final blueprint = ResourceBlueprint(
      blueprintId: 'bp_attempt_${DateTime.now().microsecondsSinceEpoch}',
      sessionId: creation.sessionId!,
      resourceType: ResourceType.worldview,
      suggestedName: 'Attempt 编号测试资源',
      summary: 'Attempt 编号',
      sections: [
        BlueprintSection(
          id: 'sec_1',
          title: '第一章',
          parts: [
            for (var index = 1; index <= partCount; index++)
              BlueprintPart(
                id: 'part_$index',
                sectionId: 'sec_1',
                title: '第 $index 节',
                generationGoal: '生成第 $index 节',
                estimatedLength: 300,
                dependencies: const <String>[],
              ),
          ],
        ),
      ],
    );
    await blueprintRepo.saveBlueprint(blueprint);
    final confirmation = await blueprintRepo.confirmBlueprint(
      blueprintId: blueprint.blueprintId,
    );
    return (
      resourceId: confirmation.resourceId.value,
      blueprintId: blueprint.blueprintId,
      sessionId: creation.sessionId!,
    );
  }

  StreamingResourceGenerationService buildService() =>
      StreamingResourceGenerationService(
        sessionRepository: sessionRepo,
        taskRepository: taskRepo,
        blueprintRepository: blueprintRepo,
        pipeline: pipeline,
        coordinator: PartGenerationCoordinator(
          taskRepository: taskRepo,
          blueprintRepository: blueprintRepo,
          pipeline: pipeline,
          completer: completer(),
          maxConcurrency: 1,
        ),
      );

  Future<String> taskIdForPart(String resourceId, int index) async {
    final task = (await taskRepo.findTasksForResource(resourceId))
        .firstWhere((t) => t.partId == '${resourceId}_part_$index');
    return task.taskId;
  }

  /// Persisted attempt rows for a task, in creation order.
  Future<List<int>> attemptNumbers(String taskId) async {
    final rows = await db.query(
      'resource_generation_attempts',
      columns: const ['attempt_number'],
      where: 'task_id = ?',
      whereArgs: [taskId],
      orderBy: 'rowid ASC',
    );
    return [for (final row in rows) row['attempt_number'] as int];
  }

  Future<List<String>> attemptStatuses(String taskId) async {
    final rows = await db.query(
      'resource_generation_attempts',
      columns: const ['status'],
      where: 'task_id = ?',
      whereArgs: [taskId],
      orderBy: 'rowid ASC',
    );
    return [for (final row in rows) row['status'] as String];
  }

  Future<void> releaseTask(String taskId) async {
    await taskRepo.markTaskReady(taskId);
  }

  // ── Repository authority ────────────────────────────────────────────────

  test('A/B: the first attempt is 1 and each new attempt row increments',
      () async {
    final setupRef = await setup();
    final taskId = await taskIdForPart(setupRef.resourceId, 1);
    await taskRepo.findReadyTasks(setupRef.resourceId);

    final first = await taskRepo.startAttempt(
      taskId: taskId,
      generationId: 'gen_1',
    );
    expect(first.attemptNumber, 1);

    await taskRepo.recordFailedAttempt(
      taskId: taskId,
      attemptId: first.attemptId,
      errorMessage: 'attempt 1 failed',
    );
    await releaseTask(taskId);

    final second = await taskRepo.startAttempt(
      taskId: taskId,
      generationId: 'gen_2',
    );
    expect(second.attemptNumber, 2);
    expect(await attemptNumbers(taskId), [1, 2]);
  });

  test('D: attempts are counted per task, never globally', () async {
    final setupRef = await setup(partCount: 2);
    await taskRepo.findReadyTasks(setupRef.resourceId);
    final taskA = await taskIdForPart(setupRef.resourceId, 1);
    final taskB = await taskIdForPart(setupRef.resourceId, 2);

    // Task A: 1 → 2 → 3
    for (var i = 0; i < 3; i++) {
      final attempt = await taskRepo.startAttempt(
        taskId: taskA,
        generationId: 'gen_a_$i',
      );
      expect(attempt.attemptNumber, i + 1);
      await taskRepo.recordFailedAttempt(
        taskId: taskA,
        attemptId: attempt.attemptId,
        errorMessage: 'failed',
      );
      await releaseTask(taskA);
    }

    // Task B: 1 → 2, unaffected by Task A's counter.
    for (var i = 0; i < 2; i++) {
      final attempt = await taskRepo.startAttempt(
        taskId: taskB,
        generationId: 'gen_b_$i',
      );
      expect(attempt.attemptNumber, i + 1);
      if (i == 0) {
        await taskRepo.recordFailedAttempt(
          taskId: taskB,
          attemptId: attempt.attemptId,
          errorMessage: 'failed',
        );
        await releaseTask(taskB);
      }
    }

    expect(await attemptNumbers(taskA), [1, 2, 3]);
    expect(await attemptNumbers(taskB), [1, 2]);
  });

  test('E: concurrent leases on one task yield exactly one new attempt',
      () async {
    final setupRef = await setup();
    final taskId = await taskIdForPart(setupRef.resourceId, 1);
    await taskRepo.findReadyTasks(setupRef.resourceId);

    final results = <Future<PartGenerationAttempt>>[
      taskRepo.startAttempt(taskId: taskId, generationId: 'gen_a'),
      taskRepo.startAttempt(taskId: taskId, generationId: 'gen_b'),
    ];
    var successes = 0;
    for (final future in results) {
      try {
        await future;
        successes++;
      } catch (_) {
        // The exclusive lease rejects the second concurrent attempt.
      }
    }

    expect(successes, 1);
    expect(await attemptNumbers(taskId), [1]);
  });

  test('F/G: a failed attempt is persisted, and numbering survives a reload',
      () async {
    final setupRef = await setup();
    final taskId = await taskIdForPart(setupRef.resourceId, 1);
    await taskRepo.findReadyTasks(setupRef.resourceId);

    final first = await taskRepo.startAttempt(
      taskId: taskId,
      generationId: 'gen_1',
    );
    await taskRepo.recordFailedAttempt(
      taskId: taskId,
      attemptId: first.attemptId,
      errorMessage: 'attempt 1 failed',
    );
    expect(await attemptNumbers(taskId), [1]);
    expect(await attemptStatuses(taskId), ['failed']);

    // A fresh repository instance models an application restart: the numbering
    // comes from persistence, so it must not reset to 1.
    final reloaded =
        PartGenerationTaskRepositoryImpl(getDb: () => DatabaseService.database);
    await reloaded.markTaskReady(taskId);
    final second = await reloaded.startAttempt(
      taskId: taskId,
      generationId: 'gen_2',
    );
    expect(second.attemptNumber, 2);
    expect(await attemptNumbers(taskId), [1, 2]);
  });

  test('H: legacy duplicate numbering (1,1,1) continues at the true ordinal',
      () async {
    final setupRef = await setup();
    final taskId = await taskIdForPart(setupRef.resourceId, 1);
    await taskRepo.findReadyTasks(setupRef.resourceId);

    // Simulate the legacy defect: three retired attempts that all stored 1.
    final now = DateTime.now().toIso8601String();
    for (var i = 0; i < 3; i++) {
      await db.insert('resource_generation_attempts', {
        'attempt_id': 'legacy_$i',
        'task_id': taskId,
        'generation_id': 'legacy_gen_$i',
        'part_id': '${setupRef.resourceId}_part_1',
        'attempt_number': 1,
        'status': 'failed',
        'content_length': 0,
        'error_message': 'legacy',
        'created_at': now,
        'updated_at': now,
      });
    }
    await db.update(
      'resource_generation_tasks',
      {'status': PartTaskStatus.ready.storageValue},
      where: 'task_id = ?',
      whereArgs: [taskId],
    );

    final next = await taskRepo.startAttempt(
      taskId: taskId,
      generationId: 'gen_next',
    );

    // The new attempt is the real 4th, and the legacy rows are untouched.
    expect(next.attemptNumber, 4);
    expect(await attemptNumbers(taskId), [1, 1, 1, 4]);
  });

  // ── End-to-end through the retry authority ──────────────────────────────

  test('C/I: retries persist 1 → 2 → 3 and report the same ordinal to callers',
      () async {
    final setupRef = await setup();
    final service = buildService();
    final session = await service.createSession(
      resourceId: setupRef.resourceId,
      blueprintId: setupRef.blueprintId,
      creationSessionId: setupRef.sessionId,
    );
    final partId = '${setupRef.resourceId}_part_1';
    final taskId = await taskIdForPart(setupRef.resourceId, 1);
    failParts.add(partId);

    final reported = <int>[];
    final subscription = service.eventStream.listen((event) {
      if (event is PartStarted) reported.add(event.attemptNumber);
    });

    await service.startGeneration(
      sessionId: session.sessionId,
      maxRetriesPerPart: 0,
    );
    expect(await attemptNumbers(taskId), [1]);
    expect(await attemptStatuses(taskId), ['failed']);

    // First retry still fails; a second attempt row is recorded.
    expect(await service.retryPart(session.sessionId, partId), isFalse);
    expect(await attemptNumbers(taskId), [1, 2]);
    expect(await attemptStatuses(taskId), ['failed', 'failed']);

    // Second retry succeeds.
    failParts.clear();
    expect(await service.retryPart(session.sessionId, partId), isTrue);
    expect(await attemptNumbers(taskId), [1, 2, 3]);
    expect(await attemptStatuses(taskId), ['failed', 'failed', 'completed']);

    // The ordinal handed to the lifecycle callbacks (and therefore to the
    // generation request) follows the same sequence.
    await subscription.cancel();
    expect(reported, [1, 2, 3]);
    service.dispose();
  });

  test('I: the prompt is independent of the attempt number', () {
    PartGenerationRequest request(int attemptNumber) => PartGenerationRequest(
          generationId: 'gen',
          resourceId: const ResourceId('res'),
          sectionId: const SectionId('sec'),
          partId: const PartId('part'),
          attemptId: 'att',
          attemptNumber: attemptNumber,
          targetBudget: 300,
          promptGoal: '写一段正文',
          context: const PartGenerationContext(
            resourceName: '资源',
            resourceType: ResourceType.worldview,
            resourceSummary: '简介',
            sectionTitle: '章节',
            sectionSummary: '章节简介',
            partTitle: '段落',
          ),
        );

    expect(
      PartGenerationPromptBuilder.buildSystemPrompt(request(1)),
      PartGenerationPromptBuilder.buildSystemPrompt(request(3)),
    );
    expect(
      PartGenerationPromptBuilder.buildInstruction(request(1)),
      PartGenerationPromptBuilder.buildInstruction(request(3)),
    );
  });
}
