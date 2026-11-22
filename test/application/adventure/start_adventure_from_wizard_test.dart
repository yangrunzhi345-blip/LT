import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/application/adventure/adventure_readiness_gate.dart';
import 'package:lt_dialogue/application/adventure/adventure_setup_use_case.dart';
import 'package:lt_dialogue/application/resources/resource_readiness_contracts.dart';
import 'package:lt_dialogue/controllers/adventure_setup_controller.dart';
import 'package:lt_dialogue/controllers/resource_crud_controller.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/setting_cards/setting_card.dart';
import 'package:lt_dialogue/features/adventure/application/use_cases/start_adventure_from_wizard.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/services/repositories/library_repository.dart';

import '../../helpers/setting_card_fakes.dart';

final class _EmptyLibrary implements ILibraryRepository {
  @override
  Future<List<Map<String, dynamic>>> getCharacterCards({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async =>
      const <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> getNpcCards({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async =>
      const <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> getWorldviewPresets({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async =>
      const <Map<String, dynamic>>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

final class _RecordingCrud extends ResourceCrudController {
  _RecordingCrud() : super(repository: _EmptyLibrary());

  int worldviewSaves = 0;
  int characterSaves = 0;

  @override
  Future<ResourceOperationResult> saveWorldviewPreset({
    required String id,
    required String name,
    required String description,
    required String entriesJson,
    required String now,
    String source = '',
    String contentHash = '',
    String detailJson = '{}',
    bool validate = true,
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
    String authoringMethod = 'manual',
    String aiGenerationDepth = '',
    String matchingWorldviewId = '',
  }) async {
    worldviewSaves++;
    return const ResourceOperationResult.success();
  }

  @override
  Future<ResourceOperationResult> saveCharacterCard({
    required String id,
    required String name,
    required String jsonData,
    required String source,
    required String now,
    String matchingWorldviewId = '',
    String weight = '',
    String contentHash = '',
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
    String authoringMethod = 'manual',
    String aiGenerationDepth = '',
  }) async {
    characterSaves++;
    return const ResourceOperationResult.success();
  }
}

final class _FakeSetup extends AdventureSetupController {
  _FakeSetup() : super(useCase: AdventureSetupUseCase(_EmptyLibrary()));

  @override
  Future<void> loadInitialData() async {}

  @override
  Map<String, dynamic>? buildWorldviewSnapshot({
    required String id,
    required String worldview,
  }) =>
      <String, dynamic>{'source_id': id, 'name': worldview};
}

final class _ReadyGate implements IAdventureReadinessGate {
  @override
  Future<AssemblyPrepareOutcome> prepare(String assetId) async =>
      AssemblyPrepareOutcome(
        record: AssemblyReadinessRecord(
          resourceId: assetId,
          state: ReadinessState.ready,
        ),
      );

  @override
  Future<Map<String, AdventureAssetReadiness>> resolve(
    Iterable<String> assetIds,
  ) async =>
      <String, AdventureAssetReadiness>{
        for (final id in assetIds)
          id: AdventureAssetReadiness(
            assetId: id,
            status: AdventureAssetGateStatus.ready,
            issueCode: AdventureReadinessIssueCode.ready,
          ),
      };

  @override
  Future<Map<String, AdventureAssetReadiness>> resolveConfig(
    AdventureConfig config,
  ) =>
      resolve(const <String>['sc_w']);

  @override
  Future<AdventureConfig> enforceAndFreeze(AdventureConfig config) async =>
      config;
}

SettingCard _card(String id, SettingCardKind kind) => SettingCard(
      id: id,
      kind: kind,
      name: '旧名',
      summary: '旧摘要',
      content: '正文',
      createdAt: '2026-01-01T00:00:00.000',
      updatedAt: '2026-01-01T00:00:00.000',
    );

void main() {
  test('starting from wizard never mirrors an existing card into legacy tables',
      () async {
    final cards = MemorySettingCardRepository();
    await cards.save(_card('sc_w', SettingCardKind.worldview));
    await cards.save(_card('sc_c', SettingCardKind.character));
    final crud = _RecordingCrud();
    final useCase = StartAdventureFromWizardUseCase(
      crud: crud,
      setup: _FakeSetup(),
      gate: _ReadyGate(),
      cards: cards,
    );

    final outcome = await useCase.prepare(
      draft: const WizardStartDraft(
        worldview: WizardWorldviewDraft(
          id: 'sc_w',
          name: '新名',
          description: '新摘要',
          detailJson: '{}',
          saveToLibrary: true,
        ),
        characters: <WizardCharacterDraft>[
          WizardCharacterDraft(
            id: 'sc_c',
            name: '林恩',
            jsonData: '{}',
            matchingWorldviewId: '',
          ),
        ],
        saveCharacters: true,
      ),
      composeConfig: (_) => AdventureConfig(
        worldviewSnapshot: <String, dynamic>{'source_id': 'sc_w'},
      ),
    );

    expect(outcome, isA<WizardStartReady>());
    expect(crud.worldviewSaves, 0);
    expect(crud.characterSaves, 0);
    expect(cards.cards, hasLength(2));
    expect(
        cards.cards.containsKey('res_legacy_worldview_presets_sc_w'), isFalse);

    final saved = cards.cards['sc_w']!;
    expect(saved.name, '新名');
    expect(saved.summary, '新摘要');
    expect(saved.content, '正文');
  });
}
