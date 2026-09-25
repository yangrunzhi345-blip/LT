import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<List<String>> _columns(Database db, String table) async {
  final info = await db.rawQuery('PRAGMA table_info($table)');
  return info.map((row) => row['name'] as String).toList();
}

Future<List<String>> _indexes(Database db, String table) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name=?",
    <Object?>[table],
  );
  return rows.map((row) => row['name'] as String).toList();
}

Future<List<String>> _tables(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table'",
  );
  return rows.map((row) => row['name'] as String).toList();
}

Future<int> _userVersion(Database db) async {
  final rows = await db.rawQuery('PRAGMA user_version');
  return (rows.first.values.first as num).toInt();
}

const _phase10Tables = <String>[
  'resource_assembly_readiness',
  'resource_assembly_entries',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_v42_mig_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('Schema v46 fresh install', () {
    test('creates the readiness and assembly index tables', () async {
      final db = await DatabaseService.database;

      expect(await _userVersion(db), DatabaseService.schemaVersion);
      // Pinned on purpose: a schema bump must force a conscious update here.
      expect(DatabaseService.schemaVersion, 46);
      expect(await _columns(db, 'scene_runtime_state'), contains('revision'));
      expect(
        await _columns(db, 'resource_creation_sessions'),
        contains('target_characters'),
      );

      expect(await _tables(db), containsAll(_phase10Tables));
    });

    test('declares every column the readiness table needs', () async {
      final db = await DatabaseService.database;

      expect(
        await _columns(db, 'resource_assembly_readiness'),
        containsAll(<String>[
          'resource_id',
          'target_revision_id',
          'target_content_hash',
          'state',
          'assembly_revision_id',
          'assembly_content_hash',
          'attempt_token',
          'validation_message',
          'failure_reason',
          'started_at',
          'completed_at',
          'updated_at',
        ]),
      );
      expect(
        await _columns(db, 'resource_assembly_entries'),
        containsAll(<String>[
          'entry_id',
          'resource_id',
          'revision_id',
          'revision_content_hash',
          'keys_json',
          'content',
          'insertion_order',
          'sticky',
          'created_at',
        ]),
      );
      // Revision provenance on world entries (Phase 10).
      expect(
        await _columns(db, 'world_entries'),
        contains('source_revision_id'),
      );
    });

    test('declares the state and revision indexes', () async {
      final db = await DatabaseService.database;

      final readinessIndexes =
          await _indexes(db, 'resource_assembly_readiness');
      expect(
        readinessIndexes,
        contains('idx_resource_assembly_readiness_state'),
      );
      final entryIndexes = await _indexes(db, 'resource_assembly_entries');
      expect(entryIndexes, contains('idx_resource_assembly_entries_rev'));
    });
  });

  group('Migration v41 to v46', () {
    test('adds only the new tables and preserves existing data', () async {
      // Build a v41 database by hand: everything up to the Phase 9 tables.
      final path = '${tempDir.path}/v41.db';
      final v41 = await openDatabase(
        path,
        version: 41,
        onCreate: (db, version) async {
          await DatabaseService.createV41Schema(db);
          await db.execute('PRAGMA user_version = 41');
        },
      );
      expect(await _userVersion(v41), 41);

      await v41.insert('resources', {
        'id': 'res_legacy',
        'type': 'worldview',
        'name': '升级前资源',
        'summary': '摘要',
        'status': 'confirmed',
        'metadata_json': '{"k":"v"}',
        'schema_version': 1,
        'created_at': '2026-09-16T00:00:00.000',
        'updated_at': '2026-09-16T00:00:00.000',
      });
      await v41.insert('resource_parts', {
        'id': 'part_legacy',
        'section_id': 'sec_legacy',
        'title': '开场',
        'content': '升级前的正文，必须逐字保留。',
        'content_hash': 'legacy_hash',
        'sort_order': 0,
        'status': 'confirmed',
        'created_at': '2026-09-16T00:00:00.000',
        'updated_at': '2026-09-16T00:00:00.000',
      });
      await v41.close();

      final upgraded = await openDatabase(
        path,
        version: DatabaseService.schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onUpgrade: (db, oldVersion, newVersion) =>
            DatabaseService.migrateStepByStep(db, oldVersion, newVersion),
      );

      expect(await _userVersion(upgraded), 46);
      expect(
        await _columns(upgraded, 'resource_creation_sessions'),
        contains('target_characters'),
      );
      expect(await _tables(upgraded), containsAll(_phase10Tables));

      // Non-destructive: the pre-existing tree is byte-for-byte intact.
      final part = (await upgraded.query(
        'resource_parts',
        where: 'id = ?',
        whereArgs: <Object?>['part_legacy'],
        limit: 1,
      ));
      expect(part, hasLength(1));
      expect(part.first['content'], '升级前的正文，必须逐字保留。');

      // New tables start empty.
      expect(await upgraded.query('resource_assembly_readiness'), isEmpty);
      expect(await upgraded.query('resource_assembly_entries'), isEmpty);
      await upgraded.close();
    });

    test('is idempotent when the migration runs twice', () async {
      final path = '${tempDir.path}/v41_twice.db';
      var opened = await openDatabase(
        path,
        version: 41,
        onCreate: (db, version) async {
          await DatabaseService.createV41Schema(db);
          await db.execute('PRAGMA user_version = 41');
        },
      );
      await opened.close();

      Future<Database> upgrade() => openDatabase(
            path,
            version: DatabaseService.schemaVersion,
            onUpgrade: (db, oldVersion, newVersion) =>
                DatabaseService.migrateStepByStep(db, oldVersion, newVersion),
          );

      opened = await upgrade();
      await opened.close();
      // Second pass over an already-v46 file must not fail.
      opened = await upgrade();

      expect(await _userVersion(opened), 46);
      expect(await _tables(opened), containsAll(_phase10Tables));
      await opened.close();
    });

    test('upgrades an existing v42 database and removes legacy tables',
        () async {
      final path = '${tempDir.path}/v42_legacy.db';
      var v42 = await openDatabase(
        path,
        version: 42,
        onCreate: (db, version) async {
          await DatabaseService.createV42Schema(db);
          await db.execute('CREATE TABLE quests (id TEXT PRIMARY KEY)');
          await db.execute('CREATE TABLE map_nodes (id TEXT PRIMARY KEY)');
          await db.execute(
            'CREATE TABLE map_connections (id TEXT PRIMARY KEY)',
          );
          await db.insert('resources', {
            'id': 'v42_resource',
            'type': 'worldview',
            'name': '保留资源',
            'summary': 'v42 数据',
            'status': 'confirmed',
            'metadata_json': '{}',
            'schema_version': 1,
            'created_at': '2026-09-18T00:00:00.000',
            'updated_at': '2026-09-18T00:00:00.000',
          });
          await db.execute('PRAGMA user_version = 42');
        },
      );
      expect(await _userVersion(v42), 42);
      expect(
        await _tables(v42),
        containsAll(<String>['quests', 'map_nodes', 'map_connections']),
      );
      await v42.close();

      Future<Database> openCurrent() => openDatabase(
            path,
            version: DatabaseService.schemaVersion,
            onUpgrade: (db, oldVersion, newVersion) =>
                DatabaseService.migrateStepByStep(db, oldVersion, newVersion),
          );

      var upgraded = await openCurrent();
      expect(await _userVersion(upgraded), 46);
      final tables = await _tables(upgraded);
      expect(tables, isNot(contains('quests')));
      expect(tables, isNot(contains('map_nodes')));
      expect(tables, isNot(contains('map_connections')));
      expect(tables, contains('resources'));
      expect(
        await upgraded.query(
          'resources',
          where: 'id = ?',
          whereArgs: ['v42_resource'],
        ),
        hasLength(1),
      );
      await upgraded.close();

      upgraded = await openCurrent();
      expect(await _userVersion(upgraded), 46);
      expect(await _tables(upgraded), isNot(contains('quests')));
      await DatabaseService.dropLegacyQuestAndMapTables(upgraded);
      await upgraded.close();
    });
  });
}
