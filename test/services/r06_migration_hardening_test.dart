import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<int> _pragmaInt(Database db, String pragma) async {
  final rows = await db.rawQuery('PRAGMA $pragma');
  return (rows.single.values.single as num).toInt();
}

Future<bool> _tableExists(Database db, String table) async =>
    DatabaseService.tableExists(db, table);

Future<Database> _createV42Fixture(String path) {
  return openDatabase(
    path,
    version: 42,
    onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    onCreate: (db, version) async {
      await DatabaseService.createV42Schema(db);
      await db.execute('CREATE TABLE quests (id TEXT PRIMARY KEY)');
      await db.execute('PRAGMA user_version = 42');
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_r06_migration_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('R06 migration hardening', () {
    test('A1 keeps foreign keys enabled after opening', () async {
      final db = await DatabaseService.database;

      expect(await _pragmaInt(db, 'foreign_keys'), 1);
    });

    test('A2 and A3 preserve parent-child behavior across v42 upgrade',
        () async {
      final path = '${tempDir.path}/adventures.db';
      final fixture = await _createV42Fixture(path);
      await fixture.insert('resources', {
        'id': 'resource-a',
        'type': 'worldview',
        'name': 'fixture',
        'created_at': '2026-09-19T00:00:00.000',
        'updated_at': '2026-09-19T00:00:00.000',
      });
      await fixture.insert('resource_sections', {
        'id': 'section-a',
        'resource_id': 'resource-a',
        'created_at': '2026-09-19T00:00:00.000',
        'updated_at': '2026-09-19T00:00:00.000',
      });
      await fixture.close();

      final upgraded = await DatabaseService.database;

      expect(await _pragmaInt(upgraded, 'foreign_keys'), 1);
      await expectLater(
        upgraded.insert('resource_sections', {
          'id': 'orphan',
          'resource_id': 'missing',
          'created_at': '2026-09-19T00:00:00.000',
          'updated_at': '2026-09-19T00:00:00.000',
        }),
        throwsA(isA<DatabaseException>()),
      );
      await upgraded.delete(
        'resources',
        where: 'id = ?',
        whereArgs: ['resource-a'],
      );
      expect(
        await upgraded.query(
          'resource_sections',
          where: 'id = ?',
          whereArgs: ['section-a'],
        ),
        isEmpty,
      );
      await DatabaseService.resetDatabase();
    });

    test('A4 and A5 rollback a failed upgrade and recover on reopen', () async {
      final path = '${tempDir.path}/v42_failure.db';
      final fixture = await _createV42Fixture(path);
      await fixture.close();

      await expectLater(
        openDatabase(
          path,
          version: DatabaseService.schemaVersion,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onUpgrade: (db, oldVersion, newVersion) async {
            await DatabaseService.migrateStepByStep(
              db,
              oldVersion,
              newVersion,
            );
            await db.execute('CREATE TABLE injected_partial (id INTEGER)');
            throw StateError('injected migration failure');
          },
        ),
        throwsA(isA<StateError>()),
      );

      final afterFailure = await openDatabase(path);
      expect(await _pragmaInt(afterFailure, 'user_version'), 42);
      expect(await _tableExists(afterFailure, 'quests'), isTrue);
      expect(await _tableExists(afterFailure, 'injected_partial'), isFalse);
      await afterFailure.close();

      final recovered = await openDatabase(
        path,
        version: DatabaseService.schemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onUpgrade: DatabaseService.migrateStepByStep,
      );
      expect(await _pragmaInt(recovered, 'user_version'), 43);
      expect(await _tableExists(recovered, 'quests'), isFalse);
      expect(await _pragmaInt(recovered, 'foreign_keys'), 1);
      await recovered.close();
    });

    test('repeating the v42 migration is a deterministic no-op', () async {
      final path = '${tempDir.path}/v42_repeat.db';
      final fixture = await _createV42Fixture(path);

      await DatabaseService.migrateStepByStep(fixture, 42, 43);
      final tablesAfterFirst = await fixture.rawQuery(
        "SELECT name, sql FROM sqlite_master WHERE type = 'table' ORDER BY name",
      );
      await DatabaseService.migrateStepByStep(fixture, 42, 43);
      final tablesAfterSecond = await fixture.rawQuery(
        "SELECT name, sql FROM sqlite_master WHERE type = 'table' ORDER BY name",
      );

      expect(tablesAfterSecond, tablesAfterFirst);
      expect(await _tableExists(fixture, 'quests'), isFalse);
      await fixture.close();
    });
  });
}
