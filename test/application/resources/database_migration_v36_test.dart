import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<List<String>> _columns(Database db, String table) async {
  final info = await db.rawQuery('PRAGMA table_info($table)');
  return info.map((r) => r['name'] as String).toList();
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

  group('Schema v37 install and migration', () {
    test('fresh install creates v37 tables and columns', () async {
      final db = await DatabaseService.database;
      expect(await _userVersion(db), DatabaseService.schemaVersion);
      // Pinned on purpose: bumping the schema version must force a conscious
      // update here (and in database_migration_v38_test.dart) instead of
      // silently passing with a ">= old version" check.
      // v40 added the compression worker lease columns.
      expect(DatabaseService.schemaVersion, 46);

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

      expect(
        await DatabaseService.tableExists(db, 'resource_generation_sessions'),
        isTrue,
      );
      final sessionCols = await _columns(db, 'resource_generation_sessions');
      expect(
        sessionCols,
        containsAll(<String>[
          'session_id',
          'resource_id',
          'blueprint_id',
          'creation_session_id',
          'status',
          'current_part_id',
          'current_task_id',
          'current_attempt_id',
          'completed_parts_count',
          'total_parts_count',
          'error_message',
          'created_at',
          'updated_at',
        ]),
      );
      expect(
        await _indexes(db, 'resource_generation_sessions'),
        containsAll(<String>[
          'idx_gen_sessions_resource',
          'idx_gen_sessions_blueprint',
          'idx_gen_sessions_status',
          'idx_gen_sessions_active_resource',
        ]),
      );
    });

    test('migrates from v36 to v37 and preserves existing generation data',
        () async {
      final dbPath = '${tempDir.path}/adventures.db';
      final v36Db = await openDatabase(
        dbPath,
        version: 36,
        onCreate: (db, version) async {
          await DatabaseService.createV36Schema(db);
          await db.execute('PRAGMA user_version = 36');
        },
      );

      expect(await _userVersion(v36Db), 36);

      // Insert pre-existing v36 task.
      await v36Db.insert('resource_generation_tasks', {
        'task_id': 'task_v36_1',
        'blueprint_id': 'bp_v36',
        'resource_id': 'res_v36',
        'section_id': 'sec_v36',
        'part_id': 'part_v36',
        'prompt_goal': '测试旧任务数据保留',
        'estimated_length': 1000,
        'dependencies_json': '[]',
        'status': 'pending',
        'sort_order': 0,
        'created_at': '2026-09-16T12:00:00.000',
        'updated_at': '2026-09-16T12:00:00.000',
      });

      await v36Db.close();

      // Open through DatabaseService triggers migrateStepByStep(v36 -> latest).
      final upgradedDb = await DatabaseService.database;
      expect(await _userVersion(upgradedDb), DatabaseService.schemaVersion);

      // Verify resource_generation_attempts was created
      expect(
        await DatabaseService.tableExists(
            upgradedDb, 'resource_generation_attempts'),
        isTrue,
      );
      expect(
        await DatabaseService.tableExists(
            upgradedDb, 'resource_generation_sessions'),
        isTrue,
      );
      expect(
        await _indexes(upgradedDb, 'resource_generation_sessions'),
        contains('idx_gen_sessions_active_resource'),
      );

      // Verify old task data is intact
      final rows = await upgradedDb.query(
        'resource_generation_tasks',
        where: 'task_id = ?',
        whereArgs: ['task_v36_1'],
      );
      expect(rows.length, 1);
      expect(rows.first['prompt_goal'], '测试旧任务数据保留');
      expect(rows.first['current_attempt_id'], '');
      expect(rows.first['error_message'], '');
    });
  });
}
