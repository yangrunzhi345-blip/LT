import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/compression_coordinator.dart';
import 'package:lt_dialogue/application/resources/compression_job_repository.dart';
import 'package:lt_dialogue/application/resources/compression_worker.dart';
import 'package:lt_dialogue/application/resources/resource_capacity_repository.dart';
import 'package:lt_dialogue/application/resources/resource_capacity_service.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/resource_capacity_fakes.dart';
import '../../helpers/resource_tree_fixtures.dart';

int _jobSeed = 0;

String _nextJobId() => 'cw_job_${_jobSeed++}';

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
    tempDir = await Directory.systemTemp.createTemp('lt_phase8_worker_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    db = await DatabaseService.database;
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  CompressionBackgroundWorker buildWorker(CompressionLlmPort llmPort) {
    final capacityRepository = ResourceCapacityRepositoryImpl(
      getDb: () async => db,
    );
    return CompressionBackgroundWorker(
      coordinator: CompressionCoordinator(
        jobRepository: CompressionJobRepositoryImpl(getDb: () async => db),
        treeRepository: ResourceTreeRepositoryImpl(getDb: () async => db),
        capacityRepository: capacityRepository,
        llmPort: llmPort,
        jobIdFactory: _nextJobId,
      ),
      capacityService: ResourceCapacityService(repository: capacityRepository),
    );
  }

  Future<ResourceId> resourceWith(String name, List<String> parts) =>
      createResourceTreeForTest(
        db,
        id: ResourceId('res_$name'),
        type: ResourceType.character,
        name: name,
        sections: [parts],
      );

  test('repeated scheduling of one resource coalesces into a single pass',
      () async {
    // Two sections of 10,001 characters each: past the 20,000-character nominal
    // budget, so the trigger queues work, while each section stays inside the
    // 12,000-character compression input window.
    final id = await createResourceTreeForTest(
      db,
      id: const ResourceId('res_coalesce'),
      type: ResourceType.character,
      name: 'coalesce',
      sections: [
        ['赤' * 3000, '赤' * 3000, '赤' * 3000, '赤' * 1001],
        ['赤' * 3000, '赤' * 3000, '赤' * 3000, '赤' * 1001],
      ],
    );
    final llm = GatedCompressionLlm()..response = _compressedJson('赤' * 400);
    final worker = buildWorker(llm);
    await worker.onEditorLeave(id.value);

    await waitForCondition(() async => llm.calls >= 1);
    expect(worker.processingCount, 1,
        reason: 'one resource has at most one background pass at a time');
    worker.scheduleProcessing(id.value);
    worker.scheduleProcessing(id.value);
    expect(worker.processingCount, 1);

    llm.release();
    await waitForCondition(() async => worker.processingCount == 0);
    expect(llm.calls, 2,
        reason: 'coalescing must not repeat a queued job\'s model call');
    expect(worker.lastError, isEmpty);
  });

  test('an automatic trigger failure never throws to the caller', () async {
    final worker = buildWorker(FakeCompressionLlm());

    // An unknown resource makes the measurement fail; the editor path must
    // survive it because compression is a derived task.
    final active = await worker.onEditorLeave('res_missing');

    expect(active, 0);
    expect(worker.lastError, isNotEmpty,
        reason: 'the failure is recorded instead of being swallowed');
  });

  test('leftover queued jobs are processed even below the threshold', () async {
    // 800 characters is inside a character card's nominal budget, so the
    // threshold trigger stays silent — but a job queued earlier must not be
    // abandoned just because the resource is no longer over budget.
    final id = await resourceWith('leftover', ['赤' * 800]);
    final llm = FakeCompressionLlm()..response = _compressedJson('赤' * 400);
    final capacityRepository = ResourceCapacityRepositoryImpl(
      getDb: () async => db,
    );
    final coordinator = CompressionCoordinator(
      jobRepository: CompressionJobRepositoryImpl(getDb: () async => db),
      treeRepository: ResourceTreeRepositoryImpl(getDb: () async => db),
      capacityRepository: capacityRepository,
      llmPort: llm,
      jobIdFactory: _nextJobId,
    );
    final worker = CompressionBackgroundWorker(
      coordinator: coordinator,
      capacityService: ResourceCapacityService(repository: capacityRepository),
    );
    expect(await coordinator.enqueueForResource(id), hasLength(1));

    final active = await worker.onEditorLeave(id.value);
    expect(active, 1);

    await waitForCondition(
      () async => (await coordinator.candidatesForResource(id)).isNotEmpty,
    );
    expect(llm.calls, 1);
    expect(worker.lastError, isEmpty);
  });

  test('start reports no work on a clean database', () async {
    final worker = buildWorker(FakeCompressionLlm());
    expect(await worker.start(), 0);
    expect(worker.lastError, isEmpty);
  });
}
