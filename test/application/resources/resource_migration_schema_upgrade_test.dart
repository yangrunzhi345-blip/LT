import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Phase 2 moves the schema from v31 to v32 (the migration audit table).
///
/// A real v31 database must upgrade in place, keep every legacy row, and end up
/// with the same audit schema a fresh install gets.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_phase2_schema_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('fresh install is already at v32 with the audit table', () async {
    final db = await DatabaseService.database;
    expect(await _userVersion(db), DatabaseService.schemaVersion);
    expect(
      await DatabaseService.tableExists(db, 'resource_migration_records'),
      isTrue,
    );
    // The tree from v31 must still be there.
    for (final table in const [
      'resources',
      'resource_sections',
      'resource_parts',
    ]) {
      expect(await DatabaseService.tableExists(db, table), isTrue);
    }
  });

  test('a v31 database upgrades in place and keeps its legacy rows', () async {
    final fixtureDir = await _v31FixtureWithLegacyRows();
    DatabaseService.customDbDir = fixtureDir.path;
    await DatabaseService.resetDatabase();

    final db = await DatabaseService.database;

    expect(await _userVersion(db), DatabaseService.schemaVersion);
    expect(
      await DatabaseService.tableExists(db, 'resource_migration_records'),
      isTrue,
    );

    // Legacy data is untouched by the schema upgrade itself.
    final worlds = await db.query('worldview_presets');
    expect(worlds, hasLength(1));
    expect(worlds.first['id'], 'wv_v31');
    expect(worlds.first['detail_json'],
        '{"modules":{"overview":{"summary":"v31 世界观","status":"confirmed"}}}');

    // And no audit record exists yet: the upgrade only adds the table.
    final records = await db.query('resource_migration_records');
    expect(records, isEmpty);

    await db.close();
    fixtureDir.deleteSync(recursive: true);
  });

  test('the upgraded audit schema matches a fresh install', () async {
    final fixtureDir = await _v31FixtureWithLegacyRows();
    DatabaseService.customDbDir = fixtureDir.path;
    await DatabaseService.resetDatabase();
    final upgraded = await _auditSignature(await DatabaseService.database);
    await DatabaseService.resetDatabase();

    final freshDir = await Directory.systemTemp.createTemp('lt_phase2_fresh_');
    DatabaseService.customDbDir = freshDir.path;
    await DatabaseService.resetDatabase();
    final fresh = await _auditSignature(await DatabaseService.database);
    await DatabaseService.resetDatabase();

    expect(upgraded, equals(fresh));

    fixtureDir.deleteSync(recursive: true);
    freshDir.deleteSync(recursive: true);
  });
}

/// Builds a real v31 database that already holds a legacy worldview.
Future<Directory> _v31FixtureWithLegacyRows() async {
  final dir = await Directory.systemTemp.createTemp('lt_phase2_v31_');
  final db = await openDatabase(
    p.join(dir.path, 'adventures.db'),
    version: 31,
    onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
    onCreate: (db, version) async {
      await DatabaseService.createV31Schema(db);
      await DatabaseService.createCreationLibrarySchema(db);
    },
  );
  await db.insert('worldview_presets', {
    'id': 'wv_v31',
    'name': 'v31 世界观',
    'description': '描述',
    'entries_json': '[]',
    'detail_json':
        '{"modules":{"overview":{"summary":"v31 世界观","status":"confirmed"}}}',
    'created_at': '2026-09-15T00:00:00.000',
    'updated_at': '2026-09-15T00:00:00.000',
  });
  expect(await _userVersion(db), 31);
  await db.close();
  return dir;
}

Future<Map<String, Object?>> _auditSignature(Database db) async {
  final columns = await db.rawQuery(
    'PRAGMA table_info(resource_migration_records)',
  );
  final indexes = await db.rawQuery(
    'PRAGMA index_list(resource_migration_records)',
  );
  return <String, Object?>{
    'user_version': await _userVersion(db),
    'columns': (columns.map((column) => column['name'].toString()).toList()
      ..sort()),
    'indexes': (indexes
        .map((index) => index['name'].toString())
        .where((name) => !name.startsWith('sqlite_'))
        .toList()
      ..sort()),
  };
}

Future<int> _userVersion(Database db) async {
  final rows = await db.rawQuery('PRAGMA user_version');
  return (rows.first.values.first as num).toInt();
}
