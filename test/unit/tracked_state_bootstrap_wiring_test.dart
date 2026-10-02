import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/application/adventure/adventure_tracked_state_freezer.dart';
import 'package:lt_dialogue/application/adventure/tracked_state_bootstrap_runner.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/models/scene_state.dart';
import 'package:lt_dialogue/models/tracked_state_definition.dart';
import 'package:lt_dialogue/models/typed_runtime_state.dart';
import 'package:lt_dialogue/models/worldview_details.dart';
import 'package:lt_dialogue/providers/chat_provider.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/settings_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/world_entry_repository_impl.dart';

final class _FakeLlm extends LLMService {
  _FakeLlm(this.response, {this.failure})
      : super(const LLMConfig(
          provider: LLMProvider.deepseek,
          apiKey: 'test-key',
          baseUrl: 'https://example.invalid',
          model: 'deepseek-flash',
        ));

  final String response;
  final Object? failure;
  int calls = 0;

  @override
  Future<LLMStreamResult> sendMessageStreamDetailed(
    List<Map<String, String>> messages,
    void Function(String chunk) onChunk,
    void Function() onDone, {
    void Function(String reasoningChunk)? onReasoningChunk,
    CompletionParams params = const CompletionParams(),
    GenerationTaskHandle? taskHandle,
  }) async {
    calls++;
    if (failure != null) throw failure!;
    onChunk(response);
    onDone();
    return LLMStreamResult(
      content: response,
      finishReason: LLMFinishReason.stop,
      responseCompleted: true,
    );
  }
}

const _warDefinition = TrackedStateDefinition(
  id: 'war_tension',
  name: '战争紧张度',
  valueKind: RuntimeStateValueKind.integer,
  minimum: 0,
  maximum: 100,
);

AdventureConfig _worldConfig({
  String openingScene = '帝国在北境正式向邻国宣战，两军已经在边境交火。',
}) {
  final base = AdventureConfig(
    name: 'Alice',
    openingScene: openingScene,
    openingOptions: const ['迎战', '交涉', '撤退'],
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
      'detail_json': const WorldviewDetails(
        trackedStateDefinitions: [_warDefinition],
      ).toJson(),
    },
  );
  return base.copyWith(
    trackedStateDefinitions: const AdventureTrackedStateFreezer().freeze(base),
  );
}

const _worldResponse =
    '{"runtime_state_changes":[{"entity_type":"world","entity_id":"world",'
    '"change_kind":"primary","operation":"set",'
    '"path":"custom_attributes.war_tension","value":65,'
    '"reason":"开场宣战"}]}';

ChatProvider _provider() => ChatProvider.withRepos(
      adventureRepo:
          AdventureRepositoryImpl(getDb: () => DatabaseService.database),
      worldEntryRepo:
          WorldEntryRepositoryImpl(getDb: () => DatabaseService.database),
      libraryRepo: LibraryRepositoryImpl(getDb: () => DatabaseService.database),
      settingsRepo:
          SettingsRepositoryImpl(getDb: () => DatabaseService.database),
    );

void main() {
  late Directory tempDir;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tempDir = await Directory.systemTemp.createTemp('lt_bootstrap_wiring_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    await DatabaseService.database;
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test(
      'A: opening evidence initializes world state, refreshes cache, keeps chat clean',
      () async {
    final chat = _provider();
    await chat.loadApiKey();
    final llm = _FakeLlm(_worldResponse);
    chat.debugBootstrapLlmOverride = llm;

    final id = await chat.startAdventureWithConfig(_worldConfig());
    final repo = AdventureRepositoryImpl(getDb: () => DatabaseService.database);

    expect(llm.calls, 1);
    final world = (await repo.getRuntimeEntities(id, 0))
        .singleWhere((e) => e.entityType == RuntimeEntityType.world);
    expect(world.overlay['custom_attributes.war_tension'], 65);
    expect((await repo.getRuntimeHead(id, 0)).revision, 1);

    final timeline =
        await repo.getRuntimeTimeline(adventureId: id, branchId: 0);
    expect(timeline.single.causeType, 'opening_bootstrap');

    // Cache refresh: the value is visible without reopening the adventure.
    final cached = chat.adventureProvider.runtimeEntities
        .where((e) => e.entityType == RuntimeEntityType.world);
    expect(cached.single.overlay['custom_attributes.war_tension'], 65);

    // Chat isolation: only the seeded opening message, no bootstrap JSON.
    expect(chat.messages, hasLength(1));
    expect(chat.messages.single.content.contains('runtime_state_changes'),
        isFalse);
  });

  test('B: opening without evidence commits nothing', () async {
    final chat = _provider();
    await chat.loadApiKey();
    final llm = _FakeLlm('{"runtime_state_changes":[]}');
    chat.debugBootstrapLlmOverride = llm;

    final id = await chat.startAdventureWithConfig(_worldConfig());
    final repo = AdventureRepositoryImpl(getDb: () => DatabaseService.database);

    expect(llm.calls, 1);
    expect((await repo.getRuntimeHead(id, 0)).revision, 0);
    final world = (await repo.getRuntimeEntities(id, 0))
        .singleWhere((e) => e.entityType == RuntimeEntityType.world);
    expect(world.overlay.containsKey('custom_attributes.war_tension'), isFalse);
  });

  test('C: bootstrap network failure never fails the adventure', () async {
    final chat = _provider();
    await chat.loadApiKey();
    final llm = _FakeLlm('', failure: const SocketException('offline'));
    chat.debugBootstrapLlmOverride = llm;

    final id = await chat.startAdventureWithConfig(_worldConfig());
    final repo = AdventureRepositoryImpl(getDb: () => DatabaseService.database);

    expect(id, greaterThan(0));
    expect(chat.isAdventureChatOpen, isTrue);
    expect((await repo.getRuntimeHead(id, 0)).revision, 0);
    expect(chat.messages.where((m) => m.errorType != null), isEmpty);
  });

  test('D: no definitions means no bootstrap request', () async {
    final chat = _provider();
    await chat.loadApiKey();
    final llm = _FakeLlm(_worldResponse);
    chat.debugBootstrapLlmOverride = llm;

    final config = AdventureConfig(
      name: 'Alice',
      openingScene: '平静的一天。',
      selectedCharacters: [
        AdventureSelectedCharacter(
          id: 'alice',
          characterId: 'alice',
          characterName: 'Alice',
          isProtagonist: true,
        ),
      ],
    );
    await chat.startAdventureWithConfig(config);

    expect(llm.calls, 0);
  });

  test('E: definitions without an opening scene make no request', () async {
    final chat = _provider();
    await chat.loadApiKey();
    final llm = _FakeLlm(_worldResponse);
    chat.debugBootstrapLlmOverride = llm;

    await chat.startAdventureWithConfig(_worldConfig(openingScene: ''));

    expect(llm.calls, 0);
  });

  group('runner contract', () {
    test('F: same adventure/branch bootstraps at most once', () async {
      final repo =
          AdventureRepositoryImpl(getDb: () => DatabaseService.database);
      final config = _worldConfig();
      final id = await repo.createAdventure('Idempotent', config);
      await repo.seedRuntimeEntity(
        adventureId: id,
        branchId: 0,
        entityType: RuntimeEntityType.world,
        entityId: 'world',
      );
      final llm = _FakeLlm(_worldResponse);
      final runner =
          TrackedStateBootstrapRunner(repository: repo, llmService: llm);

      final first = await runner.run(
        adventureId: id,
        branchId: 0,
        config: config,
        sceneState: const SceneState(presentCharacterIds: ['protagonist']),
        runtimeEntities: const [],
      );
      final second = await runner.run(
        adventureId: id,
        branchId: 0,
        config: config,
        sceneState: const SceneState(presentCharacterIds: ['protagonist']),
        runtimeEntities: const [],
      );

      expect(first.committedCount, 1);
      expect((await repo.getRuntimeHead(id, 0)).revision, 1);
      expect(second.revisionAfter, 1);
      final timeline =
          await repo.getRuntimeTimeline(adventureId: id, branchId: 0);
      expect(timeline, hasLength(1));
      expect(timeline.single.causeType, 'opening_bootstrap');
    });

    test('G: world + character produce one commit with two diffs', () async {
      final repo =
          AdventureRepositoryImpl(getDb: () => DatabaseService.database);
      AdventureConfig build() {
        final base = AdventureConfig(
          name: 'Alice',
          openingScene: 'Alice 触碰了深渊遗物，同时边境正式宣战。',
          selectedCharacters: [
            AdventureSelectedCharacter(
              id: 'alice',
              characterId: 'alice',
              characterName: 'Alice',
              isProtagonist: true,
              characterCardJson: const {
                'name': 'Alice',
                'tracked_state_definitions': [
                  {
                    'id': 'curse',
                    'name': '诅咒侵蚀',
                    'value_kind': 'integer',
                    'minimum': 0,
                    'maximum': 100,
                  },
                ],
              },
            ),
          ],
          worldviewSnapshot: {
            'source_id': 'w1',
            'detail_json': const WorldviewDetails(
              trackedStateDefinitions: [_warDefinition],
            ).toJson(),
          },
        );
        return base;
      }

      final config = build();
      // Freeze through the production freezer so the config is authoritative.
      final frozen = config.copyWith(
        trackedStateDefinitions:
            const AdventureTrackedStateFreezer().freeze(config),
      );
      final id = await repo.createAdventure('Dual', frozen);
      await repo.seedRuntimeEntity(
        adventureId: id,
        branchId: 0,
        entityType: RuntimeEntityType.world,
        entityId: 'world',
      );
      const response =
          '{"runtime_state_changes":[{"entity_type":"world","entity_id":"world",'
          '"change_kind":"primary","operation":"set",'
          '"path":"custom_attributes.war_tension","value":70,"reason":"宣战"},'
          '{"entity_type":"character","entity_id":"alice","change_kind":"primary",'
          '"operation":"set","path":"custom_attributes.curse","value":12,'
          '"reason":"触碰遗物"}]}';
      final runner = TrackedStateBootstrapRunner(
          repository: repo, llmService: _FakeLlm(response));

      final result = await runner.run(
        adventureId: id,
        branchId: 0,
        config: frozen,
        sceneState: const SceneState(presentCharacterIds: ['protagonist']),
        runtimeEntities: const [],
        entityNames: const {'world': '艾尔德兰', 'alice': 'Alice'},
      );

      expect(result.committedCount, 2);
      expect((await repo.getRuntimeHead(id, 0)).revision, 1);
      final timeline =
          await repo.getRuntimeTimeline(adventureId: id, branchId: 0);
      expect(timeline.single.diffs, hasLength(2));
    });

    test('H: selected-only companion follows the real presence contract',
        () async {
      final repo =
          AdventureRepositoryImpl(getDb: () => DatabaseService.database);
      final base = AdventureConfig(
        name: 'Alice',
        openingScene: 'Bob 独自面对怪物。',
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
                  'maximum': 100,
                },
              ],
            },
          ),
        ],
      );
      final config = base.copyWith(
        trackedStateDefinitions:
            const AdventureTrackedStateFreezer().freeze(base),
      );
      final id = await repo.createAdventure('SelectedOnly', config);
      const response = '{"runtime_state_changes":[{"entity_type":"character",'
          '"entity_id":"bob","change_kind":"primary","operation":"set",'
          '"path":"custom_attributes.fear","value":40,"reason":"面对怪物"}]}';
      final runner = TrackedStateBootstrapRunner(
          repository: repo, llmService: _FakeLlm(response));

      // Bob is NOT in the scene presence authority: bootstrap must not invent
      // presence for him, and there is nothing else to initialize.
      final absent = await runner.run(
        adventureId: id,
        branchId: 0,
        config: config,
        sceneState: const SceneState(presentCharacterIds: ['protagonist']),
        runtimeEntities: const [],
      );
      expect(absent.status, TrackedStateBootstrapStatus.skipped);
      expect(absent.reason, 'no_candidates');

      // When the scene presence does include Bob, he is bootstrapped exactly
      // like any other character.
      final present = await runner.run(
        adventureId: id,
        branchId: 0,
        config: config,
        sceneState:
            const SceneState(presentCharacterIds: ['protagonist', 'bob']),
        runtimeEntities: const [],
      );
      expect(present.committedCount, 1);
      final bob = (await repo.getRuntimeEntities(id, 0))
          .singleWhere((e) => e.entityId == 'bob');
      expect(bob.overlay['custom_attributes.fear'], 40);
    });
  });
}
