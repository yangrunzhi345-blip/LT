import '../../domain/resources/character_relationship.dart';
import '../../models/adventure_config.dart';

/// Projects live resource edges into an Adventure-owned snapshot.
final class ResourceRelationshipProjection {
  const ResourceRelationshipProjection._();

  /// Returns only edges whose two resource endpoints are selected.
  static List<AdventureCharacterRelationship> project({
    required Iterable<CharacterRelationship> relationships,
    required Set<String> selectedResourceIds,
  }) {
    final result = <AdventureCharacterRelationship>[];
    for (final relationship in relationships) {
      final a = relationship.endpointAResourceId.value;
      final b = relationship.endpointBResourceId.value;
      if (!selectedResourceIds.contains(a) ||
          !selectedResourceIds.contains(b)) {
        continue;
      }
      result.add(AdventureCharacterRelationship(
        id: relationship.id,
        sourceCharacterId: a,
        targetCharacterId: b,
        relationType: _adventureRelationType(relationship),
        customRelationName:
            relationship.relationType == CharacterRelationshipType.custom
                ? relationship.endpointARole
                : '',
        description: relationship.description,
      ));
    }
    return List.unmodifiable(result);
  }

  static String _adventureRelationType(CharacterRelationship relationship) {
    return switch (relationship.relationType) {
      CharacterRelationshipType.friend => AdventureRelationType.friend,
      CharacterRelationshipType.family ||
      CharacterRelationshipType.sibling ||
      CharacterRelationshipType.parentChild =>
        AdventureRelationType.family,
      CharacterRelationshipType.enemy => AdventureRelationType.enemy,
      CharacterRelationshipType.companion => AdventureRelationType.companion,
      CharacterRelationshipType.lover => AdventureRelationType.lover,
      CharacterRelationshipType.mentorStudent ||
      CharacterRelationshipType.guardianWard =>
        AdventureRelationType.mentor,
      CharacterRelationshipType.employerEmployee =>
        AdventureRelationType.employer,
      CharacterRelationshipType.rival => AdventureRelationType.rival,
      CharacterRelationshipType.stranger => AdventureRelationType.stranger,
      CharacterRelationshipType.custom => AdventureRelationType.custom,
    };
  }
}
