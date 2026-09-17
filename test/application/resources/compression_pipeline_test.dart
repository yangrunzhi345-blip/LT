import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/compression_coordinator.dart';
import 'package:lt_dialogue/application/resources/compression_job_repository.dart';
import 'package:lt_dialogue/application/resources/compression_prompt_builder.dart';
import 'package:lt_dialogue/application/resources/compression_response_parser.dart';
import 'package:lt_dialogue/application/resources/resource_capacity_repository.dart';
import 'package:lt_dialogue/domain/resources/resource_compression.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_limits.dart';
import 'package:lt_dialogue/models/generation_task_handle.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/resource_capacity_fakes.dart';
import '../../helpers/resource_tree_fixtures.dart';

String _compressedJson(
  String content, {
  List<String> entities = const <String>[],
  List<String> relationships = const <String>[],
  List<String> timeline = const <String>[],
}) {
  return jsonEncode({
    'protocol_version': 1,
    'compressed_content': content,
    'retained': {
      'entities': entities,
      'relationships': relationships,
      'timeline': timeline,
    },
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_phase8_compress_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('CompressionPromptBuilder', () {
    CompressionRequest request({int nodeLength = 100}) => CompressionRequest(
          jobId: 'job_1',
          resourceId: const ResourceId('res_1'),
          resourceType: ResourceType.worldview,
          scope: CompressionScope.section,
          targetNodeId: 'sec_1',
          resourceName: '世界观',
          nodes: [
            CompressionSourceNode(
              nodeId: 'part_1',
              title: '第一章',
              content: '赤' * nodeLength,
            ),
          ],
          targetCharacters: 60,
        );

    test('builds a prompt that carries the node and its budget', () {
      final instruction = CompressionPromptBuilder.buildInstruction(request());
      expect(instruction, contains('sec_1'));
      expect(instruction, contains('part_1'));
      expect(instruction, contains('目标节点'));
      expect(CompressionPromptBuilder.buildSystemPrompt(request()),
          contains('protocol_version'));
    });

    test('rejects a source window above the bounded input budget', () {
      final oversized = request(
        nodeLength: ResourceLimits.maxCompressionInputCharacters + 1,
      );
      expect(
        () => CompressionPromptBuilder.assertWithinInputBudget(oversized),
        throwsArgumentError,
      );
    });

    test('accepts a window exactly at the budget', () {
      final exact = request(
        nodeLength: ResourceLimits.maxCompressionInputCharacters,
      );
      expect(
        () => CompressionPromptBuilder.assertWithinInputBudget(exact),
        returnsNormally,
      );
    });

    test('bounds user guidance', () {
      final guidance =
          '要求' * (CompressionPromptBuilder.maxGuidanceCharacters + 200);
      final instruction = CompressionPromptBuilder.buildInstruction(
        CompressionRequest(
          jobId: 'job_1',
          resourceId: const ResourceId('res_1'),
          resourceType: ResourceType.worldview,
          scope: CompressionScope.section,
          targetNodeId: 'sec_1',
          resourceName: '世界观',
          nodes: const <CompressionSourceNode>[],
          targetCharacters: 60,
          guidance: guidance,
        ),
      );
      expect(
        instruction.length,
        lessThan(guidance.length),
        reason: 'guidance must be truncated to its bounded length',
      );
    });
  });

  group('CompressionResponseParser', () {
    test('parses a well-formed response', () {
      final parsed = CompressionResponseParser.parse(
        _compressedJson(
          '压缩后的正文',
          entities: const ['艾琳'],
          relationships: const ['艾琳→卡尔'],
          timeline: const ['第三纪元 120 年'],
        ),
      );
      expect(parsed.compressedContent, '压缩后的正文');
      expect(parsed.retention.entities, ['艾琳']);
      expect(parsed.retention.relationships, ['艾琳→卡尔']);
      expect(parsed.retention.timeline, ['第三纪元 120 年']);
    });

    test('unwraps a single fenced block', () {
      final parsed = CompressionResponseParser.parse(
        '```json\n${_compressedJson('压缩正文')}\n```',
      );
      expect(parsed.compressedContent, '压缩正文');
    });

    test('rejects unknown top-level fields', () {
      expect(
        () => CompressionResponseParser.parse(
          '{"protocol_version":1,"compressed_content":"x","extra":true}',
        ),
        throwsA(isA<CompressionParseException>()),
      );
    });

    test('rejects a wrong protocol version', () {
      expect(
        () => CompressionResponseParser.parse(
          '{"protocol_version":2,"compressed_content":"x"}',
        ),
        throwsA(isA<CompressionParseException>()),
      );
    });

    test('rejects empty and non-JSON payloads', () {
      expect(
        () => CompressionResponseParser.parse('   '),
        throwsA(isA<CompressionParseException>()),
      );
      expect(
        () => CompressionResponseParser.parse('这不是 JSON'),
        throwsA(isA<CompressionParseException>()),
      );
    });

    test('rejects an oversized result instead of storing it', () {
      final huge = '赤' * (ResourceLimits.maxCompressionOutputCharacters + 1);
      expect(
        () => CompressionResponseParser.parse(_compressedJson(huge)),
        throwsA(isA<CompressionParseException>()),
      );
    });
  });

  group('CompressionCoordinator', () {
    late Database db;
    late FakeCompressionLlm llm;
    late CompressionCoordinator coordinator;

    CompressionCoordinator buildCoordinator(Database database) {
      return CompressionCoordinator(
        jobRepository:
            CompressionJobRepositoryImpl(getDb: () async => database),
        treeRepository: ResourceTreeRepositoryImpl(getDb: () async => database),
        capacityRepository:
            ResourceCapacityRepositoryImpl(getDb: () async => database),
        llmPort: llm,
        jobIdFactory: _nextJobId,
      );
    }

    setUp(() async {
      db = await DatabaseService.database;
      llm = FakeCompressionLlm();
      coordinator = buildCoordinator(db);
    });

    Future<ResourceId> threeSectionResource() => createResourceTreeForTest(
          db,
          id: const ResourceId('res_compress'),
          type: ResourceType.worldview,
          name: '压缩测试',
          sections: [
            ['赤' * 800],
            ['青' * 800],
            ['白' * 800],
          ],
        );

    test('queueing never calls the model', () async {
      await threeSectionResource();
      final jobs = await coordinator.enqueueForResource(
        const ResourceId('res_compress'),
      );
      expect(jobs, hasLength(3));
      expect(jobs.every((job) => job.status == CompressionJobStatus.queued),
          isTrue);
      expect(llm.calls, 0,
          reason:
              'leaving the editor must only queue, never block on a request');
    });

    test(
        'compresses every section and stores candidates without touching '
        'the original', () async {
      final id = await threeSectionResource();
      final before = await readPartBodiesForTest(db, id);
      await coordinator.enqueueForResource(id);
      llm.response = _compressedJson('压缩后的摘要正文');

      final progress = await coordinator.drain();
      expect(progress.succeededJobs, 3);
      expect(progress.failedJobs, 0);

      final candidates = await coordinator.candidatesForResource(id);
      expect(candidates, hasLength(3));
      expect(candidates.every((candidate) => candidate.isValidated), isTrue);
      expect(
          candidates.every((candidate) => candidate.isCandidateOnly), isTrue);
      expect(
          candidates.first.compressedCharacters,
          lessThan(
            candidates.first.originalCharacters,
          ));

      final after = await readPartBodiesForTest(db, id);
      expect(after, before,
          reason: 'compression must leave the original content byte-for-byte '
              'unchanged; only Phase 9 may publish a candidate');
    });

    test('de-duplicates by resource, target and source version', () async {
      final id = await threeSectionResource();
      final first = await coordinator.enqueueForResource(id);
      final second = await coordinator.enqueueForResource(id);
      expect(second.map((job) => job.jobId), first.map((job) => job.jobId));
      expect(await coordinator.jobsForResource(id), hasLength(3));
    });

    test('a second drain does nothing once every job is terminal', () async {
      final id = await threeSectionResource();
      await coordinator.enqueueForResource(id);
      llm.response = _compressedJson('压缩后的摘要正文');
      await coordinator.drain();
      final callsAfterFirst = llm.calls;

      final second = await coordinator.drain();
      expect(second.processedJobs, 0);
      expect(llm.calls, callsAfterFirst);
      expect(await coordinator.candidatesForResource(id), hasLength(3));
    });

    test('empty content produces no job at all', () async {
      final id = await createResourceTreeForTest(
        db,
        id: const ResourceId('res_empty'),
        type: ResourceType.character,
        name: '空资源',
        sections: [
          [''],
          <String>[],
        ],
      );
      final jobs = await coordinator.enqueueForResource(id);
      expect(jobs, isEmpty);
      expect(llm.calls, 0);
    });

    test('a section larger than the input window splits into Part jobs',
        () async {
      final id = await createResourceTreeForTest(
        db,
        id: const ResourceId('res_split'),
        type: ResourceType.worldview,
        name: '超长章节',
        sections: [
          [for (var i = 0; i < 5; i++) '赤' * 3000],
        ],
      );
      final jobs = await coordinator.enqueueForResource(id);
      expect(jobs, hasLength(5));
      expect(
        jobs.every((job) => job.scope == CompressionScope.part),
        isTrue,
      );
    });

    test('a malformed response fails the job and stores no candidate',
        () async {
      final id = await threeSectionResource();
      await coordinator.enqueueForResource(id);
      llm.response = '这不是 JSON';

      final progress = await coordinator.drain(maxJobs: 1);
      expect(progress.failedJobs, 1);
      expect(await coordinator.candidatesForResource(id), isEmpty);

      final jobs = await coordinator.jobsForResource(id);
      final failed = jobs.firstWhere(
        (job) => job.status == CompressionJobStatus.failed,
      );
      expect(failed.attempts, 1);
      expect(failed.errorMessage, isNotEmpty);
    });

    test('a lost entity fails validation and keeps the original', () async {
      final id = await createResourceTreeForTest(
        db,
        id: const ResourceId('res_entity'),
        type: ResourceType.worldview,
        name: '实体守卫',
        sections: [
          ['艾琳与卡尔在赤焰城结盟。' * 50],
        ],
      );
      final before = await readPartBodiesForTest(db, id);
      await coordinator.enqueueForResource(id);
      llm.response = _compressedJson(
        '两人结盟。',
        entities: const ['黑铁团'],
      );

      await coordinator.drain(maxJobs: 1);
      expect(await coordinator.candidatesForResource(id), isEmpty);
      expect(await readPartBodiesForTest(db, id), before);

      final failed = (await coordinator.jobsForResource(id))
          .firstWhere((job) => job.status == CompressionJobStatus.failed);
      expect(failed.errorMessage, contains('压缩校验未通过'));
    });

    test('a hard network failure is bounded and requires an explicit retry',
        () async {
      final id = await threeSectionResource();
      await coordinator.enqueueForResource(id);
      llm.error = StateError('网络中断');

      await coordinator.drain(maxJobs: 1);
      var failed = (await coordinator.jobsForResource(id))
          .firstWhere((item) => item.status == CompressionJobStatus.failed);
      expect(failed.attempts, 1);

      // A later drain processes the remaining queued jobs but never retries the
      // failed one on its own.
      llm.error = null;
      llm.response = _compressedJson('其它章节的压缩结果');
      await coordinator.drain();
      failed = (await coordinator.jobsForResource(id))
          .firstWhere((item) => item.jobId == failed.jobId);
      expect(failed.status, CompressionJobStatus.failed);
      expect(failed.attempts, 1,
          reason: 'a failed job must wait for an explicit retry');

      // The explicit retry is allowed while the attempt budget remains.
      expect(await coordinator.retryJob(failed.jobId), isTrue);
      llm.error = StateError('再次失败');
      await coordinator.drain(maxJobs: 1);
      failed = (await coordinator.jobsForResource(id))
          .firstWhere((item) => item.jobId == failed.jobId);
      expect(failed.status, CompressionJobStatus.failed);
      expect(failed.attempts, ResourceLimits.maxCompressionAttempts);

      // The budget is spent: the job can no longer be re-queued, so the retry
      // count and the model call count both stop growing.
      final callsBefore = llm.calls;
      expect(await coordinator.retryJob(failed.jobId), isFalse,
          reason: 'the attempt budget is the hard stop against infinite retry');
      expect((await coordinator.drain()).processedJobs, 0);
      expect(llm.calls, callsBefore);
    });

    test('cancellation leaves queued jobs queued and calls no model', () async {
      final id = await threeSectionResource();
      await coordinator.enqueueForResource(id);
      final handle = GenerationTaskHandle(taskId: 'cancel_1');
      await handle.cancel();

      final progress = await coordinator.drain(taskHandle: handle);
      expect(progress.processedJobs, 0);
      expect(llm.calls, 0);
      final jobs = await coordinator.jobsForResource(id);
      expect(
        jobs.every((job) => job.status == CompressionJobStatus.queued),
        isTrue,
      );
    });

    test('queued jobs survive a restart and are recovered by a new drain',
        () async {
      final id = await threeSectionResource();
      await coordinator.enqueueForResource(id);

      // A fresh coordinator over the same database simulates an app restart.
      final restarted = buildCoordinator(db);
      llm.response = _compressedJson('重启后压缩结果');
      final progress = await restarted.drain();

      expect(progress.succeededJobs, 3);
      expect(await restarted.candidatesForResource(id), hasLength(3));
    });

    test('records the potential saving of validated candidates', () async {
      final id = await threeSectionResource();
      await coordinator.enqueueForResource(id);
      llm.response = _compressedJson('压缩结果');
      await coordinator.drain();

      final saved = await coordinator.potentialSavedCharacters(id);
      expect(saved, greaterThan(0));
    });

    test('an interrupted running job is released and can be drained again',
        () async {
      final id = await threeSectionResource();
      final jobs = await coordinator.enqueueForResource(id);
      final crashed = jobs.first;

      // Simulate the process dying mid-request: the row is left `running` with
      // one attempt already spent, and no worker owns it any more.
      await markCompressionJobRunningForTest(db, crashed.jobId, attempts: 1);

      // A new coordinator is the next process; its first drain recovers.
      final restarted = buildCoordinator(db);
      llm.response = _compressedJson('重启后恢复的压缩结果');
      final progress = await restarted.drain();

      expect(progress.succeededJobs, 3,
          reason: 'the released job must be runnable again, not stuck forever');
      final recovered = await readCompressionJobForTest(db, crashed.jobId);
      expect(recovered['status'], CompressionJobStatus.succeeded.storageValue);
      expect(await restarted.candidatesForResource(id), hasLength(3));
    });

    test('recovery is bounded: an exhausted running job becomes failed',
        () async {
      final id = await threeSectionResource();
      final jobs = await coordinator.enqueueForResource(id);
      final crashed = jobs.first;
      await markCompressionJobRunningForTest(
        db,
        crashed.jobId,
        attempts: ResourceLimits.maxCompressionAttempts,
      );

      final restarted = buildCoordinator(db);
      expect(await restarted.recoverStaleJobs(), 1);

      final row = await readCompressionJobForTest(db, crashed.jobId);
      expect(
        row['status'],
        CompressionJobStatus.failed.storageValue,
        reason: 'with no attempt budget left, recovery must stop rather than '
            'loop forever',
      );
      expect(row['error_message'], contains('重试次数已用尽'));

      // The untouched jobs still drain normally.
      llm.response = _compressedJson('其它章节压缩结果');
      final progress = await restarted.drain();
      expect(progress.succeededJobs, 2);
    });

    test('recovery is idempotent', () async {
      final id = await threeSectionResource();
      final jobs = await coordinator.enqueueForResource(id);
      await markCompressionJobRunningForTest(db, jobs.first.jobId, attempts: 1);

      final restarted = buildCoordinator(db);
      expect(await restarted.recoverStaleJobs(), 1);
      expect(await restarted.recoverStaleJobs(), 0,
          reason: 'a released job is no longer `running`, so nothing to redo');
    });

    test('a realistic 0.7 ratio result fails actionably and can be retried',
        () async {
      final id = await createResourceTreeForTest(
        db,
        id: const ResourceId('res_ratio'),
        type: ResourceType.character,
        name: '比例校验',
        sections: [
          ['赤' * 800],
        ],
      );
      final before = await readPartBodiesForTest(db, id);
      await coordinator.enqueueForResource(id);

      // 560/800 = 0.7: genuinely shorter, but above the 480-character budget.
      llm.response = _compressedJson('赤' * 560);
      await coordinator.drain(maxJobs: 1);

      var job = (await coordinator.jobsForResource(id)).single;
      expect(job.status, CompressionJobStatus.failed);
      expect(job.errorMessage, contains('压缩校验未通过'));
      expect(job.errorMessage, contains('超出预算'));
      expect(job.errorMessage, contains('原文 800 字'));
      expect(job.errorMessage, contains('目标 480 字'));
      expect(job.canRetry, isTrue,
          reason: 'an over-budget near miss must stay retryable');
      expect(await coordinator.candidatesForResource(id), isEmpty,
          reason: 'a rejected result must not become a candidate');
      expect(await readPartBodiesForTest(db, id), before,
          reason: 'the original must be byte-for-byte unchanged');

      // The retry path is reachable and, with a compliant result, succeeds.
      final retried = await coordinator.retryFailedJobs(id);
      expect(retried.requeued, 1);
      expect(retried.skippedActiveTarget, 0);
      job = (await coordinator.jobsForResource(id)).single;
      expect(job.status, CompressionJobStatus.queued);

      llm.response = _compressedJson('赤' * 400);
      final progress = await coordinator.drain();
      expect(progress.succeededJobs, 1);
      final candidates = await coordinator.candidatesForResource(id);
      expect(candidates, hasLength(1));
      expect(candidates.single.compressedCharacters, 400);
      expect(await readPartBodiesForTest(db, id), before);
    });
  });
}

int _jobSeed = 0;

String _nextJobId() => 'job_${_jobSeed++}';
