import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/application/adventure/adventure_assembler.dart';
import 'package:lt_dialogue/models/game_state.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/models/scene_state.dart';
import 'package:lt_dialogue/models/scene_dialogue_effects.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
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
import 'package:lt_dialogue/providers/adventure_provider.dart';

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
    test('should initialize runtime state when importing JSONL adventure',
        () async {
      final provider = AdventureProvider(
        adventureRepo: adventureRepo,
        worldEntryRepo: worldEntryRepo,
        libraryRepo: libraryRepo,
      );
      addTearDown(provider.dispose);

      final adventureId = await provider.importFromJsonl(
        '{"role":"user","content":"我进入白港。"}\n'
            '{"role":"assistant","content":"雾气笼罩码头。"}',
        'JSONL 初始化回归',
      );

      expect(await adventureRepo.getAdventureById(adventureId), isNotNull);
      expect(await adventureRepo.getGameState(adventureId), isNotNull);
      expect(await adventureRepo.getSceneState(adventureId, 0), isNotNull);
      expect(await adventureRepo.getScenePresence(adventureId, 0), isNotNull);
    });

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

    test('runtime commits preserve frozen config and are idempotent', () async {
      final config = AdventureConfig(
        name: '旅人',
        supportingCharacters: [
          SupportingCharacter(id: 'eileen', name: '艾琳', affinity: 40),
        ],
      );
      final adventureId = await adventureRepo.createAdventure('运行时状态', config);
      final commit = SceneDialogueCommit(
        requestId: 'runtime-idempotent',
        adventureId: adventureId,
        branchId: 0,
        userMessage: Message(id: 'u1', content: '继续前进', isUser: true),
        assistantMessage: Message(id: 'a1', content: '艾琳倒下了', isUser: false),
        gameState: GameState(adventureId: adventureId),
        effects: const SceneDialogueEffects(
          affinityChanges: {'艾琳': 10},
          deadCharacters: {'艾琳'},
        ),
      );

      expect((await adventureRepo.commitSceneDialogueTurn(commit)).applied,
          isTrue);
      expect((await adventureRepo.commitSceneDialogueTurn(commit)).applied,
          isFalse);
      final stored = await adventureRepo.getAdventureById(adventureId);
      final frozen = AdventureConfig.fromJson(
          jsonDecode(stored!['config'] as String) as Map<String, dynamic>);
      expect(frozen.supportingCharacters.single.isAlive, isTrue);
      expect(frozen.supportingCharacters.single.affinity, 40);
      final head = await adventureRepo.getRuntimeHead(adventureId, 0);
      final entity =
          (await adventureRepo.getRuntimeEntities(adventureId, 0)).single;
      expect(head.revision, 1);
      expect(entity.overlay['life_status'], 'dead');
      expect(entity.overlay['affinity'], 50);
    });

    test('runtime overlays fork and remain branch isolated', () async {
      final adventureId = await adventureRepo.createAdventure(
          '分支运行时',
          AdventureConfig(
              supportingCharacters: [SupportingCharacter(id: 'b', name: 'B')]));
      await adventureRepo.commitSceneDialogueTurn(SceneDialogueCommit(
        requestId: 'root-change',
        adventureId: adventureId,
        branchId: 0,
        userMessage: Message(id: 'u', content: 'x', isUser: true),
        assistantMessage: Message(id: 'a', content: 'x', isUser: false),
        gameState: GameState(adventureId: adventureId),
        runtimeStateDraft: const RuntimeStateCommitDraft(
            expectedRevision: 0,
            summary: 'death',
            changes: [
              RuntimeStateChangeProposal(
                  entityType: RuntimeEntityType.character,
                  entityId: 'b',
                  changeKind: RuntimeChangeKind.primary,
                  operation: RuntimeChangeOperation.set,
                  path: 'life_status',
                  value: 'dead',
                  reason: 'test')
            ]),
      ));
      final branch = await adventureRepo.createBranch(
          adventureId: adventureId, forkAfterId: 0);
      expect(
          (await adventureRepo.getRuntimeEntities(adventureId, branch))
              .single
              .overlay['life_status'],
          'dead');
      // Branch-local no-op/change state remains independent of the root HEAD.
      expect((await adventureRepo.getRuntimeHead(adventureId, branch)).revision,
          1);
      expect((await adventureRepo.getRuntimeHead(adventureId, 0)).revision, 1);
    });

    test('v27 migration preserves adventures and creates runtime archive',
        () async {
      final path = '${tempDir.path}/migration_v27.db';
      final v27 =
          await openDatabase(path, version: 27, onCreate: (db, _) async {
        await DatabaseService.createV27Schema(db);
      });
      await v27.insert('adventures', {
        'title': '旧存档',
        'config': jsonEncode(AdventureConfig(name: '旧主角').toJson()),
        'created_at': DateTime.now().toIso8601String(),
      });
      await v27.close();
      final upgraded = await openDatabase(path, version: 28,
          onUpgrade: (db, old, latest) async {
        await DatabaseService.migrateStepByStep(db, old, latest);
      });

      expect((await upgraded.query('adventures')).single['title'], '旧存档');
      for (final table in const [
        'adventure_runtime_heads',
        'adventure_runtime_entities',
        'adventure_state_commits',
        'adventure_state_changes',
      ]) {
        expect(await DatabaseService.tableExists(upgraded, table), isTrue);
      }
      final indexes = await upgraded
          .rawQuery("SELECT name FROM sqlite_master WHERE type='index'");
      expect(indexes.map((row) => row['name']),
          contains('idx_runtime_commits_branch_revision'));
      await upgraded.close();
    });

    test('runtime no-op and unknown entities do not advance HEAD', () async {
      final adventureId = await adventureRepo.createAdventure(
        'runtime no-op',
        AdventureConfig(supportingCharacters: [
          SupportingCharacter(id: 'known', name: 'Known')
        ]),
      );
      SceneDialogueCommit commit(
              String requestId, String entityId, int revision) =>
          SceneDialogueCommit(
            requestId: requestId,
            adventureId: adventureId,
            branchId: 0,
            userMessage:
                Message(id: '$requestId-u', content: 'u', isUser: true),
            assistantMessage:
                Message(id: '$requestId-a', content: 'a', isUser: false),
            gameState: GameState(adventureId: adventureId),
            runtimeStateDraft: RuntimeStateCommitDraft(
              expectedRevision: revision,
              summary: 'state',
              changes: [
                RuntimeStateChangeProposal(
                    entityType: RuntimeEntityType.character,
                    entityId: entityId,
                    changeKind: RuntimeChangeKind.primary,
                    operation: RuntimeChangeOperation.set,
                    path: 'life_status',
                    value: 'dead',
                    reason: 'test'),
              ],
            ),
          );
      await adventureRepo.commitSceneDialogueTurn(commit('first', 'known', 0));
      expect((await adventureRepo.getRuntimeHead(adventureId, 0)).revision, 1);
      await adventureRepo.commitSceneDialogueTurn(commit('noop', 'known', 1));
      await adventureRepo
          .commitSceneDialogueTurn(commit('unknown', 'missing', 1));
      expect((await adventureRepo.getRuntimeHead(adventureId, 0)).revision, 1);
      expect(
          await adventureRepo.getRuntimeEntities(adventureId, 0), hasLength(1));
    });

    test('confirmed non-character entity can receive a runtime overlay',
        () async {
      final adventureId = await adventureRepo.createAdventure(
          'seeded faction', AdventureConfig());
      await adventureRepo.seedRuntimeEntity(
        adventureId: adventureId,
        branchId: 0,
        entityType: RuntimeEntityType.faction,
        entityId: 'white_guard',
      );
      await adventureRepo.commitSceneDialogueTurn(SceneDialogueCommit(
        requestId: 'faction-destroyed',
        adventureId: adventureId,
        branchId: 0,
        userMessage: Message(id: 'u', content: 'u', isUser: true),
        assistantMessage: Message(id: 'a', content: 'a', isUser: false),
        gameState: GameState(adventureId: adventureId),
        runtimeStateDraft: const RuntimeStateCommitDraft(
            expectedRevision: 0,
            summary: 'faction',
            changes: [
              RuntimeStateChangeProposal(
                  entityType: RuntimeEntityType.faction,
                  entityId: 'white_guard',
                  changeKind: RuntimeChangeKind.primary,
                  operation: RuntimeChangeOperation.set,
                  path: 'lifecycle_status',
                  value: 'destroyed',
                  reason: 'confirmed event'),
            ]),
      ));
      final entity =
          (await adventureRepo.getRuntimeEntities(adventureId, 0)).single;
      expect(entity.lifecycleStatus, 'destroyed');
      expect((await adventureRepo.getRuntimeHead(adventureId, 0)).revision, 1);
    });
  });
}
