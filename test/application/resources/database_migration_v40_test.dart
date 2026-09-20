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

Future<List<String>> _columns(Database db, String table) async {
  final info = await db.rawQuery('PRAGMA table_info($table)');
  return info.map((row) => row['name'] as String).toList();
}

Future<int> _userVersion(Database db) async {
  final rows = await db.rawQuery('PRAGMA user_version');
  return (rows.first.values.first as num).toInt();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_v40_mig_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('Schema v41 fresh install (v40 test kept as a historical pin)', () {
    test('adds the compression worker lease columns', () async {
      final db = await DatabaseService.database;

      expect(await _userVersion(db), DatabaseService.schemaVersion);
      // Pinned on purpose: a schema bump must force a conscious update here.
      expect(DatabaseService.schemaVersion, 44);

      expect(
        await _columns(db, 'resource_compression_jobs'),
        containsAll(<String>[
          'worker_id',
          'claimed_at',
          'lease_expires_at',
        ]),
      );

      // A fresh job row must carry no owner: it cannot claim itself.
      await db.insert('resource_compression_jobs', {
        'job_id': 'job_fresh',
        'resource_id': 'res_fresh',
        'scope': 'part',
        'target_node_id': 'part_fresh',
        'parent_node_id': '',
        'source_token': 't0',
        'status': 'queued',
        'attempts': 0,
        'max_attempts': 2,
        'error_message': '',
        'created_at': '2026-09-17T00:00:00.000',
        'updated_at': '2026-09-17T00:00:00.000',
      });
      final row = (await db.query(
        'resource_compression_jobs',
        where: 'job_id = ?',
        whereArgs: ['job_fresh'],
      ))
          .single;
      expect(row['worker_id'], '');
      expect(row['claimed_at'], isNull);
      expect(row['lease_expires_at'], isNull);
    });
  });

  group('Migration v39 to v40', () {
    test('adds the lease columns and keeps a legacy running job recoverable',
        () async {
      final dbPath = '${tempDir.path}/adventures.db';
      final v39Db = await openDatabase(
        dbPath,
        version: 39,
        onCreate: (db, version) async {
          await DatabaseService.createV39Schema(db);
          await db.execute('PRAGMA user_version = 39');
        },
      );
      expect(await _userVersion(v39Db), 39);
      await v39Db.insert('resource_compression_jobs', {
        'job_id': 'job_legacy',
        'resource_id': 'res_legacy',
        'scope': 'section',
        'target_node_id': 'sec_legacy',
        'parent_node_id': '',
        'source_token': 't1',
        'status': 'running',
        'attempts': 1,
        'max_attempts': 2,
        'error_message': '',
        'created_at': '2026-09-17T00:00:00.000',
        'updated_at': '2026-09-17T00:00:00.000',
      });
      await v39Db.close();

      final upgraded = await DatabaseService.database;
      expect(await _userVersion(upgraded), DatabaseService.schemaVersion);

      final row = (await upgraded.query(
        'resource_compression_jobs',
        where: 'job_id = ?',
        whereArgs: ['job_legacy'],
      ))
          .single;
      // The migration does not rewrite business rows: the legacy `running` row
      // keeps its status and simply cannot prove ownership.
      expect(row['status'], CompressionJobStatus.running.storageValue);
      expect(row['attempts'], 1);
      expect(row['error_message'], '');
      expect(row['worker_id'], '');
      expect(row['claimed_at'], isNull);
      expect(row['lease_expires_at'], isNull);

      // Which is exactly what stale recovery handles, so no legacy running job
      // is left unrecoverable.
      final coordinator = CompressionCoordinator(
        jobRepository:
            CompressionJobRepositoryImpl(getDb: () async => upgraded),
        treeRepository: ResourceTreeRepositoryImpl(getDb: () async => upgraded),
        capacityRepository:
            ResourceCapacityRepositoryImpl(getDb: () async => upgraded),
        llmPort: FakeCompressionLlm(),
      );
      expect(await coordinator.recoverStaleJobs(), 1);
      expect(
        (await coordinator.jobsForResource(const ResourceId('res_legacy')))
            .single
            .status,
        CompressionJobStatus.queued,
      );
    });

    test('re-running the upgrade step is idempotent', () async {
      final db = await DatabaseService.database;
      await DatabaseService.addCompressionLeaseColumns(db);
      await DatabaseService.addCompressionLeaseColumns(db);

      final columns = await _columns(db, 'resource_compression_jobs');
      expect(columns.where((name) => name == 'worker_id').length, 1);
      expect(columns.where((name) => name == 'claimed_at').length, 1);
      expect(columns.where((name) => name == 'lease_expires_at').length, 1);
    });
  });
}
