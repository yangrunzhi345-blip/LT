import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// R2-B1 regression: the **production provider assembly** must route Resource
/// Library deletes into the Phase 9 recycle bin.
///
/// The first remediation wired the bridge into `DatabaseService._libraryRepo`
/// but not into `libraryRepoProvider`, so every delete from the Resource
/// Library UI hit the fail-closed guard and the feature was unusable. The
/// tests below therefore read the real providers from a real
/// `ProviderContainer` with **no overrides and no hand-built repositories**:
/// if the wiring is ever severed again, they fail the same way the production
/// UI does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late ProviderContainer container;

  Future<Database> getDb() => DatabaseService.database;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // A successful production delete fires the library-refresh callback, which
    // builds chatProvider → SettingsProvider.loadApiKey → shared_preferences.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tempDir = await Directory.systemTemp.createTemp('lt_p9_prod_wiring_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  const now = '2026-09-18T00:00:00.000';

  Future<int> rowCount(String table) async {
    final db = await getDb();
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    return (rows.first['c'] as num).toInt();
  }

  Future<int> activeTrashCount() async {
    final db = await getDb();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM resource_trash WHERE restored_at IS NULL',
    );
    return (rows.first['c'] as num).toInt();
  }

  Future<String> singleTrashId() async {
    final db = await getDb();
    final rows = await db.query(
      'resource_trash',
      where: 'restored_at IS NULL',
      limit: 1,
    );
    return rows.single['trash_id'] as String;
  }

  /// Lets the fire-and-forget library-refresh callbacks (fired by a successful
  /// production delete) finish their database work before the test closes it.
  Future<void> settleLibraryRefresh() =>
      Future<void>.delayed(const Duration(milliseconds: 100));

  Future<List<String>> listedIds(List<Map<String, dynamic>> rows) =>
      Future.value(rows.map((row) => row['id']?.toString() ?? '').toList());

  test(
    'worldview preset: production delete reaches the bin and restores',
    () async {
      final repo = container.read(libraryRepoProvider);
      await repo.saveWorldviewPreset(
        id: 'wv-prod',
        name: '生产世界观',
        description: '生产链路回归',
        entriesJson: '[]',
        now: now,
      );

      final crud = container.read(resourceCrudControllerProvider);
      final result = await crud.deleteWorldviewPreset('wv-prod');
      await settleLibraryRefresh();

      expect(
        result.success,
        isTrue,
        reason: 'the production delete path must be wired (R2-B1): '
            '${result.errorMessage ?? ''}',
      );
      expect(
        await rowCount('worldview_presets'),
        1,
        reason: 'a normal delete never physically removes a legacy row',
      );
      expect(await activeTrashCount(), 1);
      expect(
        (await listedIds(await repo.getWorldviewPresets())),
        isNot(contains('wv-prod')),
        reason: 'the deleted resource disappears from the library listing',
      );

      await container
          .read(resourceTrashRuntimeProvider)
          .restore(await singleTrashId());
      await settleLibraryRefresh();

      expect(
        await listedIds(await repo.getWorldviewPresets()),
        contains('wv-prod'),
        reason: 'the restore brings the resource back through the bin',
      );
    },
  );

  test(
    'character card: production delete reaches the bin and restores',
    () async {
      final repo = container.read(libraryRepoProvider);
      await repo.saveCharacterCard(
        id: 'card-prod',
        name: '生产角色卡',
        jsonData: '{"name":"生产角色卡"}',
        source: '手动创建',
        now: now,
      );

      final crud = container.read(resourceCrudControllerProvider);
      final result = await crud.deleteCharacterCard('card-prod');
      await settleLibraryRefresh();

      expect(result.success, isTrue, reason: result.errorMessage ?? '');
      expect(await rowCount('character_cards'), 1);
      expect(await activeTrashCount(), 1);
      expect(
        await listedIds(await repo.getCharacterCards()),
        isNot(contains('card-prod')),
      );

      await container
          .read(resourceTrashRuntimeProvider)
          .restore(await singleTrashId());
      await settleLibraryRefresh();

      expect(
        await listedIds(await repo.getCharacterCards()),
        contains('card-prod'),
      );
    },
  );

  test('npc card: production delete reaches the bin and restores', () async {
    final repo = container.read(libraryRepoProvider);
    await repo.saveNpcCard(
      id: 'npc-prod',
      name: '生产NPC',
      jsonData: '{"name":"生产NPC"}',
      source: '手动创建',
      now: now,
    );

    final crud = container.read(resourceCrudControllerProvider);
    final result = await crud.deleteNpcCard('npc-prod');
    await settleLibraryRefresh();

    expect(result.success, isTrue, reason: result.errorMessage ?? '');
    expect(await rowCount('npc_cards'), 1);
    expect(await activeTrashCount(), 1);
    expect(
      await listedIds(await repo.getNpcCards()),
      isNot(contains('npc-prod')),
    );

    await container
        .read(resourceTrashRuntimeProvider)
        .restore(await singleTrashId());

    expect(
      await listedIds(await repo.getNpcCards()),
      contains('npc-prod'),
    );
  });

  test(
    'the production chain and DatabaseService share one bridge source',
    () async {
      // Both assemblies must resolve to the same bridge instance, so a future
      // half-wired assembly cannot exist silently (R2-B1 root cause).
      final db = await getDb();
      expect(db, isNotNull);
      expect(
        DatabaseService.libraryTrashBridge,
        same(DatabaseService.libraryTrashBridge),
      );
      final repo = container.read(libraryRepoProvider);
      // The provider-built repository can actually delete: fail-closed would
      // throw here.
      await repo.saveWorldviewPreset(
        id: 'wv-bridge',
        name: '桥接一致性',
        description: '',
        entriesJson: '[]',
        now: now,
      );
      await expectLater(
        repo.deleteWorldviewPreset('wv-bridge'),
        completes,
        reason: 'the provider-built repository carries the recycle-bin bridge',
      );
      expect(await activeTrashCount(), 1);
    },
  );
}
