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

/// The exact v49 `resource_blueprints` DDL: the frozen elastic snapshot exists
/// but `budget_policy_version` does not yet.
const String _v49BlueprintSchema = '''
  CREATE TABLE resource_blueprints (
    blueprint_id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    resource_type TEXT NOT NULL,
    suggested_name TEXT NOT NULL DEFAULT '',
    summary TEXT NOT NULL DEFAULT '',
    revision INTEGER NOT NULL DEFAULT 1,
    status TEXT NOT NULL DEFAULT 'draft',
    target_capacity INTEGER NOT NULL DEFAULT 0,
    elastic_percent INTEGER,
    blueprint_json TEXT NOT NULL DEFAULT '{}',
    resource_id TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_v50_mig_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('Schema v50 fresh install', () {
    test('resource_blueprints carries the non-null budget policy version',
        () async {
      final db = await DatabaseService.database;
      expect(await _userVersion(db), DatabaseService.schemaVersion);
      // Pinned on purpose: a schema bump must force a conscious update here.
      expect(DatabaseService.schemaVersion, 50);
      expect(await _columns(db, 'resource_blueprints'),
          contains('budget_policy_version'));
    });
  });

  group('Migration v49 to v50', () {
    test(
        'adds the version column and defaults legacy rows to the legacy policy',
        () async {
      final dbPath = '${tempDir.path}/adventures.db';
      final v49Db = await openDatabase(
        dbPath,
        version: 49,
        onCreate: (db, version) async {
          await db.execute(_v49BlueprintSchema);
          await db.execute('PRAGMA user_version = 49');
        },
      );
      expect(await _userVersion(v49Db), 49);
      await v49Db.insert('resource_blueprints', {
        'blueprint_id': 'bp_legacy_50',
        'session_id': 'sess_legacy',
        'resource_type': 'worldview',
        'revision': 1,
        'status': 'confirmed',
        'target_capacity': 50000,
        'elastic_percent': 50,
        'blueprint_json': '{}',
        'created_at': '2026-10-01T00:00:00.000',
        'updated_at': '2026-10-01T00:00:00.000',
      });
      await v49Db.close();

      final upgraded = await DatabaseService.database;
      expect(await _userVersion(upgraded), DatabaseService.schemaVersion);
      expect(await _columns(upgraded, 'resource_blueprints'),
          contains('budget_policy_version'));

      // The already-frozen row keeps the historical `min(..., A)` policy, so
      // upgrading never retroactively widens it to 75000.
      final legacyRows = await upgraded.query('resource_blueprints',
          where: 'blueprint_id = ?', whereArgs: ['bp_legacy_50']);
      expect(legacyRows, hasLength(1));
      expect(legacyRows.single['budget_policy_version'], 1);
      expect(legacyRows.single['elastic_percent'], 50);
      expect(legacyRows.single['target_capacity'], 50000);

      // A new row can persist the current policy version explicitly.
      await upgraded.insert('resource_blueprints', {
        'blueprint_id': 'bp_new_current',
        'session_id': 'sess_new',
        'resource_type': 'character',
        'revision': 1,
        'status': 'confirmed',
        'target_capacity': 20000,
        'elastic_percent': 50,
        'budget_policy_version': 2,
        'blueprint_json': '{}',
        'created_at': '2026-10-02T00:00:00.000',
        'updated_at': '2026-10-02T00:00:00.000',
      });
      final newRows = await upgraded.query('resource_blueprints',
          where: 'blueprint_id = ?', whereArgs: ['bp_new_current']);
      expect(newRows.single['budget_policy_version'], 2);

      // A row inserted without the column value defaults to legacy.
      await upgraded.insert('resource_blueprints', {
        'blueprint_id': 'bp_default',
        'session_id': 'sess_default',
        'resource_type': 'npc',
        'revision': 1,
        'status': 'confirmed',
        'target_capacity': 20000,
        'blueprint_json': '{}',
        'created_at': '2026-10-03T00:00:00.000',
        'updated_at': '2026-10-03T00:00:00.000',
      });
      final defaultRows = await upgraded.query('resource_blueprints',
          where: 'blueprint_id = ?', whereArgs: ['bp_default']);
      expect(defaultRows.single['budget_policy_version'], 1);
    });

    test('re-running the migration is idempotent', () async {
      final db = await DatabaseService.database;
      await DatabaseService.migrateStepByStep(db, 49, 50);
      await DatabaseService.migrateStepByStep(db, 49, 50);
      expect(await _columns(db, 'resource_blueprints'),
          contains('budget_policy_version'));
    });
  });
}
