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

  /// Updates roles entered from the current endpoint's perspective.
  ///
  /// The repository stores canonical endpoint ordering, so this boundary is
  /// responsible for translating the editor's subject/counterpart roles back
  /// to the canonical pair before persistence.
  Future<CharacterRelationship> updateFromPerspective({
    required ResourceId subjectResourceId,
    required String relationshipId,
    required CharacterRelationshipType relationType,
    required String subjectRole,
    required String counterpartRole,
    required String description,
  }) async {
    final existing = await _repository.getById(relationshipId);
    if (existing == null) {
      throw const CharacterRelationshipValidationException(
        CharacterRelationshipFailure.relationshipNotFound,
        'Relationship no longer exists',
      );
    }
    final perspective = existing.perspectiveFor(subjectResourceId);
    final endpoints = CharacterRelationshipEndpoints.canonicalize(
      firstResourceId: subjectResourceId,
      firstRole: subjectRole,
      secondResourceId: perspective.counterpartResourceId,
      secondRole: counterpartRole,
    );
    return _repository.update(
      id: relationshipId,
      relationType: relationType,
      endpointARole: endpoints.aRole,
      endpointBRole: endpoints.bRole,
      description: description,
    );
  }

  /// Deletes only the edge; endpoint resources remain untouched.
  Future<void> delete(String relationshipId) async {
    final existing = await _repository.getById(relationshipId);
    if (existing == null) {
      throw const CharacterRelationshipValidationException(
        CharacterRelationshipFailure.relationshipNotFound,
        'Relationship no longer exists',
      );
    }
    await _repository.delete(relationshipId);
  }
}
