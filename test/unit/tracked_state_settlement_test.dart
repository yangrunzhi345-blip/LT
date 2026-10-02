import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/adventure/adventure_tracked_state_freezer.dart';
import 'package:lt_dialogue/engines/chat_engine.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/models/dialogue_level.dart';
import 'package:lt_dialogue/models/game_state.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/models/tracked_state_definition.dart';
import 'package:lt_dialogue/models/typed_runtime_state.dart';
import 'package:lt_dialogue/models/worldview_details.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/chat_engine_host_fixture.dart';

const _narrative = '艾琳在石桥边停下脚步，确认远处的追兵已经失去踪迹。'
    '夜风掠过河面，火把的倒影随着水波摇曳。你们决定暂时在桥边休整。';

final class _ScriptedLlm extends LLMService {
  _ScriptedLlm(this.response)
      : super(const LLMConfig(
          provider: LLMProvider.deepseek,
          apiKey: 'test-key',
          baseUrl: 'https://example.invalid',
          model: 'deepseek-flash',
        ));

  final String response;

  @override
  Future<LLMStreamResult> sendMessageStreamDetailed(
    List<Map<String, String>> messages,
    void Function(String chunk) onChunk,
    void Function() onDone, {
    void Function(String reasoningChunk)? onReasoningChunk,
    CompletionParams params = const CompletionParams(),
    GenerationTaskHandle? taskHandle,
  }) async {
    onChunk(response);
    onDone();
    return LLMStreamResult(
      content: response,
      finishReason: LLMFinishReason.stop,
      responseCompleted: true,
    );
  }
}

AdventureConfig _config() {
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
        characterCardJson: const {
          'name': 'Bob',
          'tracked_state_definitions': [
            {
              'id': 'fear',
              'name': '恐惧程度',
              'value_kind': 'integer',
              'minimum': 0,
              'maximum': 100
            },
          ],
        },
      ),
    ],
    npcSnapshots: [
      AdventureNpcSnapshot(
        assetId: 'guard',
        name: '守门人',
        npcJson: const {
          'name': '守门人',
          'tracked_state_definitions': [
            {
              'id': 'alertness',
              'name': '警戒程度',
              'value_kind': 'integer',
              'minimum': 0,
              'maximum': 100
            },
          ],
        },
      ),
    ],
    worldviewSnapshot: {
      'source_id': 'w1',
      'name': '艾尔德兰',
      'detail_json': const WorldviewDetails(
        trackedStateDefinitions: [
          TrackedStateDefinition(
              id: 'war_tension',
              name: '战争紧张度',
              valueKind: RuntimeStateValueKind.integer,
              minimum: 0,
              maximum: 100),
        ],
      ).toJson(),
    },
  );
  return base.copyWith(
    trackedStateDefinitions: const AdventureTrackedStateFreezer().freeze(base),
  );
}

ChatEngine _engine(
  IAdventureRepository repository,
  AdventureConfig config,
  int adventureId,
  String response,
) {
  final llm = _ScriptedLlm(response);
  final messages = <Message>[];
  var gameState = GameState();
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
    ),
    notifyParent: () {},
    adventureRepo: repository,
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;
  late IAdventureRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_tracked_settlement_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    repository = AdventureRepositoryImpl(getDb: () => DatabaseService.database);
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('sparse settlement updates companion, NPC and world in one commit',
      () async {
    final config = _config();
    final adventureId = await repository.createAdventure('Tracked', config);
    // Non-character entities need a seeded runtime row before they may be
    // mutated (the production creation path seeds them too).
    await repository.seedRuntimeEntity(
      adventureId: adventureId,
      branchId: 0,
      entityType: RuntimeEntityType.npc,
      entityId: 'guard',
    );
    await repository.seedRuntimeEntity(
      adventureId: adventureId,
      branchId: 0,
      entityType: RuntimeEntityType.world,
      entityId: 'world',
    );

    const response = '$_narrative\n---JSON---\n'
        '{"scene":"石桥","options":["继续前进","检查装备","观察河面"],'
        '"runtime_state_changes":['
        '{"entity_type":"character","entity_id":"bob","change_kind":"primary",'
        '"operation":"set","path":"custom_attributes.fear","value":30,'
        '"reason":"Bob 独自面对怪物"},'
        '{"entity_type":"npc","entity_id":"guard","change_kind":"primary",'
        '"operation":"increment","path":"custom_attributes.alertness","value":10,'
        '"reason":"玩家试图翻墙"},'
        '{"entity_type":"world","entity_id":"world","change_kind":"primary",'
        '"operation":"set","path":"custom_attributes.war_tension","value":65,'
        '"reason":"帝国正式宣战"}]}';

    final engine = _engine(repository, config, adventureId, response);
    addTearDown(engine.dispose);
    await engine.sendMessage('我让 Bob 殿后，同时试图翻过大门。');

    final entities = {
      for (final entity in await repository.getRuntimeEntities(adventureId, 0))
        '${entity.entityType.name}:${entity.entityId}': entity,
    };
    expect(entities['character:bob']!.overlay['custom_attributes.fear'], 30);
    expect(entities['npc:guard']!.overlay['custom_attributes.alertness'], 10);
    expect(
        entities['world:world']!.overlay['custom_attributes.war_tension'], 65);
    // A single atomic commit for the whole turn.
    expect((await repository.getRuntimeHead(adventureId, 0)).revision, 1);

    final timeline = await repository.getRuntimeTimeline(
      adventureId: adventureId,
      branchId: 0,
    );
    expect(timeline.single.diffs, hasLength(3));
  });

  test('a turn that touches nothing produces no runtime commit', () async {
    final config = _config();
    final adventureId = await repository.createAdventure('Tracked', config);
    await repository.seedRuntimeEntity(
      adventureId: adventureId,
      branchId: 0,
      entityType: RuntimeEntityType.npc,
      entityId: 'guard',
    );
    await repository.seedRuntimeEntity(
      adventureId: adventureId,
      branchId: 0,
      entityType: RuntimeEntityType.world,
      entityId: 'world',
    );

    const response = '$_narrative\n---JSON---\n'
        '{"scene":"石桥","options":["继续前进","检查装备","观察河面"],'
        '"runtime_state_changes":[]}';

    final engine = _engine(repository, config, adventureId, response);
    addTearDown(engine.dispose);
    await engine.sendMessage('我们安静地坐着休息。');

    final entities = await repository.getRuntimeEntities(adventureId, 0);
    expect(entities.every((e) => e.overlay.isEmpty), isTrue);
    expect((await repository.getRuntimeHead(adventureId, 0)).revision, 0);
  });

  test('the model cannot invent a monitor that the registry never declared',
      () async {
    final config = _config();
    final adventureId = await repository.createAdventure('Tracked', config);

    const response = '$_narrative\n---JSON---\n'
        '{"scene":"石桥","options":["继续前进","检查装备","观察河面"],'
        '"runtime_state_changes":['
        '{"entity_type":"character","entity_id":"bob","change_kind":"primary",'
        '"operation":"set","path":"custom_attributes.random_mood","value":10,'
        '"reason":"模型自造状态"}]}';

    final engine = _engine(repository, config, adventureId, response);
    addTearDown(engine.dispose);
    await engine.sendMessage('Bob 心情似乎不错。');

    expect(await repository.getRuntimeEntities(adventureId, 0), isEmpty);
    expect((await repository.getRuntimeHead(adventureId, 0)).revision, 0);
  });

  test('a numeric increment is clamped to the definition range', () async {
    final config = _config();
    final adventureId = await repository.createAdventure('Tracked', config);
    await repository.seedRuntimeEntity(
      adventureId: adventureId,
      branchId: 0,
      entityType: RuntimeEntityType.world,
      entityId: 'world',
    );

    const response = '$_narrative\n---JSON---\n'
        '{"scene":"石桥","options":["继续前进","检查装备","观察河面"],'
        '"runtime_state_changes":['
        '{"entity_type":"world","entity_id":"world","change_kind":"primary",'
        '"operation":"increment","path":"custom_attributes.war_tension",'
        '"value":999,"reason":"远超范围"}]}';

    final engine = _engine(repository, config, adventureId, response);
    addTearDown(engine.dispose);
    await engine.sendMessage('战争全面爆发。');

    final world = (await repository.getRuntimeEntities(adventureId, 0))
        .singleWhere((e) => e.entityType == RuntimeEntityType.world);
    expect(world.overlay['custom_attributes.war_tension'], 100);
  });

  test('runtime change is not written back into the resource definition',
      () async {
    final config = _config();
    final adventureId = await repository.createAdventure('Tracked', config);
    const response = '$_narrative\n---JSON---\n'
        '{"scene":"石桥","options":["继续前进","检查装备","观察河面"],'
        '"runtime_state_changes":['
        '{"entity_type":"character","entity_id":"bob","change_kind":"primary",'
        '"operation":"set","path":"custom_attributes.fear","value":30,'
        '"reason":"Bob 独自面对怪物"}]}';

    final engine = _engine(repository, config, adventureId, response);
    addTearDown(engine.dispose);
    await engine.sendMessage('Bob 独自冲向前方。');

    final stored = await repository.getAdventureById(adventureId);
    final frozen = AdventureConfig.fromJson(
      jsonDecode(stored!['config'] as String) as Map<String, dynamic>,
    );
    final bobDefinition = frozen.trackedStateDefinitions
        .firstWhere((d) => d.entityId == 'bob')
        .definition;
    // The definition is unchanged: no current value ever lands on it.
    expect(bobDefinition.toJson().containsKey('value'), isFalse);
    expect(bobDefinition.toJson().containsKey('current_value'), isFalse);
  });
}
