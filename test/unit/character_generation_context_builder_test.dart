import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resource_library/character_generation_context_builder.dart';
import 'package:lt_dialogue/application/resource_library/character_generation_reference.dart';
import 'package:lt_dialogue/domain/resources/character_relationship.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';

void main() {
  group('CharacterGenerationContextBuilder', () {
    test(
        'retains typed relationship constraints independently of legacy context',
        () {
      final relationship = CharacterGenerationRelationship(references: [
        CharacterGenerationReference(
          sourceResourceId: const ResourceId('res_a'),
          relationshipType: CharacterRelationshipType.friend,
          sourceRole: 'friend',
          generatedCharacterRole: 'friend',
        ),
      ]);
      final context = const CharacterGenerationContextBuilder().build(
        source: 'source',
        relationship: relationship,
      );

      expect(context.relationship.references.single.sourceResourceId.value,
          'res_a');
      expect(context.associatedCharacters, isEmpty);
    });
    test('should select bounded relevant worldview modules', () {
      final context = const CharacterGenerationContextBuilder().build(
        source: '白港炼金师',
        worldview: jsonEncode({
          'mode': 'detailed',
          'modules': {
            'overview': {'summary': '白港是雾银炼金的贸易城市。'},
            'world_rules': {'content': '炼金术会消耗施术者的记忆。'},
            'locations': {'content': '白港下城区聚集着炼金工坊。'},
            'factions': {'content': '白港炼金议会控制牌照。'},
            'timeline': {'content': List.filled(10000, '冗余历史').join()},
          },
        }),
      );

      expect(context.worldview, contains('白港'));
      expect(context.worldview, contains('炼金'));
      expect(context.worldview.length, lessThanOrEqualTo(8000));
    });

    test('should retain each linked character relation independently', () {
      final context = const CharacterGenerationContextBuilder().build(
        source: '新角色',
        associatedCharacters: const [
          {
            'name': '阿尔玛',
            'profession': '医师',
            'background': '很长的背景',
            'relation': '姐姐',
          },
          {
            'name': '贝恩',
            'profession': '卫兵',
            'relation': '敌人',
          },
        ],
      );

      expect(context.associatedCharacters, hasLength(2));
      expect(context.associatedCharacters[0]['relation'], '姐姐');
      expect(context.associatedCharacters[1]['relation'], '敌人');
    });

    test('rejects mixed worldview scopes before building generation context',
        () {
      CharacterGenerationReference reference(String id, String worldview) =>
          CharacterGenerationReference(
            sourceResourceId: ResourceId(id),
            relationshipType: CharacterRelationshipType.friend,
            sourceRole: 'friend',
            generatedCharacterRole: 'friend',
            worldviewScope: worldview,
          );

      expect(
        () => const CharacterGenerationContextBuilder().build(
          source: 'new character',
          relationship: CharacterGenerationRelationship.fromReferences([
            // Distinct scopes must not silently inherit the first reference.
            CharacterGenerationReference(
              sourceResourceId: const ResourceId('res_a'),
              relationshipType: CharacterRelationshipType.friend,
              sourceRole: 'friend',
              generatedCharacterRole: 'friend',
              worldviewScope: 'world_a',
            ),
            CharacterGenerationReference(
              sourceResourceId: const ResourceId('res_b'),
              relationshipType: CharacterRelationshipType.friend,
              sourceRole: 'friend',
              generatedCharacterRole: 'friend',
              worldviewScope: 'world_b',
            ),
          ]),
        ),
        throwsA(isA<CharacterGenerationScopeException>()),
      );
      // Keep the helper's type checked in this test so future changes cannot
      // accidentally replace ResourceId with display names.
      expect(reference('res_c', 'world_c').sourceResourceId,
          const ResourceId('res_c'));
    });
  });
}
