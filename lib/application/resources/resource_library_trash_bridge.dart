import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_trash.dart';
import '../../services/repositories/resource_tree_row_mapper.dart';
import 'legacy_library_row_purger.dart';
import 'resource_trash_service.dart';

/// Outcome of moving one library row's content into the recycle bin.
final class LibraryTrashMoveOutcome {
  const LibraryTrashMoveOutcome({
    required this.entry,
    required this.alreadyDeleted,
    required this.treeBacked,
  });

  final ResourceTrashEntry entry;

  /// True when the resource was already in the bin, so nothing changed.
  final bool alreadyDeleted;

  /// True when a content-tree row was soft deleted; false when the entry is a
  /// marker that hides a legacy row left completely untouched.
  final bool treeBacked;

  /// Message the library shows after a delete. Delete always means "moved to the
  /// recycle bin" now, so this never claims a physical removal.
  String get userMessage => alreadyDeleted ? '该资源已在回收站中' : '已移入回收站，可在「回收站」中恢复';
}

/// Where the content of one library row actually lives.
final class _TrashTarget {
  const _TrashTarget({
    required this.legacyTable,
    required this.title,
    this.treeId,
    this.treeExpectedUpdatedAt,
    this.legacyId,
  });

  /// Content-tree resource id, when one exists.
  final String? treeId;

  /// Optimistic token of the live tree row; null when the row is missing or
  /// already soft deleted.
  final String? treeExpectedUpdatedAt;

  /// Legacy table this row belongs to (`worldview_presets` etc.).
  final String legacyTable;

  /// Legacy row id, **only** when a legacy row is actually involved.
  ///
  /// Deliberately nullable: a tree-only resource must not carry a synthetic link
  /// back to `legacyTable` with the tree id, or a permanent delete would try to
  /// remove a legacy row that may belong to something else.
  final String? legacyId;

  final String title;

  /// True only when there is a **live** tree row that can be soft deleted.
  bool get hasLiveTree => treeId != null && treeExpectedUpdatedAt != null;

  /// True when the content tree copy was migrated from a legacy row, so both
  /// copies exist and a permanent delete has to remove both.
  bool get hasLegacyLink => legacyId != null && legacyId!.isNotEmpty;
}

/// Wires resource-level deletion into the recycle bin for the Resource Library.
///
/// Phase 9's rule is that a delete may never be the step that destroys content,
/// so the library's three `delete*` entry points are rerouted here:
///
/// ```text
/// library row ──▶ resolve where the content lives
///                   ├─ live content tree row  ──▶ trash.deleteNode(treeId)   (soft delete + revision)
///                   └─ legacy-only / no live tree ──▶ trash marker entry      (legacy row untouched)
/// ```
///
/// The legacy tables have no soft-delete column, so a legacy-only resource is
/// hidden from the library by *filtering on the bin* ([hiddenLegacyIds]) instead
/// of by writing to the legacy table. Only an explicit permanent delete calls
/// [purgeLegacyRowInTransaction] — the single place allowed to remove a legacy
/// row while those tables still exist.
final class ResourceLibraryTrashBridge {
  ResourceLibraryTrashBridge({
    required Future<Database> Function() getDb,
    required ResourceTrashService trashService,
  })  : _getDb = getDb,
        _trash = trashService;

  final Future<Database> Function() _getDb;
  final ResourceTrashService _trash;

  /// Legacy tables this bridge is allowed to read/hide.
  ///
  /// Delegates to the purger so the bridge and the permanent-delete path agree
  /// on exactly which tables the recycle bin owns (and which table name may
  /// reach the purge statement).
  static Set<String> get legacyResourceTables =>
      LegacyLibraryRowPurger.legacyResourceTables;

  static const String resourcesTable = 'resources';
  static const String migrationsTable = 'resource_migration_records';
  static const String trashTable = 'resource_trash';

  /// Moves the content behind one library row into the recycle bin.
  Future<LibraryTrashMoveOutcome> moveToTrash({
    required String table,
    required String id,
    String title = '',
  }) async {
    if (!legacyResourceTables.contains(table)) {
      throw ResourceTrashException('未知的资源库表：$table');
    }
    final db = await _getDb();
    final target = await _resolveTarget(db, table: table, id: id, title: title);

    if (target.hasLiveTree) {
      final result = await _trash.deleteNode(
        id: ResourceId(target.treeId!),
        expectedUpdatedAt: target.treeExpectedUpdatedAt!,
        // A migrated resource has a legacy copy too. Recording the link keeps
        // the entry self-describing so a later permanent delete can remove both
        // copies without re-deriving the migration relationship.
        metadata: <String, Object?>{
          if (target.hasLegacyLink) ...<String, Object?>{
            TrashOrigin.metadataSourceTableKey: target.legacyTable,
            TrashOrigin.metadataSourceIdKey: target.legacyId,
          },
        },
      );
      return LibraryTrashMoveOutcome(
        entry: result.entry,
        alreadyDeleted: result.alreadyDeleted,
        treeBacked: true,
      );
    }

    // No live tree row: either the resource was never migrated, its migration
    // failed, its source changed, or its tree disappeared. The legacy row is
    // then the only copy, so the bin gets a marker and the row is left alone.
    final legacyId = target.legacyId ?? id;
    final result = await _trash.deleteLegacyOnlyResource(
      resourceId: target.treeId ?? legacyId,
      sourceTable: target.legacyTable,
      sourceId: legacyId,
      title: target.title,
    );
    return LibraryTrashMoveOutcome(
      entry: result.entry,
      alreadyDeleted: result.alreadyDeleted,
      treeBacked: false,
    );
  }

  /// Ids of [candidateIds] that are currently in the recycle bin.
  ///
  /// Two shapes are hidden, because Phase 9 stopped removing legacy rows:
  /// - the row's own id carries an unresolved marker entry (legacy-only
  ///   resource), and
  /// - the row has a migration record pointing at a tree resource that carries
  ///   an unresolved entry (a migrated resource whose tree row was binned).
  Future<Set<String>> hiddenLegacyIds(
    DatabaseExecutor db, {
    required String table,
    required Iterable<String> candidateIds,
  }) async {
    if (!legacyResourceTables.contains(table)) return const <String>{};
    final active = await db.query(
      trashTable,
      columns: const ['node_id', 'metadata_json'],
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
      if (metadata[TrashOrigin.metadataSourceTableKey]?.toString() != table) {
        continue;
      }
      final sourceId =
          metadata[TrashOrigin.metadataSourceIdKey]?.toString() ?? '';
      if (sourceId.isNotEmpty) hidden.add(sourceId);
    }

    final ids = candidateIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isNotEmpty) {
      final placeholders = List.filled(ids.length, '?').join(', ');
      final records = await db.query(
        migrationsTable,
        columns: const ['source_id', 'resource_id'],
        where: 'source_table = ? AND source_id IN ($placeholders)',
        whereArgs: <Object?>[table, ...ids],
      );
      for (final record in records) {
        final resourceId = record['resource_id']?.toString() ?? '';
        if (resourceId.isEmpty) continue;
        if (trashedNodeIds.contains(resourceId)) {
          final sourceId = record['source_id']?.toString() ?? '';
          if (sourceId.isNotEmpty) hidden.add(sourceId);
        }
      }
    }
    return hidden;
  }

  Future<_TrashTarget> _resolveTarget(
    DatabaseExecutor db, {
    required String table,
    required String id,
    required String title,
  }) async {
    // 1. The library id is itself a content-tree resource id. That covers
    //    pipeline-created resources and every row the library projects under a
    //    tree id, including a migrated resource listed under `res_legacy_*`.
    final directTreeId = await _treeResourceId(db, id);
    if (directTreeId != null) {
      return _TrashTarget(
        treeId: directTreeId,
        treeExpectedUpdatedAt: await _liveToken(db, directTreeId),
        legacyTable: table,
        // Only a real migration link counts; a tree-only resource has no legacy
        // row and must not pretend to have one.
        legacyId: await _legacyIdFor(db, table: table, treeId: directTreeId),
        title: title,
      );
    }

    // 2. The library id is a legacy source id whose migration succeeded: the
    //    content lives in the migrated tree resource.
    final migratedTreeId = await _migratedTreeIdFor(db, table: table, id: id);
    if (migratedTreeId != null) {
      return _TrashTarget(
        treeId: migratedTreeId,
        treeExpectedUpdatedAt: await _liveToken(db, migratedTreeId),
        legacyTable: table,
        legacyId: id,
        title: title,
      );
    }

    // 3. No content tree copy exists at all → marker entry, legacy row kept.
    return _TrashTarget(legacyTable: table, legacyId: id, title: title);
  }

  Future<String?> _treeResourceId(DatabaseExecutor db, String id) async {
    final rows = await db.query(
      resourcesTable,
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id']?.toString();
  }

  /// `updated_at` of a **live** tree row, or null when it is missing/deleted.
  Future<String?> _liveToken(DatabaseExecutor db, String resourceId) async {
    final rows = await db.query(
      resourcesTable,
      columns: const ['updated_at'],
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: <Object?>[resourceId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['updated_at']?.toString();
  }

  /// Legacy row id that a tree resource was migrated from, when known.
  Future<String?> _legacyIdFor(
    DatabaseExecutor db, {
    required String table,
    required String treeId,
  }) async {
    final rows = await db.query(
      migrationsTable,
      columns: const ['source_id'],
      where: 'source_table = ? AND resource_id = ?',
      whereArgs: <Object?>[table, treeId],
      orderBy: 'migration_version DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final sourceId = rows.first['source_id']?.toString() ?? '';
    return sourceId.isEmpty ? null : sourceId;
  }

  /// Tree resource a legacy row was successfully migrated into, when known.
  Future<String?> _migratedTreeIdFor(
    DatabaseExecutor db, {
    required String table,
    required String id,
  }) async {
    final rows = await db.query(
      migrationsTable,
      columns: const ['resource_id'],
      where: 'source_table = ? AND source_id = ? AND status = ? '
          'AND resource_id IS NOT NULL',
      whereArgs: <Object?>[table, id, 'succeeded'],
      orderBy: 'migration_version DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final resourceId = rows.first['resource_id']?.toString() ?? '';
    if (resourceId.isEmpty) return null;
    // A record can outlive its tree row; only report it when the row is there.
    return await _treeResourceId(db, resourceId) == null ? null : resourceId;
  }

  static Map<String, Object?> _decodeMetadata(Object? raw) {
    try {
      return ResourceTreeRowMapper.decodeMetadata(raw);
    } catch (_) {
      // An unreadable marker must not hide anything: treat it as a tree entry.
      return const <String, Object?>{};
    }
  }
}
