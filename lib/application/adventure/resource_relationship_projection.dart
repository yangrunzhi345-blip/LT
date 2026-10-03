import '../../domain/resources/character_relationship.dart';
import '../../models/adventure_config.dart';

/// Projects live resource edges into an Adventure-owned snapshot.
final class ResourceRelationshipProjection {
  const ResourceRelationshipProjection._();

  /// Returns only edges whose two resource endpoints are selected.
  static List<AdventureCharacterRelationship> project({
    required Iterable<CharacterRelationship> relationships,
    required Set<String> selectedResourceIds,
    Map<String, String> resourceIdToAdventureId = const <String, String>{},
  }) {
    final result = <AdventureCharacterRelationship>[];
    for (final relationship in relationships) {
      final a = relationship.endpointAResourceId.value;
      final b = relationship.endpointBResourceId.value;
      if (!selectedResourceIds.contains(a) ||
          !selectedResourceIds.contains(b)) {
        continue;
      }
      final sourceIsA = _sourceIsEndpointA(relationship);
      final sourceResourceId = sourceIsA ? a : b;
      final targetResourceId = sourceIsA ? b : a;
      final sourceId =
          resourceIdToAdventureId[sourceResourceId] ?? sourceResourceId;
      final targetId =
          resourceIdToAdventureId[targetResourceId] ?? targetResourceId;
      final sourceRole =
          sourceIsA ? relationship.endpointARole : relationship.endpointBRole;
      final targetRole =
          sourceIsA ? relationship.endpointBRole : relationship.endpointARole;
      result.add(AdventureCharacterRelationship(
        id: relationship.id,
        sourceCharacterId: sourceId,
        targetCharacterId: targetId,
        relationType: _adventureRelationType(relationship),
        customRelationName:
            relationship.relationType == CharacterRelationshipType.custom
                ? sourceRole
                : '',
        sourceRole: sourceRole,
        targetRole: targetRole,
        description: relationship.description,
      ));
    }
    return List.unmodifiable(result);
  }

  /// Directional resource relationships are canonicalized by opaque resource
  /// identity, which may put the semantic target before the semantic source.
  /// Reorder only the snapshot endpoints for directional types; symmetric and
  /// custom relationships retain their canonical endpoint order.
  static bool _sourceIsEndpointA(CharacterRelationship relationship) {
    final sourceRole = switch (relationship.relationType) {
      CharacterRelationshipType.mentorStudent => 'mentor',
      CharacterRelationshipType.parentChild => 'parent',
      CharacterRelationshipType.employerEmployee => 'employer',
      CharacterRelationshipType.guardianWard => 'guardian',
      _ => null,
    };
    if (sourceRole == null) return true;
    if (relationship.endpointARole == sourceRole) return true;
    if (relationship.endpointBRole == sourceRole) return false;
    // Domain validation rejects this state. Keep projection deterministic if a
    // legacy/tampered row reaches the boundary rather than swapping blindly.
    return true;
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
