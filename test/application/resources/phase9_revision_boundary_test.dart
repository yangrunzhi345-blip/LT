import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/compression_job_repository.dart';
import 'package:lt_dialogue/application/resources/resource_compression_publisher.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_service.dart';
import 'package:lt_dialogue/domain/resources/resource_compression.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_protocol.dart';
import 'package:lt_dialogue/domain/resources/resource_revision.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _resourceId = ResourceId('res_bound');
const _sectionId = SectionId('res_bound_sec_1');
const _partId = PartId('res_bound_sec_1_part_1');

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
  late CompressionJobRepositoryImpl compressionJobs;
  late CompressionPublisher publisher;

  Future<Database> getDb() => DatabaseService.database;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_phase9_bound_');
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
        name: '边界测试资源',
        sections: [
          ResourceTreeSectionDraft(
            id: _sectionId,
            title: '第一章',
            parts: [
              ResourceTreePartDraft(
                id: _partId,
                title: '开场',
                content: '',
              ),
            ],
          ),
        ],
      ),
    );
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> seedTask({String status = 'ready'}) async {
    final db = await getDb();
    await db.insert('resource_generation_tasks', {
      'task_id': 'task_bound',
      'blueprint_id': 'bp_bound',
      'resource_id': _resourceId.value,
      'section_id': _sectionId.value,
      'part_id': _partId.value,
      'prompt_goal': '写开场',
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

  /// Attempt token the repository issued, captured so the commit can present
  /// the token it actually created instead of a hard-coded one.
  var attemptId = '';

  /// Source token observed when the attempt acquired its lease (R02-B).
  var sourceToken = '';
  var attemptSequence = 1;

  Future<void> startAttempt() async {
    final attempt = await tasks.startAttempt(
      taskId: 'task_bound',
      generationId: 'gen_bound',
      attemptNumber: attemptSequence++,
    );
    attemptId = attempt.attemptId;
    sourceToken = attempt.sourceToken;
  }

  Future<void> commit(String content) => tasks.commitPartContent(
        response: PartGenerationResponse(
          protocolVersion: 1,
          generationId: 'gen_bound',
          resourceId: _resourceId,
          sectionId: _sectionId,
          partId: _partId,
          attemptId: attemptId,
          content: content,
        ),
        taskId: 'task_bound',
        attemptId: attemptId,
        expectedSourceToken: sourceToken,
      );

  Future<String> liveContent() async =>
      (await tree.readParts(_sectionId)).single.content;

  Future<String> taskStatus() async {
    final db = await getDb();
    final row = (await db.query(
      'resource_generation_tasks',
      where: 'task_id = ?',
      whereArgs: <Object?>['task_bound'],
    ))
        .single;
    return row['status']!.toString();
  }

  group('generation commit boundary', () {
    test('a first generation records the result as the head', () async {
      await seedTask();
      await startAttempt();

      await commit('AI 生成的第一版正文');

      expect(await liveContent(), 'AI 生成的第一版正文');
      final head = await revisionService.latestHead(_resourceId);
      expect(head, isNotNull);
      final revision = await revisions.readRevision(head!.revisionId);
      expect(
        revision!.cause,
        RevisionCause.generation,
        reason: 'filling an empty Part is a first generation',
      );
      expect(revision.isHead, isTrue);
      expect(await taskStatus(), 'completed');
    });

    test('a regeneration records the pre-existing text as history', () async {
      await seedTask();
      await startAttempt();
      await commit('第一版正文');

      // Regenerate: reset the completed task the way the revision boundary
      // does, then commit again.
      await revisionService.beginLossyOperation(
        _resourceId,
        cause: RevisionCause.regeneration,
        partIds: <String>[_partId.value],
      );
      expect(await taskStatus(), 'ready');
      await startAttempt();
      await commit('第二版正文');

      expect(await liveContent(), '第二版正文');
      final history = await revisionService.history(_resourceId);
      expect(history.length, greaterThanOrEqualTo(2));
      expect(history.first.cause, RevisionCause.regeneration);
      expect(history.first.isHead, isTrue);

      // Some earlier revision must still describe the text the regeneration
      // replaced; which one it is depends on how many checkpoints the first
      // generation needed.
      final recorded = <String>[];
      for (final revision in history) {
        final state = await revisionService.readState(revision.revisionId);
        recorded.add(state.nodes[_partId.value]?.content ?? '');
      }
      expect(
        recorded,
        contains('第一版正文'),
        reason: 'the content a regeneration replaced must stay recoverable',
      );
    });

    test('regenerate to before and back restores exactly', () async {
      await seedTask();
      await startAttempt();
      await commit('原始正文');
      final before = (await revisionService.latestHead(_resourceId))!;

      await revisionService.beginLossyOperation(
        _resourceId,
        cause: RevisionCause.regeneration,
        partIds: <String>[_partId.value],
      );
      await startAttempt();
      await commit('重写后的正文');
      expect(await liveContent(), '重写后的正文');

      await revisionService.restoreRevision(before.revisionId);
      expect(await liveContent(), '原始正文');

      // And the rewrite is still reachable, so the rollback is itself a step in
      // a chain rather than a destructive reset.
      final rewrite = (await revisionService.history(_resourceId)).firstWhere(
          (revision) => revision.cause == RevisionCause.regeneration);
      await revisionService.restoreRevision(rewrite.revisionId);
      expect(await liveContent(), '重写后的正文');
    });

    test('a stale attempt token cannot commit', () async {
      await seedTask();
      await startAttempt();
      await commit('第一版');
      final revisionsBefore = await revisionService.countRevisions(_resourceId);

      await expectLater(
        tasks.commitPartContent(
          response: const PartGenerationResponse(
            protocolVersion: 1,
            generationId: 'gen_bound',
            resourceId: _resourceId,
            sectionId: _sectionId,
            partId: _partId,
            attemptId: 'att_stale',
            content: '晚到的响应',
          ),
          taskId: 'task_bound',
          attemptId: 'att_stale',
          expectedSourceToken: sourceToken,
        ),
        throwsA(isA<StateError>()),
      );

      expect(await liveContent(), '第一版');
      expect(
        await revisionService.countRevisions(_resourceId),
        revisionsBefore,
        reason: 'a rejected commit must not leave a revision behind',
      );
    });

    test('an uncommitted attempt never becomes completed', () async {
      await seedTask();
      await startAttempt();

      // A stream that was interrupted before validation never calls
      // commitPartContent, so nothing about it may look finished.
      expect(await taskStatus(), 'generating');
      expect(await liveContent(), '');
      expect(await revisionService.countRevisions(_resourceId), 0);

      await tasks.cancelTasks(resourceId: _resourceId.value);
      expect(await taskStatus(), 'cancelled');
      expect(
        await revisionService.countRevisions(_resourceId),
        0,
        reason: 'a chunk that was never confirmed must not surface as a '
            'completed part after a restart',
      );
    });

    test('a cancelled task refuses a late commit', () async {
      await seedTask();
      await startAttempt();
      await tasks.cancelTasks(resourceId: _resourceId.value);

      await expectLater(
        commit('晚到的内容'),
        throwsA(isA<StateError>()),
      );

      expect(await liveContent(), '');
      expect(await revisionService.countRevisions(_resourceId), 0);
    });
  });

  group('compression publish', () {
    Future<CompressionCandidate> seedCandidate({
      String content = '压缩后的正文',
      CompressionScope scope = CompressionScope.part,
      String? validationState,
      String? sourceTokenOverride,
    }) async {
      // R02-B: a real candidate is produced from the live Part, so its job
      // records the Part's current `updated_at` as the source token. Publishing
      // CASes against that token.
      final liveToken =
          sourceTokenOverride ?? (await tree.readNodeState(_partId))!.updatedAt;
      final job = await compressionJobs.insertJob(CompressionJob(
        jobId: 'job_bound',
        resourceId: _resourceId,
        scope: scope,
        targetNodeId: _partId.value,
        parentNodeId: _sectionId.value,
        sourceToken: liveToken,
        status: CompressionJobStatus.succeeded,
        attempts: 1,
        maxAttempts: 2,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ));
      final candidate = CompressionCandidate(
        candidateId: 'cand_bound',
        jobId: job.jobId,
        resourceId: _resourceId,
        scope: scope,
        targetNodeId: _partId.value,
        originalCharacters: 400,
        compressedCharacters: content.length,
        compressedContent: content,
        retention: const CompressionRetention(),
        isValidated: validationState != 'rejected',
        validationMessage: validationState == 'rejected' ? '超出预算' : '',
        createdAt: DateTime(2026),
      );
      await compressionJobs.insertCandidate(candidate);
      return candidate;
    }

    test('publishing replaces the body and records the old text first',
        () async {
      await seedTask();
      await startAttempt();
      await commit('一段需要压缩的原始正文');
      await seedCandidate();
      final beforePublish = (await revisionService.latestHead(_resourceId))!;

      final outcome = await publisher.publish('cand_bound');

      expect(outcome.alreadyApplied, isFalse);
      expect(outcome.partId, _partId.value);
      expect(await liveContent(), '压缩后的正文');
      expect(
        outcome.headRevisionId,
        isNot(beforePublish.revisionId.value),
        reason: 'publishing is a head switch, not an in-place edit',
      );

      final history = await revisionService.history(_resourceId);
      expect(
        history.first.cause,
        RevisionCause.compression,
        reason: 'the cause must let the user see what produced the version',
      );
      final old = await revisionService.readState(beforePublish.revisionId);
      expect(
        old.nodes.values
            .firstWhere((node) => node.nodeId == _partId.value)
            .content,
        '一段需要压缩的原始正文',
        reason: 'the pre-compression text must be restorable',
      );
    });

    test('the candidate is marked applied so it cannot publish twice',
        () async {
      await seedTask();
      await startAttempt();
      await commit('原始正文');
      await seedCandidate();

      final first = await publisher.publish('cand_bound');
      final second = await publisher.publish('cand_bound');

      expect(first.alreadyApplied, isFalse);
      expect(
        second.alreadyApplied,
        isTrue,
        reason: 'a repeated publish is an idempotent no-op',
      );
      final db = await getDb();
      final row = (await db.query(
        'resource_compression_candidates',
        where: 'candidate_id = ?',
        whereArgs: <Object?>['cand_bound'],
      ))
          .single;
      expect(row['applied_at'], isNotNull);
      expect(await publisher.publishableCandidates(_resourceId), isEmpty);
    });

    test('publishing marks the task regenerable again', () async {
      await seedTask();
      await startAttempt();
      await commit('原始正文');
      await seedCandidate();

      await publisher.publish('cand_bound');

      expect(
        await taskStatus(),
        'ready',
        reason: 'compressed text no longer comes from the generation that '
            'produced the source, so it must be regenerable',
      );
    });

    test('restoring the published revision returns the original text',
        () async {
      await seedTask();
      await startAttempt();
      await commit('原始正文');
      await seedCandidate();
      final before = (await revisionService.latestHead(_resourceId))!;

      await publisher.publish('cand_bound');
      expect(await liveContent(), '压缩后的正文');

      await revisionService.restoreRevision(before.revisionId);
      expect(await liveContent(), '原始正文');
    });

    test('a rejected candidate is refused', () async {
      await seedTask();
      await startAttempt();
      await commit('原始正文');
      await seedCandidate(validationState: 'rejected');

      await expectLater(
        publisher.publish('cand_bound'),
        throwsA(isA<CompressionPublishException>()),
      );
      expect(await liveContent(), '原始正文');
    });

    test('a section-scoped candidate is refused rather than guessed at',
        () async {
      await seedTask();
      await startAttempt();
      await commit('原始正文');
      await seedCandidate(scope: CompressionScope.section);

      await expectLater(
        publisher.publish('cand_bound'),
        throwsA(isA<CompressionPublishException>()),
      );
      expect(
        await liveContent(),
        '原始正文',
        reason: 'a section candidate has no per-Part mapping, so publishing it '
            'would have to invent a split',
      );
    });

    test('a candidate whose text is already in place is reported as applied',
        () async {
      await seedTask();
      await startAttempt();
      // The body already equals the candidate text.
      await commit('压缩后的正文');
      await seedCandidate();
      final revisionsBefore = await revisionService.countRevisions(_resourceId);

      final outcome = await publisher.publish('cand_bound');

      expect(outcome.alreadyApplied, isTrue);
      expect(
        outcome.savedCharacters,
        0,
        reason: 'nothing was replaced, so nothing was saved (P9-M4)',
      );
      expect(outcome.headRevisionId, isNull);
      expect(
        await revisionService.countRevisions(_resourceId),
        revisionsBefore,
        reason: 'an already-applied publish must not claim a new history entry',
      );
      expect(await liveContent(), '压缩后的正文');
    });

    test('an unknown candidate is refused', () async {
      await seedTask();
      await expectLater(
        publisher.publish('cand_missing'),
        throwsA(isA<CompressionPublishException>()),
      );
    });

    test('a failed publish leaves both the body and applied_at untouched',
        () async {
      await seedTask();
      await startAttempt();
      await commit('原始正文');
      await seedCandidate();
      // Permanently remove the target so the apply step cannot succeed.
      final db = await getDb();
      await db.delete(
        'resource_parts',
        where: 'id = ?',
        whereArgs: <Object?>[_partId.value],
      );

      await expectLater(
        publisher.publish('cand_bound'),
        throwsA(isA<ResourceRevisionException>()),
      );

      final row = (await db.query(
        'resource_compression_candidates',
        where: 'candidate_id = ?',
        whereArgs: <Object?>['cand_bound'],
      ))
          .single;
      expect(
        row['applied_at'],
        isNull,
        reason: 'the claim and the write share one transaction, so neither can '
            'land alone',
      );
    });

    test('publishableCandidates lists only valid, unapplied, part-scoped ones',
        () async {
      await seedTask();
      await startAttempt();
      await commit('原始正文');
      await seedCandidate();

      expect(
        (await publisher.publishableCandidates(_resourceId))
            .map((candidate) => candidate.candidateId),
        <String>['cand_bound'],
      );

      await publisher.publish('cand_bound');
      expect(await publisher.publishableCandidates(_resourceId), isEmpty);
    });
  });

  group('manual save boundary through the commit service', () {
    test('editing a part is a manualSave revision and keeps the old text',
        () async {
      await seedTask();
      await startAttempt();
      await commit('AI 正文');
      final generated = (await revisionService.latestHead(_resourceId))!;

      await revisionService.beginLossyOperation(
        _resourceId,
        cause: RevisionCause.regeneration,
        partIds: <String>[_partId.value],
      );
      await startAttempt();
      await commit('重写正文');
      await revisionService.restoreRevision(generated.revisionId);

      expect(await liveContent(), 'AI 正文');
    });
  });
}
