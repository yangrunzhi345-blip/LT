import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/compression_coordinator.dart';
import 'package:lt_dialogue/application/resources/compression_job_repository.dart';
import 'package:lt_dialogue/application/resources/compression_worker.dart';
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
  late ResourceCapacityService capacityService;
  late CompressionCoordinator coordinator;
  late CompressionBackgroundWorker worker;
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
    capacityService = ResourceCapacityService(repository: capacityRepository);
    coordinator = CompressionCoordinator(
      jobRepository: CompressionJobRepositoryImpl(getDb: () async => db),
      treeRepository: ResourceTreeRepositoryImpl(getDb: () async => db),
      capacityRepository: capacityRepository,
      llmPort: llm,
      jobIdFactory: _nextJobId,
    );
    worker = CompressionBackgroundWorker(
      coordinator: coordinator,
      capacityService: capacityService,
    );
    runtime = ResourceCapacityServiceRuntime(
      capacityService: capacityService,
      compressionCoordinator: coordinator,
      worker: worker,
    );
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('automatic compression lifecycle (production worker)', () {
    /// Two sections of 10,001 characters each.
    ///
    /// The total is just past the 20,000-character character nominal budget, so
    /// the trigger fires, and each section fits the 12,000-character
    /// compression input window, so the pass queues exactly two section jobs.
    List<List<String>> overBudgetSections() => [
          ['赤' * 3000, '赤' * 3000, '赤' * 3000, '赤' * 1001],
          ['赤' * 3000, '赤' * 3000, '赤' * 3000, '赤' * 1001],
        ];

    Future<ResourceId> overBudgetResource(String name) =>
        createResourceTreeForTest(
          db,
          id: ResourceId('res_$name'),
          type: ResourceType.character,
          name: name,
          sections: overBudgetSections(),
        );

    test('leaving the editor compresses in the background without blocking',
        () async {
      final id = await overBudgetResource('auto_over');
      final before = await readPartBodiesForTest(db, id);
      llm.response = _compressedJson('赤' * 400);

      // The trigger must return without waiting for the model: the fake LLM is
      // instantaneous here, but every value the caller needs (the queued count
      // and its own state) is produced before the pass is scheduled.
      final active = await runtime.onEditorLeave(id.value);
      expect(active, greaterThanOrEqualTo(1),
          reason: 'a resource past its nominal budget must be queued');

      // The background pass then produces the candidates on its own.
      await waitForCondition(
        () async => (await coordinator.candidatesForResource(id)).isNotEmpty,
      );
      final candidates = await coordinator.candidatesForResource(id);
      expect(candidates, hasLength(2));
      expect(candidates.every((candidate) => candidate.isValidated), isTrue);
      expect(await readPartBodiesForTest(db, id), before,
          reason: 'the automatic path may only produce candidates');
      expect(llm.calls, 2,
          reason: 'each queued job must be compressed exactly once');
    });

    test('leaving the editor does not make the caller wait for the model',
        () async {
      final id = await overBudgetResource('auto_nonblocking');
      final gated = GatedCompressionLlm()
        ..response = _compressedJson('赤' * 400);
      final gatedCoordinator = CompressionCoordinator(
        jobRepository: CompressionJobRepositoryImpl(getDb: () async => db),
        treeRepository: ResourceTreeRepositoryImpl(getDb: () async => db),
        capacityRepository:
            ResourceCapacityRepositoryImpl(getDb: () async => db),
        llmPort: gated,
        jobIdFactory: _nextJobId,
      );
      final gatedRuntime = ResourceCapacityServiceRuntime(
        capacityService: capacityService,
        compressionCoordinator: gatedCoordinator,
        worker: CompressionBackgroundWorker(
          coordinator: gatedCoordinator,
          capacityService: capacityService,
        ),
      );

      // If the trigger awaited its background pass, this future would never
      // complete while the model call is blocked.
      final active = await gatedRuntime.onEditorLeave(id.value);
      expect(active, greaterThanOrEqualTo(1));

      await waitForCondition(() async => gated.calls >= 1);
      expect(gated.calls, 1,
          reason:
              'the model call started but the trigger had already returned');

      gated.release();
      await waitForCondition(
        () async =>
            (await gatedCoordinator.candidatesForResource(id)).isNotEmpty,
      );
      expect(await gatedCoordinator.candidatesForResource(id), hasLength(2));
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

      final active = await runtime.onEditorLeave(id.value);

      expect(active, 0);
      expect(llm.calls, 0);
      expect(worker.processingCount, 0);
      final summary = await runtime.summarize(id.value);
      expect(summary.queuedJobs, 0);
      expect(summary.candidateCount, 0);
    });

    test('a repeated lifecycle event never produces a second candidate',
        () async {
      final id = await overBudgetResource('auto_repeat');
      llm.response = _compressedJson('赤' * 400);

      await runtime.onEditorLeave(id.value);
      await waitForCondition(
        () async => (await coordinator.candidatesForResource(id)).isNotEmpty,
      );
      await runtime.onEditorLeave(id.value);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(await coordinator.candidatesForResource(id), hasLength(2),
          reason: 'the same (resource, target, version) is one job per node');
      expect(llm.calls, 2);
    });

    test(
        'a model failure in the background never breaks the caller and '
        'leaves the original untouched', () async {
      final id = await overBudgetResource('auto_fail');
      final before = await readPartBodiesForTest(db, id);
      llm.error = StateError('网络中断');

      final active = await runtime.onEditorLeave(id.value);
      expect(active, greaterThanOrEqualTo(1));

      await waitForCondition(
        () async => (await coordinator.jobsForResource(id))
            .any((job) => job.status == CompressionJobStatus.failed),
      );
      expect(await readPartBodiesForTest(db, id), before);
      expect(worker.lastError, isEmpty,
          reason: 'a per-job failure is recorded on the job, not as a worker '
              'infrastructure error');
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
      await runtime.runQueuedCompression(id.value);

      var summary = await runtime.summarize(id.value);
      expect(summary.retryableFailedJobs, 1,
          reason:
              'a failure with attempt budget left must be offered for retry');
      expect(summary.latestFailureReason, contains('网络中断'),
          reason: 'the panel needs the reason, not just a count');
      expect(summary.candidateCount, 0);

      final outcome = await runtime.retryFailedCompression(id.value);
      expect(outcome.requeued, 1);
      expect(outcome.skippedActiveTarget, 0);
      llm.error = null;
      llm.response = _compressedJson('赤' * 400);
      await runtime.runQueuedCompression(id.value);

      summary = await runtime.summarize(id.value);
      expect(summary.retryableFailedJobs, 0);
      expect(summary.candidateCount, 1);
    });

    test('refuses to retry once the attempt budget is spent', () async {
      final id = await compressibleResource('retry_exhausted');
      await runtime.queueCompression(id.value);

      // First failure.
      llm.error = StateError('第一次失败');
      await runtime.runQueuedCompression(id.value);
      expect((await runtime.retryFailedCompression(id.value)).requeued, 1);

      // Second failure spends the budget (maxAttempts == 2).
      llm.error = StateError('第二次失败');
      await runtime.runQueuedCompression(id.value);

      final outcome = await runtime.retryFailedCompression(id.value);
      expect(outcome.requeued, 0,
          reason: 'the attempt budget is the hard stop');
      expect(outcome.skippedExhausted, 1);
      final summary = await runtime.summarize(id.value);
      expect(summary.retryableFailedJobs, 0);
      expect(summary.latestFailureReason, contains('第二次失败'));
    });

    test('retrying with nothing to retry reports nothing to do', () async {
      final id = await compressibleResource('retry_none');
      final outcome = await runtime.retryFailedCompression(id.value);
      expect(outcome.requeued, 0);
      expect(outcome.skipped, 0);
    });
  });

  group('interrupted recovery (worker lifecycle, no Studio involved)', () {
    test('start releases a job left running by a previous process', () async {
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
      // No lease: the row was written by a process that is gone.
      await markCompressionJobRunningForTest(db, jobId, attempts: 1);

      expect(await worker.start(), 1);
      final row = await readCompressionJobForTest(db, jobId);
      expect(row['status'], CompressionJobStatus.queued.storageValue);

      llm.response = _compressedJson('赤' * 400);
      final progress = await runtime.runQueuedCompression(id.value);
      expect(progress.succeededJobs, 1,
          reason: 'a released job must be drainable again');
      expect((await runtime.summarize(id.value)).candidateCount, 1);
    });

    test('start never touches a job whose lease is still live', () async {
      final id = await createResourceTreeForTest(
        db,
        id: const ResourceId('res_recover_live'),
        type: ResourceType.character,
        name: '活跃角色',
        sections: [
          ['赤' * 800],
        ],
      );
      await runtime.queueCompression(id.value);
      final jobId = await _onlyJobId(db, id);
      await markCompressionJobRunningForTest(
        db,
        jobId,
        attempts: 1,
        workerId: 'wkr_other',
        leaseExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );

      expect(await worker.start(), 0,
          reason: 'a live worker must not be robbed of its job');
      expect(
        (await readCompressionJobForTest(db, jobId))['status'],
        CompressionJobStatus.running.storageValue,
      );
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

      expect(await worker.start(), 1);
      expect(
        (await readCompressionJobForTest(db, jobId))['status'],
        CompressionJobStatus.failed.storageValue,
      );
      // Nothing is queued, so a drain is a no-op rather than a stuck target.
      expect(
        (await runtime.runQueuedCompression(id.value)).processedJobs,
        0,
      );
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
