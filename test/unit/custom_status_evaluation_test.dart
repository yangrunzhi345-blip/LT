import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/engines/chat_engine.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/models/custom_attribute_item.dart';
import 'package:lt_dialogue/models/custom_status_change.dart';
import 'package:lt_dialogue/models/custom_status_evaluation.dart';
import 'package:lt_dialogue/models/dialogue_level.dart';
import 'package:lt_dialogue/models/game_state.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/models/scene_dialogue.dart';
import 'package:lt_dialogue/models/scene_dialogue_effects.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository.dart';
import '../support/chat_engine_host_fixture.dart';

const _narrative = '你推开藤蔓走进幽暗森林，雾气在脚下翻涌，枯枝断裂的脆响在林间回荡，'
    '远处微光忽明忽暗，你握紧剑柄，一步步踏进湿冷的阴影深处，心跳与虫鸣交织成网。';

const _options = '["推开藤蔓继续深入","沿着溪流折返","蹲下检查地上的脚印"]';

Map<String, Object?> _eval(
  String attributeId, {
  required bool changed,
  String? operation,
  Object? value,
  String reason = '本轮没有相关事件',
}) =>
    {
      'character_id': 'char_proto',
      'attribute_id': attributeId,
      'changed': changed,
      if (operation != null) 'operation': operation,
      if (value != null) 'value': value,
      'reason': reason,
    };

/// 主响应：携带评估协议；[changeOverrides] 会作为 legacy 协议同时出现。
String _payload(
  List<Map<String, Object?>> evaluations, {
  String? legacyChanges,
}) {
  final buffer = StringBuffer()
    ..write('$_narrative\n---JSON---\n')
    ..write('{"scene":"幽暗森林","options":$_options,')
    ..write('"custom_status_evaluations":${jsonEncode(evaluations)}');
  if (legacyChanges != null) {
    buffer.write(',"custom_status_changes":$legacyChanges');
  }
  buffer.write('}');
  return buffer.toString();
}

String _legacyOnlyPayload() => '$_narrative\n---JSON---\n'
    '{"scene":"幽暗森林","options":$_options,'
    '"custom_status_changes":[{"character_id":"char_proto","attribute_id":"a1",'
    '"operation":"delta","value":5}]}';

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

class _Harness {
  _Harness(String mainContent) : llm = _FixedLlmService(mainContent) {
    config = AdventureConfig(
      name: '主角',
      customAttributes: const [
        CustomAttributeItem(
          id: 'a1',
          name: '体力',
          value: '50/100',
          currentValue: 50,
          maxValue: 100,
          characterName: '主角',
        ),
        CustomAttributeItem(
          id: 'a2',
          name: '精神压力',
          value: '稳定',
          characterName: '主角',
        ),
      ],
      selectedCharacters: [
        AdventureSelectedCharacter(
          id: 'sel1',
          characterId: 'char_proto',
          characterName: '主角',
          isProtagonist: true,
        ),
      ],
    );
  }

  final _FixedLlmService llm;
  final List<Message> messages = <Message>[];
  GameState gameState = GameState();
  late AdventureConfig config;
  int configUpdates = 0;
  List<String> statusDiagnostics = const [];

  ChatEngine build() {
    final host = ChatDependencies(
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
      setAdventureConfig: (value) {
        configUpdates++;
        config = value;
      },
      onSceneDialogueCommitResult: (result) {
        statusDiagnostics = result.statusDiagnostics;
      },
    );
    return ChatEngine(
      host: host,
      notifyParent: () {},
      adventureRepo: _NoopAdventureRepository(),
    );
  }

  int get trackedValue => config.customAttributes.first.currentValue ?? -1;
  String get trackedText => config.customAttributes[1].value;
}

/// 最小 adventure repository 桩：ChatEngine 构造需要该依赖。
class _NoopAdventureRepository implements IAdventureRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('CustomStatusEvaluation.parse', () {
    test('accepts bool / string / numeric changed flags', () {
      final diagnostics = <String>[];
      final parsed = CustomStatusEvaluation.parse([
        {
          'attribute_id': 'a1',
          'changed': true,
          'operation': 'delta',
          'value': 5
        },
        {
          'attribute_id': 'a2',
          'changed': 'true',
          'operation': 'set',
          'value': '紧绷',
        },
        {
          'attribute_id': 'a3',
          'changed': 1,
          'operation': 'delta',
          'value': '3'
        },
        {'attribute_id': 'a4', 'changed': false},
        {'attribute_id': 'a5', 'changed': '无变化'},
      ], diagnostics: diagnostics);

      expect(diagnostics, isEmpty);
      expect(parsed.map((e) => e.changed).toList(),
          [true, true, true, false, false]);
      expect(parsed.first.operation, CustomStatusChangeOperation.delta);
      expect(parsed[2].toChange().value, '3');
    });

    test('infers changed=true when only operation/value are present', () {
      final diagnostics = <String>[];
      final parsed = CustomStatusEvaluation.parse([
        {'attribute_id': 'a1', 'operation': 'delta', 'value': 5},
      ], diagnostics: diagnostics);

      expect(diagnostics, isEmpty);
      expect(parsed.single.changed, isTrue);
    });

    test('records a diagnostic when changed cannot be understood', () {
      final diagnostics = <String>[];
      final parsed = CustomStatusEvaluation.parse([
        {'attribute_id': 'a1', 'changed': 'maybe'},
      ], diagnostics: diagnostics);

      expect(parsed, isEmpty);
      expect(diagnostics, contains('invalid_evaluation:a1'));
    });

    test('records a diagnostic when changed=true has no attribute reference',
        () {
      final diagnostics = <String>[];
      final parsed = CustomStatusEvaluation.parse([
        {'character_id': 'char_proto', 'changed': true, 'value': 5},
      ], diagnostics: diagnostics);

      expect(parsed, isEmpty);
      expect(diagnostics, contains('invalid_evaluation:char_proto'));
    });

    test('records invalid_operation / invalid_delta_value / invalid_value', () {
      final diagnostics = <String>[];
      final parsed = CustomStatusEvaluation.parse([
        {
          'attribute_id': 'a1',
          'changed': true,
          'operation': 'boost',
          'value': 5
        },
        {
          'attribute_id': 'stress',
          'changed': true,
          'operation': 'delta',
          'value': 'heavy',
        },
        {'attribute_id': 'a2', 'changed': true, 'operation': 'set'},
      ], diagnostics: diagnostics);

      expect(parsed, isEmpty);
      expect(diagnostics, contains('invalid_operation:a1'));
      expect(diagnostics, contains('invalid_delta_value:stress'));
      expect(diagnostics, contains('invalid_value:a2'));
    });

    test('caps the list and reports the overflow', () {
      final diagnostics = <String>[];
      final raw = [
        for (var i = 0;
            i < CustomStatusEvaluation.maximumEvaluationsPerTurn + 5;
            i++)
          {'attribute_id': 'a$i', 'changed': false},
      ];
      final parsed =
          CustomStatusEvaluation.parse(raw, diagnostics: diagnostics);

      expect(
          parsed, hasLength(CustomStatusEvaluation.maximumEvaluationsPerTurn));
      expect(diagnostics, contains('custom_status_evaluations:limit'));
    });

    test('non-list payload is rejected instead of silently ignored', () {
      final diagnostics = <String>[];
      expect(CustomStatusEvaluation.parse('nope', diagnostics: diagnostics),
          isEmpty);
      expect(diagnostics, contains('custom_status_evaluations:type'));
    });

    test('null payload means the protocol is absent, not empty', () {
      final diagnostics = <String>[];
      expect(CustomStatusEvaluation.parse(null, diagnostics: diagnostics),
          isEmpty);
      expect(diagnostics, isEmpty);
    });
  });

  group('自定义状态评估协议端到端', () {
    test('1. changed=true 必须落为状态变化', () async {
      final harness = _Harness(_payload([
        _eval('a1',
            changed: true, operation: 'delta', value: 5, reason: '本轮发生积极互动'),
        _eval('a2', changed: false),
      ]));
      final engine = harness.build();
      addTearDown(engine.dispose);

      await engine.sendMessage('进入森林');

      expect(harness.trackedValue, 55); // 50 + delta 5
      expect(harness.configUpdates, 1);
      expect(harness.statusDiagnostics, isEmpty);
    });

    test('2. changed=false 不修改状态，也不写盘', () async {
      final harness = _Harness(_payload([
        _eval('a1', changed: false),
        _eval('a2', changed: false),
      ]));
      final engine = harness.build();
      addTearDown(engine.dispose);

      await engine.sendMessage('进入森林');

      expect(harness.trackedValue, 50);
      expect(harness.trackedText, '稳定');
      expect(harness.configUpdates, 0);
    });

    test('3. 非法 attribute 记入 statusDiagnostics 且不误改其他状态', () async {
      final harness = _Harness(_payload([
        _eval('不存在', changed: true, operation: 'delta', value: 5),
        _eval('a1', changed: false),
        _eval('a2', changed: false),
      ]));
      final engine = harness.build();
      addTearDown(engine.dispose);

      await engine.sendMessage('进入森林');

      expect(harness.statusDiagnostics, contains('unknown_attribute:不存在'));
      expect(harness.trackedValue, 50);
    });

    test('3b. delta 作用于非数值状态时记录 invalid_delta_value', () async {
      final harness = _Harness(_payload([
        _eval('a2', changed: true, operation: 'delta', value: 5),
        _eval('a1', changed: false),
      ]));
      final engine = harness.build();
      addTearDown(engine.dispose);

      await engine.sendMessage('进入森林');

      expect(harness.statusDiagnostics, contains('invalid_delta_value:a2'));
      expect(harness.trackedText, '稳定');
    });

    test('4. 同一目标被评估与旧协议同时提交时只结算一次', () async {
      final harness = _Harness(
        _payload([
          _eval('a1', changed: true, operation: 'delta', value: 5),
          _eval('a2', changed: false),
        ],
            legacyChanges: '[{"character_id":"char_proto","attribute_id":"a1",'
                '"operation":"delta","value":5}]'),
      );
      final engine = harness.build();
      addTearDown(engine.dispose);

      await engine.sendMessage('进入森林');

      expect(harness.trackedValue, 55); // 不是 60
      expect(harness.configUpdates, 1);
    });

    test('5. 遗漏追踪状态时记录 unevaluated_attribute', () async {
      final harness = _Harness(_payload([
        _eval('a1', changed: true, operation: 'delta', value: 5),
      ]));
      final engine = harness.build();
      addTearDown(engine.dispose);

      await engine.sendMessage('进入森林');

      expect(harness.statusDiagnostics, contains('unevaluated_attribute:a2'));
      expect(harness.trackedValue, 55);
    });

    test('6. 旧协议单独出现时不产生 unevaluated 诊断', () async {
      final harness = _Harness(_legacyOnlyPayload());
      final engine = harness.build();
      addTearDown(engine.dispose);

      await engine.sendMessage('进入森林');

      expect(harness.trackedValue, 55);
      expect(harness.statusDiagnostics, isEmpty);
    });

    test('7. 评估协议不会残留在持久化的消息 JSON 中', () async {
      final harness = _Harness(_payload([
        _eval('a1', changed: true, operation: 'delta', value: 5),
        _eval('a2', changed: false),
      ]));
      final engine = harness.build();
      addTearDown(engine.dispose);

      await engine.sendMessage('进入森林');

      final aiMessage = harness.messages.last;
      expect(aiMessage.isUser, isFalse);
      expect(aiMessage.content, isNot(contains('custom_status_evaluations')));
      expect(aiMessage.content, isNot(contains('custom_status_changes')));
      expect(aiMessage.content, contains('custom_status'));
    });
  });

  group('SceneDialogueCommitResult.statusDiagnostics', () {
    test('默认空列表，可携带诊断', () {
      final empty = SceneDialogueCommitResult(
        applied: true,
        gameState: GameState(),
        effects: const SceneDialogueEffects(),
      );
      expect(empty.statusDiagnostics, isEmpty);

      final withDiagnostics = SceneDialogueCommitResult(
        applied: true,
        gameState: GameState(),
        effects: const SceneDialogueEffects(),
        statusDiagnostics: const ['unknown_attribute:好感度'],
      );
      expect(withDiagnostics.statusDiagnostics, ['unknown_attribute:好感度']);
    });
  });
}
