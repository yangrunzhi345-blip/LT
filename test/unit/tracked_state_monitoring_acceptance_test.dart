import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/adventure/adventure_tracked_state_freezer.dart';
import 'package:lt_dialogue/application/adventure/adventure_tracked_state_registry.dart';
import 'package:lt_dialogue/engines/chat_engine.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/adventure_tracked_state.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/models/custom_attribute_item.dart';
import 'package:lt_dialogue/models/dialogue_level.dart';
import 'package:lt_dialogue/models/game_state.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/models/scene_dialogue.dart'
    show SceneDialogueCommitResult;
import 'package:lt_dialogue/models/tracked_state_definition.dart';
import 'package:lt_dialogue/models/turn_settlement.dart';
import 'package:lt_dialogue/models/worldview_details.dart';
import 'package:lt_dialogue/providers/adventure_provider.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/world_entry_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/chat_engine_host_fixture.dart';

/// Acceptance regression for the monitoring rework:
/// * P1 — a `不可忽略项` is always evaluated (`changed` / `unchanged` /
///   `undetermined`), never silently skipped; a bounded follow-up recovers an
///   omission and a still-missing evaluation degrades instead of blocking.
/// * P2 — a definition added mid-adventure seeds its runtime entity at once.
/// * P3 — a worldview general rule binds to concrete characters/NPCs, each
///   storing an independent value; legacy world definitions stay global.

const String _narrative = '艾琳在石桥边停下脚步，确认远处的追兵已经失去踪迹。'
    '夜风掠过河面，火把的倒影随着水波摇曳。你们决定暂时在桥边休整。';

String _settlement({
  List<Map<String, dynamic>> changes = const [],
  List<Map<String, dynamic>>? evaluations,
  List<String> options = const ['继续前进', '检查装备', '观察河面'],
}) =>
    jsonEncode({
      'schema_version': TurnSettlement.schemaVersion,
      'options': options,
      if (changes.isNotEmpty) 'runtime_state_changes': changes,
      if (evaluations != null) 'tracked_evaluations': evaluations,
    });

final class _ScriptedLlm extends LLMService {
  _ScriptedLlm(this.script)
      : super(const LLMConfig(
          provider: LLMProvider.deepseek,
          apiKey: 'test-key',
          baseUrl: 'https://example.invalid',
          model: 'deepseek-flash',
        ));

  /// One entry per call, in order: narrative, settlement, optional top-up.
  final List<Object> script;
  final List<List<Map<String, String>>> messages =
      <List<Map<String, String>>>[];
  int _calls = 0;

  int get callCount => _calls;

  @override
  Future<LLMStreamResult> sendMessageStreamDetailed(
    List<Map<String, String>> messages,
    void Function(String chunk) onChunk,
    void Function() onDone, {
    void Function(String reasoningChunk)? onReasoningChunk,
    CompletionParams params = const CompletionParams(),
    GenerationTaskHandle? taskHandle,
  }) async {
    final index = _calls++;
    this.messages.add([
      for (final m in messages) Map<String, String>.from(m),
    ]);
    final scripted = index < script.length ? script[index] : script.last;
    if (scripted is Exception) throw scripted;
    final content = scripted as String;
    onChunk(content);
    onDone();
    return LLMStreamResult(
      content: content,
      finishReason: LLMFinishReason.stop,
      responseCompleted: true,
    );
  }
}

TrackedStateDefinition _monitor(
  String id, {
  String name = '生命值',
  CustomAttributeImportance importance = CustomAttributeImportance.critical,
  int? minimum = 0,
  int? maximum = 100,
  TrackedStateScope scope = TrackedStateScope.inherit,
}) =>
    TrackedStateDefinition(
      id: id,
      name: name,
      importance: importance,
      minimum: minimum,
      maximum: maximum,
      scope: scope,
    );

AdventureConfig _characterConfig({
  String id = 'alice',
  CustomAttributeImportance importance = CustomAttributeImportance.critical,
  String monitorId = 'hp_custom',
}) =>
    AdventureConfig(
      name: '旅人',
      selectedCharacters: [
        AdventureSelectedCharacter(
          id: id,
          characterId: id,
          characterName: '艾琳',
          isProtagonist: true,
        ),
      ],
      trackedStateDefinitions: [
        AdventureTrackedStateDefinition(
          entityType: RuntimeEntityType.character,
          entityId: id,
          definition: _monitor(monitorId, importance: importance),
        ),
      ],
    );

final class _EngineHarness {
  _EngineHarness(this.config, this.repository);

  AdventureConfig config;
  final IAdventureRepository repository;
  final List<Message> messages = <Message>[];
  final List<SceneDialogueCommitResult> commits = <SceneDialogueCommitResult>[];
  int? adventureId;
  GameState gameState = GameState(hp: 100, maxHp: 100);

  /// Scene participants resolve to stable ids the candidate planner uses.
  List<String> participantIds = const ['alice'];

  ChatEngine build(_ScriptedLlm llm) => ChatEngine(
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
          getCompletionParams: () =>
              const CompletionParams(enableThinking: false, maxTokens: 2048),
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
          getDialogueLevel: () => DialogueLevel.l0,
          getSceneParticipantIds: () => participantIds,
          onSceneDialogueCommitResult: commits.add,
        ),
        notifyParent: () {},
        adventureRepo: repository,
      );

  List<String> get lastDiagnostics =>
      commits.isEmpty ? const [] : commits.last.statusDiagnostics;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;
  late AdventureRepositoryImpl repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_monitor_accept_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    repository = AdventureRepositoryImpl(getDb: () => DatabaseService.database);
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<_EngineHarness> startEngine({AdventureConfig? config}) async {
    final harness = _EngineHarness(config ?? _characterConfig(), repository);
    harness.adventureId = await repository.createAdventure(
      'Monitored',
      harness.config,
    );
    // A character entity must exist before a proposal may write its overlay.
    await repository.seedRuntimeEntity(
      adventureId: harness.adventureId!,
      branchId: 0,
      entityType: RuntimeEntityType.character,
      entityId: 'alice',
    );
    return harness;
  }

  // ───────────────────────────────────────────────────────────────────────
  // P1 — mandatory evaluation
  // ───────────────────────────────────────────────────────────────────────

  test('P1: prompt marks a critical monitor as mandatory', () async {
    final llm = _ScriptedLlm([
      '$_narrative\n---JSON---\n{"scene":"桥","options":["a","b","c"]}',
      _settlement(evaluations: const [
        {
          'entity_type': 'character',
          'entity_id': 'alice',
          'monitor_id': 'hp_custom',
          'status': 'unchanged',
          'reason': '本轮未受伤',
        },
      ]),
    ]);
    final harness = await startEngine();
    final engine = harness.build(llm);
    addTearDown(engine.dispose);
    await engine.sendMessage('我们继续赶路。');

    final prompt = llm.messages[1].map((m) => m['content']).join('\n');
    expect(prompt, contains('必须评估=true'));
    expect(prompt, contains('monitor_id=hp_custom'));
  });

  test(
      'P1: omission triggers exactly one bounded follow-up that recovers the '
      'evaluation and commits the change', () async {
    final llm = _ScriptedLlm([
      '$_narrative\n---JSON---\n{"scene":"桥","options":["a","b","c"]}',
      // Settlement omits the mandatory monitor entirely.
      _settlement(),
      // Follow-up supplies the missing judgement.
      jsonEncode({
        'tracked_evaluations': [
          {
            'entity_type': 'character',
            'entity_id': 'alice',
            'monitor_id': 'hp_custom',
            'status': 'changed',
            'operation': 'set',
            'value': 88,
            'reason': '艾琳在混战中受伤',
          }
        ]
      }),
    ]);
    final harness = await startEngine();
    final engine = harness.build(llm);
    addTearDown(engine.dispose);
    await engine.sendMessage('我们冲入战团。');

    expect(llm.callCount, 3, reason: 'narrative + settlement + one follow-up');
    final entities =
        await repository.getRuntimeEntities(harness.adventureId!, 0);
    final alice = entities.singleWhere((e) => e.entityId == 'alice');
    expect(alice.overlay['custom_attributes.hp_custom'], 88);
    expect(
        (await repository.getRuntimeHead(harness.adventureId!, 0)).revision, 1);

    final diagnostics = harness.lastDiagnostics;
    expect(diagnostics, contains('critical_evaluation:topup:1'));
    expect(diagnostics,
        contains('critical_evaluation:resolved:character:alice:hp_custom'));
  });

  test('P1: unchanged evaluation never fabricates a value', () async {
    final llm = _ScriptedLlm([
      '$_narrative\n---JSON---\n{"scene":"桥","options":["a","b","c"]}',
      _settlement(evaluations: const [
        {
          'entity_type': 'character',
          'entity_id': 'alice',
          'monitor_id': 'hp_custom',
          'status': 'unchanged',
          'reason': '本轮平静，未受伤',
        },
      ]),
    ]);
    final harness = await startEngine();
    final engine = harness.build(llm);
    addTearDown(engine.dispose);
    await engine.sendMessage('我们安静地休整。');

    // Only the narrative + settlement, no follow-up.
    expect(llm.callCount, 2);
    final entities =
        await repository.getRuntimeEntities(harness.adventureId!, 0);
    expect(entities.every((e) => e.overlay.isEmpty), isTrue);
    expect(
        (await repository.getRuntimeHead(harness.adventureId!, 0)).revision, 0);

    final diagnostics = harness.lastDiagnostics;
    expect(diagnostics,
        contains('critical_evaluation:evaluated:character:alice:hp_custom'));
    expect(diagnostics,
        contains('critical_evaluation:unchanged:character:alice:hp_custom'));
  });

  test('P1: undetermined evaluation never writes', () async {
    final llm = _ScriptedLlm([
      '$_narrative\n---JSON---\n{"scene":"桥","options":["a","b","c"]}',
      _settlement(evaluations: const [
        {
          'entity_type': 'character',
          'entity_id': 'alice',
          'monitor_id': 'hp_custom',
          'status': 'undetermined',
          'reason': '正文没有足够信息',
        },
      ]),
    ]);
    final harness = await startEngine();
    final engine = harness.build(llm);
    addTearDown(engine.dispose);
    await engine.sendMessage('我们观察四周。');

    expect(llm.callCount, 2);
    expect(await repository.getRuntimeEntities(harness.adventureId!, 0),
        everyElement(predicate<RuntimeEntityState>((e) => e.overlay.isEmpty)));
    expect(harness.lastDiagnostics,
        contains('critical_evaluation:undetermined:character:alice:hp_custom'));
  });

  test('P1: a still-missing evaluation degrades and never blocks the turn',
      () async {
    final llm = _ScriptedLlm([
      '$_narrative\n---JSON---\n{"scene":"桥","options":["a","b","c"]}',
      _settlement(),
      // Follow-up also omits it.
      jsonEncode({'tracked_evaluations': []}),
    ]);
    final harness = await startEngine();
    final engine = harness.build(llm);
    addTearDown(engine.dispose);
    await engine.sendMessage('我们冲入战团。');

    expect(llm.callCount, 3);
    expect(harness.commits, isNotEmpty, reason: 'turn must still commit');
    expect(await repository.getRuntimeEntities(harness.adventureId!, 0),
        everyElement(predicate<RuntimeEntityState>((e) => e.overlay.isEmpty)));
    expect(harness.lastDiagnostics,
        contains('critical_evaluation:unevaluated:character:alice:hp_custom'));
  });

  test('P1: a follow-up failure degrades instead of blocking', () async {
    final llm = _ScriptedLlm([
      '$_narrative\n---JSON---\n{"scene":"桥","options":["a","b","c"]}',
      _settlement(),
      Exception('top-up request failed'),
    ]);
    final harness = await startEngine();
    final engine = harness.build(llm);
    addTearDown(engine.dispose);
    await engine.sendMessage('我们冲入战团。');

    expect(harness.commits, isNotEmpty);
    expect(
        harness.lastDiagnostics, contains('critical_evaluation:topup_failed'));
    expect(harness.lastDiagnostics,
        contains('critical_evaluation:unevaluated:character:alice:hp_custom'));
  });

  test('P1: a non-critical monitor keeps the sparse protocol (no follow-up)',
      () async {
    final llm = _ScriptedLlm([
      '$_narrative\n---JSON---\n{"scene":"桥","options":["a","b","c"]}',
      _settlement(),
    ]);
    final harness = await startEngine(
      config: _characterConfig(importance: CustomAttributeImportance.reference),
    );
    final engine = harness.build(llm);
    addTearDown(engine.dispose);
    await engine.sendMessage('我们冲入战团。');

    expect(llm.callCount, 2, reason: 'no mandatory monitor, no follow-up');
    expect(harness.lastDiagnostics.where((d) => d.startsWith('critical_')),
        isEmpty);
  });

  test(
      'P1: an out-of-scope critical monitor is named, never silently invisible',
      () async {
    // Alice is on scene; Bob is an off-scene critical monitor.
    final config = AdventureConfig(
      name: '旅人',
      selectedCharacters: [
        AdventureSelectedCharacter(
          id: 'alice',
          characterId: 'alice',
          characterName: '艾琳',
          isProtagonist: true,
        ),
        AdventureSelectedCharacter(
          id: 'bob',
          characterId: 'bob',
          characterName: '鲍勃',
        ),
      ],
      trackedStateDefinitions: [
        for (final id in ['alice', 'bob'])
          AdventureTrackedStateDefinition(
            entityType: RuntimeEntityType.character,
            entityId: id,
            definition: _monitor('hp_custom'),
          ),
      ],
    );
    final llm = _ScriptedLlm([
      '$_narrative\n---JSON---\n{"scene":"桥","options":["a","b","c"]}',
      _settlement(evaluations: const [
        {
          'entity_type': 'character',
          'entity_id': 'alice',
          'monitor_id': 'hp_custom',
          'status': 'unchanged',
          'reason': '本轮未受伤',
        },
      ]),
    ]);
    final harness = await startEngine(config: config);
    final engine = harness.build(llm);
    addTearDown(engine.dispose);
    await engine.sendMessage('我们继续赶路。');

    expect(llm.callCount, 2, reason: 'only the in-scope critical needs a pass');
    expect(
      harness.lastDiagnostics,
      contains('critical_evaluation:out_of_scope:character:bob:hp_custom'),
    );
  });

  // ───────────────────────────────────────────────────────────────────────
  // P3 — scope
  // ───────────────────────────────────────────────────────────────────────

  AdventureConfig generalRuleConfig({
    TrackedStateScope scope = TrackedStateScope.characters,
    String monitorId = 'hp_custom',
  }) {
    final base = AdventureConfig(
      name: 'Alice',
      selectedCharacters: [
        AdventureSelectedCharacter(
          id: 'alice',
          characterId: 'alice',
          characterName: 'Alice',
          isProtagonist: true,
        ),
        AdventureSelectedCharacter(
          id: 'bob',
          characterId: 'bob',
          characterName: 'Bob',
        ),
      ],
      npcSnapshots: [
        AdventureNpcSnapshot(assetId: 'guard', name: '守门人', npcJson: const {}),
      ],
      worldviewSnapshot: {
        'source_id': 'w1',
        'name': '艾尔德兰',
        'detail_json': WorldviewDetails(
          trackedStateDefinitions: [
            _monitor(monitorId, scope: scope),
          ],
        ).toJson(),
      },
    );
    return base.copyWith(
      trackedStateDefinitions:
          const AdventureTrackedStateFreezer().freeze(base),
    );
  }

  test('P3: scope=characters binds the worldview rule to every character',
      () async {
    final config = generalRuleConfig(scope: TrackedStateScope.characters);
    final entities = config.trackedStateDefinitions
        .where((d) => d.definition.effectiveId == 'hp_custom')
        .toList();
    expect(
      entities.map((d) => '${d.entityType.name}:${d.entityId}').toSet(),
      {'character:alice', 'character:bob'},
    );
  });

  test('P3: scope=npcs binds the worldview rule to every NPC', () async {
    final config = generalRuleConfig(scope: TrackedStateScope.npcs);
    final bindings = config.trackedStateDefinitions
        .where((d) => d.definition.effectiveId == 'hp_custom')
        .toList();
    expect(bindings.single.entityType, RuntimeEntityType.npc);
    expect(bindings.single.entityId, 'guard');
  });

  test('P3: a legacy worldview definition with no scope stays world-global',
      () async {
    final base = AdventureConfig(
      name: 'Alice',
      selectedCharacters: [
        AdventureSelectedCharacter(
          id: 'alice',
          characterId: 'alice',
          characterName: 'Alice',
          isProtagonist: true,
        ),
      ],
      worldviewSnapshot: {
        'source_id': 'w1',
        'name': '艾尔德兰',
        'detail_json': WorldviewDetails(
          trackedStateDefinitions: [_monitor('war_tension')],
        ).toJson(),
      },
    );
    final frozen = const AdventureTrackedStateFreezer().freeze(base);
    final binding =
        frozen.singleWhere((d) => d.definition.effectiveId == 'war_tension');
    expect(binding.entityType, RuntimeEntityType.world);
    expect(binding.entityId, AdventureRuntimeEntityIds.world);
  });

  test('P3: scope round-trips through the definition codec', () {
    const definition = TrackedStateDefinition(
      id: 'hp_custom',
      name: '生命值',
      scope: TrackedStateScope.characters,
    );
    final restored = TrackedStateDefinition.fromJson(definition.toJson());
    expect(restored.scope, TrackedStateScope.characters);
    // Absent scope defaults to inherit (backward compatible).
    expect(
      TrackedStateDefinition.fromJson(const {'id': 'x', 'name': 'X'}).scope,
      TrackedStateScope.inherit,
    );
  });

  test('P3: a general rule stores an independent value per character',
      () async {
    final config = generalRuleConfig(scope: TrackedStateScope.characters);
    final harness = _EngineHarness(config, repository);
    harness.participantIds = const ['alice', 'bob'];
    harness.adventureId = await repository.createAdventure('General', config);
    for (final id in ['alice', 'bob']) {
      await repository.seedRuntimeEntity(
        adventureId: harness.adventureId!,
        branchId: 0,
        entityType: RuntimeEntityType.character,
        entityId: id,
      );
    }
    final llm = _ScriptedLlm([
      '$_narrative\n---JSON---\n{"scene":"桥","options":["a","b","c"]}',
      _settlement(evaluations: const [
        {
          'entity_type': 'character',
          'entity_id': 'alice',
          'monitor_id': 'hp_custom',
          'status': 'changed',
          'operation': 'set',
          'value': 70,
          'reason': 'Alice 受伤',
        },
        {
          'entity_type': 'character',
          'entity_id': 'bob',
          'monitor_id': 'hp_custom',
          'status': 'unchanged',
          'reason': 'Bob 本轮未受伤',
        },
      ]),
    ]);
    final engine = harness.build(llm);
    addTearDown(engine.dispose);
    await engine.sendMessage('我们冲入战团。');

    final entities =
        await repository.getRuntimeEntities(harness.adventureId!, 0);
    final byId = {for (final e in entities) e.entityId: e};
    expect(byId['alice']!.overlay['custom_attributes.hp_custom'], 70);
    expect(byId['bob']!.overlay.containsKey('custom_attributes.hp_custom'),
        isFalse,
        reason: 'each character keeps an independent value');
  });

  test('P3: a custom monitor and the built-in hp stay independent', () async {
    final harness = await startEngine();
    final llm = _ScriptedLlm([
      '$_narrative\n---JSON---\n{"scene":"桥","options":["a","b","c"]}',
      _settlement(changes: const [
        {
          'entity_type': 'character',
          'entity_id': 'alice',
          'change_kind': 'primary',
          'operation': 'increment',
          'path': 'hp',
          'value': -20,
          'reason': '受伤',
        }
      ], evaluations: const [
        {
          'entity_type': 'character',
          'entity_id': 'alice',
          'monitor_id': 'hp_custom',
          'status': 'changed',
          'operation': 'set',
          'value': 88,
          'reason': '自定义生命值',
        }
      ]),
    ]);
    final engine = harness.build(llm);
    addTearDown(engine.dispose);
    await engine.sendMessage('我们冲入战团。');

    final alice = (await repository.getRuntimeEntities(harness.adventureId!, 0))
        .singleWhere((e) => e.entityId == 'alice');
    // Two distinct authorities, never synced to each other.
    expect(alice.overlay['hp'], 80);
    expect(alice.overlay['custom_attributes.hp_custom'], 88);
  });

  // ───────────────────────────────────────────────────────────────────────
  // P2 — mid-adventure definition add seeds the entity at once
  // ───────────────────────────────────────────────────────────────────────

  AdventureProvider buildProvider() => AdventureProvider(
        adventureRepo:
            AdventureRepositoryImpl(getDb: () => DatabaseService.database),
        worldEntryRepo:
            WorldEntryRepositoryImpl(getDb: () => DatabaseService.database),
        libraryRepo:
            LibraryRepositoryImpl(getDb: () => DatabaseService.database),
      );

  test('P2: adding a worldview definition mid-adventure seeds the world entity',
      () async {
    final noWorld = AdventureConfig(
      name: '旅人',
      selectedCharacters: [
        AdventureSelectedCharacter(
          id: 'alice',
          characterId: 'alice',
          characterName: 'Alice',
          isProtagonist: true,
        ),
      ],
    );
    final adventureId = await repository.createAdventure('Mid', noWorld);
    final provider = buildProvider();
    await provider.loadAdventure(adventureId);

    // Precondition: the world entity is not seeded (no worldview definition).
    var entities = await repository.getRuntimeEntities(adventureId, 0);
    expect(entities.where((e) => e.entityType == RuntimeEntityType.world),
        isEmpty);

    final updated = noWorld.copyWith(trackedStateDefinitions: [
      AdventureTrackedStateDefinition(
        entityType: RuntimeEntityType.world,
        entityId: AdventureRuntimeEntityIds.world,
        definition: _monitor('war_tension', name: '战争紧张度'),
      ),
    ]);
    final ok = await provider.applyTrackedStateEdit(updatedConfig: updated);
    expect(ok, isTrue);

    entities = await repository.getRuntimeEntities(adventureId, 0);
    expect(entities.where((e) => e.entityType == RuntimeEntityType.world),
        hasLength(1));

    // The very next settlement commit for the world entity is now accepted.
    final head = await repository.getRuntimeHead(adventureId, 0);
    await repository.commitRuntimeMutation(RuntimeStateMutation(
      requestId: 'mid-add-1',
      adventureId: adventureId,
      branchId: 0,
      draft: RuntimeStateCommitDraft(
        expectedRevision: head.revision,
        changes: const [
          RuntimeStateChangeProposal(
            entityType: RuntimeEntityType.world,
            entityId: AdventureRuntimeEntityIds.world,
            changeKind: RuntimeChangeKind.primary,
            operation: RuntimeChangeOperation.set,
            path: 'custom_attributes.war_tension',
            value: 40,
            reason: '战争升级',
          ),
        ],
        summary: 'mid-adventure world change',
      ),
    ));
    final world = (await repository.getRuntimeEntities(adventureId, 0))
        .singleWhere((e) => e.entityType == RuntimeEntityType.world);
    expect(world.overlay['custom_attributes.war_tension'], 40);
  });

  test('P2: re-saving is idempotent and preserves an existing overlay',
      () async {
    final config = _characterConfig();
    final adventureId = await repository.createAdventure('Idem', config);
    final provider = buildProvider();
    await provider.loadAdventure(adventureId);

    // Add a world definition mid-adventure; the world entity is seeded.
    final updated = config.copyWith(trackedStateDefinitions: [
      ...config.trackedStateDefinitions,
      AdventureTrackedStateDefinition(
        entityType: RuntimeEntityType.world,
        entityId: AdventureRuntimeEntityIds.world,
        definition: _monitor('war_tension', name: '战争紧张度'),
      ),
    ]);
    await provider.applyTrackedStateEdit(updatedConfig: updated);

    // Give the world entity a real overlay through the production commit path.
    final head = await repository.getRuntimeHead(adventureId, 0);
    await repository.commitRuntimeMutation(RuntimeStateMutation(
      requestId: 'seed-world',
      adventureId: adventureId,
      branchId: 0,
      draft: RuntimeStateCommitDraft(
        expectedRevision: head.revision,
        changes: const [
          RuntimeStateChangeProposal(
            entityType: RuntimeEntityType.world,
            entityId: AdventureRuntimeEntityIds.world,
            changeKind: RuntimeChangeKind.primary,
            operation: RuntimeChangeOperation.set,
            path: 'custom_attributes.war_tension',
            value: 55,
            reason: '初始化',
          ),
        ],
        summary: 'seed',
      ),
    ));

    // Re-save the same definitions: must be a no-op for entities and overlays.
    await provider.applyTrackedStateEdit(updatedConfig: updated);
    await provider.applyTrackedStateEdit(updatedConfig: updated);

    final worlds = (await repository.getRuntimeEntities(adventureId, 0))
        .where((e) => e.entityType == RuntimeEntityType.world)
        .toList();
    expect(worlds, hasLength(1), reason: 'seeding is idempotent');
    expect(worlds.single.overlay['custom_attributes.war_tension'], 55,
        reason: 'an existing overlay is never cleared');
  });

  test('P2: registry exposes the newly added world definition immediately',
      () async {
    final noWorld = AdventureConfig(
      name: '旅人',
      selectedCharacters: [
        AdventureSelectedCharacter(
          id: 'alice',
          characterId: 'alice',
          characterName: 'Alice',
          isProtagonist: true,
        ),
      ],
    );
    final adventureId = await repository.createAdventure('Reg', noWorld);
    final provider = buildProvider();
    await provider.loadAdventure(adventureId);

    final updated = noWorld.copyWith(trackedStateDefinitions: [
      AdventureTrackedStateDefinition(
        entityType: RuntimeEntityType.world,
        entityId: AdventureRuntimeEntityIds.world,
        definition: _monitor('war_tension', name: '战争紧张度'),
      ),
    ]);
    await provider.applyTrackedStateEdit(updatedConfig: updated);

    final registry =
        AdventureTrackedStateRegistry.fromConfig(provider.adventureConfig);
    expect(
      registry
          .forEntity(RuntimeEntityType.world, AdventureRuntimeEntityIds.world)
          .map((b) => b.definitionId),
      contains('war_tension'),
    );
  });
}
