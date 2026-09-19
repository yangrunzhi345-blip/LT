import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/compression_job_repository.dart';
import 'package:lt_dialogue/application/resources/part_content_commit_service.dart';
import 'package:lt_dialogue/application/resources/part_generation_coordinator.dart';
import 'package:lt_dialogue/application/resources/resource_autosave_repository.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_compression_publisher.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_service.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_compression.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_protocol.dart';
import 'package:lt_dialogue/domain/resources/resource_revision.dart';
import 'package:lt_dialogue/models/llm_task.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/section_control_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// R02-B — the unified `resource_parts.content` source CAS.
///
/// Every writer that replaces Part body text must present the version it
/// observed and be rejected when the Part moved on. These tests use a real
/// SQLite database so the CAS is an actual transaction predicate, not a mock
/// assertion, and the interleavings are driven by awaiting real futures in a
/// fixed order.

const _resourceId = ResourceId('res_r02b');
const _sectionId = SectionId('res_r02b_sec_1');
const _partId = PartId('res_r02b_sec_1_part_1');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late ResourceTreeRepositoryImpl tree;
  late ResourceRevisionRepositoryImpl revisions;
  late RevisionCaptureEngine engine;
  late PartGenerationTaskRepositoryImpl tasks;
  late ResourceRevisionService revisionService;
  late PartContentCommitService commitService;
  late SectionControlRepositoryImpl sections;
  late CompressionJobRepositoryImpl compressionJobs;
  late CompressionPublisher publisher;

  Future<Database> getDb() => DatabaseService.database;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_r02b_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();

    tree = ResourceTreeRepositoryImpl(getDb: getDb);
    revisions = ResourceRevisionRepositoryImpl(getDb: getDb);
    engine = RevisionCaptureEngine(
      revisionRepository: revisions,
      treeBoundary: tree,
    );
    tasks = PartGenerationTaskRepositoryImpl(
      getDb: getDb,
      revisionBoundary: engine,
    );
    revisionService = ResourceRevisionService(
      revisionRepository: revisions,
      captureEngine: engine,
      treeBoundary: tree,
      getDb: getDb,
      taskReset: tasks,
    );
    sections = SectionControlRepositoryImpl(getDb: getDb);
    commitService = PartContentCommitService(
      treeBoundary: tree,
      validationBoundary: sections,
      captureEngine: engine,
      autosaveRepository: ResourceAutosaveRepositoryImpl(getDb: getDb),
      getDb: getDb,
      taskReset: tasks,
    );
    compressionJobs = CompressionJobRepositoryImpl(getDb: getDb);
    publisher = CompressionPublisher(
      jobRepository: compressionJobs,
      revisionService: revisionService,
      getDb: getDb,
    );

    await tree.createResourceTree(
      const ResourceTreeDraft(
        id: _resourceId,
        type: ResourceType.worldview,
        name: '源版本测试资源',
        sections: [
          ResourceTreeSectionDraft(
            id: _sectionId,
            title: '第一章',
            parts: [
              ResourceTreePartDraft(id: _partId, title: '段落一', content: '初始正文'),
            ],
          ),
        ],
      ),
    );
    await revisionService.captureRevision(_resourceId,
        cause: RevisionCause.migration);
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<String> liveContent() async =>
      (await tree.readParts(_sectionId)).single.content;

  Future<String> partToken() async =>
      (await tree.readNodeState(_partId))!.updatedAt;

  Future<void> seedTask({
    String taskId = 'task_r02b',
    String status = 'ready',
  }) async {
    final db = await getDb();
    await db.insert('resource_generation_tasks', {
      'task_id': taskId,
      'blueprint_id': 'bp_r02b',
      'resource_id': _resourceId.value,
      'section_id': _sectionId.value,
      'part_id': _partId.value,
      'prompt_goal': '写正文',
      'estimated_length': 800,
      'dependencies_json': '[]',
      'status': status,
      'sort_order': 0,
      'current_attempt_id': '',
      'error_message': '',
      'created_at': '2026-09-17T00:00:00.000',
      'updated_at': '2026-09-17T00:00:00.000',
    });
  }

  Future<String> taskStatus(String taskId) async {
    final t = await tasks.findTask(taskId);
    return t!.status;
  }

  Future<void> manualEdit(String content, {required String token}) =>
      commitService.applyContent(PartContentCommitRequest(
        partId: _partId,
        expectedUpdatedAt: token,
        content: content,
      ));

  PartGenerationResponse generationResponse(String content, String attemptId) =>
      PartGenerationResponse(
        protocolVersion: 1,
        generationId: 'gen_r02b',
        resourceId: _resourceId,
        sectionId: _sectionId,
        partId: _partId,
        attemptId: attemptId,
        content: content,
      );

  group('R02-B generation source CAS', () {
    test('B1 a manual edit during generation is never overwritten', () async {
      await seedTask();
      final attempt = await tasks.startAttempt(
        taskId: 'task_r02b',
        generationId: 'gen_r02b',
        attemptNumber: 1,
      );
      final t0 = attempt.sourceToken;
      expect(t0, isNotEmpty);

      // The user edits the Part while the model is still working.
      await manualEdit('用户手改的正文', token: t0);
      final t1 = await partToken();
      expect(t1, isNot(t0));

      await expectLater(
        tasks.commitPartContent(
          response: generationResponse('模型生成的正文', attempt.attemptId),
          taskId: 'task_r02b',
          attemptId: attempt.attemptId,
          expectedSourceToken: t0,
        ),
        throwsA(isA<ResourceTreeConflictException>()),
      );

      expect(await liveContent(), '用户手改的正文',
          reason: 'the stale generation must not overwrite the user edit');
      expect(await partToken(), t1);
      expect(await taskStatus('task_r02b'), isNot('completed'),
          reason: 'a conflicted generation is not a success');
    });

    test(
        'B2 an unchanged Part lets the generation commit and advances the token',
        () async {
      await seedTask();
      final attempt = await tasks.startAttempt(
        taskId: 'task_r02b',
        generationId: 'gen_r02b',
        attemptNumber: 1,
      );

      await tasks.commitPartContent(
        response: generationResponse('模型生成的正文', attempt.attemptId),
        taskId: 'task_r02b',
        attemptId: attempt.attemptId,
        expectedSourceToken: attempt.sourceToken,
      );

      expect(await liveContent(), '模型生成的正文');
      expect(await partToken(), isNot(attempt.sourceToken));
      expect(await taskStatus('task_r02b'), 'completed');
    });

    test('B3 a superseded attempt cannot commit even with the right token',
        () async {
      await seedTask();
      final first = await tasks.startAttempt(
        taskId: 'task_r02b',
        generationId: 'gen_r02b',
        attemptNumber: 1,
      );
      await tasks.recordFailedAttempt(
        taskId: 'task_r02b',
        attemptId: first.attemptId,
        errorMessage: 'superseded',
      );
      await tasks.markTaskReady('task_r02b');
      final second = await tasks.startAttempt(
        taskId: 'task_r02b',
        generationId: 'gen_r02b',
        attemptNumber: 2,
      );
      expect(second.sourceToken, first.sourceToken, reason: 'Part unchanged');

      await expectLater(
        tasks.commitPartContent(
          response: generationResponse('旧尝试的正文', first.attemptId),
          taskId: 'task_r02b',
          attemptId: first.attemptId,
          expectedSourceToken: first.sourceToken,
        ),
        throwsA(isA<StateError>()),
      );

      await tasks.commitPartContent(
        response: generationResponse('新尝试的正文', second.attemptId),
        taskId: 'task_r02b',
        attemptId: second.attemptId,
        expectedSourceToken: second.sourceToken,
      );
      expect(await liveContent(), '新尝试的正文');
    });

    test('B4 a cancelled attempt cannot commit even when the token matches',
        () async {
      await seedTask();
      final attempt = await tasks.startAttempt(
        taskId: 'task_r02b',
        generationId: 'gen_r02b',
        attemptNumber: 1,
      );
      await tasks.cancelTasks(resourceId: _resourceId.value);

      await expectLater(
        tasks.commitPartContent(
          response: generationResponse('晚到的正文', attempt.attemptId),
          taskId: 'task_r02b',
          attemptId: attempt.attemptId,
          expectedSourceToken: attempt.sourceToken,
        ),
        throwsA(isA<StateError>()),
      );
      expect(await liveContent(), '初始正文');
    });

    test('B9/B10 a rejected commit leaves no revision head or section state',
        () async {
      await seedTask();
      final attempt = await tasks.startAttempt(
        taskId: 'task_r02b',
        generationId: 'gen_r02b',
        attemptNumber: 1,
      );
      await manualEdit('用户手改的正文', token: attempt.sourceToken);

      final revisionsBefore = await revisionService.countRevisions(_resourceId);
      final headBefore = await revisionService.latestHead(_resourceId);
      final sectionBefore = (await sections.findSectionControlRow(_sectionId))!;
      final tokenBefore = await partToken();

      await expectLater(
        tasks.commitPartContent(
          response: generationResponse('模型生成的正文', attempt.attemptId),
          taskId: 'task_r02b',
          attemptId: attempt.attemptId,
          expectedSourceToken: attempt.sourceToken,
        ),
        throwsA(isA<ResourceTreeConflictException>()),
      );

      expect(await revisionService.countRevisions(_resourceId), revisionsBefore,
          reason: 'a refused commit must not create a revision');
      expect(
        (await revisionService.latestHead(_resourceId))!.revisionId.value,
        headBefore!.revisionId.value,
      );
      final sectionAfter = (await sections.findSectionControlRow(_sectionId))!;
      expect(sectionAfter.updatedAt, sectionBefore.updatedAt,
          reason: 'a refused commit must not move the section token');
      expect(sectionAfter.validationState, sectionBefore.validationState);
      expect(await partToken(), tokenBefore);
    });

    test('B8 the existing manual-edit CAS is still enforced', () async {
      final token = await partToken();
      await manualEdit('第一次手改', token: token);

      await expectLater(
        manualEdit('基于旧令牌的第二次手改', token: token),
        throwsA(isA<ResourceTreeConflictException>()),
      );
      expect(await liveContent(), '第一次手改');
    });
  });

  group('R02-B compression source CAS', () {
    Future<void> seedCandidate({
      String candidateId = 'cand_r02b',
      String content = '压缩后的正文',
      String? sourceTokenOverride,
    }) async {
      final token = sourceTokenOverride ?? await partToken();
      await compressionJobs.insertJob(CompressionJob(
        jobId: 'job_r02b',
        resourceId: _resourceId,
        scope: CompressionScope.part,
        targetNodeId: _partId.value,
        parentNodeId: _sectionId.value,
        sourceToken: token,
        status: CompressionJobStatus.succeeded,
        attempts: 1,
        maxAttempts: 2,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ));
      await compressionJobs.insertCandidate(CompressionCandidate(
        candidateId: candidateId,
        jobId: 'job_r02b',
        resourceId: _resourceId,
        scope: CompressionScope.part,
        targetNodeId: _partId.value,
        originalCharacters: 400,
        compressedCharacters: content.length,
        compressedContent: content,
        retention: const CompressionRetention(),
        isValidated: true,
        createdAt: DateTime(2026),
      ));
    }

    test('B5 a candidate is refused after a manual edit moved the Part',
        () async {
      final token = await partToken();
      await seedCandidate(sourceTokenOverride: token);
      await manualEdit('用户手改的正文', token: token);

      await expectLater(
        publisher.publish('cand_r02b'),
        throwsA(isA<ResourceTreeConflictException>()),
      );

      expect(await liveContent(), '用户手改的正文');
      final db = await getDb();
      final row = (await db.query(
        'resource_compression_candidates',
        where: 'candidate_id = ?',
        whereArgs: <Object?>['cand_r02b'],
      ))
          .single;
      expect(row['applied_at'], isNull,
          reason: 'a stale candidate must not be marked applied');
    });

    test('B6 an unchanged Part publishes and advances the token', () async {
      final token = await partToken();
      await seedCandidate(sourceTokenOverride: token);

      final outcome = await publisher.publish('cand_r02b');

      expect(outcome.alreadyApplied, isFalse);
      expect(await liveContent(), '压缩后的正文');
      expect(await partToken(), isNot(token));
    });

    test('B7 a repeated publish of the same candidate is idempotent', () async {
      await seedCandidate();

      final first = await publisher.publish('cand_r02b');
      final second = await publisher.publish('cand_r02b');

      expect(first.alreadyApplied, isFalse);
      expect(second.alreadyApplied, isTrue);
      expect(await liveContent(), '压缩后的正文');
    });
  });

  group('R02-B coordinator stops on a source conflict', () {
    late ResourceCreationPipeline pipeline;
    late ResourceBlueprintRepositoryImpl blueprintRepo;

    setUp(() {
      pipeline = ResourceCreationPipeline(
        getDb: getDb,
        hasAiCredentials: () => true,
        treeRepository: tree,
      );
      blueprintRepo = ResourceBlueprintRepositoryImpl(
        getDb: getDb,
        treeRepository: tree,
      );
    });

    test(
        'a manual edit during generation keeps the edit and is not auto-retried',
        () async {
      final session = await pipeline.create(ResourceCreationRequest(
        resourceType: ResourceType.worldview,
        method: CreationMethod.aiReference,
        name: '并发编辑资源',
        idempotencyKey: 'idemp_r02b_${DateTime.now().microsecondsSinceEpoch}',
        referenceSource: ReferenceSource.text('参考材料'),
      ));
      final blueprint = ResourceBlueprint(
        blueprintId: 'bp_r02b_coord',
        sessionId: session.sessionId!,
        resourceType: ResourceType.worldview,
        suggestedName: '并发编辑资源',
        summary: '并发编辑资源',
        sections: [
          BlueprintSection(
            id: 'sec_1',
            title: '第一章',
            parts: const [
              BlueprintPart(
                id: 'part_1',
                sectionId: 'sec_1',
                title: '段落一',
                generationGoal: '写正文',
                estimatedLength: 1000,
                dependencies: [],
              ),
            ],
          ),
        ],
      );
      await blueprintRepo.saveBlueprint(blueprint);
      final confirmed = await blueprintRepo.confirmBlueprint(
        blueprintId: blueprint.blueprintId,
      );
      final partId = '${confirmed.resourceId.value}_part_1';
      var completerCalls = 0;

      Future<String> completer({
        required String systemPrompt,
        required String instruction,
        required LlmTask task,
        GenerationTaskHandle? taskHandle,
      }) async {
        completerCalls++;
        final generationMatch =
            RegExp(r'"generation_id": "(.*?)"').firstMatch(systemPrompt);
        final resourceMatch =
            RegExp(r'"resource_id": "(.*?)"').firstMatch(systemPrompt);
        final sectionMatch =
            RegExp(r'"section_id": "(.*?)"').firstMatch(systemPrompt);
        final partMatch =
            RegExp(r'"part_id": "(.*?)"').firstMatch(systemPrompt);
        final attemptMatch =
            RegExp(r'"attempt_id": "(.*?)"').firstMatch(systemPrompt);
        final actualPartId = partMatch!.group(1)!;
        // The user edits the Part while the model is "thinking".
        final token =
            (await tree.readNodeState(PartId(actualPartId)))!.updatedAt;
        await commitService.applyContent(PartContentCommitRequest(
          partId: PartId(actualPartId),
          expectedUpdatedAt: token,
          content: '用户手改的正文',
        ));
        return jsonEncode({
          'protocol_version': 1,
          'generation_id': generationMatch!.group(1)!,
          'resource_id': resourceMatch!.group(1)!,
          'section_id': sectionMatch!.group(1)!,
          'part_id': actualPartId,
          'attempt_id': attemptMatch!.group(1)!,
          'content': '模型生成的正文',
          'status': 'completed',
        });
      }

      final coordinator = PartGenerationCoordinator(
        taskRepository: tasks,
        blueprintRepository: blueprintRepo,
        pipeline: pipeline,
        completer: completer,
      );

      final success = await coordinator.generateAllParts(
        blueprintId: blueprint.blueprintId,
      );

      expect(success, isFalse,
          reason: 'a stale generation must not report success');
      expect(completerCalls, 1,
          reason: 'a source conflict must not be auto-retried over the edit');
      final parts = await tree.readParts(
        SectionId('${confirmed.resourceId.value}_sec_1'),
      );
      expect(parts.single.content, '用户手改的正文');
      final storedTask = await tasks.findTaskByPartId(partId);
      expect(storedTask!.status, 'failed',
          reason: 'the conflicted generation must surface as a failed task');
      expect(storedTask.status, isNot('completed'));
    });
  });
}
