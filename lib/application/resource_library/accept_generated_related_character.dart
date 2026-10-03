import 'package:sqflite/sqflite.dart';

import '../../domain/resources/character_relationship.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../services/repositories/resource_tree_repository.dart';
import '../../services/repositories/character_relationship_repository.dart';
import '../../services/repositories/resource_tree_repository_impl.dart';
import '../../services/repositories/resource_tree_row_mapper.dart';

/// Persists an accepted character and all requested edges at one commit point.
final class AcceptGeneratedRelatedCharacter {
  const AcceptGeneratedRelatedCharacter({
    required ResourceTreeRepositoryImpl resourceRepository,
    required CharacterRelationshipRepository relationshipRepository,
  })  : _resourceRepository = resourceRepository,
        _relationshipRepository = relationshipRepository;

  final ResourceTreeRepositoryImpl _resourceRepository;
  final CharacterRelationshipRepository _relationshipRepository;

  /// The accepted resource records the operation identity in its metadata.
  /// This reuses the existing resource identity/provenance channel and keeps
  /// repeated accepts from creating a second aggregate.
  static const acceptanceIdempotencyKeyMetadata =
      'related_character_accept_idempotency_key';
  static const acceptanceSessionIdMetadata =
      'related_character_accept_creation_session_id';

  /// Commits [resource] and every [relationships] edge atomically.
  Future<ResourceId> call({
    required ResourceTreeDraft resource,
    required Iterable<CharacterRelationshipDraftInput> relationships,
    String? idempotencyKey,
    String? creationSessionId,
  }) async {
    if (resource.type != ResourceType.character &&
        resource.type != ResourceType.npc) {
      throw const ResourceTreeConflictException(
        'Only character or NPC resources can be accepted with relationships',
      );
    }
    final normalizedKey = _normalizeIdentity(idempotencyKey, 'idempotencyKey');
    final normalizedSession =
        _normalizeIdentity(creationSessionId, 'creationSessionId');
    final requestedRelationships = relationships.toList(growable: false);
    for (final relationship in requestedRelationships) {
      if (relationship.firstResourceId != resource.id &&
          relationship.secondResourceId != resource.id) {
        throw const ResourceTreeConflictException(
          'Every accepted relationship must include the accepted resource',
        );
      }
    }
    final metadata = <String, Object?>{...resource.metadata};
    if (normalizedKey != null) {
      metadata[acceptanceIdempotencyKeyMetadata] = normalizedKey;
    }
    if (normalizedSession != null) {
      metadata[acceptanceSessionIdMetadata] = normalizedSession;
    }
    final acceptedResource = resource.withMetadata(metadata);

    return _resourceRepository.runInTransaction((DatabaseExecutor txn) async {
      final existingForOperation =
          normalizedKey == null && normalizedSession == null
              ? null
              : await _findAcceptedResourceByOperation(
                  txn,
                  idempotencyKey: normalizedKey,
                  creationSessionId: normalizedSession,
                );
      if (existingForOperation != null) return existingForOperation;

      final targetRows = await txn.query(
        'resources',
        columns: const ['id', 'deleted_at', 'metadata_json'],
        where: 'id = ?',
        whereArgs: [resource.id.value],
        limit: 1,
      );
      if (targetRows.isNotEmpty) {
        final row = targetRows.single;
        if (row['deleted_at'] != null) {
          throw const ResourceTreeConflictException(
            'The accepted resource identity is already in trash',
          );
        }
        final existingMetadata =
            ResourceTreeRowMapper.decodeMetadata(row['metadata_json']);
        if (normalizedKey == null && normalizedSession == null) {
          throw const ResourceTreeConflictException(
            'An accepted resource with this identity already exists; '
            'retry with its idempotency key',
          );
        }
        _ensureExistingIdentity(
          existingMetadata,
          idempotencyKey: normalizedKey,
          creationSessionId: normalizedSession,
        );
        return resource.id;
      }

      await _resourceRepository.createResourceTreeInTransaction(
        txn,
        acceptedResource,
      );
      for (final relationship in requestedRelationships) {
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

  String? _normalizeIdentity(String? value, String field) {
    if (value == null) return null;
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ResourceTreeConflictException('$field must not be empty');
    }
    return normalized;
  }

  Future<ResourceId?> _findAcceptedResourceByOperation(
    DatabaseExecutor txn, {
    required String? idempotencyKey,
    required String? creationSessionId,
  }) async {
    final rows = await txn.query(
      'resources',
      columns: const ['id', 'metadata_json'],
      where: 'deleted_at IS NULL',
    );
    for (final row in rows) {
      final metadata =
          ResourceTreeRowMapper.decodeMetadata(row['metadata_json']);
      final sameOperation = (idempotencyKey != null &&
              metadata[acceptanceIdempotencyKeyMetadata] == idempotencyKey) ||
          (creationSessionId != null &&
              metadata[acceptanceSessionIdMetadata] == creationSessionId);
      if (sameOperation) {
        _ensureExistingIdentity(
          metadata,
          idempotencyKey: idempotencyKey,
          creationSessionId: creationSessionId,
        );
        return ResourceId(row['id'].toString());
      }
    }
    return null;
  }

  void _ensureExistingIdentity(
    Map<String, Object?> metadata, {
    required String? idempotencyKey,
    required String? creationSessionId,
  }) {
    if (idempotencyKey != null &&
        metadata[acceptanceIdempotencyKeyMetadata] != idempotencyKey) {
      throw const ResourceTreeConflictException(
        'The accepted resource identity belongs to another operation',
      );
    }
    if (creationSessionId != null &&
        metadata[acceptanceSessionIdMetadata] != creationSessionId) {
      throw const ResourceTreeConflictException(
        'The accepted resource belongs to another creation session',
      );
    }
  }
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
