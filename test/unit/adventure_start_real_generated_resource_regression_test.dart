import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/application/adventure/adventure_tracked_state_freezer.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_response.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/models/worldview_details.dart';
import 'package:lt_dialogue/models/tracked_state_definition.dart';
import 'package:lt_dialogue/models/typed_runtime_state.dart';
import 'package:lt_dialogue/providers/chat_provider.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/settings_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/world_entry_repository_impl.dart';

final class _FakeLlm extends LLMService {
  _FakeLlm(this.response)
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

ChatProvider _provider() => ChatProvider.withRepos(
      adventureRepo:
          AdventureRepositoryImpl(getDb: () => DatabaseService.database),
      worldEntryRepo:
          WorldEntryRepositoryImpl(getDb: () => DatabaseService.database),
      libraryRepo: LibraryRepositoryImpl(getDb: () => DatabaseService.database),
      settingsRepo:
          SettingsRepositoryImpl(getDb: () => DatabaseService.database),
    );

/// Realistic generated character card JSON, as produced by the resource studio
/// (SillyTavern v2 envelope + tracked definitions + custom attributes).
Map<String, dynamic> _generatedCharacterCard({
  required String name,
}) =>
    {
      'spec': 'chara_card_v2',
      'data': {
        'name': name,
        'description': '$name 的详细背景。',
        'personality': '冷静、缜密。',
        'scenario': '动荡的边境。',
        'first_mes': '“你终于来了。”',
        'mes_example': '<START>\n{{user}}: 你好\n{{char}}: 欢迎。',
        'creator_notes': '由生成器创建',
        'tags': ['奇幻', '政治'],
        'tracked_state_definitions': [
          {
            'id': 'resolve',
            'name': '决心',
            'value_kind': 'integer',
            'minimum': 0,
            'maximum': 100,
            'description': '面对压力时的意志',
            'importance': 'reference',
          },
          {
            'id': 'inner_voice',
            'name': '心声',
            'value_kind': 'text',
          },
        ],
        'custom_attributes': [
          {'id': 'mood', 'name': '心情', 'value': '', 'importance': 'reference'},
        ],
      },
    };

Map<String, dynamic> _generatedWorldviewSnapshot() {
  const details = WorldviewDetails(
    mode: WorldviewEditingMode.detailed,
    modules: {
      'overview': {
        'summary': '艾尔德兰大陆，帝国与邻国长期对峙。',
        'status': 'confirmed',
      },
      'world_rules': {
        'summary': '魔法源于元素共鸣，使用需消耗精神。',
        'status': 'confirmed',
      },
      'factions': [
        {'name': '银月骑士团', 'description': '帝国最精锐的骑士团。'},
      ],
    },
    trackedStateDefinitions: [
      TrackedStateDefinition(
        id: 'war_tension',
        name: '战争紧张度',
        valueKind: RuntimeStateValueKind.integer,
        minimum: 0,
        maximum: 100,
      ),
    ],
  );
  return {
    'source_id': 'res_cre_worldview',
    'name': '艾尔德兰',
    'description': '帝国与邻国对峙的大陆。',
    'format_version': WorldviewDetails.currentFormatVersion,
    'detail_json': details.toJson(),
    'content_hash': 'hash-worldview',
    'created_at': DateTime.now().toIso8601String(),
  };
}

AdventureConfig _realisticConfig({
  String openingScene = '林澈推开门，望向桌上的海图。',
  List<String> openingOptions = const ['查看海图', '询问船长', '整理行囊'],
  bool withNpc = false,
  bool withRelationship = false,
}) {
  final protagonist = AdventureSelectedCharacter(
    id: 'res_cre_protagonist',
    characterId: 'res_cre_protagonist',
    characterName: '林澈',
    isProtagonist: true,
    narrativeRole: AdventureCharacterRole.protagonist,
    sortOrder: 0,
    characterCardJson: _generatedCharacterCard(name: '林澈'),
  );
  final companion = AdventureSelectedCharacter(
    id: 'res_cre_companion',
    characterId: 'res_cre_companion',
    characterName: '苏晚',
    isProtagonist: false,
    narrativeRole: AdventureCharacterRole.companion,
    sortOrder: 1,
    characterCardJson: _generatedCharacterCard(name: '苏晚'),
  );
  final base = AdventureConfig(
    name: '林澈',
    worldview: '艾尔德兰',
    worldviewSnapshot: _generatedWorldviewSnapshot(),
    protagonistClass: '航海士',
    protagonistBackground: '出身港口，熟悉每一片暗礁。',
    openingScene: openingScene,
    openingOptions: openingOptions,
    selectedCharacters: [protagonist, companion],
    characterRelationships: withRelationship
        ? [
            AdventureCharacterRelationship(
              id: 'rel_res_cre_protagonist__res_cre_companion',
              sourceCharacterId: 'res_cre_protagonist',
              targetCharacterId: 'res_cre_companion',
              relationType: AdventureRelationType.companion,
              sourceRole: 'protagonist',
              targetRole: 'companion',
              description: '同伴',
            ),
          ]
        : const [],
    npcSnapshots: withNpc
        ? [
            AdventureNpcSnapshot(
              assetId: 'res_cre_npc_1',
              name: '老船长',
              npcJson: const {
                'name': '老船长',
                'description': '经验丰富的老水手。',
                'tracked_state_definitions': [
                  {'id': 'trust', 'name': '信任', 'value_kind': 'integer'},
                ],
              },
            ),
          ]
        : const [],
  );
  return base.copyWith(
    trackedStateDefinitions: const AdventureTrackedStateFreezer().freeze(base),
  );
}

const _bootstrapResponse = '{"runtime_state_changes":[]}';

void main() {
  late Directory tempDir;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tempDir = await Directory.systemTemp.createTemp('lt_start_real_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    await DatabaseService.database;
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> runCase(String label, AdventureConfig config) async {
    final chat = _provider();
    await chat.loadApiKey();
    addTearDown(chat.dispose);
    chat.debugBootstrapLlmOverride = _FakeLlm(_bootstrapResponse);

    final id = await chat.startAdventureWithConfig(config);
    expect(id, greaterThan(0), reason: '$label: adventure id');

    await DatabaseService.resetDatabase();
    final repo = AdventureRepositoryImpl(getDb: () => DatabaseService.database);
    final adventure = await repo.getAdventureById(id);
    expect(adventure, isNotNull, reason: '$label: persisted adventure');
    final messages = await repo.getMessages(id);
    expect(messages, isNotEmpty, reason: '$label: opening message');
    final opening = messages.first;
    expect(
      AdventureResponse.tryParseSplit(opening.content),
      isNotNull,
      reason: '$label: opening parses',
    );
    final parsed = AdventureResponse.tryParseSplit(opening.content)!;
    expect(parsed.options, config.openingOptions, reason: '$label: options');
  }

  test('Case A: worldview + protagonist + opening persists through reopen',
      () async {
    await runCase('A', _realisticConfig());
  });

  test('Case B: protagonist + supporting companion', () async {
    await runCase('B', _realisticConfig());
  });

  test('Case C: generated card with tracked_state_definitions', () async {
    await runCase('C', _realisticConfig());
  });

  test('Case E: character relationships', () async {
    await runCase('E', _realisticConfig(withRelationship: true));
  });

  test('Case F: NPC snapshot + relationship + worldview', () async {
    await runCase('F', _realisticConfig(withNpc: true, withRelationship: true));
  });

  test('Case G: opening prose contains JSON-like text', () async {
    await runCase(
      'G',
      _realisticConfig(
        openingScene: '他翻开泛黄的手札，上面写着 {"note": "北礁危险"} 与 [坐标: 07,12]，'
            '海风掀动纸页。\n\n“记下来。”他说。',
      ),
    );
  });
}
