import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_revision.dart';
import '../../domain/resources/resource_trash.dart';
import '../../services/repositories/resource_tree_repository.dart';
import 'resource_owned_state_purger.dart';
import 'resource_revision_service.dart';
import 'resource_trash_repository.dart';

/// Result of moving a node to the recycle bin.
final class TrashDeleteResult {
  const TrashDeleteResult({
    required this.entry,
    required this.alreadyDeleted,
    this.headRevisionId,
  });

  final ResourceTrashEntry entry;

  /// True when the node was already in the bin, so this call changed nothing.
  final bool alreadyDeleted;

  /// The revision that is the head after the delete. For a resource delete this
  /// stays at the pre-delete revision, which is what keeps the last live state
  /// of a deleted resource recoverable.
  final ResourceRevisionId? headRevisionId;
}

/// Physically removes one legacy library row.
///
/// Phase 9 must never call this from a normal delete. It exists so the recycle
/// bin's explicit permanent delete is the **only** code path that can destroy a
/// legacy row while the legacy tables still exist (Phase 12 drops them
/// wholesale). Until then a legacy row may be the only copy of a resource whose
/// migration has not happened, has failed, or whose source changed.
abstract interface class ILegacyLibraryRowPort {
  /// Deletes exactly one legacy row inside [txn].
  Future<void> purgeLegacyRowInTransaction(
    DatabaseExecutor txn, {
    required String sourceTable,
    required String sourceId,
  });
}

/// Application service of the recycle bin.
///
/// Delete is always `live → trash`, never `live → gone`:
/// - the bin row records where the node came from and how long it may stay,
/// - the body stays in the tree behind `deleted_at` (or, for a resource whose
///   content only exists in a legacy table, in that table untouched),
/// - a permanent delete is a separate, explicit call.
final class ResourceTrashService {
  ResourceTrashService({
    required IResourceTrashRepository repository,
    required IResourceTreeRevisionBoundary treeBoundary,
    required RevisionCaptureEngine captureEngine,
    required Future<Database> Function() getDb,
    ILegacyLibraryRowPort? legacyRowPort,
    IResourceOwnedStatePort? ownedStatePort,
    Duration retention = TrashRetentionPolicy.retentionPeriod,
  })  : _repository = repository,
        _tree = treeBoundary,
        _capture = captureEngine,
        _getDb = getDb,
        _legacyRowPort = legacyRowPort,
        _ownedStatePort = ownedStatePort,
        _retention = retention;

  final IResourceTrashRepository _repository;
  final IResourceTreeRevisionBoundary _tree;
  final RevisionCaptureEngine _capture;
  final Future<Database> Function() _getDb;
  final ILegacyLibraryRowPort? _legacyRowPort;

  /// Deletes the auxiliary state a purged node owns (revisions, autosaves,
  /// compression jobs, generation tasks, assembly state…) inside the same
  /// transaction as the purge itself (R03-B).
  ///
  /// Nullable only so existing constructions keep compiling; a tree-backed
  /// permanent delete without it fails closed rather than silently leaving
  /// semantically live orphans behind.
  final IResourceOwnedStatePort? _ownedStatePort;
  final Duration _retention;

  /// Recycle-bin contents, newest first.
  Future<List<ResourceTrashEntry>> list({
    ResourceId? resourceId,
    bool includeRestored = false,
    int limit = 200,
    int offset = 0,
  }) =>
      _repository.listEntries(
        resourceId: resourceId,
        includeRestored: includeRestored,
        limit: limit,
        offset: offset,
      );

  /// How many unresolved entries a resource has.
  Future<int> countActive(ResourceId resourceId) =>
      _repository.countActiveEntries(resourceId);

  /// One post-detach snapshot of the node the entry describes.
  Future<ResourceTrashEntry?> findEntry(String trashId) =>
      _repository.findEntry(trashId);

  /// Moves [id] to the recycle bin.
  ///
  /// Runs in one transaction: capture the current state, write the bin row,
  /// soft delete the node, record the resulting head. A failure anywhere rolls
  /// the whole step back, so a node is never deleted without a bin row and a
  /// bin row never exists without a delete.
  Future<TrashDeleteResult> deleteNode({
    required NodeId id,
    required String expectedUpdatedAt,
    TrashReason reason = TrashReason.userDelete,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final db = await _getDb();
    final now = _now();

    return db.transaction((txn) async {
      final placement = await _tree.readNodePlacement(txn, id);
      if (placement == null) {
        throw ResourceTrashNotFoundException('节点不存在，无法删除：${id.value}');
      }
      if (!placement.isLive) {
        final existing = await _repository.findActiveEntryForNodeInTransaction(
            txn, id.value);
        if (existing != null) {
          // Idempotent repeat: the bin already describes this delete.
          return TrashDeleteResult(entry: existing, alreadyDeleted: true);
        }
        // The node may have gone with an ancestor instead of on its own: a
        // cascade delete only writes one entry, for the node the user deleted.
        // In that case the ancestor's entry is the authoritative record, and
        // reporting it is a no-op delete rather than a conflict (audit P9-M6).
        final ancestorEntry = await _findAncestorEntryInTransaction(
          txn,
          placement,
        );
        if (ancestorEntry != null) {
          return TrashDeleteResult(entry: ancestorEntry, alreadyDeleted: true);
        }
        throw ResourceTrashConflictException(
          '节点 ${id.value} 已被删除，但回收站缺少对应记录',
        );
      }
      if (placement.resourceId.isEmpty) {
        throw ResourceTrashException(
          '无法确定节点 ${id.value} 所属资源，拒绝写入回收站',
        );
      }
      final resourceId = ResourceId(placement.resourceId);

      final before = await _capture.captureInTransaction(
        txn,
        resourceId: resourceId,
        cause: RevisionCause.deletion,
        now: now,
        label: '删除前快照',
      );

      final entry = await _repository.insertEntryInTransaction(
        txn,
        resourceId: resourceId,
        nodeId: id,
        reason: reason,
        parentNodeId: placement.parentNodeId,
        originalSortOrder: placement.sortOrder,
        originalStatus: _nodeStatus(placement.status),
        originalTitle: placement.title,
        deletedAtToken: now,
        expiresAtToken: DateTime.now().add(_retention).toIso8601String(),
        revisionId: before?.revisionId.value ?? '',
        metadata: <String, Object?>{
          ...metadata,
          TrashOrigin.metadataOriginKey: TrashOrigin.tree.storageValue,
          'node_kind': placement.nodeKind,
        },
      );

      await _tree.softDeleteNodeInTransaction(
        txn,
        id: id,
        expectedUpdatedAt: expectedUpdatedAt,
        now: now,
      );

      // A resource delete leaves nothing live, so this capture is a no-op for
      // that case and the pre-delete revision stays the head on purpose.
      final after = await _capture.captureInTransaction(
        txn,
        resourceId: resourceId,
        cause: RevisionCause.deletion,
        now: now,
      );

      return TrashDeleteResult(
        entry: entry,
        alreadyDeleted: false,
        headRevisionId: after?.revisionId ?? before?.revisionId,
      );
    });
  }

  /// Moves a resource whose content lives only in a legacy library table into
  /// the bin.
  ///
  /// There is no content-tree row to soft delete and no tree state to snapshot,
  /// so the entry is a **hiding marker**: the legacy row is left completely
  /// untouched and the library listing filters it out while the entry is
  /// unresolved. Restoring clears the marker; only an explicit permanent delete
  /// removes the row.
  ///
  /// This is the deterministic answer for a `ResourceReadFacade` fallback
  /// resource (`notMigrated` / `migrationFailed` / `sourceChanged` /
  /// `treeMissing`). It must never fall through to deleting the legacy row.
  Future<TrashDeleteResult> deleteLegacyOnlyResource({
    required String resourceId,
    required String sourceTable,
    required String sourceId,
    String title = '',
    TrashReason reason = TrashReason.userDelete,
  }) async {
    if (sourceTable.isEmpty || sourceId.isEmpty) {
      throw ResourceTrashException(
        '旧表资源缺少来源信息（table="$sourceTable" id="$sourceId"），拒绝写入回收站',
      );
    }
    final db = await _getDb();
    final now = _now();

    return db.transaction((txn) async {
      final existing = await _repository.findActiveEntryForNodeInTransaction(
        txn,
        sourceId,
      );
      if (existing != null) {
        // Idempotent repeat: the marker already exists.
        return TrashDeleteResult(entry: existing, alreadyDeleted: true);
      }

      final entry = await _repository.insertEntryInTransaction(
        txn,
        resourceId: ResourceId(resourceId),
        nodeId: ResourceId(sourceId),
        reason: reason,
        parentNodeId: '',
        originalSortOrder: 0,
        originalStatus: NodeStatus.draft,
        originalTitle: title,
        deletedAtToken: now,
        expiresAtToken: DateTime.now().add(_retention).toIso8601String(),
        metadata: <String, Object?>{
          TrashOrigin.metadataOriginKey: TrashOrigin.legacy.storageValue,
          TrashOrigin.metadataSourceTableKey: sourceTable,
          TrashOrigin.metadataSourceIdKey: sourceId,
        },
      );
      return TrashDeleteResult(entry: entry, alreadyDeleted: false);
    });
  }

  /// The active bin entry of the nearest deleted ancestor, if any.
  ///
  /// A cascade delete marks every descendant with the same `deleted_at` but
  /// only writes one entry, so a later delete of a descendant has to resolve to
  /// that entry rather than to a conflict.
  Future<ResourceTrashEntry?> _findAncestorEntryInTransaction(
    DatabaseExecutor txn,
    TrashNodePlacement placement,
  ) async {
    final candidates = <String>{
      if (placement.parentNodeId.isNotEmpty) placement.parentNodeId,
      if (placement.resourceId.isNotEmpty) placement.resourceId,
    };
    for (final candidate in candidates) {
      if (candidate == placement.nodeId.value) continue;
      final entry = await _repository.findActiveEntryForNodeInTransaction(
        txn,
        candidate,
      );
      if (entry != null) return entry;
    }
    return null;
  }

  /// Restores one bin entry.
  ///
  /// Deterministic rules, in order:
  /// - already restored → idempotent repeat, nothing is written;
  /// - the node was permanently deleted → explicit failure, the entry stays;
  /// - a Part whose original Section is no longer live → a new Section is
  ///   created under the Resource root and reported as a fallback placement;
  /// - otherwise → the node returns to its original parent and sort order.
  Future<TrashRestoreResult> restore(String trashId) async {
    final db = await _getDb();
    final now = _now();

    return db.transaction((txn) async {
      final entry = await _repository.findEntryInTransaction(txn, trashId);
      if (entry == null) {
        throw ResourceTrashNotFoundException('回收站条目不存在：$trashId');
      }
      if (entry.isRestored) {
        return TrashRestoreResult(
          entry: entry,
          placement: TrashRestorePlacement.alreadyRestored,
          restoredNodeId: entry.nodeId,
        );
      }

      // The claim happens after the placement so the recorded outcome is the
      // real one; it is still safe against a concurrent restore because the
      // guarded `restored_at IS NULL` update is the last write of this
      // transaction — the loser of the race gets 0 rows and rolls back.
      final resourceId = entry.resourceId;

      // A legacy-origin entry never touched the tree, so there is no tree state
      // to snapshot: capturing would either be a no-op or, worse, snapshot an
      // unrelated resource that happens to share the id.
      final treeBacked = !entry.isLegacyOrigin;
      if (treeBacked) {
        await _capture.captureInTransaction(
          txn,
          resourceId: resourceId,
          cause: RevisionCause.restore,
          now: now,
          label: '恢复前',
        );
      }

      final restored = await _placeBack(txn, entry, now);

      if (treeBacked) {
        await _capture.captureInTransaction(
          txn,
          resourceId: resourceId,
          cause: RevisionCause.restore,
          now: now,
          label: restored.label,
        );
      }

      final claimed = await _repository.markRestoredInTransaction(
        txn,
        trashId: trashId,
        now: now,
        outcome: restored.label,
      );
      if (!claimed) {
        throw ResourceTrashConflictException('回收站条目已被并发恢复：$trashId');
      }

      return TrashRestoreResult(
        entry: await _repository.findEntryInTransaction(txn, trashId) ?? entry,
        placement: restored.placement,
        restoredNodeId: entry.nodeId,
        createdSectionId: restored.createdSectionId,
      );
    });
  }

  Future<
      ({
        TrashRestorePlacement placement,
        String label,
        String? createdSectionId,
      })> _placeBack(
    DatabaseExecutor txn,
    ResourceTrashEntry entry,
    String now,
  ) async {
    // A legacy-origin entry is a hiding marker: clearing it is the whole
    // restore. Touching the tree here would be wrong — the row was never
    // soft deleted, and the content is still in the legacy table untouched.
    if (entry.isLegacyOrigin) {
      return (
        placement: TrashRestorePlacement.restoredToLibrary,
        label: TrashRestorePlacement.restoredToLibrary.displayLabel,
        createdSectionId: null,
      );
    }

    switch (entry.nodeKind) {
      case RevisionNodeKindRef.resource:
        final resourceId = ResourceId(entry.nodeId);
        final timestamps = await _tree.readNodesTimestamps(txn, resourceId);
        if (timestamps == null) {
          throw ResourceTrashNotFoundException(
            '资源 ${entry.nodeId} 已被永久删除，无法恢复；回收站条目保留',
          );
        }
        if (timestamps.deletedAt != null) {
          await _tree.reviveNodeInTransaction(
            txn,
            id: resourceId,
            expectedDeletedAt: timestamps.deletedAt!,
            now: now,
          );
        }
        return (
          placement: TrashRestorePlacement.original,
          label: TrashRestorePlacement.original.displayLabel,
          createdSectionId: null,
        );

      case RevisionNodeKindRef.section:
        final sectionId = SectionId(entry.nodeId);
        final timestamps = await _tree.readNodesTimestamps(txn, sectionId);
        if (timestamps == null) {
          throw ResourceTrashNotFoundException(
            'Section ${entry.nodeId} 已被永久删除，无法恢复；回收站条目保留',
          );
        }
        final parent = await _tree.readNodesTimestamps(
          txn,
          ResourceId(entry.parentNodeId),
        );
        if (parent == null) {
          throw ResourceTrashException(
            'Section ${entry.nodeId} 的原所属资源已不存在，无法恢复；'
            '回收站条目保留，未丢失任何数据',
          );
        }
        // R03-B / N5/N7: "row exists" is not "row is live". Restoring a
        // Section under a Resource that is itself still in the bin would
        // recreate a dangling child — visible in no listing, inside a parent
        // the user believes is deleted. The parent must be restored first.
        if (parent.deletedAt != null) {
          throw ResourceTrashConflictException(
            'Section ${entry.nodeId} 的原所属资源 ${entry.parentNodeId} '
            '仍在回收站中，无法恢复；请先恢复该资源',
          );
        }
        if (timestamps.deletedAt != null) {
          await _tree.reviveNodeInTransaction(
            txn,
            id: sectionId,
            expectedDeletedAt: timestamps.deletedAt!,
            now: now,
          );
        }
        return (
          placement: TrashRestorePlacement.original,
          label: TrashRestorePlacement.original.displayLabel,
          createdSectionId: null,
        );

      case RevisionNodeKindRef.part:
        final partId = PartId(entry.nodeId);
        final timestamps = await _tree.readNodesTimestamps(txn, partId);
        if (timestamps == null) {
          throw ResourceTrashNotFoundException(
            'Part ${entry.nodeId} 已被永久删除，无法恢复；回收站条目保留',
          );
        }
        final parentTimestamps = entry.parentNodeId.isEmpty
            ? null
            : await _tree.readNodesTimestamps(
                txn,
                SectionId(entry.parentNodeId),
              );
        final parentIsLive =
            parentTimestamps != null && parentTimestamps.deletedAt == null;
        if (parentIsLive) {
          if (timestamps.deletedAt != null) {
            await _tree.reviveNodeInTransaction(
              txn,
              id: partId,
              expectedDeletedAt: timestamps.deletedAt!,
              now: now,
            );
          }
          return (
            placement: TrashRestorePlacement.original,
            label: TrashRestorePlacement.original.displayLabel,
            createdSectionId: null,
          );
        }

        // Fallback: the original Section is gone or still in the bin, so the
        // Part is placed in a new Section under the Resource root rather than
        // being left invisible inside a deleted parent.
        final resourceTimestamps =
            await _tree.readNodesTimestamps(txn, entry.resourceId);
        if (resourceTimestamps == null) {
          throw ResourceTrashException(
            'Part ${entry.nodeId} 的原所属资源已不存在，无法恢复；'
            '回收站条目保留，未丢失任何数据',
          );
        }
        final section = await _tree.createSectionInTransaction(
          txn,
          resourceId: entry.resourceId,
          title: _fallbackSectionTitle(entry),
          now: now,
        );
        await _tree.reparentNodeInTransaction(
          txn,
          id: partId,
          newParentId: section.value,
          sortOrder: 0,
          now: now,
        );
        return (
          placement: TrashRestorePlacement.recreatedSectionUnderRoot,
          label: TrashRestorePlacement.recreatedSectionUnderRoot.displayLabel,
          createdSectionId: section.value,
        );
    }
  }

  /// Permanently deletes one bin entry and the node behind it.
  ///
  /// This is the explicit second operation: a normal delete only ever reaches
  /// the bin. Calling it twice is idempotent.
  Future<TrashPurgeResult> permanentDelete(String trashId) async {
    final db = await _getDb();
    return db.transaction((txn) async {
      final entry = await _repository.findEntryInTransaction(txn, trashId);
      if (entry == null) {
        return TrashPurgeResult(
          trashId: trashId,
          deletedNodeIds: const <String>[],
          alreadyGone: true,
        );
      }
      if (entry.isRestored) {
        // A restored node is live again; only the audit row is dropped. Refuse
        // to touch the tree, otherwise a stale bin row could delete live data.
        await _repository.deleteEntryInTransaction(txn, trashId);
        return TrashPurgeResult(
          trashId: trashId,
          deletedNodeIds: const <String>[],
          alreadyGone: true,
        );
      }

      if (entry.isLegacyOrigin) {
        return _purgeLegacyEntry(txn, entry);
      }

      final placement = await _tree.readNodePlacement(txn, entry.identity);
      if (placement == null) {
        await _repository.deleteEntryInTransaction(txn, trashId);
        return TrashPurgeResult(
          trashId: trashId,
          deletedNodeIds: const <String>[],
          alreadyGone: true,
        );
      }
      if (placement.isLive) {
        throw ResourceTrashConflictException(
          '节点 ${entry.nodeId} 已回到存活状态，拒绝永久删除',
        );
      }

      // R03-B: auxiliary state and tree rows go in the same transaction. The
      // auxiliary purge runs first so a Section's descendant Part ids remain
      // available for node-scoped cleanup. A resource purge discharges the full
      // ownership (revisions, autosaves, compression, generation, assembly); a
      // Section/Part purge only removes node-scoped rows because the resource
      // itself is still live. Without this, a purged resource leaves
      // semantically live orphans that queries and recovery paths would still
      // report.
      final port = _ownedStatePort;
      if (port == null) {
        throw ResourceTrashException(
          '缺少资源附属状态清理端口，拒绝永久删除（条目 ${entry.trashId}）',
        );
      }
      await port.purgeOwnedStateInTransaction(
        txn,
        resourceId: entry.resourceId.value,
        nodeId: entry.nodeKind == RevisionNodeKindRef.resource
            ? null
            : entry.nodeId,
      );
      await _tree.purgeNodeInTransaction(txn, entry.identity);
      // A migrated resource has two copies. Purging only the tree row would let
      // the legacy copy make the resource reappear in the library, so the link
      // recorded at delete time is purged in the same transaction.
      await _purgeLinkedLegacyRow(txn, entry);
      await _repository.deleteEntryInTransaction(txn, trashId);
      return TrashPurgeResult(
        trashId: trashId,
        deletedNodeIds: <String>[entry.nodeId],
      );
    });
  }

  /// Physically deletes every entry whose retention window has passed.
  ///
  /// Entries still inside their retention window are never touched, which is
  /// the whole point of the recycle bin: a cleanup pass cannot shorten the
  /// recovery window a user was promised.
  Future<int> purgeExpired({DateTime? now}) async {
    final db = await _getDb();
    final clock = now ?? DateTime.now();
    final expired = await db.transaction(
      (txn) => _repository.findExpiredInTransaction(txn, clock),
    );
    var purged = 0;
    for (final entry in expired) {
      final result = await permanentDelete(entry.trashId);
      if (!result.alreadyGone || result.deletedNodeIds.isNotEmpty) {
        purged++;
      }
    }
    return purged;
  }

  /// Physically deletes the legacy row a marker entry hides, then the entry.
  ///
  /// Fails closed when no legacy port is wired: silently dropping the marker
  /// would make the row reappear in the library, and guessing at the table name
  /// would let the bin delete from a table it does not own.
  Future<TrashPurgeResult> _purgeLegacyEntry(
    DatabaseExecutor txn,
    ResourceTrashEntry entry,
  ) async {
    await _purgeLinkedLegacyRow(txn, entry);
    await _repository.deleteEntryInTransaction(txn, entry.trashId);
    return TrashPurgeResult(
      trashId: entry.trashId,
      deletedNodeIds: <String>[entry.linkedSourceId],
    );
  }

  /// Purges the legacy row an entry links to, when it links to one.
  ///
  /// Shared by the two permanent-delete shapes: a marker entry (legacy-only
  /// resource) and a tree entry whose resource also has a legacy copy.
  Future<void> _purgeLinkedLegacyRow(
    DatabaseExecutor txn,
    ResourceTrashEntry entry,
  ) async {
    final table = entry.linkedSourceTable;
    final sourceId = entry.linkedSourceId;
    if (table.isEmpty || sourceId.isEmpty) {
      if (entry.isLegacyOrigin) {
        throw ResourceTrashException(
          '回收站条目 ${entry.trashId} 标记为旧表来源但缺少来源信息，拒绝永久删除',
        );
      }
      return;
    }
    final port = _legacyRowPort;
    if (port == null) {
      throw ResourceTrashException(
        '缺少旧表清理端口，拒绝永久删除（条目 ${entry.trashId} 关联旧表 $table）',
      );
    }
    await port.purgeLegacyRowInTransaction(
      txn,
      sourceTable: table,
      sourceId: sourceId,
    );
  }

  String _fallbackSectionTitle(ResourceTrashEntry entry) {
    final title = entry.originalTitle.trim();
    if (title.isNotEmpty) return '已恢复：$title';
    return '已恢复内容';
  }

  static NodeStatus _nodeStatus(String raw) {
    for (final status in NodeStatus.values) {
      if (status.storageValue == raw) return status;
    }
    return NodeStatus.draft;
  }

  static String _now() => DateTime.now().toIso8601String();
}
