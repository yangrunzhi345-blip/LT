import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/application/resources/legacy_resource_mapper.dart';
import 'package:lt_dialogue/domain/resources/character_relationship.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_revision.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_response.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/providers/chat_provider.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/character_relationship_repository.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:lt_dialogue/services/repositories/settings_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/world_entry_repository_impl.dart';

import '../helpers/phase10_fixture.dart';

/// Production-path regression: an Adventure launched from real managed
/// (unified-tree) resources must create, seed, persist and reopen through the
/// real providers and SQLite — including resource ids that are not ASCII
/// identifiers, which is what real character-card libraries contain.
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

void main() {
  late Phase10Fixture fixture;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    fixture = Phase10Fixture();
    await fixture.setUp(prefix: 'lt_start_managed_');
  });

  tearDown(() => fixture.tearDown());

  ChatProvider providerWith(Phase10Fixture f) => ChatProvider.withRepos(
        adventureRepo:
            AdventureRepositoryImpl(getDb: () => DatabaseService.database),
        worldEntryRepo:
            WorldEntryRepositoryImpl(getDb: () => DatabaseService.database),
        libraryRepo:
            LibraryRepositoryImpl(getDb: () => DatabaseService.database),
        settingsRepo:
            SettingsRepositoryImpl(getDb: () => DatabaseService.database),
        readinessGate: f.gate,
      );

  Future<int> start(
    ChatProvider chat,
    AdventureConfig config, {
    required String label,
  }) async {
    final id = await chat.startAdventureWithConfig(config);
    expect(id, greaterThan(0), reason: '$label: adventure id');
    await DatabaseService.resetDatabase();
    final repo = AdventureRepositoryImpl(getDb: () => DatabaseService.database);
    expect(await repo.getAdventureById(id), isNotNull,
        reason: '$label: adventure row persisted');
    final messages = await repo.getMessages(id);
    expect(messages, isNotEmpty, reason: '$label: opening persisted');
    final parsed = AdventureResponse.tryParseSplit(messages.first.content);
    expect(parsed, isNotNull, reason: '$label: opening parses');
    expect(parsed!.options, config.openingOptions, reason: '$label: options');
    return id;
  }

  test('managed worldview + character start persists and reopens', () async {
    final wv = await fixture.createWorldview(
      'res_wv_1',
      [
        ['艾尔德兰大陆，帝国与邻国长期对峙。'],
        ['魔法源于元素共鸣，使用需消耗精神。'],
      ],
      summary: '帝国与邻国对峙的大陆',
      confirmed: true,
      name: '艾尔德兰',
    );
    await fixture.coordinator.prepare(wv);
    await fixture.createCharacter('res_ch_1');
    await fixture.coordinator.prepare(const ResourceId('res_ch_1'));

    final config = AdventureConfig(
      name: '林澈',
      worldview: '艾尔德兰',
      openingScene: '林澈推开门，望向桌上的海图。',
      openingOptions: const ['查看海图', '询问船长', '整理行囊'],
      selectedCharacters: [
        AdventureSelectedCharacter(
          id: 'res_ch_1',
          characterId: 'res_ch_1',
          characterName: '林澈',
          isProtagonist: true,
          narrativeRole: AdventureCharacterRole.protagonist,
        ),
      ],
    );

    final chat = providerWith(fixture);
    await chat.loadApiKey();
    addTearDown(chat.dispose);
    chat.debugBootstrapLlmOverride = _FakeLlm('{"runtime_state_changes":[]}');

    await start(chat, config, label: 'managed basic');
    expect(chat.isAdventureChatOpen, isTrue);
  });

  test('managed world + 2 characters + attributes + relationship + npc',
      () async {
    final wv = await fixture.createWorldview(
      'res_wv_2',
      [
        ['艾尔德兰大陆，帝国与邻国长期对峙。'],
        ['魔法源于元素共鸣，使用需消耗精神。'],
      ],
      summary: '帝国与邻国对峙的大陆',
      confirmed: true,
      name: '艾尔德兰',
    );
    await fixture.coordinator.prepare(wv);

    Future<ResourceId> character(
      String id,
      String name, {
      required bool withAttributes,
    }) async {
      final resourceId = await fixture.treeRepository.createResourceTree(
        ResourceTreeDraft(
          id: ResourceId(id),
          type: ResourceType.character,
          name: name,
          summary: '$name 摘要',
          sections: [
            const ResourceTreeSectionDraft(
              title: LegacyResourceMapper.characterProfileSectionTitle,
              parts: [
                ResourceTreePartDraft(title: '性别', content: '未知'),
                ResourceTreePartDraft(title: '职业', content: '冒险者'),
              ],
            ),
            if (withAttributes)
              const ResourceTreeSectionDraft(
                title: LegacyResourceMapper.characterAttributesSectionTitle,
                parts: [
                  ResourceTreePartDraft(title: '心情', content: '平静'),
                  ResourceTreePartDraft(title: '体力', content: '80/100'),
                ],
              ),
            const ResourceTreeSectionDraft(
              title: '剧情',
              parts: [ResourceTreePartDraft(title: '开场白', content: '“来了。”')],
            ),
          ],
        ),
      );
      await fixture.revisionService
          .captureRevision(resourceId, cause: RevisionCause.manualSave);
      await fixture.coordinator.prepare(resourceId);
      return resourceId;
    }

    await character('res_ch_p', '林澈', withAttributes: true);
    await character('res_ch_c', '苏晚', withAttributes: true);

    final npcId = await fixture.treeRepository.createResourceTree(
      const ResourceTreeDraft(
        id: ResourceId('res_npc_1'),
        type: ResourceType.npc,
        name: '老船长',
        summary: '经验丰富的老水手',
        sections: [
          ResourceTreeSectionDraft(
            title: '剧情',
            parts: [ResourceTreePartDraft(title: '开场白', content: '“上船吧。”')],
          ),
        ],
      ),
    );
    await fixture.revisionService
        .captureRevision(npcId, cause: RevisionCause.manualSave);
    await fixture.coordinator.prepare(npcId);

    final relationships = CharacterRelationshipRepositoryImpl(
        getDb: () => DatabaseService.database);
    await relationships.create(
      firstResourceId: const ResourceId('res_ch_p'),
      firstRole: '同伴',
      secondResourceId: const ResourceId('res_ch_c'),
      secondRole: '同伴',
      relationType: CharacterRelationshipType.companion,
    );

    final config = AdventureConfig(
      name: '林澈',
      worldview: '艾尔德兰',
      openingScene: '林澈推开门，望向桌上的海图。',
      openingOptions: const ['查看海图', '询问船长', '整理行囊'],
      selectedCharacters: [
        AdventureSelectedCharacter(
          id: 'res_ch_p',
          characterId: 'res_ch_p',
          characterName: '林澈',
          isProtagonist: true,
          narrativeRole: AdventureCharacterRole.protagonist,
        ),
        AdventureSelectedCharacter(
          id: 'res_ch_c',
          characterId: 'res_ch_c',
          characterName: '苏晚',
          narrativeRole: AdventureCharacterRole.companion,
        ),
      ],
      npcSnapshots: [
        AdventureNpcSnapshot(
          assetId: 'res_npc_1',
          name: '老船长',
          npcJson: const {'name': '老船长'},
        ),
      ],
    );

    final chat = providerWith(fixture);
    await chat.loadApiKey();
    addTearDown(chat.dispose);
    chat.debugBootstrapLlmOverride = _FakeLlm('{"runtime_state_changes":[]}');

    await start(chat, config, label: 'managed rich');
  });

  test('name-based (non-ASCII) character resource id still starts and reopens',
      () async {
    // A character card imported through the character manager gets a resource
    // id of `<name>_<creator>`, which is non-ASCII for a typical CJK card. It
    // must remain usable as the adventure's stable runtime entity id.
    final wv = await fixture.createWorldview(
      'res_wv_3',
      [
        ['某大陆正文'],
      ],
      summary: '某大陆',
      confirmed: true,
      name: '某大陆',
    );
    await fixture.coordinator.prepare(wv);

    const charId = '林澈_某作者';
    await fixture.createCharacter(charId);
    await fixture.coordinator.prepare(const ResourceId(charId));

    final config = AdventureConfig(
      name: '林澈',
      worldview: '某大陆',
      openingScene: '林澈推开门，望向桌上的海图。',
      openingOptions: const ['查看海图', '询问船长'],
      selectedCharacters: [
        AdventureSelectedCharacter(
          id: charId,
          characterId: charId,
          characterName: '林澈',
          isProtagonist: true,
        ),
      ],
    );

    final chat = providerWith(fixture);
    await chat.loadApiKey();
    addTearDown(chat.dispose);
    chat.debugBootstrapLlmOverride = _FakeLlm('{"runtime_state_changes":[]}');

    final id = await start(chat, config, label: 'non-ascii id');
    await DatabaseService.resetDatabase();
    final repo = AdventureRepositoryImpl(getDb: () => DatabaseService.database);
    // The non-ASCII id was actually seeded as the runtime entity id.
    final entities = await repo.getRuntimeEntities(id, 0);
    expect(entities.any((entity) => entity.entityId == charId), isTrue);
  });
}
