import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_repository.dart';
import '../../domain/resources/resource_revision.dart';
import '../../services/repositories/resource_tree_repository.dart';
import '../../utils/content_hasher.dart';
import 'resource_revision_repository.dart';

/// Revision hooks the Part commit path calls **inside its own transaction**.
///
/// This is the reason the boundary exists as an interface instead of a
/// post-hoc callback: a "before" snapshot taken outside the commit transaction
/// could survive a failed commit and leave a revision that never matched the
/// tree. Calling these on the commit's `DatabaseExecutor` makes the head flip
/// and the content write share one commit or fail together.
abstract interface class IPartCommitRevisionBoundary {
  /// Records the current state as a revision if it is not already the head.
  ///
  /// Idempotent: when the live tree already equals the stored head, nothing is
  /// written. Call it before an overwrite so the previous confirmed content is
  /// always reachable afterwards.
  Future<void> captureBeforeWrite(
    DatabaseExecutor txn, {
    required ResourceId resourceId,
    required RevisionCause cause,
    required String now,
  });

  /// Records the post-write state as the new head.
  Future<void> captureAfterWrite(
    DatabaseExecutor txn, {
    required ResourceId resourceId,
    required RevisionCause cause,
    required String now,
    String label = '',
  });
}

/// Resets generation tasks that a controlled overwrite invalidated.
///
/// A Part whose content was replaced (restore, compression publish, manual
/// rewrite) is no longer "generated from its current source": leaving the task
/// `completed` would make the frozen Phase 5 protocol refuse every later
/// regeneration. This port lets the revision service reopen those tasks in the
/// same transaction without owning the task table.
abstract interface class IGenerationTaskResetPort {
  /// Moves `completed` tasks of [partIds] back to `ready`.
  ///
  /// Returns the ids actually moved. Tasks in any other status are untouched so
  /// an in-flight generation is never hijacked.
  Future<List<String>> reopenCompletedTasksInTransaction(
    DatabaseExecutor txn, {
    required Iterable<String> partIds,
    required String now,
  });
}

/// What one capture did.
final class RevisionCaptureReport {
  const RevisionCaptureReport({
    required this.revision,
    required this.deltaCount,
    required this.wasNoOp,
  });

  /// The revision that is now the head, or null when the live tree was empty
  /// (nothing existed to record).
  final ResourceRevision? revision;

  /// True when the revision already recorded this exact state, so no row was
  /// written. This is what makes repeated captures cheap and duplicate-free.
  final bool wasNoOp;

  final int deltaCount;

  bool get captured => revision != null;
}

/// Result of rolling a resource back to a recorded revision.
final class RevisionRestoreResult {
  const RevisionRestoreResult({
    required this.sourceRevisionId,
    required this.sourceCause,
    required this.alreadyAtRevision,
    required this.restoredNodeCount,
    required this.removedNodeCount,
    required this.reopenedPartIds,
    this.beforeRevisionId,
    this.headRevisionId,
  });

  final ResourceRevisionId sourceRevisionId;
  final RevisionCause sourceCause;

  /// True when the live tree already matched the requested revision, so this
  /// call changed nothing. Repeated restores are therefore idempotent instead
  /// of appending duplicate revisions.
  final bool alreadyAtRevision;

  final int restoredNodeCount;
  final int removedNodeCount;
  final List<String> reopenedPartIds;

  /// Snapshot of the state that the restore replaced, kept so the restore
  /// itself is reversible.
  final ResourceRevisionId? beforeRevisionId;

  /// The new head after the restore.
  final ResourceRevisionId? headRevisionId;
}

/// Result of one retention pass.
final class RevisionPruneReport {
  const RevisionPruneReport({
    required this.deletedRevisions,
    required this.rerootedRevisions,
    required this.protectedRevisions,
    required this.skippedResources,
  });

  final int deletedRevisions;

  /// How many revisions were converted into self-contained roots so the
  /// surviving chain stays replayable.
  final int rerootedRevisions;

  /// Revision ids that were kept even though they are older than the retention
  /// window, because a head, a recycle-bin entry or an assembly pointer still
  /// needs them.
  final List<ResourceRevisionId> protectedRevisions;

  /// Resources whose chain was left alone (missing head or broken chain). A
  /// broken chain is reported instead of silently truncated, because truncating
  /// it would destroy history.
  final List<String> skippedResources;
}

/// Result of publishing a compression candidate as the new head.
final class CompressionPublishResult {
  const CompressionPublishResult({
    required this.candidateId,
    required this.partId,
    required this.alreadyApplied,
    required this.appliedCharacters,
    this.headRevisionId,
  });

  final String candidateId;
  final String partId;

  /// True when the candidate had already been published; the call is still a
  /// success, which keeps "publish twice" idempotent.
  final bool alreadyApplied;

  final int appliedCharacters;
  final ResourceRevisionId? headRevisionId;
}

/// Records immutable revisions and owns the head pointer.
///
/// The invariant this class maintains is "the head revision always describes
/// the current live tree at rest". Every mutation path therefore calls
/// [captureAfterWrite] (or [captureRevision]) after it changed the tree, and a
/// defensive [captureBeforeWrite] before it could lose something. A path that
/// mutates without capturing does not corrupt history: the next capture simply
/// records a bigger delta, which is why a missed hook degrades into a coarser
/// revision rather than into data loss.
final class RevisionCaptureEngine implements IPartCommitRevisionBoundary {
  RevisionCaptureEngine({
    required IResourceRevisionRepository revisionRepository,
    required IResourceTreeRevisionBoundary treeBoundary,
  })  : _revisions = revisionRepository,
        _tree = treeBoundary;

  final IResourceRevisionRepository _revisions;
  final IResourceTreeRevisionBoundary _tree;

  /// Records the live tree as the latest head if it is not already recorded.
  ///
  /// Returns null (and writes nothing) when the resource is missing or soft
  /// deleted: an absent tree has nothing to preserve, and recording an empty
  /// state as the head would erase the last real snapshot.
  Future<ResourceRevision?> captureInTransaction(
    DatabaseExecutor txn, {
    required ResourceId resourceId,
    required RevisionCause cause,
    required String now,
    ResourceRevisionKind kind = ResourceRevisionKind.latestHead,
    String label = '',
  }) async {
    final live = await _tree.readLiveState(txn, resourceId);
    if (live.isEmpty) return null;

    final head = await _revisions.readHeadInTransaction(txn, resourceId, kind);
    final parentState = head == null
        ? const <String, RevisionNodeSnapshot>{}
        : (await _revisions.readStateInTransaction(txn, head.revisionId)).nodes;
    final deltas =
        ResourceRevisionMath.diff(parent: parentState, current: live);
    if (deltas.isEmpty && head != null) return head;

    return _revisions.insertRevisionInTransaction(
      txn,
      resourceId: resourceId,
      kind: kind,
      cause: cause,
      parentRevisionId: head?.revisionId,
      contentHash: hashState(live.values),
      deltas: deltas,
      nodeCount: live.length,
      charCount: _charCount(live.values),
      now: now,
      label: label,
    );
  }

  @override
  Future<void> captureBeforeWrite(
    DatabaseExecutor txn, {
    required ResourceId resourceId,
    required RevisionCause cause,
    required String now,
  }) async {
    await captureInTransaction(txn,
        resourceId: resourceId, cause: cause, now: now);
  }

  @override
  Future<void> captureAfterWrite(
    DatabaseExecutor txn, {
    required ResourceId resourceId,
    required RevisionCause cause,
    required String now,
    String label = '',
  }) async {
    await captureInTransaction(
      txn,
      resourceId: resourceId,
      cause: cause,
      now: now,
      label: label,
    );
  }

  /// Whole-state hash, using the project's single content hasher.
  static String hashState(Iterable<RevisionNodeSnapshot> nodes) =>
      ContentHasher.hash(ResourceRevisionMath.encodeState(nodes));

  static int _charCount(Iterable<RevisionNodeSnapshot> nodes) => nodes
      .where((node) => node.kind == RevisionNodeKind.part)
      .fold(0, (sum, node) => sum + node.content.length);
}

/// Application service of the revision system.
///
/// Implements the frozen [ResourceRevisionSelector] contract (latest head,
/// selection, assembly publication) plus the Phase 9 operations the frozen
/// contract does not cover: capture, restore and retention cleanup.
///
/// Scope note: [select] resolves **revision pointers** (which revision exists,
/// whether the assembly pointer still matches the latest head). It deliberately
/// does not decide whether a resource is ready for Adventure consumption — that
/// policy belongs to Phase 10.
final class ResourceRevisionService implements ResourceRevisionSelector {
  ResourceRevisionService({
    required IResourceRevisionRepository revisionRepository,
    required RevisionCaptureEngine captureEngine,
    required IResourceTreeRevisionBoundary treeBoundary,
    required Future<Database> Function() getDb,
    IGenerationTaskResetPort? taskReset,
    Duration retention = RevisionRetentionPolicy.defaultRetention,
  })  : _revisions = revisionRepository,
        _capture = captureEngine,
        _tree = treeBoundary,
        _getDb = getDb,
        _taskReset = taskReset,
        _retention = retention;

  final IResourceRevisionRepository _revisions;
  final RevisionCaptureEngine _capture;
  final IResourceTreeRevisionBoundary _tree;
  final Future<Database> Function() _getDb;
  final IGenerationTaskResetPort? _taskReset;
  final Duration _retention;

  RevisionCaptureEngine get capture => _capture;

  // ─── Capture ───

  /// Records the current live tree as a revision, if it is not already one.
  Future<RevisionCaptureReport> captureRevision(
    ResourceId resourceId, {
    required RevisionCause cause,
    String label = '',
  }) async {
    final db = await _getDb();
    final now = _now();
    // Read inside the transaction: a head observed outside it can already be a
    // different one by the time the compare-and-set runs, which would make
    // `wasNoOp` a guess rather than a fact (audit P9-I1).
    late RevisionCaptureReport report;
    await db.transaction((txn) async {
      final headBefore = await _revisions.readHeadInTransaction(
        txn,
        resourceId,
        ResourceRevisionKind.latestHead,
      );
      final revision = await _capture.captureInTransaction(
        txn,
        resourceId: resourceId,
        cause: cause,
        now: now,
        label: label,
      );
      report = RevisionCaptureReport(
        revision: revision,
        deltaCount: revision == null ? 0 : revision.nodeCount,
        wasNoOp: revision == null ||
            (headBefore != null &&
                revision.revisionId == headBefore.revisionId),
      );
    });
    return report;
  }

  // ─── Reads ───

  /// Newest-first revision history of one resource.
  Future<List<ResourceRevision>> history(
    ResourceId resourceId, {
    ResourceRevisionKind? kind,
    int limit = 50,
    int offset = 0,
  }) =>
      _revisions.listRevisions(resourceId,
          kind: kind, limit: limit, offset: offset);

  /// How many revisions a resource has.
  Future<int> countRevisions(ResourceId resourceId) =>
      _revisions.countRevisions(resourceId);

  /// Rebuilds the tree recorded by one revision.
  Future<ResourceRevisionState> readState(ResourceRevisionId revisionId) =>
      _revisions.readState(revisionId);

  /// Current optimistic token of one resource, or null when it is gone.
  ///
  /// A caller about to restore reads this first and passes it back as
  /// \`expectedUpdatedAt\`, so the destructive overwrite is guarded by the same
  /// compare-and-set every other Phase 9 write uses (audit P9-M5).
  Future<String?> resourceUpdatedAt(ResourceId resourceId) async {
    final db = await _getDb();
    final timestamps = await db.transaction(
      (txn) => _tree.readNodesTimestamps(txn, resourceId),
    );
    return timestamps?.updatedAt;
  }

  @override
  Future<ResourceRevisionRef?> latestHead(ResourceId resourceId) async {
    final head =
        await _revisions.readHead(resourceId, ResourceRevisionKind.latestHead);
    if (head == null) return null;
    return ResourceRevisionRef(
      resourceId: resourceId,
      revisionId: head.revisionId,
      kind: ResourceRevisionKind.latestHead,
      createdAt: DateTime.tryParse(head.createdAtToken),
    );
  }

  @override
  Future<ResourceRevisionSelection> select(ResourceId resourceId) async {
    final latest =
        await _revisions.readHead(resourceId, ResourceRevisionKind.latestHead);
    final assembly =
        await _revisions.readHead(resourceId, ResourceRevisionKind.assembly);

    if (assembly == null) {
      return ResourceRevisionSelection(
        resourceId: resourceId,
        readiness: ReadinessState.preparing,
        latestHead: latest == null ? null : _ref(latest),
      );
    }

    // Pointer freshness only: a published assembly version is `ready` while it
    // still matches the latest head and `stale` once the head moved on.
    final fresh = latest != null && latest.contentHash == assembly.contentHash;
    return ResourceRevisionSelection(
      resourceId: resourceId,
      readiness: fresh ? ReadinessState.ready : ReadinessState.stale,
      latestHead: latest == null ? null : _ref(latest),
      assemblyRevision: _ref(assembly),
    );
  }

  @override
  Future<void> publishAssemblyRevision({
    required ResourceId resourceId,
    required ResourceRevisionId revisionId,
  }) async {
    final db = await _getDb();
    final source = await _revisions.readRevision(revisionId);
    if (source == null || source.resourceId != resourceId) {
      throw ResourceRevisionNotFoundException(
        'revision ${revisionId.value} 不属于资源 ${resourceId.value}',
      );
    }
    final state = await _revisions.readState(revisionId);
    await db.transaction((txn) async {
      final publication = await txn.query(
        'resource_revisions',
        columns: const ['revision_id'],
        where: 'resource_id = ? AND kind = ? AND content_hash = ?',
        whereArgs: <Object?>[
          resourceId.value,
          ResourceRevisionKind.assembly.storageValue,
          state.contentHash,
        ],
        limit: 1,
      );
      if (publication.isNotEmpty) {
        await _revisions.switchHeadInTransaction(
          txn,
          ResourceRevisionId(publication.first['revision_id'].toString()),
          resourceId: resourceId,
          kind: ResourceRevisionKind.assembly,
        );
        return;
      }
      // An assembly revision is its own chain so the two heads stay
      // independent: publishing never rewrites the latest-head pointer.
      //
      // The delta must be a *diff* against the previous assembly state, not the
      // full target state: a revision stores only what changed, so a node the
      // published state no longer contains has to be written as a tombstone.
      // Storing upserts alone left deleted nodes alive in the reconstructed
      // assembly state (Phase 9 audit P9-M1).
      final previousAssembly = await _revisions.readHeadInTransaction(
        txn,
        resourceId,
        ResourceRevisionKind.assembly,
      );
      final previousState = previousAssembly == null
          ? const <String, RevisionNodeSnapshot>{}
          : (await _revisions.readStateInTransaction(
              txn,
              previousAssembly.revisionId,
            ))
              .nodes;
      final deltas = ResourceRevisionMath.diff(
        parent: previousState,
        current: state.nodes,
      );
      await _revisions.insertRevisionInTransaction(
        txn,
        resourceId: resourceId,
        kind: ResourceRevisionKind.assembly,
        cause: RevisionCause.migration,
        parentRevisionId: previousAssembly?.revisionId,
        contentHash: state.contentHash,
        deltas: deltas,
        nodeCount: state.nodes.length,
        charCount: state.charCount,
        now: _now(),
        label: 'assembly',
      );
    });
  }

  // ─── Restore ───

  /// Rolls the live tree back to [revisionId].
  ///
  /// Runs entirely in one transaction:
  /// 1. records whatever the live tree currently holds (so the restore itself
  ///    is reversible),
  /// 2. applies the target state — creating, reviving and soft deleting nodes,
  /// 3. reopens the generation tasks of Parts whose body changed,
  /// 4. records the post-restore state as the new head.
  ///
  /// Repeating the same restore is a no-op instead of appending duplicates.
  Future<RevisionRestoreResult> restoreRevision(
    ResourceRevisionId revisionId, {
    String expectedUpdatedAt = '',
  }) async {
    final db = await _getDb();
    final now = _now();

    return db.transaction((txn) async {
      final source =
          await _revisions.readRevisionInTransaction(txn, revisionId);
      if (source == null) {
        throw ResourceRevisionNotFoundException(
            'revision 不存在：${revisionId.value}');
      }
      final resourceId = source.resourceId;

      final target = await _revisions.readStateInTransaction(txn, revisionId);
      final live = await _tree.readLiveState(txn, resourceId);
      final liveHash =
          live.isEmpty ? '' : RevisionCaptureEngine.hashState(live.values);
      final head = await _revisions.readHeadInTransaction(
          txn, resourceId, ResourceRevisionKind.latestHead);

      if (head != null &&
          head.contentHash == target.contentHash &&
          liveHash == target.contentHash) {
        return RevisionRestoreResult(
          sourceRevisionId: revisionId,
          sourceCause: source.cause,
          alreadyAtRevision: true,
          restoredNodeCount: 0,
          removedNodeCount: 0,
          reopenedPartIds: const <String>[],
          headRevisionId: head.revisionId,
        );
      }

      if (expectedUpdatedAt.isNotEmpty) {
        final timestamps = await _tree.readNodesTimestamps(
          txn,
          ResourceId(resourceId.value),
        );
        if (timestamps == null) {
          throw ResourceRevisionNotFoundException(
            '资源 ${resourceId.value} 已不存在，无法恢复',
          );
        }
        if (timestamps.updatedAt != expectedUpdatedAt) {
          throw ResourceRevisionConflictException(
            '资源 ${resourceId.value} 已被并发修改（期望 updated_at='
            '$expectedUpdatedAt，实际 ${timestamps.updatedAt}），恢复被拒绝',
          );
        }
      }

      final before = await _capture.captureInTransaction(
        txn,
        resourceId: resourceId,
        cause: RevisionCause.restore,
        now: now,
        label: '恢复前',
      );

      final changedParts = await _applyTargetState(
        txn,
        resourceId: resourceId,
        target: target.nodes,
        now: now,
      );
      final removed =
          live.keys.where((id) => !target.nodes.containsKey(id)).length;

      final reopened = await _reopenTasks(txn, changedParts, now);

      final after = await _capture.captureInTransaction(
        txn,
        resourceId: resourceId,
        cause: RevisionCause.restore,
        now: now,
        label: '恢复到 ${source.cause.displayLabel}',
      );

      return RevisionRestoreResult(
        sourceRevisionId: revisionId,
        sourceCause: source.cause,
        alreadyAtRevision: false,
        restoredNodeCount: target.nodes.length,
        removedNodeCount: removed,
        reopenedPartIds: reopened,
        beforeRevisionId: before?.revisionId,
        headRevisionId: after?.revisionId ?? before?.revisionId,
      );
    });
  }

  // ─── Lossy-operation boundary ───

  /// Prepares a lossy operation: captures the current state and reopens the
  /// generation tasks it is about to replace.
  ///
  /// Call before `regenerate`, `rewrite`, `regenerate all` or any other
  /// operation that overwrites confirmed content. The capture is a no-op when
  /// the head already matches, so calling it twice costs nothing.
  Future<RevisionCaptureReport> beginLossyOperation(
    ResourceId resourceId, {
    required RevisionCause cause,
    Iterable<String> partIds = const <String>[],
    String label = '',
  }) async {
    final db = await _getDb();
    final now = _now();
    final headBefore =
        await _revisions.readHead(resourceId, ResourceRevisionKind.latestHead);
    final reopened = <String>[];
    final revision = await db.transaction((txn) async {
      final captured = await _capture.captureInTransaction(
        txn,
        resourceId: resourceId,
        cause: cause,
        now: now,
        label: label,
      );
      reopened.addAll(await _reopenTasks(txn, partIds.toSet(), now));
      return captured;
    });
    return RevisionCaptureReport(
      revision: revision,
      deltaCount: revision?.nodeCount ?? 0,
      wasNoOp: revision == null ||
          (headBefore != null && revision.revisionId == headBefore.revisionId),
    );
  }

  // ─── Compression publication ───

  /// Applies an already-validated compression candidate as the new head.
  ///
  /// Only part-scoped candidates are publishable: a section-scoped candidate
  /// has no per-Part mapping, so writing it would have to guess which Part
  /// receives which text. Publishing runs through the same revision-state apply
  /// used by restore, so there is exactly one writer of `resource_parts.content`
  /// for this path.
  Future<CompressionPublishResult> publishCompressedContent({
    required String candidateId,
    required String partId,
    required ResourceId resourceId,
    required String compressedContent,
    required int originalCharacters,
    required String expectedSourceToken,
  }) async {
    final db = await _getDb();
    return db.transaction(
      (txn) => publishCompressedContentInTransaction(
        txn,
        candidateId: candidateId,
        partId: partId,
        resourceId: resourceId,
        compressedContent: compressedContent,
        originalCharacters: originalCharacters,
        expectedSourceToken: expectedSourceToken,
      ),
    );
  }

  /// Transaction-scoped variant of [publishCompressedContent].
  ///
  /// Exists so the candidate's `applied_at` claim and the content write share
  /// one commit; the caller (the compression publisher) owns that transaction.
  ///
  /// [expectedSourceToken] is the Part's `updated_at` when the candidate was
  /// generated. A mismatch means the Part moved on (manual edit, autosave,
  /// generation/regeneration commit) and the stale candidate is refused with a
  /// [ResourceTreeConflictException] before any write — so the user's newer text
  /// is preserved and `applied_at` is not left claiming a publication that never
  /// happened.
  Future<CompressionPublishResult> publishCompressedContentInTransaction(
    DatabaseExecutor txn, {
    required String candidateId,
    required String partId,
    required ResourceId resourceId,
    required String compressedContent,
    required int originalCharacters,
    required String expectedSourceToken,
  }) async {
    final now = _now();
    final live = await _tree.readLiveState(txn, resourceId);
    final existing = live[partId];
    if (existing == null) {
      throw ResourceRevisionNotFoundException(
        'Part $partId 不存在或已删除，无法发布压缩结果',
      );
    }
    final timestamps = await _tree.readNodesTimestamps(txn, PartId(partId));
    final liveSourceToken = timestamps?.updatedAt ?? '';
    if (liveSourceToken != expectedSourceToken) {
      throw ResourceTreeConflictException(
        '压缩候选已过期：Part $partId 在候选生成后被修改'
        '（期望 updated_at=$expectedSourceToken，当前=$liveSourceToken），'
        '拒绝覆盖用户新内容',
      );
    }
    if (existing.content == compressedContent) {
      return CompressionPublishResult(
        candidateId: candidateId,
        partId: partId,
        alreadyApplied: true,
        appliedCharacters: compressedContent.length,
      );
    }

    final before = await _capture.captureInTransaction(
      txn,
      resourceId: resourceId,
      cause: RevisionCause.compression,
      now: now,
      label: '压缩前',
    );

    final target = Map<String, RevisionNodeSnapshot>.from(live);
    target[partId] = RevisionNodeSnapshot(
      nodeId: existing.nodeId,
      kind: existing.kind,
      parentNodeId: existing.parentNodeId,
      title: existing.title,
      summary: existing.summary,
      status: existing.status,
      sortOrder: existing.sortOrder,
      content: compressedContent,
      metadata: existing.metadata,
    );

    final changed = await _applyTargetState(
      txn,
      resourceId: resourceId,
      target: target,
      now: now,
    );
    await _reopenTasks(txn, changed, now);

    final after = await _capture.captureInTransaction(
      txn,
      resourceId: resourceId,
      cause: RevisionCause.compression,
      now: now,
      label: '语义压缩（节省 ${originalCharacters - compressedContent.length} 字）',
    );

    return CompressionPublishResult(
      candidateId: candidateId,
      partId: partId,
      alreadyApplied: false,
      appliedCharacters: compressedContent.length,
      headRevisionId: after?.revisionId ?? before?.revisionId,
    );
  }

  // ─── Cleanup ───

  /// Deletes revisions older than the retention window.
  ///
  /// Runs once per chain kind. Both the `latestHead` chain and the `assembly`
  /// chain are deltas against their own parent, so both have to be pruned with
  /// the same "keep the newest prefix, re-root the survivor" rule — otherwise
  /// the assembly chain grows forever while its documented protection is vacuous
  /// (Phase 9 audit P9-M7).
  ///
  /// Only a prefix of a chain is ever removed, and the oldest retained revision
  /// is re-rooted (its delta replaced by a full snapshot) first, so the
  /// surviving chain still replays. Never deleted:
  /// - the current head of the chain being pruned,
  /// - the published `assembly` head (for the latest-head chain),
  /// - revisions referenced by a readiness target or assembly pointer,
  /// - revisions a recycle-bin entry still points at,
  /// - any revision newer than the retention window.
  Future<RevisionPruneReport> pruneRevisions({
    DateTime? now,
    ResourceId? resourceId,
    int maxRevisions = 0,
  }) async {
    final db = await _getDb();
    final clock = now ?? DateTime.now();
    final cutoff = clock.subtract(_retention);

    final resourceIds = <String>[];
    if (resourceId != null) {
      resourceIds.add(resourceId.value);
    } else {
      final rows = await db.rawQuery(
        'SELECT resource_id FROM ${ResourceRevisionRepositoryImpl.revisionsTable} '
        'UNION SELECT resource_id FROM resource_assembly_entries',
      );
      resourceIds.addAll(rows.map((row) => row['resource_id'].toString()));
    }

    var deleted = 0;
    var rerooted = 0;
    final protectedIds = <ResourceRevisionId>[];
    final skipped = <String>[];

    for (final id in resourceIds) {
      final target = ResourceId(id);
      for (final kind in ResourceRevisionKind.values) {
        final result = await db.transaction((txn) async {
          try {
            final report = await _pruneOneChain(
              txn,
              resourceId: target,
              kind: kind,
              cutoff: cutoff,
              maxRevisions: maxRevisions,
            );
            await _deleteOrphanedAssemblyEntries(txn, target);
            return report;
          } on ResourceRevisionException catch (error) {
            // A broken chain is reported, never truncated: destroying history to
            // make a cleanup succeed would be worse than leaving it alone.
            return RevisionPruneReport(
              deletedRevisions: 0,
              rerootedRevisions: 0,
              protectedRevisions: const <ResourceRevisionId>[],
              skippedResources: <String>[
                '$id/${kind.storageValue}: ${error.message}',
              ],
            );
          }
        });
        deleted += result.deletedRevisions;
        rerooted += result.rerootedRevisions;
        protectedIds.addAll(result.protectedRevisions);
        skipped.addAll(result.skippedResources);
      }
    }

    return RevisionPruneReport(
      deletedRevisions: deleted,
      rerootedRevisions: rerooted,
      protectedRevisions: protectedIds,
      skippedResources: skipped,
    );
  }

  Future<RevisionPruneReport> _pruneOneChain(
    DatabaseExecutor txn, {
    required ResourceId resourceId,
    required ResourceRevisionKind kind,
    required DateTime cutoff,
    required int maxRevisions,
  }) async {
    final head = await _revisions.readHeadInTransaction(txn, resourceId, kind);
    if (head == null) {
      return const RevisionPruneReport(
        deletedRevisions: 0,
        rerootedRevisions: 0,
        protectedRevisions: <ResourceRevisionId>[],
        skippedResources: <String>[],
      );
    }

    final protectedIds = <String>{head.revisionId.value};
    final protected = <ResourceRevisionId>[];

    // The two heads are independent chains, but the *latest* head is what the
    // user can still roll back to, so it stays out of the assembly pass too.
    final latestHead = await _revisions.readHeadInTransaction(
      txn,
      resourceId,
      ResourceRevisionKind.latestHead,
    );
    if (latestHead != null && kind != ResourceRevisionKind.latestHead) {
      protectedIds.add(latestHead.revisionId.value);
    }
    final assembly = await _revisions.readHeadInTransaction(
      txn,
      resourceId,
      ResourceRevisionKind.assembly,
    );
    if (assembly != null) {
      protectedIds.add(assembly.revisionId.value);
      protected.add(assembly.revisionId);
    }

    // Readiness can still offer an older assembly while a newer publication
    // exists or preparation is in progress. Protect both persisted pointers.
    final readinessRows = await txn.query(
      'resource_assembly_readiness',
      columns: const ['target_revision_id', 'assembly_revision_id'],
      where: 'resource_id = ?',
      whereArgs: <Object?>[resourceId.value],
    );
    for (final row in readinessRows) {
      for (final column in const [
        'target_revision_id',
        'assembly_revision_id',
      ]) {
        final revisionId = row[column].toString();
        if (revisionId.isEmpty) continue;
        protectedIds.add(revisionId);
        protected.add(ResourceRevisionId(revisionId));
      }
    }

    // A recycle-bin entry that still points at a revision keeps it alive.
    final trashRows = await txn.query(
      'resource_trash',
      columns: const ['revision_id'],
      where: 'resource_id = ? AND restored_at IS NULL AND revision_id != ?',
      whereArgs: <Object?>[resourceId.value, ''],
    );
    for (final row in trashRows) {
      final revisionId = row['revision_id'].toString();
      if (revisionId.isEmpty) continue;
      protectedIds.add(revisionId);
      protected.add(ResourceRevisionId(revisionId));
    }

    final chain = await _revisions.readChainInTransaction(
      txn,
      head.revisionId,
    );

    var keepFrom = chain.length;
    for (var i = 0; i < chain.length; i++) {
      final createdAt = DateTime.tryParse(chain[i].createdAtToken);
      if (createdAt != null && !createdAt.isBefore(cutoff)) {
        keepFrom = i;
        break;
      }
    }
    if (maxRevisions > 0 && chain.length - keepFrom > maxRevisions) {
      keepFrom = chain.length - maxRevisions;
    }
    // A count limit cannot override live references.
    for (var i = 0; i < chain.length; i++) {
      if (protectedIds.contains(chain[i].revisionId.value) && i < keepFrom) {
        keepFrom = i;
      }
    }
    // The head itself is never pruned, whatever the retention window says.
    if (keepFrom > chain.length - 1) keepFrom = chain.length - 1;
    if (keepFrom <= 0) {
      return RevisionPruneReport(
        deletedRevisions: 0,
        rerootedRevisions: 0,
        protectedRevisions: protected,
        skippedResources: const <String>[],
      );
    }

    final rerootTarget = chain[keepFrom];
    final state =
        await _revisions.readStateInTransaction(txn, rerootTarget.revisionId);
    await _revisions.rerootInTransaction(
      txn,
      revisionId: rerootTarget.revisionId,
      contentHash: state.contentHash,
      deltas: state.nodes.values.toList(),
      nodeCount: state.nodes.length,
      charCount: state.charCount,
    );

    final doomed =
        chain.take(keepFrom).map((revision) => revision.revisionId).toList();
    final deleted = await _revisions.deleteRevisionsInTransaction(txn, doomed);

    return RevisionPruneReport(
      deletedRevisions: deleted,
      rerootedRevisions: 1,
      protectedRevisions: protected,
      skippedResources: const <String>[],
    );
  }

  /// Removes documents only once all owners are gone, in the prune transaction.
  /// Also sweeps leftovers from retention passes predating assembly cleanup.
  Future<void> _deleteOrphanedAssemblyEntries(
    DatabaseExecutor txn,
    ResourceId resourceId,
  ) async {
    await txn.rawDelete(
      '''
      DELETE FROM resource_assembly_entries
      WHERE resource_id = ?
        AND NOT EXISTS (
          SELECT 1 FROM resource_revisions r
          WHERE r.revision_id = resource_assembly_entries.revision_id
        )
        AND NOT EXISTS (
          SELECT 1 FROM resource_assembly_readiness ready
          WHERE ready.target_revision_id = resource_assembly_entries.revision_id
             OR ready.assembly_revision_id = resource_assembly_entries.revision_id
        )
        AND NOT EXISTS (
          SELECT 1 FROM resource_trash trash
          WHERE trash.revision_id = resource_assembly_entries.revision_id
            AND trash.restored_at IS NULL
        )
      ''',
      <Object?>[resourceId.value],
    );
  }

  Future<List<String>> _reopenTasks(
    DatabaseExecutor txn,
    Set<String> partIds,
    String now,
  ) async {
    final reset = _taskReset;
    if (reset == null || partIds.isEmpty) return const <String>[];
    return reset.reopenCompletedTasksInTransaction(
      txn,
      partIds: partIds,
      now: now,
    );
  }

  /// Applies a revision state, reporting tree-level failures as revision ones.
  ///
  /// The caller asked for a restore, so a failure caused by the tree being
  /// inconsistent with the revision is a revision-boundary failure. The
  /// original message is preserved verbatim; only the type is normalised, so a
  /// caller can handle "the restore did not happen" without also knowing about
  /// the tree repository's error hierarchy.
  Future<Set<String>> _applyTargetState(
    DatabaseExecutor txn, {
    required ResourceId resourceId,
    required Map<String, RevisionNodeSnapshot> target,
    required String now,
  }) async {
    try {
      return await _tree.applyRevisionState(
        txn,
        resourceId: resourceId,
        target: target,
        now: now,
      );
    } on ResourceTreeException catch (error) {
      throw ResourceRevisionException(error.message);
    }
  }

  ResourceRevisionRef _ref(ResourceRevision revision) => ResourceRevisionRef(
        resourceId: revision.resourceId,
        revisionId: revision.revisionId,
        kind: revision.kind,
        createdAt: DateTime.tryParse(revision.createdAtToken),
      );

  static String _now() => DateTime.now().toIso8601String();
}
