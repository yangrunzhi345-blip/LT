import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_revision.dart';
import '../../utils/content_hasher.dart';
import '../../services/repositories/resource_tree_row_mapper.dart';

/// Persistence port of the immutable revision chain.
///
/// Two properties are the whole point of this port, and both are enforced here
/// rather than by callers:
/// - a revision records only the **delta** against its parent, so recording a
///   checkpoint costs the size of the change instead of the size of the tree;
/// - exactly one revision per `(resource, kind)` carries `is_head = 1`, enforced
///   by a partial unique index, so a lost race cannot produce two heads.
abstract interface class IResourceRevisionRepository {
  /// Current head for [kind], or null when nothing was recorded yet.
  Future<ResourceRevision?> readHead(
      ResourceId resourceId, ResourceRevisionKind kind);

  /// Transaction-scoped variant of [readHead].
  ///
  /// Exists because a head check and the write it guards must share one
  /// transaction, otherwise two concurrent captures could both believe they are
  /// the first to record a revision.
  Future<ResourceRevision?> readHeadInTransaction(
    DatabaseExecutor db,
    ResourceId resourceId,
    ResourceRevisionKind kind,
  );

  /// One revision by id, or null.
  Future<ResourceRevision?> readRevision(ResourceRevisionId revisionId);

  /// Transaction-scoped variant of [readRevision].
  ///
  /// Callers inside an open transaction MUST use this one: reading through the
  /// `Database` object while a transaction holds the connection deadlocks
  /// instead of failing, because the read waits for the transaction that is
  /// waiting for the read.
  Future<ResourceRevision?> readRevisionInTransaction(
    DatabaseExecutor db,
    ResourceRevisionId revisionId,
  );

  /// Newest-first history of one resource.
  Future<List<ResourceRevision>> listRevisions(
    ResourceId resourceId, {
    ResourceRevisionKind? kind,
    int limit = 50,
    int offset = 0,
  });

  /// How many revisions exist for [resourceId].
  Future<int> countRevisions(ResourceId resourceId);

  /// Delta recorded by one revision.
  Future<List<RevisionNodeSnapshot>> readDeltas(ResourceRevisionId revisionId);

  /// Rebuilds the full state at [revisionId] by replaying the parent chain.
  Future<ResourceRevisionState> readState(ResourceRevisionId revisionId);

  /// Rebuilds a state inside a transaction the caller already owns.
  Future<ResourceRevisionState> readStateInTransaction(
    DatabaseExecutor db,
    ResourceRevisionId revisionId,
  );

  /// Inserts one immutable revision and makes it the head of its kind.
  ///
  /// Must run inside [txn]: the head flip and the revision write have to commit
  /// together, otherwise a crash could leave a head pointing at a state that
  /// was never recorded.
  Future<ResourceRevision> insertRevisionInTransaction(
    DatabaseExecutor txn, {
    required ResourceId resourceId,
    required ResourceRevisionKind kind,
    required RevisionCause cause,
    required ResourceRevisionId? parentRevisionId,
    required String contentHash,
    required List<RevisionNodeSnapshot> deltas,
    required int nodeCount,
    required int charCount,
    required String now,
    String label = '',
  });

  /// Moves the head pointer of [revision.kind] to [revision].
  Future<void> switchHeadInTransaction(
    DatabaseExecutor txn,
    ResourceRevisionId revisionId, {
    required ResourceId resourceId,
    required ResourceRevisionKind kind,
  });

  /// Replaces a revision's delta with a full snapshot and clears its parent.
  ///
  /// Used only by cleanup: before the oldest revisions of a chain are deleted,
  /// the oldest retained revision must become self-contained, otherwise the
  /// surviving chain would dangle.
  Future<void> rerootInTransaction(
    DatabaseExecutor txn, {
    required ResourceRevisionId revisionId,
    required String contentHash,
    required List<RevisionNodeSnapshot> deltas,
    required int nodeCount,
    required int charCount,
  });

  /// Deletes revisions and their node deltas (cascade).
  ///
  /// Only non-head revisions can be removed; the guarded `WHERE is_head = 0`
  /// means a stale cleanup decision cannot detach a head pointer.
  Future<int> deleteRevisions(List<ResourceRevisionId> revisionIds);

  /// Transaction-scoped variant of [deleteRevisions].
  Future<int> deleteRevisionsInTransaction(
    DatabaseExecutor txn,
    List<ResourceRevisionId> revisionIds,
  );

  /// Oldest-first parent chain ending at [revisionId].
  Future<List<ResourceRevision>> readChainInTransaction(
    DatabaseExecutor db,
    ResourceRevisionId revisionId, {
    int maxDepth = 512,
  });
}

final class ResourceRevisionRepositoryImpl
    implements IResourceRevisionRepository {
  ResourceRevisionRepositoryImpl({required Future<Database> Function() getDb})
      : _getDb = getDb;

  final Future<Database> Function() _getDb;

  /// Static for the same reason as the tree repository's counter: the revision
  /// repository is a singleton in production, but a second instance must still
  /// not be able to mint a colliding primary key inside one microsecond.
  static int _idSequence = 0;

  static const String revisionsTable = 'resource_revisions';
  static const String nodesTable = 'resource_revision_nodes';

  @override
  Future<ResourceRevision?> readHead(
    ResourceId resourceId,
    ResourceRevisionKind kind,
  ) async {
    final db = await _getDb();
    return _readHead(db, resourceId, kind);
  }

  @override
  Future<ResourceRevision?> readHeadInTransaction(
    DatabaseExecutor db,
    ResourceId resourceId,
    ResourceRevisionKind kind,
  ) =>
      _readHead(db, resourceId, kind);

  @override
  Future<ResourceRevision?> readRevision(ResourceRevisionId revisionId) async {
    final db = await _getDb();
    return _readRevision(db, revisionId.value);
  }

  @override
  Future<ResourceRevision?> readRevisionInTransaction(
    DatabaseExecutor db,
    ResourceRevisionId revisionId,
  ) =>
      _readRevision(db, revisionId.value);

  @override
  Future<List<ResourceRevision>> listRevisions(
    ResourceId resourceId, {
    ResourceRevisionKind? kind,
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await _getDb();
    final rows = await db.query(
      revisionsTable,
      where: kind == null ? 'resource_id = ?' : 'resource_id = ? AND kind = ?',
      whereArgs: kind == null
          ? <Object?>[resourceId.value]
          : <Object?>[resourceId.value, kind.storageValue],
      orderBy: 'created_at DESC, revision_id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(_mapRevision).toList();
  }

  @override
  Future<int> countRevisions(ResourceId resourceId) async {
    final db = await _getDb();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM $revisionsTable WHERE resource_id = ?',
      <Object?>[resourceId.value],
    );
    return _intOf(rows.first['cnt']);
  }

  @override
  Future<List<RevisionNodeSnapshot>> readDeltas(
    ResourceRevisionId revisionId,
  ) async {
    final db = await _getDb();
    return _readDeltas(db, revisionId.value);
  }

  @override
  Future<ResourceRevisionState> readState(ResourceRevisionId revisionId) async {
    final db = await _getDb();
    return readStateInTransaction(db, revisionId);
  }

  @override
  Future<ResourceRevisionState> readStateInTransaction(
    DatabaseExecutor db,
    ResourceRevisionId revisionId,
  ) async {
    final chain = await readChainInTransaction(db, revisionId);
    if (chain.isEmpty) {
      throw ResourceRevisionNotFoundException(
          'revision 不存在：${revisionId.value}');
    }
    var state = <String, RevisionNodeSnapshot>{};
    for (final revision in chain) {
      final deltas = await _readDeltas(db, revision.revisionId.value);
      state = ResourceRevisionMath.applyDelta(state, deltas);
    }
    final target = chain.last;
    return ResourceRevisionState(
      revisionId: target.revisionId,
      contentHash: _hashState(state.values),
      nodes: state,
    );
  }

  @override
  Future<List<ResourceRevision>> readChainInTransaction(
    DatabaseExecutor db,
    ResourceRevisionId revisionId, {
    int maxDepth = 512,
  }) async {
    final chain = <ResourceRevision>[];
    var cursor = revisionId.value;
    final seen = <String>{};
    while (cursor.isNotEmpty) {
      if (!seen.add(cursor)) {
        throw ResourceRevisionCorruptedException(
          'revision 链存在环：$cursor',
        );
      }
      if (chain.length >= maxDepth) {
        throw ResourceRevisionCorruptedException(
          'revision 链深度超过 $maxDepth，拒绝继续回溯',
        );
      }
      final revision = await _readRevision(db, cursor);
      if (revision == null) {
        throw ResourceRevisionNotFoundException(
          'revision 链断裂：找不到 ${cursor.toString()}',
        );
      }
      chain.add(revision);
      cursor = revision.parentRevisionId?.value ?? '';
    }
    return chain.reversed.toList();
  }

  @override
  Future<ResourceRevision> insertRevisionInTransaction(
    DatabaseExecutor txn, {
    required ResourceId resourceId,
    required ResourceRevisionKind kind,
    required RevisionCause cause,
    required ResourceRevisionId? parentRevisionId,
    required String contentHash,
    required List<RevisionNodeSnapshot> deltas,
    required int nodeCount,
    required int charCount,
    required String now,
    String label = '',
  }) async {
    final revisionId = ResourceRevisionId(_newId('rev'));

    // Clear the previous head first so the partial unique index cannot trip.
    await txn.update(
      revisionsTable,
      <String, Object?>{'is_head': 0},
      where: 'resource_id = ? AND kind = ? AND is_head = 1',
      whereArgs: <Object?>[resourceId.value, kind.storageValue],
    );

    await txn.insert(revisionsTable, <String, Object?>{
      'revision_id': revisionId.value,
      'resource_id': resourceId.value,
      'kind': kind.storageValue,
      'cause': cause.storageValue,
      'parent_revision_id': parentRevisionId?.value,
      'content_hash': contentHash,
      'node_count': nodeCount,
      'char_count': charCount,
      'label': label,
      'is_head': 1,
      'created_at': now,
    });

    for (final delta in deltas) {
      await txn.insert(nodesTable, <String, Object?>{
        'revision_id': revisionId.value,
        'node_id': delta.nodeId,
        'node_kind': delta.kind.storageValue,
        'parent_node_id': delta.parentNodeId,
        'title': delta.title,
        'summary': delta.summary,
        'status': delta.status.storageValue,
        'sort_order': delta.sortOrder,
        'content': delta.content,
        'content_hash': delta.contentHash,
        'metadata_json': ResourceTreeRowMapper.encodeMetadata(delta.metadata),
        'is_removed': delta.isRemoved ? 1 : 0,
      });
    }

    return ResourceRevision(
      revisionId: revisionId,
      resourceId: resourceId,
      kind: kind,
      cause: cause,
      parentRevisionId: parentRevisionId,
      contentHash: contentHash,
      nodeCount: nodeCount,
      charCount: charCount,
      label: label,
      isHead: true,
      createdAtToken: now,
    );
  }

  @override
  Future<void> switchHeadInTransaction(
    DatabaseExecutor txn,
    ResourceRevisionId revisionId, {
    required ResourceId resourceId,
    required ResourceRevisionKind kind,
  }) async {
    await txn.update(
      revisionsTable,
      <String, Object?>{'is_head': 0},
      where: 'resource_id = ? AND kind = ? AND is_head = 1',
      whereArgs: <Object?>[resourceId.value, kind.storageValue],
    );
    final updated = await txn.update(
      revisionsTable,
      <String, Object?>{'is_head': 1},
      where: 'revision_id = ? AND resource_id = ? AND kind = ?',
      whereArgs: <Object?>[
        revisionId.value,
        resourceId.value,
        kind.storageValue
      ],
    );
    if (updated == 0) {
      throw ResourceRevisionNotFoundException(
        '无法切换 head：revision ${revisionId.value} 不属于资源 '
        '${resourceId.value} 的 ${kind.storageValue}',
      );
    }
  }

  @override
  Future<void> rerootInTransaction(
    DatabaseExecutor txn, {
    required ResourceRevisionId revisionId,
    required String contentHash,
    required List<RevisionNodeSnapshot> deltas,
    required int nodeCount,
    required int charCount,
  }) async {
    await txn.delete(
      nodesTable,
      where: 'revision_id = ?',
      whereArgs: <Object?>[revisionId.value],
    );
    for (final delta in deltas) {
      await txn.insert(nodesTable, <String, Object?>{
        'revision_id': revisionId.value,
        'node_id': delta.nodeId,
        'node_kind': delta.kind.storageValue,
        'parent_node_id': delta.parentNodeId,
        'title': delta.title,
        'summary': delta.summary,
        'status': delta.status.storageValue,
        'sort_order': delta.sortOrder,
        'content': delta.content,
        'content_hash': delta.contentHash,
        'metadata_json': ResourceTreeRowMapper.encodeMetadata(delta.metadata),
        'is_removed': delta.isRemoved ? 1 : 0,
      });
    }
    await txn.update(
      revisionsTable,
      <String, Object?>{
        'parent_revision_id': null,
        'content_hash': contentHash,
        'node_count': nodeCount,
        'char_count': charCount,
      },
      where: 'revision_id = ?',
      whereArgs: <Object?>[revisionId.value],
    );
  }

  @override
  Future<int> deleteRevisions(List<ResourceRevisionId> revisionIds) async {
    final db = await _getDb();
    return deleteRevisionsInTransaction(db, revisionIds);
  }

  @override
  Future<int> deleteRevisionsInTransaction(
    DatabaseExecutor txn,
    List<ResourceRevisionId> revisionIds,
  ) async {
    if (revisionIds.isEmpty) return 0;
    var deleted = 0;
    for (final id in revisionIds) {
      deleted += await txn.delete(
        revisionsTable,
        where: 'revision_id = ? AND is_head = 0',
        whereArgs: <Object?>[id.value],
      );
    }
    return deleted;
  }

  // ─── internals ───

  Future<ResourceRevision?> _readHead(
    DatabaseExecutor db,
    ResourceId resourceId,
    ResourceRevisionKind kind,
  ) async {
    final rows = await db.query(
      revisionsTable,
      where: 'resource_id = ? AND kind = ? AND is_head = 1',
      whereArgs: <Object?>[resourceId.value, kind.storageValue],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _mapRevision(rows.first);
  }

  Future<ResourceRevision?> _readRevision(
    DatabaseExecutor db,
    String revisionId,
  ) async {
    final rows = await db.query(
      revisionsTable,
      where: 'revision_id = ?',
      whereArgs: <Object?>[revisionId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _mapRevision(rows.first);
  }

  Future<List<RevisionNodeSnapshot>> _readDeltas(
    DatabaseExecutor db,
    String revisionId,
  ) async {
    final rows = await db.query(
      nodesTable,
      where: 'revision_id = ?',
      whereArgs: <Object?>[revisionId],
      orderBy: 'node_kind ASC, sort_order ASC, node_id ASC',
    );
    return rows.map(_mapNode).toList();
  }

  ResourceRevision _mapRevision(Map<String, Object?> row) {
    final kind = row['kind']?.toString() ?? '';
    final parent = row['parent_revision_id']?.toString() ?? '';
    return ResourceRevision(
      revisionId: ResourceRevisionId(row['revision_id'].toString()),
      resourceId: ResourceId(row['resource_id'].toString()),
      kind: kind == ResourceRevisionKind.assembly.storageValue
          ? ResourceRevisionKind.assembly
          : ResourceRevisionKind.latestHead,
      cause: RevisionCause.fromStorageValue(row['cause']?.toString()),
      parentRevisionId: parent.isEmpty ? null : ResourceRevisionId(parent),
      contentHash: row['content_hash']?.toString() ?? '',
      nodeCount: _intOf(row['node_count']),
      charCount: _intOf(row['char_count']),
      label: row['label']?.toString() ?? '',
      isHead: _intOf(row['is_head']) == 1,
      createdAtToken: row['created_at']?.toString() ?? '',
    );
  }

  RevisionNodeSnapshot _mapNode(Map<String, Object?> row) {
    final kind = RevisionNodeKind.fromStorageValue(
      row['node_kind']?.toString(),
    );
    if (kind == null) {
      throw ResourceRevisionCorruptedException(
        '未知的 revision 节点类型：${row['node_kind']}',
      );
    }
    return RevisionNodeSnapshot(
      nodeId: row['node_id'].toString(),
      kind: kind,
      parentNodeId: row['parent_node_id']?.toString() ?? '',
      title: row['title']?.toString() ?? '',
      summary: row['summary']?.toString() ?? '',
      status: _nodeStatus(row['status']?.toString()),
      sortOrder: _intOf(row['sort_order']),
      content: row['content']?.toString() ?? '',
      contentHash: row['content_hash']?.toString() ?? '',
      metadata: ResourceTreeRowMapper.decodeMetadata(row['metadata_json']),
      isRemoved: _intOf(row['is_removed']) == 1,
    );
  }

  static NodeStatus _nodeStatus(String? raw) {
    final value = raw?.trim() ?? '';
    for (final status in NodeStatus.values) {
      if (status.storageValue == value) return status;
    }
    return NodeStatus.draft;
  }

  /// Whole-state hash. Uses the project's single hasher over the canonical
  /// encoding produced by the contract layer.
  static String _hashState(Iterable<RevisionNodeSnapshot> nodes) =>
      ContentHasher.hash(ResourceRevisionMath.encodeState(nodes));

  static int _intOf(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  String _newId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${++_idSequence}';
}
