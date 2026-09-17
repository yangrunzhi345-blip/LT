import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_revision.dart';
import 'package:lt_dialogue/domain/resources/resource_trash.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/phase9_recovery_fixtures.dart';

/// P9-B1 regression: a Resource Library delete must move content into the
/// recycle bin and must never be the step that destroys it.
///
/// Before the fix the path was "soft delete the tree + `db.delete` the legacy
/// row", which for a resource whose content only existed in a legacy table (not
/// migrated / migration failed / source changed / tree missing) destroyed the
/// only copy and left nothing in the bin.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late Phase9RecoveryFixture phase9;

  Future<Database> getDb() => DatabaseService.database;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_p9_lib_delete_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    phase9 = Phase9RecoveryFixture(getDb: getDb);
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  const now = '2026-09-17T00:00:00.000';

  Future<void> seedLegacyWorldview(String id, {String name = '世界观'}) =>
      phase9.libraryRepository().saveWorldviewPreset(
            id: id,
            name: name,
            description: '描述 $id',
            entriesJson: '[]',
            now: now,
          );

  Future<void> seedLegacyCard(String id, {String name = '角色卡'}) =>
      phase9.libraryRepository().saveCharacterCard(
            id: id,
            name: name,
            jsonData: '{"name":"$name","description":"$id"}',
            source: '手动创建',
            now: now,
          );

  Future<void> seedLegacyNpc(String id, {String name = 'NPC'}) =>
      phase9.libraryRepository().saveNpcCard(
            id: id,
            name: name,
            jsonData: '{"name":"$name","profession":"$id"}',
            source: '手动创建',
            now: now,
          );

  Future<void> seedTreeResource(String id, {String content = '正文'}) =>
      phase9.tree.createResourceTree(
        ResourceTreeDraft(
          id: ResourceId(id),
          type: ResourceType.worldview,
          name: '树资源 $id',
          sections: <ResourceTreeSectionDraft>[
            ResourceTreeSectionDraft(
              id: SectionId('${id}_sec'),
              title: '第一章',
              parts: <ResourceTreePartDraft>[
                ResourceTreePartDraft(
                  id: PartId('${id}_part'),
                  title: '开场',
                  content: content,
                ),
              ],
            ),
          ],
        ),
      );

  Future<void> seedMigrationRecord({
    required String table,
    required String sourceId,
    required String resourceId,
    String status = 'succeeded',
  }) async {
    final db = await getDb();
    await db.insert('resource_migration_records', <String, Object?>{
      'source_table': table,
      'source_id': sourceId,
      'migration_version': 1,
      'source_hash': 'hash_$sourceId',
      'status': status,
      'resource_id': resourceId,
      'error_reason': '',
      'raw_payload': '',
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<int> rowCount(String table) async {
    final db = await getDb();
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    return (rows.first['c'] as num).toInt();
  }

  Future<String?> legacyName(String table, String id) async {
    final db = await getDb();
    final rows = await db.query(
      table,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['name']?.toString();
  }

  Future<List<ResourceTrashEntry>> activeEntries() =>
      phase9.trashRepository.listEntries();

  group('legacy-only resource delete', () {
    for (final kind in const <String>['worldview', 'character', 'npc']) {
      test('$kind delete moves the row into the bin, not out of the database',
          () async {
        final table = switch (kind) {
          'worldview' => 'worldview_presets',
          'character' => 'character_cards',
          _ => 'npc_cards',
        };
        const id = 'legacy-row-1';
        switch (kind) {
          case 'worldview':
            await seedLegacyWorldview(id);
          case 'character':
            await seedLegacyCard(id);
          default:
            await seedLegacyNpc(id);
        }
        final library = phase9.libraryRepository();

        switch (kind) {
          case 'worldview':
            await library.deleteWorldviewPreset(id);
          case 'character':
            await library.deleteCharacterCard(id);
          default:
            await library.deleteNpcCard(id);
        }

        expect(
          await rowCount(table),
          1,
          reason: 'a normal delete must never physically remove a legacy row',
        );
        final entries = await activeEntries();
        expect(entries, hasLength(1));
        expect(entries.single.isLegacyOrigin, isTrue);
        expect(entries.single.linkedSourceTable, table);
        expect(entries.single.linkedSourceId, id);

        // …and it is hidden from the library while it sits in the bin.
        final visible = switch (kind) {
          'worldview' => await library.getWorldviewPresets(),
          'character' => await library.getCharacterCards(),
          _ => await library.getNpcCards(),
        };
        expect(visible, isEmpty);
      });
    }

    test('restore clears the marker and the row is visible again', () async {
      await seedLegacyWorldview('wv-restore');
      final library = phase9.libraryRepository();
      await library.deleteWorldviewPreset('wv-restore');
      final entry = (await activeEntries()).single;

      final result = await phase9.trash.restore(entry.trashId);

      expect(result.placement, TrashRestorePlacement.restoredToLibrary);
      expect(result.entry.isRestored, isTrue);
      expect(await library.getWorldviewPresets(), hasLength(1));
      expect(
        await legacyName('worldview_presets', 'wv-restore'),
        '世界观',
        reason: 'the legacy row was never touched, so its content is intact',
      );
    });

    test('permanent delete is the only path that removes the row', () async {
      await seedLegacyWorldview('wv-purge');
      final library = phase9.libraryRepository();
      await library.deleteWorldviewPreset('wv-purge');
      expect(await rowCount('worldview_presets'), 1);

      final entry = (await activeEntries()).single;
      final result = await phase9.trash.permanentDelete(entry.trashId);

      expect(result.deletedNodeIds, <String>['wv-purge']);
      expect(await rowCount('worldview_presets'), 0);
      expect(await activeEntries(), isEmpty);
    });

    test('a repeated delete is idempotent', () async {
      await seedLegacyWorldview('wv-twice');
      final library = phase9.libraryRepository();
      await library.deleteWorldviewPreset('wv-twice');

      await library.deleteWorldviewPreset('wv-twice');

      expect(await activeEntries(), hasLength(1));
      expect(await rowCount('worldview_presets'), 1);
    });

    test('permanent delete of a restored entry leaves the row in place',
        () async {
      await seedLegacyWorldview('wv-restored-purge');
      final library = phase9.libraryRepository();
      await library.deleteWorldviewPreset('wv-restored-purge');
      final entry = (await activeEntries()).single;
      await phase9.trash.restore(entry.trashId);

      final result = await phase9.trash.permanentDelete(entry.trashId);

      expect(result.alreadyGone, isTrue);
      expect(
        await rowCount('worldview_presets'),
        1,
        reason: 'a stale bin row must never be able to delete live data',
      );
    });
  });

  group('fallback-state resource coverage', () {
    test('notMigrated: no tree row at all, content preserved and restorable',
        () async {
      await seedLegacyCard('card-not-migrated');
      final library = phase9.libraryRepository();

      await library.deleteCharacterCard('card-not-migrated');

      expect(await rowCount('character_cards'), 1);
      expect(await library.getCharacterCards(), isEmpty);
      final entry = (await activeEntries()).single;
      expect(entry.isLegacyOrigin, isTrue);

      await phase9.trash.restore(entry.trashId);

      final restored = await library.getCharacterCards();
      expect(restored, hasLength(1));
      expect(
        restored.single['json_data'],
        contains('card-not-migrated'),
        reason: 'the fallback resource must come back byte-identical',
      );
    });

    test('treeMissing: audit record exists but the tree row is gone', () async {
      await seedLegacyNpc('npc-tree-missing');
      await seedMigrationRecord(
        table: 'npc_cards',
        sourceId: 'npc-tree-missing',
        resourceId: 'res_legacy_gone',
      );
      final library = phase9.libraryRepository();

      await library.deleteNpcCard('npc-tree-missing');

      expect(await rowCount('npc_cards'), 1);
      expect(await library.getNpcCards(), isEmpty);
      final entry = (await activeEntries()).single;
      expect(
        entry.isLegacyOrigin,
        isTrue,
        reason: 'a stale audit record pointing at a missing tree row must not '
            'make the tree delete path run',
      );

      await phase9.trash.restore(entry.trashId);
      expect(await library.getNpcCards(), hasLength(1));
    });

    test('migrationFailed: a failed audit record still keeps the row',
        () async {
      await seedLegacyWorldview('wv-failed');
      await seedMigrationRecord(
        table: 'worldview_presets',
        sourceId: 'wv-failed',
        resourceId: '',
        status: 'failed',
      );
      final library = phase9.libraryRepository();

      await library.deleteWorldviewPreset('wv-failed');

      expect(await rowCount('worldview_presets'), 1);
      final entry = (await activeEntries()).single;
      expect(entry.isLegacyOrigin, isTrue);
    });
  });

  group('migrated resource delete', () {
    const legacyId = 'wv-migrated';
    const treeId = 'res_legacy_worldview_presets_wv-migrated';

    Future<void> seedMigrated() async {
      await seedLegacyWorldview(legacyId);
      await seedTreeResource(treeId, content: '迁移后的正文');
      await seedMigrationRecord(
        table: 'worldview_presets',
        sourceId: legacyId,
        resourceId: treeId,
      );
    }

    test('soft deletes the tree row, hides the legacy row, keeps both',
        () async {
      await seedMigrated();
      final library = phase9.libraryRepository();
      await phase9.revisionService.captureRevision(
        const ResourceId(treeId),
        cause: RevisionCause.migration,
      );

      await library.deleteWorldviewPreset(legacyId);

      expect(await phase9.tree.findResource(const ResourceId(treeId)), isNull);
      expect(
        await rowCount('worldview_presets'),
        1,
        reason: 'the legacy row is kept until an explicit permanent delete',
      );
      expect(await library.getWorldviewPresets(), isEmpty);
      final entry = (await activeEntries()).single;
      expect(entry.isLegacyOrigin, isFalse);
      expect(entry.nodeId, treeId);

      // The deleted state was recorded before the delete, so it is recoverable.
      final state = await phase9.revisionService.readState(
        ResourceRevisionId(entry.revisionId),
      );
      expect(
        state.nodes.values
            .firstWhere((node) => node.nodeId == '${treeId}_part')
            .content,
        '迁移后的正文',
      );
    });

    test('restore revives the tree row and the library row reappears',
        () async {
      await seedMigrated();
      final library = phase9.libraryRepository();
      // A migrated resource is projected by the Phase 3 union from BOTH the
      // legacy row and its tree row, so the id set (not the row count) is what
      // this regression pins: the delete must hide every projection, and the
      // restore must bring back exactly what was listed before.
      final before =
          (await library.getWorldviewPresets()).map((row) => row['id']).toSet();
      expect(before, isNotEmpty);

      await library.deleteWorldviewPreset(legacyId);
      expect(await library.getWorldviewPresets(), isEmpty);
      final entry = (await activeEntries()).single;

      await phase9.trash.restore(entry.trashId);

      expect(
          await phase9.tree.findResource(const ResourceId(treeId)), isNotNull);
      expect(
        (await library.getWorldviewPresets()).map((row) => row['id']).toSet(),
        before,
        reason: 'a restore must reproduce the pre-delete listing exactly',
      );
      expect(await rowCount('worldview_presets'), 1);
    });

    test('permanent delete removes both the tree row and the legacy row',
        () async {
      await seedMigrated();
      final library = phase9.libraryRepository();
      await library.deleteWorldviewPreset(legacyId);
      final entry = (await activeEntries()).single;

      await phase9.trash.permanentDelete(entry.trashId);

      expect(await rowCount('worldview_presets'), 0);
      final db = await getDb();
      expect(
        await db.query(
          'resources',
          where: 'id = ?',
          whereArgs: <Object?>[treeId],
        ),
        isEmpty,
      );
    });
  });

  group('tree-only resource delete', () {
    const treeId = 'res_pipeline_only';

    test('soft deletes the tree row and can be restored', () async {
      await seedTreeResource(treeId, content: '管道创建的正文');
      final library = phase9.libraryRepository();
      await phase9.revisionService.captureRevision(
        const ResourceId(treeId),
        cause: RevisionCause.generation,
      );

      await library.deleteWorldviewPreset(treeId);

      expect(await phase9.tree.findResource(const ResourceId(treeId)), isNull);
      expect(await library.getWorldviewPresets(), isEmpty);
      final entry = (await activeEntries()).single;
      expect(entry.isLegacyOrigin, isFalse);

      await phase9.trash.restore(entry.trashId);

      final tree = await phase9.tree.readTree(const ResourceId(treeId));
      expect(tree, isNotNull);
      expect(tree!.parts.single.content, '管道创建的正文');
    });
  });

  group('safety rails', () {
    test('an unwired library repository refuses to delete', () async {
      await seedLegacyWorldview('wv-unwired');
      final unwired = phase9.unwiredLibraryRepository();

      await expectLater(
        unwired.deleteWorldviewPreset('wv-unwired'),
        throwsA(isA<StateError>()),
      );

      expect(
        await rowCount('worldview_presets'),
        1,
        reason: 'failing closed is the point: without the bin there is no safe '
            'way to delete',
      );
      expect(await activeEntries(), isEmpty);
    });

    test('legacy rows can only be purged from the three resource tables',
        () async {
      await seedLegacyWorldview('wv-table-guard');
      final library = phase9.libraryRepository();
      await library.deleteWorldviewPreset('wv-table-guard');
      final entry = (await activeEntries()).single;

      // A tampered marker must not be able to point the purge at another table.
      final db = await getDb();
      await db.update(
        'resource_trash',
        <String, Object?>{
          'metadata_json':
              '{"origin":"legacy","source_table":"adventure_state_commits","source_id":"x"}',
        },
        where: 'trash_id = ?',
        whereArgs: <Object?>[entry.trashId],
      );

      await expectLater(
        phase9.trash.permanentDelete(entry.trashId),
        throwsA(isA<ResourceTrashException>()),
      );
      expect(await rowCount('worldview_presets'), 1);
    });

    test('search hides a binned resource too', () async {
      await seedLegacyWorldview('wv-search-a', name: '阿卡姆');
      await seedLegacyWorldview('wv-search-b', name: '阿卡姆之夜');
      final library = phase9.libraryRepository();
      expect(
        await library.searchWorldviewPresets('阿卡姆'),
        hasLength(2),
      );

      await library.deleteWorldviewPreset('wv-search-a');

      final results = await library.searchWorldviewPresets('阿卡姆');
      expect(results, hasLength(1));
      expect(results.single['id'], 'wv-search-b');
    });

    test('a non-resource library table keeps its own delete semantics',
        () async {
      final library = phase9.libraryRepository();
      await library.savePromptPreset(
        id: 'prompt-1',
        name: '预设',
        systemPrompt: '系统提示',
        authorsNote: '',
        noteDepth: 0,
        noteFrequency: 0,
        now: now,
      );
      expect(await rowCount('prompt_presets'), 1);

      await library.deletePromptPreset('prompt-1',
          mode: ResourceLibraryMode.adventure);

      expect(
        await rowCount('prompt_presets'),
        0,
        reason: 'configuration tables never went through the resource bin',
      );
      expect(await activeEntries(), isEmpty);
    });
  });
}
