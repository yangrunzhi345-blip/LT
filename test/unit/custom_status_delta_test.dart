import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/engines/chat_engine.dart';
import 'package:lt_dialogue/engines/chat_engine_host.dart';
import 'package:lt_dialogue/managers/chat_dependencies.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_response.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/models/custom_attribute_item.dart';
import 'package:lt_dialogue/models/custom_status_change.dart';
import 'package:lt_dialogue/models/dialogue_level.dart';
import 'package:lt_dialogue/models/game_state.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:lt_dialogue/services/custom_status_merger.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository.dart';

CustomAttributeItem _num(String id, String name, int value,
        {String? charName, int max = 100}) =>
    CustomAttributeItem(
      id: id,
      name: name,
      value: '$value/$max',
      currentValue: value,
      maxValue: max,
      characterName: charName,
    );

CustomAttributeItem _text(String id, String name, String value,
        {String? charName}) =>
    CustomAttributeItem(
      id: id,
      name: name,
      value: value,
      characterName: charName,
    );

SupportingCharacter _npc(
        String id, String name, List<CustomAttributeItem> attrs) =>
    SupportingCharacter(id: id, name: name, customAttributes: attrs);

/// 4 个角色（1 主角 + 3 配角），每个 4 个自添加项 = 16 状态。
({
  String protagonistName,
  String protagonistId,
  List<CustomAttributeItem> protagonistAttributes,
  List<SupportingCharacter> supportingCharacters
}) _buildSixteenStates() {
  final protagonist = [
    _num('a1', '体力', 50, charName: '主角'),
    _num('a2', '好感度', 60, charName: '主角'),
    _num('a3', '理智', 80, charName: '主角'),
    _text('a4', '父亲失踪线索', '未知', charName: '主角'),
  ];
  final supporting = [
    _npc('npc_1', '艾莉丝', [
      _num('b1', '体力', 40, charName: '艾莉丝'),
      _num('b2', '好感度', 55, charName: '艾莉丝'),
      _text('b3', '潮感异常', '稳定', charName: '艾莉丝'),
      _text('b4', '秘密', '未揭示', charName: '艾莉丝'),
    ]),
    _npc('npc_2', '莫维奇', [
      _num('c1', '体力', 45, charName: '莫维奇'),
      _num('c2', '好感度', 30, charName: '莫维奇'),
      _text('c3', '阵营', '中立', charName: '莫维奇'),
      _text('c4', '线索', '无', charName: '莫维奇'),
    ]),
    _npc('npc_3', '索尔', [
      _num('d1', '体力', 70, charName: '索尔'),
      _num('d2', '好感度', 20, charName: '索尔'),
      _text('d3', '锻造秘法', '初级', charName: '索尔'),
      _text('d4', '立场', '中立', charName: '索尔'),
    ]),
  ];
  return (
    protagonistName: '主角',
    protagonistId: 'char_proto',
    protagonistAttributes: protagonist,
    supportingCharacters: supporting,
  );
}

void main() {
  group('CustomStatusChange parse', () {
    test('parses valid set/delta changes with id and name aliases', () {
      final diagnostics = <String>[];
      final changes = CustomStatusChange.parse([
        {
          'character_id': 'char_1',
          'attribute_id': 'a1',
          'operation': 'set',
          'value': 30
        },
        {
          'character_id': 'char_2',
          'attribute_id': 'a2',
          'operation': 'delta',
          'value': -5
        },
        {
          'character_name': '艾莉丝',
          'attribute_name': '潮感异常',
          'operation': 'set',
          'value': '波动'
        },
      ], diagnostics: diagnostics);

      expect(diagnostics, isEmpty);
      expect(changes, hasLength(3));
      expect(changes[0].operation, CustomStatusChangeOperation.set);
      expect(changes[0].value, 30);
      expect(changes[1].operation, CustomStatusChangeOperation.delta);
      expect(changes[2].characterName, '艾莉丝');
    });

    test('drops invalid items and records diagnostics', () {
      final diagnostics = <String>[];
      final changes = CustomStatusChange.parse([
        {
          'character_id': 'char_1',
          'attribute_id': 'a1',
          'operation': 'delta',
          'value': 'not-a-number'
        },
        {'character_id': 'char_1', 'operation': 'set', 'value': 3},
        'garbage',
      ], diagnostics: diagnostics);

      expect(changes, isEmpty);
      expect(diagnostics, contains('custom_status_changes:invalid'));
      expect(diagnostics, contains('custom_status_changes:item'));
    });

    test('defaults missing operation to set', () {
      final changes = CustomStatusChange.parse([
        {'character_id': 'char_1', 'attribute_id': 'a1', 'value': 42},
      ], diagnostics: <String>[]);

      expect(changes, hasLength(1));
      expect(changes.first.operation, CustomStatusChangeOperation.set);
    });
  });

  group('CustomStatusMerger.applyChanges (delta)', () {
    test('16 states with 1 change updates only that one', () {
      final baseline = _buildSixteenStates();
      final result = CustomStatusMerger.applyChanges(
        protagonistName: baseline.protagonistName,
        protagonistId: baseline.protagonistId,
        protagonistAttributes: baseline.protagonistAttributes,
        supportingCharacters: baseline.supportingCharacters,
        changes: const [
          CustomStatusChange(
            characterId: 'char_proto',
            attributeId: 'a1',
            operation: CustomStatusChangeOperation.delta,
            value: 3,
          ),
        ],
      );

      // 主角 a1 体力 50 -> 53
      expect(result.protagonistAttributes[0].currentValue, 53);
      expect(result.protagonistAttributes[0].value, '53/100');
      // 其余 15 项完全不变
      expect(result.protagonistAttributes[1].currentValue, 60);
      expect(result.protagonistAttributes[2].currentValue, 80);
      expect(result.protagonistAttributes[3].value, '未知');
      for (final sc in result.supportingCharacters) {
        expect(sc.customAttributes, hasLength(4));
      }
      expect(
          result.supportingCharacters[0].customAttributes[0].currentValue, 40);
      expect(result.supportingCharacters[0].customAttributes[2].value, '稳定');
      expect(
          result.supportingCharacters[1].customAttributes[1].currentValue, 30);
      expect(
          result.supportingCharacters[2].customAttributes[0].currentValue, 70);

      // 状态总数不能减少：4 + 4*3 = 16
      final total = result.protagonistAttributes.length +
          result.supportingCharacters
              .fold<int>(0, (sum, sc) => sum + sc.customAttributes.length);
      expect(total, 16);
      expect(result.diagnostics, isEmpty);
    });

    test('no changes leaves full state untouched', () {
      final baseline = _buildSixteenStates();
      final result = CustomStatusMerger.applyChanges(
        protagonistName: baseline.protagonistName,
        protagonistId: baseline.protagonistId,
        protagonistAttributes: baseline.protagonistAttributes,
        supportingCharacters: baseline.supportingCharacters,
        changes: const [],
      );

      expect(result.protagonistAttributes, baseline.protagonistAttributes);
      expect(result.supportingCharacters, baseline.supportingCharacters);
    });

    test('multi-character changes only touch actual targets', () {
      final baseline = _buildSixteenStates();
      final result = CustomStatusMerger.applyChanges(
        protagonistName: baseline.protagonistName,
        protagonistId: baseline.protagonistId,
        protagonistAttributes: baseline.protagonistAttributes,
        supportingCharacters: baseline.supportingCharacters,
        changes: const [
          CustomStatusChange(
            characterId: 'char_proto',
            attributeId: 'a2',
            operation: CustomStatusChangeOperation.delta,
            value: -10,
          ),
          CustomStatusChange(
            characterId: 'npc_1',
            attributeId: 'b1',
            operation: CustomStatusChangeOperation.set,
            value: 90,
          ),
          CustomStatusChange(
            characterId: 'npc_2',
            attributeId: 'c3',
            operation: CustomStatusChangeOperation.set,
            value: '敌对',
          ),
        ],
      );

      expect(result.protagonistAttributes[1].currentValue, 50); // 60 - 10
      expect(result.protagonistAttributes[0].currentValue, 50); // unchanged
      expect(
          result.supportingCharacters[0].customAttributes[0].currentValue, 90);
      expect(result.supportingCharacters[0].customAttributes[1].currentValue,
          55); // unchanged
      expect(result.supportingCharacters[1].customAttributes[2].value, '敌对');
      expect(result.supportingCharacters[1].customAttributes[1].currentValue,
          30); // unchanged
      expect(result.supportingCharacters[2].customAttributes[0].currentValue,
          70); // unchanged
    });

    test('numeric delta 50 + 3 = 53 and set 30 = 30', () {
      final proto = [_num('a1', '体力', 50, charName: '主角')];
      final delta = CustomStatusMerger.applyChanges(
        protagonistName: '主角',
        protagonistId: 'char_proto',
        protagonistAttributes: proto,
        supportingCharacters: const [],
        changes: const [
          CustomStatusChange(
              characterId: 'char_proto',
              attributeId: 'a1',
              operation: CustomStatusChangeOperation.delta,
              value: 3),
        ],
      );
      expect(delta.protagonistAttributes.first.currentValue, 53);
      expect(delta.protagonistAttributes.first.value, '53/100');

      final set = CustomStatusMerger.applyChanges(
        protagonistName: '主角',
        protagonistId: 'char_proto',
        protagonistAttributes: proto,
        supportingCharacters: const [],
        changes: const [
          CustomStatusChange(
              characterId: 'char_proto',
              attributeId: 'a1',
              operation: CustomStatusChangeOperation.set,
              value: 30),
        ],
      );
      expect(set.protagonistAttributes.first.currentValue, 30);
      expect(set.protagonistAttributes.first.value, '30/100');
    });

    test('text/stage set updates and same-value set is no-op', () {
      final proto = [_text('a4', '潮感异常', '稳定', charName: '主角')];
      final updated = CustomStatusMerger.applyChanges(
        protagonistName: '主角',
        protagonistId: 'char_proto',
        protagonistAttributes: proto,
        supportingCharacters: const [],
        changes: const [
          CustomStatusChange(
              characterId: 'char_proto',
              attributeId: 'a4',
              operation: CustomStatusChangeOperation.set,
              value: '波动'),
        ],
      );
      expect(updated.protagonistAttributes.first.value, '波动');

      final noOp = CustomStatusMerger.applyChanges(
        protagonistName: '主角',
        protagonistId: 'char_proto',
        protagonistAttributes: proto,
        supportingCharacters: const [],
        changes: const [
          CustomStatusChange(
              characterId: 'char_proto',
              attributeId: 'a4',
              operation: CustomStatusChangeOperation.set,
              value: '稳定'),
        ],
      );
      // 同值 set 不产生覆盖（措辞未变），对象引用不变
      expect(identical(noOp.protagonistAttributes.first, proto.first), isTrue);
    });

    test('unknown character_id/attribute_id ignored with diagnostic', () {
      final proto = [_num('a1', '体力', 50, charName: '主角')];
      final result = CustomStatusMerger.applyChanges(
        protagonistName: '主角',
        protagonistId: 'char_proto',
        protagonistAttributes: proto,
        supportingCharacters: const [],
        changes: const [
          CustomStatusChange(
              characterId: 'nope',
              attributeId: 'a1',
              operation: CustomStatusChangeOperation.delta,
              value: 5),
          CustomStatusChange(
              characterId: 'char_proto',
              attributeId: 'nope',
              operation: CustomStatusChangeOperation.set,
              value: 99),
        ],
      );

      expect(result.protagonistAttributes.first.currentValue, 50); // 未误更新
      expect(result.diagnostics, hasLength(2));
      expect(result.diagnostics.every((d) => d.startsWith('unknown:')), isTrue);
    });

    test('name fallback works when ids are absent', () {
      final proto = [_num('a1', '体力', 50, charName: '主角')];
      final result = CustomStatusMerger.applyChanges(
        protagonistName: '主角',
        protagonistId: 'char_proto',
        protagonistAttributes: proto,
        supportingCharacters: const [],
        changes: const [
          CustomStatusChange(
              characterName: '主角',
              attributeName: '体力',
              operation: CustomStatusChangeOperation.delta,
              value: 5),
        ],
      );
      expect(result.protagonistAttributes.first.currentValue, 55);
    });
  });

  group('CustomStatusMerger.applyLegacySnapshot', () {
    test('legacy custom_status still parses and applies', () {
      final snapshot = AdventureResponse.parseCustomStatus({'体力': 70});
      expect(snapshot, hasLength(1));

      final result = CustomStatusMerger.applyLegacySnapshot(
        protagonistName: '主角',
        protagonistAttributes: [_num('a1', '体力', 50, charName: '主角')],
        supportingCharacters: const [],
        snapshot: snapshot,
      );
      expect(result.protagonistAttributes.first.currentValue, 70);
      expect(result.protagonistAttributes.first.value, '70/100');
    });

    test('legacy 好感度 snapshot updates supporting affinity', () {
      final snapshot = AdventureResponse.parseCustomStatus({
        '艾莉丝': {'好感度': 88},
      });
      final result = CustomStatusMerger.applyLegacySnapshot(
        protagonistName: '主角',
        protagonistAttributes: const [],
        supportingCharacters: [
          _npc('npc_1', '艾莉丝', [
            _num('b2', '好感度', 55, charName: '艾莉丝'),
          ]),
        ],
        snapshot: snapshot,
      );
      expect(result.supportingCharacters.first.affinity, 88);
    });
  });

  group('AdventureResponse delta payload', () {
    test('recognizes custom_status_changes and separates it from custom_status',
        () {
      const content = '你走进大厅。\n---JSON---\n'
          '{"scene":"大厅","options":["走","停"],'
          '"custom_status_changes":[{"character_id":"c","attribute_id":"a","operation":"set","value":30}],'
          '"custom_status":[{"name":"体力","value":"99/100"}]}';
      final parsed = AdventureResponse.tryParseSplit(content);
      expect(parsed, isNotNull);
      expect(parsed!.customStatusChanges, hasLength(1));
      expect(parsed.customStatusChanges.first.attributeId, 'a');
      expect(parsed.customStatus, hasLength(1));
    });

    test('pure JSON with custom_status_changes is payload-only, no leak', () {
      const pure = '{"scene":"森林","options":["走","停"],'
          '"custom_status_changes":[{"character_id":"c","attribute_id":"a","operation":"delta","value":3}]}';
      final parsed = AdventureResponse.parse(pure);
      expect(parsed.kind, AdventureResponseKind.payloadOnly);
      expect(parsed.narrative, isEmpty);
      expect(AdventureResponse.streamingDisplayText(pure), isEmpty);
    });

    test('narrative + separator + delta payload does not leak into body', () {
      const raw = '你推开木门，屋内一片漆黑。\n---JSON---\n'
          '{"scene":"屋","options":["点灯","退回"],'
          '"custom_status_changes":[{"character_id":"c","attribute_id":"a","operation":"set","value":"稳定"}]}';
      final parsed = AdventureResponse.parse(raw);
      expect(parsed.kind, AdventureResponseKind.narrativeWithPayload);
      expect(parsed.narrative.join(), '你推开木门，屋内一片漆黑。');
      expect(parsed.narrative.join(), isNot(contains('custom_status_changes')));

      final canonical = AdventureResponse.canonicalize(raw);
      expect(canonical, contains('你推开木门'));
      expect(canonical, contains('custom_status_changes'));
    });

    test('inline delta JSON is stripped from narrative', () {
      const raw = '你走进大厅。 {"scene":"大厅","options":["走","停"],'
          '"custom_status_changes":[{"character_id":"c","attribute_id":"a","operation":"set","value":30}]}';
      final parsed = AdventureResponse.parse(raw);
      expect(parsed.kind, AdventureResponseKind.narrativeWithPayload);
      expect(parsed.narrative.join(), '你走进大厅。');
      expect(parsed.narrative.join(), isNot(contains('"')));
    });

    test('damaged delta JSON never leaks to narrative', () {
      const damaged = '你走进大厅。\n---JSON---\n'
          '{"scene":"大厅","custom_status_changes":[{"character_id":"c","attribute_id":"a"';
      // 正文 + 损坏 JSON：正文保留，损坏片段被剥离，绝不泄漏到正文。
      expect(AdventureResponse.canonicalize(damaged), '你走进大厅。');
      expect(AdventureResponse.canonicalize(damaged),
          isNot(contains('custom_status_changes')));

      const pureDamaged =
          '{"scene":"大厅","custom_status_changes":[{"character_id":"c"';
      final pureParsed = AdventureResponse.parse(pureDamaged);
      expect(pureParsed.kind, AdventureResponseKind.malformedStructured);
      expect(AdventureResponse.canonicalize(pureDamaged), isEmpty);
    });
  });

  group('displayValue', () {
    test('numeric state shows cur/max, text state shows text (not 0)', () {
      expect(_num('a', '好感度', 53).displayValue, '53/100');
      expect(_text('b', '潮感异常', '稳定').displayValue, '稳定');
      expect(_text('c', '父亲失踪线索', '已确认第五环关联').displayValue, '已确认第五环关联');
    });
  });

  group('ChatEngine delta priority (no double settlement)', () {
    test('prefers custom_status_changes over legacy custom_status', () async {
      final protagonist = _num('a1', '好感度', 50, charName: '主角');
      AdventureConfig? captured;
      var config = AdventureConfig(
        name: '主角',
        customAttributes: [protagonist],
        selectedCharacters: [
          AdventureSelectedCharacter(
            id: 'sel1',
            characterId: 'char_proto',
            characterName: '主角',
            isProtagonist: true,
          ),
        ],
      );
      final messages = <Message>[];
      final llm = _FixedLlmService(
        '你走进幽暗森林，四周雾气弥漫，脚下枯枝断裂，远处微光闪烁，'
        '你握紧剑柄，缓缓靠近，心跳逐渐加速，决心一探究竟，脚步沉稳而坚定，警惕地观察四周动静。\n'
        '---JSON---\n'
        '{"scene":"幽暗森林","options":["前进","后退","观察"],'
        '"custom_status_changes":[{"character_id":"char_proto","attribute_id":"a1","operation":"delta","value":5}],'
        '"custom_status":[{"name":"好感度","value":"99/100","currentValue":99,"maxValue":100,"characterName":"主角"}]}',
      );
      final host = _configHost(
        config: config,
        llm: llm,
        messages: messages,
        onConfigUpdate: (c) {
          captured = c;
          config = c;
        },
      );
      final engine = ChatEngine(
        host: host,
        notifyParent: () {},
        adventureRepo: _NoopAdventureRepository(),
      );
      addTearDown(engine.dispose);

      await engine.sendMessage('进入森林');

      expect(captured, isNotNull);
      // Delta 优先：50 + 5 = 55，而不是 legacy 快照的 99。
      expect(captured!.customAttributes.first.currentValue, 55);
    });
  });
}

class _FixedLlmService extends LLMService {
  final String content;
  _FixedLlmService(this.content)
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
    onChunk(content);
    onDone();
    return LLMStreamResult(
      content: content,
      finishReason: LLMFinishReason.stop,
      responseCompleted: true,
    );
  }
}

ChatEngineHost _configHost({
  required AdventureConfig config,
  required LLMService llm,
  required List<Message> messages,
  required void Function(AdventureConfig) onConfigUpdate,
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
    getAdventureConfig: () => config,
    getWorldEntries: () => const [],
    getBrightness: () => Brightness.light,
    getGameTopic: () => '测试',
    getGameDifficulty: () => '普通',
    getCompletionParams: () =>
        const CompletionParams(enableThinking: false, maxTokens: 2048),
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
    getDialogueLevel: () => DialogueLevel.l0,
    setAdventureConfig: onConfigUpdate,
  );
}

/// 最小 adventure repository 桩：ChatEngine 构造需要该依赖。
class _NoopAdventureRepository implements IAdventureRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
