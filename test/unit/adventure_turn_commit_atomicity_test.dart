import 'dart:async';
import 'dart:io' show HandshakeException;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/engines/chat_engine.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/models/custom_attribute_item.dart';
import 'package:lt_dialogue/models/dialogue_level.dart';
import 'package:lt_dialogue/models/game_state.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository.dart';
import '../support/chat_engine_host_fixture.dart';

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
  final List<CompletionParams> receivedParams = [];
  int repairCalls = 0;

  /// 在修复请求真正发出时回调，用于模拟“修复期间被取消”。
  void Function()? onRepairCall;

  /// 主请求失败（无有效正文）场景。
  Object? mainError;
  Future<LLMStreamResult> Function(
      void Function(String), void Function(String)?)? mainResponse;

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
    receivedParams.add(params);
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
    final response = mainResponse;
    if (response != null) return response(onChunk, onReasoningChunk);
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

  ChatEngine build(
      {DialogueLevel level = DialogueLevel.l0,
      bool thinking = false,
      int? adventureId,
      IAdventureRepository? repository}) {
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
          CompletionParams(enableThinking: thinking, maxTokens: 4096),
      getCurrentAdventureId: () => adventureId,
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
      getDialogueLevel: () => level,
      setAdventureConfig: (value) {
        configUpdates++;
        config = value;
      },
    );
    return ChatEngine(
      host: host,
      notifyParent: () {},
      adventureRepo: repository ?? _NoopAdventureRepository(),
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

class _FailingPreparationRepository extends _NoopAdventureRepository {
  @override
  Future<RuntimeHead> getRuntimeHead(int adventureId, int branchId) async =>
      throw StateError('runtime read failed');
}

void main() {
  group('Adventure 回合原子提交与 option repair 降级', () {
    test('should classify an internal processing error separately from network',
        () async {
      final harness = _TurnHarness(_mainPayload(withOptions: true));
      harness.llm.mainError = StateError('consumer processing failed');
      final engine = harness.build();
      addTearDown(engine.dispose);

      await engine.sendMessage('进入森林');

      expect(engine.lastErrorType, 'internal');
      expect(engine.sceneDialoguePhase, SceneDialoguePhase.failed);
      expect(engine.status, ChatStatus.idle);
      expect(harness.messages.where((m) => m.isUser), hasLength(1));
      expect(harness.messages.where((m) => !m.isUser && !m.isError), isEmpty);
      expect(harness.configUpdates, 0);
      expect(harness.gameState.gold, 0);
    });

    test('L5 stage reserves shared output budget for reasoning and prose',
        () async {
      final harness = _TurnHarness(_mainPayload(withOptions: true));
      harness.llm.mainError = StateError('stop after observing request');
      final engine = harness.build(level: DialogueLevel.l5, thinking: true);
      addTearDown(engine.dispose);
      await engine.sendMessage('进入森林');
      expect(harness.llm.receivedParams.single.enableThinking, isTrue);
      expect(harness.llm.receivedParams.single.maxTokens, 5712 + 8192);
    });

    test('stop with reasoning but empty narrative cannot start another stage',
        () async {
      final harness = _TurnHarness(_mainPayload(withOptions: true));
      harness.llm.mainResponse = (onChunk, onReasoning) async {
        onReasoning?.call('analysis');
        return const LLMStreamResult(
            content: '',
            reasoningContent: 'analysis',
            finishReason: LLMFinishReason.stop,
            responseCompleted: true);
      };
      final engine = harness.build(level: DialogueLevel.l5);
      addTearDown(engine.dispose);
      await engine.sendMessage('进入森林');
      expect(harness.llm.mainCalls, 1);
      expect(engine.lastErrorType, 'generation');
      expect(harness.messages.where((m) => !m.isUser && !m.isError), isEmpty);
      expect(harness.configUpdates, 0);
      expect(engine.status, ChatStatus.idle);
    });

    for (final finish in [
      LLMFinishReason.unknown,
      LLMFinishReason.interrupted
    ]) {
      test('incomplete 500-character narrative with $finish never commits',
          () async {
        final harness = _TurnHarness(_mainPayload(withOptions: true));
        harness.llm.mainResponse = (onChunk, onReasoning) async {
          final draft = '林' * 500;
          onChunk(draft);
          return LLMStreamResult(
              content: draft, finishReason: finish, responseCompleted: false);
        };
        final engine = harness.build();
        addTearDown(engine.dispose);
        await engine.sendMessage('进入森林');
        expect(engine.lastErrorType, 'generation');
        expect(engine.status, ChatStatus.idle);
        expect(harness.messages.where((m) => !m.isUser && !m.isError), isEmpty);
        expect(harness.configUpdates, 0);
        expect(harness.llm.mainCalls, 1);
      });
    }

    test(
        'rapid double dispatch starts one logical turn with one request identity',
        () async {
      final harness = _TurnHarness(_mainPayload(withOptions: true));
      final started = Completer<void>();
      final release = Completer<void>();
      harness.llm.mainResponse = (onChunk, onReasoning) async {
        started.complete();
        await release.future;
        onChunk(harness.llm.mainContent);
        return LLMStreamResult(
            content: harness.llm.mainContent,
            finishReason: LLMFinishReason.stop,
            responseCompleted: true);
      };
      final engine = harness.build();
      addTearDown(engine.dispose);
      final first = engine.sendMessage('进入森林');
      await started.future;
      await engine.sendMessage('进入森林');
      expect(harness.llm.mainCalls, 1);
      expect(harness.messages.where((m) => m.isUser), hasLength(1));
      release.complete();
      await first;
      expect(
          harness.messages.where((m) => !m.isUser && !m.isError), hasLength(1));
      expect(engine.status, ChatStatus.idle);
    });

    for (final switchModel in [false, true]) {
      test(
          'retry ${switchModel ? "with another model" : "same model"} reuses the failed user bubble',
          () async {
        final harness = _TurnHarness(_mainPayload(withOptions: true));
        harness.messages
            .add(Message(id: 'old-a', isUser: false, content: '旅店内序章'));
        harness.llm.mainError = StateError('processing failed');
        final engine = harness.build();
        addTearDown(engine.dispose);
        await engine.sendMessage('进入森林');
        final userId = harness.messages.singleWhere((m) => m.isUser).id;
        harness.llm.mainError = null;
        await engine.retryLast(
            overrideModel: switchModel ? 'another-model' : null);
        expect(harness.llm.mainCalls, 2);
        expect(harness.messages.where((m) => m.isUser), hasLength(1));
        expect(harness.messages.singleWhere((m) => m.isUser).id, userId);
        expect(harness.messages.where((m) => m.isError), isEmpty);
        expect(harness.messages.where((m) => !m.isUser), hasLength(2));
        expect(engine.status, ChatStatus.idle);
      });
    }

    test('preparation failure converges status and exposes internal failure',
        () async {
      final harness = _TurnHarness(_mainPayload(withOptions: true));
      final engine = harness.build(
          adventureId: 7, repository: _FailingPreparationRepository());
      addTearDown(engine.dispose);
      await engine.sendMessage('进入森林');
      expect(engine.status, ChatStatus.idle);
      expect(engine.lastErrorType, 'internal');
      expect(harness.llm.mainCalls, 0);
      expect(harness.configUpdates, 0);
    });

    for (final partial in [false, true]) {
      test(
          'stage 2 ${partial ? "partial content" : "reasoning"} failure preserves completed prefix only',
          () async {
        final harness = _TurnHarness(_mainPayload(withOptions: true));
        final prefix = '林间风声回荡' * 550;
        harness.llm.mainResponse = (onChunk, onReasoning) async {
          if (harness.llm.mainCalls == 1) {
            onChunk(prefix);
            return LLMStreamResult(
                content: prefix,
                finishReason: LLMFinishReason.stop,
                responseCompleted: true);
          }
          onReasoning?.call('stage two analysis');
          if (partial) onChunk('未完成的下一幕');
          throw const HandshakeException('stream reset');
        };
        final engine = harness.build(level: DialogueLevel.l5);
        addTearDown(engine.dispose);
        await engine.sendMessage('进入森林');
        expect(harness.llm.mainCalls, 2);
        expect(engine.status, ChatStatus.idle);
        expect(engine.pendingAssistantContent, prefix);
        expect(engine.hasPendingAssistant, isTrue);
        expect(harness.messages.where((m) => m.isUser), hasLength(1));
        expect(harness.messages.where((m) => !m.isUser && !m.isError), isEmpty);
        expect(harness.configUpdates, 0);
        expect(harness.gameState.gold, 0);
      });
    }

    test('1. 主正文成功且 options 完整 — 不调用 repair，状态提交一次', () async {
      final harness = _TurnHarness(_mainPayload(withOptions: true));
      final engine = harness.build();
      addTearDown(engine.dispose);

      await engine.sendMessage('进入森林');

      expect(harness.llm.repairCalls, 0);
      expect(harness.configUpdates, 0);
      expect(harness.trackedValue, 50);
      expect(harness.messages.last.content, contains('55/100'));
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
      expect(harness.configUpdates, 0);
      expect(harness.trackedValue, 50);
      expect(harness.messages.last.content, contains('55/100'));
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
      expect(harness.configUpdates, 0);
      expect(harness.trackedValue, 50);
      expect(harness.messages.last.content, contains('55/100'));
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

      expect(harness.configUpdates, 0);
      expect(harness.trackedValue, 50);
      expect(harness.messages.last.content, contains('57/100'));
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
      expect(harness.messages.last.isError, isTrue);
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
      expect(harness.configUpdates, 0);
      expect(harness.trackedValue, 50);
      expect(harness.messages.last.content, contains('55/100'));
    });

    test('8. 连续两轮 — 不重复应用上一轮 delta', () async {
      final harness = _TurnHarness(_mainPayload(withOptions: true));
      final engine = harness.build();
      addTearDown(engine.dispose);

      await engine.sendMessage('进入森林');
      expect(harness.configUpdates, 0);
      expect(harness.trackedValue, 50);
      expect(harness.messages.last.content, contains('55/100'));

      // 第二轮：正文完整但没有任何状态变化。
      harness.llm.mainContent = '$_narrative\n---JSON---\n'
          '{"scene":"幽暗森林","gold":0,'
          '"options":["推开藤蔓继续深入","沿着溪流折返","蹲下检查地上的脚印"]}';
      await engine.sendMessage('继续深入');

      expect(harness.configUpdates, 0, reason: '剧情不得写回 Frozen Baseline');
      expect(harness.trackedValue, 50, reason: 'Frozen Baseline 必须保持初始值');
      expect(harness.hasErrorCard, isFalse);
      expect(harness.llm.repairCalls, 0);
    });
  });
}
