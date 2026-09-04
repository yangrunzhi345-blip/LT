import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/engines/chat_engine_internals/prompt_builder.dart';
import 'package:lt_dialogue/models/adventure_response.dart';
import 'package:lt_dialogue/models/character_card.dart';
import 'package:lt_dialogue/models/conversation_character_card.dart';
import 'package:lt_dialogue/models/dialogue_level.dart';
import 'package:lt_dialogue/models/game_state.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/models/model_context_capability.dart';
import 'package:lt_dialogue/models/scene_dialogue.dart';
import 'package:lt_dialogue/models/scene_dialogue_effects.dart';
import 'package:lt_dialogue/models/world_entry.dart';
import 'package:lt_dialogue/models/worldview_preset.dart';

void main() {
  group('PromptBuilder Tests', () {
    final builder = PromptBuilder();

    test('buildFrozenSceneContext formats snapshot fields correctly', () {
      final snapshot = SceneDialogueContextSnapshot(
        id: 'snapshot_1',
        userInput: '观察四周',
        gameState: GameState().toMap(),
        recentMessages: const [],
        actor: const SceneParticipantRef(id: 'player_1', name: '冒险家亚瑟', kind: 'player'),
        presentParticipants: const [
          SceneParticipantRef(id: 'player_1', name: '冒险家亚瑟', kind: 'player'),
          SceneParticipantRef(id: 'npc_1', name: '老铁匠格林', kind: 'npc'),
        ],
        currentLocation: '铁匠铺后院',
        confirmedWorldview: const {'时代': '蒸汽朋克', '魔力状态': '枯竭'},
        retrievalFacts: const ['黑铁矿石非常稀有', '格林曾经是王国第一工匠'],
        budget: SceneDialogueOutputBudget.resolve(DialogueLevel.l2),
      );

      final rendered = builder.buildFrozenSceneContext(snapshot);
      expect(rendered, contains('[本轮冻结场景上下文]'));
      expect(rendered, contains('地点：铁匠铺后院'));
      expect(rendered, contains('行动者：冒险家亚瑟'));
      expect(rendered, contains('在场角色：冒险家亚瑟、老铁匠格林'));
      expect(rendered, contains('已确认世界观：{"时代":"蒸汽朋克","魔力状态":"枯竭"}'));
      expect(rendered, contains('本冒险检索参考：黑铁矿石非常稀有\n格林曾经是王国第一工匠'));
      expect(rendered, contains('[冻结场景上下文结束]'));
    });

    test('wrapEarlyTimeline wraps summary with proper boundary markers', () {
      const summary = '- 亚瑟在酒馆结识了格林。\n- 两人决定前往废弃矿坑。';
      final wrapped = PromptBuilder.wrapEarlyTimeline(summary);

      expect(wrapped, contains('[早期事件时间线'));
      expect(wrapped, contains(summary));
      expect(wrapped, contains('[时间线结束 — 以下是最近6轮完整对话]'));
    });

    test('injectWorldInfo activates entries matching recent messages', () {
      final messages = [
        Message(
          id: 'm1',
          content: '我们来到了艾尔登废墟，寻找失落的符文石。',
          isUser: true,
          timestamp: DateTime.now(),
        ),
      ];

      final entries = [
        WorldEntry(
          id: 1,
          adventureId: 10,
          keys: ['艾尔登废墟', '废墟'],
          content: '艾尔登废墟是古代帝国的首都遗址，布满致命陷阱。',
          insertPosition: WorldEntryPosition.beforePrompt,
          enabled: true,
        ),
        WorldEntry(
          id: 2,
          adventureId: 10,
          keys: ['巨龙', '龙骨'],
          content: '巨龙早已灭绝。',
          insertPosition: WorldEntryPosition.beforePrompt,
          enabled: true,
        ),
      ];

      final resultBefore = builder.injectWorldInfo(
        WorldEntryPosition.beforePrompt,
        messages,
        entries,
      );

      expect(resultBefore, contains('艾尔登废墟是古代帝国的首都遗址'));
      expect(resultBefore, isNot(contains('巨龙早已灭绝')));

      // If position doesn't match, should not inject
      final resultAfter = builder.injectWorldInfo(
        WorldEntryPosition.afterPrompt,
        messages,
        entries,
      );
      expect(resultAfter, isEmpty);
    });
  });

  group('AdventureResponse Double-Segment Stream Tests', () {
    test('tryParseSplit separates narrative prose from ---JSON--- payload', () {
      const rawResponse = '''
你踏入昏暗的地窖，火把照亮了石壁上的远古壁画。
空气中弥漫着潮湿的泥土气息，远处传来隐约的水滴声。

---JSON---
{
  "scene": "地下迷宫一层",
  "hp": 95,
  "maxHp": 100,
  "energy": 80,
  "maxEnergy": 100,
  "gold": 50,
  "inventory": ["火把", "生锈铁剑"],
  "options": ["检查壁画", "继续深入地窖", "返回地面"]
}
''';

      final parsed = AdventureResponse.tryParseSplit(rawResponse);
      expect(parsed, isNotNull);
      expect(parsed!.narrative.length, greaterThanOrEqualTo(1));
      expect(parsed.narrative.join('\n'), contains('你踏入昏暗的地窖'));
      expect(parsed.narrative.join('\n'), contains('空气中弥漫着潮湿的泥土气息'));
      expect(parsed.narrative.join('\n'), isNot(contains('---JSON---')));
      expect(parsed.narrative.join('\n'), isNot(contains('"scene"')));

      expect(parsed.scene, equals('地下迷宫一层'));
      expect(parsed.hp, equals(95));
      expect(parsed.gold, equals(50));
      expect(parsed.inventory, contains('火把'));
      expect(parsed.options, equals(['检查壁画', '继续深入地窖', '返回地面']));
    });

    test('tryParse handles pure JSON', () {
      const jsonStr = '''
{
  "scene": "幽暗森林",
  "hp": 100,
  "maxHp": 100,
  "energy": 100,
  "maxEnergy": 100,
  "gold": 20,
  "narrative": ["树林密不透风。"],
  "options": ["向前走"]
}
''';
      final parsed = AdventureResponse.tryParse(jsonStr);
      expect(parsed, isNotNull);
      expect(parsed!.scene, equals('幽暗森林'));
      expect(parsed.options, equals(['向前走']));
    });
  });

  group('Models Serialization Tests', () {
    test('Message copyWith and properties', () {
      final msg = Message(
        id: 'msg_100',
        content: '你好，世界！',
        isUser: false,
        timestamp: DateTime.utc(2026, 9, 4, 12, 0, 0),
      );

      expect(msg.id, equals('msg_100'));
      expect(msg.content, equals('你好，世界！'));
      expect(msg.isUser, equals(false));

      final updated = msg.copyWith(content: '新内容');
      expect(updated.id, equals('msg_100'));
      expect(updated.content, equals('新内容'));
    });

    test('GameState toMap and fromMap roundtrip', () {
      final state = GameState(
        adventureId: 42,
        hp: 85,
        maxHp: 100,
        energy: 60,
        maxEnergy: 80,
        gold: 150,
        inventory: ['治疗药水', '匕首'],
        currentScene: '王都集市',
      );

      final map = state.toMap();
      final revived = GameState.fromMap(map);

      expect(revived.adventureId, equals(42));
      expect(revived.hp, equals(85));
      expect(revived.gold, equals(150));
      expect(revived.inventory, equals(['治疗药水', '匕首']));
      expect(revived.currentScene, equals('王都集市'));
    });

    test('CharacterCard toJson and fromJson roundtrip', () {
      final card = CharacterCard(
        name: '卡莲',
        description: '忠诚勇敢的年轻骑士。',
        personality: '严谨、正直、略带傲娇',
        firstMessage: '向您致敬，指挥官。',
        appearance: '银白铠甲，金色长发',
      );

      final json = card.toJson();
      final revived = CharacterCard.fromJson(json);

      expect(revived.name, equals('卡莲'));
      expect(revived.description, equals('忠诚勇敢的年轻骑士。'));
      expect(revived.firstMessage, equals('向您致敬，指挥官。'));
      expect(revived.appearance, equals('银白铠甲，金色长发'));
    });

    test('WorldviewPreset toJson and fromJson roundtrip', () {
      final preset = WorldviewPreset(
        id: 'wv_1',
        name: '赛博夜之城',
        description: '高科技，低生活。霓虹灯照耀下的罪恶之都。',
      );

      final json = preset.toJson();
      final revived = WorldviewPreset.fromJson(json);

      expect(revived.name, equals('赛博夜之城'));
      expect(revived.description, equals('高科技，低生活。霓虹灯照耀下的罪恶之都。'));
    });

    test('SceneDialogueEffects parsed and applied to GameState', () {
      const jsonEffect = '''
{
  "level": 3,
  "experience": 450,
  "mp": 70,
  "max_mp": 120,
  "base_atk": 15,
  "base_def": 8,
  "base_speed": 12,
  "skill_points": 2,
  "affinity_change": {"卡莲": 5}
}
''';
      final map = jsonDecode(jsonEffect) as Map<String, dynamic>;
      final effects = SceneDialogueEffects.fromJson(map);

      expect(effects.level, equals(3));
      expect(effects.experience, equals(450));
      expect(effects.mp, equals(70));
      expect(effects.baseAtk, equals(15));
      expect(effects.affinityChanges['卡莲'], equals(5));

      final state = GameState(level: 1, mp: 50, baseAtk: 5);
      final updatedState = effects.applyState(state);

      expect(updatedState.level, equals(3));
      expect(updatedState.mp, equals(70));
      expect(updatedState.baseAtk, equals(15));
    });

    test('ModelContextCapability defaults and JSON serialization roundtrip', () {
      const cap = ModelContextCapability(
        providerId: 'openai',
        modelId: 'gpt-4o',
        maximumContextTokens: 128000,
        maximumOutputTokens: 4096,
        supportsPromptCaching: true,
        supportsStructuredOutput: true,
      );

      final json = cap.toJson();
      final revived = ModelContextCapability.fromJson(json);

      expect(revived.providerId, equals('openai'));
      expect(revived.modelId, equals('gpt-4o'));
      expect(revived.maximumContextTokens, equals(128000));
      expect(revived.maximumOutputTokens, equals(4096));
      expect(revived.supportsPromptCaching, isTrue);
      expect(revived.supportsStructuredOutput, isTrue);

      const fallback = ModelContextCapability.conservative();
      expect(fallback.maximumContextTokens, equals(8192));
      expect(fallback.maximumOutputTokens, equals(1024));
    });

    test('ConversationCharacterCardDefaults provides valid initial assistant info', () {
      expect(ConversationCharacterCardDefaults.id, equals('conversation_naila_default'));
      expect(ConversationCharacterCardDefaults.name, equals('奈拉'));
      expect(ConversationCharacterCardDefaults.jsonData, contains('奈拉'));
      expect(ConversationCharacterCardDefaults.data['role'], contains('AI 助手'));
    });
  });
}
