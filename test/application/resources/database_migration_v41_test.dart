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

/// Phase 9 tables, as declared by the frozen implementation plan.
const _phase9Tables = <String>[
  'resource_revisions',
  'resource_revision_nodes',
  'resource_autosaves',
  'resource_trash',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_v41_mig_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('Schema v41 fresh install', () {
    test('creates the revision, autosave and trash tables', () async {
      final db = await DatabaseService.database;

      expect(await _userVersion(db), DatabaseService.schemaVersion);
      // Pinned on purpose: a schema bump must force a conscious update here.
      expect(DatabaseService.schemaVersion, 45);

      final tables = await _tables(db);
      expect(tables, containsAll(_phase9Tables));
    });

    test('declares the columns each Phase 9 table needs', () async {
      final db = await DatabaseService.database;

      expect(
        await _columns(db, 'resource_revisions'),
        containsAll(<String>[
          'revision_id',
          'resource_id',
          'kind',
          'cause',
          'parent_revision_id',
          'content_hash',
          'node_count',
          'char_count',
          'label',
          'is_head',
          'created_at',
        ]),
      );
      expect(
        await _columns(db, 'resource_revision_nodes'),
        containsAll(<String>[
          'revision_id',
          'node_id',
          'node_kind',
          'parent_node_id',
          'title',
          'summary',
          'status',
          'sort_order',
          'content',
          'content_hash',
          'metadata_json',
          'is_removed',
        ]),
      );
      expect(
        await _columns(db, 'resource_autosaves'),
        containsAll(<String>[
          'checkpoint_id',
          'resource_id',
          'node_id',
          'node_kind',
          'content',
          'content_hash',
          'base_updated_at',
          'created_at',
          'updated_at',
        ]),
      );
      expect(
        await _columns(db, 'resource_trash'),
        containsAll(<String>[
          'trash_id',
          'resource_id',
          'node_id',
          'node_kind',
          'parent_node_id',
          'original_sort_order',
          'original_status',
          'original_title',
          'reason',
          'revision_id',
          'deleted_at',
          'expires_at',
          'restored_at',
          'restore_outcome',
          'metadata_json',
        ]),
      );
    });

    test('indexes the head pointer and the active-bin lookups', () async {
      final db = await DatabaseService.database;

      expect(
        await _indexes(db, 'resource_revisions'),
        containsAll(<String>[
          'idx_resource_revisions_resource',
          'idx_resource_revisions_head',
        ]),
      );
      expect(
        await _indexes(db, 'resource_revision_nodes'),
        contains('idx_resource_revision_nodes_node'),
      );
      expect(
        await _indexes(db, 'resource_autosaves'),
        containsAll(<String>[
          'idx_resource_autosaves_node',
          'idx_resource_autosaves_resource',
        ]),
      );
      expect(
        await _indexes(db, 'resource_trash'),
        containsAll(<String>[
          'idx_resource_trash_active_node',
          'idx_resource_trash_resource',
          'idx_resource_trash_expiry',
        ]),
      );
    });

    test('enforces at most one head per (resource, kind) in the database',
        () async {
      final db = await DatabaseService.database;
      await db.insert('resource_revisions', {
        'revision_id': 'rev_a',
        'resource_id': 'res_head',
        'kind': 'latestHead',
        'cause': 'manualSave',
        'content_hash': 'h1',
        'is_head': 1,
        'created_at': '2026-09-17T00:00:00.000',
      });

      // A second head for the same (resource, kind) is a database-level error,
      // not something a caller can talk its way past.
      await expectLater(
        db.insert('resource_revisions', {
          'revision_id': 'rev_b',
          'resource_id': 'res_head',
          'kind': 'latestHead',
          'cause': 'manualSave',
          'content_hash': 'h2',
          'is_head': 1,
          'created_at': '2026-09-17T00:00:01.000',
        }),
        throwsA(isA<DatabaseException>()),
      );

      // A different kind is a different head and stays legal.
      await db.insert('resource_revisions', {
        'revision_id': 'rev_c',
        'resource_id': 'res_head',
        'kind': 'assembly',
        'cause': 'migration',
        'content_hash': 'h1',
        'is_head': 1,
        'created_at': '2026-09-17T00:00:02.000',
      });
      final heads = await db.query(
        'resource_revisions',
        where: 'resource_id = ? AND is_head = 1',
        whereArgs: <Object?>['res_head'],
      );
      expect(heads, hasLength(2));
    });

    test('cascades revision-node deletion from its revision', () async {
      final db = await DatabaseService.database;
      await db.insert('resource_revisions', {
        'revision_id': 'rev_cascade',
        'resource_id': 'res_cascade',
        'kind': 'latestHead',
        'cause': 'generation',
        'content_hash': 'h',
        'is_head': 1,
        'created_at': '2026-09-17T00:00:00.000',
      });
      await db.insert('resource_revision_nodes', {
        'revision_id': 'rev_cascade',
        'node_id': 'part_1',
        'node_kind': 'part',
        'parent_node_id': 'sec_1',
        'title': '开场',
        'sort_order': 0,
        'content': '正文',
        'is_removed': 0,
      });

      await expectLater(
        db.insert('resource_revision_nodes', {
          'revision_id': 'rev_missing',
          'node_id': 'part_x',
          'node_kind': 'part',
          'is_removed': 0,
        }),
        throwsA(isA<DatabaseException>()),
      );

      await db.delete(
        'resource_revisions',
        where: 'revision_id = ?',
        whereArgs: <Object?>['rev_cascade'],
      );
      expect(
        await db.query(
          'resource_revision_nodes',
          where: 'revision_id = ?',
          whereArgs: <Object?>['rev_cascade'],
        ),
        isEmpty,
      );
    });
  });

  group('Migration v40 to v41', () {
    test('adds only the new tables and preserves existing data', () async {
      // Build a v40 database by hand: everything up to the lease columns.
      final path = '${tempDir.path}/v40.db';
      final v40 = await openDatabase(
        path,
        version: 40,
        onCreate: (db, version) async {
          await DatabaseService.createV40Schema(db);
          await db.execute('PRAGMA user_version = 40');
        },
      );
      expect(await _userVersion(v40), 40);

      await v40.insert('resources', {
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
      await v40.insert('resource_sections', {
        'id': 'sec_legacy',
        'resource_id': 'res_legacy',
        'title': '第一章',
        'sort_order': 0,
        'status': 'confirmed',
        'created_at': '2026-09-16T00:00:00.000',
        'updated_at': '2026-09-16T00:00:00.000',
      });
      await v40.insert('resource_parts', {
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
      await v40.close();

      final upgraded = await openDatabase(
        path,
        version: DatabaseService.schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onUpgrade: (db, oldVersion, newVersion) =>
            DatabaseService.migrateStepByStep(db, oldVersion, newVersion),
      );

      expect(await _userVersion(upgraded), 45);
      expect(await _tables(upgraded), containsAll(_phase9Tables));

      // Non-destructive: the pre-existing tree is byte-for-byte intact.
      final part = (await upgraded.query(
        'resource_parts',
        where: 'id = ?',
        whereArgs: <Object?>['part_legacy'],
      ))
          .single;
      expect(part['content'], '升级前的正文，必须逐字保留。');
      expect(part['content_hash'], 'legacy_hash');
      expect(part['status'], 'confirmed');
      final resource = (await upgraded.query(
        'resources',
        where: 'id = ?',
        whereArgs: <Object?>['res_legacy'],
      ))
          .single;
      expect(resource['name'], '升级前资源');
      expect(resource['metadata_json'], '{"k":"v"}');

      // New tables start empty, so an upgrade never invents history.
      for (final table in _phase9Tables) {
        expect(
          await upgraded.query(table),
          isEmpty,
          reason: '$table must start empty on upgrade',
        );
      }

      await upgraded.close();
    });

    test('is safe to run twice', () async {
      final path = '${tempDir.path}/v40_twice.db';
      final v40 = await openDatabase(
        path,
        version: 40,
        onCreate: (db, version) async {
          await DatabaseService.createV40Schema(db);
          await db.execute('PRAGMA user_version = 40');
        },
      );
      await v40.close();

      for (var attempt = 0; attempt < 2; attempt++) {
        final db = await openDatabase(path);
        await DatabaseService.migrateStepByStep(db, 40, 41);
        expect(await _tables(db), containsAll(_phase9Tables));
        await db.close();
      }
    });
  });
}
