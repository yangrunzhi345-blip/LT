import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_trash.dart';

/// Minimal legacy-row tombstone store on the existing `resource_trash` table.
///
/// The heavy tree / revision / assembly pipeline is being retired. What still
/// has to survive a restart is a single fact: "this legacy library row (or
/// adventure) was deleted and must stay hidden until restored". A tombstone is
/// one `resource_trash` row with `restored_at IS NULL`; restoring clears the
/// marker and the legacy row becomes visible again. No content is copied and no
/// tree row is touched.
final class LegacyTombstoneStore {
  LegacyTombstoneStore({required Future<Database> Function() getDb})
      : _getDb = getDb;

  final Future<Database> Function() _getDb;

  static const String table = 'resource_trash';
  static const String migrationsTable = 'resource_migration_records';

  /// Marks one node as deleted and returns its tombstone.
  ///
  /// Idempotent: an active marker for [nodeId] is returned unchanged instead of
  /// inserting a duplicate. [sourceId] is the legacy row id — library ids are
  /// strings while adventure ids are ints, so it is accepted as [Object] and
  /// stored as text.
  Future<TrashDeleteResult> markDeleted({
    required String nodeId,
    required String sourceTable,
    required Object sourceId,
    required String title,
  }) async {
    final db = await _getDb();
    return db.transaction((txn) async {
      final existing = await _activeEntry(txn, nodeId);
      if (existing != null) {
        return TrashDeleteResult(entry: existing, alreadyDeleted: true);
      }

      final now = DateTime.now();
      final sourceIdText = '$sourceId';
      final metadata = <String, Object?>{
        TrashOrigin.metadataOriginKey: TrashOrigin.legacy.storageValue,
        TrashOrigin.metadataSourceTableKey: sourceTable,
        TrashOrigin.metadataSourceIdKey: sourceIdText,
      };
      final trashId = 'trash_${now.microsecondsSinceEpoch}_$nodeId';
      final deletedAt = now.toIso8601String();
      final expiresAt = TrashRetentionPolicy.expiresAt(now).toIso8601String();

      await txn.insert(table, <String, Object?>{
        'trash_id': trashId,
        'resource_id': nodeId,
        'node_id': nodeId,
        'node_kind': RevisionNodeKindRef.resource.storageValue,
        'parent_node_id': '',
        'original_sort_order': 0,
        'original_status': 'draft',
        'original_title': title,
        'reason': TrashReason.userDelete.storageValue,
        'revision_id': '',
        'deleted_at': deletedAt,
        'expires_at': expiresAt,
        'restored_at': null,
        'restore_outcome': '',
        'metadata_json': jsonEncode(metadata),
      });

      return TrashDeleteResult(
        entry: ResourceTrashEntry(
          trashId: trashId,
          resourceId: ResourceId(nodeId),
          nodeId: nodeId,
          nodeKind: RevisionNodeKindRef.resource,
          reason: TrashReason.userDelete,
          deletedAtToken: deletedAt,
          expiresAtToken: expiresAt,
          originalTitle: title,
          metadata: metadata,
        ),
        alreadyDeleted: false,
      );
    });
  }

  /// True when [nodeId] has an unresolved tombstone.
  Future<bool> isDeleted(String nodeId) async {
    final db = await _getDb();
    final rows = await db.query(
      table,
      columns: const <String>['trash_id'],
      where: 'node_id = ? AND restored_at IS NULL',
      whereArgs: <Object?>[nodeId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Clears the unresolved tombstone for [nodeId], if any.
  Future<void> restoreByNodeId(String nodeId) async {
    final db = await _getDb();
    await db.update(
      table,
      <String, Object?>{
        'restored_at': DateTime.now().toIso8601String(),
        'restore_outcome': 'restored',
      },
      where: 'node_id = ? AND restored_at IS NULL',
      whereArgs: <Object?>[nodeId],
    );
  }

  /// Of [candidateIds], the ids currently hidden by an active tombstone.
  ///
  /// Mirrors the retired library bridge: a candidate is hidden both when its
  /// own id carries a legacy marker and when a migration record maps it to a
  /// tree resource whose node id carries an active entry.
  Future<Set<String>> activeNodeIds({
    required String sourceTable,
    required Iterable<String> candidateIds,
  }) async {
    final candidates =
        candidateIds.where((id) => id.isNotEmpty).toSet().toList();
    if (candidates.isEmpty) return const <String>{};

    final db = await _getDb();
    final active = await db.query(
      table,
      columns: const <String>['node_id', 'metadata_json'],
      where: 'restored_at IS NULL',
    );
    if (active.isEmpty) return const <String>{};

    final trashedNodeIds = <String>{};
    final hidden = <String>{};
    for (final row in active) {
      final nodeId = row['node_id']?.toString() ?? '';
      if (nodeId.isEmpty) continue;
      trashedNodeIds.add(nodeId);
      final metadata = _decodeMetadata(row['metadata_json']);
      if (TrashOrigin.fromMetadata(metadata) != TrashOrigin.legacy) continue;
      if (metadata[TrashOrigin.metadataSourceTableKey]?.toString() !=
          sourceTable) {
        continue;
      }
      final sourceId =
          metadata[TrashOrigin.metadataSourceIdKey]?.toString() ?? '';
      if (sourceId.isNotEmpty) hidden.add(sourceId);
    }

    final placeholders = List<String>.filled(candidates.length, '?').join(', ');
    final records = await db.query(
      migrationsTable,
      columns: const <String>['source_id', 'resource_id'],
      where: 'source_table = ? AND source_id IN ($placeholders)',
      whereArgs: <Object?>[sourceTable, ...candidates],
    );
    for (final record in records) {
      final resourceId = record['resource_id']?.toString() ?? '';
      if (resourceId.isEmpty || !trashedNodeIds.contains(resourceId)) continue;
      final sourceId = record['source_id']?.toString() ?? '';
      if (sourceId.isNotEmpty) hidden.add(sourceId);
    }
    return hidden;
  }

  Future<ResourceTrashEntry?> _activeEntry(
    DatabaseExecutor txn,
    String nodeId,
  ) async {
    final rows = await txn.query(
      table,
      where: 'node_id = ? AND restored_at IS NULL',
      whereArgs: <Object?>[nodeId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return ResourceTrashEntry(
      trashId: row['trash_id']?.toString() ?? '',
      resourceId: ResourceId(row['resource_id']?.toString() ?? nodeId),
      nodeId: row['node_id']?.toString() ?? nodeId,
      nodeKind: RevisionNodeKindRef.resource,
      reason: TrashReason.fromStorageValue(row['reason']?.toString()),
      deletedAtToken: row['deleted_at']?.toString() ?? '',
      expiresAtToken: row['expires_at']?.toString() ?? '',
      parentNodeId: row['parent_node_id']?.toString() ?? '',
      originalSortOrder: (row['original_sort_order'] as num?)?.toInt() ?? 0,
      originalTitle: row['original_title']?.toString() ?? '',
      revisionId: row['revision_id']?.toString() ?? '',
      restoredAtToken: row['restored_at']?.toString(),
      restoreOutcome: row['restore_outcome']?.toString() ?? '',
      metadata: _decodeMetadata(row['metadata_json']),
    );
  }

  static Map<String, Object?> _decodeMetadata(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return const <String, Object?>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? Map<String, Object?>.from(decoded)
          : const <String, Object?>{};
    } catch (_) {
      return const <String, Object?>{};
    }
  }
}
