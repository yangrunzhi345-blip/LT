import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/compression_coordinator.dart';
import 'package:lt_dialogue/application/resources/compression_job_repository.dart';
import 'package:lt_dialogue/application/resources/resource_capacity_repository.dart';
import 'package:lt_dialogue/domain/resources/resource_compression.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/resource_capacity_fakes.dart';
import '../../helpers/resource_tree_fixtures.dart';

int _jobSeed = 0;

String _nextJobId() => 'cc_job_${_jobSeed++}';

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

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_phase8_concurrency_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    db = await DatabaseService.database;
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  CompressionCoordinator buildCoordinator({
    required String workerId,
    required CompressionLlmPort llmPort,
    DateTime Function()? clock,
  }) {
    return CompressionCoordinator(
      jobRepository: CompressionJobRepositoryImpl(getDb: () async => db),
      treeRepository: ResourceTreeRepositoryImpl(getDb: () async => db),
      capacityRepository: ResourceCapacityRepositoryImpl(getDb: () async => db),
      llmPort: llmPort,
      jobIdFactory: _nextJobId,
      workerId: workerId,
      clock: clock,
    );
  }

  Future<ResourceId> oneSectionResource(String name, {int parts = 1}) =>
      createResourceTreeForTest(
        db,
        id: ResourceId('res_$name'),
        type: ResourceType.character,
        name: name,
        sections: [
          [for (var i = 0; i < parts; i++) '赤' * 800],
        ],
      );

  Future<ResourceId> twoSectionResource(String name) =>
      createResourceTreeForTest(
        db,
        id: ResourceId('res_$name'),
        type: ResourceType.character,
        name: name,
        sections: [
          ['赤' * 800],
          ['青' * 800],
        ],
      );

  Future<CompressionJob> onlyJob(
          ResourceId id, CompressionCoordinator worker) async =>
      (await worker.jobsForResource(id)).single;

  group('TEST-1 two concurrent drains', () {
    test('exactly one worker runs the queued job', () async {
      final id = await oneSectionResource('race');
      final llm = GatedCompressionLlm()..response = _compressedJson('赤' * 400);
      final workers = [
        for (var i = 0; i < 4; i++)
          buildCoordinator(workerId: 'wkr_race_$i', llmPort: llm),
      ];
      await workers.first.enqueueForResource(id);

      // The drains really overlap: they start before either can finish, and the
      // winner is held inside the model call while the others act on the same
      // database row.
      final drains = Future.wait(
        [
          for (final worker in workers) worker.drain(resourceId: id, maxJobs: 1)
        ],
      );
      await waitForCondition(() async => llm.calls >= 1);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(llm.calls, 1,
          reason: 'no other worker may execute a job that was claimed');
      llm.release();
      await drains;

      final job = await onlyJob(id, workers.first);
      expect(job.status, CompressionJobStatus.succeeded);
      expect(job.attempts, 1, reason: 'one claim means one attempt');
      expect(llm.calls, 1);
      expect(await workers.first.candidatesForResource(id), hasLength(1));
    });
  });

  group('TEST-2 a live worker is not recovered', () {
    test('a running job under an unexpired lease keeps running', () async {
      final id = await oneSectionResource('live');
      final llm = GatedCompressionLlm()..response = _compressedJson('赤' * 400);
      final workerA = buildCoordinator(workerId: 'wkr_live', llmPort: llm);
      final workerB = buildCoordinator(workerId: 'wkr_other', llmPort: llm);
      await workerA.enqueueForResource(id);

      final inFlight = workerA.drain(resourceId: id, maxJobs: 1);
      await waitForCondition(() async =>
          (await workerB.jobsForResource(id)).single.status ==
          CompressionJobStatus.running);

      // A second worker starts up and recovers while the first is mid-request.
      expect(await workerB.recoverStaleJobs(), 0,
          reason: 'a live lease must never be reclaimed');
      final duringRun = await workerB.jobsForResource(id);
      expect(duringRun.single.status, CompressionJobStatus.running);
      expect(duringRun.single.workerId, workerA.workerId);
      expect(
          (await workerB.drain(resourceId: id, maxJobs: 1)).processedJobs, 0);

      llm.release();
      await inFlight;

      final afterRun = await workerB.jobsForResource(id);
      expect(afterRun.single.status, CompressionJobStatus.succeeded);
      expect(afterRun.single.attempts, 1);
      expect(llm.calls, 1);
      expect(await workerB.candidatesForResource(id), hasLength(1));
    });
  });

  group('TEST-3 an expired lease is recovered', () {
    test('a stale running job returns to the queue and then succeeds',
        () async {
      final id = await oneSectionResource('expired');
      final llm = FakeCompressionLlm()..response = _compressedJson('赤' * 400);
      final clockNow = DateTime(2026, 9, 17, 12);
      final worker = buildCoordinator(
        workerId: 'wkr_new',
        llmPort: llm,
        clock: () => clockNow,
      );
      await worker.enqueueForResource(id);
      final jobId = (await worker.jobsForResource(id)).single.jobId;
      await markCompressionJobRunningForTest(
        db,
        jobId,
        attempts: 1,
        workerId: 'wkr_dead',
        leaseExpiresAt: clockNow.subtract(const Duration(minutes: 1)),
      );

      expect(await worker.recoverStaleJobs(), 1);
      expect(
        (await readCompressionJobForTest(db, jobId))['status'],
        CompressionJobStatus.queued.storageValue,
      );

      final progress = await worker.drain(resourceId: id);
      expect(progress.succeededJobs, 1);
      final job = await worker.jobsForResource(id);
      expect(job.single.status, CompressionJobStatus.succeeded);
      expect(await worker.candidatesForResource(id), hasLength(1));
    });
  });

  group('TEST-4 retry versus an active target', () {
    test('a busy target is skipped as a business result, never an exception',
        () async {
      final id = await oneSectionResource('retry_conflict');
      final llm = FakeCompressionLlm()..error = StateError('网络中断');
      final worker = buildCoordinator(workerId: 'wkr_retry', llmPort: llm);
      await worker.enqueueForResource(id);
      await worker.drain(resourceId: id);
      final failed = await worker.jobsForResource(id);
      expect(failed.single.status, CompressionJobStatus.failed);

      // The section changes, so a new version gets its own queued job for the
      // same target — the state that used to make retry throw.
      await db.rawUpdate(
        'UPDATE resource_sections SET updated_at = ? WHERE resource_id = ?',
        ['2026-09-17T23:59:59.000', id.value],
      );
      await worker.enqueueForResource(id);
      final beforeRetry = await worker.jobsForResource(id);
      expect(beforeRetry, hasLength(2));
      expect(
        beforeRetry.where((job) => job.isActive).length,
        1,
        reason: 'only one active row per target may exist',
      );

      final outcome = await worker.retryFailedJobs(id);
      expect(outcome.requeued, 0);
      expect(outcome.skippedActiveTarget, 1);

      final afterRetry = await worker.jobsForResource(id);
      expect(afterRetry.where((job) => job.isActive).length, 1,
          reason: 'the retry must not add a second active row');
      expect(
        afterRetry.where((job) => job.status == CompressionJobStatus.failed),
        hasLength(1),
      );
    });
  });

  group('TEST-5 retry batch with a partial conflict', () {
    test('a conflict on one target does not abort the other retries', () async {
      final id = await twoSectionResource('retry_batch');
      final llm = FakeCompressionLlm()..error = StateError('网络中断');
      final worker = buildCoordinator(workerId: 'wkr_batch', llmPort: llm);
      await worker.enqueueForResource(id);
      await worker.drain(resourceId: id);
      final failedJobs = await worker.jobsForResource(id);
      expect(failedJobs, hasLength(2));
      expect(
        failedJobs.every((job) => job.status == CompressionJobStatus.failed),
        isTrue,
      );

      // Only the first target gets a new version, so only it becomes busy.
      final sectionIds = await _sectionIds(db, id);
      await db.rawUpdate(
        'UPDATE resource_sections SET updated_at = ? WHERE id = ?',
        ['2026-09-17T23:59:59.000', sectionIds.first],
      );
      await worker.enqueueForResource(id);

      final outcome = await worker.retryFailedJobs(id);
      expect(outcome.requeued, 1, reason: 'the free target must still retry');
      expect(outcome.skippedActiveTarget, 1);

      final attemptedTargets = (await worker.jobsForResource(id))
          .where((job) => job.status == CompressionJobStatus.queued)
          .length;
      expect(attemptedTargets, 2,
          reason: 'one new queued job plus the retried one');
    });
  });

  group('TEST-6 a drain is resource scoped', () {
    test('draining A leaves B queued and never calls the model for B',
        () async {
      final resourceA = await twoSectionResource('scoped_a');
      final resourceB = await twoSectionResource('scoped_b');
      final llm = FakeCompressionLlm()..response = _compressedJson('赤' * 400);
      final worker = buildCoordinator(workerId: 'wkr_scope', llmPort: llm);
      await worker.enqueueForResource(resourceA);
      await worker.enqueueForResource(resourceB);

      final progressA = await worker.drain(resourceId: resourceA);
      expect(progressA.succeededJobs, 2);
      expect(llm.calls, 2, reason: "B's jobs must not be sent to the model");
      expect(
        (await worker.jobsForResource(resourceB))
            .every((job) => job.status == CompressionJobStatus.queued),
        isTrue,
        reason: 'B stays queued while A is being processed',
      );
      expect(await worker.candidatesForResource(resourceB), isEmpty);

      final progressB = await worker.drain(resourceId: resourceB);
      expect(progressB.succeededJobs, 2);
      expect(llm.calls, 4);
      expect(await worker.candidatesForResource(resourceB), hasLength(2));
    });
  });

  group('claim and ownership', () {
    test('a terminal write from a worker that lost its lease is rejected',
        () async {
      final id = await oneSectionResource('ownership');
      final llm = GatedCompressionLlm()..response = _compressedJson('赤' * 400);
      final workerA = buildCoordinator(workerId: 'wkr_owner', llmPort: llm);
      final workerB = buildCoordinator(workerId: 'wkr_usurper', llmPort: llm);
      await workerA.enqueueForResource(id);

      final inFlight = workerA.drain(resourceId: id, maxJobs: 1);
      await waitForCondition(() async =>
          (await workerB.jobsForResource(id)).single.status ==
          CompressionJobStatus.running);

      // Force the lease to look expired and let a second worker reclaim it.
      await db.rawUpdate(
        'UPDATE resource_compression_jobs SET lease_expires_at = ? '
        'WHERE resource_id = ?',
        ['2026-09-17T00:00:00.000', id.value],
      );
      expect(await workerB.recoverStaleJobs(), 1);
      final reclaimed = (await workerB.jobsForResource(id)).single;
      expect(reclaimed.status, CompressionJobStatus.queued);

      // The first worker finishes late; its result must not overwrite the row.
      llm.release();
      await inFlight;
      final afterLateFinish = (await workerB.jobsForResource(id)).single;
      expect(afterLateFinish.status, CompressionJobStatus.queued,
          reason: 'a worker without a lease must not commit its result');
      expect(await workerA.candidatesForResource(id), isEmpty);
    });
  });
}

Future<List<String>> _sectionIds(Database db, ResourceId id) async {
  final rows = await db.query(
    'resource_sections',
    columns: ['id'],
    where: 'resource_id = ? AND deleted_at IS NULL',
    whereArgs: [id.value],
    orderBy: 'sort_order ASC, id ASC',
  );
  return rows.map((row) => row['id']?.toString() ?? '').toList();
}
