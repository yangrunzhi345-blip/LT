import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/setting_cards/setting_card.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/character_card.dart';
import 'package:lt_dialogue/models/supporting_character.dart';

import '../../helpers/phase10_fixture.dart';

void main() {
  late Phase10Fixture fixture;

  Map<String, dynamic> data(String version) => {
        'name': 'name_$version',
        'description': 'background_$version',
        'personality': 'personality_$version',
        'first_mes': 'greeting_$version',
        'system_prompt': 'system_$version',
      };

  setUp(() async {
    fixture = Phase10Fixture();
    await fixture.setUp(prefix: 'lt_p10_fields_');
  });
  tearDown(() => fixture.tearDown());

  group('card gate field freezing', () {
    test('freezes every card carrier from the card, not Wizard input',
        () async {
      await fixture.putCard(
        id: 'hero',
        kind: SettingCardKind.character,
        name: 'name_A',
        content: 'background_A',
        summary: '摘要_A',
      );
      await fixture.putCard(
        id: 'companion',
        kind: SettingCardKind.character,
        name: 'name_A',
        content: 'background_A',
      );
      await fixture.putCard(
        id: 'npc',
        kind: SettingCardKind.npc,
        name: 'name_A',
        content: 'npc_body_A',
        originWorldviewId: 'world_A',
      );

      final legacy = SupportingCharacter(id: 'legacy', name: 'untouched');
      final config = AdventureConfig(
        name: 'name_B',
        gender: 'gender_B',
        age: '42',
        personality: 'personality_B',
        protagonistClass: 'profession_B',
        protagonistBackground: 'background_B',
        characterCard: CharacterCard.fromJson(data('B')),
        selectedCharacters: [
          AdventureSelectedCharacter(
            id: 'hero-selection',
            characterId: 'hero',
            characterName: 'name_B',
            characterAvatar: 'avatar_B',
            isProtagonist: true,
            characterCardJson: data('B'),
          ),
          AdventureSelectedCharacter(
            id: 'companion-selection',
            characterId: 'companion',
            characterName: 'name_B',
            narrativeRole: AdventureCharacterRole.mentor,
            characterCardJson: data('B'),
          ),
        ],
        supportingCharacters: [
          SupportingCharacter.fromJson({
            ...data('B'),
            'id': 'companion',
            'relation': '用户指定关系',
          }),
          SupportingCharacter.fromJson({...data('B'), 'id': 'npc'}),
          legacy,
        ],
        npcSnapshots: [
          AdventureNpcSnapshot(
            assetId: 'npc',
            name: 'name_B',
            originWorldviewId: 'world_B',
            npcJson: data('B'),
          ),
        ],
      );
      final inputBefore = jsonEncode(config.toJson());

      final frozen = await fixture.gate.enforceAndFreeze(config);

      // The caller's config is never mutated.
      expect(jsonEncode(config.toJson()), inputBefore);

      // The protagonist card is authoritative: the stale card and the
      // Wizard-entered fields are replaced by the card document.
      expect(frozen.characterCard, isNull);
      expect(frozen.name, 'name_A');
      expect(frozen.personality, isEmpty);
      expect(frozen.gender, 'gender_B');
      expect(frozen.protagonistClass, 'profession_B');

      final hero = frozen.selectedCharacters.first;
      expect(hero.characterName, 'name_A');
      expect(hero.characterCardJson!['description'], 'background_A');
      expect(hero.characterCardJson!['setting_card_id'], 'hero');
      expect(jsonEncode(hero.characterCardJson), isNot(contains('_B')));

      final companionSelection = frozen.selectedCharacters.last;
      expect(companionSelection.narrativeRole, AdventureCharacterRole.mentor);
      expect(companionSelection.characterName, 'name_A');

      final support = frozen.supportingCharacters.first;
      expect(support.id, 'companion');
      expect(support.name, 'name_A');
      // The card gate only owns the identity fields; user-chosen relation
      // survives.
      expect(support.relation, '用户指定关系');

      final frozenNpcSupport = frozen.supportingCharacters[1];
      expect(frozenNpcSupport.id, 'npc');
      expect(frozenNpcSupport.name, 'name_A');

      // Untouched legacy supporting characters pass through unchanged.
      expect(
        frozen.supportingCharacters.last.toJson(),
        legacy.toJson(),
      );

      final npc = frozen.npcSnapshots.single;
      expect(npc.name, 'name_A');
      expect(npc.originWorldviewId, 'world_A');
      expect(npc.npcJson['content'], 'npc_body_A');
      expect(jsonEncode(npc.npcJson), isNot(contains('_B')));
      expect(frozen.resourceBindings, isEmpty);
    });

    test('later card edits never change an already frozen config', () async {
      await fixture.putCard(
        id: 'hero',
        kind: SettingCardKind.character,
        name: 'name_A',
        content: 'background_A',
      );
      await fixture.putCard(
        id: 'npc',
        kind: SettingCardKind.npc,
        name: 'name_A',
        content: 'npc_body_A',
        originWorldviewId: 'world_A',
      );
      final config = AdventureConfig(
        selectedCharacters: [
          AdventureSelectedCharacter(
            id: 'hero-selection',
            characterId: 'hero',
            characterName: 'name_B',
            isProtagonist: true,
            characterCardJson: data('B'),
          ),
        ],
        npcSnapshots: [
          AdventureNpcSnapshot(
            assetId: 'npc',
            name: 'name_B',
            originWorldviewId: 'world_B',
            npcJson: data('B'),
          ),
        ],
      );

      final frozen = await fixture.gate.enforceAndFreeze(config);
      final frozenBefore = jsonEncode(frozen.toJson());

      await fixture.putCard(
        id: 'hero',
        kind: SettingCardKind.character,
        name: 'name_C',
        content: 'background_C',
      );
      await fixture.putCard(
        id: 'npc',
        kind: SettingCardKind.npc,
        name: 'name_C',
        content: 'npc_body_C',
        originWorldviewId: 'world_C',
      );

      expect(jsonEncode(frozen.toJson()), frozenBefore);
      final reloaded = AdventureConfig.fromJson(jsonDecode(frozenBefore));
      expect(reloaded.selectedCharacters.single.characterName, 'name_A');
      expect(
        reloaded.selectedCharacters.single.characterCardJson!['description'],
        'background_A',
      );
      expect(reloaded.npcSnapshots.single.name, 'name_A');
    });
  });
}
