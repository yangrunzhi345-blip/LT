import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/application/adventure/adventure_assembler.dart';
import 'package:lt_dialogue/core/utils/worldview_character_scope_policy.dart';
import 'package:lt_dialogue/features/adventure/presentation/wizard/models/wizard_character_item.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/character_card.dart';

void main() {
  group('WorldviewCharacterScopePolicy', () {
    test('should keep every character selectable and prioritize native origin',
        () {
      final resources = <Map<String, dynamic>>[
        {'id': 'b1', 'matching_worldview_id': 'world-b'},
        {'id': 'x'},
        {'id': 'a1', 'matching_worldview_id': 'world-a'},
        {'id': 'a2', 'matching_worldview_id': 'world-a'},
      ];

      final ordered = WorldviewCharacterScopePolicy.orderByOriginCompatibility(
        resources,
        'world-a',
      );

      expect(ordered.map((item) => item['id']), ['a1', 'a2', 'x', 'b1']);
      expect(ordered, hasLength(4));
      expect(
        WorldviewCharacterScopePolicy.compatibility('world-b', 'world-a'),
        CharacterWorldviewCompatibility.crossWorld,
      );
    });
  });

  group('WizardRelationshipItem', () {
    test('should keep a newly discovered relationship unset', () {
      final relationship = WizardRelationshipItem(
        id: 'a__b',
        sourceCharacterId: 'a',
        targetCharacterId: 'b',
      );

      expect(relationship.relationType, AdventureRelationType.unset);
      expect(relationship.effectiveRelation, '未设定');
    });
  });

  group('AdventureAssembler', () {
    test('should freeze worldview and character data by value', () {
      final sourceCard = <String, dynamic>{
        'name': '艾琳',
        'description': '北境骑士',
      };
      final sourceWorldview = <String, dynamic>{
        'source_id': 'world-a',
        'name': '北境',
        'description': '永冻之地',
      };
      final input = AdventureConfig(
        worldview: '北境',
        worldviewSnapshot: sourceWorldview,
        name: '艾琳',
        characterCard: CharacterCard(
          name: '艾琳',
          description: '北境骑士',
        ),
        selectedCharacters: [
          AdventureSelectedCharacter(
            id: 'character-a',
            characterId: 'character-a',
            characterName: '艾琳',
            isProtagonist: true,
            characterCardJson: sourceCard,
          ),
        ],
      );

      final frozen = const AdventureAssembler().assemble(input);
      sourceCard['description'] = '后来被修改';
      sourceWorldview['description'] = '后来被修改';

      expect(frozen.worldviewSnapshot?['description'], '永冻之地');
      expect(
        frozen.selectedCharacters.single.characterCardJson?['description'],
        '北境骑士',
      );
    });

    test('should create snapshots for legacy assembly input', () {
      final frozen = const AdventureAssembler().assemble(
        AdventureConfig(
          worldview: '北境',
          name: '艾琳',
          characterCard: CharacterCard(
            name: '艾琳',
            description: '北境骑士',
          ),
          selectedCharacters: [
            AdventureSelectedCharacter(
              id: 'character-a',
              characterId: 'character-a',
              characterName: '艾琳',
              isProtagonist: true,
            ),
          ],
        ),
      );

      expect(frozen.worldviewSnapshot, isNotNull);
      expect(
        (frozen.selectedCharacters.single.characterCardJson?['data']
            as Map<String, dynamic>?)?['description'],
        '北境骑士',
      );
    });
  });
}
