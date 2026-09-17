import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_trash.dart';
import '../../services/repositories/resource_tree_row_mapper.dart';

/// Persistence port of the recycle bin.
///
/// The bin stores only metadata. The deleted body stays in `resource_parts`
/// behind `deleted_at`, so a delete never duplicates long text and a restore
/// never replays a serialized tree.
abstract interface class IResourceTrashRepository {
  /// One entry by id, restored or not.
  Future<ResourceTrashEntry?> findEntry(String trashId);

  /// Transaction-scoped variant of [findEntry].
  ///
  /// Callers inside an open transaction MUST use this: reading through the
  /// `Database` object while a transaction holds the connection deadlocks,
  /// because the read waits for the transaction that is waiting for the read.
  Future<ResourceTrashEntry?> findEntryInTransaction(
    DatabaseExecutor db,
    String trashId,
  );

  /// Transaction-scoped variant of [findActiveEntryForNode].
  Future<ResourceTrashEntry?> findActiveEntryForNodeInTransaction(
    DatabaseExecutor db,
    String nodeId,
  );

  /// The unresolved entry for a node, if any.
  ///
  /// This is what makes a repeated delete idempotent instead of producing a
  /// second bin row for the same node.
  Future<ResourceTrashEntry?> findActiveEntryForNode(String nodeId);

  /// Bin contents, newest delete first.
  Future<List<ResourceTrashEntry>> listEntries({
    ResourceId? resourceId,
    bool includeRestored = false,
    int limit = 200,
    int offset = 0,
  });

  /// How many unresolved entries a resource has.
  Future<int> countActiveEntries(ResourceId resourceId);

  /// Inserts a bin row inside a transaction the caller already owns.
  Future<ResourceTrashEntry> insertEntryInTransaction(
    DatabaseExecutor txn, {
    required ResourceId resourceId,
    required NodeId nodeId,
    required TrashReason reason,
    required String parentNodeId,
    required int originalSortOrder,
    required NodeStatus originalStatus,
    required String originalTitle,
    required String deletedAtToken,
    required String expiresAtToken,
    String revisionId = '',
    Map<String, Object?> metadata = const <String, Object?>{},
  });

  /// Marks an unresolved entry as restored.
  ///
  /// Guarded by `restored_at IS NULL`, so two concurrent restores cannot both
  /// claim the same entry; the loser sees 0 rows and reports an idempotent
  /// repeat instead of reviving the node twice.
  Future<bool> markRestoredInTransaction(
    DatabaseExecutor txn, {
    required String trashId,
    required String now,
    required String outcome,
  });

  /// Unresolved entries whose retention deadline has passed.
  Future<List<ResourceTrashEntry>> findExpiredInTransaction(
    DatabaseExecutor txn,
    DateTime now,
  );

  /// Removes one bin row.
  Future<int> deleteEntryInTransaction(DatabaseExecutor txn, String trashId);
}

final class ResourceTrashRepositoryImpl implements IResourceTrashRepository {
  ResourceTrashRepositoryImpl({required Future<Database> Function() getDb})
      : _getDb = getDb;

  final Future<Database> Function() _getDb;

  static const String table = 'resource_trash';

  @override
  Future<ResourceTrashEntry?> findEntry(String trashId) async {
    final db = await _getDb();
    return _findEntry(db, trashId);
  }

  @override
  Future<ResourceTrashEntry?> findEntryInTransaction(
    DatabaseExecutor db,
    String trashId,
  ) =>
      _findEntry(db, trashId);

  @override
  Future<ResourceTrashEntry?> findActiveEntryForNode(String nodeId) async {
    final db = await _getDb();
    return findActiveEntryForNodeInTransaction(db, nodeId);
  }

  @override
  Future<ResourceTrashEntry?> findActiveEntryForNodeInTransaction(
    DatabaseExecutor db,
    String nodeId,
  ) async {
    final rows = await db.query(
      table,
      where: 'node_id = ? AND restored_at IS NULL',
      whereArgs: <Object?>[nodeId],
      limit: 1,
    );
    return rows.isEmpty ? null : _mapEntry(rows.first);
  }

  @override
  Future<List<ResourceTrashEntry>> listEntries({
    ResourceId? resourceId,
    bool includeRestored = false,
    int limit = 200,
    int offset = 0,
  }) async {
    final db = await _getDb();
    final clauses = <String>[];
    final args = <Object?>[];
    if (resourceId != null) {
      clauses.add('resource_id = ?');
      args.add(resourceId.value);
    }
    if (!includeRestored) {
      clauses.add('restored_at IS NULL');
    }
    final rows = await db.query(
      table,
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'deleted_at DESC, trash_id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(_mapEntry).toList();
  }

  @override
  Future<int> countActiveEntries(ResourceId resourceId) async {
    final db = await _getDb();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM $table '
      'WHERE resource_id = ? AND restored_at IS NULL',
      <Object?>[resourceId.value],
    );
    return _intOf(rows.first['cnt']);
  }

  @override
  Future<ResourceTrashEntry> insertEntryInTransaction(
    DatabaseExecutor txn, {
    required ResourceId resourceId,
    required NodeId nodeId,
    required TrashReason reason,
    required String parentNodeId,
    required int originalSortOrder,
    required NodeStatus originalStatus,
    required String originalTitle,
    required String deletedAtToken,
    required String expiresAtToken,
    String revisionId = '',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final nodeKind = RevisionNodeKindRef.of(nodeId);
    final trashId =
        'trash_${DateTime.now().microsecondsSinceEpoch}_${nodeId.value}';
    await txn.insert(table, <String, Object?>{
      'trash_id': trashId,
      'resource_id': resourceId.value,
      'node_id': nodeId.value,
      'node_kind': nodeKind.storageValue,
      'parent_node_id': parentNodeId,
      'original_sort_order': originalSortOrder,
      'original_status': originalStatus.storageValue,
      'original_title': originalTitle,
      'reason': reason.storageValue,
      'revision_id': revisionId,
      'deleted_at': deletedAtToken,
      'expires_at': expiresAtToken,
      'restored_at': null,
      'restore_outcome': '',
      'metadata_json': ResourceTreeRowMapper.encodeMetadata(metadata),
    });
    return ResourceTrashEntry(
      trashId: trashId,
      resourceId: resourceId,
      nodeId: nodeId.value,
      nodeKind: nodeKind,
      parentNodeId: parentNodeId,
      originalSortOrder: originalSortOrder,
      originalStatus: originalStatus,
      originalTitle: originalTitle,
      reason: reason,
      revisionId: revisionId,
      deletedAtToken: deletedAtToken,
      expiresAtToken: expiresAtToken,
      metadata: metadata,
    );
  }

  @override
  Future<bool> markRestoredInTransaction(
    DatabaseExecutor txn, {
    required String trashId,
    required String now,
    required String outcome,
  }) async {
    final updated = await txn.update(
      table,
      <String, Object?>{
        'restored_at': now,
        'restore_outcome': outcome,
      },
      where: 'trash_id = ? AND restored_at IS NULL',
      whereArgs: <Object?>[trashId],
    );
    return updated > 0;
  }

  @override
  Future<List<ResourceTrashEntry>> findExpiredInTransaction(
    DatabaseExecutor txn,
    DateTime now,
  ) async {
    final rows = await txn.query(
      table,
      where: 'restored_at IS NULL AND expires_at <= ?',
      whereArgs: <Object?>[now.toIso8601String()],
      orderBy: 'expires_at ASC, trash_id ASC',
    );
    return rows.map(_mapEntry).toList();
  }

  @override
  Future<int> deleteEntryInTransaction(DatabaseExecutor txn, String trashId) {
    return txn.delete(
      table,
      where: 'trash_id = ?',
      whereArgs: <Object?>[trashId],
    );
  }

  Future<ResourceTrashEntry?> _findEntry(
    DatabaseExecutor db,
    String trashId,
  ) async {
    final rows = await db.query(
      table,
      where: 'trash_id = ?',
      whereArgs: <Object?>[trashId],
      limit: 1,
    );
    return rows.isEmpty ? null : _mapEntry(rows.first);
  }

  ResourceTrashEntry _mapEntry(Map<String, Object?> row) {
    final restoredAt = row['restored_at']?.toString() ?? '';
    return ResourceTrashEntry(
      trashId: row['trash_id'].toString(),
      resourceId: ResourceId(row['resource_id'].toString()),
      nodeId: row['node_id'].toString(),
      nodeKind: RevisionNodeKindRef.fromStorageValue(
        row['node_kind']?.toString(),
      ),
      parentNodeId: row['parent_node_id']?.toString() ?? '',
      originalSortOrder: _intOf(row['original_sort_order']),
      originalStatus: _nodeStatus(row['original_status']?.toString()),
      originalTitle: row['original_title']?.toString() ?? '',
      reason: TrashReason.fromStorageValue(row['reason']?.toString()),
      revisionId: row['revision_id']?.toString() ?? '',
      deletedAtToken: row['deleted_at']?.toString() ?? '',
      expiresAtToken: row['expires_at']?.toString() ?? '',
      restoredAtToken: restoredAt.isEmpty ? null : restoredAt,
      restoreOutcome: row['restore_outcome']?.toString() ?? '',
      metadata: ResourceTreeRowMapper.decodeMetadata(row['metadata_json']),
    );
  }

  static NodeStatus _nodeStatus(String? raw) {
    final value = raw?.trim() ?? '';
    for (final status in NodeStatus.values) {
      if (status.storageValue == value) return status;
    }
    return NodeStatus.draft;
  }

  static int _intOf(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }
}
