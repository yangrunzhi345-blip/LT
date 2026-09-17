import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/compression_coordinator.dart';
import 'package:lt_dialogue/application/resources/compression_job_repository.dart';
import 'package:lt_dialogue/application/resources/resource_capacity_repository.dart';
import 'package:lt_dialogue/application/resources/resource_capacity_service.dart';
import 'package:lt_dialogue/domain/resources/resource_compression.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_limits.dart';
import 'package:lt_dialogue/features/resource_studio/application/use_cases/resource_capacity_runtime.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/resource_capacity_fakes.dart';
import '../../helpers/resource_tree_fixtures.dart';

int _jobSeed = 0;

String _nextJobId() => 'rt_job_${_jobSeed++}';

String _compressedJson(String content) => jsonEncode({
      'protocol_version': 1,
      'compressed_content': content,
      'retained': {
        'entities': <String>[],
        'relationships': <String>[],
        'timeline': <String>[],
      },
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late Database db;
  late FakeCompressionLlm llm;
  late ResourceCapacityServiceRuntime runtime;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_phase8_runtime_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    db = await DatabaseService.database;
    llm = FakeCompressionLlm();

    final capacityRepository = ResourceCapacityRepositoryImpl(
      getDb: () async => db,
    );
    runtime = ResourceCapacityServiceRuntime(
      capacityService: ResourceCapacityService(repository: capacityRepository),
      compressionCoordinator: CompressionCoordinator(
        jobRepository: CompressionJobRepositoryImpl(getDb: () async => db),
        treeRepository: ResourceTreeRepositoryImpl(getDb: () async => db),
        capacityRepository: capacityRepository,
        llmPort: llm,
        jobIdFactory: _nextJobId,
      ),
    );
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('automatic compression trigger (production runtime)', () {
    test(
        'queues jobs when the resource is over its budget, without a model '
        'call', () async {
      // 6 Parts x 1,000 characters = 6,000 > the 5,000 character nominal budget,
      // so the resource is elastic and compression is warranted.
      final id = await createResourceTreeForTest(
        db,
        id: const ResourceId('res_over_budget'),
        type: ResourceType.character,
        name: '超限角色',
        sections: [
          [for (var i = 0; i < 6; i++) '赤' * 1000],
        ],
      );
      final before = await readPartBodiesForTest(db, id);

      final queued = await runtime.autoQueueCompressionIfNeeded(id.value);

      expect(queued, greaterThanOrEqualTo(1),
          reason: 'a resource past its nominal budget must be queued');
      expect(llm.calls, 0,
          reason: 'the trigger may only create jobs, never call the model');
      expect(await readPartBodiesForTest(db, id), before,
          reason: 'queueing must not touch Part content');
      final summary = await runtime.summarize(id.value);
      expect(summary.queuedJobs, greaterThanOrEqualTo(1));
      expect(summary.candidateCount, 0,
          reason: 'queueing produces no candidate on its own');
    });

    test('does nothing while the resource is inside its budget', () async {
      final id = await createResourceTreeForTest(
        db,
        id: const ResourceId('res_in_budget'),
        type: ResourceType.character,
        name: '正常角色',
        sections: [
          ['赤' * 100],
        ],
      );

      final queued = await runtime.autoQueueCompressionIfNeeded(id.value);

      expect(queued, 0);
      expect(llm.calls, 0);
      final jobs = await runtime.summarize(id.value);
      expect(jobs.queuedJobs, 0);
      expect(jobs.candidateCount, 0);
    });

    test('the same revision is never queued twice', () async {
      final id = await createResourceTreeForTest(
        db,
        id: const ResourceId('res_dedup'),
        type: ResourceType.character,
        name: '去重角色',
        sections: [
          [for (var i = 0; i < 6; i++) '赤' * 1000],
        ],
      );

      final first = await runtime.autoQueueCompressionIfNeeded(id.value);
      final second = await runtime.autoQueueCompressionIfNeeded(id.value);

      expect(first, greaterThanOrEqualTo(1));
      expect(second, first,
          reason: 'the same (resource, target, version) is one job');
    });
  });

  group('retry workflow (production runtime)', () {
    Future<ResourceId> compressibleResource(String name) =>
        createResourceTreeForTest(
          db,
          id: ResourceId('res_$name'),
          type: ResourceType.character,
          name: name,
          sections: [
            ['赤' * 800],
          ],
        );

    test('a failed job is visible, retryable and succeeds on retry', () async {
      final id = await compressibleResource('retry_ok');
      await runtime.queueCompression(id.value);
      llm.error = StateError('网络中断');
      await runtime.runQueuedCompression();

      var summary = await runtime.summarize(id.value);
      expect(summary.retryableFailedJobs, 1,
          reason:
              'a failure with attempt budget left must be offered for retry');
      expect(summary.latestFailureReason, contains('网络中断'),
          reason: 'the panel needs the reason, not just a count');
      expect(summary.candidateCount, 0);

      expect(await runtime.retryFailedCompression(id.value), 1);
      llm.error = null;
      llm.response = _compressedJson('赤' * 400);
      await runtime.runQueuedCompression();

      summary = await runtime.summarize(id.value);
      expect(summary.retryableFailedJobs, 0);
      expect(summary.candidateCount, 1);
    });

    test('refuses to retry once the attempt budget is spent', () async {
      final id = await compressibleResource('retry_exhausted');
      await runtime.queueCompression(id.value);

      // First failure.
      llm.error = StateError('第一次失败');
      await runtime.runQueuedCompression();
      expect(await runtime.retryFailedCompression(id.value), 1);

      // Second failure spends the budget (maxAttempts == 2).
      llm.error = StateError('第二次失败');
      await runtime.runQueuedCompression();

      expect(await runtime.retryFailedCompression(id.value), 0,
          reason: 'the attempt budget is the hard stop');
      final summary = await runtime.summarize(id.value);
      expect(summary.retryableFailedJobs, 0);
      expect(summary.latestFailureReason, contains('第二次失败'));
    });

    test('retrying with nothing to retry reports nothing to do', () async {
      final id = await compressibleResource('retry_none');
      expect(await runtime.retryFailedCompression(id.value), 0);
    });
  });

  group('interrupted recovery (production runtime)', () {
    test('releases a job left running by a previous process', () async {
      final id = await createResourceTreeForTest(
        db,
        id: const ResourceId('res_recover'),
        type: ResourceType.character,
        name: '恢复角色',
        sections: [
          ['赤' * 800],
        ],
      );
      await runtime.queueCompression(id.value);
      final jobId = await _onlyJobId(db, id);
      expect(jobId, isNotEmpty);
      await markCompressionJobRunningForTest(db, jobId, attempts: 1);

      expect(await runtime.recoverInterruptedJobs(), 1);
      final row = await readCompressionJobForTest(db, jobId);
      expect(row['status'], CompressionJobStatus.queued.storageValue);

      llm.response = _compressedJson('赤' * 400);
      final progress = await runtime.runQueuedCompression();
      expect(progress.succeededJobs, 1,
          reason: 'a released job must be drainable again');
      expect((await runtime.summarize(id.value)).candidateCount, 1);
    });

    test('turns an exhausted interrupted job into a terminal failure',
        () async {
      final id = await createResourceTreeForTest(
        db,
        id: const ResourceId('res_recover_exhausted'),
        type: ResourceType.character,
        name: '恢复耗尽角色',
        sections: [
          ['赤' * 800],
        ],
      );
      await runtime.queueCompression(id.value);
      final jobId = await _onlyJobId(db, id);
      await markCompressionJobRunningForTest(
        db,
        jobId,
        attempts: ResourceLimits.maxCompressionAttempts,
      );

      expect(await runtime.recoverInterruptedJobs(), 1);
      expect(
        (await readCompressionJobForTest(db, jobId))['status'],
        CompressionJobStatus.failed.storageValue,
      );
      // Nothing is queued, so a drain is a no-op rather than a stuck target.
      expect((await runtime.runQueuedCompression()).processedJobs, 0);
    });
  });
}

Future<String> _onlyJobId(Database db, ResourceId id) async {
  final rows = await db.query(
    'resource_compression_jobs',
    columns: ['job_id'],
    where: 'resource_id = ?',
    whereArgs: [id.value],
    orderBy: 'created_at ASC, job_id ASC',
    limit: 1,
  );
  return rows.isEmpty ? '' : rows.first['job_id']?.toString() ?? '';
}
