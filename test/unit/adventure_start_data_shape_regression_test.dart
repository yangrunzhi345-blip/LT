import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/application/adventure/adventure_tracked_state_freezer.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_response.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/providers/chat_provider.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/settings_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/world_entry_repository_impl.dart';

/// Regression for start-path data shapes that previously aborted Adventure
/// creation after its row was already inserted (leaving a partial adventure):
/// non-ASCII entity ids and a legacy `detail_json` stored as text.
final class _FakeLlm extends LLMService {
  _FakeLlm()
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
    onChunk('{"runtime_state_changes":[]}');
    onDone();
    return const LLMStreamResult(
      content: '{"runtime_state_changes":[]}',
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

AdventureConfig _config({
  List<AdventureSelectedCharacter>? selected,
  List<AdventureCharacterRelationship>? relationships,
  List<AdventureNpcSnapshot>? npcs,
  Map<String, dynamic>? worldviewSnapshot,
}) {
  final base = AdventureConfig(
    name: '林澈',
    worldview: '艾尔德兰',
    worldviewSnapshot: worldviewSnapshot ??
        {
          'source_id': 'wv_1',
          'name': '艾尔德兰',
          'description': '对峙的大陆',
          'detail_json': {
            'format_version': 2,
            'mode': 'detailed',
            'modules': {}
          },
        },
    openingScene: '林澈推开门。',
    openingOptions: const ['查看海图', '询问船长'],
    selectedCharacters: selected ??
        [
          AdventureSelectedCharacter(
            id: 'p1',
            characterId: 'p1',
            characterName: '林澈',
            isProtagonist: true,
            narrativeRole: AdventureCharacterRole.protagonist,
          ),
        ],
    characterRelationships: relationships ?? const [],
    npcSnapshots: npcs ?? const [],
  );
  return base.copyWith(
      trackedStateDefinitions:
          const AdventureTrackedStateFreezer().freeze(base));
}

void main() {
  late Directory tempDir;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tempDir = await Directory.systemTemp.createTemp('lt_start_shapes_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    await DatabaseService.database;
  });
  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> expectStartOk(String label, AdventureConfig config) async {
    final chat = _provider();
    await chat.loadApiKey();
    addTearDown(chat.dispose);
    chat.debugBootstrapLlmOverride = _FakeLlm();

    final id = await chat.startAdventureWithConfig(config);
    expect(id, greaterThan(0), reason: '$label: id');

    await DatabaseService.resetDatabase();
    final repo = AdventureRepositoryImpl(getDb: () => DatabaseService.database);
    expect(await repo.getAdventureById(id), isNotNull,
        reason: '$label: adventure persisted');
    final messages = await repo.getMessages(id);
    expect(messages, isNotEmpty, reason: '$label: opening persisted');
    expect(AdventureResponse.tryParseSplit(messages.first.content), isNotNull,
        reason: '$label: opening parses');
  }

  test('non-ASCII character entity id seeds and starts', () async {
    await expectStartOk(
      'chinese id',
      _config(selected: [
        AdventureSelectedCharacter(
          id: '林澈',
          characterId: '林澈',
          characterName: '林澈',
          isProtagonist: true,
        ),
      ]),
    );
  });

  test('name-based id with spaces and slashes seeds and starts', () async {
    await expectStartOk(
      'spaced/slashed id',
      _config(selected: [
        AdventureSelectedCharacter(
          id: '作者 / 林澈 01',
          characterId: '作者 / 林澈 01',
          characterName: '林澈',
          isProtagonist: true,
        ),
      ]),
    );
  });

  test('non-ASCII relationship id seeds and starts', () async {
    await expectStartOk(
      'relationship id',
      _config(
        selected: [
          AdventureSelectedCharacter(
              id: 'p1',
              characterId: 'p1',
              characterName: '林澈',
              isProtagonist: true),
          AdventureSelectedCharacter(
              id: 's1', characterId: 's1', characterName: '苏晚'),
        ],
        relationships: [
          AdventureCharacterRelationship(
            id: '同伴关系',
            sourceCharacterId: 'p1',
            targetCharacterId: 's1',
            relationType: AdventureRelationType.companion,
          ),
        ],
      ),
    );
  });

  test('legacy text detail_json does not abort the start', () async {
    await expectStartOk(
      'text detail_json',
      _config(worldviewSnapshot: {
        'source_id': 'wv_1',
        'name': '艾尔德兰',
        'description': '对峙的大陆',
        'detail_json': '{"format_version":2,"modules":{}}',
      }),
    );
  });

  test('empty character id falls back without aborting the start', () async {
    await expectStartOk(
      'empty id',
      _config(selected: [
        AdventureSelectedCharacter(
          id: '',
          characterId: '',
          characterName: '林澈',
          isProtagonist: true,
        ),
      ]),
    );
  });
}
