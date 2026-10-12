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

Future<void> _insertLegacyBlueprint(Database db,
    {required String id, int? elasticPercent}) async {
  await db.insert('resource_blueprints', {
    'blueprint_id': id,
    'session_id': 'sess_$id',
    'resource_type': 'character',
    'revision': 1,
    'status': 'confirmed',
    'target_capacity': 10000,
    if (elasticPercent != null) 'elastic_percent': elasticPercent,
    'blueprint_json': '{}',
    'created_at': '2026-10-01T00:00:00.000',
    'updated_at': '2026-10-01T00:00:00.000',
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_v49_mig_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('Schema v49 fresh install', () {
    test('creates resource_blueprints with the nullable snapshot column',
        () async {
      final db = await DatabaseService.database;
      expect(await _userVersion(db), DatabaseService.schemaVersion);
      // Pinned on purpose: a schema bump must force a conscious update here.
      expect(DatabaseService.schemaVersion, 49);
      expect(await _columns(db, 'resource_blueprints'),
          contains('elastic_percent'));
    });
  });

  group('Migration v48 to v49', () {
    test('adds the snapshot column and preserves legacy rows as NULL',
        () async {
      final dbPath = '${tempDir.path}/adventures.db';
      final v48Db = await openDatabase(
        dbPath,
        version: 48,
        onCreate: (db, version) async {
          await DatabaseService.createV44Schema(db);
          await DatabaseService.createRuntimeCheckpointSchema(db);
          await DatabaseService.createCreationLibrarySchema(db);
          await DatabaseService.createResourceCharacterRelationshipSchema(db);
          await db.execute('PRAGMA user_version = 48');
        },
      );
      expect(await _userVersion(v48Db), 48);
      await _insertLegacyBlueprint(v48Db, id: 'bp_legacy_20');
      await v48Db.close();

      final upgraded = await DatabaseService.database;
      expect(await _userVersion(upgraded), DatabaseService.schemaVersion);
      expect(await _columns(upgraded, 'resource_blueprints'),
          contains('elastic_percent'));

      // The historical row survives with a NULL snapshot: it must keep the
      // frozen PR #5 20% semantics, never adopt a later global value.
      final legacyRows = await upgraded.query('resource_blueprints',
          where: 'blueprint_id = ?', whereArgs: ['bp_legacy_20']);
      expect(legacyRows, hasLength(1));
      expect(legacyRows.single['elastic_percent'], isNull);
      expect(legacyRows.single['target_capacity'], 10000);

      // New rows can persist a frozen snapshot value.
      await _insertLegacyBlueprint(upgraded,
          id: 'bp_new_50', elasticPercent: 50);
      final newRows = await upgraded.query('resource_blueprints',
          where: 'blueprint_id = ?', whereArgs: ['bp_new_50']);
      expect(newRows.single['elastic_percent'], 50);
    });

    test('re-running the migration is idempotent', () async {
      final db = await DatabaseService.database;
      await DatabaseService.migrateStepByStep(db, 48, 49);
      await DatabaseService.migrateStepByStep(db, 48, 49);
      expect(await _columns(db, 'resource_blueprints'),
          contains('elastic_percent'));
    });
  });
}
