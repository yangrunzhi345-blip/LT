import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/application/adventure/adventure_assembler.dart';
import 'package:lt_dialogue/core/utils/worldview_character_scope_policy.dart';
import 'package:lt_dialogue/features/adventure/presentation/wizard/models/wizard_character_item.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/character_card.dart';
import 'package:lt_dialogue/models/supporting_character.dart';

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

    test('legacy filter wrapper must not reintroduce hard worldview scoping',
        () {
      final resources = <Map<String, dynamic>>[
        {'id': 'cross', 'matching_worldview_id': 'world-b'},
        {'id': 'unbound'},
        {'id': 'native', 'matching_worldview_id': 'world-a'},
      ];

      final result = WorldviewCharacterScopePolicy.filterSceneResources(
        resources,
        'world-a',
      );

      expect(result.map((item) => item['id']), ['native', 'unbound', 'cross']);
      expect(result, hasLength(3));
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

    test('should keep undefined selected-character relation empty at runtime',
        () {
      final frozen = const AdventureAssembler().assemble(
        AdventureConfig(
          name: '主角',
          selectedCharacters: [
            AdventureSelectedCharacter(
              id: 'hero',
              characterId: 'hero',
              characterName: '主角',
              isProtagonist: true,
            ),
            AdventureSelectedCharacter(
              id: 'ally',
              characterId: 'ally',
              characterName: '艾琳',
              narrativeRole: AdventureCharacterRole.supporting,
            ),
          ],
          supportingCharacters: [
            SupportingCharacter(
              id: 'ally',
              name: '艾琳',
              role: '骑士',
              relation: '重要配角',
            ),
          ],
        ),
      );

      expect(frozen.supportingCharacters.single.role, '骑士');
      expect(frozen.supportingCharacters.single.relation, isEmpty);
    });

    test('should preserve an explicitly defined selected-character relation',
        () {
      final frozen = const AdventureAssembler().assemble(
        AdventureConfig(
          name: '主角',
          selectedCharacters: [
            AdventureSelectedCharacter(
              id: 'hero',
              characterId: 'hero',
              characterName: '主角',
              isProtagonist: true,
            ),
            AdventureSelectedCharacter(
              id: 'ally',
              characterId: 'ally',
              characterName: '艾琳',
            ),
          ],
          characterRelationships: [
            AdventureCharacterRelationship(
              id: 'ally__hero',
              sourceCharacterId: 'hero',
              targetCharacterId: 'ally',
              relationType: AdventureRelationType.companion,
            ),
          ],
          supportingCharacters: [
            SupportingCharacter(
              id: 'ally',
              name: '艾琳',
              relation: '重要配角',
            ),
          ],
        ),
      );

      expect(frozen.supportingCharacters.single.relation, '同伴');
    });

    test('should freeze and restore NPC data without its library asset', () {
      final sourceNpc = <String, dynamic>{
        'name': '守门人',
        'profession': '王宫卫兵',
      };
      final frozen = const AdventureAssembler().assemble(
        AdventureConfig(
          name: '艾琳',
          npcSnapshots: [
            AdventureNpcSnapshot(
              assetId: 'npc-1',
              name: '守门人',
              originWorldviewId: 'world-a',
              npcJson: sourceNpc,
            ),
          ],
        ),
      );
      sourceNpc['profession'] = '后来被修改';

      final restored = AdventureConfig.fromJson(frozen.toJson());
      expect(restored.npcSnapshots.single.assetId, 'npc-1');
      expect(
        restored.npcSnapshots.single.npcJson['profession'],
        '王宫卫兵',
      );
    });

    test('should clear legacy role pollution when no relation is defined', () {
      final frozen = const AdventureAssembler().assemble(
        AdventureConfig(
          selectedCharacters: [
            AdventureSelectedCharacter(
              id: 'hero-row',
              characterId: 'hero-asset',
              characterName: '主角',
              isProtagonist: true,
            ),
            AdventureSelectedCharacter(
              id: 'lead-row',
              characterId: 'lead-asset',
              characterName: '艾琳',
              narrativeRole: AdventureCharacterRole.femaleLead,
            ),
          ],
          supportingCharacters: [
            SupportingCharacter(
              id: 'lead-asset',
              name: '艾琳',
              relation: '女主',
            ),
          ],
        ),
      );

      expect(frozen.supportingCharacters.single.relation, isEmpty);
    });

    test('should retain an explicit relation across selected ID aliases', () {
      final frozen = const AdventureAssembler().assemble(
        AdventureConfig(
          selectedCharacters: [
            AdventureSelectedCharacter(
              id: 'hero-row',
              characterId: 'hero-asset',
              characterName: '主角',
              isProtagonist: true,
            ),
            AdventureSelectedCharacter(
              id: 'lead-row',
              characterId: 'lead-asset',
              characterName: '艾琳',
            ),
          ],
          characterRelationships: [
            AdventureCharacterRelationship(
              id: 'relation',
              sourceCharacterId: 'hero-asset',
              targetCharacterId: 'lead-row',
              relationType: AdventureRelationType.enemy,
            ),
          ],
          supportingCharacters: [
            SupportingCharacter(id: 'lead-asset', name: '艾琳', relation: '女主'),
          ],
        ),
      );

      expect(frozen.supportingCharacters.single.relation, '敌人');
    });
  });
}
