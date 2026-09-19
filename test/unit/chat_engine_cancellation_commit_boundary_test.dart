import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/engines/chat_engine.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/models/dialogue_level.dart';
import 'package:lt_dialogue/models/game_state.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/models/scene_dialogue.dart';
import 'package:lt_dialogue/models/scene_dialogue_effects.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository.dart';
import '../support/chat_engine_host_fixture.dart';

/// R02-A — dialogue commit boundary.
///
/// The race this file pins: the DB commit is the one irreversible boundary of a
/// turn. A cancellation that lands before it must prevent the write; a
/// cancellation that lands after it must never delete the committed user/assistant
/// messages or restore the previous GameState. Every barrier here is a
/// [Completer] — no timers, no sleeps, no reliance on machine speed.

const _narrative = '你推开藤蔓走进幽暗森林，雾气在脚下翻涌，枯枝断裂的脆响在林间回荡，'
    '远处微光忽明忽暗，你握紧剑柄，一步步踏进湿冷的阴影深处。';

const _mainResponse = '$_narrative\n---JSON---\n'
    '{"scene":"幽暗森林","options":["推开藤蔓继续深入","沿着溪流折返","蹲下检查地上的脚印"]}';

const _committedScene = '余烬峡谷';

/// A controllable LLM service: the main narrative request can be held behind a
/// [gate] so a test can deterministically cancel while generation is in flight.
class _GatedLlmService extends LLMService {
  _GatedLlmService()
      : super(const LLMConfig(
          provider: LLMProvider.deepseek,
          apiKey: 'test-key',
          baseUrl: 'https://example.invalid',
          model: 'deepseek-flash',
        ));

  int mainCalls = 0;
  Completer<void>? started;
  Completer<void>? gate;
  String content = _mainResponse;

  @override
  Future<LLMStreamResult> sendMessageStreamDetailed(
    List<Map<String, String>> messages,
    void Function(String chunk) onChunk,
    void Function() onDone, {
    void Function(String reasoningChunk)? onReasoningChunk,
    CompletionParams params = const CompletionParams(),
    GenerationTaskHandle? taskHandle,
  }) async {
    mainCalls++;
    started?.complete();
    final barrier = gate;
    if (barrier != null) await barrier.future;
    onChunk(content);
    onDone();
    return LLMStreamResult(
      content: content,
      finishReason: LLMFinishReason.stop,
      responseCompleted: true,
    );
  }
}

/// Minimal [IAdventureRepository] whose commit can be blocked and completed on
/// demand, which is what makes the pre/post-commit races deterministic.
class _ControlledAdventureRepository implements IAdventureRepository {
  int commitCalls = 0;
  Completer<void>? commitStarted;
  Completer<SceneDialogueCommitResult>? commitGate;
  SceneDialogueCommit? lastCommit;

  @override
  Future<RuntimeHead> getRuntimeHead(int adventureId, int branchId) async =>
      const RuntimeHead(adventureId: 1, branchId: 0, revision: 0);

  @override
  Future<List<RuntimeEntityState>> getRuntimeEntities(
    int adventureId,
    int branchId, {
    int limit = 32,
  }) async =>
      const <RuntimeEntityState>[];

  @override
  Future<SceneDialogueCommitResult> commitSceneDialogueTurn(
      SceneDialogueCommit commit) async {
    commitCalls++;
    lastCommit = commit;
    commitStarted?.complete();
    final barrier = commitGate;
    if (barrier != null) return barrier.future;
    return SceneDialogueCommitResult(
      applied: true,
      gameState: commit.gameState.copyWith(
        currentScene: _committedScene,
        gold: 42,
      ),
      effects: const SceneDialogueEffects(),
      sceneState: commit.sceneState,
      statusDiagnostics: const <String>[],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Harness {
  _Harness() {
    host = ChatDependencies(
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
      getGameTopic: () => '测试',
      getGameDifficulty: () => '普通',
      getCompletionParams: () =>
          const CompletionParams(enableThinking: false, maxTokens: 2048),
      getCurrentAdventureId: () => 1,
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
      onSceneDialogueCommitResult: (result) => appliedResults.add(result),
    );
    engine = ChatEngine(
      host: host,
      notifyParent: () {},
      adventureRepo: repo,
    );
  }

  final _GatedLlmService llm = _GatedLlmService();
  final _ControlledAdventureRepository repo = _ControlledAdventureRepository();
  late final ChatDependencies host;
  late final ChatEngine engine;
  final List<Message> messages = <Message>[];
  final List<SceneDialogueCommitResult> appliedResults =
      <SceneDialogueCommitResult>[];
  GameState gameState = GameState();

  bool get hasErrorCard => messages.any((message) => message.isError);
  List<Message> get assistantMessages =>
      messages.where((message) => !message.isUser).toList();

  void dispose() => engine.dispose();
}

void main() {
  group('R02-A dialogue commit boundary', () {
    test('A1 cancel before the commit writes nothing and leaves no memory turn',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final llmStarted = Completer<void>();
      final llmGate = Completer<void>();
      h.llm.started = llmStarted;
      h.llm.gate = llmGate;

      final pending = h.engine.sendMessage('进入森林');
      await llmStarted.future;
      h.engine.cancelStreaming();
      llmGate.complete();
      await pending;

      expect(h.repo.commitCalls, 0, reason: 'cancelled before the boundary');
      expect(h.messages, isEmpty,
          reason: 'the user bubble must be rolled back');
      expect(h.engine.sceneDialoguePhase, SceneDialoguePhase.cancelled);
      expect(h.engine.status, ChatStatus.idle);
    });

    test('A2 cancel while the commit is blocked still keeps the committed turn',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final commitStarted = Completer<void>();
      final commitGate = Completer<SceneDialogueCommitResult>();
      h.repo.commitStarted = commitStarted;
      h.repo.commitGate = commitGate;

      final pending = h.engine.sendMessage('进入森林');
      await commitStarted.future;
      h.engine.cancelStreaming();
      // The database accepted the turn even though the user cancelled during it.
      commitGate.complete(SceneDialogueCommitResult(
        applied: true,
        gameState: h.repo.lastCommit!.gameState.copyWith(
          currentScene: _committedScene,
          gold: 42,
        ),
        effects: const SceneDialogueEffects(),
      ));
      await pending;

      expect(h.repo.commitCalls, 1);
      expect(h.messages.where((m) => m.isUser), hasLength(1));
      expect(h.assistantMessages, hasLength(1),
          reason: 'the committed assistant message must be applied');
      expect(h.hasErrorCard, isFalse);
      expect(h.gameState.currentScene, _committedScene,
          reason: 'committed GameState must win over the cancellation');
      expect(h.gameState.gold, 42);
      expect(h.engine.sceneDialoguePhase, SceneDialoguePhase.completed);
      expect(h.appliedResults, hasLength(1));
    });

    test('A3 cancel immediately after the commit cannot roll it back',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final commitStarted = Completer<void>();
      final commitGate = Completer<SceneDialogueCommitResult>();
      h.repo.commitStarted = commitStarted;
      h.repo.commitGate = commitGate;

      final pending = h.engine.sendMessage('进入森林');
      await commitStarted.future;
      // Complete first, then cancel synchronously: the cancel lands right after
      // the durable commit but before the awaiting continuation runs.
      commitGate.complete(SceneDialogueCommitResult(
        applied: true,
        gameState: h.repo.lastCommit!.gameState.copyWith(
          currentScene: _committedScene,
          gold: 42,
        ),
        effects: const SceneDialogueEffects(),
      ));
      h.engine.cancelStreaming();
      await pending;

      expect(h.messages.where((m) => m.isUser), hasLength(1));
      expect(h.assistantMessages, hasLength(1));
      expect(h.hasErrorCard, isFalse);
      expect(h.gameState.currentScene, _committedScene);
      expect(h.engine.sceneDialoguePhase, SceneDialoguePhase.completed);
    });

    test(
        'A4 a commit failure before durability rolls back the uncommitted turn',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final commitStarted = Completer<void>();
      final commitGate = Completer<SceneDialogueCommitResult>();
      h.repo.commitStarted = commitStarted;
      h.repo.commitGate = commitGate;

      final pending = h.engine.sendMessage('进入森林');
      await commitStarted.future;
      h.engine.cancelStreaming();
      // The transaction fails: nothing durable happened, so the turn is still
      // an uncommitted in-memory draft and the rollback is legitimate.
      commitGate.completeError(StateError('数据库写入失败'));
      await pending;

      expect(h.messages, isEmpty,
          reason: 'nothing was committed, so the rollback is correct');
      expect(h.assistantMessages, isEmpty);
      expect(h.appliedResults, isEmpty);
      expect(h.engine.sceneDialoguePhase, SceneDialoguePhase.cancelled);
    });

    test(
        'A5 duplicate cancellation is idempotent and does not poison the next '
        'turn', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final llmStarted = Completer<void>();
      final llmGate = Completer<void>();
      h.llm.started = llmStarted;
      h.llm.gate = llmGate;

      final pending = h.engine.sendMessage('进入森林');
      await llmStarted.future;
      h.engine.cancelStreaming();
      h.engine.cancelStreaming();
      h.engine.cancelStreaming();
      llmGate.complete();
      await pending;

      expect(h.repo.commitCalls, 0);
      expect(h.messages, isEmpty);
      expect(h.engine.status, ChatStatus.idle);

      // A fresh request must not be blocked by the previous cancellation flag.
      h.llm.gate = null;
      h.llm.started = null;
      await h.engine.sendMessage('再次进入');

      expect(h.repo.commitCalls, 1);
      expect(h.messages.where((m) => m.isUser), hasLength(1));
      expect(h.assistantMessages, hasLength(1));
      expect(h.engine.sceneDialoguePhase, SceneDialoguePhase.completed);
    });

    test('A6 a stale request cannot commit after the context moved on',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final llmStarted = Completer<void>();
      final llmGate = Completer<void>();
      h.llm.started = llmStarted;
      h.llm.gate = llmGate;

      final stale = h.engine.sendMessage('进入森林');
      await llmStarted.future;
      // Adventure switch / reset: bumps the generation and detaches the request.
      h.engine.resetState();
      llmGate.complete();
      await stale;

      expect(h.repo.commitCalls, 0,
          reason: 'a superseded request must not write');
      expect(h.messages, isEmpty);

      h.llm.gate = null;
      h.llm.started = null;
      await h.engine.sendMessage('新的开始');

      expect(h.repo.commitCalls, 1);
      expect(h.assistantMessages, hasLength(1));
    });

    test('A7 the turn after a commit uses the committed GameState as its base',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);

      await h.engine.sendMessage('进入森林');
      expect(h.gameState.currentScene, _committedScene);

      // Second turn: the payload carries no `scene`, so the base scene must come
      // from the committed state applied above, not the pre-commit state.
      h.llm.content = '$_narrative\n---JSON---\n'
          '{"options":["继续深入","原地观察","退回入口"]}';
      await h.engine.sendMessage('继续深入');

      expect(h.repo.commitCalls, 2);
      expect(h.repo.lastCommit!.gameState.currentScene, _committedScene,
          reason: 'the second turn must start from the committed state');
      expect(h.assistantMessages, hasLength(2));
    });
  });
}
