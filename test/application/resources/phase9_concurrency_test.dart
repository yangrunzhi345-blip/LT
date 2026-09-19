import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/compression_job_repository.dart';
import 'package:lt_dialogue/application/resources/part_content_commit_service.dart';
import 'package:lt_dialogue/application/resources/resource_autosave_repository.dart';
import 'package:lt_dialogue/application/resources/resource_autosave_service.dart';
import 'package:lt_dialogue/application/resources/resource_compression_publisher.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_service.dart';
import 'package:lt_dialogue/application/resources/resource_trash_repository.dart';
import 'package:lt_dialogue/application/resources/resource_trash_service.dart';
import 'package:lt_dialogue/domain/resources/resource_compression.dart';
import 'package:lt_dialogue/domain/resources/resource_autosave.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_protocol.dart';
import 'package:lt_dialogue/domain/resources/resource_revision.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/section_control_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _resourceId = ResourceId('res_conc');
const _sectionId = SectionId('res_conc_sec_1');
const _partA = PartId('res_conc_sec_1_part_1');
const _partB = PartId('res_conc_sec_1_part_2');

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
  late ResourceAutosaveRepositoryImpl journalRepository;
  late ResourceAutosaveService autosave;
  late ResourceTrashRepositoryImpl trashRepository;
  late ResourceTrashService trash;
  late CompressionJobRepositoryImpl compressionJobs;
  late CompressionPublisher publisher;

  Future<Database> getDb() => DatabaseService.database;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_phase9_conc_');
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
    journalRepository = ResourceAutosaveRepositoryImpl(getDb: getDb);
    autosave = ResourceAutosaveService(
      journal: journalRepository,
      committer: PartContentCommitService(
        treeBoundary: tree,
        validationBoundary: SectionControlRepositoryImpl(getDb: getDb),
        captureEngine: engine,
        autosaveRepository: journalRepository,
        getDb: getDb,
        taskReset: tasks,
      ),
      treeBoundary: tree,
      getDb: getDb,
      debounce: const Duration(milliseconds: 20),
    );
    trashRepository = ResourceTrashRepositoryImpl(getDb: getDb);
    trash = ResourceTrashService(
      repository: trashRepository,
      treeBoundary: tree,
      captureEngine: engine,
      getDb: getDb,
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
        name: '并发测试资源',
        sections: [
          ResourceTreeSectionDraft(
            id: _sectionId,
            title: '第一章',
            parts: [
              ResourceTreePartDraft(id: _partA, title: '段落一', content: 'A 初始'),
              ResourceTreePartDraft(id: _partB, title: '段落二', content: 'B 初始'),
            ],
          ),
        ],
      ),
    );
    await revisionService.captureRevision(
      _resourceId,
      cause: RevisionCause.migration,
    );
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> seedTask({
    required String taskId,
    required PartId partId,
    String status = 'ready',
    String attemptId = '',
  }) async {
    final db = await getDb();
    await db.insert('resource_generation_tasks', {
      'task_id': taskId,
      'blueprint_id': 'bp_conc',
      'resource_id': _resourceId.value,
      'section_id': _sectionId.value,
      'part_id': partId.value,
      'prompt_goal': '写正文',
      'estimated_length': 800,
      'dependencies_json': '[]',
      'status': status,
      'sort_order': 0,
      'current_attempt_id': attemptId,
      'error_message': '',
      'created_at': '2026-09-17T00:00:00.000',
      'updated_at': '2026-09-17T00:00:00.000',
    });
  }

  /// Records an in-flight attempt, which is what the commit path updates when it
  /// finishes. Without it the commit correctly refuses to report a completion
  /// it cannot attribute to a real attempt.
  Future<void> seedAttempt({
    required String taskId,
    required String attemptId,
    required PartId partId,
  }) async {
    final db = await getDb();
    await db.insert('resource_generation_attempts', {
      'attempt_id': attemptId,
      'task_id': taskId,
      'generation_id': 'gen_conc',
      'part_id': partId.value,
      'attempt_number': 1,
      'status': 'started',
      'content_length': 0,
      'error_message': '',
      'created_at': '2026-09-17T00:00:00.000',
      'updated_at': '2026-09-17T00:00:00.000',
    });
  }

  Future<String?> liveContent(PartId partId) async {
    final parts = await tree.readParts(_sectionId);
    for (final part in parts) {
      if (part.id == partId) return part.content;
    }
    return null;
  }

  Future<String> token(PartId partId) async =>
      (await tree.readNodeState(partId))!.updatedAt;

  Future<void> expectSingleHeadAndConsistentTree() async {
    final db = await getDb();
    final heads = await db.query(
      'resource_revisions',
      where: 'resource_id = ? AND kind = ? AND is_head = 1',
      whereArgs: <Object?>[_resourceId.value, 'latestHead'],
    );
    expect(heads, hasLength(1), reason: 'exactly one head may ever exist');

    // Whatever the interleaving, the head must describe the live tree: a drift
    // would mean a write landed without a recorded revision.
    final head = await revisionService.readState(
      ResourceRevisionId(heads.single['revision_id'].toString()),
    );
    final live = await tree.readLiveState(db, _resourceId);
    for (final entry in live.entries) {
      final recorded = head.nodes[entry.key];
      if (recorded == null) continue;
      expect(
        recorded.content,
        entry.value.content,
        reason: 'revision node ${entry.key} drifted from the live tree',
      );
      expect(
        recorded.sortOrder,
        entry.value.sortOrder,
        reason: 'revision node ${entry.key} order drifted from the live tree',
      );
    }
  }

  group('autosave interleavings', () {
    test('autosave and a generation commit racing on one Part', () async {
      await seedTask(
        taskId: 'task_a',
        partId: _partA,
        status: 'generating',
        attemptId: 'att_a',
      );
      final base = await token(_partA);

      autosave.schedule(
        resourceId: _resourceId,
        partId: _partA,
        content: '用户手改的正文',
        expectedUpdatedAt: base,
      );

      // Real overlap: both writes are started before either is awaited.
      final results = await Future.wait<Object?>([
        autosave.flush().then<Object?>((value) => value),
        tasks
            .commitPartContent(
              response: const PartGenerationResponse(
                protocolVersion: 1,
                generationId: 'gen_conc',
                resourceId: _resourceId,
                sectionId: _sectionId,
                partId: _partA,
                attemptId: 'att_a',
                content: '模型生成的正文',
              ),
              taskId: 'task_a',
              attemptId: 'att_a',
              expectedSourceToken: base,
            )
            .then<Object?>((value) => value)
            .catchError((Object error) => error),
      ]);

      final content = await liveContent(_partA);
      expect(
        content,
        anyOf('用户手改的正文', '模型生成的正文'),
        reason: 'one writer wins; the stored text is never a mix',
      );
      // The autosave side reports its outcome honestly instead of pretending.
      final flush = results.first! as AutosaveFlushResult;
      expect(flush.outcomes, hasLength(1));
      if (!flush.outcomes.single.persisted) {
        expect(
          flush.outcomes.single.status,
          AutosaveWriteStatus.conflict,
          reason: 'a losing autosave must be reported as a conflict',
        );
        expect(
          await journalRepository.countDrafts(_resourceId),
          1,
          reason: 'the losing text must remain recoverable in the journal',
        );
      }
      await expectSingleHeadAndConsistentTree();
      await autosave.dispose();
    });

    test('autosave and a regeneration boundary racing', () async {
      await seedTask(
        taskId: 'task_a',
        partId: _partA,
        status: 'completed',
      );
      final base = await token(_partA);
      autosave.schedule(
        resourceId: _resourceId,
        partId: _partA,
        content: '编辑到一半的正文',
        expectedUpdatedAt: base,
      );

      await Future.wait<Object?>([
        autosave.flush().then<Object?>((value) => value),
        revisionService.beginLossyOperation(
          _resourceId,
          cause: RevisionCause.regeneration,
          partIds: <String>[_partA.value],
        ).then<Object?>((value) => value),
      ]);

      // The pre-operation content is reachable no matter which side landed
      // first, because the boundary captured whatever was there.
      final history = await revisionService.history(_resourceId);
      final states = <String>[];
      for (final revision in history) {
        final state = await revisionService.readState(revision.revisionId);
        states.add(
          state.nodes[_partA.value]?.content ?? '',
        );
      }
      expect(states, contains('A 初始'));
      await expectSingleHeadAndConsistentTree();
      await autosave.dispose();
    });

    test('deleting a Part while its autosave flush is in flight', () async {
      final base = await token(_partA);
      autosave.schedule(
        resourceId: _resourceId,
        partId: _partA,
        content: '删除前正在编辑的正文',
        expectedUpdatedAt: base,
      );

      final results = await Future.wait<Object?>([
        autosave.flush().then<Object?>((value) => value),
        trash
            .deleteNode(id: _partA, expectedUpdatedAt: base)
            .then<Object?>((value) => value)
            .catchError((Object error) => error),
      ]);

      final flush = results.first! as AutosaveFlushResult;
      final deleteOutcome = results.last;
      // Either the delete won (the flush is then a conflict or a missing target)
      // or the flush won (the delete is then a conflict). Never a lost write
      // reported as success.
      if (deleteOutcome is! TrashDeleteResult) {
        expect(flush.outcomes.single.persisted, isFalse);
      }
      final content = await liveContent(_partA);
      if (content == null) {
        expect(
          (await trash.list()).map((entry) => entry.nodeId),
          contains(_partA.value),
          reason: 'a deleted Part must be in the bin, not simply gone',
        );
      }
      await expectSingleHeadAndConsistentTree();
      await autosave.dispose();
    });
  });

  group('revision interleavings', () {
    test('two restores of the same revision in flight together', () async {
      final target = (await revisionService.latestHead(_resourceId))!;
      await tree.updatePart(
        id: _partA,
        expectedUpdatedAt: await token(_partA),
        content: '恢复前的最新正文',
      );
      await revisionService.captureRevision(
        _resourceId,
        cause: RevisionCause.manualSave,
      );

      final outcomes = await Future.wait<Object?>([
        revisionService
            .restoreRevision(target.revisionId)
            .then<Object?>((value) => value)
            .catchError((Object error) => error),
        revisionService
            .restoreRevision(target.revisionId)
            .then<Object?>((value) => value)
            .catchError((Object error) => error),
      ]);

      // At least one restore succeeded and neither corrupted the tree.
      expect(
        outcomes.whereType<RevisionRestoreResult>(),
        isNotEmpty,
      );
      expect(await liveContent(_partA), 'A 初始');
      await expectSingleHeadAndConsistentTree();

      // A third, sequential restore is a clean idempotent repeat.
      final third = await revisionService.restoreRevision(target.revisionId);
      expect(third.alreadyAtRevision, isTrue);
      expect(await liveContent(_partA), 'A 初始');
    });

    test('cleanup racing a restore loses no recoverable content', () async {
      final deleted = await trash.deleteNode(
        id: _partB,
        expectedUpdatedAt: await token(_partB),
      );
      final aggressive = ResourceRevisionService(
        revisionRepository: revisions,
        captureEngine: engine,
        treeBoundary: tree,
        getDb: getDb,
        retention: Duration.zero,
        taskReset: tasks,
      );
      await aggressive.captureRevision(
        _resourceId,
        cause: RevisionCause.manualSave,
      );

      await Future.wait<Object?>([
        aggressive.pruneRevisions(resourceId: _resourceId).then<Object?>(
              (value) => value,
            ),
        trash
            .restore(deleted.entry.trashId)
            .then<Object?>((value) => value)
            .catchError((Object error) => error),
      ]);

      // The bin entry is either restored or still actionable; the body is never
      // silently dropped.
      final content = await liveContent(_partB);
      final entries = await trash.list();
      expect(
        content != null || entries.any((entry) => entry.nodeId == _partB.value),
        isTrue,
        reason: 'a concurrent cleanup must not make the content unrecoverable',
      );
      await expectSingleHeadAndConsistentTree();
    });

    test('a stale head write is rejected instead of overwriting', () async {
      final head = (await revisionService.latestHead(_resourceId))!;
      await tree.updatePart(
        id: _partA,
        expectedUpdatedAt: await token(_partA),
        content: '更晚的编辑',
      );
      await revisionService.captureRevision(
        _resourceId,
        cause: RevisionCause.manualSave,
      );
      final resourceToken = (await tree.readNodeState(_resourceId))!.updatedAt;

      // A restore based on a token that another writer already moved must fail.
      await tree.updateResource(
        id: _resourceId,
        expectedUpdatedAt: resourceToken,
        summary: '并发写入的摘要',
      );

      await expectLater(
        revisionService.restoreRevision(
          head.revisionId,
          expectedUpdatedAt: resourceToken,
        ),
        throwsA(isA<ResourceRevisionConflictException>()),
      );

      expect(await liveContent(_partA), '更晚的编辑');
      await expectSingleHeadAndConsistentTree();
    });

    test('a compression publish racing a revision capture', () async {
      await seedTask(taskId: 'task_a', partId: _partA, status: 'completed');
      await compressionJobs.insertJob(CompressionJob(
        jobId: 'job_conc',
        resourceId: _resourceId,
        scope: CompressionScope.part,
        targetNodeId: _partA.value,
        // R02-B: the candidate is bound to the live Part version, so the publish
        // CAS can tell whether the Part moved on.
        sourceToken: await token(_partA),
        status: CompressionJobStatus.succeeded,
        attempts: 1,
        maxAttempts: 2,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ));
      await compressionJobs.insertCandidate(CompressionCandidate(
        candidateId: 'cand_conc',
        jobId: 'job_conc',
        resourceId: _resourceId,
        scope: CompressionScope.part,
        targetNodeId: _partA.value,
        originalCharacters: 'A 初始'.length,
        compressedCharacters: 3,
        compressedContent: '压缩后',
        retention: const CompressionRetention(),
        isValidated: true,
        createdAt: DateTime(2026),
      ));

      await Future.wait<Object?>([
        publisher
            .publish('cand_conc')
            .then<Object?>((value) => value)
            .catchError((Object error) => error),
        revisionService
            .captureRevision(_resourceId, cause: RevisionCause.manualSave)
            .then<Object?>((value) => value),
      ]);

      final db = await getDb();
      final candidate = (await db.query(
        'resource_compression_candidates',
        where: 'candidate_id = ?',
        whereArgs: <Object?>['cand_conc'],
      ))
          .single;
      expect(
        candidate['applied_at'],
        isNotNull,
        reason: 'a published candidate is marked exactly once',
      );
      await expectSingleHeadAndConsistentTree();
    });
  });

  group('terminating boundaries', () {
    test('leaving the editor with an armed debounce still saves', () async {
      final base = await token(_partA);
      autosave.schedule(
        resourceId: _resourceId,
        partId: _partA,
        content: '离开瞬间的正文',
        expectedUpdatedAt: base,
      );

      // No delay: the debounce timer is still armed when the editor closes.
      await autosave.dispose();

      expect(await liveContent(_partA), '离开瞬间的正文');
      await expectSingleHeadAndConsistentTree();
    });

    test('cancelling a run keeps what was already committed', () async {
      await seedTask(
        taskId: 'task_a',
        partId: _partA,
        status: 'generating',
        attemptId: 'att_a',
      );
      await seedTask(taskId: 'task_b', partId: _partB, status: 'ready');
      await seedAttempt(taskId: 'task_a', attemptId: 'att_a', partId: _partA);

      await tasks.commitPartContent(
        response: const PartGenerationResponse(
          protocolVersion: 1,
          generationId: 'gen_conc',
          resourceId: _resourceId,
          sectionId: _sectionId,
          partId: _partA,
          attemptId: 'att_a',
          content: '已确认的正文',
        ),
        taskId: 'task_a',
        attemptId: 'att_a',
        expectedSourceToken: await token(_partA),
      );
      await tasks.cancelTasks(resourceId: _resourceId.value);

      expect(
        await liveContent(_partA),
        '已确认的正文',
        reason: 'cancelling the run must not undo committed content',
      );
      final db = await getDb();
      final taskB = (await db.query(
        'resource_generation_tasks',
        where: 'task_id = ?',
        whereArgs: <Object?>['task_b'],
      ))
          .single;
      expect(taskB['status'], 'cancelled');
      expect(await liveContent(_partB), 'B 初始');
      await expectSingleHeadAndConsistentTree();
    });

    test('a generation error keeps what was already committed', () async {
      await seedTask(
        taskId: 'task_a',
        partId: _partA,
        status: 'generating',
        attemptId: 'att_a',
      );
      await seedTask(
        taskId: 'task_b',
        partId: _partB,
        status: 'generating',
        attemptId: 'att_b',
      );
      await seedAttempt(taskId: 'task_a', attemptId: 'att_a', partId: _partA);
      await seedAttempt(taskId: 'task_b', attemptId: 'att_b', partId: _partB);

      await tasks.commitPartContent(
        response: const PartGenerationResponse(
          protocolVersion: 1,
          generationId: 'gen_conc',
          resourceId: _resourceId,
          sectionId: _sectionId,
          partId: _partA,
          attemptId: 'att_a',
          content: '第一个成功的段落',
        ),
        taskId: 'task_a',
        attemptId: 'att_a',
        expectedSourceToken: await token(_partA),
      );
      await tasks.recordFailedAttempt(
        taskId: 'task_b',
        attemptId: 'att_b',
        errorMessage: '网络中断',
      );

      expect(await liveContent(_partA), '第一个成功的段落');
      final db = await getDb();
      final taskB = (await db.query(
        'resource_generation_tasks',
        where: 'task_id = ?',
        whereArgs: <Object?>['task_b'],
      ))
          .single;
      expect(taskB['status'], 'failed');
      expect(
        await liveContent(_partB),
        'B 初始',
        reason: 'a failed attempt must not leave partial text behind',
      );
      await expectSingleHeadAndConsistentTree();
    });

    test('a crash leaves a recoverable draft and no fake completion', () async {
      await seedTask(
        taskId: 'task_b',
        partId: _partB,
        status: 'generating',
        attemptId: 'att_b',
      );
      final base = await token(_partB);
      // The draft is written, then the process dies before the tree write.
      await journalRepository.upsertDraftInTransaction(
        await getDb(),
        resourceId: _resourceId,
        partId: _partB,
        content: '崩溃前未保存的正文',
        baseUpdatedAt: base,
        now: DateTime.now().toIso8601String(),
      );
      await tasks
          .recoverInterruptedTasks(_resourceId.value)
          .catchError((Object _) => 0);

      final outcomes = await autosave.reconcilePendingDrafts(
        resourceId: _resourceId,
      );

      expect(outcomes, hasLength(1));
      expect(
        outcomes.single.disposition,
        AutosaveRecoveryDisposition.needsUserDecision,
      );
      final db = await getDb();
      final task = (await db.query(
        'resource_generation_tasks',
        where: 'task_id = ?',
        whereArgs: <Object?>['task_b'],
      ))
          .single;
      expect(
        task['status'],
        isNot('completed'),
        reason: 'an unconfirmed chunk must never come back as completed',
      );
      expect(await liveContent(_partB), 'B 初始');
      await autosave.dispose();
    });
  });
}
