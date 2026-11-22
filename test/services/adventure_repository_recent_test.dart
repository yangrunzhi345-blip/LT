import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/legacy_tombstone_store.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/game_state.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/models/scene_state.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  group('AdventureRepositoryImpl recent adventures', () {
    late Directory directory;
    late Database db;
    late AdventureRepositoryImpl repository;
    late LegacyTombstoneStore tombstones;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('lt_recent_adventure_');
      DatabaseService.customDbDir = directory.path;
      await DatabaseService.resetDatabase();
      db = await DatabaseService.database;
      tombstones = LegacyTombstoneStore(getDb: () async => db);
      repository = AdventureRepositoryImpl(
        getDb: () async => db,
        tombstoneStore: tombstones,
      );
    });

    tearDown(() async {
      await DatabaseService.resetDatabase();
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    Future<int> seed(String title, String created, {String updated = ''}) =>
        db.insert('adventures', {
          'title': title,
          'created_at': created,
          'updated_at': updated,
          'config': '{"name":"preserved"}',
        });

    Future<Map<String, List<Map<String, Object?>>>> snapshot() async {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%' AND name != 'resource_trash'",
      );
      return {
        for (final table in tables)
          table['name'] as String:
              await db.query(table['name'] as String, orderBy: 'rowid'),
      };
    }

    Future<List<Map<String, Object?>>> activeTombstones() => db.query(
          'resource_trash',
          where: 'restored_at IS NULL',
          orderBy: 'node_id',
        );

    test(
        'should read and update v29 adventures without requiring a trash table',
        () async {
      final legacyDb = await databaseFactory.openDatabase(
        '${directory.path}/legacy.db',
        options: OpenDatabaseOptions(
            version: 29,
            onCreate: (db, version) async {
              await DatabaseService.createV29Schema(db);
            }),
      );
      try {
        final legacyRepository =
            AdventureRepositoryImpl(getDb: () async => legacyDb);
        final id = await legacyRepository.createAdventure(
            'legacy', AdventureConfig(name: 'legacy'));
        expect(
            (await legacyRepository.getAdventureById(id))!['title'], 'legacy');
        expect((await legacyRepository.getAdventures()).single['id'], id);
        await legacyRepository.renameAdventure(id, 'renamed');
        await legacyRepository.markAdventureOpened(id);
        expect(
            (await legacyRepository.getAdventureById(id))!['title'], 'renamed');
        expect(
            await legacyDb.query('sqlite_master',
                where: 'name = ?', whereArgs: ['resource_trash']),
            isEmpty);
      } finally {
        await legacyDb.close();
      }
    });

    test('should return an empty list without creating a second authority',
        () async {
      expect(await repository.getAdventures(), isEmpty);
    });

    test('should sort by activity with legacy fallback and stable ties',
        () async {
      final old = await seed('old', '2025-01-01T00:00:00Z');
      final newer = await seed('new', '2025-01-02T00:00:00Z');
      final opened = await seed('opened', '2025-01-01T00:00:00Z',
          updated: '2025-01-03T09:00:00+08:00');
      final tie = await seed('tie', '2025-01-03T01:00:00Z');
      await repository.insertMessage(
        old,
        Message(
          id: 'new-message',
          content: 'recent narrative',
          isUser: false,
          timestamp: DateTime.parse('2025-01-04T00:00:00Z'),
        ),
        branchId: 2,
      );
      await repository.insertMessage(
        old,
        Message(
          id: 'old-message',
          content: 'imported old narrative',
          isUser: true,
          timestamp: DateTime.parse('2024-01-01T00:00:00Z'),
        ),
      );
      final rows = await repository.getAdventures();
      expect(rows.map((row) => row['id']), [old, tie, opened, newer]);
      expect(DateTime.parse(rows.first['recent_activity_at'] as String),
          DateTime.utc(2025, 1, 4));
    });

    test('should interpret legacy local timestamps and UTC as the same instant',
        () async {
      final local = DateTime(2025, 1, 2, 0, 15);
      final legacy = await seed('legacy local', local.toIso8601String());
      final explicit =
          await seed('explicit UTC', local.toUtc().toIso8601String());
      final rows = await repository.getAdventures();
      expect(rows.map((row) => row['id']), [explicit, legacy]);
      for (final row in rows) {
        final activity = DateTime.parse(row['recent_activity_at'] as String);
        expect(activity, local.toUtc());
        expect(activity.toLocal().day, 2);
        expect(activity.toLocal().hour, 0);
      }
    });

    test('should persist opening and rename without replacing config',
        () async {
      final id = await seed('old title', '2020-01-01T00:00:00Z');
      final before = await repository.getAdventureById(id);
      final start = DateTime.now().toUtc();
      await repository.markAdventureOpened(id);
      await repository.renameAdventure(id, '  new title  ');
      await DatabaseService.resetDatabase();
      db = await DatabaseService.database;
      final reopened = AdventureRepositoryImpl(getDb: () async => db);
      final row = await reopened.getAdventureById(id);
      expect(row!['title'], 'new title');
      expect(row['config'], before!['config']);
      expect(
          DateTime.parse(row['updated_at'] as String).toUtc().isBefore(start),
          isFalse);
      await expectLater(
          repository.renameAdventure(id, ' '), throwsArgumentError);
      await expectLater(
          repository.markAdventureOpened(id + 1), throwsStateError);
    });

    test('should hide idempotently, isolate resource ids, and restore all data',
        () async {
      final id = await repository.createAdventure(
          'Adventure', AdventureConfig(name: 'payload'));
      await repository.insertMessage(
          id, Message(id: 'msg', content: 'story', isUser: false));
      await repository.saveGameState(GameState(adventureId: id, gold: 21));
      await repository.saveSceneState(id, 0,
          const SceneState(location: 'city', presentCharacterIds: ['hero']));
      await repository.saveSummary(id, 'preserved summary', 1);
      await repository.createBranch(adventureId: id, forkAfterId: 0);
      await db.insert('equipment', {'id': 'sword', 'adventure_id': id});
      await db
          .insert('inventory_items', {'adventure_id': id, 'item_id': 'potion'});
      await db.insert('adventure_state_commits', {
        'id': 'restored-commit',
        'adventure_id': id,
        'request_id': 'restored-r',
        'revision': 1,
        'created_at': 'now',
      });
      await db.insert('adventure_state_changes', {
        'id': 'restored-change',
        'commit_id': 'restored-commit',
        'change_index': 0,
        'entity_type': 'character',
        'entity_id': 'hero',
        'change_kind': 'primary',
        'operation': 'set',
        'path': 'location',
        'reason': 'test',
      });
      // A same-numbered legacy row in another table must stay isolated: its
      // tombstone keys on the legacy id, not the adventure node id.
      await tombstones.markDeleted(
        nodeId: 'legacy-resource',
        sourceTable: 'character_cards',
        sourceId: '$id',
        title: 'Unrelated resource',
      );
      final original = await snapshot();
      await repository.moveAdventureToTrash(id);
      await repository.moveAdventureToTrash(id);
      final entries = await activeTombstones();
      expect(entries, hasLength(2));
      final entry =
          entries.singleWhere((row) => row['node_id'] == 'adventure:$id');
      expect(entry['resource_id'], 'adventure:$id');
      expect(entry['reason'], 'userDelete');
      final metadata =
          jsonDecode(entry['metadata_json'] as String) as Map<String, dynamic>;
      expect(metadata['origin'], 'legacy');
      expect(metadata['source_table'], 'adventures');
      expect(metadata['source_id'], '$id');
      expect(await tombstones.isDeleted('adventure:$id'), isTrue);
      expect(await tombstones.isDeleted('legacy-resource'), isTrue);
      expect(await repository.getAdventures(), isEmpty);
      expect(await repository.getAdventureById(id), isNull);
      expect(await snapshot(), original);
      await expectLater(
          repository.renameAdventure(id, 'forbidden'), throwsStateError);
      await expectLater(repository.markAdventureOpened(id), throwsStateError);
      expect(
        await tombstones.activeNodeIds(
          sourceTable: 'character_cards',
          candidateIds: ['$id'],
        ),
        {'$id'},
      );

      await tombstones.restoreByNodeId('adventure:$id');
      expect(await tombstones.isDeleted('adventure:$id'), isFalse);
      expect(await repository.getAdventureById(id), isNotNull);
      expect(await snapshot(), original);
      // Restoring again is a no-op rather than a failure.
      await tombstones.restoreByNodeId('adventure:$id');
      expect(await tombstones.isDeleted('adventure:$id'), isFalse);
      expect(await tombstones.isDeleted('legacy-resource'), isTrue);
    });
  });
}
