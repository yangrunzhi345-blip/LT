import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/adventure/adventure_readiness_gate.dart';
import 'package:lt_dialogue/application/resources/assembly_readiness_coordinator.dart';
import 'package:lt_dialogue/application/resources/assembly_readiness_repository.dart';
import 'package:lt_dialogue/application/resources/compression_coordinator.dart';
import 'package:lt_dialogue/application/resources/compression_job_repository.dart';
import 'package:lt_dialogue/application/resources/resource_capacity_repository.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/errors/diagnostic_envelope.dart';
import 'package:lt_dialogue/models/generation_task_handle.dart';
import 'package:sqflite/sqflite.dart';

import '../../helpers/phase10_fixture.dart';

class _NeverCompressLlmPort implements CompressionLlmPort {
  @override
  Future<String> compress({
    required String systemPrompt,
    required String instruction,
    GenerationTaskHandle? taskHandle,
  }) async {
    throw StateError('不该在本测试中触发真实压缩请求');
  }
}

/// Delegates everything but fails the index write, simulating a semantic
/// index build failure.
class _BrokenIndexRepository implements IAssemblyReadinessRepository {
  _BrokenIndexRepository(this._inner);

  final IAssemblyReadinessRepository _inner;

  @override
  Future<AssemblyReadinessRecord?> read(String resourceId) =>
      _inner.read(resourceId);

  @override
  Future<AssemblyReadinessRecord?> readInTransaction(
    DatabaseExecutor txn,
    String resourceId,
  ) =>
      _inner.readInTransaction(txn, resourceId);

  @override
  Future<void> writeInTransaction(
    DatabaseExecutor txn,
    AssemblyReadinessRecord record,
  ) =>
      _inner.writeInTransaction(txn, record);

  @override
  Future<List<AssemblyReadinessRecord>> listByState(ReadinessState state) =>
      _inner.listByState(state);

  @override
  Future<List<AssemblyIndexDoc>> readIndexDocs(
    String resourceId,
    String revisionId,
  ) =>
      _inner.readIndexDocs(resourceId, revisionId);

  @override
  Future<List<AssemblyIndexDoc>> readIndexDocsInTransaction(
    DatabaseExecutor txn,
    String resourceId,
    String revisionId,
  ) =>
      _inner.readIndexDocsInTransaction(txn, resourceId, revisionId);

  @override
  Future<void> replaceIndexDocsInTransaction(
    DatabaseExecutor txn, {
    required String resourceId,
    required String revisionId,
    required String revisionContentHash,
    required List<AssemblyIndexDoc> docs,
    required String now,
  }) async {
    throw const ResourceContractException('注入的索引构建失败');
  }
}

void main() {
  late Phase10Fixture fixture;

  setUp(() async {
    fixture = Phase10Fixture();
    await fixture.setUp(prefix: 'lt_phase10_extra_');
  });

  tearDown(() => fixture.tearDown());

  test('index build failure keeps the resource failed and never ready',
      () async {
    final resourceId = await fixture.createWorldview(
        'x_wv1',
        [
          ['正文'],
        ],
        summary: '概览',
        confirmed: true);

    final db = fixture.db;
    final brokenCoordinator = AssemblyReadinessCoordinator(
      getDb: () async => db,
      readinessRepository:
          _BrokenIndexRepository(AssemblyReadinessRepositoryImpl(
        getDb: () async => db,
      )),
      revisionRepository: fixture.revisionRepository,
      revisionService: fixture.revisionService,
      builder: fixture.builder,
      typeResolver: (id) async =>
          (await fixture.treeRepository.findResource(id))?.type,
    );

    final outcome = await brokenCoordinator.prepare(resourceId);
    expect(outcome.record.state, ReadinessState.failed);
    expect(
      DiagnosticEnvelope.tryDecode(outcome.record.failureReason)?.code,
      'preparationFailed',
    );

    // Fail-closed: the readiness row is `failed`, so the Adventure gate
    // blocks the resource even though the immutable assembly revision row
    // itself was published (a revision row without a ready verdict is not
    // consumable).
    final statuses = await fixture.gate.resolve([resourceId.value]);
    expect(
      statuses[resourceId.value]!.status,
      AdventureAssetGateStatus.failed,
    );
    expect(
      statuses[resourceId.value]!.status.blocksStart,
      isTrue,
    );

    // A retry with a healthy index repository reaches ready.
    final retried = await fixture.coordinator.prepare(resourceId);
    expect(retried.record.state, ReadinessState.ready);
    // The index documents exist only after the healthy retry.
    final assembly = await fixture.revisionRepository.readHead(
      resourceId,
      ResourceRevisionKind.assembly,
    );
    expect(assembly, isNotNull);
    final docs = await fixture.readinessRepository.readIndexDocs(
      resourceId.value,
      assembly!.revisionId.value,
    );
    expect(docs, isNotEmpty);
  });

  test('OVERFLOW head enqueues Phase 8 compression preparation jobs', () async {
    final bigBody = '超' * 61000;
    final resourceId = await fixture.createWorldview(
        'x_wv2',
        [
          [bigBody],
        ],
        summary: '概览',
        confirmed: true);

    // A real Phase 8 coordinator (compression is never drained here, so the
    // LLM port is never called).
    final compression = CompressionCoordinator(
      jobRepository:
          CompressionJobRepositoryImpl(getDb: () async => fixture.db),
      treeRepository: fixture.treeRepository,
      capacityRepository:
          ResourceCapacityRepositoryImpl(getDb: () async => fixture.db),
      llmPort: _NeverCompressLlmPort(),
    );
    final coordinator = fixture.secondCoordinator();
    coordinator.attachCompression(coordinatorGetter: () => compression);

    final outcome = await coordinator.prepare(resourceId);

    expect(outcome.awaitedCompression, isTrue);
    expect(outcome.record.state, ReadinessState.preparing);

    // Phase 8 compression preparation actually received jobs.
    final jobs = await fixture.db.query(
      'resource_compression_jobs',
      where: 'resource_id = ?',
      whereArgs: <Object?>[resourceId.value],
    );
    expect(jobs, isNotEmpty);

    // Fail-closed: no assembly revision exists for an OVERFLOW head.
    final assembly = await fixture.revisionRepository.readHead(
      resourceId,
      ResourceRevisionKind.assembly,
    );
    expect(assembly, isNull);
  });

  test('OVERFLOW head without a compression link fails closed', () async {
    final bigBody = '超' * 61000;
    final resourceId = await fixture.createWorldview(
        'x_wv3',
        [
          [bigBody],
        ],
        summary: '概览',
        confirmed: true);

    // No compression is attached, so no worker would ever drain this overflow:
    // staying `preparing` would be a silent dead-end (C14 fail-fast).
    final outcome = await fixture.coordinator.prepare(resourceId);

    expect(outcome.record.state, ReadinessState.failed);
    expect(
      DiagnosticEnvelope.tryDecode(outcome.record.failureReason)?.code,
      'compressionUnavailable',
    );
    expect(outcome.awaitedCompression, isFalse);

    // Fail-closed: the failed verdict blocks Adventure start.
    final statuses = await fixture.gate.resolve([resourceId.value]);
    expect(
      statuses[resourceId.value]!.status.blocksStart,
      isTrue,
    );
  });
}
