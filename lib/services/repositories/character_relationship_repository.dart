import 'package:sqflite/sqflite.dart';

import '../../domain/resources/character_relationship.dart';
import '../../domain/resources/resource_contracts.dart';

abstract interface class CharacterRelationshipRepository {
  Future<CharacterRelationship> create({
    required ResourceId firstResourceId,
    required String firstRole,
    required ResourceId secondResourceId,
    required String secondRole,
    required CharacterRelationshipType relationType,
    String description = '',
  });

  Future<CharacterRelationship?> getById(String id);
  Future<CharacterRelationship?> findBetween(
      ResourceId first, ResourceId second);
  Future<List<CharacterRelationship>> listForResource(ResourceId resourceId);

  Future<CharacterRelationship> update({
    required String id,
    required CharacterRelationshipType relationType,
    required String endpointARole,
    required String endpointBRole,
    required String description,
  });

  Future<void> delete(String id);
  Future<int> deleteForResourcePurge(
    DatabaseExecutor txn,
    ResourceId resourceId,
  );

  Future<CharacterRelationship> createInTransaction(
    DatabaseExecutor txn, {
    required ResourceId firstResourceId,
    required String firstRole,
    required ResourceId secondResourceId,
    required String secondRole,
    required CharacterRelationshipType relationType,
    String description = '',
  });
}

final class CharacterRelationshipRepositoryImpl
    implements CharacterRelationshipRepository {
  CharacterRelationshipRepositoryImpl(
      {required Future<Database> Function() getDb})
      : _getDb = getDb;

  static const table = 'resource_character_relationships';
  final Future<Database> Function() _getDb;

  @override
  Future<CharacterRelationship> create({
    required ResourceId firstResourceId,
    required String firstRole,
    required ResourceId secondResourceId,
    required String secondRole,
    required CharacterRelationshipType relationType,
    String description = '',
  }) async {
    final db = await _getDb();
    return db.transaction((txn) => createInTransaction(
          txn,
          firstResourceId: firstResourceId,
          firstRole: firstRole,
          secondResourceId: secondResourceId,
          secondRole: secondRole,
          relationType: relationType,
          description: description,
        ));
  }

  @override
  Future<CharacterRelationship> createInTransaction(
    DatabaseExecutor txn, {
    required ResourceId firstResourceId,
    required String firstRole,
    required ResourceId secondResourceId,
    required String secondRole,
    required CharacterRelationshipType relationType,
    String description = '',
  }) async {
    final endpoints = CharacterRelationshipEndpoints.canonicalize(
      firstResourceId: firstResourceId,
      firstRole: firstRole,
      secondResourceId: secondResourceId,
      secondRole: secondRole,
    );
    CharacterRelationship.validate(
      relationType: relationType,
      endpointARole: endpoints.aRole,
      endpointBRole: endpoints.bRole,
      description: description,
    );
    await _validateEndpoints(txn, endpoints);
    final existing =
        await _findBetween(txn, endpoints.aResourceId, endpoints.bResourceId);
    if (existing != null) {
      throw const CharacterRelationshipConflictException(
        'A relationship already exists for these endpoints',
      );
    }
    final now = DateTime.now().toIso8601String();
    final id = 'rel_${DateTime.now().microsecondsSinceEpoch}';
    try {
      await txn.insert(table, {
        'id': id,
        'endpoint_a_resource_id': endpoints.aResourceId.value,
        'endpoint_b_resource_id': endpoints.bResourceId.value,
        'relation_type': relationType.storageValue,
        'endpoint_a_role': endpoints.aRole.trim(),
        'endpoint_b_role': endpoints.bRole.trim(),
        'description': description,
        'created_at': now,
        'updated_at': now,
      });
    } on DatabaseException catch (error) {
      if (error.toString().contains('UNIQUE')) {
        throw const CharacterRelationshipConflictException(
          'A relationship already exists for these endpoints',
        );
      }
      rethrow;
    }
    return _readById(txn, id).then((row) => _map(row!));
  }

  @override
  Future<CharacterRelationship?> getById(String id) async {
    final db = await _getDb();
    return _readById(db, id).then((row) => row == null ? null : _map(row));
  }

  @override
  Future<CharacterRelationship?> findBetween(
      ResourceId first, ResourceId second) async {
    final endpoints = CharacterRelationshipEndpoints.canonicalize(
      firstResourceId: first,
      firstRole: 'a',
      secondResourceId: second,
      secondRole: 'b',
    );
    final db = await _getDb();
    final row =
        await _findBetween(db, endpoints.aResourceId, endpoints.bResourceId);
    return row == null ? null : _map(row);
  }

  @override
  Future<List<CharacterRelationship>> listForResource(
      ResourceId resourceId) async {
    final db = await _getDb();
    final rows = await db.rawQuery('''
      SELECT r.* FROM $table r
      JOIN resources a ON a.id = r.endpoint_a_resource_id
      JOIN resources b ON b.id = r.endpoint_b_resource_id
      WHERE (r.endpoint_a_resource_id = ? OR r.endpoint_b_resource_id = ?)
        AND a.deleted_at IS NULL AND b.deleted_at IS NULL
        AND a.type IN ('character', 'npc') AND b.type IN ('character', 'npc')
      ORDER BY r.updated_at DESC, r.id ASC
    ''', [resourceId.value, resourceId.value]);
    return rows.map(_map).toList();
  }

  @override
  Future<CharacterRelationship> update({
    required String id,
    required CharacterRelationshipType relationType,
    required String endpointARole,
    required String endpointBRole,
    required String description,
  }) async {
    CharacterRelationship.validate(
      relationType: relationType,
      endpointARole: endpointARole,
      endpointBRole: endpointBRole,
      description: description,
    );
    final db = await _getDb();
    final count = await db.update(
        table,
        {
          'relation_type': relationType.storageValue,
          'endpoint_a_role': endpointARole.trim(),
          'endpoint_b_role': endpointBRole.trim(),
          'description': description,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id]);
    if (count == 0) {
      throw StateError('Relationship not found: $id');
    }
    return (await getById(id))!;
  }

  @override
  Future<void> delete(String id) async {
    final db = await _getDb();
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<int> deleteForResourcePurge(
      DatabaseExecutor txn, ResourceId resourceId) {
    return txn.delete(table,
        where: 'endpoint_a_resource_id = ? OR endpoint_b_resource_id = ?',
        whereArgs: [resourceId.value, resourceId.value]);
  }

  Future<void> _validateEndpoints(
    DatabaseExecutor db,
    CharacterRelationshipEndpoints endpoints,
  ) async {
    final rows = await db.query('resources',
        columns: ['id', 'type', 'deleted_at'],
        where: 'id IN (?, ?)',
        whereArgs: [endpoints.aResourceId.value, endpoints.bResourceId.value]);
    if (rows.length != 2) {
      throw const CharacterRelationshipValidationException(
        CharacterRelationshipFailure.endpointNotFound,
        'Both relationship endpoints must exist',
      );
    }
    for (final row in rows) {
      final type = row['type']?.toString();
      if (type != 'character' && type != 'npc') {
        throw const CharacterRelationshipValidationException(
          CharacterRelationshipFailure.endpointNotFound,
          'Relationship endpoints must be character resources',
        );
      }
      if (row['deleted_at'] != null) {
        throw const CharacterRelationshipValidationException(
          CharacterRelationshipFailure.endpointNotLive,
          'Relationship endpoints must be live resources',
        );
      }
    }
  }

  Future<Map<String, Object?>?> _findBetween(
    DatabaseExecutor db,
    ResourceId a,
    ResourceId b,
  ) async {
    final rows = await db.query(table,
        where: 'endpoint_a_resource_id = ? AND endpoint_b_resource_id = ?',
        whereArgs: [a.value, b.value],
        limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> _readById(
      DatabaseExecutor db, String id) async {
    final rows =
        await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  CharacterRelationship _map(Map<String, Object?> row) => CharacterRelationship(
        id: row['id'].toString(),
        endpointAResourceId:
            ResourceId(row['endpoint_a_resource_id'].toString()),
        endpointBResourceId:
            ResourceId(row['endpoint_b_resource_id'].toString()),
        relationType: CharacterRelationshipType.fromStorageValue(
          row['relation_type'].toString(),
        ),
        endpointARole: row['endpoint_a_role'].toString(),
        endpointBRole: row['endpoint_b_role'].toString(),
        description: row['description']?.toString() ?? '',
        createdAt: DateTime.parse(row['created_at'].toString()),
        updatedAt: DateTime.parse(row['updated_at'].toString()),
      );
}
