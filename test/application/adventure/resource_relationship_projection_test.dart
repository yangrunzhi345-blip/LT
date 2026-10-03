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
    expect(projected.single.sourceRole, 'friend');
    expect(projected.single.targetRole, 'friend');
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
    expect(projected.single.sourceRole, 'mentor');
    expect(projected.single.targetRole, 'student');
  });

  test('reorders an inverse directional edge by semantic roles', () {
    final edge = CharacterRelationship(
      id: 'edge-inverse',
      endpointAResourceId: const ResourceId('a'),
      endpointBResourceId: const ResourceId('b'),
      relationType: CharacterRelationshipType.mentorStudent,
      endpointARole: 'student',
      endpointBRole: 'mentor',
      description: 'inverse canonical ordering',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final projected = ResourceRelationshipProjection.project(
      relationships: [edge],
      selectedResourceIds: {'a', 'b'},
    );

    expect(projected.single.sourceCharacterId, 'b');
    expect(projected.single.targetCharacterId, 'a');
    expect(projected.single.sourceRole, 'mentor');
    expect(projected.single.targetRole, 'student');
  });

  test('preserves semantic roles for parent, employer, and guardian edges', () {
    final cases = <(CharacterRelationshipType, String, String, String)>[
      (
        CharacterRelationshipType.parentChild,
        'child',
        'parent',
        AdventureRelationType.family,
      ),
      (
        CharacterRelationshipType.employerEmployee,
        'employee',
        'employer',
        AdventureRelationType.employer,
      ),
      (
        CharacterRelationshipType.guardianWard,
        'ward',
        'guardian',
        AdventureRelationType.mentor,
      ),
    ];

    for (final (type, endpointARole, endpointBRole, adventureType) in cases) {
      final projected = ResourceRelationshipProjection.project(
        relationships: [
          CharacterRelationship(
            id: 'edge-${type.name}',
            endpointAResourceId: const ResourceId('a'),
            endpointBResourceId: const ResourceId('b'),
            relationType: type,
            endpointARole: endpointARole,
            endpointBRole: endpointBRole,
            description: '',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        ],
        selectedResourceIds: {'a', 'b'},
      );

      expect(projected.single.sourceCharacterId, 'b');
      expect(projected.single.targetCharacterId, 'a');
      expect(projected.single.relationType, adventureType);
      expect(projected.single.sourceRole, endpointBRole);
      expect(projected.single.targetRole, endpointARole);
    }
  });

  test('preserves both custom endpoint roles and legacy JSON remains readable',
      () {
    final edge = CharacterRelationship(
      id: 'edge-custom',
      endpointAResourceId: const ResourceId('a'),
      endpointBResourceId: const ResourceId('b'),
      relationType: CharacterRelationshipType.custom,
      endpointARole: 'rival in exile',
      endpointBRole: 'reluctant ally',
      description: 'custom roles',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final projected = ResourceRelationshipProjection.project(
      relationships: [edge],
      selectedResourceIds: {'a', 'b'},
    ).single;
    expect(projected.sourceCharacterId, 'a');
    expect(projected.targetCharacterId, 'b');
    expect(projected.sourceRole, 'rival in exile');
    expect(projected.targetRole, 'reluctant ally');
    expect(projected.customRelationName, 'rival in exile');

    final legacy = AdventureCharacterRelationship.fromJson({
      'id': 'legacy',
      'sourceCharacterId': 'a',
      'targetCharacterId': 'b',
      'relationType': AdventureRelationType.friend,
    });
    expect(legacy.sourceRole, isEmpty);
    expect(legacy.targetRole, isEmpty);
  });
}
