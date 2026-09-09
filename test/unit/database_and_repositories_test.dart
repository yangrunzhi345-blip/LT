import 'dart:convert';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/application/adventure/adventure_assembler.dart';
import 'package:lt_dialogue/models/game_state.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/models/scene_state.dart';
import 'package:lt_dialogue/models/world_entry.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/key_vault.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/library_repository.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/settings_repository.dart';
import 'package:lt_dialogue/services/repositories/settings_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/world_entry_repository.dart';
import 'package:lt_dialogue/services/repositories/world_entry_repository_impl.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;
  late ISettingsRepository settingsRepo;
  late ILibraryRepository libraryRepo;
  late IAdventureRepository adventureRepo;
  late IWorldEntryRepository worldEntryRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_db_test_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();

    settingsRepo =
        SettingsRepositoryImpl(getDb: () => DatabaseService.database);
    libraryRepo = LibraryRepositoryImpl(getDb: () => DatabaseService.database);
    adventureRepo =
        AdventureRepositoryImpl(getDb: () => DatabaseService.database);
    worldEntryRepo =
        WorldEntryRepositoryImpl(getDb: () => DatabaseService.database);
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Phase 2 Persistence & Repositories Verification', () {
    test('DatabaseService initializes and creates core tables', () async {
      final db = await DatabaseService.database;
      expect(db.isOpen, isTrue);

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      final tableNames = tables.map((t) => t['name'] as String).toSet();

      // Verify essential tables exist
      expect(tableNames.contains('settings'), isTrue);
      expect(tableNames.contains('api_keys'), isTrue);
      expect(tableNames.contains('character_cards'), isTrue);
      expect(tableNames.contains('worldview_presets'), isTrue);
      expect(tableNames.contains('adventures'), isTrue);
      expect(tableNames.contains('messages'), isTrue);
      expect(tableNames.contains('game_state'), isTrue);
      expect(tableNames.contains('world_entries'), isTrue);
      expect(tableNames.contains('scene_runtime_state'), isTrue);
      final characterColumns =
          await db.rawQuery('PRAGMA table_info(character_cards)');
      final characterColumnNames =
          characterColumns.map((column) => column['name']).toSet();
      expect(characterColumnNames, contains('authoring_method'));
      expect(characterColumnNames, contains('ai_generation_depth'));
    });

    test('SettingsRepository can write and read settings', () async {
      await settingsRepo.setSetting('theme_mode', 'dark');
      final value = await settingsRepo.getSetting('theme_mode');
      expect(value, equals('dark'));

      final all = await settingsRepo.getAllSettings();
      expect(all['theme_mode'], equals('dark'));
    });

    test('LibraryRepository can insert and query character card and worldview',
        () async {
      final now = DateTime.now().toIso8601String();

      // 1. Worldview preset
      await libraryRepo.saveWorldviewPreset(
        id: 'test_w1',
        name: '赛博朋克 2077',
        description: '高科技与低生活交织的未来世界',
        entriesJson: '[]',
        now: now,
        authoringMethod: 'aiReference',
        aiGenerationDepth: 'detailed',
      );

      final worldviews = await libraryRepo.getWorldviewPresets();
      expect(worldviews.any((w) => w['name'] == '赛博朋克 2077'), isTrue);
      final worldview = worldviews.firstWhere((w) => w['id'] == 'test_w1');
      expect(worldview['authoring_method'], 'aiReference');
      expect(worldview['ai_generation_depth'], 'detailed');

      // 2. Character card
      await libraryRepo.saveCharacterCard(
        id: 'test_c1',
        name: 'V',
        jsonData: '{"name":"V","description":"夜之城的雇佣兵"}',
        source: 'manual',
        now: now,
        authoringMethod: 'manual',
      );

      final cards = await libraryRepo.getCharacterCards();
      expect(cards.any((c) => c['name'] == 'V'), isTrue);
      final card = cards.firstWhere((c) => c['id'] == 'test_c1');
      expect(card['authoring_method'], 'manual');
      expect(card['ai_generation_depth'], isEmpty);
    });

    test(
        'AdventureRepository creates adventure, inserts messages and game state',
        () async {
      final config = AdventureConfig(
        name: 'V',
        worldview: '赛博朋克 2077',
      );

      final advId = await adventureRepo.createAdventure('夜之城初探', config);
      expect(advId, isPositive);

      // Insert message
      final msg = Message(
        id: 'msg_1',
        content: '我推开酒吧的门。',
        isUser: true,
      );
      await adventureRepo.insertMessage(advId, msg);

      final messages = await adventureRepo.getMessages(advId);
      expect(messages.length, equals(1));
      expect(messages.first.content, equals('我推开酒吧的门。'));

      // Save and get GameState
      final state = GameState(
        adventureId: advId,
        hp: 90,
        maxHp: 100,
        gold: 480,
        currentScene: '来生酒吧',
      );
      await adventureRepo.saveGameState(state);

      final loadedState = await adventureRepo.getGameState(advId);
      expect(loadedState, isNotNull);
      expect(loadedState!.hp, equals(90));
      expect(loadedState.gold, equals(480));
      expect(loadedState.currentScene, equals('来生酒吧'));
    });

    test('WorldEntryRepository can insert and query world entries', () async {
      final advId = await adventureRepo.createAdventure(
        '夜之城',
        AdventureConfig(name: 'V', worldview: '赛博朋克'),
      );

      final entry = WorldEntry(
        adventureId: advId,
        keys: ['荒坂', '公司'],
        content: '荒坂公司是控制夜之城的主要超级财团之一。',
      );
      final id = await worldEntryRepo.insertWorldEntry(entry);
      expect(id, isPositive);

      final entries = await worldEntryRepo.getWorldEntries(advId);
      expect(entries.length, equals(1));
      expect(entries.first.content, contains('荒坂公司'));
    });

    test('AdventureRepository persists branch-local scene runtime state',
        () async {
      final adventureId = await adventureRepo.createAdventure(
        '王宫分支',
        AdventureConfig(name: '旅人', worldview: '低魔世界'),
      );
      const state = SceneState(
        location: '酒馆',
        presentCharacterIds: ['player'],
        goals: [
          SceneGoal(
            id: 'palace',
            description: '前往王宫',
            status: SceneGoalStatus.cancelled,
          ),
          SceneGoal(id: 'tavern', description: '寻找酒馆'),
        ],
      );

      await adventureRepo.saveSceneState(adventureId, 0, state);
      final restored = await adventureRepo.getSceneState(adventureId, 0);

      expect(restored, isNotNull);
      expect(restored!.location, '酒馆');
      expect(restored.goals.first.status, SceneGoalStatus.cancelled);
      expect(restored.activeGoals.single.description, '寻找酒馆');
    });

    test('Adventure snapshots survive source asset updates and deletion',
        () async {
      const worldviewId = 'snapshot-world';
      const characterId = 'snapshot-character';
      const npcId = 'snapshot-npc';
      final now = DateTime.now().toIso8601String();
      await libraryRepo.saveWorldviewPreset(
        id: worldviewId,
        name: '北境',
        description: '创建时的世界观',
        entriesJson: '[]',
        now: now,
      );
      await libraryRepo.saveCharacterCard(
        id: characterId,
        name: '艾琳',
        jsonData: '{"name":"艾琳","description":"创建时的角色"}',
        source: '手动创建',
        now: now,
        matchingWorldviewId: worldviewId,
      );
      await libraryRepo.saveNpcCard(
        id: npcId,
        name: '守门人',
        jsonData: '{"name":"守门人","profession":"创建时的卫兵"}',
        source: '手动创建',
        now: now,
        matchingWorldviewId: worldviewId,
      );

      final frozen = const AdventureAssembler().assemble(
        AdventureConfig(
          worldview: '北境',
          worldviewSnapshot: {
            'source_id': worldviewId,
            'name': '北境',
            'description': '创建时的世界观',
          },
          name: '艾琳',
          selectedCharacters: [
            AdventureSelectedCharacter(
              id: characterId,
              characterId: characterId,
              characterName: '艾琳',
              isProtagonist: true,
              characterCardJson: const {
                'name': '艾琳',
                'description': '创建时的角色',
              },
            ),
          ],
          npcSnapshots: [
            AdventureNpcSnapshot(
              assetId: npcId,
              name: '守门人',
              originWorldviewId: worldviewId,
              npcJson: const {
                'name': '守门人',
                'profession': '创建时的卫兵',
              },
            ),
          ],
        ),
      );
      final adventureId = await adventureRepo.createAdventure('快照冒险', frozen);

      await libraryRepo.saveWorldviewPreset(
        id: worldviewId,
        name: '北境',
        description: '修改后的世界观',
        entriesJson: '[]',
        now: now,
      );
      await libraryRepo.saveCharacterCard(
        id: characterId,
        name: '艾琳',
        jsonData: '{"name":"艾琳","description":"修改后的角色"}',
        source: '手动创建',
        now: now,
      );
      await libraryRepo.saveNpcCard(
        id: npcId,
        name: '守门人',
        jsonData: '{"name":"守门人","profession":"修改后的卫兵"}',
        source: '手动创建',
        now: now,
      );
      await libraryRepo.deleteWorldviewPreset(worldviewId);
      await libraryRepo.deleteCharacterCard(characterId);
      await libraryRepo.deleteNpcCard(npcId);

      final row = await adventureRepo.getAdventureById(adventureId);
      final restored = AdventureConfig.fromJson(
        jsonDecode(row!['config'] as String) as Map<String, dynamic>,
      );
      expect(restored.worldviewSnapshot?['description'], '创建时的世界观');
      expect(
        restored.selectedCharacters.single.characterCardJson?['description'],
        '创建时的角色',
      );
      expect(
        restored.npcSnapshots.single.npcJson['profession'],
        '创建时的卫兵',
      );
      expect(await libraryRepo.getWorldviewPresets(), isEmpty);
      expect(await libraryRepo.getCharacterCards(), isEmpty);
      expect(await libraryRepo.getNpcCards(), isEmpty);
    });

    test('KeyVault encrypts and decrypts correctly', () {
      const originalKey = 'sk-proj-1234567890abcdefghijklmnopqrstuvwxyz';
      final encrypted = KeyVault.encrypt(originalKey);
      expect(encrypted, isNotEmpty);
      expect(encrypted, isNot(equals(originalKey)));

      final decrypted = KeyVault.decrypt(encrypted);
      expect(decrypted, equals(originalKey));
    });
  });
}
