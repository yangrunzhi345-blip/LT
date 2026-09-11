import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:lt_dialogue/config/app_config.dart';
import 'package:lt_dialogue/engines/chat_engine.dart';
import 'package:lt_dialogue/engines/chat_engine_host.dart';
import 'package:lt_dialogue/engines/chat_engine_internals/prompt_builder.dart';
import 'package:lt_dialogue/engines/chat_engine_internals/response_length_guard.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/custom_attribute_item.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:lt_dialogue/models/adventure_response.dart';
import 'package:lt_dialogue/models/character_card.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/models/conversation_character_card.dart';
import 'package:lt_dialogue/models/dialogue_level.dart';
import 'package:lt_dialogue/models/game_state.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/models/model_capabilities.dart';
import 'package:lt_dialogue/models/model_context_capability.dart';
import 'package:lt_dialogue/models/scene_dialogue.dart';
import 'package:lt_dialogue/models/scene_dialogue_effects.dart';
import 'package:lt_dialogue/models/worldview_preset.dart';
import 'package:lt_dialogue/providers/adventure_provider.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository.dart';
import '../support/chat_engine_host_fixture.dart';

final class _MockAdventureRepository extends Mock
    implements IAdventureRepository {}

final class _ThinkingPolicyLlmService extends LLMService {
  final List<LLMStreamResult> responses;
  final List<CompletionParams> receivedParams = [];
  final List<bool> receivedReasoningCallbacks = [];

  _ThinkingPolicyLlmService(this.responses)
      : super(const LLMConfig(
          provider: LLMProvider.deepseek,
          apiKey: 'test-key',
          baseUrl: 'https://example.invalid',
          model: 'deepseek-flash',
        ));

  @override
  Future<LLMStreamResult> sendMessageStreamDetailed(
    List<Map<String, String>> messages,
    void Function(String chunk) onChunk,
    void Function() onDone, {
    void Function(String reasoningChunk)? onReasoningChunk,
    CompletionParams params = const CompletionParams(),
    GenerationTaskHandle? taskHandle,
  }) async {
    receivedParams.add(params);
    receivedReasoningCallbacks.add(onReasoningChunk != null);
    final response = responses[receivedParams.length - 1];
    if (response.reasoningContent case final reasoning?) {
      onReasoningChunk?.call(reasoning);
    }
    onChunk(response.content);
    onDone();
    return response;
  }
}

ChatEngineHost _buildHost({
  required LLMService llm,
  required CompletionParams userParams,
  required List<Message> messages,
  String gameTopic = '测试',
}) {
  var gameState = GameState();
  return ChatDependencies(
    getApiKey: () => 'test-key',
    getApiBaseUrl: () => 'https://example.invalid',
    getProviderType: () => LLMProvider.deepseek,
    getModelName: () => 'deepseek-flash',
    getCustomSystemPrompt: () => '',
    getAuthorsNote: () => '',
    getAuthorsNoteDepth: () => 0,
    getAuthorsNoteFrequency: () => 0,
    getAdventureConfig: () => null,
    getWorldEntries: () => const [],
    getBrightness: () => Brightness.light,
    getGameTopic: () => gameTopic,
    getGameDifficulty: () => '普通',
    getCompletionParams: () => userParams,
    getCurrentAdventureId: () => null,
    getCurrentBranchId: () => 0,
    getActivePersona: () => null,
    getSelectedCharacterName: () => null,
    getTts: () => null,
    getLLMService: () => llm,
    setProvider: (_) async {},
    setModel: (_) async {},
    getGameState: () => gameState,
    setGameState: (value) => gameState = value,
    getMessages: () => messages,
    setMessages: (value) {
      messages
        ..clear()
        ..addAll(value);
    },
    getDialogueLevel: () => DialogueLevel.l2,
  );
}

ChatEngine _buildThinkingPolicyEngine({
  required _ThinkingPolicyLlmService llm,
  required CompletionParams userParams,
  required List<Message> messages,
}) {
  return ChatEngine(
    host: _buildHost(llm: llm, userParams: userParams, messages: messages),
    notifyParent: () {},
    adventureRepo: _MockAdventureRepository(),
  );
}

void main() {
  group('Prompt assembly determinism', () {
    test('identical input yields byte-identical messages', () {
      final builder = PromptBuilder();
      final messages = <Message>[
        Message(id: 'u1', content: '前进', isUser: true),
        Message(id: 'a1', content: '你走进白港。', isUser: false),
      ];
      final host = _buildHost(
        llm: _ThinkingPolicyLlmService(const []),
        userParams: const CompletionParams(),
        messages: messages,
      );

      final first = builder.buildMessages(host, '观察四周', messages, null, null);
      final second = builder.buildMessages(host, '观察四周', messages, null, null);

      expect(second, equals(first));
      final system = first.firstWhere((m) => m['role'] == 'system')['content']!;
      // The stable prefix carries the protocol; it must not embed per-request
      // markers that would break DeepSeek prompt-cache prefix reuse.
      expect(system, contains('---JSON---'));
      expect(system, isNot(contains('requestId')));
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

    test('ModelContextCapability defaults and JSON serialization roundtrip',
        () {
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

    test(
        'ConversationCharacterCardDefaults provides valid initial assistant info',
        () {
      expect(ConversationCharacterCardDefaults.id,
          equals('conversation_naila_default'));
      expect(ConversationCharacterCardDefaults.name, equals('奈拉'));
      expect(ConversationCharacterCardDefaults.jsonData, contains('奈拉'));
      expect(ConversationCharacterCardDefaults.data['role'], contains('AI 助手'));
    });
  });

  group('AdventureResponse Custom Status Parsing Tests', () {
    test(
        'AdventureResponse.tryParseSplit parses narrative, custom_status and options',
        () {
      const aiRaw = '''你踏入古老的神庙，四周弥漫着黑雾。
---JSON---
{
  "options": ["点燃火把", "拔剑戒备"],
  "custom_status": [
    {"name": "SAN值", "value": "75/100"},
    {"name": "污染度", "value": "中度"}
  ]
}''';
      final parsed = AdventureResponse.tryParseSplit(aiRaw);
      expect(parsed, isNotNull);
      expect(parsed!.narrative.join('\n'), contains('你踏入古老的神庙，四周弥漫着黑雾。'));
      expect(parsed.options, equals(['点燃火把', '拔剑戒备']));
      expect(parsed.customStatus.length, equals(2));
      expect(parsed.customStatus[0].name, equals('SAN值'));
      expect(parsed.customStatus[0].value, equals('75/100'));
      expect(parsed.customStatus[1].name, equals('污染度'));
      expect(parsed.customStatus[1].value, equals('中度'));
    });

    test('AdventureResponse.tryParseSplit parses when custom_status is absent',
        () {
      const aiRaw = '''你环顾四周，没有发生任何异常。
---JSON---
{
  "options": ["继续前进", "原地休息"]
}''';
      final parsed = AdventureResponse.tryParseSplit(aiRaw);
      expect(parsed, isNotNull);
      expect(parsed!.narrative.join('\n'), contains('你环顾四周，没有发生任何异常。'));
      expect(parsed.options, equals(['继续前进', '原地休息']));
      expect(parsed.customStatus, isEmpty);
    });

    test('AdventureResponse parses custom_status from map format', () {
      const jsonStr = '''
{
  "narrative": "迷雾渐渐散去。",
  "options": ["离开"],
  "custom_status": {
    "饥饿度": "30%",
    "异化程度": "轻微"
  }
}''';
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final resp = AdventureResponse.fromJson(map);
      expect(resp.customStatus.length, equals(2));
      expect(resp.customStatus.any((e) => e.name == '饥饿度' && e.value == '30%'),
          isTrue);
      expect(resp.customStatus.any((e) => e.name == '异化程度' && e.value == '轻微'),
          isTrue);
    });

    test(
        'AdventureResponse parses multi-character custom_status grouped by characterName',
        () {
      const jsonStr = '''
{
  "narrative": "两人相视一笑。",
  "options": ["继续前行"],
  "custom_status": {
    "莉莉安娜·冯·艾德斯坦": {
      "好感度": 62
    },
    "艾莉丝·冯·奥伯莱恩": {
      "好感度": 60
    }
  }
}''';
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final resp = AdventureResponse.fromJson(map);
      expect(resp.customStatus.length, equals(2));

      final lili =
          resp.customStatus.firstWhere((e) => e.characterName == '莉莉安娜·冯·艾德斯坦');
      expect(lili.name, equals('好感度'));
      expect(lili.currentValue, equals(62));

      final alice =
          resp.customStatus.firstWhere((e) => e.characterName == '艾莉丝·冯·奥伯莱恩');
      expect(alice.name, equals('好感度'));
      expect(alice.currentValue, equals(60));
    });
  });

  group('Multi-Character Custom Attributes and Prompt Tests', () {
    test(
        'AdventureConfig.allTrackedCustomAttributes gathers protagonist and alive companions with characterName',
        () {
      final config = AdventureConfig(
        name: '莉莉安娜·冯·艾德斯坦',
        customAttributes: const [
          CustomAttributeItem(
              id: 'a1',
              name: '好感度',
              value: '62/100',
              currentValue: 62,
              maxValue: 100),
        ],
        supportingCharacters: [
          SupportingCharacter(
            name: '艾莉丝·冯·奥伯莱恩',
            isAlive: true,
            customAttributes: const [
              CustomAttributeItem(
                  id: 'a2',
                  name: '好感度',
                  value: '60/100',
                  currentValue: 60,
                  maxValue: 100),
            ],
          ),
          SupportingCharacter(
            name: '已故导师',
            isAlive: false,
            customAttributes: const [
              CustomAttributeItem(id: 'a3', name: '好感度', value: '10/100'),
            ],
          ),
        ],
      );

      final all = config.allTrackedCustomAttributes;
      expect(all.length, equals(2));
      expect(all[0].characterName, equals('莉莉安娜·冯·艾德斯坦'));
      expect(all[0].name, equals('好感度'));
      expect(all[0].effectiveCurrentValue, equals(62));

      expect(all[1].characterName, equals('艾莉丝·冯·奥伯莱恩'));
      expect(all[1].name, equals('好感度'));
      expect(all[1].effectiveCurrentValue, equals(60));
    });

    test(
        'AppConfig.adventurePrompt includes multi-character custom status instructions',
        () {
      final config = AdventureConfig(
        name: '莉莉安娜·冯·艾德斯坦',
        customAttributes: const [
          CustomAttributeItem(
              id: 'a1',
              name: '好感度',
              value: '62/100',
              currentValue: 62,
              maxValue: 100),
        ],
        supportingCharacters: [
          SupportingCharacter(
            name: '艾莉丝·冯·奥伯莱恩',
            isAlive: true,
            customAttributes: const [
              CustomAttributeItem(
                  id: 'a2',
                  name: '好感度',
                  value: '60/100',
                  currentValue: 60,
                  maxValue: 100),
            ],
          ),
        ],
      );

      final prompt = AppConfig.adventurePrompt(
        Brightness.light,
        '奇幻森林',
        '普通',
        config,
        false,
        1,
      );

      expect(prompt, contains('当前需追踪的自定义检测状态（含稳定 ID，变化时按 ID 引用；名称仅作历史兼容）：'));
      expect(prompt, contains('[莉莉安娜·冯·艾德斯坦] 【参考】好感度：62/100'));
      expect(prompt, contains('[艾莉丝·冯·奥伯莱恩] 【参考】好感度：60/100'));
      expect(prompt, contains('custom_status_changes'));
      expect(prompt, contains('【状态变更规则（Delta 增量协议，只输出变化）】：'));
    });
  });

  group('Message In-Place Overwrite & Deduplication Tests', () {
    test(
        'deduplicateConsecutiveUserMessages collapses consecutive identical user messages into one',
        () {
      final messages = [
        Message(id: '1', content: '初始剧情', isUser: false),
        Message(id: '2', content: '直接询问艾莉丝是否认得这条暗红细线的来历', isUser: true),
        Message(id: '3', content: '直接询问艾莉丝是否认得这条暗红细线的来历', isUser: true),
        Message(id: '4', content: '直接询问艾莉丝是否认得这条暗红细线的来历', isUser: true),
      ];

      final cleaned =
          AdventureProvider.deduplicateConsecutiveUserMessages(messages);
      expect(cleaned.length, equals(2));
      expect(cleaned[0].content, equals('初始剧情'));
      expect(cleaned[1].content, equals('直接询问艾莉丝是否认得这条暗红细线的来历'));
      expect(cleaned[1].id, equals('2'));
    });

    test(
        'deduplicateConsecutiveUserMessages retains alternating turns and different actions',
        () {
      final messages = [
        Message(id: '1', content: '第一幕', isUser: false),
        Message(id: '2', content: '行动A', isUser: true),
        Message(id: '3', content: '第二幕', isUser: false),
        Message(id: '4', content: '行动B', isUser: true),
      ];

      final cleaned =
          AdventureProvider.deduplicateConsecutiveUserMessages(messages);
      expect(cleaned.length, equals(4));
    });
  });

  group('Multi-Stage Pipeline Word Count & Deficit Feedback Tests', () {
    test(
        'ChatEngine.countChinese accurately filters punctuation, spaces and non-Chinese characters',
        () {
      const mixedText = '第一幕：艾莉丝拔出长剑！"Ready?" 500 gold coins.';
      // 纯汉字: 第 一 幕 艾 莉 丝 拔 出 长 剑 = 10个
      expect(ChatEngine.countChinese(mixedText), equals(10));
    });

    test('planStage distributes remaining target and never exceeds hard max',
        () {
      // L5: min 4500, target 6500, hardMax 10000.
      var plan = SceneDialogueOutputBudget.planStage(
        stage: 1,
        currentChars: 0,
        targetChars: 6500,
        hardMaximum: 10000,
        maxStages: 4,
      );
      expect(plan.isFinal, isFalse);
      expect(plan.charTarget, 3250);

      // After stage 1 wrote ~3250 chars, remaining target 3250 over 3 stages.
      plan = SceneDialogueOutputBudget.planStage(
        stage: 2,
        currentChars: 3250,
        targetChars: 6500,
        hardMaximum: 10000,
        maxStages: 4,
      );
      expect(plan.isFinal, isFalse);
      expect(plan.charTarget, 1084);
    });

    test('planStage concludes once the target is reached', () {
      final plan = SceneDialogueOutputBudget.planStage(
        stage: 3,
        currentChars: 6600,
        targetChars: 6500,
        hardMaximum: 10000,
        maxStages: 4,
      );
      expect(plan.isFinal, isTrue);
      expect(plan.charTarget, 0);
    });

    test('planStage caps at the hard maximum and settles', () {
      final plan = SceneDialogueOutputBudget.planStage(
        stage: 2,
        currentChars: 10100,
        targetChars: 6500,
        hardMaximum: 10000,
        maxStages: 4,
      );
      expect(plan.isFinal, isTrue);
      expect(plan.charTarget, 0);
    });

    test('hardMaximum is bounded by min*3 and never exceeds the tier max', () {
      expect(SceneDialogueOutputBudget.l0.hardMaximum, 150);
      expect(SceneDialogueOutputBudget.l1.hardMaximum, 300);
      expect(SceneDialogueOutputBudget.l2.hardMaximum, 1000);
      expect(SceneDialogueOutputBudget.l3.hardMaximum, 2200);
      expect(SceneDialogueOutputBudget.l4.hardMaximum, 4500);
      expect(SceneDialogueOutputBudget.l5.hardMaximum, 10000);
    });

    test(
        'DialogueLevel L4 budget and prompt are never overridden by legacy quickMode',
        () {
      final budget =
          SceneDialogueOutputBudget.resolve(DialogueLevel.l4, quickMode: true);
      expect(budget.minChineseChars, equals(2500));
      expect(budget.targetChineseChars, equals(3200));
      expect(budget.hardMaximum, equals(4500));

      final prompt = AppConfig.adventurePrompt(
        Brightness.light,
        '奇幻森林',
        '普通',
        null,
        true, // quickMode: true
        1,
        DialogueLevel.l4,
      );
      expect(prompt, contains('深度长篇叙事模式（纯汉字范围 2500~4500 字，目标 3200 字）'));
      expect(prompt, isNot(contains('不设字数上限')));
      expect(prompt, isNot(contains('快速模式')));
    });
  });

  group('NarrativeLengthGuard', () {
    const guard = NarrativeLengthGuard();

    test('should merge one L2 supplement until the frozen minimum is met', () {
      final initial = '${'叙事内容' * 65}\n---JSON---\n{"options": []}';
      final supplement = '补充内容' * 45;
      final result = guard.merge(
        initialRawResponse: initial,
        supplementRawResponse: supplement,
        supplementSucceeded: true,
      );

      expect(result.initialChineseChars, equals(260));
      expect(result.supplementChineseChars, equals(180));
      expect(result.finalChineseChars, equals(440));
      expect(
          result.passed(SceneDialogueOutputBudget.l2.minChineseChars), isTrue);
    });

    test('should not plan a supplement when the initial narrative passes', () {
      final result = guard.withoutSupplement('叙事内容' * 163);

      expect(result.finalChineseChars, greaterThanOrEqualTo(400));
      expect(
          result.passed(SceneDialogueOutputBudget.l2.minChineseChars), isTrue);
      expect(result.supplementAttempted, isFalse);
    });

    test('should use the quick L0 frozen budget instead of legacy L0 words',
        () {
      final quickBudget =
          SceneDialogueOutputBudget.resolve(DialogueLevel.l0, quickMode: true);
      final result = guard.withoutSupplement('叙事内容' * 75);

      expect(quickBudget.minChineseChars, equals(500));
      expect(result.finalChineseChars, equals(300));
      expect(result.passed(quickBudget.minChineseChars), isFalse);
    });

    test('should not plan a supplement for a normal L0 response over 50', () {
      final normalBudget =
          SceneDialogueOutputBudget.resolve(DialogueLevel.l0, quickMode: false);
      final result = guard.withoutSupplement('叙事内容' * 20);

      expect(result.finalChineseChars, equals(80));
      expect(result.passed(normalBudget.minChineseChars), isTrue);
    });

    test('should preserve exactly one initial payload when merging', () {
      const initial = '第一段正文\n---JSON---\n{"options":["前进"]}';
      const supplement = '补写正文\n---JSON---\n{"options":["错误重复"]}';
      final result = guard.merge(
        initialRawResponse: initial,
        supplementRawResponse: supplement,
        supplementSucceeded: true,
      );

      expect(NarrativeLengthGuard.jsonMarker.allMatches(result.content),
          hasLength(1));
      expect(result.content, contains('"前进"'));
      expect(result.content, isNot(contains('"错误重复"')));
    });

    test(
        'should use the continuation payload only when the first response lacks one',
        () {
      const initial = '第一段尚未完成的正文';
      const supplement = '补写正文\n---JSON---\n{"options":["继续"]}';
      final result = guard.merge(
        initialRawResponse: initial,
        supplementRawResponse: supplement,
        supplementSucceeded: true,
      );

      expect(NarrativeLengthGuard.jsonMarker.allMatches(result.content),
          hasLength(1));
      expect(result.content, contains('"继续"'));
    });

    test('should remove a repeated continuation prefix deterministically', () {
      const initial = '雨声渐密，她推开了门。';
      const supplement = '她推开了门。冷风立刻灌入房间。';

      final result = guard.merge(
        initialRawResponse: initial,
        supplementRawResponse: supplement,
        supplementSucceeded: true,
      );

      expect(result.content, '雨声渐密，她推开了门。\n\n冷风立刻灌入房间。');
    });

    test('should retain a failed single supplement result without retrying',
        () {
      final initial = guard.withoutSupplement('叙事内容' * 10);
      final failed = NarrativeLengthGuardResult(
        content: initial.content,
        initialChineseChars: initial.initialChineseChars,
        supplementChineseChars: 0,
        finalChineseChars: initial.finalChineseChars,
        supplementAttempted: true,
        supplementSucceeded: false,
      );

      expect(failed.supplementAttempted, isTrue);
      expect(failed.supplementSucceeded, isFalse);
      expect(
          failed.passed(SceneDialogueOutputBudget.l2.minChineseChars), isFalse);
    });

    test('should disable thinking only in copied supplement parameters', () {
      const userParams = CompletionParams(
        enableThinking: true,
        reasoningEffort: 'high',
        temperature: 0.8,
        topP: 0.9,
        frequencyPenalty: 0.2,
        presencePenalty: 0.1,
        maxTokens: 8192,
      );

      final supplementParams = guard.supplementParams(
        userParams,
        maximumOutputTokens: 1536,
      );

      expect(userParams.enableThinking, isTrue);
      expect(userParams.maxTokens, equals(8192));
      expect(supplementParams.enableThinking, isFalse);
      expect(supplementParams.maxTokens, equals(1536));
      expect(supplementParams.reasoningEffort, equals('high'));
      expect(supplementParams.temperature, equals(0.8));
      expect(supplementParams.topP, equals(0.9));
      expect(supplementParams.frequencyPenalty, equals(0.2));
      expect(supplementParams.presencePenalty, equals(0.1));
    });

    test('should keep thinking disabled when the user already disabled it', () {
      const userParams = CompletionParams(
        enableThinking: false,
        maxTokens: 2048,
      );

      final supplementParams = guard.supplementParams(
        userParams,
        maximumOutputTokens: 1024,
      );

      expect(userParams.enableThinking, isFalse);
      expect(supplementParams.enableThinking, isFalse);
    });

    test('should map supplement parameters to DeepSeek thinking disabled', () {
      final supplementParams = guard.supplementParams(
        const CompletionParams(
          enableThinking: true,
          reasoningEffort: 'high',
        ),
        maximumOutputTokens: 1024,
      );
      final request = supplementParams.toRequestMap(
        capabilities: ModelCapabilityRegistry.deepSeekFlash,
      );

      expect(request['thinking'], equals({'type': 'disabled'}));
      expect(request.containsKey('reasoning_effort'), isFalse);
    });
  });

  group('ChatEngine length supplement thinking policy', () {
    test('should preserve main reasoning and disable supplement thinking',
        () async {
      const mainReasoning = '第一轮针对真实用户请求的思考';
      const unexpectedSupplementReasoning = '本不应该出现的补轮思考';
      final llm = _ThinkingPolicyLlmService([
        LLMStreamResult(
          content: '${'叙事内容' * 65}\n---JSON---\n{"options":["前进","观察","等待"]}',
          reasoningContent: mainReasoning,
          finishReason: LLMFinishReason.stop,
          responseCompleted: true,
        ),
        LLMStreamResult(
          content: '补充内容' * 45,
          reasoningContent: unexpectedSupplementReasoning,
          finishReason: LLMFinishReason.stop,
          responseCompleted: true,
        ),
      ]);
      const userParams = CompletionParams(
        enableThinking: true,
        reasoningEffort: 'high',
        maxTokens: 2048,
      );
      final messages = <Message>[];
      final engine = _buildThinkingPolicyEngine(
        llm: llm,
        userParams: userParams,
        messages: messages,
      );
      addTearDown(engine.dispose);

      await engine.sendMessage('推开门进入大厅');

      expect(llm.receivedParams, hasLength(2));
      expect(llm.receivedParams[0].enableThinking, isTrue);
      expect(llm.receivedParams[0].reasoningEffort, equals('high'));
      expect(llm.receivedParams[1].enableThinking, isFalse);
      expect(llm.receivedReasoningCallbacks, equals([true, false]));
      expect(userParams.enableThinking, isTrue);
      expect(messages.where((message) => message.isUser), hasLength(1));
      expect(messages.where((message) => !message.isUser), hasLength(1));
      expect(messages.last.reasoningContent, equals(mainReasoning));
      expect(messages.last.reasoningContent, isNot(contains('本不应该出现的补轮思考')));
      expect(engine.isThinkingNotifier.value, isFalse);
    });

    test('should keep both requests non-thinking when the user disabled it',
        () async {
      final llm = _ThinkingPolicyLlmService([
        LLMStreamResult(
          content: '${'叙事内容' * 65}\n---JSON---\n{"options":["前进","观察","等待"]}',
          finishReason: LLMFinishReason.stop,
          responseCompleted: true,
        ),
        LLMStreamResult(
          content: '补充内容' * 45,
          finishReason: LLMFinishReason.stop,
          responseCompleted: true,
        ),
      ]);
      const userParams = CompletionParams(
        enableThinking: false,
        maxTokens: 2048,
      );
      final engine = _buildThinkingPolicyEngine(
        llm: llm,
        userParams: userParams,
        messages: <Message>[],
      );
      addTearDown(engine.dispose);

      await engine.sendMessage('推开门进入大厅');

      expect(
        llm.receivedParams.map((params) => params.enableThinking),
        equals([false, false]),
      );
      expect(userParams.enableThinking, isFalse);
      expect(engine.isThinkingNotifier.value, isFalse);
    });
  });

  group('Structured response protocol classification', () {
    test('pure JSON is payloadOnly and never becomes narrative', () {
      const pureJson = '{"scene":"幽暗森林","hp":100,"max_hp":100,"energy":100,'
          '"max_energy":100,"gold":0,"options":["向前走","后退","观察"],'
          '"custom_status":[{"name":"SAN值","value":"80/100"}]}';

      final parsed = AdventureResponse.parse(pureJson);
      expect(parsed.kind, AdventureResponseKind.payloadOnly);
      expect(parsed.payload, isNotNull);
      expect(parsed.narrative, isEmpty);

      final canonical = AdventureResponse.canonicalize(pureJson);
      expect(canonical, startsWith('---JSON---'));
      expect(AdventureResponse.streamingDisplayText(pureJson), isEmpty);

      final response = AdventureResponse.tryParseSplit(pureJson);
      expect(response, isNotNull);
      expect(response!.narrative, isEmpty);
      expect(response.options, equals(['向前走', '后退', '观察']));
    });

    test('standard split JSON separates narrative from payload', () {
      const raw = '你推开木门，屋内一片漆黑。\n\n---JSON---\n'
          '{"scene":"木屋","options":["点火","退出","呼喊"]}';

      final parsed = AdventureResponse.parse(raw);
      expect(parsed.kind, AdventureResponseKind.narrativeWithPayload);
      expect(parsed.narrative.join(), contains('你推开木门'));

      final canonical = AdventureResponse.canonicalize(raw);
      final marker = canonical.indexOf('---JSON---');
      expect(marker, greaterThan(0));
      expect(canonical.substring(0, marker), isNot(contains('"options"')));
      expect(AdventureResponse.streamingDisplayText(raw),
          isNot(contains('"options"')));
    });

    test('inline JSON without the separator is split out of the narrative', () {
      const raw = '你推开木门，屋内一片漆黑。'
          '{"scene":"木屋","options":["点火","退出","呼喊"]}';

      final parsed = AdventureResponse.parse(raw);
      expect(parsed.kind, AdventureResponseKind.narrativeWithPayload);
      expect(parsed.narrative.join(), '你推开木门，屋内一片漆黑。');
      expect(parsed.narrative.join(), isNot(contains('"scene"')));

      final canonical = AdventureResponse.canonicalize(raw);
      final marker = canonical.indexOf('---JSON---');
      expect(marker, greaterThan(0));
      expect(canonical.substring(0, marker), isNot(contains('{')));

      final response = AdventureResponse.tryParseSplit(raw);
      expect(response, isNotNull);
      expect(response!.narrative.join(), isNot(contains('"scene"')));
      expect(response.options, equals(['点火', '退出', '呼喊']));
    });

    test('damaged JSON payload is never used as narrative', () {
      const pureDamaged = '{"scene":"大厅","options":["走","停"';
      final damaged = AdventureResponse.parse(pureDamaged);
      expect(damaged.kind, AdventureResponseKind.malformedStructured);
      expect(AdventureResponse.canonicalize(pureDamaged), isEmpty);
      expect(AdventureResponse.tryParseSplit(pureDamaged), isNull);

      const proseWithDamaged = '你走进大厅。\n---JSON---\n'
          '{"scene":"大厅","options":["走","停"';
      final mixed = AdventureResponse.parse(proseWithDamaged);
      expect(mixed.narrative.join(), '你走进大厅。');
      expect(AdventureResponse.canonicalize(proseWithDamaged), '你走进大厅。');
    });
  });

  group('ChatEngine payload-only narrative recovery', () {
    test('keeps the payload and adds one same-turn narrative supplement',
        () async {
      final llm = _ThinkingPolicyLlmService([
        const LLMStreamResult(
          content: '{"scene":"幽暗森林","options":["向前走","后退","观察四周"],'
              '"custom_status":{"SAN值":80}}',
          finishReason: LLMFinishReason.stop,
          responseCompleted: true,
        ),
        LLMStreamResult(
          content: '阴冷的雾气贴着地面翻涌，你握紧火把向前迈出一步。' * 20,
          finishReason: LLMFinishReason.stop,
          responseCompleted: true,
        ),
      ]);
      final messages = <Message>[];
      final engine = _buildThinkingPolicyEngine(
        llm: llm,
        userParams:
            const CompletionParams(enableThinking: false, maxTokens: 2048),
        messages: messages,
      );
      addTearDown(engine.dispose);

      await engine.sendMessage('进入森林');

      expect(llm.receivedParams, hasLength(2));
      final assistant = messages.lastWhere((message) => !message.isUser);
      final marker = assistant.content.indexOf('---JSON---');
      expect(marker, greaterThan(0));
      final body = assistant.content.substring(0, marker);
      expect(body, contains('阴冷的雾气'));
      expect(body, isNot(contains('"scene"')));
      expect(body, isNot(contains('"options"')));
      expect(body, isNot(contains('"custom_status"')));
      expect(assistant.content.substring(marker), contains('幽暗森林'));
      expect(engine.parsedOptions, equals(['向前走', '后退', '观察四周']));
    });
  });
}
