import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/engines/chat_engine.dart';
import 'package:lt_dialogue/engines/game_engine.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_response.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/models/dialogue_level.dart';
import 'package:lt_dialogue/models/game_state.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/models/scene_dialogue.dart';
import 'package:lt_dialogue/models/scene_state.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:lt_dialogue/models/turn_settlement.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/chat_engine_host_fixture.dart';

/// Scripted LLM that records every request. One script entry per call: a
/// response body (String) or a failure to throw.
final class _ScriptedLlmService extends LLMService {
  _ScriptedLlmService(this.script)
      : super(const LLMConfig(
          provider: LLMProvider.deepseek,
          apiKey: 'test-key',
          baseUrl: 'https://example.invalid',
          model: 'deepseek-flash',
        ));

  final List<Object> script;
  final List<List<Map<String, String>>> requests =
      <List<Map<String, String>>>[];

  int get callCount => requests.length;

  /// The system prompt of the **narrative** request of the most recent turn
  /// (skipping the settlement request that follows it).
  String get lastNarrativeSystemPrompt {
    for (final request in requests.reversed) {
      final system =
          request.firstWhereOrNull((m) => m['role'] == 'system')?['content'] ??
              '';
      // The settlement prompt introduces itself as the turn's settlement
      // engine; skip it to reach the narrative request of the turn.
      if (system.contains('剧情结算器')) continue;
      return system;
    }
    return '';
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
    final index = requests.length;
    requests.add(messages);
    if (index >= script.length) {
      throw StateError('unscripted LLM call #$index');
    }
    final entry = script[index];
    if (entry is _ScriptedFailure) throw entry.error;
    final content = entry as String;
    onChunk(content);
    onDone();
    return LLMStreamResult(
      content: content,
      finishReason: LLMFinishReason.stop,
      responseCompleted: true,
    );
  }
}

final class _ScriptedFailure {
  const _ScriptedFailure(this.error);
  final Object error;
}

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final item in this) {
      if (test(item)) return item;
    }
    return null;
  }
}

/// Two-person scene: the protagonist with 艾拉 and 鲍里斯 present, while the
/// third roster character 卡森 is available but absent.
const _filler = '窗外的天色渐渐沉下来，街灯一盏盏亮起，把两个人的影子拉得很长，'
    '空气里全是烘咖啡豆和旧木头的味道。';

/// Pads a short narrative past the L2 minimum (400) and below the hard
/// maximum (1000) so the length guard never fires for the wrong reason.
String _long(String core) {
  var text = core;
  var guard = 0;
  while (text.length < 700 && guard < 40) {
    text += _filler;
    guard++;
  }
  return text;
}

String _settlementJson({
  List<String> options = const ['继续和她聊下去', '问问她的近况', '安静地坐一会儿'],
  List<Map<String, dynamic>> runtimeChanges = const [],
}) =>
    jsonEncode({
      'schema_version': TurnSettlement.schemaVersion,
      'options': options,
      if (runtimeChanges.isNotEmpty) 'runtime_state_changes': runtimeChanges,
    });

/// A narrative payload carrying a scene-state proposal.
String _narrativeWithProposal(
  String narrative, {
  List<String> charactersEnter = const [],
  List<String> charactersLeave = const [],
  String? location,
  String? time,
  List<Map<String, dynamic>> goalsUpdate = const [],
  List<Map<String, dynamic>> runtimeChanges = const [],
}) {
  final changes = <String, dynamic>{
    if (charactersEnter.isNotEmpty) 'characters_enter': charactersEnter,
    if (charactersLeave.isNotEmpty) 'characters_leave': charactersLeave,
    if (location != null) 'location': location,
    if (time != null) 'time': time,
    if (goalsUpdate.isNotEmpty) 'goals_update': goalsUpdate,
  };
  return '$narrative\n${AdventureResponse.jsonSeparator}\n'
      '${jsonEncode({
        'scene': '第1幕·咖啡馆',
        'options': ['继续和她聊下去', '问问她的近况', '安静地坐一会儿'],
        if (changes.isNotEmpty) 'scene_state_changes': changes,
        if (runtimeChanges.isNotEmpty) 'runtime_state_changes': runtimeChanges,
      })}';
}

final class _Harness {
  _Harness({
    required this.repository,
    required this.adventureId,
    required this.config,
    required this.sceneState,
  });

  final IAdventureRepository repository;
  final int adventureId;
  final AdventureConfig config;
  SceneState sceneState;
  final List<Message> messages = <Message>[];
  final List<SceneDialogueCommitResult> commits = <SceneDialogueCommitResult>[];

  GameState gameState = GameState(hp: 100, maxHp: 100);
  _ScriptedLlmService? activeLlm;

  /// When true the host exposes a real [GameEngine] so the turn builds the
  /// per-round affinity summary (which needs an [AffinityManager]).
  bool withGameEngine = false;

  GameEngine _buildGameEngine() => GameEngine(
        combatMgr: CombatManager(
          getGameState: () => gameState,
          setGameState: (value) => gameState = value,
          getAllSkills: () => const [],
          getCharacterSkills: (_) => const [],
        ),
        skillMgr: SkillManager(
          getAllSkills: () async => const [],
          getCharacterSkills: (_) async => const [],
          saveCharacterSkill: (_) async => 0,
          updateCharacterSkill: (_, __) async {},
          getGameState: () => gameState,
          setGameState: (value) => gameState = value,
        ),
        affinityMgr: AffinityManager(),
        inventoryMgr: InventoryManager(
          getEquipment: (_) async => const [],
          saveEquipment: (_) async {},
          getInventoryItems: (_) async => const [],
          getInventoryItemsByCharacter: (_, __) async => const [],
          saveInventoryItem: (_) async => 0,
          updateInventoryItem: (_, __) async {},
          deleteInventoryItem: (_) async {},
          getGameState: () => gameState,
          setGameState: (value) => gameState = value,
        ),
      );

  ChatEngine build() {
    return ChatEngine(
      host: ChatDependencies(
        getApiKey: () => 'test-key',
        getApiBaseUrl: () => 'https://example.invalid',
        getGameEngine: () => withGameEngine ? _buildGameEngine() : null,
        getProviderType: () => LLMProvider.deepseek,
        getModelName: () => 'deepseek-flash',
        getCustomSystemPrompt: () => '',
        getAuthorsNote: () => '',
        getAuthorsNoteDepth: () => 0,
        getAuthorsNoteFrequency: () => 0,
        getAdventureConfig: () => config,
        getWorldEntries: () => const [],
        getBrightness: () => Brightness.light,
        getGameTopic: () => '咖啡馆',
        getGameDifficulty: () => '普通',
        getCompletionParams: () =>
            const CompletionParams(enableThinking: false, maxTokens: 4096),
        getCurrentAdventureId: () => adventureId,
        getCurrentBranchId: () => 0,
        getActivePersona: () => null,
        getSelectedCharacterName: () => null,
        getTts: () => null,
        getLLMService: () => activeLlm!,
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
        getSceneParticipantIds: () => sceneState.presentCharacterIds,
        getSceneState: () => sceneState,
      ),
      notifyParent: () {},
      adventureRepo: repository,
    );
  }

  DialogueLevel dialogueLevel = DialogueLevel.l2;
}

AdventureConfig _config() => AdventureConfig(
      name: '旅人',
      supportingCharacters: [
        SupportingCharacter(id: 'npc-a', name: '艾拉', role: '吟游诗人'),
        SupportingCharacter(id: 'npc-b', name: '鲍里斯', role: '保镖'),
        SupportingCharacter(id: 'npc-c', name: '卡森', role: '商人'),
      ],
    );

SceneState _sceneState() => const SceneState(
      location: '咖啡馆',
      time: '傍晚',
      presentCharacterIds: ['protagonist', 'npc-a', 'npc-b'],
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;
  late IAdventureRepository repository;
  late int adventureId;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_narrative_authority_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    repository = AdventureRepositoryImpl(getDb: () => DatabaseService.database);
    adventureId = await repository.createAdventure('叙事控制权', _config());
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  _Harness harness({DialogueLevel level = DialogueLevel.l2}) {
    final h = _Harness(
      repository: repository,
      adventureId: adventureId,
      config: _config(),
      sceneState: _sceneState(),
    );
    h.dialogueLevel = level;
    return h;
  }

  Future<SceneState?> sceneStateOf() =>
      repository.getSceneState(adventureId, 0);

  /// Diagnostics of the most recent committed turn.
  Future<Map<String, dynamic>> latestDiagnostics() async {
    final db = await DatabaseService.database;
    final rows = await db.query('scene_dialogue_turns',
        where: 'adventure_id = ?',
        whereArgs: [adventureId],
        orderBy: 'rowid DESC',
        limit: 1);
    return jsonDecode(rows.single['diagnostics_json'] as String)
        as Map<String, dynamic>;
  }

  Future<List<String>> ignoredSceneChanges() async =>
      ((await latestDiagnostics())['ignored_scene_state_changes'] as List?)
          ?.cast<String>() ??
      const [];

  Future<List<String>> ignoredRuntimeChanges() async =>
      ((await latestDiagnostics())['ignored_runtime_state_changes'] as List?)
          ?.cast<String>() ??
      const [];

  Future<List<String>> continuityWarnings() async =>
      ((await latestDiagnostics())['warnings'] as List?)?.cast<String>() ??
      const [];

  group('P2: scene participant authority', () {
    test('1. model tries to force an absent third party into an A/B scene',
        () async {
      final h = harness();
      h.activeLlm = _ScriptedLlmService([
        _long('艾拉靠在窗边，目光落在你身上，等你先开口。'),
        _settlementJson(),
        // Prose never depicts 卡森, yet the payload tries to make him present.
        _narrativeWithProposal(_long('鲍里斯把外套搭在椅背上，打量着你，一言不发。'),
            charactersEnter: ['npc-c']),
        _settlementJson(),
      ]);
      final engine = h.build();
      await engine.sendMessage('安静地坐了一会儿。');
      await engine.sendMessage('鲍里斯清了清嗓子。');

      final state = await sceneStateOf();
      expect(state!.presentCharacterIds,
          containsAll(['protagonist', 'npc-a', 'npc-b']));
      expect(state.presentCharacterIds, isNot(contains('npc-c')));
      expect(await ignoredSceneChanges(),
          contains('scene_state_changes:characters_enter:unauthorized:npc-c'));
    });

    test('2. user excludes C and the model still proposes his entry', () async {
      final h = harness();
      h.activeLlm = _ScriptedLlmService([
        _long('艾拉靠在窗边，目光落在你身上，等你先开口。'),
        _settlementJson(),
        // Prose names 卡森, but the player excluded him this turn.
        _narrativeWithProposal(_long('鲍里斯把外套搭在椅背上；窗外的卡森探了探头，没有靠近。'),
            charactersEnter: ['npc-c']),
        _settlementJson(),
      ]);
      final engine = h.build();
      await engine.sendMessage('先随便聊聊。');
      await engine.sendMessage('不要让卡森打扰我们。');

      final state = await sceneStateOf();
      expect(state!.presentCharacterIds, isNot(contains('npc-c')));
      expect(await ignoredSceneChanges(),
          contains('scene_state_changes:characters_enter:excluded:npc-c'));
    });

    test('3. user only mentions C without allowing entry', () async {
      final h = harness();
      h.activeLlm = _ScriptedLlmService([
        _long('艾拉靠在窗边，目光落在你身上，等你先开口。'),
        _settlementJson(),
        _narrativeWithProposal(_long('鲍里斯把外套搭在椅背上，打量着你，一言不发。'),
            charactersEnter: ['npc-c']),
        _settlementJson(),
      ]);
      final engine = h.build();
      await engine.sendMessage('先随便聊聊。');
      await engine.sendMessage('卡森最近怎么样？');

      final state = await sceneStateOf();
      expect(state!.presentCharacterIds, isNot(contains('npc-c')));
      expect(await ignoredSceneChanges(),
          contains('scene_state_changes:characters_enter:unauthorized:npc-c'));
    });

    test('4. user explicitly invites C and the entry is accepted', () async {
      final h = harness();
      h.activeLlm = _ScriptedLlmService([
        _long('艾拉靠在窗边，目光落在你身上，等你先开口。'),
        _settlementJson(),
        // The invitation authorizes the entry even though this turn's prose
        // does not name him yet.
        _narrativeWithProposal(_long('鲍里斯把外套搭在椅背上，打量着你，一言不发。'),
            charactersEnter: ['npc-c']),
        _settlementJson(),
      ]);
      final engine = h.build();
      await engine.sendMessage('先随便聊聊。');
      await engine.sendMessage('叫卡森一起来吧。');

      final state = await sceneStateOf();
      expect(state!.presentCharacterIds, contains('npc-c'));
      expect(await ignoredSceneChanges(), isEmpty);
    });

    test('5. a third party with narrative basis enters normally', () async {
      final h = harness();
      h.activeLlm = _ScriptedLlmService([
        _long('艾拉靠在窗边，目光落在你身上，等你先开口。'),
        _settlementJson(),
        _narrativeWithProposal(_long('门被推开，卡森端着麦酒走进来，笑着和你们打了个招呼。'),
            charactersEnter: ['npc-c']),
        _settlementJson(),
      ]);
      final engine = h.build();
      await engine.sendMessage('先随便聊聊。');
      await engine.sendMessage('我招呼路过的商人。');

      final state = await sceneStateOf();
      expect(state!.presentCharacterIds, contains('npc-c'));
      expect(await ignoredSceneChanges(), isEmpty);
    });

    test('an unnamed arrival does not authorize an entry', () async {
      final h = harness();
      h.activeLlm = _ScriptedLlmService([
        _long('艾拉靠在窗边，目光落在你身上，等你先开口。'),
        _settlementJson(),
        // Prose depicts an arrival without naming the arriving character. The
        // proposal still claims roster id npc-c, so the entry is refused: an
        // unnamed stranger belongs in scene_candidates, not in presence.
        _narrativeWithProposal(_long('门被推开，那个商人端着麦酒走进来，笑着和你们打了个招呼。'),
            charactersEnter: ['npc-c']),
        _settlementJson(),
      ]);
      final engine = h.build();
      await engine.sendMessage('先随便聊聊。');
      await engine.sendMessage('我招呼路过的商人。');

      final state = await sceneStateOf();
      expect(state!.presentCharacterIds, isNot(contains('npc-c')));
      expect(await ignoredSceneChanges(),
          contains('scene_state_changes:characters_enter:unnamed:npc-c'));
    });

    test('6. quiet two-person scene: an uninvited interruption is observable',
        () async {
      final h = harness();
      h.activeLlm = _ScriptedLlmService([
        _long('艾拉靠在窗边，目光落在你身上，等你先开口。'),
        _settlementJson(),
        _narrativeWithProposal(_long('突然，门被撞开，一个蒙面人闯了进来，目光扫过整个咖啡馆。'),
            charactersEnter: ['npc-c']),
        _settlementJson(),
      ]);
      final engine = h.build();
      await engine.sendMessage('先随便聊聊。');
      await engine.sendMessage('我轻声回应她。');

      final state = await sceneStateOf();
      expect(state!.presentCharacterIds, isNot(contains('npc-c')));
      expect((await continuityWarnings()).any((w) => w.contains('突发方式引入入场角色')),
          isTrue);
    });

    test('a plain crisis in prose is not blocked (no over-restriction)',
        () async {
      final h = harness();
      h.activeLlm = _ScriptedLlmService([
        _long('艾拉靠在窗边，目光落在你身上，等你先开口。'),
        _settlementJson(),
        _long('窗外突然下起了大雨，艾拉看着你笑了笑，把椅子往你这边挪了挪。'),
        _settlementJson(),
      ]);
      final engine = h.build();
      await engine.sendMessage('先随便聊聊。');
      await engine.sendMessage('我望着窗外的天气。');

      expect(h.commits, hasLength(2));
      final state = await sceneStateOf();
      expect(state!.presentCharacterIds,
          containsAll(['protagonist', 'npc-a', 'npc-b']));
    });
  });

  group('P1: narrative beat and player decision point', () {
    test('7. a staged user goal stays active; unknown goal ids are rejected',
        () async {
      final h = harness();
      h.activeLlm = _ScriptedLlmService([
        _narrativeWithProposal(_long('艾拉靠在窗边，目光落在你身上，等你先开口。'), goalsUpdate: [
          {'id': 'intent-guessed', 'status': 'resolved'}
        ]),
        _settlementJson(),
      ]);
      final engine = h.build();
      await engine.sendMessage('我想一步一步赢得艾拉的信任。');

      final state = await sceneStateOf();
      expect(state!.activeGoals.any((g) => g.description.contains('赢得艾拉的信任')),
          isTrue);
      expect(await ignoredSceneChanges(),
          contains('scene_state_changes:goals_update:missing:intent-guessed'));
    });

    test('8. L4 multi-stage stops at the player decision point', () async {
      final h = harness(level: DialogueLevel.l4);
      h.activeLlm = _ScriptedLlmService([
        // Stage 1 already reaches the decision point.
        '艾拉靠在窗边，目光落在你身上，等你先开口。\n${AdventureResponse.playerStopMarker}',
        _settlementJson(),
        // Anything after the settlement would be an unscripted call.
      ]);
      final engine = h.build();
      await engine.sendMessage('我安静地坐在她对面。');

      // One narrative stage + one settlement: the loop never asked for stage 2.
      expect(h.activeLlm!.callCount, 2);
      expect(h.commits.single.applied, isTrue);
      final committedText = h.messages.last.content;
      expect(
          committedText, isNot(contains(AdventureResponse.playerStopMarker)));
      expect(committedText, contains('等你先开口'));
      final diagnostics = await latestDiagnostics();
      expect(diagnostics['length_final_verdict'], 'decision_stop');
      expect(diagnostics['length_stopped_at_decision'], true);
    });

    test('9. under-length turn at a decision point is not supplemented',
        () async {
      final h = harness();
      final engine = h.build();
      h.activeLlm = _ScriptedLlmService([
        '她望着你，等待你的回答。\n${AdventureResponse.playerStopMarker}',
        _settlementJson(),
      ]);
      await engine.sendMessage('我问她愿不愿意留下来。');

      // No length-supplement request was made.
      expect(h.activeLlm!.callCount, 2);
      expect(
          (await latestDiagnostics())['length_final_verdict'], 'decision_stop');

      // The next turn must not carry an underflow warning for it.
      h.activeLlm = _ScriptedLlmService([
        _long('艾拉靠在窗边，目光落在你身上，等你先开口。'),
        _settlementJson(),
      ]);
      await engine.sendMessage('我继续说下去。');
      expect(h.activeLlm!.lastNarrativeSystemPrompt, isNot(contains('尚未跨过')));
    });

    test('a short turn without the marker still triggers the underflow path',
        () async {
      final h = harness();
      h.activeLlm = _ScriptedLlmService([
        '她望着你。',
        // Length supplement continuation.
        '补' * 500,
        _settlementJson(),
      ]);
      final engine = h.build();
      await engine.sendMessage('我问她愿不愿意留下来。');

      // narrative + supplement + settlement
      expect(h.activeLlm!.callCount, 3);
      expect(
          (await latestDiagnostics())['length_final_verdict'], 'within_range');
    });

    test('a bare stop marker with no prose never commits an empty turn',
        () async {
      final h = harness();
      h.activeLlm = _ScriptedLlmService([
        // Marker only: no prose, no payload.
        AdventureResponse.playerStopMarker,
      ]);
      final engine = h.build();
      await engine.sendMessage('我问她愿不愿意留下来。');

      // The protocol failure must not produce a durable turn.
      expect(h.commits, isEmpty);
      final db = await DatabaseService.database;
      final rows = await db.query('scene_dialogue_turns',
          where: 'adventure_id = ?', whereArgs: [adventureId]);
      expect(rows, isEmpty);
    });

    test('a streak of decision-point stops escalates a reminder', () async {
      final h = harness();
      final engine = h.build();
      h.activeLlm = _ScriptedLlmService([
        '她望着你，等待你的回答。\n${AdventureResponse.playerStopMarker}',
        _settlementJson(),
        '她望着你，等待你的回答。\n${AdventureResponse.playerStopMarker}',
        _settlementJson(),
        _long('艾拉靠在窗边，目光落在你身上，等你先开口。'),
        _settlementJson(),
      ]);
      await engine.sendMessage('我问她愿不愿意留下来。');
      await engine.sendMessage('她还是不说话。');
      await engine.sendMessage('我继续说下去。');

      // Two consecutive below-minimum stops must escalate, not be silenced.
      expect(h.activeLlm!.lastNarrativeSystemPrompt,
          contains('已连续 2 轮以 `---等待玩家---` 停笔'));
      // The normal turn resets the streak.
      expect((await latestDiagnostics())['consecutive_decision_stops'], 0);
    });

    test('marker plus payload keeps the payload and commits once', () async {
      final h = harness();
      h.activeLlm = _ScriptedLlmService([
        '她望着你，等待你的回答。\n${AdventureResponse.playerStopMarker}\n'
            '${AdventureResponse.jsonSeparator}\n'
            '${jsonEncode({
              'scene': '第2幕·咖啡馆',
              'options': ['点点头，留下来', '转移话题', '起身告辞'],
            })}',
        _settlementJson(),
      ]);
      final engine = h.build();
      await engine.sendMessage('我问她愿不愿意留下来。');

      expect(h.activeLlm!.callCount, 2);
      expect(h.commits.single.applied, isTrue);
      final committedText = h.messages.last.content;
      expect(
          committedText, isNot(contains(AdventureResponse.playerStopMarker)));
      expect(committedText, contains('她望着你，等待你的回答。'));
      expect(committedText, contains(AdventureResponse.jsonSeparator));
    });
  });

  group('P4: user authorization over scene and time', () {
    test('10. user-authorised time jump is applied', () async {
      final h = harness();
      h.activeLlm = _ScriptedLlmService([
        _long('艾拉靠在窗边，目光落在你身上，等你先开口。'),
        _settlementJson(),
        _narrativeWithProposal(_long('鲍里斯把外套搭在椅背上，打量着你，一言不发。'), time: '第二天清晨'),
        _settlementJson(),
      ]);
      final engine = h.build();
      await engine.sendMessage('先随便聊聊。');
      await engine.sendMessage('直接跳到第二天。');

      final state = await sceneStateOf();
      expect(state!.time, '第二天清晨');
      expect(await ignoredSceneChanges(), isEmpty);
    });

    test('11. a forbidden scene change is vetoed but the turn still commits',
        () async {
      final h = harness();
      h.activeLlm = _ScriptedLlmService([
        _narrativeWithProposal(_long('艾拉靠在窗边，目光落在你身上，等你先开口。')),
        _settlementJson(),
        _narrativeWithProposal(_long('鲍里斯把外套搭在椅背上，打量着你，一言不发。'), location: '王宫'),
        _settlementJson(),
      ]);
      final engine = h.build();
      await engine.sendMessage('先随便聊聊。');
      final locationBefore = (await sceneStateOf())!.location;
      expect(locationBefore, isNot(contains('王宫')));
      await engine.sendMessage('暂时不要换场景，我想多坐一会儿。');

      final state = await sceneStateOf();
      // The forbidden location never lands; the turn is still durable.
      expect(state!.location, locationBefore);
      expect(state.location, isNot(contains('王宫')));
      expect(await ignoredSceneChanges(),
          contains('scene_state_changes:location:forbidden'));
      expect(h.commits, hasLength(2));
      expect(h.commits.last.applied, isTrue);
    });

    test('12. settlement cannot move a player-excluded entity', () async {
      final h = harness();
      h.activeLlm = _ScriptedLlmService([
        _long('艾拉靠在窗边，目光落在你身上，等你先开口。'),
        _settlementJson(),
        _long('鲍里斯把外套搭在椅背上，打量着你，一言不发。'),
        _settlementJson(runtimeChanges: [
          {
            'entity_type': 'character',
            'entity_id': 'npc-c',
            'change_kind': 'primary',
            'operation': 'increment',
            'path': 'affinity',
            'value': 5,
            'reason': '他在窗外点了点头',
          },
        ]),
      ]);
      final engine = h.build();
      await engine.sendMessage('先随便聊聊。');
      await engine.sendMessage('不要让卡森打扰我们。');

      expect(await ignoredRuntimeChanges(),
          contains('runtime_state_change:excluded_entity:npc-c'));
    });

    test('the legacy settlement-failure fallback also honours the exclusion',
        () async {
      final h = harness();
      h.activeLlm = _ScriptedLlmService([
        _long('艾拉靠在窗边，目光落在你身上，等你先开口。'),
        _settlementJson(),
        // The narrative payload (the labelled legacy fallback) tries to move
        // the excluded character's state; both settlement attempts fail, so
        // this is the path that would otherwise apply it.
        _narrativeWithProposal(
          _long('鲍里斯把外套搭在椅背上，打量着你，一言不发。'),
          runtimeChanges: [
            {
              'entity_type': 'character',
              'entity_id': 'npc-c',
              'change_kind': 'primary',
              'operation': 'increment',
              'path': 'affinity',
              'value': 5,
              'reason': '他在窗外点了点头',
            },
          ],
        ),
        'not-json',
        'not-json',
      ]);
      final engine = h.build();
      await engine.sendMessage('先随便聊聊。');
      await engine.sendMessage('不要让卡森打扰我们。');

      final diagnostics = await latestDiagnostics();
      final statusDiagnostics =
          (diagnostics['status_diagnostics'] as List?)?.cast<String>() ??
              const [];
      expect(statusDiagnostics,
          contains('runtime_state_change:excluded_entity:npc-c'));
      // The excluded change never becomes a persisted runtime entity.
      final entities = await repository.getRuntimeEntities(adventureId, 0);
      expect(entities.any((entity) => entity.entityId == 'npc-c'), isFalse);
    });

    test('a failed turn never commits unauthorized state', () async {
      final h = harness();
      h.activeLlm = _ScriptedLlmService([
        _long('艾拉靠在窗边，目光落在你身上，等你先开口。'),
        _settlementJson(),
        _ScriptedFailure(Exception('network down')),
      ]);
      final engine = h.build();
      await engine.sendMessage('先随便聊聊。');
      await engine.sendMessage('鲍里斯继续说道。');

      expect(h.commits, hasLength(1));
      final db = await DatabaseService.database;
      final rows = await db.query('scene_dialogue_turns',
          where: 'adventure_id = ?', whereArgs: [adventureId]);
      expect(rows, hasLength(1));
    });
  });

  group('P4: authorization determinism and repeated proposals', () {
    test('13. repeated unauthorized proposals are filtered every time',
        () async {
      final h = harness();
      h.activeLlm = _ScriptedLlmService([
        _long('艾拉靠在窗边，目光落在你身上，等你先开口。'),
        _settlementJson(),
        _narrativeWithProposal(_long('鲍里斯把外套搭在椅背上，打量着你，一言不发。'),
            charactersEnter: ['npc-c']),
        _settlementJson(),
        _narrativeWithProposal(_long('艾拉靠在窗边，目光落在你身上，等你先开口。'),
            charactersEnter: ['npc-c']),
        _settlementJson(),
      ]);
      final engine = h.build();
      await engine.sendMessage('先随便聊聊。');
      await engine.sendMessage('鲍里斯又讲了个故事。');
      await engine.sendMessage('艾拉轻轻点头。');

      final state = await sceneStateOf();
      expect(state!.presentCharacterIds, isNot(contains('npc-c')));
      expect(h.commits, hasLength(3));
      final db = await DatabaseService.database;
      final rows = await db.query('scene_dialogue_turns',
          where: 'adventure_id = ?', whereArgs: [adventureId]);
      expect(rows, hasLength(3));
    });
  });

  group('P2: prompt contract for the authoritative presence list', () {
    test('14. compiled prompt names the closed presence set', () async {
      final h = harness()..withGameEngine = true;
      h.activeLlm = _ScriptedLlmService([
        _long('艾拉靠在窗边，目光落在你身上，等你先开口。'),
        _settlementJson(),
      ]);
      final engine = h.build();
      await engine.sendMessage('我安静地坐在她对面。');

      final system = h.activeLlm!.lastNarrativeSystemPrompt;
      expect(system, contains('【当前在场角色（权威名单）】旅人、艾拉、鲍里斯'));
      expect(system, contains('只有名单中的角色可以与玩家互动'));
      expect(system, contains('不等于进入场景'));
      expect(system, contains('【等待玩家标记】'));
      expect(system, contains('不得把制造冲突、危机或戏剧性转折当作每轮必须完成的任务'));
      // Present companions keep their affinity summary; the absent 卡森
      // must not leak into it.
      expect(system, contains('【角色好感度】'));
      expect(system, contains('艾拉'));
      expect(system, isNot(contains('卡森')));
    });

    test('15. a mentioned-but-absent companion keeps its affinity line',
        () async {
      final h = harness()..withGameEngine = true;
      h.activeLlm = _ScriptedLlmService([
        _long('艾拉靠在窗边，目光落在你身上，等你先开口。'),
        _settlementJson(),
      ]);
      final engine = h.build();
      await engine.sendMessage('卡森最近怎么样？');

      final system = h.activeLlm!.lastNarrativeSystemPrompt;
      expect(system, contains('【角色好感度】'));
      // The affinity line itself (`卡森: <label> (n/100)`), not merely a
      // reference in the mentioned-absent section.
      expect(system, contains('卡森: '));
      // Still a reference-only mention, never a scene participant.
      expect(system, contains('【被提及但不在场的角色】'));
      expect(system, isNot(contains('【当前在场角色（权威名单）】旅人、艾拉、鲍里斯、卡森')));
    });

    test('16. an adventure with no companions yet leaks no absent affinity',
        () async {
      // Regression for the removed all-NPC fallback: when only the
      // protagonist is present and the player names nobody, no absent
      // companion may appear in the affinity summary.
      final h = harness()..withGameEngine = true;
      h.sceneState = const SceneState(
        location: '咖啡馆',
        time: '傍晚',
        presentCharacterIds: ['protagonist'],
      );
      h.activeLlm = _ScriptedLlmService([
        _long('雨点敲在窗上，你独自坐着。'),
        _settlementJson(),
      ]);
      final engine = h.build();
      await engine.sendMessage('我先在这里坐一会儿。');

      final system = h.activeLlm!.lastNarrativeSystemPrompt;
      expect(system, isNot(contains('【角色好感度】')));
      expect(system, isNot(contains('艾拉: ')));
      expect(system, isNot(contains('鲍里斯: ')));
      expect(system, isNot(contains('卡森: ')));
    });

    test('17. an excluded present character loses its affinity line', () async {
      final h = harness()..withGameEngine = true;
      h.activeLlm = _ScriptedLlmService([
        _long('鲍里斯把外套搭在椅背上，打量着你，一言不发。'),
        _settlementJson(),
      ]);
      final engine = h.build();
      await engine.sendMessage('不要让艾拉打扰我们，我想和鲍里斯单独谈谈。');

      final system = h.activeLlm!.lastNarrativeSystemPrompt;
      // 艾拉 is present in storage but excluded this turn: the authoritative
      // presence list drops her, so the affinity summary must not contradict
      // it by echoing her affinity line.
      expect(system, contains('【角色好感度】'));
      expect(system, contains('鲍里斯: '));
      expect(system, isNot(contains('艾拉: ')));
    });
  });
}
