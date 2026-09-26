import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/widgets/session_app_bar.dart';
import 'package:lt_dialogue/managers/combat_manager.dart';
import 'package:lt_dialogue/managers/encounter_manager.dart';
import 'package:lt_dialogue/managers/inventory_manager.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_response.dart';
import 'package:lt_dialogue/models/combat_state.dart';
import 'package:lt_dialogue/models/equipment.dart';
import 'package:lt_dialogue/models/game_state.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/models/scene_dialogue_effects.dart';
import 'package:lt_dialogue/providers/adventure_provider.dart';
import 'package:lt_dialogue/screens/chat/widgets/quick_menu.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/world_entry_repository_impl.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('lt_post_removal_smoke_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('Post-Removal Smoke Acceptance: Session Lifecycle & Resume', () {
    test('Multi-turn dialogue with legacy quest JSON and Adventure Resume',
        () async {
      final repo =
          AdventureRepositoryImpl(getDb: () => DatabaseService.database);

      // 1. Create adventure
      final config = AdventureConfig(
        name: '亚瑟',
        worldview: '艾尔登奇幻世界',
      );
      final adventureId = await repo.createAdventure('迷雾森林远征', config);
      expect(adventureId, isPositive);

      // 2. Initialize GameState with narrative location
      var state = GameState(
        adventureId: adventureId,
        hp: 100,
        maxHp: 100,
        mp: 50,
        maxMp: 50,
        gold: 200,
        level: 1,
        currentScene: '边缘营地',
      );
      await repo.saveGameState(state);

      // 3. Turn 1: User message + Assistant message with legacy quests in JSON
      final userMsg1 = Message(
        id: 'msg_1',
        content: '我向守林人打听森林深处的异动。',
        isUser: true,
      );
      await repo.insertMessage(adventureId, userMsg1);

      const assistantTurn1 = '守林人告诉你，林地深处的古代祭坛最近有幽魂游荡。\n\n---JSON---\n'
          '{"hp": 95, "mp": 45, "gold": 220, "scene": "迷雾祭坛外围", '
          '"quests": [{"id": "q1", "title": "调查古代祭坛"}], '
          '"items_gained": [{"name": "月光草", "type": "consumable", "icon": "🌿", "data": {"heal_hp": 20}}]}';

      // Verify parser ignores legacy quest field safely
      final parsed = AdventureResponse.tryParseSplit(assistantTurn1);
      expect(parsed, isNotNull);
      expect(parsed!.narrative.first, contains('守林人告诉你'));
      expect(parsed.hp, equals(95));
      expect(parsed.gold, equals(220));
      expect(parsed.scene, equals('迷雾祭坛外围'));

      final effects = SceneDialogueEffects.fromJson(
        jsonDecode(assistantTurn1.split('---JSON---')[1])
            as Map<String, dynamic>,
      );
      expect(effects.itemsGained, hasLength(1));
      expect(effects.itemsGained.first.name, '月光草');

      state = effects.applyState(state).copyWith(
            currentScene: parsed.scene,
            hp: parsed.hp,
            gold: parsed.gold,
          );
      await repo.saveGameState(state);

      final assistantMsg1 = Message(
        id: 'msg_2',
        content: parsed.narrative.join('\n\n'),
        isUser: false,
      );
      await repo.insertMessage(adventureId, assistantMsg1);

      // Add gained item to inventory
      await repo.saveInventoryItem({
        'adventure_id': adventureId,
        'item_id': 'item_1',
        'name': '月光草',
        'item_type': 'consumable',
        'icon': '🌿',
        'quantity': 1,
        'data_json': jsonEncode({'heal_hp': 20}),
      });

      // 4. Turn 2: User continues dialogue
      final userMsg2 = Message(
        id: 'msg_3',
        content: '我服下月光草，拔剑踏上石阶。',
        isUser: true,
      );
      await repo.insertMessage(adventureId, userMsg2);

      final assistantMsg2 = Message(
        id: 'msg_4',
        content: '月光草的清凉能量在胸口化开，石阶上的青苔泛着荧光。',
        isUser: false,
      );
      await repo.insertMessage(adventureId, assistantMsg2);

      // 5. Simulate closing and reopening: resume through the production
      // AdventureProvider wired with real repositories. We build it directly
      // instead of reading the global riverpod `adventureProvider`, because
      // that facade constructs ChatProvider whose unawaited `_init()` settings
      // writes keep running past the end of this non-widget test and race the
      // database teardown (database_closed).
      final resumedProvider = AdventureProvider(
        adventureRepo: repo,
        worldEntryRepo:
            WorldEntryRepositoryImpl(getDb: () => DatabaseService.database),
        libraryRepo:
            LibraryRepositoryImpl(getDb: () => DatabaseService.database),
      );
      await resumedProvider.loadAdventure(adventureId);

      expect(resumedProvider.currentTitle, '迷雾森林远征');
      expect(resumedProvider.currentAdventureId, adventureId);
      expect(resumedProvider.messages, hasLength(4));
      expect(resumedProvider.messages.first.content, contains('守林人'));
      expect(resumedProvider.messages.last.content, contains('月光草的清凉能量'));

      // Verify GameState & Location
      final resumedState = resumedProvider.gameState;
      expect(resumedState.currentScene, '迷雾祭坛外围');
      expect(resumedState.hp, 95);
      expect(resumedState.gold, 220);

      // Verify inventory
      final items = await repo.getInventoryItems(adventureId);
      expect(items, hasLength(1));
      expect(items.first['name'], '月光草');
    });
  });

  group('Post-Removal Smoke Acceptance: v28 -> v29 DB Migration and Resume',
      () {
    test('v28 database with legacy data upgrades cleanly and resumes',
        () async {
      final dbPath = '${tempDir.path}/legacy_v28_test.db';

      // 1. Create database at v28 and insert legacy data
      var db = await openDatabase(
        dbPath,
        version: 28,
        onCreate: (db, version) async {
          await DatabaseService.createV28Schema(db);
        },
      );

      // Insert core data
      final now = DateTime.now().toIso8601String();
      final advId = await db.insert('adventures', {
        'title': '旧版迁移测试冒险',
        'config': jsonEncode({'name': '测试主角', 'worldview': '旧世界'}),
        'created_at': now,
        'updated_at': now,
      });

      await db.insert('game_state', {
        'adventure_id': advId,
        'hp': 88,
        'max_hp': 100,
        'energy': 90,
        'max_energy': 100,
        'gold': 500,
        'level': 3,
        'current_scene': '旧王城主殿',
      });

      await db.insert('messages', {
        'adventure_id': advId,
        'role': 'user',
        'content': '我们在主殿内休整。',
        'timestamp': now,
        'branch_id': 0,
      });

      await db.insert('inventory_items', {
        'adventure_id': advId,
        'item_id': 'legacy_potion',
        'name': '陈年生命药剂',
        'item_type': 'consumable',
        'icon': '🧪',
        'quantity': 2,
        'data_json': '{}',
      });

      // Insert legacy quest and map entries
      await db.insert('quests', {
        'id': 'legacy_q_01',
        'adventure_id': advId,
        'title': '旧版任务',
        'description': '将在v29被清除',
        'created_at': now,
      });

      await db.insert('map_nodes', {
        'id': 'legacy_node_01',
        'adventure_id': advId,
        'name': '旧版节点',
        'created_at': now,
      });

      await db.close();

      // 2. Open at v29, triggering migration
      db = await openDatabase(
        dbPath,
        version: 29,
        onUpgrade: (db, oldVersion, newVersion) async {
          await DatabaseService.migrateStepByStep(db, oldVersion, newVersion);
        },
      );

      // Verify legacy tables are dropped
      final tablesQuery = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('quests', 'map_nodes', 'map_connections')",
      );
      expect(tablesQuery, isEmpty,
          reason: 'Legacy tables must be dropped after migration');

      // Verify core data is preserved
      final advRows =
          await db.query('adventures', where: 'id = ?', whereArgs: [advId]);
      expect(advRows, hasLength(1));
      expect(advRows.first['title'], '旧版迁移测试冒险');

      final stateRows = await db
          .query('game_state', where: 'adventure_id = ?', whereArgs: [advId]);
      expect(stateRows, hasLength(1));
      expect(stateRows.first['current_scene'], '旧王城主殿');
      expect(stateRows.first['hp'], 88);
      expect(stateRows.first['gold'], 500);

      final msgRows = await db
          .query('messages', where: 'adventure_id = ?', whereArgs: [advId]);
      expect(msgRows, hasLength(1));
      expect(msgRows.first['content'], '我们在主殿内休整。');

      final itemRows = await db.query('inventory_items',
          where: 'adventure_id = ?', whereArgs: [advId]);
      expect(itemRows, hasLength(1));
      expect(itemRows.first['name'], '陈年生命药剂');

      // 3. Resume session using repository on upgraded DB
      final repo = AdventureRepositoryImpl(getDb: () async => db);
      final provider = AdventureProvider(
        adventureRepo: repo,
        worldEntryRepo: WorldEntryRepositoryImpl(getDb: () async => db),
        libraryRepo: LibraryRepositoryImpl(getDb: () async => db),
      );
      await provider.loadAdventure(advId);

      expect(provider.currentTitle, '旧版迁移测试冒险');
      expect(provider.gameState.currentScene, '旧王城主殿');
      expect(provider.messages, hasLength(1));

      await db.close();
    });
  });

  group(
      'Post-Removal Smoke Acceptance: UI Components Responsive & Overflow-Free',
      () {
    const mobileWidths = [320.0, 360.0, 390.0, 412.0];
    final l10n = AppLocalizationsZh();

    for (final width in mobileWidths) {
      testWidgets('QuickMenuButton renders and operates cleanly on ${width}px',
          (tester) async {
        tester.view.physicalSize = Size(width, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        bool inventoryTapped = false;
        bool characterManagementTapped = false;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Center(
                child: QuickMenuButton(
                  isDark: false,
                  onShowInventory: () => inventoryTapped = true,
                  onShowSkills: () {},
                  onShowWordCount: () {},
                  onShowSettings: () {},
                  onShowSceneCharacters: () => characterManagementTapped = true,
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // Tap QuickMenu button to open popup
        await tester.tap(find.byType(QuickMenuButton));
        await tester.pumpAndSettle();

        // Verify items exist
        expect(find.text(l10n.inventoryTitle), findsOneWidget);
        expect(find.text(l10n.characterManagementTitle), findsOneWidget);
        expect(find.text(l10n.wordCountSettings), findsOneWidget);
        expect(find.text(l10n.settingsCenter), findsOneWidget);

        // Verify removed items do NOT exist
        expect(find.text('任务'), findsNothing);
        expect(find.text('地图'), findsNothing);

        // Tap backpack
        await tester.tap(find.text(l10n.inventoryTitle));
        await tester.pumpAndSettle();
        expect(inventoryTapped, isTrue);

        await tester.tap(find.byType(QuickMenuButton));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.characterManagementTitle));
        await tester.pumpAndSettle();
        expect(characterManagementTapped, isTrue);

        expect(tester.takeException(), isNull);
      });

      testWidgets('SessionAppBar renders without overflow on ${width}px',
          (tester) async {
        tester.view.physicalSize = Size(width, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const Scaffold(
                appBar: SessionAppBar(),
              ),
            ),
          ),
        );
        await tester.pump();

        // Verify back button and more options button exist
        expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
        expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);

        // Open popup
        await tester.tap(find.byIcon(Icons.more_vert_rounded));
        await tester.pumpAndSettle();

        // Verify items
        expect(find.text(l10n.switchModelAction), findsOneWidget);
        expect(find.text(l10n.promptSettingsAction), findsOneWidget);
        expect(find.text(l10n.restartAdventureAction), findsOneWidget);
        expect(find.text(l10n.settingsCenter), findsOneWidget);

        // Verify removed items do NOT exist
        expect(find.text('任务'), findsNothing);
        expect(find.text('任务清单'), findsNothing);
        expect(find.text('世界地图'), findsNothing);

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Post-Removal Smoke Acceptance: RPG & Combat Mechanics', () {
    test('InventoryManager handles items, categories, and equipping', () async {
      final inventory = InventoryManager(
        getEquipment: (_) async => const [],
        saveEquipment: (_) async {},
        getInventoryItems: (_) async => const [],
        getInventoryItemsByCharacter: (_, __) async => const [],
        saveInventoryItem: (_) async => 1,
        updateInventoryItem: (_, __) async {},
        deleteInventoryItem: (_) async {},
        getGameState: () => GameState(),
        setGameState: (_) {},
      );

      await inventory.addItem(
        InventoryItem(
          adventureId: 1,
          itemId: 'hp_potion',
          name: '强效生命药剂',
          type: ItemType.consumable,
          quantity: 5,
          data: const {'heal_hp': 50},
        ),
      );

      await inventory.addItem(
        InventoryItem(
          adventureId: 1,
          itemId: 'iron_sword',
          name: '铁剑',
          type: ItemType.equipment,
          quantity: 1,
          data: const {'atk': 10},
        ),
      );

      expect(inventory.allItems, hasLength(2));
      expect(inventory.getByCategory(ItemType.consumable), hasLength(1));
      expect(inventory.getByCategory(ItemType.equipment), hasLength(1));
      expect(inventory.getByCategory(ItemType.material), isEmpty);
    });

    test('EncounterManager provides random enemies and items for RPG combat',
        () {
      final enemy = EncounterManager.getRandomEnemy();
      expect(enemy['name'], isNotNull);
      expect(enemy['hp'], isPositive);
      expect(enemy['atk'], isPositive);

      final item = EncounterManager.getRandomItem();
      expect(item['name'], isNotNull);
      expect(item['type'], isNotNull);
    });

    test('CombatManager runs turn-based combat and rewards exp/gold', () {
      var gameState = GameState(
        hp: 100,
        maxHp: 100,
        mp: 50,
        maxMp: 50,
        gold: 100,
        baseAtk: 15,
        baseDef: 5,
        baseSpeed: 10,
      );

      final combat = CombatManager(
        getGameState: () => gameState,
        setGameState: (s) => gameState = s,
        getAllSkills: () => const [],
        getCharacterSkills: (_) => const [],
      );

      final enemy = CombatUnit(
        id: 'goblin_1',
        name: '测试哥布林',
        maxHp: 10,
        currentHp: 10,
        atk: 3,
        def: 1,
        speed: 2,
      );

      combat.enter([enemy], gameState);
      expect(combat.isActive, isTrue);

      // Perform attack turn
      final result = combat.playerAct(CombatAction.attack);
      expect(result.action, '攻击');
      expect(result.damage, isPositive);
      expect(combat.activeCombat!.enemies.first.isDead, isTrue);
      expect(combat.activeCombat!.phase, CombatPhase.victory);
    });
  });
}
