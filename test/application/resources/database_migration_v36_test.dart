import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<List<String>> _columns(Database db, String table) async {
  final info = await db.rawQuery('PRAGMA table_info($table)');
  return info.map((r) => r['name'] as String).toList();
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
    tempDir = await Directory.systemTemp.createTemp('lt_v36_mig_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Schema v36 fresh install and migration', () {
    test('fresh install creates v36 tables and columns', () async {
      final db = await DatabaseService.database;
      expect(await _userVersion(db), DatabaseService.schemaVersion);
      expect(DatabaseService.schemaVersion, 36);

      expect(
        await DatabaseService.tableExists(db, 'resource_generation_attempts'),
        isTrue,
      );

      final attemptCols = await _columns(db, 'resource_generation_attempts');
      expect(
          attemptCols,
          containsAll(<String>[
            'attempt_id',
            'task_id',
            'generation_id',
            'part_id',
            'attempt_number',
            'status',
            'content_length',
            'error_message',
            'created_at',
            'updated_at',
          ]));

      final taskCols = await _columns(db, 'resource_generation_tasks');
      expect(
          taskCols,
          containsAll(<String>[
            'task_id',
            'blueprint_id',
            'resource_id',
            'section_id',
            'part_id',
            'prompt_goal',
            'estimated_length',
            'dependencies_json',
            'status',
            'sort_order',
            'current_attempt_id',
            'error_message',
            'created_at',
            'updated_at',
          ]));
    });

    test('migrates from v35 to v36 idempotently and preserves data', () async {
      final dbPath = '${tempDir.path}/adventures.db';
      final v35Db = await openDatabase(
        dbPath,
        version: 35,
        onCreate: (db, version) async {
          await DatabaseService.createV35Schema(db);
          await db.execute('PRAGMA user_version = 35');
        },
      );

      expect(await _userVersion(v35Db), 35);

      // Insert pre-existing v35 task
      await v35Db.insert('resource_generation_tasks', {
        'task_id': 'task_v35_1',
        'blueprint_id': 'bp_v35',
        'resource_id': 'res_v35',
        'section_id': 'sec_v35',
        'part_id': 'part_v35',
        'prompt_goal': '测试旧任务数据保留',
        'estimated_length': 1000,
        'dependencies_json': '[]',
        'status': 'pending',
        'sort_order': 0,
        'created_at': '2026-09-16T12:00:00.000',
        'updated_at': '2026-09-16T12:00:00.000',
      });

      await v35Db.close();

      // Open through DatabaseService triggers migrateStepByStep(v35 -> v36)
      final upgradedDb = await DatabaseService.database;
      expect(await _userVersion(upgradedDb), 36);

      // Verify resource_generation_attempts was created
      expect(
        await DatabaseService.tableExists(
            upgradedDb, 'resource_generation_attempts'),
        isTrue,
      );

      // Verify old task data is intact
      final rows = await upgradedDb.query(
        'resource_generation_tasks',
        where: 'task_id = ?',
        whereArgs: ['task_v35_1'],
      );
      expect(rows.length, 1);
      expect(rows.first['prompt_goal'], '测试旧任务数据保留');
      expect(rows.first['current_attempt_id'], '');
      expect(rows.first['error_message'], '');
    });
  });
}
