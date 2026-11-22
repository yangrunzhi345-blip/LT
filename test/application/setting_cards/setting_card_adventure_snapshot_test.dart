import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/adventure/adventure_readiness_gate.dart';
import 'package:lt_dialogue/application/resources/assembly_readiness_coordinator.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_adventure_snapshot.dart';
import 'package:lt_dialogue/domain/setting_cards/setting_card.dart';
import 'package:lt_dialogue/models/adventure_config.dart';

import '../../helpers/setting_card_fakes.dart';

final class _FakeInnerGate implements IAdventureReadinessGate {
  AdventureConfig? received;
  int freezeCalls = 0;

  @override
  Future<AssemblyPrepareOutcome> prepare(String assetId) =>
      throw UnimplementedError();

  @override
  Future<Map<String, AdventureAssetReadiness>> resolve(
    Iterable<String> assetIds,
  ) async =>
      <String, AdventureAssetReadiness>{
        for (final id in assetIds)
          id: AdventureAssetReadiness(
            assetId: id,
            status: AdventureAssetGateStatus.notManaged,
            issueCode: AdventureReadinessIssueCode.notManaged,
          ),
      };

  @override
  Future<Map<String, AdventureAssetReadiness>> resolveConfig(
    AdventureConfig config,
  ) =>
      resolve(<String>[
        if (config.worldviewSnapshot?['source_id'] != null)
          config.worldviewSnapshot!['source_id'].toString(),
      ]);

  @override
  Future<AdventureConfig> enforceAndFreeze(AdventureConfig config) async {
    freezeCalls++;
    received = config;
    return config;
  }
}

SettingCard _card(
  String id,
  SettingCardKind kind, {
  String name = '设定',
  String content = '正文',
  String legacyId = '',
}) =>
    SettingCard(
      id: id,
      kind: kind,
      name: name,
      content: content,
      originWorldviewId: kind == SettingCardKind.npc ? 'w1' : '',
      legacyId: legacyId.isEmpty ? null : legacyId,
      createdAt: '2026-01-01T00:00:00.000',
      updatedAt: '2026-01-01T00:00:00.000',
    );

void main() {
  late MemorySettingCardRepository cards;
  late _FakeInnerGate inner;
  late SettingCardAwareReadinessGate gate;

  setUp(() {
    cards = MemorySettingCardRepository();
    inner = _FakeInnerGate();
    gate = SettingCardAwareReadinessGate(inner: inner, cards: cards);
  });

  test('card assets resolve ready without an assembly revision', () async {
    cards.cards['w1'] = _card('w1', SettingCardKind.worldview);

    final result = await gate.resolve(<String>['w1']);

    expect(result['w1']!.status, AdventureAssetGateStatus.ready);
    expect(result['w1']!.parameters['snapshot'], 'setting_card');
  });

  test('worldview card is frozen as a single-document snapshot', () async {
    cards.cards['w1'] = _card(
      'w1',
      SettingCardKind.worldview,
      name: '银月大陆',
      content: '# 银月大陆\n\n被月光笼罩。',
    );
    final config = AdventureConfig(
      worldviewSnapshot: <String, dynamic>{'source_id': 'w1'},
    );

    final frozen = await gate.enforceAndFreeze(config);

    expect(frozen.worldviewSnapshot!['name'], '银月大陆');
    expect(frozen.worldviewSnapshot!['content'], contains('被月光笼罩'));
    expect(frozen.worldviewSnapshot!['snapshot_kind'], 'setting_card');
    expect(frozen.worldviewSnapshot!['source_id'], 'w1');
    // Only card assets: the legacy gate must not run.
    expect(inner.freezeCalls, 0);
  });

  test('character card fills the selected character and protagonist name',
      () async {
    cards.cards['c1'] = _card(
      'c1',
      SettingCardKind.character,
      name: '林恩',
      content: '他是一名游侠',
    );
    final config = AdventureConfig(
      selectedCharacters: <AdventureSelectedCharacter>[
        AdventureSelectedCharacter(
          id: 'sel-1',
          characterId: 'c1',
          characterName: '旧名字',
          isProtagonist: true,
        ),
      ],
    );

    final frozen = await gate.enforceAndFreeze(config);

    final selected = frozen.selectedCharacters.single;
    expect(selected.characterName, '林恩');
    expect(selected.characterCardJson!['description'], '他是一名游侠');
    expect(frozen.name, '林恩');
  });

  test('npc card replaces the frozen npc snapshot', () async {
    cards.cards['n1'] = _card(
      'n1',
      SettingCardKind.npc,
      name: '北门守卫',
      content: '忠于银月城。',
    );
    final config = AdventureConfig(
      npcSnapshots: <AdventureNpcSnapshot>[
        AdventureNpcSnapshot(
          assetId: 'n1',
          name: '旧守卫',
          npcJson: <String, dynamic>{'old': true},
        ),
      ],
    );

    final frozen = await gate.enforceAndFreeze(config);

    final npc = frozen.npcSnapshots.single;
    expect(npc.name, '北门守卫');
    expect(npc.npcJson['content'], '忠于银月城。');
    expect(npc.npcJson.containsKey('old'), isFalse);
    expect(npc.originWorldviewId, 'w1');
  });

  test('legacy-only assets still go through the old gate', () async {
    final config = AdventureConfig(
      selectedCharacters: <AdventureSelectedCharacter>[
        AdventureSelectedCharacter(
          id: 'sel-1',
          characterId: 'legacy-c',
          characterName: '旧角色',
        ),
      ],
    );

    await gate.enforceAndFreeze(config);

    expect(inner.freezeCalls, 1);
    expect(inner.received!.selectedCharacters.single.characterId, 'legacy-c');
  });

  test('mixed config freezes cards and delegates only legacy ids', () async {
    cards.cards['c1'] = _card(
      'c1',
      SettingCardKind.character,
      name: '林恩',
      content: '游侠',
    );
    final config = AdventureConfig(
      selectedCharacters: <AdventureSelectedCharacter>[
        AdventureSelectedCharacter(
          id: 'sel-1',
          characterId: 'c1',
          characterName: '旧名字',
        ),
        AdventureSelectedCharacter(
          id: 'sel-2',
          characterId: 'legacy-c',
          characterName: '旧角色',
        ),
      ],
    );

    final frozen = await gate.enforceAndFreeze(config);

    expect(inner.freezeCalls, 1);
    expect(
      inner.received!.selectedCharacters.map((item) => item.characterId),
      <String>['legacy-c'],
    );
    expect(
      frozen.selectedCharacters.map((item) => item.characterName),
      <String>['林恩', '旧角色'],
    );
  });

  test('legacy id resolves to the migrated card', () async {
    cards.cards['res_legacy_character_cards_c1'] = _card(
      'res_legacy_character_cards_c1',
      SettingCardKind.character,
      name: '迁移角色',
      legacyId: 'c1',
    );

    final result = await gate.resolve(<String>['c1']);

    expect(result['c1']!.status, AdventureAssetGateStatus.ready);
  });
}
