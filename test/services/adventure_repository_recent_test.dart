import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/legacy_library_row_purger.dart';
import 'package:lt_dialogue/application/resources/resource_revision_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_service.dart';
import 'package:lt_dialogue/application/resources/resource_trash_repository.dart';
import 'package:lt_dialogue/application/resources/resource_trash_service.dart';
import 'package:lt_dialogue/domain/resources/resource_trash.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/game_state.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/models/scene_state.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  group('AdventureRepositoryImpl recent adventures', () {
    late Directory directory;
    late Database db;
    late AdventureRepositoryImpl repository;
    late ResourceTrashService trash;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('lt_recent_adventure_');
      DatabaseService.customDbDir = directory.path;
      await DatabaseService.resetDatabase();
      db = await DatabaseService.database;
      final tree = ResourceTreeRepositoryImpl(getDb: () async => db);
      trash = ResourceTrashService(
        repository: ResourceTrashRepositoryImpl(getDb: () async => db),
        treeBoundary: tree,
        captureEngine: RevisionCaptureEngine(
          revisionRepository:
              ResourceRevisionRepositoryImpl(getDb: () async => db),
          treeBoundary: tree,
        ),
        getDb: () async => db,
        legacyRowPort: LegacyLibraryRowPurger(getDb: () async => db),
      );
      repository = AdventureRepositoryImpl(
        getDb: () async => db,
        trashService: trash,
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
      final original = await snapshot();
      await trash.deleteLegacyOnlyResource(
        resourceId: '$id',
        sourceTable: 'character_cards',
        sourceId: '$id',
        title: 'Unrelated resource',
      );
      await repository.moveAdventureToTrash(id);
      await repository.moveAdventureToTrash(id);
      final entries = await trash.list();
      expect(entries, hasLength(2));
      final entry =
          entries.singleWhere((e) => e.linkedSourceTable == 'adventures');
      expect(entry.nodeId, 'adventure:$id');
      expect(entry.resourceId.value, 'adventure:$id');
      expect(entry.linkedSourceId, '$id');
      expect(await repository.getAdventures(), isEmpty);
      expect(await repository.getAdventureById(id), isNull);
      expect(await snapshot(), original);
      await expectLater(
          repository.renameAdventure(id, 'forbidden'), throwsStateError);
      await expectLater(repository.markAdventureOpened(id), throwsStateError);
      final restored = await trash.restore(entry.trashId);
      expect(restored.placement, TrashRestorePlacement.restoredToAdventures);
      expect(await repository.getAdventureById(id), isNotNull);
      expect(await snapshot(), original);
      expect((await trash.restore(entry.trashId)).isIdempotentRepeat, isTrue);
    });

    test(
        'should cascade owned data only on explicit purge and rollback failure',
        () async {
      final id = await repository.createAdventure(
          'delete', AdventureConfig(name: 'delete'));
      final keep = await repository.createAdventure(
          'keep', AdventureConfig(name: 'keep'));
      await repository.insertMessage(
          id, Message(id: 'gone', content: 'gone', isUser: false));
      await repository.insertMessage(
          keep, Message(id: 'kept', content: 'kept', isUser: false));
      await repository.saveGameState(GameState(adventureId: id));
      await repository.saveSceneState(
          id, 0, const SceneState(location: 'city'));
      await repository.createBranch(adventureId: id, forkAfterId: 0);
      await db.insert('runtime_state_checkpoints', {
        'id': 'cp',
        'adventure_id': id,
        'revision': 0,
        'name': 'cp',
        'created_at': 'now',
        'updated_at': 'now'
      });
      await db.insert('adventure_character_memberships', {
        'adventure_id': id,
        'character_id': 'hero',
        'snapshot_json': '{}',
        'request_id': 'r',
        'attached_at': 'now',
        'updated_at': 'now'
      });
      await db.insert('scene_presence_mutation_requests', {
        'adventure_id': id,
        'request_id': 'r',
        'source': 'test',
        'revision': 0,
        'created_at': 'now'
      });
      final sharedEntry = await db.insert('world_entries', {
        'adventure_id': keep,
        'content': 'shared content',
      });
      for (final owner in [id, keep]) {
        await db.insert('world_entry_embeddings', {
          'entry_id': sharedEntry,
          'adventure_id': owner,
          'content_hash': 'hash-$owner',
          'model_id': 'model',
          'dimensions': 1,
          'embedding_json': '[1.0]',
          'created_at': 'now',
        });
      }
      await db.insert('adventure_state_commits', {
        'id': 'commit',
        'adventure_id': id,
        'request_id': 'commit-request',
        'revision': 1,
        'created_at': 'now',
      });
      await db.insert('adventure_state_changes', {
        'id': 'change',
        'commit_id': 'commit',
        'change_index': 0,
        'entity_type': 'character',
        'entity_id': 'hero',
        'change_kind': 'primary',
        'operation': 'set',
        'path': 'location',
        'reason': 'test',
      });
      // Validate every direct adventure FK in the real current schema; child
      // archives and map connections inherit deletion from their owning rows.
      final tables = await db
          .rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      final nonCascadeScopes = <String>{};
      for (final table in tables) {
        final name = table['name'] as String;
        final fks = await db.rawQuery('PRAGMA foreign_key_list("$name")');
        final columns = await db.rawQuery('PRAGMA table_info("$name")');
        if (columns.any((column) => column['name'] == 'adventure_id') &&
            !fks.any((fk) => fk['table'] == 'adventures')) {
          nonCascadeScopes.add(name);
        }
        for (final fk in fks.where((fk) => fk['table'] == 'adventures')) {
          expect(fk['on_delete'], 'CASCADE', reason: name);
        }
      }
      expect(nonCascadeScopes, {'world_entry_embeddings'});
      await repository.moveAdventureToTrash(id);
      final entry = (await trash.list()).single;
      final original = await snapshot();
      // The trigger fails after cascades begin. Marker deletion and all owned
      // data must be rolled back together with the adventure deletion.
      await db.execute(
          'CREATE TRIGGER deny_adventure_purge AFTER DELETE ON adventures BEGIN SELECT RAISE(ABORT, "injected failure"); END');
      await expectLater(trash.permanentDelete(entry.trashId),
          throwsA(isA<DatabaseException>()));
      expect(await snapshot(), original);
      expect((await trash.list()).single.trashId, entry.trashId);
      await db.execute('DROP TRIGGER deny_adventure_purge');
      await trash.permanentDelete(entry.trashId);
      expect(await repository.getAdventureById(id), isNull);
      expect(await repository.getAdventureById(keep), isNotNull);
      for (final table in [
        'messages',
        'game_state',
        'scene_runtime_state',
        'branches',
        'runtime_state_checkpoints',
        'adventure_character_memberships',
        'scene_presence_mutation_requests',
        'world_entry_embeddings',
        'adventure_state_commits'
      ]) {
        expect(
            await db.query(table, where: 'adventure_id = ?', whereArgs: [id]),
            isEmpty,
            reason: table);
      }
      expect(await db.query('adventure_state_changes'), isEmpty);
      expect(
          await db.query('world_entries',
              where: 'id = ?', whereArgs: [sharedEntry]),
          hasLength(1));
      expect(
          await db.query('world_entry_embeddings',
              where: 'adventure_id = ?', whereArgs: [keep]),
          hasLength(1));
      expect((await repository.getMessages(keep)).single.content, 'kept');
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      expect((await trash.permanentDelete(entry.trashId)).alreadyGone, isTrue);
      expect(LegacyLibraryRowPurger.isResourceTable('adventures'), isFalse);
    });
  });
}
