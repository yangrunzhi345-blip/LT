import 'resource_contracts.dart';

/// Base type for revision-boundary failures.
class ResourceRevisionException implements Exception {
  const ResourceRevisionException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when a revision is expected to exist but does not.
class ResourceRevisionNotFoundException extends ResourceRevisionException {
  const ResourceRevisionNotFoundException(super.message);
}

/// Thrown when a revision write loses an optimistic-locking race, or when the
/// caller's expected head no longer matches the stored head.
class ResourceRevisionConflictException extends ResourceRevisionException {
  const ResourceRevisionConflictException(super.message);
}

/// Thrown when a revision is written whose delta does not describe the change
/// its parent implies.
///
/// Catching this at the write boundary is what keeps "a non-root revision stores
/// the difference from its parent" a real invariant instead of a convention: an
/// upsert-only delta attached to a non-null parent silently resurrects deleted
/// nodes when the chain is replayed.
class ResourceRevisionDeltaException extends ResourceRevisionException {
  const ResourceRevisionDeltaException(super.message);
}

/// Thrown when a stored revision row cannot be mapped back into the domain.
class ResourceRevisionCorruptedException extends ResourceRevisionException {
  const ResourceRevisionCorruptedException(super.message);
}

/// Canonical lifecycle position of a resource (R03).
///
/// `live → soft-deleted/trash → restore → live` or
/// `soft-deleted/trash → permanent delete → gone`. A revision is the history of
/// a live resource; reaching a non-live state through revision operations is a
/// contract violation, not a rollback path.
enum ResourceLifecycleState {
  /// The canonical row exists and `deleted_at` is null.
  live,

  /// The canonical row exists but sits in the recycle bin (`deleted_at` set).
  trashed,

  /// The canonical row no longer exists (permanently deleted).
  gone;

  String get displayLabel => switch (this) {
        ResourceLifecycleState.live => '存活',
        ResourceLifecycleState.trashed => '回收站',
        ResourceLifecycleState.gone => '已永久删除',
      };
}

/// Thrown when a revision operation is refused because the target resource is
/// not live: it sits in the recycle bin or has been permanently deleted.
///
/// Restoring a revision must never be the side door that flips `deleted_at`
/// back to null; recovery from the bin has to go through the explicit trash
/// restore first (R03-C / CP-2).
class ResourceRevisionLifecycleException extends ResourceRevisionException {
  const ResourceRevisionLifecycleException(
    super.message, {
    required this.resourceId,
    required this.state,
  });

  final String resourceId;
  final ResourceLifecycleState state;
}

/// Why a revision was recorded.
///
/// The set is deliberately explicit: a later phase must add a value here (and
/// therefore change this file) instead of overloading an existing cause.
enum RevisionCause {
  /// A user-confirmed save (autosave final flush, explicit save).
  manualSave,

  /// A generation commit that produced previously absent content.
  generation,

  /// A blueprint/outline write: the planning stage creates or replaces the tree
  /// of placeholder nodes before any prose exists.
  planning,

  /// A regeneration / rewrite / expand / condense of already confirmed content.
  regeneration,

  /// Publishing a semantic-compression candidate as the new head.
  compression,

  /// Rolling a resource back to a previously recorded revision.
  restore,

  /// A legacy-migration write.
  migration,

  /// A delete operation that captured the state before it became lossy.
  deletion;

  String get storageValue => name;

  static RevisionCause fromStorageValue(String? raw) {
    final value = raw?.trim() ?? '';
    for (final cause in RevisionCause.values) {
      if (cause.name == value) return cause;
    }
    return RevisionCause.manualSave;
  }

  /// Human label used by the revision-history UI.
  String get displayLabel => switch (this) {
        RevisionCause.manualSave => '手动保存',
        RevisionCause.generation => 'AI 生成',
        RevisionCause.planning => '大纲规划',
        RevisionCause.regeneration => '重新生成',
        RevisionCause.compression => '语义压缩',
        RevisionCause.restore => '版本恢复',
        RevisionCause.migration => '数据迁移',
        RevisionCause.deletion => '删除前快照',
      };
}

/// What kind of node a revision snapshot entry describes.
enum RevisionNodeKind {
  resource,
  section,
  part;

  String get storageValue => name;

  static RevisionNodeKind? fromStorageValue(String? raw) {
    final value = raw?.trim() ?? '';
    for (final kind in RevisionNodeKind.values) {
      if (kind.name == value) return kind;
    }
    return null;
  }

  static RevisionNodeKind? of(NodeId id) => switch (id) {
        ResourceId() => RevisionNodeKind.resource,
        SectionId() => RevisionNodeKind.section,
        PartId() => RevisionNodeKind.part,
      };
}

/// One node as recorded inside a revision delta.
///
/// The snapshot is intentionally shaped like the stored tree row: it must be
/// enough to re-create the node verbatim on restore without reading the live
/// tree, which is what keeps a revision an independent, immutable record.
final class RevisionNodeSnapshot {
  const RevisionNodeSnapshot({
    required this.nodeId,
    required this.kind,
    required this.parentNodeId,
    required this.title,
    required this.sortOrder,
    this.summary = '',
    this.status = NodeStatus.draft,
    this.content = '',
    this.contentHash = '',
    this.metadata = const <String, Object?>{},
    this.isRemoved = false,
  }) : assert(sortOrder >= 0, 'sortOrder must not be negative');

  final String nodeId;
  final RevisionNodeKind kind;

  /// Owning resource id for sections, owning section id for parts, empty for
  /// the resource root.
  final String parentNodeId;

  final String title;
  final String summary;
  final NodeStatus status;
  final int sortOrder;

  /// Part body. Empty for resources and sections (ADR-0001 §4: long text only
  /// ever belongs to a Part).
  final String content;
  final String contentHash;

  /// Resource metadata only; empty for sections and parts.
  final Map<String, Object?> metadata;

  /// True when the node did not exist in this revision's state. A tombstone is
  /// what makes "restore back to before a Section was created" expressible.
  final bool isRemoved;

  NodeId get nodeIdentity => switch (kind) {
        RevisionNodeKind.resource => ResourceId(nodeId),
        RevisionNodeKind.section => SectionId(nodeId),
        RevisionNodeKind.part => PartId(nodeId),
      };

  /// Identity comparison used by the diff that produces a delta.
  ///
  /// Two snapshots describe the same node state when every persisted field
  /// matches; [nodeId] is excluded because a map lookup already fixes it.
  bool hasSameState(RevisionNodeSnapshot other) =>
      kind == other.kind &&
      parentNodeId == other.parentNodeId &&
      title == other.title &&
      summary == other.summary &&
      status == other.status &&
      sortOrder == other.sortOrder &&
      content == other.content &&
      contentHash == other.contentHash &&
      _sameMetadata(metadata, other.metadata);

  static bool _sameMetadata(
    Map<String, Object?> a,
    Map<String, Object?> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      final left = entry.value;
      final right = b[entry.key];
      if (left is Map && right is Map) {
        if (!_sameMetadata(
          left.map((k, v) => MapEntry(k.toString(), v as Object?)),
          right.map((k, v) => MapEntry(k.toString(), v as Object?)),
        )) {
          return false;
        }
        continue;
      }
      if (left != right) return false;
    }
    return true;
  }

  @override
  String toString() =>
      'RevisionNodeSnapshot($nodeId, ${kind.storageValue}, removed=$isRemoved)';
}

/// Immutable metadata of one recorded revision.
final class ResourceRevision {
  const ResourceRevision({
    required this.revisionId,
    required this.resourceId,
    required this.kind,
    required this.cause,
    required this.isHead,
    required this.createdAtToken,
    this.parentRevisionId,
    this.contentHash = '',
    this.nodeCount = 0,
    this.charCount = 0,
    this.label = '',
  });

  final ResourceRevisionId revisionId;
  final ResourceId resourceId;

  /// [ResourceRevisionKind.latestHead] is the user's newest saved state;
  /// [ResourceRevisionKind.assembly] is the version Runtime may consume. Both
  /// are revision rows; only the head pointer differs.
  final ResourceRevisionKind kind;

  final RevisionCause cause;

  /// Null only for the root of a chain (a full snapshot). Cleanup re-roots the
  /// oldest retained revision, so the chain never dangles.
  final ResourceRevisionId? parentRevisionId;

  /// Hash of the whole reconstructed tree at this revision, computed by the
  /// repository with the project's single content hasher.
  final String contentHash;

  final int nodeCount;
  final int charCount;

  /// Optional caller label ("压缩前" / "角色卡导入前").
  final String label;

  final bool isHead;

  /// Storage timestamp; ISO-8601 string, matching the tree tables' convention.
  final String createdAtToken;

  ResourceRevision copyWith({
    bool? isHead,
    ResourceRevisionId? parentRevisionId,
    String? contentHash,
    int? nodeCount,
    int? charCount,
  }) =>
      ResourceRevision(
        revisionId: revisionId,
        resourceId: resourceId,
        kind: kind,
        cause: cause,
        parentRevisionId: parentRevisionId ?? this.parentRevisionId,
        contentHash: contentHash ?? this.contentHash,
        nodeCount: nodeCount ?? this.nodeCount,
        charCount: charCount ?? this.charCount,
        label: label,
        isHead: isHead ?? this.isHead,
        createdAtToken: createdAtToken,
      );

  @override
  String toString() =>
      'ResourceRevision(${revisionId.value}, ${cause.storageValue}, '
      'head=$isHead)';
}

/// One recorded revision together with the delta it applies to its parent.
final class ResourceRevisionRecord {
  const ResourceRevisionRecord({
    required this.revision,
    required this.deltas,
  });

  final ResourceRevision revision;

  /// Only the nodes that differ from `revision.parentRevisionId`, ordered by
  /// `(kind, sortOrder, nodeId)` for deterministic replay.
  final List<RevisionNodeSnapshot> deltas;
}

/// A reconstructed tree state at one revision.
final class ResourceRevisionState {
  const ResourceRevisionState({
    required this.revisionId,
    required this.contentHash,
    required this.nodes,
  });

  final ResourceRevisionId revisionId;

  /// Whole-tree hash of this state.
  final String contentHash;

  /// Node snapshots by node id. Removed nodes are absent, not tombstoned: a
  /// state is a plain view of what existed at that revision.
  final Map<String, RevisionNodeSnapshot> nodes;

  bool get isEmpty => nodes.isEmpty;

  int get charCount => nodes.values
      .where((node) => node.kind == RevisionNodeKind.part)
      .fold(0, (sum, node) => sum + node.content.length);

  /// Rebuilds the frozen tree value object, or null when the state has no root.
  ///
  /// Returns null instead of throwing so a caller can distinguish "the revision
  /// does not describe a resource root" from "the data is corrupt".
  ResourceTree? toResourceTree() {
    final root = nodes.values
        .where((node) => node.kind == RevisionNodeKind.resource)
        .firstOrNull;
    if (root == null) return null;

    final sections = nodes.values
        .where((node) =>
            node.kind == RevisionNodeKind.section &&
            node.parentNodeId == root.nodeId)
        .map((node) => ResourceSection(
              id: SectionId(node.nodeId),
              resourceId: ResourceId(root.nodeId),
              title: node.title,
              summary: node.summary,
              sortOrder: node.sortOrder,
              status: node.status,
            ))
        .toList();

    final parts = nodes.values
        .where((node) => node.kind == RevisionNodeKind.part)
        .map((node) => ResourcePart(
              id: PartId(node.nodeId),
              sectionId: SectionId(node.parentNodeId),
              title: node.title,
              content: node.content,
              sortOrder: node.sortOrder,
              status: node.status,
              contentHash: node.contentHash,
            ))
        .toList();

    return ResourceTree(
      resource: Resource(
        id: ResourceId(root.nodeId),
        type: ResourceType.fromStorageValue(
          root.metadata['type']?.toString(),
        ),
        name: root.title,
        summary: root.summary,
        metadata: root.metadata,
        status: root.status,
      ),
      sections: sections,
      parts: parts,
    );
  }

  RevisionNodeSnapshot? nodeOf(String nodeId) => nodes[nodeId];
}

/// Retention policy of the revision history.
///
/// Lives here so the service, the cleanup pass and the tests read one number
/// instead of restating it, and so a later phase changes it deliberately.
abstract final class RevisionRetentionPolicy {
  /// How long a superseded revision is kept before cleanup may prune it.
  static const Duration defaultRetention = Duration(days: 90);

  /// Hard cap on how far a parent chain may be replayed.
  ///
  /// A chain deeper than this is treated as corrupt instead of being followed
  /// forever, which turns a data problem into a reported error rather than a
  /// hang.
  static const int maxChainDepth = 512;
}

/// Pure helpers shared by the revision repository and its callers.
///
/// Lives in the domain layer so the delta/replay rules are testable without a
/// database and cannot drift between the writer and the reader. Hashing itself
/// stays in the repository layer, because the contract layer must not depend on
/// the project's content hasher (Phase 0 purity guard).
abstract final class ResourceRevisionMath {
  /// Canonical encoding of one node's persisted state.
  ///
  /// Stable across runs and independent of map iteration order, so hashing this
  /// string yields the same revision content hash for the same state.
  static String encodeNode(RevisionNodeSnapshot node) => _stableEncode(
        <String, Object?>{
          'id': node.nodeId,
          'k': node.kind.storageValue,
          'p': node.parentNodeId,
          't': node.title,
          's': node.summary,
          'st': node.status.storageValue,
          'o': node.sortOrder,
          'c': node.content,
          'm': node.metadata,
        },
      );

  /// Canonical encoding of a whole state: nodes ordered by id.
  static String encodeState(Iterable<RevisionNodeSnapshot> nodes) {
    final encoded = nodes
        .map((node) => '${node.nodeId}\u0000${encodeNode(node)}')
        .toList()
      ..sort();
    return encoded.join('\u0001');
  }

  /// The delta needed to move from [parent] to [current].
  ///
  /// Nodes present only in [parent] become tombstones, which is what makes a
  /// deletion representable without keeping a copy of the whole tree.
  static List<RevisionNodeSnapshot> diff({
    required Map<String, RevisionNodeSnapshot> parent,
    required Map<String, RevisionNodeSnapshot> current,
  }) {
    final changed = <RevisionNodeSnapshot>[];
    for (final entry in current.entries) {
      final before = parent[entry.key];
      if (before == null || !before.hasSameState(entry.value)) {
        changed.add(entry.value);
      }
    }
    for (final entry in parent.entries) {
      if (current.containsKey(entry.key)) continue;
      changed.add(RevisionNodeSnapshot(
        nodeId: entry.value.nodeId,
        kind: entry.value.kind,
        parentNodeId: entry.value.parentNodeId,
        title: entry.value.title,
        sortOrder: entry.value.sortOrder,
        isRemoved: true,
      ));
    }
    changed.sort(_compareSnapshots);
    return changed;
  }

  /// Applies one delta on top of [state], returning the resulting state.
  ///
  /// Pure and side-effect free so chain replay can be unit-tested without
  /// SQLite. [state] is not mutated.
  static Map<String, RevisionNodeSnapshot> applyDelta(
    Map<String, RevisionNodeSnapshot> state,
    Iterable<RevisionNodeSnapshot> deltas,
  ) {
    final next = Map<String, RevisionNodeSnapshot>.from(state);
    for (final delta in deltas) {
      if (delta.isRemoved) {
        next.remove(delta.nodeId);
      } else {
        next[delta.nodeId] = delta;
      }
    }
    return next;
  }

  static int _compareSnapshots(
    RevisionNodeSnapshot a,
    RevisionNodeSnapshot b,
  ) {
    final byKind = a.kind.index.compareTo(b.kind.index);
    if (byKind != 0) return byKind;
    final bySort = a.sortOrder.compareTo(b.sortOrder);
    if (bySort != 0) return bySort;
    return a.nodeId.compareTo(b.nodeId);
  }

  /// Deterministic, dependency-free encoding of a JSON-like value.
  ///
  /// Written by hand instead of delegating to a JSON encoder so the contract
  /// layer keeps its frozen "never serialize a whole resource as JSON" guard
  /// (ADR-0001 + the Phase 0 structural test) while still producing a canonical
  /// string for hashing.
  static String _stableEncode(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      final buffer = StringBuffer('{');
      for (var i = 0; i < keys.length; i++) {
        if (i > 0) buffer.write(',');
        buffer
          ..write(keys[i])
          ..write(':')
          ..write(_stableEncode(value[keys[i]]));
      }
      buffer.write('}');
      return buffer.toString();
    }
    if (value is List) {
      return '[${value.map(_stableEncode).join(',')}]';
    }
    if (value is String) return '"$value"';
    if (value == null) return 'null';
    return value.toString();
  }
}
