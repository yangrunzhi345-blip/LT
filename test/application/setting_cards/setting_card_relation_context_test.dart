import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_relation_context.dart';
import 'package:lt_dialogue/domain/resources/character_relationship.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/setting_cards/setting_card.dart';

import '../../helpers/setting_card_fakes.dart';

SettingCard _card({
  required String id,
  String name = '',
  String content = '',
  String? legacyId,
}) =>
    SettingCard(
      id: id,
      kind: SettingCardKind.character,
      name: name,
      content: content,
      legacyId: legacyId,
      createdAt: '2026-01-01T00:00:00.000',
      updatedAt: '2026-01-01T00:00:00.000',
    );

CharacterRelationshipPerspective _perspective({
  required String id,
  required String counterpart,
  String description = '结伴同行',
}) =>
    CharacterRelationshipPerspective(
      relationshipId: id,
      counterpartResourceId: ResourceId(counterpart),
      relationType: CharacterRelationshipType.companion,
      subjectRole: '同伴',
      counterpartRole: '同伴',
      description: description,
    );

void main() {
  test('loads confirmed relations as readable generation context', () async {
    final cards = MemorySettingCardRepository();
    await cards.save(_card(id: 'sc_hero', name: '林恩', legacyId: 'hero'));
    await cards.save(_card(
      id: 'res_legacy_companion',
      name: '艾琳',
      legacyId: 'companion',
      content: '## 性格与心理\n\n冷静而敏锐。\n\n## 背景经历\n\n来自北境。',
    ));

    final summaries = await SettingCardRelationContext.load(
      cardId: 'hero',
      cards: cards,
      listFor: (resourceId) async => resourceId.value == 'hero'
          ? <CharacterRelationshipPerspective>[
              _perspective(id: 'rel_1', counterpart: 'companion'),
            ]
          : const <CharacterRelationshipPerspective>[],
    );

    expect(summaries, hasLength(1));
    expect(summaries.single['name'], '艾琳');
    expect(summaries.single['relation'], '结伴同行');
    expect(summaries.single['personality'], '冷静而敏锐。');
    expect(summaries.single['background'], '来自北境。');
  });

  test('skips a deleted counterpart instead of failing generation', () async {
    final cards = MemorySettingCardRepository();
    await cards.save(_card(id: 'sc_hero', name: '林恩'));
    await cards.save(_card(id: 'sc_gone', name: '旧友'));
    await cards.softDelete('sc_gone', deletedAt: '2026-02-01T00:00:00.000');

    final summaries = await SettingCardRelationContext.load(
      cardId: 'sc_hero',
      cards: cards,
      listFor: (resourceId) async => resourceId.value == 'sc_hero'
          ? <CharacterRelationshipPerspective>[
              _perspective(id: 'rel_2', counterpart: 'sc_gone'),
            ]
          : const <CharacterRelationshipPerspective>[],
    );

    expect(summaries, isEmpty);
  });

  test('reads relations stored under the legacy resource id', () async {
    final cards = MemorySettingCardRepository();
    await cards.save(_card(id: 'sc_hero', name: '林恩', legacyId: 'hero'));
    await cards.save(_card(id: 'sc_friend', name: '米娅', legacyId: 'friend'));
    final queried = <String>[];

    final summaries = await SettingCardRelationContext.load(
      cardId: 'sc_hero',
      cards: cards,
      listFor: (resourceId) async {
        queried.add(resourceId.value);
        return resourceId.value == 'hero'
            ? <CharacterRelationshipPerspective>[
                _perspective(id: 'rel_3', counterpart: 'friend'),
              ]
            : const <CharacterRelationshipPerspective>[];
      },
    );

    expect(queried, containsAll(<String>['sc_hero', 'hero']));
    expect(summaries.single['name'], '米娅');
  });
}
