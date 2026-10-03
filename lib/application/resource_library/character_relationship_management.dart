import '../../domain/resources/character_relationship.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../services/repositories/character_relationship_repository.dart';

/// Application boundary for displaying and changing resource relationships.
final class CharacterRelationshipManagement {
  const CharacterRelationshipManagement(this._repository);

  final CharacterRelationshipRepository _repository;

  /// Lists edges projected for [resourceId]'s perspective.
  Future<List<CharacterRelationshipPerspective>> listFor(
    ResourceId resourceId,
  ) async {
    final relationships = await _repository.listForResource(resourceId);
    return relationships
        .map((relationship) => relationship.perspectiveFor(resourceId))
        .toList(growable: false);
  }

  /// Updates one edge after validating both endpoint roles.
  Future<CharacterRelationship> update({
    required String relationshipId,
    required CharacterRelationshipType relationType,
    required String endpointARole,
    required String endpointBRole,
    required String description,
  }) =>
      _repository.update(
        id: relationshipId,
        relationType: relationType,
        endpointARole: endpointARole,
        endpointBRole: endpointBRole,
        description: description,
      );

  /// Deletes only the edge; endpoint resources remain untouched.
  Future<void> delete(String relationshipId) =>
      _repository.delete(relationshipId);
}
