part of 'adventure_repository_impl.dart';

mixin _AdventureRuntimeHeadEntityStore on _AdventureRepositoryBase {
  @override
  Future<RuntimeHead> getRuntimeHead(int adventureId, int branchId) async {
    final db = await _getDb();
    final rows = await db.query('adventure_runtime_heads',
        where: 'adventure_id = ? AND branch_id = ?',
        whereArgs: [adventureId, branchId],
        limit: 1);
    if (rows.isEmpty) {
      return RuntimeHead(adventureId: adventureId, branchId: branchId);
    }
    final row = rows.single;
    return RuntimeHead(
      adventureId: adventureId,
      branchId: branchId,
      revision: row['revision'] as int? ?? 0,
      headCommitId: row['head_commit_id'] as String?,
    );
  }

  @override
  Future<List<RuntimeEntityState>> getRuntimeEntities(
    int adventureId,
    int branchId, {
    int? limit,
  }) async {
    final db = await _getDb();
    final rows = await db.query('adventure_runtime_entities',
        where: 'adventure_id = ? AND branch_id = ?',
        whereArgs: [adventureId, branchId],
        orderBy: 'updated_at DESC',
        // Complete state reads must not silently fall back to snapshot values
        // when an older overlay falls outside a display/retrieval limit.
        limit: limit?.clamp(1, 512));
    // Runtime tables are persisted state, so a single legacy/corrupt row must
    // not block the whole adventure's runtime overlay. Skip malformed rows
    // (unknown entity_type, bad state_json) and keep the readable ones.
    final entities = <RuntimeEntityState>[];
    for (final row in rows) {
      final entityType = _runtimeEntityType(row['entity_type']);
      final entityId = JsonValueReader.stringScalar(row['entity_id'])?.trim();
      final overlay = _decodeRuntimeOverlay(row['state_json']);
      if (entityType == null ||
          entityId == null ||
          entityId.isEmpty ||
          overlay == null) {
        debugPrint(
            '[AdventureRepository] skipping malformed runtime entity row '
            'type=${row['entity_type']} id=${row['entity_id']}');
        continue;
      }
      entities.add(RuntimeEntityState(
        entityType: entityType,
        entityId: entityId,
        overlay: overlay,
        lifecycleStatus: row['lifecycle_status'] as String? ?? 'active',
        lastCommitId: row['last_commit_id'] as String?,
      ));
    }
    return entities.toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> getRecentStateChangesForEntity(
    int adventureId,
    int branchId,
    RuntimeEntityType entityType,
    String entityId, {
    int limit = 5,
  }) async {
    final db = await _getDb();
    return db.rawQuery('''
      SELECT c.*, s.change_index, s.path, s.before_json, s.after_json, s.reason
      FROM adventure_state_changes s
      JOIN adventure_state_commits c ON c.id = s.commit_id
      WHERE c.adventure_id = ? AND c.branch_id = ?
        AND s.entity_type = ? AND s.entity_id = ?
      ORDER BY c.revision DESC, s.change_index DESC LIMIT ?
    ''',
        [adventureId, branchId, entityType.name, entityId, limit.clamp(1, 10)]);
  }

  @override
  Future<void> seedRuntimeEntity({
    required int adventureId,
    required int branchId,
    required RuntimeEntityType entityType,
    required String entityId,
  }) async {
    // The seed id is the adventure's own stable identity for the entity —
    // exactly the frozen config's id. Resource ids are opaque strings, so this
    // must use the shared runtime entity id rule rather than an ASCII-only
    // guard, or a real (e.g. imported `name_creator`) card id would abort the
    // whole Adventure creation after its row was already inserted.
    if (!isValidRuntimeEntityId(entityId)) {
      throw ArgumentError.value(entityId, 'entityId');
    }
    final db = await _getDb();
    await db.insert(
        'adventure_runtime_entities',
        {
          'adventure_id': adventureId,
          'branch_id': branchId,
          'entity_type': entityType.name,
          'entity_id': entityId,
          'state_json': '{}',
          'lifecycle_status': 'active',
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert(
      'adventure_runtime_heads',
      {
        'adventure_id': adventureId,
        'branch_id': branchId,
        'revision': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}
