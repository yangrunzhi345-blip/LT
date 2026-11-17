part of 'adventure_repository_impl.dart';

mixin _AdventureRuntimeCheckpointStore on _AdventureRepositoryBase {
  @override
  Future<RuntimeStateCheckpoint> createRuntimeCheckpoint(
      RuntimeStateCheckpoint checkpoint) async {
    final name = checkpoint.name.trim();
    final note = checkpoint.note.trim();
    if (name.isEmpty || name.length > RuntimeStateCheckpoint.maxNameLength) {
      throw ArgumentError.value(checkpoint.name, 'name');
    }
    if (note.length > RuntimeStateCheckpoint.maxNoteLength) {
      throw ArgumentError.value(checkpoint.note, 'note');
    }
    if (checkpoint.revision < 0) {
      throw ArgumentError.value(checkpoint.revision, 'revision');
    }
    final head =
        await getRuntimeHead(checkpoint.adventureId, checkpoint.branchId);
    if (checkpoint.revision > head.revision) {
      throw ArgumentError.value(checkpoint.revision, 'revision', 'beyond HEAD');
    }
    await getRuntimeStateAtRevision(
      adventureId: checkpoint.adventureId,
      branchId: checkpoint.branchId,
      revision: checkpoint.revision,
    );
    final db = await _getDb();
    final now = DateTime.now().toUtc();
    final normalized = RuntimeStateCheckpoint(
      id: checkpoint.id,
      adventureId: checkpoint.adventureId,
      branchId: checkpoint.branchId,
      revision: checkpoint.revision,
      name: name,
      note: note,
      createdAt: checkpoint.createdAt.toUtc(),
      updatedAt: now,
    );
    await db.insert(
        'runtime_state_checkpoints',
        {
          'id': normalized.id,
          'adventure_id': normalized.adventureId,
          'branch_id': normalized.branchId,
          'revision': normalized.revision,
          'name': normalized.name,
          'note': normalized.note,
          'created_at': normalized.createdAt.toIso8601String(),
          'updated_at': normalized.updatedAt.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
    return (await getRuntimeCheckpoint(normalized.id)) ?? normalized;
  }

  RuntimeStateCheckpoint _checkpointFromRow(Map<String, Object?> row) {
    final created = DateTime.tryParse(row['created_at']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final updated =
        DateTime.tryParse(row['updated_at']?.toString() ?? '') ?? created;
    return RuntimeStateCheckpoint(
      id: row['id'].toString(),
      adventureId: (row['adventure_id'] as num).toInt(),
      branchId: (row['branch_id'] as num).toInt(),
      revision: (row['revision'] as num).toInt(),
      name: row['name']?.toString() ?? '',
      note: row['note']?.toString() ?? '',
      createdAt: created,
      updatedAt: updated,
    );
  }

  @override
  Future<List<RuntimeStateCheckpoint>> getRuntimeCheckpoints({
    required int adventureId,
    required int branchId,
    int? beforeRevision,
    int limit = 100,
  }) async {
    final db = await _getDb();
    final rows = await db.query(
      'runtime_state_checkpoints',
      where:
          'adventure_id = ? AND branch_id = ?${beforeRevision == null ? '' : ' AND revision < ?'}',
      whereArgs: [
        adventureId,
        branchId,
        if (beforeRevision != null) beforeRevision
      ],
      orderBy: 'revision DESC',
      limit: limit.clamp(1, 200),
    );
    return List.unmodifiable(rows.map(_checkpointFromRow));
  }

  @override
  Future<RuntimeStateCheckpoint?> getRuntimeCheckpoint(String id) async {
    final db = await _getDb();
    final rows = await db.query('runtime_state_checkpoints',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : _checkpointFromRow(rows.first);
  }

  @override
  Future<void> renameRuntimeCheckpoint(String id, String name) async {
    final value = name.trim();
    if (value.isEmpty || value.length > RuntimeStateCheckpoint.maxNameLength) {
      throw ArgumentError.value(name, 'name');
    }
    final db = await _getDb();
    await db.update('runtime_state_checkpoints',
        {'name': value, 'updated_at': DateTime.now().toUtc().toIso8601String()},
        where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> updateRuntimeCheckpointNote(String id, String note) async {
    final value = note.trim();
    if (value.length > RuntimeStateCheckpoint.maxNoteLength) {
      throw ArgumentError.value(note, 'note');
    }
    final db = await _getDb();
    await db.update('runtime_state_checkpoints',
        {'note': value, 'updated_at': DateTime.now().toUtc().toIso8601String()},
        where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> deleteRuntimeCheckpoint(String id) async {
    final db = await _getDb();
    await db
        .delete('runtime_state_checkpoints', where: 'id = ?', whereArgs: [id]);
  }
}
