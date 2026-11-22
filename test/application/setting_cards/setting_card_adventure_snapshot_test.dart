import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/adventure/adventure_readiness_gate.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_adventure_snapshot.dart';
import 'package:lt_dialogue/domain/setting_cards/setting_card.dart';
import 'package:lt_dialogue/models/adventure_config.dart';

import '../../helpers/setting_card_fakes.dart';

SettingCard _card(
  String id,
  SettingCardKind kind, {
  String name = '设定',
  String content = '正文',
}) =>
    SettingCard(
      id: id,
      kind: kind,
      name: name,
      content: content,
      originWorldviewId: kind == SettingCardKind.npc ? 'w1' : '',
      createdAt: '2026-01-01T00:00:00.000',
      updatedAt: '2026-01-01T00:00:00.000',
    );

void main() {
  late MemorySettingCardRepository cards;
  late SettingCardAwareReadinessGate gate;

  setUp(() {
    cards = MemorySettingCardRepository();
    gate = SettingCardAwareReadinessGate(cards: cards);
  });

  test('card assets resolve ready without an assembly revision', () async {
    cards.cards['w1'] = _card('w1', SettingCardKind.worldview);

    final result = await gate.resolve(<String>['w1']);

    expect(result['w1']!.status, AdventureAssetGateStatus.ready);
    expect(result['w1']!.parameters['snapshot'], 'setting_card');
  });

  test('non-card asset id resolves as notManaged', () async {
    final result = await gate.resolve(<String>['missing']);

    expect(result['missing']!.status, AdventureAssetGateStatus.notManaged);
    expect(
      result['missing']!.issueCode,
      AdventureReadinessIssueCode.notManaged,
    );
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
}
