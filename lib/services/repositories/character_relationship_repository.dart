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
    // No join: an endpoint is either a live character/npc resource row or a
    // live character/npc setting card. Joining `resources` would silently hide
    // every edge between native (sc_*) cards.
    final rows = await db.query(
      table,
      where: 'endpoint_a_resource_id = ? OR endpoint_b_resource_id = ?',
      whereArgs: [resourceId.value, resourceId.value],
      orderBy: 'updated_at DESC, id ASC',
    );
    if (rows.isEmpty) return const <CharacterRelationship>[];
    final endpointIds = <String>{
      for (final row in rows) ...[
        row['endpoint_a_resource_id'].toString(),
        row['endpoint_b_resource_id'].toString(),
      ],
    };
    final live = await _liveCharacterEndpoints(db, endpointIds);
    return [
      for (final row in rows)
        if (live.contains(row['endpoint_a_resource_id'].toString()) &&
            live.contains(row['endpoint_b_resource_id'].toString()))
          _map(row),
    ];
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
    final existing = await _readById(db, id);
    if (existing == null) {
      throw const CharacterRelationshipValidationException(
        CharacterRelationshipFailure.relationshipNotFound,
        'Relationship no longer exists',
      );
    }
    await _validateEndpoints(
      db,
      CharacterRelationshipEndpoints.canonicalize(
        firstResourceId:
            ResourceId(existing['endpoint_a_resource_id'].toString()),
        firstRole: endpointARole,
        secondResourceId:
            ResourceId(existing['endpoint_b_resource_id'].toString()),
        secondRole: endpointBRole,
      ),
    );
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
      throw const CharacterRelationshipValidationException(
        CharacterRelationshipFailure.relationshipNotFound,
        'Relationship no longer exists',
      );
    }
    return (await getById(id))!;
  }

  @override
  Future<void> delete(String id) async {
    final db = await _getDb();
    final count = await db.delete(table, where: 'id = ?', whereArgs: [id]);
    if (count == 0) {
      throw const CharacterRelationshipValidationException(
        CharacterRelationshipFailure.relationshipNotFound,
        'Relationship no longer exists',
      );
    }
  }

  @override
  Future<int> deleteForResourcePurge(
      DatabaseExecutor txn, ResourceId resourceId) {
    return txn.delete(table,
        where: 'endpoint_a_resource_id = ? OR endpoint_b_resource_id = ?',
        whereArgs: [resourceId.value, resourceId.value]);
  }

  /// Accepts an endpoint that is either a live character/npc row in
  /// `resources` or a live character/npc row in `setting_cards`.
  ///
  /// Native cards never exist in `resources`, so the resource check alone
  /// would reject every relationship between two cards.
  Future<void> _validateEndpoints(
    DatabaseExecutor db,
    CharacterRelationshipEndpoints endpoints,
  ) async {
    final states = await _endpointStates(
      db,
      <String>{endpoints.aResourceId.value, endpoints.bResourceId.value},
    );
    final ordered = <String>[
      endpoints.aResourceId.value,
      endpoints.bResourceId.value,
    ];
    if (ordered.any((id) => states[id] == _EndpointState.notFound)) {
      throw const CharacterRelationshipValidationException(
        CharacterRelationshipFailure.endpointNotFound,
        'Both relationship endpoints must exist',
      );
    }
    if (ordered.any((id) => states[id] != _EndpointState.live)) {
      throw const CharacterRelationshipValidationException(
        CharacterRelationshipFailure.endpointNotLive,
        'Relationship endpoints must be live resources',
      );
    }
  }

  /// Classifies each candidate id as live / not live / missing.
  ///
  /// A resource row wins when it already satisfies the contract; otherwise the
  /// same id is looked up in `setting_cards` (a soft-deleted card is reported
  /// as not live instead of missing so the caller keeps the existing error
  /// codes).
  Future<Map<String, _EndpointState>> _endpointStates(
    DatabaseExecutor db,
    Set<String> ids,
  ) async {
    if (ids.isEmpty) return const <String, _EndpointState>{};
    final states = <String, _EndpointState>{};
    final unresolved = <String>[];

    final resourceRows = await db.query(
      'resources',
      columns: ['id', 'type', 'deleted_at'],
      where: 'id IN (${_placeholders(ids.length)})',
      whereArgs: ids.toList(),
    );
    for (final row in resourceRows) {
      final id = row['id'].toString();
      final type = row['type']?.toString();
      if ((type == 'character' || type == 'npc') && row['deleted_at'] == null) {
        states[id] = _EndpointState.live;
        continue;
      }
      states[id] = row['deleted_at'] != null
          ? _EndpointState.notLive
          : _EndpointState.notFound;
      unresolved.add(id);
    }
    for (final id in ids) {
      if (states.containsKey(id)) continue;
      states[id] = _EndpointState.notFound;
      unresolved.add(id);
    }

    if (unresolved.isNotEmpty) {
      final cardRows = await db.query(
        'setting_cards',
        columns: ['id', 'kind', 'deleted_at'],
        where: 'id IN (${_placeholders(unresolved.length)})',
        whereArgs: unresolved,
      );
      for (final row in cardRows) {
        final id = row['id'].toString();
        final kind = row['kind']?.toString();
        if (kind != 'character' && kind != 'npc') continue;
        states[id] = row['deleted_at'] == null
            ? _EndpointState.live
            : _EndpointState.notLive;
      }
    }
    return states;
  }

  /// Batch liveness check used by [listForResource].
  Future<Set<String>> _liveCharacterEndpoints(
    DatabaseExecutor db,
    Set<String> ids,
  ) async {
    if (ids.isEmpty) return const <String>{};
    final states = await _endpointStates(db, ids);
    return {
      for (final entry in states.entries)
        if (entry.value == _EndpointState.live) entry.key,
    };
  }

  static String _placeholders(int count) =>
      List<String>.filled(count, '?').join(', ');

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

/// Liveness of one relationship endpoint across both storage surfaces.
enum _EndpointState { live, notLive, notFound }
