import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/part_generation_coordinator.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/application/resources/streaming_generation_session_repository.dart';
import 'package:lt_dialogue/application/resources/streaming_resource_generation_service.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_protocol.dart';
import 'package:lt_dialogue/models/llm_task.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Builds one valid Part generation response (start / append / complete).
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

  /// Per-run recorder: how often each Part was requested and which Parts fail.
  late Map<String, int> calls;
  late Set<String> failParts;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_retry_failed_');
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
    int partCount = 3,
  }) async {
    final creation = await pipeline.create(ResourceCreationRequest(
      resourceType: ResourceType.worldview,
      method: CreationMethod.aiReference,
      name: '重试失败项测试资源',
      idempotencyKey: 'retry_${DateTime.now().microsecondsSinceEpoch}',
      referenceSource: ReferenceSource.text('重试失败项的参考材料'),
    ));
    final blueprint = ResourceBlueprint(
      blueprintId: 'bp_retry_${DateTime.now().microsecondsSinceEpoch}',
      sessionId: creation.sessionId!,
      resourceType: ResourceType.worldview,
      suggestedName: '重试失败项测试资源',
      summary: '重试失败项',
      sections: [
        BlueprintSection(
          id: 'sec_1',
          title: '第一章',
          parts: [
            // Independent Parts so one failure never blocks the others.
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

  Future<String> partStatus(String partId) async {
    final rows = await db.query(
      'resource_generation_tasks',
      where: 'part_id = ?',
      whereArgs: [partId],
    );
    return rows.single['status'] as String;
  }

  Future<String> partContent(String partId) async =>
      (await taskRepo.getPartsContent([partId]))[partId]?.content ?? '';

  Future<int> attemptCount(String partId) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM resource_generation_attempts a '
      'JOIN resource_generation_tasks t ON t.task_id = a.task_id '
      'WHERE t.part_id = ?',
      [partId],
    );
    return rows.first.values.first as int? ?? 0;
  }

  Future<List<String>> attemptStatuses(String partId) async {
    // Ordered by insertion: a retry records a NEW attempt row while the original
    // failed row is preserved, so the history is never rewritten.
    final rows = await db.rawQuery(
      'SELECT a.status AS status FROM resource_generation_attempts a '
      'JOIN resource_generation_tasks t ON t.task_id = a.task_id '
      'WHERE t.part_id = ? ORDER BY a.rowid ASC',
      [partId],
    );
    return [for (final row in rows) row['status'] as String];
  }

  test('regenerating one failed Part leaves the successful Parts untouched',
      () async {
    final setupRef = await setup(partCount: 3);
    final service = buildService();
    final session = await service.createSession(
      resourceId: setupRef.resourceId,
      blueprintId: setupRef.blueprintId,
      creationSessionId: setupRef.sessionId,
    );
    final part1 = '${setupRef.resourceId}_part_1';
    final part2 = '${setupRef.resourceId}_part_2';
    final part3 = '${setupRef.resourceId}_part_3';
    failParts.add(part2);

    expect(
      await service.startGeneration(
        sessionId: session.sessionId,
        maxRetriesPerPart: 0,
      ),
      isFalse,
    );
    expect(await partStatus(part1), PartTaskStatus.completed.storageValue);
    expect(await partStatus(part2), PartTaskStatus.failed.storageValue);
    expect(await partStatus(part3), PartTaskStatus.completed.storageValue);

    final callsBefore = Map<String, int>.from(calls);
    final content1Before = await partContent(part1);
    final content3Before = await partContent(part3);
    final attempts1Before = await attemptCount(part1);
    final attempts2Before = await attemptCount(part2);
    final attempts3Before = await attemptCount(part3);

    failParts.clear();
    expect(await service.retryPart(session.sessionId, part2), isTrue);

    // Only the failed Part was requested again.
    expect(calls[part1], callsBefore[part1]);
    expect(calls[part3], callsBefore[part3]);
    expect(calls[part2], (callsBefore[part2] ?? 0) + 1);

    expect(await partStatus(part2), PartTaskStatus.completed.storageValue);
    expect(await partContent(part1), content1Before);
    expect(await partContent(part3), content3Before);
    expect((await partContent(part2)).isNotEmpty, isTrue);

    // Successful Parts keep exactly their original attempt.
    expect(await attemptCount(part1), attempts1Before);
    expect(await attemptCount(part3), attempts3Before);
    expect(await attemptCount(part2), attempts2Before + 1);
    service.dispose();
  });

  test('regenerating one failed Part never touches the other failed Part',
      () async {
    final setupRef = await setup(partCount: 4);
    final service = buildService();
    final session = await service.createSession(
      resourceId: setupRef.resourceId,
      blueprintId: setupRef.blueprintId,
      creationSessionId: setupRef.sessionId,
    );
    final part2 = '${setupRef.resourceId}_part_2';
    final part4 = '${setupRef.resourceId}_part_4';
    failParts.addAll([part2, part4]);

    expect(
      await service.startGeneration(
        sessionId: session.sessionId,
        maxRetriesPerPart: 0,
      ),
      isFalse,
    );
    expect(await partStatus(part2), PartTaskStatus.failed.storageValue);
    expect(await partStatus(part4), PartTaskStatus.failed.storageValue);

    final callsBefore = Map<String, int>.from(calls);
    final part4AttemptsBefore = await attemptCount(part4);

    failParts.clear();
    expect(await service.retryPart(session.sessionId, part2), isTrue);

    expect(await partStatus(part2), PartTaskStatus.completed.storageValue);
    // Part 4 keeps its failure and was never requested.
    expect(await partStatus(part4), PartTaskStatus.failed.storageValue);
    expect(calls[part4], callsBefore[part4]);
    expect(await attemptCount(part4), part4AttemptsBefore);
    service.dispose();
  });

  test('a failed retry stays retryable and records a new attempt', () async {
    final setupRef = await setup(partCount: 2);
    final service = buildService();
    final session = await service.createSession(
      resourceId: setupRef.resourceId,
      blueprintId: setupRef.blueprintId,
      creationSessionId: setupRef.sessionId,
    );
    final part2 = '${setupRef.resourceId}_part_2';
    failParts.add(part2);

    await service.startGeneration(
      sessionId: session.sessionId,
      maxRetriesPerPart: 0,
    );
    expect(await partStatus(part2), PartTaskStatus.failed.storageValue);
    final attemptsAfterRun = await attemptCount(part2);

    // Retry while it still fails: the new attempt is recorded, the Part stays
    // failed and remains retryable.
    expect(await service.retryPart(session.sessionId, part2), isFalse);
    expect(await partStatus(part2), PartTaskStatus.failed.storageValue);
    expect(await attemptCount(part2), attemptsAfterRun + 1);

    // Retry again now that it can succeed.
    failParts.clear();
    expect(await service.retryPart(session.sessionId, part2), isTrue);
    expect(await partStatus(part2), PartTaskStatus.completed.storageValue);
    expect(await attemptCount(part2), attemptsAfterRun + 2);
    service.dispose();
  });

  test('a duplicate retry for the same Part is rejected before any new attempt',
      () async {
    final setupRef = await setup(partCount: 2);
    final service = buildService();
    final session = await service.createSession(
      resourceId: setupRef.resourceId,
      blueprintId: setupRef.blueprintId,
      creationSessionId: setupRef.sessionId,
    );
    final part2 = '${setupRef.resourceId}_part_2';
    failParts.add(part2);

    await service.startGeneration(
      sessionId: session.sessionId,
      maxRetriesPerPart: 0,
    );
    final attemptsBefore = await attemptCount(part2);

    failParts.clear();
    final first = service.retryPart(session.sessionId, part2);
    // The in-flight retry is registered synchronously, so a second concurrent
    // trigger is refused instead of creating a second attempt.
    expect(
      () => service.retryPart(session.sessionId, part2),
      throwsA(isA<StateError>()),
    );
    expect(await first, isTrue);

    expect(await attemptCount(part2), attemptsBefore + 1);
    expect(await partStatus(part2), PartTaskStatus.completed.storageValue);
    service.dispose();
  });

  test('a failed attempt is preserved as history beside the new attempt',
      () async {
    final setupRef = await setup(partCount: 2);
    final service = buildService();
    final session = await service.createSession(
      resourceId: setupRef.resourceId,
      blueprintId: setupRef.blueprintId,
      creationSessionId: setupRef.sessionId,
    );
    final part2 = '${setupRef.resourceId}_part_2';
    failParts.add(part2);

    await service.startGeneration(
      sessionId: session.sessionId,
      maxRetriesPerPart: 0,
    );
    expect(await attemptStatuses(part2), ['failed']);

    failParts.clear();
    await service.retryPart(session.sessionId, part2);

    final statuses = await attemptStatuses(part2);
    expect(statuses, ['failed', 'completed'],
        reason: 'the failed attempt is never deleted to fake success');
    service.dispose();
  });
}
