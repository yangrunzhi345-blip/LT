import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/adventure/resource_relationship_projection.dart';
import 'package:lt_dialogue/domain/resources/character_relationship.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/models/adventure_config.dart';

void main() {
  test('projects only fully selected endpoints into an isolated snapshot', () {
    final edge = CharacterRelationship(
      id: 'edge-1',
      endpointAResourceId: const ResourceId('a'),
      endpointBResourceId: const ResourceId('b'),
      relationType: CharacterRelationshipType.friend,
      endpointARole: 'friend',
      endpointBRole: 'friend',
      description: 'old snapshot',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final projected = ResourceRelationshipProjection.project(
      relationships: [edge],
      selectedResourceIds: {'a', 'b'},
    );
    expect(projected, hasLength(1));
    expect(projected.single.sourceCharacterId, 'a');
    expect(projected.single.targetCharacterId, 'b');
    expect(projected.single.description, 'old snapshot');
    expect(
        ResourceRelationshipProjection.project(
          relationships: [edge],
          selectedResourceIds: {'a'},
        ),
        isEmpty);
  });

  test('maps unified resource ids back to wizard roster ids', () {
    final edge = CharacterRelationship(
      id: 'edge-legacy',
      endpointAResourceId: const ResourceId('res_legacy_character_cards_a'),
      endpointBResourceId: const ResourceId('res_legacy_character_cards_b'),
      relationType: CharacterRelationshipType.mentorStudent,
      endpointARole: 'mentor',
      endpointBRole: 'student',
      description: 'preserve direction',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final projected = ResourceRelationshipProjection.project(
      relationships: [edge],
      selectedResourceIds: {
        'res_legacy_character_cards_a',
        'res_legacy_character_cards_b',
      },
      resourceIdToAdventureId: {
        'res_legacy_character_cards_a': 'a',
        'res_legacy_character_cards_b': 'b',
      },
    );

    expect(projected.single.sourceCharacterId, 'a');
    expect(projected.single.targetCharacterId, 'b');
    expect(projected.single.relationType, AdventureRelationType.mentor);
  });
}
