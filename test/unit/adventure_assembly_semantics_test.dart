import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/core/utils/worldview_character_scope_policy.dart';
import 'package:lt_dialogue/features/adventure/presentation/wizard/models/wizard_character_item.dart';
import 'package:lt_dialogue/models/adventure_config.dart';

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
}
