import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
    tempDir = await Directory.systemTemp.createTemp('lt_v38_mig_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('Schema v38 fresh install', () {
    test('creates the section validation columns with safe defaults', () async {
      final db = await DatabaseService.database;
      expect(await _userVersion(db), DatabaseService.schemaVersion);
      // Pinned on purpose: a schema bump must force a conscious update here.
      // v40 added the compression worker lease columns.
      expect(DatabaseService.schemaVersion, 42);

      final columns = await _columns(db, 'resource_sections');
      expect(
        columns,
        containsAll(<String>[
          'validation_state',
          'validation_message',
          'validated_at',
        ]),
      );

      await db.insert('resources', {
        'id': 'res_v38_fresh',
        'type': 'worldview',
        'name': 'R',
        'summary': '',
        'status': 'draft',
        'metadata_json': '{}',
        'schema_version': 1,
        'created_at': '2026-09-17T00:00:00.000',
        'updated_at': '2026-09-17T00:00:00.000',
      });
      await db.insert('resource_sections', {
        'id': 'sec_v38_fresh',
        'resource_id': 'res_v38_fresh',
        'title': 'S',
        'summary': '',
        'sort_order': 0,
        'status': 'draft',
        'created_at': '2026-09-17T00:00:00.000',
        'updated_at': '2026-09-17T00:00:00.000',
      });

      final rows = await db.query(
        'resource_sections',
        where: 'id = ?',
        whereArgs: ['sec_v38_fresh'],
      );
      expect(rows.single['validation_state'], 'unvalidated');
      expect(rows.single['validation_message'], '');
      expect(rows.single['validated_at'], isNull);
    });
  });

  group('Migration v37 to v38', () {
    test('adds the columns and preserves existing section rows', () async {
      final dbPath = '${tempDir.path}/adventures.db';
      final v37Db = await openDatabase(
        dbPath,
        version: 37,
        onCreate: (db, version) async {
          await DatabaseService.createV37Schema(db);
          await db.execute('PRAGMA user_version = 37');
        },
      );
      expect(await _userVersion(v37Db), 37);

      await v37Db.insert('resources', {
        'id': 'res_v37',
        'type': 'character',
        'name': '旧资源',
        'summary': '',
        'status': 'draft',
        'metadata_json': '{}',
        'schema_version': 1,
        'created_at': '2026-09-16T00:00:00.000',
        'updated_at': '2026-09-16T00:00:00.000',
      });
      await v37Db.insert('resource_sections', {
        'id': 'sec_v37',
        'resource_id': 'res_v37',
        'title': '旧章节',
        'summary': '旧摘要',
        'sort_order': 3,
        'status': 'draft',
        'created_at': '2026-09-16T00:00:00.000',
        'updated_at': '2026-09-16T00:00:00.000',
      });
      await v37Db.close();

      final upgraded = await DatabaseService.database;
      // The v38 columns must survive the upgrade; the database itself moves to
      // whatever the current schema is (v39 added Phase 8 capacity tables).
      expect(await _userVersion(upgraded), DatabaseService.schemaVersion);
      expect(
        await _columns(upgraded, 'resource_sections'),
        containsAll(<String>[
          'validation_state',
          'validation_message',
          'validated_at',
        ]),
      );

      final rows = await upgraded.query(
        'resource_sections',
        where: 'id = ?',
        whereArgs: ['sec_v37'],
      );
      expect(rows, hasLength(1));
      expect(rows.single['title'], '旧章节');
      expect(rows.single['summary'], '旧摘要');
      expect(rows.single['sort_order'], 3);
      expect(rows.single['validation_state'], 'unvalidated');
      expect(rows.single['updated_at'], '2026-09-16T00:00:00.000');
    });

    test('re-running the column step is idempotent', () async {
      final db = await DatabaseService.database;
      await DatabaseService.addSectionControlColumns(db);
      await DatabaseService.addSectionControlColumns(db);
      expect(
        await _columns(db, 'resource_sections'),
        containsAll(<String>['validation_state', 'validation_message']),
      );
    });
  });
}
