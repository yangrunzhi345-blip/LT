import 'package:sqflite/sqflite.dart';

import '../../domain/resources/character_relationship.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../services/repositories/resource_tree_repository.dart';
import '../../services/repositories/character_relationship_repository.dart';
import '../../services/repositories/resource_tree_repository_impl.dart';

/// Persists an accepted character and all requested edges at one commit point.
final class AcceptGeneratedRelatedCharacter {
  const AcceptGeneratedRelatedCharacter({
    required ResourceTreeRepositoryImpl resourceRepository,
    required CharacterRelationshipRepository relationshipRepository,
  })  : _resourceRepository = resourceRepository,
        _relationshipRepository = relationshipRepository;

  final ResourceTreeRepositoryImpl _resourceRepository;
  final CharacterRelationshipRepository _relationshipRepository;

  /// Commits [resource] and every [relationships] edge atomically.
  Future<ResourceId> call({
    required ResourceTreeDraft resource,
    required Iterable<CharacterRelationshipDraftInput> relationships,
  }) =>
      _resourceRepository.runInTransaction((DatabaseExecutor txn) async {
        await _resourceRepository.createResourceTreeInTransaction(
            txn, resource);
        for (final relationship in relationships) {
          await _relationshipRepository.createInTransaction(
            txn,
            firstResourceId: relationship.firstResourceId,
            firstRole: relationship.firstRole,
            secondResourceId: relationship.secondResourceId,
            secondRole: relationship.secondRole,
            relationType: relationship.relationType,
            description: relationship.description,
          );
        }
        return resource.id;
      });
}

/// Validated relationship input for the accept aggregate.
final class CharacterRelationshipDraftInput {
  const CharacterRelationshipDraftInput({
    required this.firstResourceId,
    required this.firstRole,
    required this.secondResourceId,
    required this.secondRole,
    required this.relationType,
    this.description = '',
  });

  final ResourceId firstResourceId;
  final String firstRole;
  final ResourceId secondResourceId;
  final String secondRole;
  final CharacterRelationshipType relationType;
  final String description;
}
