import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Phase 1 adds database v31 (the unified Resource → Section → Part tree).
///
/// These tests pin the three properties Phase 1 must guarantee:
/// a fresh install and a v30 upgrade produce the same tree schema, the
/// migration is re-runnable, and no legacy resource data is touched or moved.
const List<String> _treeTables = [
  'resources',
  'resource_sections',
  'resource_parts',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_tree_migration_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('fresh install (v31)', () {
    test('creates the three tree tables with the frozen columns', () async {
      final db = await DatabaseService.database;

      expect(await _userVersion(db), 31);
      for (final table in _treeTables) {
        expect(
          await DatabaseService.tableExists(db, table),
          isTrue,
          reason: '$table must exist after a fresh install',
        );
      }

      expect(
        await _columns(db, 'resources'),
        containsAll(<String>[
          'id',
          'type',
          'name',
          'summary',
          'status',
          'metadata_json',
          'schema_version',
          'created_at',
          'updated_at',
          'deleted_at',
        ]),
      );
      expect(
        await _columns(db, 'resource_sections'),
        containsAll(<String>[
          'id',
          'resource_id',
          'title',
          'summary',
          'sort_order',
          'status',
          'created_at',
          'updated_at',
          'deleted_at',
        ]),
      );
      expect(
        await _columns(db, 'resource_parts'),
        containsAll(<String>[
          'id',
          'section_id',
          'title',
          'content',
          'sort_order',
          'status',
          'content_hash',
          'created_at',
          'updated_at',
          'deleted_at',
        ]),
      );
    });

    test('never adds a whole-resource body column', () async {
      final db = await DatabaseService.database;

      // Body text belongs to parts only: no giant JSON column anywhere.
      for (final table in const ['resources', 'resource_sections']) {
        final columns = await _columns(db, table);
        expect(
          columns.where((column) => column.contains('content')),
          isEmpty,
          reason: '$table must not carry body text',
        );
      }
      expect(await _columns(db, 'resource_parts'), contains('content'));
    });

    test('creates the ordering indexes used by tree reads', () async {
      final db = await DatabaseService.database;

      expect(
        await _indexes(db, 'resource_sections'),
        contains('idx_resource_sections_parent'),
      );
      expect(
        await _indexes(db, 'resource_parts'),
        contains('idx_resource_parts_parent'),
      );
      expect(
        await _indexes(db, 'resources'),
        contains('idx_resources_type_updated'),
      );
    });
  });

  group('v30 → v31 upgrade', () {
    test('upgrades in place, preserves legacy rows and migrates nothing',
        () async {
      final fixtureDir = await _v30FixtureWithLegacyData();
      DatabaseService.customDbDir = fixtureDir.path;
      await DatabaseService.resetDatabase();

      final db = await DatabaseService.database;

      expect(await _userVersion(db), 31);
      for (final table in _treeTables) {
        expect(await DatabaseService.tableExists(db, table), isTrue);
      }

      // Legacy resource tables are untouched...
      final worlds = await db.query('worldview_presets');
      expect(worlds, hasLength(1));
      expect(worlds.first['id'], 'wv_legacy');
      expect(worlds.first['detail_json'], '{"modules":{"overview":"旧世界观"}}');

      final cards = await db.query('character_cards');
      expect(cards, hasLength(1));
      expect(cards.first['id'], 'card_legacy');
      expect(cards.first['json_data'], '{"data":{"description":"旧角色"}}');

      // ...and nothing was copied into the new tree: legacy migration is
      // Phase 2, so the tree must still be empty.
      for (final table in _treeTables) {
        final count = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
        expect(
          (count.first['c'] as num).toInt(),
          0,
          reason: '$table must stay empty; Phase 1 does not migrate data',
        );
      }

      await db.close();
      fixtureDir.deleteSync(recursive: true);
    });

    test('produces the same tree schema as a fresh install', () async {
      final fixtureDir = await _v30FixtureWithLegacyData();
      DatabaseService.customDbDir = fixtureDir.path;
      await DatabaseService.resetDatabase();
      final upgraded = await _treeSignature(await DatabaseService.database);
      await DatabaseService.resetDatabase();

      final freshDir = await Directory.systemTemp.createTemp('lt_tree_fresh_');
      DatabaseService.customDbDir = freshDir.path;
      await DatabaseService.resetDatabase();
      final fresh = await _treeSignature(await DatabaseService.database);
      await DatabaseService.resetDatabase();

      expect(upgraded, equals(fresh));

      fixtureDir.deleteSync(recursive: true);
      freshDir.deleteSync(recursive: true);
    });

    test('migrateStepByStep is re-runnable without breaking the schema',
        () async {
      final fixtureDir = await _v30FixtureWithLegacyData();
      DatabaseService.customDbDir = fixtureDir.path;
      await DatabaseService.resetDatabase();

      final db = await DatabaseService.database;
      final before = await _treeSignature(db);

      // Replaying the same step must not throw and must not change anything.
      await DatabaseService.migrateStepByStep(db, 30, 31);
      await DatabaseService.migrateStepByStep(db, 30, 31);

      expect(await _treeSignature(db), equals(before));
      final worlds = await db.query('worldview_presets');
      expect(worlds, hasLength(1));

      await db.close();
      fixtureDir.deleteSync(recursive: true);
    });
  });
}

/// Builds a real v30 database file that already holds legacy resource rows.
Future<Directory> _v30FixtureWithLegacyData() async {
  final dir = await Directory.systemTemp.createTemp('lt_tree_v30_');
  final db = await openDatabase(
    p.join(dir.path, 'adventures.db'),
    version: 30,
    onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
    onCreate: (db, version) async {
      await DatabaseService.createV30Schema(db);
      await DatabaseService.createCreationLibrarySchema(db);
    },
  );

  await db.insert('worldview_presets', {
    'id': 'wv_legacy',
    'name': '旧世界观',
    'description': '描述',
    'entries_json': '[]',
    'detail_json': '{"modules":{"overview":"旧世界观"}}',
    'created_at': '2026-09-15T00:00:00.000',
    'updated_at': '2026-09-15T00:00:00.000',
  });
  await db.insert('character_cards', {
    'id': 'card_legacy',
    'name': '旧角色',
    'json_data': '{"data":{"description":"旧角色"}}',
    'source': 'legacy',
    'created_at': '2026-09-15T00:00:00.000',
    'updated_at': '2026-09-15T00:00:00.000',
  });

  expect(await _userVersion(db), 30);
  await db.close();
  return dir;
}

/// Normalized schema signature of the Phase 1 tables.
Future<Map<String, Object?>> _treeSignature(Database db) async {
  final signature = <String, Object?>{'user_version': await _userVersion(db)};
  for (final table in _treeTables) {
    final columns = (await _columns(db, table)).toList()..sort();
    final indexes = (await _indexes(db, table)).toList()..sort();
    signature[table] = {'columns': columns, 'indexes': indexes};
  }
  return signature;
}

Future<int> _userVersion(Database db) async {
  final rows = await db.rawQuery('PRAGMA user_version');
  return (rows.first.values.first as num).toInt();
}

Future<Set<String>> _columns(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.map((row) => row['name'].toString()).toSet();
}

Future<List<String>> _indexes(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA index_list($table)');
  return rows
      .map((row) => row['name'].toString())
      .where((name) => !name.startsWith('sqlite_'))
      .toList();
}
