import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/application/conversation/export_conversation_use_case.dart';
import 'package:lt_dialogue/engines/chat_engine_internals/prompt_builder.dart';
import 'package:lt_dialogue/engines/chat_engine_internals/stream_handler.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_response.dart';
import 'package:lt_dialogue/models/dialogue_level.dart';
import 'package:lt_dialogue/models/game_state.dart';
import 'package:lt_dialogue/models/llm_provider.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/models/scene_dialogue.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/key_vault.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/settings_repository_impl.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;
  late LibraryRepositoryImpl libraryRepo;
  late AdventureRepositoryImpl adventureRepo;
  late SettingsRepositoryImpl settingsRepo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('lt_e2e_test_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();

    libraryRepo = LibraryRepositoryImpl(getDb: () => DatabaseService.database);
    adventureRepo = AdventureRepositoryImpl(getDb: () => DatabaseService.database);
    settingsRepo = SettingsRepositoryImpl(getDb: () => DatabaseService.database);
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('Phase 6: End-to-End Full Lifecycle Verification', () {
    test('Flow A: Settings & KeyVault Configuration Lifecycle', () async {
      // 1. Configure custom provider settings and encrypted key
      const provider = LLMProvider.deepseek;
      const apiKey = 'sk-deepseek-test-key-123456';
      const customBaseUrl = 'https://api.deepseek.com/v1';

      final encryptedKey = KeyVault.encrypt(apiKey);
      expect(encryptedKey, isNot(equals(apiKey)));
      await settingsRepo.setEncryptedApiKey(provider.name, encryptedKey);

      final readEncryptedMap = await settingsRepo.getEncryptedApiKeys();
      expect(readEncryptedMap.containsKey(provider.name), isTrue);
      final decryptedKey = KeyVault.decrypt(readEncryptedMap[provider.name]!);
      expect(decryptedKey, equals(apiKey));

      await settingsRepo.saveLlmConfiguration(
        provider: provider.name,
        model: 'deepseek-v4-flash',
        baseUrl: customBaseUrl,
      );

      // 2. Configure conversation parameters
      await settingsRepo.setSetting('dialogue_level', DialogueLevel.l3.id);
      await settingsRepo.setSetting('max_tokens', '4096');
      await settingsRepo.setSetting('temperature', '0.7');

      expect(await settingsRepo.getSetting('dialogue_level'), equals('L3'));
      expect(await settingsRepo.getSetting('max_tokens'), equals('4096'));
      expect(await settingsRepo.getSetting('temperature'), equals('0.7'));
    });

    test('Flow B: Resource Library Complete CRUD & Search Lifecycle', () async {
      final now = DateTime.now().toIso8601String();

      // 1. Create Worldview Preset
      await libraryRepo.saveWorldviewPreset(
        id: 'wv_cyber_01',
        name: '赛博新夜之城 2077',
        description: '高科技与低生活交织的未来都市',
        entriesJson: jsonEncode([
          {'key': '时代', 'value': '赛博朋克 2077'},
          {'key': '规则', 'value': '义体改造高度普及，企业垄断一切资源'},
        ]),
        now: now,
        source: 'manual',
      );

      final loadedWvs = await libraryRepo.getWorldviewPresets();
      final loadedWv = loadedWvs.firstWhere((w) => w['id'] == 'wv_cyber_01');
      expect(loadedWv['name'], equals('赛博新夜之城 2077'));

      // 2. Create Character Card linked to Worldview
      final charJson = jsonEncode({
        'name': '艾拉 (Ayla)',
        'description': '身怀绝技的前企业黑客，行动敏捷。',
        'personality': '冷静、机警、外冷内热',
        'greeting': '黑入系统只需要三秒钟，但你最好跟紧我。',
        'tags': ['黑客', '女主角', '义体'],
      });
      await libraryRepo.saveCharacterCard(
        id: 'char_ayla_01',
        name: '艾拉 (Ayla)',
        jsonData: charJson,
        source: 'manual',
        now: now,
        matchingWorldviewId: 'wv_cyber_01',
      );

      final loadedChars = await libraryRepo.getCharacterCards();
      final loadedChar = loadedChars.firstWhere((c) => c['id'] == 'char_ayla_01');
      expect(loadedChar['name'], equals('艾拉 (Ayla)'));
      expect(loadedChar['matching_worldview_id'], equals('wv_cyber_01'));

      // 3. Create NPC Card
      final npcJson = jsonEncode({
        'name': '老兵杰克',
        'description': '退役的义体突击队员，经营地下武器工坊。',
        'personality': '粗犷、豪爽、重信誉',
      });
      await libraryRepo.saveNpcCard(
        id: 'npc_jack_01',
        name: '老兵杰克',
        jsonData: npcJson,
        source: 'manual',
        now: now,
        matchingWorldviewId: 'wv_cyber_01',
      );

      final loadedNpcs = await libraryRepo.getNpcCards();
      expect(loadedNpcs.any((n) => n['id'] == 'npc_jack_01'), isTrue);

      // 4. Create Adventure Template
      await libraryRepo.saveAdventureTemplate(
        id: 'tpl_neon_abyss',
        name: '霓虹深渊探索',
        worldviewName: '赛博新夜之城 2077',
        worldviewDesc: '高科技与低生活交织的未来都市',
        charDataJson: charJson,
        npcDataJson: jsonEncode([npcJson]),
        createdAt: now,
      );

      final loadedTemplates = await libraryRepo.getAdventureTemplates();
      final loadedTpl = loadedTemplates.firstWhere((t) => t['id'] == 'tpl_neon_abyss');
      expect(loadedTpl['name'], equals('霓虹深渊探索'));
      expect(loadedTpl['worldview_name'], equals('赛博新夜之城 2077'));

      // 5. Delete NPC and verify removal
      await libraryRepo.deleteNpcCard('npc_jack_01');
      final updatedNpcs = await libraryRepo.getNpcCards();
      expect(updatedNpcs.any((n) => n['id'] == 'npc_jack_01'), isFalse);
    });

    test('Flow C: Scene Dialogue Lifecycle, Streaming Effects & Export', () async {
      // 1. Create Adventure
      final config = AdventureConfig(
        name: '艾拉',
        worldview: '赛博新夜之城 2077',
      );
      final adventureId = await adventureRepo.createAdventure(
        '赛博夜之城行动',
        config,
      );
      expect(adventureId, isPositive);

      // 2. Initialize GameState
      final initialGameState = GameState(
        adventureId: adventureId,
        hp: 100,
        maxHp: 100,
        energy: 100,
        maxEnergy: 100,
        gold: 50,
        level: 1,
        currentScene: '霓虹街区入口',
      );
      await adventureRepo.saveGameState(initialGameState);

      // 3. Insert User Message
      final userMessage = Message(
        id: 'msg_user_1',
        content: '我拔出热能匕首，警惕地靠近前方的废弃仓库。',
        isUser: true,
      );
      await adventureRepo.insertMessage(adventureId, userMessage);

      // 4. PromptBuilder context formatting
      final promptBuilder = PromptBuilder();
      final contextSnapshot = SceneDialogueContextSnapshot(
        id: 'snap_01',
        userInput: userMessage.content,
        gameState: initialGameState.toMap(),
        recentMessages: [userMessage],
        actor: const SceneParticipantRef(id: 'char_ayla_01', name: '艾拉', kind: 'player'),
        presentParticipants: const [
          SceneParticipantRef(id: 'char_ayla_01', name: '艾拉', kind: 'player'),
        ],
        currentLocation: initialGameState.currentScene,
        confirmedWorldview: const {'时代': '赛博朋克 2077'},
        budget: SceneDialogueOutputBudget.resolve(DialogueLevel.l3),
      );

      final frozenContext = promptBuilder.buildFrozenSceneContext(contextSnapshot);
      expect(frozenContext, contains('行动者：艾拉'));
      expect(frozenContext, contains('地点：霓虹街区入口'));

      // 5. Dual-segment LLM response with AdventureResponse parsing
      const narrativeSegment = '仓库的铁门半掩着，幽蓝色的荧光在深处闪烁。你轻步潜入，忽然听到头顶通风管道传来机械爪的抓挠声！';
      final effectsJson = jsonEncode({
        'hp': 95,
        'energy': 70,
        'gold': 75,
        'scene': '废弃机械仓库内部',
        'options': ['拔枪向上射击', '就地翻滚寻找掩体', '使用黑客协议瘫痪通风系统'],
      });

      final fullLlmOutput = '$narrativeSegment\n\n---JSON---\n$effectsJson';
      final parsed = AdventureResponse.tryParseSplit(fullLlmOutput);
      expect(parsed, isNotNull);
      expect(parsed!.narrative.first, contains('仓库的铁门半掩着'));
      expect(parsed.hp, equals(95));
      expect(parsed.energy, equals(70));
      expect(parsed.gold, equals(75));
      expect(parsed.scene, equals('废弃机械仓库内部'));
      expect(parsed.options, hasLength(3));

      // 6. TypewriterController simulates smooth stream delivery
      final typewriter = TypewriterController();
      final textNotifier = ValueNotifier<String>('');
      int updateCount = 0;
      typewriter.feed(narrativeSegment, textNotifier, () => updateCount++);
      typewriter.cancel();

      // 7. Update GameState with effects
      final updatedGameState = GameState(
        adventureId: adventureId,
        hp: parsed.hp,
        maxHp: initialGameState.maxHp,
        energy: parsed.energy,
        maxEnergy: initialGameState.maxEnergy,
        gold: parsed.gold,
        level: initialGameState.level,
        currentScene: parsed.scene,
      );
      await adventureRepo.saveGameState(updatedGameState);

      // 8. Save Assistant Message
      final assistantMessage = Message(
        id: 'msg_asst_1',
        content: parsed.narrative.first,
        isUser: false,
      );
      await adventureRepo.insertMessage(adventureId, assistantMessage);

      // 9. Verify SQLite persistence of conversation history & updated game state
      final loadedMessages = await adventureRepo.getMessages(adventureId);
      expect(loadedMessages, hasLength(2));
      expect(loadedMessages[0].isUser, isTrue);
      expect(loadedMessages[1].isUser, isFalse);

      final loadedGameState = await adventureRepo.getGameState(adventureId);
      expect(loadedGameState, isNotNull);
      expect(loadedGameState!.hp, equals(95));
      expect(loadedGameState.energy, equals(70));
      expect(loadedGameState.gold, equals(75));
      expect(loadedGameState.currentScene, equals('废弃机械仓库内部'));

      // 10. Export conversation using ConversationExportUseCase
      const exporter = ConversationExportUseCase();
      final conversationMarkdown = StringBuffer();
      conversationMarkdown.writeln('# 赛博夜之城行动');
      conversationMarkdown.writeln('**当前地点**：${loadedGameState.currentScene}');
      conversationMarkdown.writeln('**生命值**：${loadedGameState.hp} / ${loadedGameState.maxHp}\n');
      for (final msg in loadedMessages) {
        conversationMarkdown.writeln('### ${msg.isUser ? "USER" : "ASSISTANT"}');
        conversationMarkdown.writeln(msg.content);
        conversationMarkdown.writeln();
      }
      conversationMarkdown.writeln('**可选行动**：');
      for (final opt in parsed.options) {
        conversationMarkdown.writeln('- $opt');
      }

      final exportedPath = await exporter.saveToFile(
        content: conversationMarkdown.toString(),
        extension: 'md',
        title: '赛博夜之城行动_测试导出',
      );
      expect(exportedPath, isNotNull);
      final exportedFile = File(exportedPath!);
      expect(await exportedFile.exists(), isTrue);

      final exportedContent = await exportedFile.readAsString();
      expect(exportedContent, contains('废弃机械仓库内部'));
      expect(exportedContent, contains('拔枪向上射击'));

      // Clean up export file
      try {
        await exportedFile.delete();
      } catch (_) {}
    });
  });
}
