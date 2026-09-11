import 'dart:io' show HandshakeException;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/engines/chat_engine.dart';
import 'package:lt_dialogue/managers/chat_dependencies.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/models/custom_attribute_item.dart';
import 'package:lt_dialogue/models/dialogue_level.dart';
import 'package:lt_dialogue/models/game_state.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository.dart';

const _narrative = '你推开藤蔓走进幽暗森林，雾气在脚下翻涌，枯枝断裂的脆响在林间回荡，'
    '远处微光忽明忽暗，你握紧剑柄，一步步踏进湿冷的阴影深处，心跳与虫鸣交织成网。';

/// 主响应：options 完整。
String _mainPayload({required bool withOptions, int delta = 5, int gold = 0}) =>
    '$_narrative\n---JSON---\n'
    '{"scene":"幽暗森林","gold":$gold,'
    '"options":${withOptions ? '["推开藤蔓继续深入","沿着溪流折返","蹲下检查地上的脚印"]' : '[]'},'
    '"custom_status_changes":[{"character_id":"char_proto","attribute_id":"a1",'
    '"operation":"delta","value":$delta}]}';

const _repairedOptions = '{"options":["举火把照向潮湿的洞壁","低声呼唤同伴的名字确认方位",'
    '"贴着岩壁慢慢向后退去"]}';

const _repairedOptionsWithSettlement = '{"options":["举火把照向潮湿的洞壁",'
    '"低声呼唤同伴的名字确认方位","贴着岩壁慢慢向后退去"],'
    '"custom_status_changes":[{"character_id":"char_proto","attribute_id":"a1",'
    '"operation":"delta","value":1000}]}';

/// 按 system 提示词区分主请求与选项修复请求。
class _TurnLlmService extends LLMService {
  _TurnLlmService(this.mainContent, {this.repairContent, this.repairError})
      : super(const LLMConfig(
          provider: LLMProvider.deepseek,
          apiKey: 'test-key',
          baseUrl: 'https://example.invalid',
          model: 'deepseek-flash',
        ));

  String mainContent;
  final String? repairContent;
  final Object? repairError;

  int mainCalls = 0;
  int repairCalls = 0;

  /// 在修复请求真正发出时回调，用于模拟“修复期间被取消”。
  void Function()? onRepairCall;

  /// 主请求失败（无有效正文）场景。
  Object? mainError;

  static bool _isRepair(List<Map<String, String>> messages) =>
      messages.any((message) => (message['content'] ?? '').contains('行动选项修复器'));

  @override
  Future<LLMStreamResult> sendMessageStreamDetailed(
    List<Map<String, String>> messages,
    void Function(String chunk) onChunk,
    void Function() onDone, {
    void Function(String reasoningChunk)? onReasoningChunk,
    CompletionParams params = const CompletionParams(),
    GenerationTaskHandle? taskHandle,
  }) async {
    if (_isRepair(messages)) {
      repairCalls++;
      onRepairCall?.call();
      final error = repairError;
      if (error != null) throw error;
      final content = repairContent;
      if (content == null) throw StateError('no repair response configured');
      onChunk(content);
      onDone();
      return LLMStreamResult(
        content: content,
        finishReason: LLMFinishReason.stop,
        responseCompleted: true,
      );
    }
    mainCalls++;
    final error = mainError;
    if (error != null) throw error;
    onChunk(mainContent);
    onDone();
    return LLMStreamResult(
      content: mainContent,
      finishReason: LLMFinishReason.stop,
      responseCompleted: true,
    );
  }
}

class _TurnHarness {
  _TurnHarness(String mainContent, {String? repairContent, Object? repairError})
      : llm = _TurnLlmService(mainContent,
            repairContent: repairContent, repairError: repairError) {
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

  final _TurnLlmService llm;
  final List<Message> messages = <Message>[];
  GameState gameState = GameState();
  late AdventureConfig config;
  int configUpdates = 0;

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
    );
    return ChatEngine(
      host: host,
      notifyParent: () {},
      adventureRepo: _NoopAdventureRepository(),
    );
  }

  int get trackedValue => config.customAttributes.first.currentValue ?? -1;

  bool get hasErrorCard => messages.any((message) => message.isError);
}

/// 最小 adventure repository 桩：ChatEngine 构造需要该依赖。
class _NoopAdventureRepository implements IAdventureRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('Adventure 回合原子提交与 option repair 降级', () {
    test('1. 主正文成功且 options 完整 — 不调用 repair，状态提交一次', () async {
      final harness = _TurnHarness(_mainPayload(withOptions: true));
      final engine = harness.build();
      addTearDown(engine.dispose);

      await engine.sendMessage('进入森林');

      expect(harness.llm.repairCalls, 0);
      expect(harness.configUpdates, 1);
      expect(harness.trackedValue, 55); // 50 + delta 5
      expect(harness.hasErrorCard, isFalse);
      expect(harness.messages.last.isUser, isFalse);
      expect(harness.messages.last.content, contains('幽暗森林'));
    });

    test('2. options 缺失且 repair 成功 — 使用 repair options，状态只提交一次', () async {
      final harness = _TurnHarness(_mainPayload(withOptions: false),
          repairContent: _repairedOptions);
      final engine = harness.build();
      addTearDown(engine.dispose);

      await engine.sendMessage('进入森林');

      expect(harness.llm.repairCalls, 1);
      expect(engine.parsedOptions, hasLength(3));
      expect(engine.parsedOptions.first, contains('举火把'));
      expect(harness.configUpdates, 1);
      expect(harness.trackedValue, 55);
      expect(harness.hasErrorCard, isFalse);
    });

    test('3. options 缺失且 repair 抛 HandshakeException — 降级而非整轮失败', () async {
      final harness = _TurnHarness(
        _mainPayload(withOptions: false),
        repairError:
            const HandshakeException('Connection terminated during handshake'),
      );
      final engine = harness.build();
      addTearDown(engine.dispose);

      await engine.sendMessage('进入森林');

      expect(harness.llm.repairCalls, 1);
      // 正文保留，没有整轮网络错误卡。
      expect(harness.hasErrorCard, isFalse);
      expect(engine.lastErrorType, isNull);
      expect(harness.messages.last.isUser, isFalse);
      expect(harness.messages.last.content, contains('幽暗森林'));
      // 至少 3 个可点击选项（此处来自场景兜底）。
      expect(engine.parsedOptions.length, greaterThanOrEqualTo(3));
      expect(engine.parsedOptions.first, contains('继续探索'));
      // 回合正常结束，而不是停在错误态。
      expect(engine.status, ChatStatus.idle);
      // 主响应状态仍然正常提交一次。
      expect(harness.configUpdates, 1);
      expect(harness.trackedValue, 55);
    });

    test('4. repair 失败前已有 custom_status_changes — 状态不丢失、不重复', () async {
      final harness = _TurnHarness(
        _mainPayload(withOptions: false, delta: 7),
        repairError:
            const HandshakeException('Connection terminated during handshake'),
      );
      final engine = harness.build();
      addTearDown(engine.dispose);

      await engine.sendMessage('进入森林');

      expect(harness.configUpdates, 1);
      expect(harness.trackedValue, 57); // 50 + delta 7，只结算一次
      expect(harness.llm.repairCalls, 1);
    });

    test('5. repair 期间请求被取消 — 状态、GameState 均不提交', () async {
      final harness = _TurnHarness(_mainPayload(withOptions: false, gold: 80),
          repairContent: _repairedOptions);
      final engine = harness.build();
      addTearDown(engine.dispose);
      harness.llm.onRepairCall = engine.cancelStreaming;

      await engine.sendMessage('进入森林');

      expect(harness.configUpdates, 0);
      expect(harness.trackedValue, 50);
      expect(harness.gameState.gold, 0, reason: 'GameState 不得落地');
      expect(harness.messages.where((m) => !m.isUser), isEmpty);
      expect(harness.hasErrorCard, isFalse);
    });

    test('6. 主请求本身 HandshakeException 且无有效正文 — 仍显示网络错误', () async {
      final harness = _TurnHarness(_mainPayload(withOptions: true));
      harness.llm.mainError =
          const HandshakeException('Connection terminated during handshake');
      final engine = harness.build();
      addTearDown(engine.dispose);

      await engine.sendMessage('进入森林');

      expect(harness.hasErrorCard, isTrue);
      expect(harness.messages.last.content, contains('⚠️'));
      expect(engine.lastErrorType, ChatEngine.errorTypeNetwork);
      expect(harness.configUpdates, 0);
      expect(harness.trackedValue, 50);
    });

    test('7. repair 返回额外 custom_status_changes — 只接受 options，状态被忽略', () async {
      final harness = _TurnHarness(_mainPayload(withOptions: false),
          repairContent: _repairedOptionsWithSettlement);
      final engine = harness.build();
      addTearDown(engine.dispose);

      await engine.sendMessage('进入森林');

      expect(engine.parsedOptions, hasLength(3));
      expect(engine.parsedOptions.first, contains('举火把'));
      // 修复模型的 delta 1000 被忽略，主响应的 delta 5 仍然只结算一次。
      expect(harness.configUpdates, 1);
      expect(harness.trackedValue, 55);
    });

    test('8. 连续两轮 — 不重复应用上一轮 delta', () async {
      final harness = _TurnHarness(_mainPayload(withOptions: true));
      final engine = harness.build();
      addTearDown(engine.dispose);

      await engine.sendMessage('进入森林');
      expect(harness.configUpdates, 1);
      expect(harness.trackedValue, 55);

      // 第二轮：正文完整但没有任何状态变化。
      harness.llm.mainContent = '$_narrative\n---JSON---\n'
          '{"scene":"幽暗森林","gold":0,'
          '"options":["推开藤蔓继续深入","沿着溪流折返","蹲下检查地上的脚印"]}';
      await engine.sendMessage('继续深入');

      expect(harness.configUpdates, 1, reason: '第二轮没有 delta，不应再次提交');
      expect(harness.trackedValue, 55, reason: '上一轮 delta 不得重复结算');
      expect(harness.hasErrorCard, isFalse);
      expect(harness.llm.repairCalls, 0);
    });
  });
}
