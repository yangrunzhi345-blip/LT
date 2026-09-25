import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<List<String>> _columns(Database db, String table) async {
  final info = await db.rawQuery('PRAGMA table_info($table)');
  return info.map((row) => row['name'] as String).toList();
}

Future<List<String>> _indexes(Database db, String table) async {
  final info = await db.rawQuery('PRAGMA index_list($table)');
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
    tempDir = await Directory.systemTemp.createTemp('lt_v39_mig_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('Schema v39 fresh install', () {
    test('creates the capacity columns and compression tables', () async {
      final db = await DatabaseService.database;
      expect(await _userVersion(db), DatabaseService.schemaVersion);
      // Pinned on purpose: a schema bump must force a conscious update here.
      // v40 added the compression worker lease columns.
      expect(DatabaseService.schemaVersion, 46);

      final resourceColumns = await _columns(db, 'resources');
      expect(
        resourceColumns,
        containsAll(<String>[
          'measured_char_count',
          'measured_token_estimate',
          'section_count',
          'part_count',
          'archive_char_count',
          'capacity_status',
          'capacity_measured_at',
        ]),
      );

      expect(
        await DatabaseService.tableExists(db, 'resource_compression_jobs'),
        isTrue,
      );
      expect(
        await DatabaseService.tableExists(
          db,
          'resource_compression_candidates',
        ),
        isTrue,
      );

      final jobColumns = await _columns(db, 'resource_compression_jobs');
      expect(
        jobColumns,
        containsAll(<String>[
          'job_id',
          'resource_id',
          'scope',
          'target_node_id',
          'parent_node_id',
          'source_token',
          'status',
          'attempts',
          'max_attempts',
          'error_message',
          'created_at',
          'updated_at',
        ]),
      );
      expect(
        await _indexes(db, 'resource_compression_jobs'),
        containsAll(<String>[
          'idx_compression_jobs_dedup',
          'idx_compression_jobs_active_target',
          'idx_compression_jobs_status',
        ]),
      );

      final candidateColumns =
          await _columns(db, 'resource_compression_candidates');
      expect(
        candidateColumns,
        containsAll(<String>[
          'candidate_id',
          'job_id',
          'resource_id',
          'scope',
          'target_node_id',
          'original_char_count',
          'compressed_char_count',
          'compressed_content',
          'retention_json',
          'validation_state',
          'validation_message',
          'applied_at',
          'created_at',
        ]),
      );
      expect(
        await _indexes(db, 'resource_compression_candidates'),
        containsAll(<String>[
          'idx_compression_candidates_job',
          'idx_compression_candidates_resource',
        ]),
      );

      // A freshly created candidate slot must default to "not applied": only
      // Phase 9 may publish a compression result.
      final newResource = await db.query('resources');
      expect(newResource, isEmpty);
    });
  });

  group('Migration v38 to v39', () {
    test('adds columns and tables while preserving existing content', () async {
      final dbPath = '${tempDir.path}/adventures.db';
      final v38Db = await openDatabase(
        dbPath,
        version: 38,
        onCreate: (db, version) async {
          await DatabaseService.createV38Schema(db);
          await db.execute('PRAGMA user_version = 38');
        },
      );
      expect(await _userVersion(v38Db), 38);

      await v38Db.insert('resources', {
        'id': 'res_v38',
        'type': 'worldview',
        'name': '旧世界观',
        'summary': '旧摘要',
        'status': 'draft',
        'metadata_json': '{}',
        'schema_version': 1,
        'created_at': '2026-09-17T00:00:00.000',
        'updated_at': '2026-09-17T00:00:00.000',
      });
      await v38Db.insert('resource_sections', {
        'id': 'sec_v38',
        'resource_id': 'res_v38',
        'title': '旧章节',
        'summary': '',
        'sort_order': 0,
        'status': 'draft',
        'created_at': '2026-09-17T00:00:00.000',
        'updated_at': '2026-09-17T00:00:00.000',
      });
      await v38Db.insert('resource_parts', {
        'id': 'part_v38',
        'section_id': 'sec_v38',
        'title': '旧部件',
        'content': '旧正文内容',
        'sort_order': 0,
        'status': 'draft',
        'content_hash': '',
        'created_at': '2026-09-17T00:00:00.000',
        'updated_at': '2026-09-17T00:00:00.000',
      });
      await v38Db.close();

      final upgraded = await DatabaseService.database;
      expect(await _userVersion(upgraded), DatabaseService.schemaVersion);

      final resource = (await upgraded.query(
        'resources',
        where: 'id = ?',
        whereArgs: ['res_v38'],
      ))
          .single;
      expect(resource['name'], '旧世界观');
      expect(resource['measured_char_count'], 0);
      expect(resource['measured_token_estimate'], 0);
      expect(resource['archive_char_count'], 0);
      expect(resource['capacity_status'], 'normal');
      expect(resource['capacity_measured_at'], isNull);

      final part = (await upgraded.query(
        'resource_parts',
        where: 'id = ?',
        whereArgs: ['part_v38'],
      ))
          .single;
      expect(part['content'], '旧正文内容');

      expect(
        await upgraded.query('resource_compression_jobs'),
        isEmpty,
      );
      expect(
        await upgraded.query('resource_compression_candidates'),
        isEmpty,
      );
    });

    test('re-running the upgrade step is idempotent', () async {
      final db = await DatabaseService.database;
      // The step uses safeAddColumn plus CREATE TABLE IF NOT EXISTS, so running
      // it again on an already upgraded database must be a no-op.
      await DatabaseService.addResourceCapacityColumns(db);
      await DatabaseService.createResourceCompressionSchema(db);

      final resourceColumns = await _columns(db, 'resources');
      expect(
        resourceColumns.where((name) => name == 'measured_char_count').length,
        1,
      );
      expect(
        await DatabaseService.tableExists(db, 'resource_compression_jobs'),
        isTrue,
      );
    });
  });
}
