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

Future<bool> _tableExists(Database db, String table) async {
  final rows = await db.rawQuery(
    "SELECT count(*) AS cnt FROM sqlite_master "
    "WHERE type='table' AND name=?",
    <Object?>[table],
  );
  return (rows.first['cnt'] as int) > 0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_v51_mig_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('Schema v51 fresh install', () {
    test('setting cards table and migration marker exist', () async {
      final db = await DatabaseService.database;

      expect(await _userVersion(db), DatabaseService.schemaVersion);
      // Pinned on purpose: a schema bump must force a conscious update here.
      expect(DatabaseService.schemaVersion, 51);
      expect(
        await _columns(db, 'setting_cards'),
        containsAll(<String>[
          'id',
          'kind',
          'name',
          'summary',
          'content',
          'status',
          'origin',
          'mode',
          'origin_worldview_id',
          'metadata_json',
          'legacy_id',
          'created_at',
          'updated_at',
          'deleted_at',
        ]),
      );
      expect(await _tableExists(db, 'setting_card_migration_state'), isTrue);
    });
  });

  group('Migration v50 to v51', () {
    test('adds the lightweight setting card table', () async {
      final dbPath = '${tempDir.path}/adventures.db';
      final v50Db = await openDatabase(
        dbPath,
        version: 50,
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE legacy_marker (id TEXT)');
        },
      );
      expect(await _userVersion(v50Db), 50);
      expect(await _tableExists(v50Db, 'setting_cards'), isFalse);
      await v50Db.close();

      final upgraded = await DatabaseService.database;

      expect(await _userVersion(upgraded), 51);
      expect(await _tableExists(upgraded, 'setting_cards'), isTrue);
      expect(
        await _columns(upgraded, 'setting_cards'),
        contains('legacy_id'),
      );
    });

    test('re-running the migration is idempotent', () async {
      final db = await DatabaseService.database;
      await DatabaseService.migrateStepByStep(db, 50, 51);
      await DatabaseService.migrateStepByStep(db, 50, 51);
      expect(await _tableExists(db, 'setting_cards'), isTrue);
    });
  });
}
