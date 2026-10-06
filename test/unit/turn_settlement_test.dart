import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lt_dialogue/core/widgets/narrative_paragraph_read_view.dart';
import 'package:lt_dialogue/domain/read_aloud/read_aloud_contracts.dart';
import 'package:lt_dialogue/services/read_aloud/read_aloud_controller.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import '../helpers/read_aloud_fakes.dart';
import 'package:lt_dialogue/engines/chat_engine.dart';
import 'package:lt_dialogue/models/adventure_response.dart';
import 'package:lt_dialogue/widgets/adventure_message_card.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import '../helpers/responsive_test_helper.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/models/custom_attribute_item.dart';
import 'package:lt_dialogue/models/dialogue_level.dart';
import 'package:lt_dialogue/models/game_state.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/models/scene_dialogue.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:lt_dialogue/models/turn_settlement.dart';
import 'package:lt_dialogue/models/adventure_tracked_state.dart';
import 'package:lt_dialogue/models/tracked_state_definition.dart';
import 'package:lt_dialogue/models/typed_runtime_state.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/chat_engine_host_fixture.dart';

/// Thrown by a scripted request instead of returning a body.
final class _ScriptedFailure {
  const _ScriptedFailure(this.error);
  final Object error;
}

/// Records every request so a test can prove **how many** requests ran, in
/// what order, and with which parameters.
final class _ScriptedLlmService extends LLMService {
  _ScriptedLlmService(this.script)
      : super(const LLMConfig(
          provider: LLMProvider.deepseek,
          apiKey: 'test-key',
          baseUrl: 'https://example.invalid',
          model: 'deepseek-flash',
        ));

  /// One entry per call: a response body or a [_ScriptedFailure].
  final List<Object> script;

  final List<CompletionParams> params = <CompletionParams>[];
  final List<List<Map<String, String>>> messages =
      <List<Map<String, String>>>[];
  final List<bool> reasoningCallbacks = <bool>[];
  final List<String?> requestIds = <String?>[];

  /// Splits one response into chunks: `(callIndex, content) -> chunks`.
  List<String> Function(int callIndex, String content)? chunker;

  /// Synchronous hook, invoked when call [callIndex] starts.
  void Function(int callIndex)? onCallStart;
  Future<void> Function(int callIndex)? beforeResponse;

  /// Synchronous hook, invoked immediately before each `onChunk` delivery.
  void Function(int callIndex, String chunk)? onChunkObserved;

  /// Indexes of the requests that were turn-settlement requests.
  List<int> get settlementCalls => [
        for (var index = 0; index < messages.length; index++)
          if (_isSettlement(index)) index,
      ];

  bool _isSettlement(int index) {
    final first = messages[index].isEmpty ? null : messages[index].first;
    return first != null &&
        first['role'] == 'system' &&
        (first['content'] ?? '').contains('剧情结算器');
  }

  @override
  Future<LLMStreamResult> sendMessageStreamDetailed(
    List<Map<String, String>> messages,
    void Function(String chunk) onChunk,
    void Function() onDone, {
    void Function(String reasoningChunk)? onReasoningChunk,
    CompletionParams params = const CompletionParams(),
    GenerationTaskHandle? taskHandle,
  }) async {
    final index = this.params.length;
    this.params.add(params);
    this.messages.add(messages);
    reasoningCallbacks.add(onReasoningChunk != null);
    requestIds.add(taskHandle?.requestId);
    onCallStart?.call(index);
    await beforeResponse?.call(index);

    if (index >= script.length) {
      throw StateError('unscripted LLM call #$index');
    }
    final entry = script[index];
    if (entry is _ScriptedFailure) throw entry.error;
    final result = entry is LLMStreamResult
        ? entry
        : LLMStreamResult(
            content: entry as String,
            finishReason: LLMFinishReason.stop,
            responseCompleted: true);
    final content = result.content;
    final reasoning = result.reasoningContent;
    if (reasoning != null) onReasoningChunk?.call(reasoning);

    for (final chunk in chunker?.call(index, content) ?? <String>[content]) {
      onChunkObserved?.call(index, chunk);
      onChunk(chunk);
    }
    onDone();
    return result;
  }
}

final class _SettlementHarness {
  _SettlementHarness({
    required this.adventureId,
    required this.repository,
    required this.config,
  });

  final int adventureId;
  final IAdventureRepository repository;
  final AdventureConfig config;
  final List<Message> messages = <Message>[];
  final List<SceneDialogueCommitResult> commits = <SceneDialogueCommitResult>[];

  GameState gameState = GameState(hp: 100, maxHp: 100);

  /// Flipped mid-flight by the staleness test to simulate an adventure switch.
  int? adventureIdOverride;

  ChatEngine build(
    _ScriptedLlmService llm, {
    DialogueLevel dialogueLevel = DialogueLevel.l0,
    bool thinking = false,
  }) {
    return ChatEngine(
      host: ChatDependencies(
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
        getGameTopic: () => '测试冒险',
        getGameDifficulty: () => '普通',
        getCompletionParams: () => CompletionParams(
            enableThinking: thinking,
            maxTokens: 2048,
            reasoningEffort: thinking ? 'max' : 'high'),
        getCurrentAdventureId: () => adventureIdOverride ?? adventureId,
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
        getDialogueLevel: () => dialogueLevel,
        onSceneDialogueCommitResult: commits.add,
      ),
      notifyParent: () {},
      adventureRepo: repository,
    );
  }
}

const String _narrative = '艾莉丝在石桥边停下脚步，确认远处的追兵已经失去踪迹。夜风掠过河面，'
    '火把的倒影随着水波摇曳，你们决定暂时在桥边休整。';

const String _firstPassSentence = '桥面的石板湿滑，你们放慢脚步。';
const String _supplementSentence = '远处的钟声敲了三下，雾气更浓了。';

String _settlementJson({
  List<String> options = const ['查看艾莉丝的伤势', '询问袭击者身份', '寻找安全地点'],
  List<Map<String, dynamic>> evaluations = const [],
  List<Map<String, dynamic>> runtimeChanges = const [],
}) =>
    jsonEncode({
      'schema_version': TurnSettlement.schemaVersion,
      'options': options,
      if (evaluations.isNotEmpty) 'custom_status_evaluations': evaluations,
      if (runtimeChanges.isNotEmpty) 'runtime_state_changes': runtimeChanges,
    });

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;
  late IAdventureRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_turn_settlement_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    repository = AdventureRepositoryImpl(getDb: () => DatabaseService.database);
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<int> turnsPersisted(int adventureId) async {
    final db = await DatabaseService.database;
    final rows = await db.query('scene_dialogue_turns',
        where: 'adventure_id = ?', whereArgs: [adventureId]);
    return rows.length;
  }

  Future<Map<String, dynamic>> diagnosticsOf(int adventureId) async {
    final db = await DatabaseService.database;
    final rows = await db.query('scene_dialogue_turns',
        where: 'adventure_id = ?', whereArgs: [adventureId]);
    expect(rows, hasLength(1));
    return jsonDecode(rows.single['diagnostics_json'] as String)
        as Map<String, dynamic>;
  }

  Future<IAdventureRepository> reopenSqlite() async {
    await DatabaseService.resetDatabase();
    return AdventureRepositoryImpl(getDb: () => DatabaseService.database);
  }

  AdventureConfig configWith({
    List<CustomAttributeItem> protagonistAttributes = const [],
    List<SupportingCharacter> companions = const [],
  }) =>
      AdventureConfig(
        name: '旅人',
        customAttributes: protagonistAttributes,
        supportingCharacters: companions,
      );

  group('Relationship turn settlement closed loop', () {
    test(
        'should settle frozen identities and clamp strength for the next prompt',
        () async {
      final config = AdventureConfig(name: 'Alice', selectedCharacters: [
        AdventureSelectedCharacter(
            id: 'a',
            characterId: 'a',
            characterName: 'Alice',
            isProtagonist: true),
        AdventureSelectedCharacter(
            id: 'b', characterId: 'b', characterName: 'Bob'),
        AdventureSelectedCharacter(
            id: 'c', characterId: 'c', characterName: 'Carol'),
        AdventureSelectedCharacter(
            id: 'd', characterId: 'd', characterName: 'David'),
      ], characterRelationships: [
        AdventureCharacterRelationship(
          id: 'rel_ab',
          sourceCharacterId: 'a',
          targetCharacterId: 'b',
          relationType: AdventureRelationType.friend,
          description: 'original note',
        ),
        ...List.generate(
          300,
          (index) => AdventureCharacterRelationship(
            id: 'other_relationship_$index',
            sourceCharacterId: 'c',
            targetCharacterId: 'd',
            relationType: AdventureRelationType.friend,
          ),
        ),
      ]);
      final id =
          await repository.createAdventure('Relationship closed loop', config);
      await repository.seedRuntimeEntity(
          adventureId: id,
          branchId: 0,
          entityType: RuntimeEntityType.relationship,
          entityId: 'rel_ab');
      Map<String, dynamic> change(
              String path, Object value, String operation) =>
          {
            'entity_type': 'relationship',
            'entity_id': 'rel_ab',
            'change_kind': 'primary',
            'operation': operation,
            'path': path,
            'value': value,
            'reason': 'Story changed the bond',
          };
      final llm = _ScriptedLlmService([
        _narrative,
        _settlementJson(runtimeChanges: [
          change('relationship', 'enemy', 'set'),
          change('type', 'enemy', 'set'),
          change('strength', 90, 'set'),
          change('notes', '', 'set'),
        ]),
        _narrative,
        _settlementJson(runtimeChanges: [change('strength', 20, 'increment')]),
        _narrative,
        _settlementJson(),
      ]);
      final harness = _SettlementHarness(
          adventureId: id, repository: repository, config: config);
      final engine = harness.build(llm);
      addTearDown(engine.dispose);
      final previewReady = Completer<void>();
      final resumeNarrative = Completer<void>();
      llm.beforeResponse = (index) async {
        if (index != 2) return;
        previewReady.complete();
        await resumeNarrative.future;
      };
      await engine.sendMessage('Alice confronts Bob');
      expect(llm.settlementCalls, [1]);
      final settlement = llm.messages[1].last['content']!;
      expect(settlement, contains('"relationship_id":"rel_ab"'));
      expect(settlement, contains('"source_name":"Alice"'));
      expect(settlement, contains('"target_name":"Bob"'));
      expect(settlement, contains('"path":"strength"'));
      expect(settlement, contains('"minimum":-100'));
      expect(settlement, contains('"maximum":100'));
      expect(settlement, isNot(contains('runtime_state_changes 必须返回空数组')));
      expect(settlement, contains('不可信资料'));
      final first =
          await repository.getRuntimeTimeline(adventureId: id, branchId: 0);
      expect(first.single.diffs, hasLength(3));
      expect(first.single.diffs.where((d) => d.path == 'relationship'),
          hasLength(1));
      final db = await DatabaseService.database;
      await db.update('adventure_runtime_entities',
          {'updated_at': '2000-01-01T00:00:00.000Z'},
          where: 'adventure_id = ? AND branch_id = ? AND entity_id = ?',
          whereArgs: [id, 0, 'rel_ab']);
      for (final relationship in config.characterRelationships.skip(1)) {
        await repository.seedRuntimeEntity(
            adventureId: id,
            branchId: 0,
            entityType: RuntimeEntityType.relationship,
            entityId: relationship.id);
      }
      expect(await repository.getRuntimeEntities(id, 0), hasLength(301));
      expect(
          await repository.getRuntimeEntities(id, 0, limit: 64), hasLength(64));
      final filteredCurrent = await repository.getCurrentRuntimeState(
          adventureId: id,
          branchId: 0,
          entityType: RuntimeEntityType.relationship,
          entityId: 'rel_ab');
      expect(filteredCurrent.entities.values.single.overlay,
          {'relationship': 'enemy', 'strength': 90, 'notes': ''});
      final inherited = await repository.getRuntimeStateAtRevision(
          adventureId: id, branchId: 0, revision: 1);
      expect(inherited.entities['relationship:rel_ab']!.overlay,
          filteredCurrent.entities.values.single.overlay);
      final pending = engine.sendMessage('Alice and Bob continue');
      await previewReady.future;
      try {
        final before = engine.lastSceneSnapshot?.runtimeRevision;
        final preview = engine.getFullPromptPreview();
        expect(preview.first['content'], contains('strength = 90'));
        expect(engine.lastSceneSnapshot?.runtimeRevision, before);
      } finally {
        resumeNarrative.complete();
      }
      await pending;
      expect(llm.messages[3].last['content'], contains('"strength":90'));
      expect(llm.messages[2].first['content'],
          contains('current relationship = "enemy"'));
      expect(
          llm.messages[2].first['content'], isNot(contains('original note')));
      final turnRows = await db.query('scene_dialogue_turns',
          where: 'adventure_id = ?', whereArgs: [id], orderBy: 'rowid');
      final diagnostics = jsonDecode(turnRows[1]['diagnostics_json'] as String)
          as Map<String, dynamic>;
      final trace = diagnostics['context_trace'] as Map<String, dynamic>;
      final relationshipEntry = (trace['sources'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((entry) => entry['relationship_id'] == 'rel_ab');
      expect(relationshipEntry['effective_value'], 'enemy');
      expect(relationshipEntry['runtime_revision'], 1);
      await engine.sendMessage('Alice and Bob reconsider');
      expect(llm.messages[4].first['content'], contains('strength = 100'));
      expect((await repository.getRuntimeHead(id, 0)).revision, 2);
      expect(await turnsPersisted(id), 3);
      final reopened = await reopenSqlite();
      final current =
          await reopened.getCurrentRuntimeState(adventureId: id, branchId: 0);
      expect(current.entities['relationship:rel_ab']!.overlay,
          {'relationship': 'enemy', 'strength': 100, 'notes': ''});
      final replay = await reopened.getRuntimeStateAtRevision(
          adventureId: id, branchId: 0, revision: 2);
      expect(replay.entities['relationship:rel_ab']!.overlay,
          current.entities['relationship:rel_ab']!.overlay);
    });
  });

  for (final recoveryStage in [1, 2, 4]) {
    test('L5 stage$recoveryStage recovery commits one turn and one revision',
        () async {
      final config = configWith(companions: [
        SupportingCharacter(id: 'alice', name: '艾莉丝', customAttributes: const [
          CustomAttributeItem(
              id: 'affinity',
              name: '好感度',
              value: '50/100',
              currentValue: 50,
              maxValue: 100),
        ]),
      ]);
      final adventureId =
          await repository.createAdventure('L5 recovery', config);
      final script = <Object>[];
      for (var stage = 1; stage <= 4; stage++) {
        if (stage == recoveryStage) {
          script.add(const LLMStreamResult(
              content: '',
              reasoningContent: 'private analysis',
              finishReason: LLMFinishReason.stop,
              responseCompleted: true));
        }
        final prose = '林' * (stage == 1 ? 2000 : 1500);
        script.add(stage == 4
            ? '$prose\n---JSON---\n{"scene":"石桥","options":["a","b","c"],'
                '"custom_status":[{"characterName":"艾莉丝","name":"好感度",'
                '"value":"55/100","currentValue":55,"maxValue":100}]}'
            : prose);
      }
      script.add(_settlementJson(evaluations: const [
        {
          'character_id': 'alice',
          'attribute_id': 'affinity',
          'changed': true,
          'operation': 'delta',
          'value': 5,
          'reason': '本轮保护了同伴'
        },
      ]));
      final llm = _ScriptedLlmService(script);
      final harness = _SettlementHarness(
          adventureId: adventureId, repository: repository, config: config);
      final engine =
          harness.build(llm, dialogueLevel: DialogueLevel.l5, thinking: true);
      addTearDown(engine.dispose);
      final recoveringThinkingFlags = <bool>[];
      llm.onCallStart = (index) {
        if (llm.requestIds[index]!.endsWith(':prose-recovery')) {
          recoveringThinkingFlags.add(engine.isThinkingNotifier.value);
        }
      };
      await engine.sendMessage('询问石桥旁的同伴');
      expect(llm.params, hasLength(6));
      expect(llm.settlementCalls, [5]);
      final recoveryIndex =
          llm.requestIds.indexWhere((id) => id!.endsWith(':prose-recovery'));
      expect(llm.requestIds[recoveryIndex],
          '${llm.requestIds[recoveryIndex - 1]}:prose-recovery');
      expect(llm.params[recoveryIndex].enableThinking, isFalse);
      expect(llm.params[recoveryIndex].reasoningEffort, 'low');
      expect(llm.params[recoveryIndex].maxTokens,
          recoveryStage == 1 ? 5712 : 2912);
      expect(llm.reasoningCallbacks[recoveryIndex], isFalse);
      expect(recoveringThinkingFlags, [false]);
      expect(llm.messages[recoveryIndex].last['content'],
          contains(recoveryStage == 4 ? '本幕为终幕' : '本幕为中间幕'));
      for (final request in llm.messages) {
        expect(request.toString(), isNot(contains('private analysis')));
        expect(
            request
                .where((m) => m['role'] == 'assistant')
                .every((m) => m['content']!.trim().isNotEmpty),
            isTrue);
      }
      expect(engine.parsedOptions, ['查看艾莉丝的伤势', '询问袭击者身份', '寻找安全地点']);
      expect(harness.commits, hasLength(1));
      expect(await turnsPersisted(adventureId), 1);
      final durable = await repository.getMessages(adventureId);
      expect(durable.where((m) => m.isUser), hasLength(1));
      expect(durable.where((m) => !m.isUser && !m.isError), hasLength(1));
      expect(durable.last.reasoningContent, 'private analysis');
      expect((await repository.getRuntimeHead(adventureId, 0)).revision, 1);
      expect(
          (await repository.getRuntimeEntities(adventureId, 0))
              .single
              .overlay['custom_attributes.affinity'],
          55);
      final reopened = await reopenSqlite();
      expect((await reopened.getRuntimeHead(adventureId, 0)).revision, 1);
      expect(
          (await reopened.getRuntimeEntities(adventureId, 0))
              .single
              .overlay['custom_attributes.affinity'],
          55);
      expect(engine.status, ChatStatus.idle);
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Case A — narrative passes on the first attempt.
  // ─────────────────────────────────────────────────────────────────────────
  group('Case A: single-pass narrative', () {
    test('settlement runs exactly once, after the narrative stream ended',
        () async {
      final config = configWith(
        companions: [SupportingCharacter(id: 'alice', name: '艾莉丝')],
      );
      final adventureId = await repository.createAdventure('Case A', config);
      final llm = _ScriptedLlmService([
        '$_narrative\n---JSON---\n{"scene":"石桥","options":["石桥上的旧选项"]}',
        _settlementJson(),
      ]);
      final harness = _SettlementHarness(
        adventureId: adventureId,
        repository: repository,
        config: config,
      );
      final engine = harness.build(llm);
      addTearDown(engine.dispose);

      final statusAtSettlement = <ChatStatus>[];
      final streamingAtSettlement = <bool>[];
      llm.onCallStart = (index) {
        if (index == 1) {
          statusAtSettlement.add(engine.status);
          streamingAtSettlement.add(engine.isStreaming);
        }
      };

      await engine.sendMessage('我扶着艾莉丝坐下。');

      expect(llm.settlementCalls, equals([1]),
          reason: 'exactly one settlement, as the second request');
      expect(statusAtSettlement, equals([ChatStatus.settling]),
          reason: 'settlement must start only after the narrative finished');
      expect(streamingAtSettlement, equals([false]),
          reason: 'narrative streaming must already be over');
      expect(engine.parsedOptions, equals(['查看艾莉丝的伤势', '询问袭击者身份', '寻找安全地点']));
      expect(await turnsPersisted(adventureId), 1);
      final diagnostics = await diagnosticsOf(adventureId);
      expect(diagnostics['turn_settlement_status'], 'applied');
      expect(diagnostics['turn_settlement_attempts'], 1);
    });

    test('settlement uses a low-latency task policy', () async {
      final adventureId =
          await repository.createAdventure('Case A policy', configWith());
      final llm = _ScriptedLlmService([
        '$_narrative\n---JSON---\n{"scene":"石桥","options":["a","b","c"]}',
        _settlementJson(),
      ]);
      final harness = _SettlementHarness(
        adventureId: adventureId,
        repository: repository,
        config: configWith(),
      );
      final engine = harness.build(llm);
      addTearDown(engine.dispose);

      await engine.sendMessage('继续前进');

      final settlementParams = llm.params[llm.settlementCalls.single];
      expect(settlementParams.enableThinking, isFalse,
          reason: 'settlement never inherits narrative thinking');
      expect(settlementParams.maxTokens, 1024,
          reason: 'settlement never inherits the narrative token budget');
      expect(settlementParams.temperature, 0.15);
      expect(settlementParams.responseFormat, {'type': 'json_object'});
      expect(llm.reasoningCallbacks[llm.settlementCalls.single], isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Case B — narrative needs one length supplement.
  // ─────────────────────────────────────────────────────────────────────────
  test(
      'Case B: settlement runs once, after the supplement, on the final '
      'narrative', () async {
    final firstPass = _firstPassSentence * 6;
    final supplement = _supplementSentence * 40;
    final adventureId =
        await repository.createAdventure('Case B', configWith());
    final llm = _ScriptedLlmService([
      '$firstPass\n---JSON---\n{"scene":"石桥","options":["石桥上的旧选项"]}',
      supplement,
      _settlementJson(),
    ]);
    final harness = _SettlementHarness(
      adventureId: adventureId,
      repository: repository,
      config: configWith(),
    );
    final engine = harness.build(llm, dialogueLevel: DialogueLevel.l2);
    addTearDown(engine.dispose);

    await engine.sendMessage('继续沿着河岸前进');

    expect(llm.messages, hasLength(3));
    expect(llm.settlementCalls, equals([2]),
        reason: 'never settle between the first pass and the supplement');
    final settlementPrompt =
        llm.messages[2].map((message) => message['content']).join('\n');
    expect(settlementPrompt, contains('桥面的石板湿滑'));
    expect(settlementPrompt, contains('远处的钟声敲了三下'),
        reason: 'settlement must see the merged final narrative, '
            'not just the first segment');

    final diagnostics = await diagnosticsOf(adventureId);
    expect(diagnostics['length_guard_triggered'], isTrue);
    expect(diagnostics['turn_settlement_status'], 'applied');
    expect(diagnostics['turn_settlement_attempts'], 1);
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Case C — settlement streaming must not touch the narrative channel.
  // ─────────────────────────────────────────────────────────────────────────
  test('Case C: settlement chunks never reach the narrative bubble', () async {
    const markerOption = '只应出现在结算里的选项🗝️';
    const emojiOption = '询问袭击者身份🔮';
    final settlementBody = _settlementJson(options: [
      markerOption,
      emojiOption,
      '寻找安全地点',
    ]);
    final adventureId =
        await repository.createAdventure('Case C', configWith());
    final llm = _ScriptedLlmService([
      '$_narrative\n---JSON---\n{"scene":"石桥","options":["旧选项一"]}',
      settlementBody,
    ])
      // 7 UTF-16 code units per chunk deliberately splits surrogate pairs
      // (emoji) and multi-byte Chinese characters mid-scalar.
      ..chunker = (index, content) {
        final chunks = <String>[];
        for (var i = 0; i < content.length; i += 7) {
          final end = i + 7 > content.length ? content.length : i + 7;
          chunks.add(content.substring(i, end));
        }
        return chunks;
      };
    final harness = _SettlementHarness(
      adventureId: adventureId,
      repository: repository,
      config: configWith(),
    );
    final engine = harness.build(llm);
    addTearDown(engine.dispose);

    final notifierValues = <String>[];
    void record() => notifierValues.add(engine.streamNotifier.value);
    engine.streamNotifier.addListener(record);
    addTearDown(() => engine.streamNotifier.removeListener(record));

    final narrativeDuringSettlement = <String>[];
    llm.onChunkObserved = (index, chunk) {
      if (index == 1) narrativeDuringSettlement.add(engine.streamingContent);
    };

    await engine.sendMessage('我扶着艾莉丝坐下。');

    expect(narrativeDuringSettlement, isNotEmpty,
        reason: 'the settlement response really was streamed in chunks');
    final first = narrativeDuringSettlement.first;
    expect(narrativeDuringSettlement.every((value) => value == first), isTrue,
        reason: '_streamingContent must not grow during settlement');
    for (final value in notifierValues) {
      expect(value, isNot(contains(markerOption)));
      expect(value, isNot(contains('🔮')));
    }
    expect(engine.streamingContent, isNot(contains(markerOption)));
    // Every chunk still arrived: the accumulator holds the complete JSON.
    expect(engine.parsedOptions, contains(markerOption));
    expect(engine.parsedOptions, contains(emojiOption));
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Case D — runtime state change reaches SQLite.
  // ─────────────────────────────────────────────────────────────────────────
  test('Case D: hp delta -20 survives a DB reopen', () async {
    final adventureId =
        await repository.createAdventure('Case D', configWith());
    final llm = _ScriptedLlmService([
      '$_narrative\n---JSON---\n{"scene":"石桥","options":["a","b","c"]}',
      _settlementJson(
        runtimeChanges: const [
          {
            'entity_type': 'character',
            'entity_id': 'protagonist',
            'change_kind': 'primary',
            'operation': 'increment',
            'path': 'hp',
            'value': -20,
            'reason': '本轮遭受攻击',
          },
        ],
      ),
    ]);
    final harness = _SettlementHarness(
      adventureId: adventureId,
      repository: repository,
      config: configWith(),
    );
    final engine = harness.build(llm);
    addTearDown(engine.dispose);

    await engine.sendMessage('我挡在艾莉丝身前');

    expect((await repository.getRuntimeHead(adventureId, 0)).revision, 1);
    final entity = (await repository.getRuntimeEntities(adventureId, 0)).single;
    expect(entity.entityId, 'protagonist');
    expect(entity.overlay['hp'], 80);

    final reopened = await reopenSqlite();
    expect((await reopened.getGameState(adventureId))?.hp, 80);
    expect((await reopened.getRuntimeHead(adventureId, 0)).revision, 1);
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Case E — custom status delta, never applied twice.
  // ─────────────────────────────────────────────────────────────────────────
  test('Case E: affinity 50 -> 55 and not 60', () async {
    final config = configWith(
      companions: [
        SupportingCharacter(
          id: 'alice',
          name: '艾莉丝',
          customAttributes: const [
            CustomAttributeItem(
              id: 'affinity',
              name: '好感度',
              value: '50/100',
              currentValue: 50,
              maxValue: 100,
            ),
          ],
        ),
      ],
    );
    final adventureId = await repository.createAdventure('Case E', config);
    final llm = _ScriptedLlmService([
      // The narrative payload still echoes a legacy snapshot with delta +5
      // baked in; it must NOT be applied on top of the settlement delta.
      '$_narrative\n---JSON---\n{"scene":"石桥","options":["a","b","c"],'
          '"custom_status":[{"characterName":"艾莉丝","name":"好感度",'
          '"value":"55/100","currentValue":55,"maxValue":100}]}',
      _settlementJson(
        evaluations: const [
          {
            'character_id': 'alice',
            'attribute_id': 'affinity',
            'changed': true,
            'operation': 'delta',
            'value': 5,
            'reason': '玩家主动保护了她',
          },
        ],
      ),
    ]);
    final harness = _SettlementHarness(
      adventureId: adventureId,
      repository: repository,
      config: config,
    );
    final engine = harness.build(llm);
    addTearDown(engine.dispose);

    await engine.sendMessage('我扶着艾莉丝坐下。');

    final entity = (await repository.getRuntimeEntities(adventureId, 0)).single;
    expect(entity.overlay['custom_attributes.affinity'], 55,
        reason: 'the legacy narrative snapshot must not double-apply');
    expect(harness.messages.last.content, contains('55/100'));

    final reopened = await reopenSqlite();
    final reopenedEntity =
        (await reopened.getRuntimeEntities(adventureId, 0)).single;
    expect(reopenedEntity.overlay['custom_attributes.affinity'], 55);
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Case F — changed=false keeps state untouched.
  // ─────────────────────────────────────────────────────────────────────────
  test('Case F: changed=false leaves the status untouched', () async {
    final config = configWith(
      companions: [
        SupportingCharacter(
          id: 'alice',
          name: '艾莉丝',
          customAttributes: const [
            CustomAttributeItem(
              id: 'affinity',
              name: '好感度',
              value: '50/100',
              currentValue: 50,
              maxValue: 100,
            ),
          ],
        ),
      ],
    );
    final adventureId = await repository.createAdventure('Case F', config);
    final llm = _ScriptedLlmService([
      '$_narrative\n---JSON---\n{"scene":"石桥","options":["a","b","c"]}',
      _settlementJson(
        evaluations: const [
          {
            'character_id': 'alice',
            'attribute_id': 'affinity',
            'changed': false,
            'reason': '没有足够剧情依据',
          },
        ],
      ),
    ]);
    final harness = _SettlementHarness(
      adventureId: adventureId,
      repository: repository,
      config: config,
    );
    final engine = harness.build(llm);
    addTearDown(engine.dispose);

    await engine.sendMessage('我点点头');

    expect(await repository.getRuntimeEntities(adventureId, 0), isEmpty);
    expect((await repository.getRuntimeHead(adventureId, 0)).revision, 0);
    // changed=false 必须可诊断：能区分「AI 判定没变」与「系统丢掉了变化」。
    expect(
      harness.commits.single.statusDiagnostics,
      contains('settlement:evaluated:alice:affinity:false'),
    );
    expect(
      harness.commits.single.statusDiagnostics,
      isNot(contains('settlement:applied:alice:affinity:50/100->50/100')),
    );
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Case G — a missing evaluation is a diagnostic, not silence.
  // ─────────────────────────────────────────────────────────────────────────
  test('Case G: an unevaluated tracked status produces a diagnostic', () async {
    final config = configWith(
      companions: [
        SupportingCharacter(
          id: 'alice',
          name: '艾莉丝',
          customAttributes: const [
            CustomAttributeItem(
                id: 'trust',
                name: '信任度',
                value: '20/100',
                currentValue: 20,
                maxValue: 100),
            CustomAttributeItem(
                id: 'fatigue',
                name: '疲劳度',
                value: '10/100',
                currentValue: 10,
                maxValue: 100),
            CustomAttributeItem(
                id: 'alert',
                name: '警觉度',
                value: '30/100',
                currentValue: 30,
                maxValue: 100),
          ],
        ),
      ],
    );
    final adventureId = await repository.createAdventure('Case G', config);
    final llm = _ScriptedLlmService([
      '$_narrative\n---JSON---\n{"scene":"石桥","options":["a","b","c"]}',
      _settlementJson(
        evaluations: const [
          {
            'character_id': 'alice',
            'attribute_id': 'trust',
            'changed': true,
            'operation': 'delta',
            'value': 5,
            'reason': '接受了玩家解释',
          },
          {
            'character_id': 'alice',
            'attribute_id': 'fatigue',
            'changed': false,
            'reason': '没有足够剧情依据',
          },
        ],
      ),
    ]);
    final harness = _SettlementHarness(
      adventureId: adventureId,
      repository: repository,
      config: config,
    );
    final engine = harness.build(llm);
    addTearDown(engine.dispose);

    await engine.sendMessage('我向艾莉丝解释。');

    expect(
      harness.commits.single.statusDiagnostics,
      contains('unevaluated_attribute:alert'),
      reason: 'a silently skipped status must be reported, not assumed false',
    );
    final entity = (await repository.getRuntimeEntities(adventureId, 0)).single;
    expect(entity.overlay['custom_attributes.trust'], 25);
    expect(entity.overlay.containsKey('custom_attributes.fatigue'), isFalse);
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Case H — invalid settlement JSON.
  // ─────────────────────────────────────────────────────────────────────────
  test(
      'Case H: invalid settlement JSON keeps the narrative and never '
      'regenerates it', () async {
    final adventureId =
        await repository.createAdventure('Case H', configWith());
    final llm = _ScriptedLlmService([
      '$_narrative\n---JSON---\n{"scene":"石桥",'
          '"options":["继续前进","检查装备","观察河面"]}',
      '{"schema_version":1,"options":["截断',
      '{"schema_version":1,"options":["继续坏掉的',
    ]);
    final harness = _SettlementHarness(
      adventureId: adventureId,
      repository: repository,
      config: configWith(),
    );
    final engine = harness.build(llm);
    addTearDown(engine.dispose);

    await engine.sendMessage('我继续前进。');

    expect(llm.messages, hasLength(3),
        reason: 'one narrative plus at most two settlement attempts');
    expect(llm.settlementCalls, equals([1, 2]));
    expect(harness.messages.where((message) => !message.isUser), hasLength(1));
    expect(harness.messages.last.content, contains('艾莉丝在石桥边停下脚步'));
    expect(engine.parsedOptions, equals(['继续前进', '检查装备', '观察河面']));
    expect(engine.lastErrorType, isNull);
    final diagnostics = await diagnosticsOf(adventureId);
    expect(diagnostics['turn_settlement_status'], 'failed_json');
    expect(diagnostics['turn_settlement_attempts'], 2);
    expect(await repository.getRuntimeEntities(adventureId, 0), isEmpty);
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Case I — settlement network failure.
  // ─────────────────────────────────────────────────────────────────────────
  test(
      'Case I: a settlement network failure keeps the narrative and the '
      'previous revision', () async {
    final adventureId =
        await repository.createAdventure('Case I', configWith());
    final llm = _ScriptedLlmService([
      '$_narrative\n---JSON---\n{"scene":"石桥",'
          '"options":["继续前进","检查装备","观察河面"]}',
      _ScriptedFailure(_FakeNetworkError()),
      _ScriptedFailure(_FakeNetworkError()),
    ]);
    final harness = _SettlementHarness(
      adventureId: adventureId,
      repository: repository,
      config: configWith(),
    );
    final engine = harness.build(llm);
    addTearDown(engine.dispose);

    await engine.sendMessage('我继续前进。');

    expect(harness.messages.where((message) => !message.isUser), hasLength(1));
    expect(harness.messages.last.content, contains('艾莉丝在石桥边停下脚步'));
    expect(engine.lastErrorType, isNull,
        reason: 'an auxiliary failure must not surface as a failed turn');
    expect(engine.parsedOptions, equals(['继续前进', '检查装备', '观察河面']));
    expect((await repository.getRuntimeHead(adventureId, 0)).revision, 0,
        reason: 'fail-closed: no state change without a settlement');
    expect(await turnsPersisted(adventureId), 1);
    final diagnostics = await diagnosticsOf(adventureId);
    expect(diagnostics['turn_settlement_status'], 'failed_request');
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Case J — a late settlement is discarded.
  // ─────────────────────────────────────────────────────────────────────────
  test('Case J: a stale settlement is dropped after an adventure switch',
      () async {
    final adventureId =
        await repository.createAdventure('Case J', configWith());
    final llm = _ScriptedLlmService([
      '$_narrative\n---JSON---\n{"scene":"石桥","options":["旧选项"]}',
      _settlementJson(options: const [
        '迟到的选项一',
        '迟到的选项二',
        '迟到的选项三',
      ]),
    ]);
    final harness = _SettlementHarness(
      adventureId: adventureId,
      repository: repository,
      config: configWith(),
    );
    final engine = harness.build(llm);
    addTearDown(engine.dispose);

    llm.onCallStart = (index) {
      if (index == 1) harness.adventureIdOverride = adventureId + 99;
    };

    await engine.sendMessage('我继续前进。');

    expect(llm.settlementCalls, equals([1]));
    expect(await turnsPersisted(adventureId), 0,
        reason: 'a settlement from a superseded turn must never be committed');
    expect(await repository.getRuntimeEntities(adventureId, 0), isEmpty);
    expect((await repository.getRuntimeHead(adventureId, 0)).revision, 0);
    expect(engine.parsedOptions, isNot(contains('迟到的选项一')));
    expect(engine.status, ChatStatus.idle);
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Case K — same-name characters stay isolated.
  // ─────────────────────────────────────────────────────────────────────────
  test('Case K: two characters named 艾莉丝 never share a status', () async {
    const attributes = [
      CustomAttributeItem(
        id: 'affinity',
        name: '好感度',
        value: '50/100',
        currentValue: 50,
        maxValue: 100,
      ),
    ];
    final config = configWith(
      companions: [
        SupportingCharacter(
            id: 'alice_a', name: '艾莉丝', customAttributes: attributes),
        SupportingCharacter(
            id: 'alice_b', name: '艾莉丝', customAttributes: attributes),
      ],
    );
    final adventureId = await repository.createAdventure('Case K', config);
    final llm = _ScriptedLlmService([
      '$_narrative\n---JSON---\n{"scene":"石桥","options":["a","b","c"]}',
      _settlementJson(
        evaluations: const [
          {
            'character_id': 'alice_b',
            'attribute_id': 'affinity',
            'changed': true,
            'operation': 'delta',
            'value': 5,
            'reason': '只有第二个艾莉丝在场',
          },
          {
            'character_id': 'alice_a',
            'attribute_id': 'affinity',
            'changed': false,
            'reason': '本轮未出场',
          },
        ],
      ),
    ]);
    final harness = _SettlementHarness(
      adventureId: adventureId,
      repository: repository,
      config: config,
    );
    final engine = harness.build(llm);
    addTearDown(engine.dispose);

    await engine.sendMessage('我向第二个艾莉丝点头。');

    final entities = await repository.getRuntimeEntities(adventureId, 0);
    final byId = {for (final entity in entities) entity.entityId: entity};
    expect(byId.containsKey('alice_b'), isTrue);
    expect(byId['alice_b']!.overlay['custom_attributes.affinity'], 55);
    expect(byId.containsKey('alice_a'), isFalse,
        reason: 'the same-named character must not receive the delta');
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Case L — supplement keeps the narrative JSON contract intact.
  // ─────────────────────────────────────────────────────────────────────────
  test('Case L: the supplement path still merges payload and narrative',
      () async {
    final firstPass = _firstPassSentence * 6;
    final supplement = _supplementSentence * 40;
    final adventureId =
        await repository.createAdventure('Case L', configWith());
    final llm = _ScriptedLlmService([
      '$firstPass\n---JSON---\n{"scene":"石桥","options":["旧选项"]}',
      '$supplement\n---JSON---\n{"scene":"错误重复","options":["错误重复"]}',
      _settlementJson(),
    ]);
    final harness = _SettlementHarness(
      adventureId: adventureId,
      repository: repository,
      config: configWith(),
    );
    final engine = harness.build(llm, dialogueLevel: DialogueLevel.l2);
    addTearDown(engine.dispose);

    await engine.sendMessage('继续沿着河岸前进');

    final assistant = harness.messages.lastWhere((message) => !message.isUser);
    final marker = assistant.content.indexOf('---JSON---');
    expect(marker, greaterThan(0));
    final body = assistant.content.substring(0, marker);
    expect(body, contains('桥面的石板湿滑'));
    expect(body, contains('远处的钟声敲了三下'));
    expect('---JSON---'.allMatches(assistant.content), hasLength(1));
    expect(body, isNot(contains('"错误重复"')));
    expect(engine.parsedOptions, equals(['查看艾莉丝的伤势', '询问袭击者身份', '寻找安全地点']));
  });

  test('settlement is skipped outside a persisted adventure', () async {
    final llm = _ScriptedLlmService([
      '$_narrative\n---JSON---\n{"scene":"石桥","options":["a","b","c"]}',
    ]);
    final messages = <Message>[];
    final engine = ChatEngine(
      host: ChatDependencies(
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
        getCurrentAdventureId: () => null,
        getCurrentBranchId: () => 0,
        getActivePersona: () => null,
        getSelectedCharacterName: () => null,
        getTts: () => null,
        getLLMService: () => llm,
        setProvider: (_) async {},
        setModel: (_) async {},
        getGameState: () => GameState(),
        setGameState: (_) {},
        getMessages: () => messages,
        setMessages: (value) {
          messages
            ..clear()
            ..addAll(value);
        },
        getDialogueLevel: () => DialogueLevel.l0,
      ),
      notifyParent: () {},
      adventureRepo: repository,
    );
    addTearDown(engine.dispose);

    await engine.sendMessage('继续前进');

    expect(llm.settlementCalls, isEmpty);
    expect(llm.messages, hasLength(1));
  });

  group('Assistant presentation production protocol', () {
    const prose = '她推开门，看向桌上的海图，逐一确认航线与沿途的港口。林澈仔细思索明日的行程，'
        '窗外的海风掠过屋檐，船长仍在等待她的决定。';
    const originalOptions = ['仔细查看桌上的海图', '询问船长航线安排', '整理明日出航的行囊'];
    const replacementOptions = ['与船长商议绕开暗礁', '去港口寻找熟悉航线的向导', '检查船上的淡水与补给'];
    const mind = '明日出航之前必须确认航线';
    final payload = jsonEncode({
      'scene': '旅店',
      'options': originalOptions,
      'custom_status': [
        {'name': '伪造状态', 'value': '不可信'}
      ],
      'custom_status_changes': [],
      'custom_status_evaluations': [],
    });
    final shapes = <String, String>{
      'canonical': '$prose\n---JSON---\n$payload',
      'inline tail': '$prose\n\n$payload',
      'pure JSON': jsonEncode({
        ...jsonDecode(payload) as Map<String, dynamic>,
        'narrative': [prose]
      }),
      'spaced separator': '$prose\n--- JSON ---\n$payload',
      'newline separator': '$prose\n---\nJSON---\n$payload',
    };

    Future<Message> produce(String input,
        {bool settlementOptions = false,
        bool repair = false,
        bool secondTurn = false,
        bool hasDefinitions = true}) async {
      final config = AdventureConfig(
          name: '林澈',
          selectedCharacters: [
            AdventureSelectedCharacter(
                id: 'lc',
                characterId: 'lc',
                characterName: '林澈',
                isProtagonist: true),
          ],
          trackedStateDefinitions: hasDefinitions
              ? const [
                  AdventureTrackedStateDefinition(
                    entityType: RuntimeEntityType.character,
                    entityId: 'lc',
                    definition: TrackedStateDefinition(
                        id: 'inner_voice',
                        name: '心声',
                        valueKind: RuntimeStateValueKind.text),
                  )
                ]
              : const []);
      final id =
          await repository.createAdventure('Presentation production', config);
      await repository.seedRuntimeEntity(
          adventureId: id,
          branchId: 0,
          entityType: RuntimeEntityType.character,
          entityId: 'lc');
      if (hasDefinitions) {
        await repository.commitRuntimeMutation(RuntimeStateMutation(
          requestId: 'seed-mind-$id',
          adventureId: id,
          branchId: 0,
          draft: const RuntimeStateCommitDraft(
              expectedRevision: 0,
              summary: 'Fixture current state',
              changes: [
                RuntimeStateChangeProposal(
                    entityType: RuntimeEntityType.character,
                    entityId: 'lc',
                    changeKind: RuntimeChangeKind.primary,
                    operation: RuntimeChangeOperation.set,
                    path: 'custom_attributes.inner_voice',
                    value: mind,
                    reason: '已有心声'),
              ]),
        ));
      }
      final script = <Object>[
        input,
        if (repair) ...[
          const _ScriptedFailure(SocketException('offline')),
          const _ScriptedFailure(SocketException('offline')),
          jsonEncode({'options': replacementOptions}),
        ] else ...[
          _settlementJson(
              options: settlementOptions ? replacementOptions : const []),
          if (!settlementOptions) _settlementJson(options: const []),
        ],
        if (secondTurn) ...[
          prose,
          _settlementJson(runtimeChanges: [
            {
              'entity_type': 'character',
              'entity_id': 'lc',
              'change_kind': 'primary',
              'operation': 'set',
              'path': 'custom_attributes.inner_voice',
              'value': '新的心声',
              'reason': '下一轮改变',
            }
          ])
        ],
      ];
      final llm = _ScriptedLlmService(script);
      final harness = _SettlementHarness(
          adventureId: id, repository: repository, config: config);
      final engine = harness.build(llm);
      try {
        await engine.sendMessage('我查看海图。');
        expect(engine.lastErrorType, isNull);
        expect(harness.commits, hasLength(1));
        expect(
            llm.settlementCalls, repair || !settlementOptions ? [1, 2] : [1]);
        expect(
            llm.messages, hasLength(repair ? 4 : (settlementOptions ? 2 : 3)));
        final diagnostics = await diagnosticsOf(id);
        expect(
            diagnostics['turn_settlement_options_applied'], settlementOptions);
        final first = harness.messages.last;
        if (secondTurn) await engine.sendMessage('我决定明日出航。');
        final reopened = await reopenSqlite();
        final messages = await reopened.getMessages(id);
        final persisted = messages.singleWhere(
            (message) => !message.isUser && message.content == first.content);
        final parsed = AdventureResponse.tryParseSplit(persisted.content)!;
        expect(parsed.narrative, [prose]);
        expect(parsed.options,
            settlementOptions || repair ? replacementOptions : originalOptions);
        if (hasDefinitions) {
          expect(parsed.customStatus, hasLength(1));
          expect(parsed.customStatus.single.name, '心声');
          expect(parsed.customStatus.single.characterName, '林澈');
          expect(parsed.customStatus.single.value, mind);
        } else {
          expect(parsed.customStatus, isEmpty);
        }
        expect(persisted.content, isNot(contains('伪造状态')));
        expect(persisted.content, isNot(contains('custom_status_changes')));
        expect(persisted.content, isNot(contains('custom_status_evaluations')));
        expect(persisted.content, contains(AdventureResponse.jsonSeparator));
        expect(
            AdventureResponse.llmHistoryProjection(persisted.content), prose);
        expect(AdventureResponse.streamingDisplayText(persisted.content).trim(),
            prose);
        if (secondTurn) {
          expect(
              (await reopened.getRuntimeEntities(id, 0))
                  .single
                  .overlay['custom_attributes.inner_voice'],
              '新的心声');
          expect(
              AdventureResponse.tryParseSplit(messages.last.content)!
                  .customStatus
                  .single
                  .value,
              '新的心声');
          final history = llm.messages[3]
              .where((entry) => entry['role'] == 'assistant')
              .map((entry) => entry['content'])
              .join();
          expect(history, contains(prose));
          expect(history, isNot(contains('custom_status')));
          expect(history, isNot(contains('options')));
        }
        return persisted;
      } finally {
        engine.dispose();
      }
    }

    for (final shape in shapes.entries) {
      for (final replacement in [false, true]) {
        test(
            'should persist ${shape.key} with ${replacement ? "settlement" : "narrative"} options after SQLite reopen',
            () async {
          await produce(shape.value, settlementOptions: replacement);
        });
      }
    }
    test('should persist repaired options and snapshot after SQLite reopen',
        () async {
      await produce(prose, repair: true);
    });
    test(
        'should remove raw model status when the authoritative snapshot is empty',
        () async {
      await produce(shapes['inline tail']!, hasDefinitions: false);
    });
    test('should keep earlier persisted snapshot after a later runtime change',
        () async {
      await produce(shapes['inline tail']!, secondTurn: true);
    });
    testWidgets(
        'should render real ChatEngine persisted output as narrative then state then options',
        (tester) async {
      final message =
          await tester.runAsync(() => produce(shapes['inline tail']!));
      expect(message, isNotNull);
      for (final viewport in requiredUiViewports) {
        setViewport(tester, width: viewport.width, height: viewport.height);
        await tester.pumpWidget(MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
              body: SingleChildScrollView(
                  child: AdventureMessageCard(
            jsonContent: message!.content,
            brightness: Brightness.light,
          ))),
        ));
        await tester.pumpAndSettle();
        final narrativeY = tester.getTopLeft(find.text(prose)).dy;
        final statusY = tester.getTopLeft(find.text('心声')).dy;
        final optionsY = tester
            .getTopLeft(find
                .textContaining(AppLocalizationsZh().optionsSectionTitle(3)))
            .dy;
        expect(narrativeY, lessThan(statusY));
        expect(statusY, lessThan(optionsY));
        expect(find.text('林澈'), findsOneWidget);
        expect(find.text(mind), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      final speechEngine = FakeReadAloudEngine();
      final controller = ReadAloudController(
          engine: speechEngine,
          initialPreferences: const ReadAloudPreferences(enabled: true));
      addTearDown(controller.dispose);
      setViewport(tester, width: 412, height: 915);
      await tester.pumpWidget(ProviderScope(
          overrides: [
            readAloudControllerProvider.overrideWith((ref) => controller,
                disposeNotifier: false),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
                body: SingleChildScrollView(
                    child: AdventureMessageCard(
              jsonContent: message!.content,
              brightness: Brightness.light,
              readSessionId: 'production-message',
            ))),
          )));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<NarrativeParagraphReadView>(
                  find.byType(NarrativeParagraphReadView))
              .text
              .trim(),
          prose);
      await tester.longPress(find.text(prose));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppLocalizationsZh().readAloudParagraph));
      await tester.pumpAndSettle();
      // Speech planning inserts spaces between sentences. Compare the full
      // spoken content, excluding whitespace only, so any status/option/JSON
      // leakage still fails this assertion.
      expect(speechEngine.spokenTexts.join().replaceAll(RegExp(r'\s+'), ''),
          prose);
      expect(tester.takeException(), isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Tracked-state authority → assistant message `custom_status` snapshot.
  // ─────────────────────────────────────────────────────────────────────────
  group('Tracked state message snapshot', () {
    AdventureConfig trackedConfig() => AdventureConfig(
          name: '旅人',
          selectedCharacters: [
            AdventureSelectedCharacter(
              id: 'lc',
              characterId: 'lc',
              characterName: '林澈',
              isProtagonist: true,
            ),
          ],
          trackedStateDefinitions: const [
            AdventureTrackedStateDefinition(
              entityType: RuntimeEntityType.character,
              entityId: 'lc',
              definition: TrackedStateDefinition(
                id: 'curse_corruption',
                name: '精神污染',
                valueKind: RuntimeStateValueKind.integer,
                minimum: 0,
                maximum: 100,
              ),
            ),
            AdventureTrackedStateDefinition(
              entityType: RuntimeEntityType.character,
              entityId: 'lc',
              definition: TrackedStateDefinition(
                id: 'trust',
                name: '信任度',
                valueKind: RuntimeStateValueKind.integer,
              ),
            ),
          ],
        );

    test(
        'Cases A+B: committed message carries the settled value and the untriggered row',
        () async {
      final config = trackedConfig();
      final adventureId =
          await repository.createAdventure('Tracked snapshot', config);
      await repository.seedRuntimeEntity(
        adventureId: adventureId,
        branchId: 0,
        entityType: RuntimeEntityType.character,
        entityId: 'lc',
      );

      final llm = _ScriptedLlmService([
        _narrative,
        _settlementJson(runtimeChanges: [
          {
            'entity_type': 'character',
            'entity_id': 'lc',
            'change_kind': 'primary',
            'operation': 'set',
            'path': 'custom_attributes.curse_corruption',
            'value': 18,
            'reason': '正文中诅咒明显加深',
          },
        ]),
      ]);
      final harness = _SettlementHarness(
        adventureId: adventureId,
        repository: repository,
        config: config,
      );
      final engine = harness.build(llm);
      addTearDown(engine.dispose);

      await engine.sendMessage('我继续深入废墟。');

      final content = harness.messages.last.content;
      // The inline block is projected from the unified authority, not the empty
      // legacy customAttributes.
      expect(content, contains('custom_status'));
      expect(content, contains('精神污染'));
      expect(content, contains('18/100'));
      // A definition with no value is explicit, never hidden and never zero.
      expect(content, contains('信任度'));
      expect(content, contains('untriggered'));

      // The committed overlay agrees with the snapshot value.
      final entity =
          (await repository.getRuntimeEntities(adventureId, 0)).single;
      expect(entity.overlay['custom_attributes.curse_corruption'], 18);
    });

    test('Case D: an out-of-range set never reaches the snapshot', () async {
      final config = trackedConfig();
      final adventureId =
          await repository.createAdventure('Tracked out of range', config);
      await repository.seedRuntimeEntity(
        adventureId: adventureId,
        branchId: 0,
        entityType: RuntimeEntityType.character,
        entityId: 'lc',
      );

      final llm = _ScriptedLlmService([
        _narrative,
        _settlementJson(runtimeChanges: [
          {
            'entity_type': 'character',
            'entity_id': 'lc',
            'change_kind': 'primary',
            'operation': 'set',
            'path': 'custom_attributes.curse_corruption',
            'value': 120,
            'reason': '模型越界提议',
          },
        ]),
      ]);
      final harness = _SettlementHarness(
        adventureId: adventureId,
        repository: repository,
        config: config,
      );
      final engine = harness.build(llm);
      addTearDown(engine.dispose);

      await engine.sendMessage('我继续深入废墟。');

      final content = harness.messages.last.content;
      // 120 exceeds the frozen maximum of 100 → rejected → the row stays
      // untriggered; the snapshot must never echo the raw proposal.
      expect(content, isNot(contains('120')));
      expect(content, contains('untriggered'));

      final entity =
          (await repository.getRuntimeEntities(adventureId, 0)).single;
      expect(entity.overlay['custom_attributes.curse_corruption'], isNull);
    });
  });
}

final class _FakeNetworkError extends Error {
  @override
  String toString() => 'FakeNetworkError: settlement request failed';
}
