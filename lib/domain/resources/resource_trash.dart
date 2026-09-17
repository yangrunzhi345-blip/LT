import 'resource_contracts.dart';

/// Base type for recycle-bin failures.
class ResourceTrashException implements Exception {
  const ResourceTrashException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when the requested trash entry does not exist, or was already purged.
class ResourceTrashNotFoundException extends ResourceTrashException {
  const ResourceTrashNotFoundException(super.message);
}

/// Thrown when a delete/restore loses an optimistic-locking race.
class ResourceTrashConflictException extends ResourceTrashException {
  const ResourceTrashConflictException(super.message);
}

/// Why a node was moved to the recycle bin.
///
/// Stored as text so a later phase can add a producer without a migration. The
/// current implementation only ever moves a node to the bin because the user
/// asked for that node; nodes that disappear with an ancestor share the
/// ancestor's entry and its delete timestamp, which is what lets a single
/// restore bring the whole subtree back.
enum TrashReason {
  /// The user asked to delete this node.
  userDelete;

  String get storageValue => name;

  static TrashReason fromStorageValue(String? raw) {
    final value = raw?.trim() ?? '';
    for (final reason in TrashReason.values) {
      if (reason.name == value) return reason;
    }
    return TrashReason.userDelete;
  }

  String get displayLabel => switch (this) {
        TrashReason.userDelete => '用户删除',
      };
}

/// What happened to a restore request.
///
/// A fallback is never silent: it is returned to the caller so the UI can tell
/// the user their Section/Part was restored somewhere other than its original
/// position instead of pretending nothing changed.
enum TrashRestorePlacement {
  /// Restored to the original parent and sort order.
  original,

  /// The original parent Section was gone; a new Section was created under the
  /// resource root and the Part placed inside it.
  recreatedSectionUnderRoot,

  /// The node was already restored by an earlier call; this call changed
  /// nothing (idempotent repeat).
  alreadyRestored;

  bool get isFallback =>
      this == TrashRestorePlacement.recreatedSectionUnderRoot;

  String get displayLabel => switch (this) {
        TrashRestorePlacement.original => '恢复到原位置',
        TrashRestorePlacement.recreatedSectionUnderRoot =>
          '原所属章节已不存在，已恢复到资源根下的新章节',
        TrashRestorePlacement.alreadyRestored => '该条目已恢复，本次未改变任何内容',
      };
}

/// One recycle-bin record.
///
/// The record deliberately stores only metadata: the deleted body stays in
/// `resource_parts.content` behind `deleted_at`, so the bin never duplicates
/// long text and a restore never has to re-parse a serialized tree.
final class ResourceTrashEntry {
  const ResourceTrashEntry({
    required this.trashId,
    required this.resourceId,
    required this.nodeId,
    required this.nodeKind,
    required this.reason,
    required this.deletedAtToken,
    required this.expiresAtToken,
    this.parentNodeId = '',
    this.originalSortOrder = 0,
    this.originalStatus = NodeStatus.draft,
    this.originalTitle = '',
    this.revisionId = '',
    this.restoredAtToken,
    this.restoreOutcome = '',
    this.metadata = const <String, Object?>{},
  });

  final String trashId;
  final ResourceId resourceId;

  /// The deleted node's id. Matches `resources.id` / `resource_sections.id` /
  /// `resource_parts.id` depending on [nodeKind].
  final String nodeId;

  final RevisionNodeKindRef nodeKind;

  /// Original owner: the resource for a Section, the Section for a Part, empty
  /// for a Resource.
  final String parentNodeId;

  final int originalSortOrder;
  final NodeStatus originalStatus;
  final String originalTitle;

  final TrashReason reason;

  /// Revision captured immediately before the delete, when one was recorded.
  final String revisionId;

  final String deletedAtToken;
  final String expiresAtToken;
  final String? restoredAtToken;
  final String restoreOutcome;

  final Map<String, Object?> metadata;

  bool get isRestored => restoredAtToken != null;

  NodeId get identity => switch (nodeKind) {
        RevisionNodeKindRef.resource => ResourceId(nodeId),
        RevisionNodeKindRef.section => SectionId(nodeId),
        RevisionNodeKindRef.part => PartId(nodeId),
      };
}

/// Node kind as stored in the recycle bin.
///
/// A separate enum from the revision one so the two tables can evolve
/// independently; the values are intentionally identical strings.
enum RevisionNodeKindRef {
  resource,
  section,
  part;

  String get storageValue => name;

  static RevisionNodeKindRef fromStorageValue(String? raw) {
    final value = raw?.trim() ?? '';
    for (final kind in RevisionNodeKindRef.values) {
      if (kind.name == value) return kind;
    }
    throw ResourceTrashException('未知的回收站节点类型：$raw');
  }

  static RevisionNodeKindRef of(NodeId id) => switch (id) {
        ResourceId() => RevisionNodeKindRef.resource,
        SectionId() => RevisionNodeKindRef.section,
        PartId() => RevisionNodeKindRef.part,
      };
}

/// Result of one restore call.
final class TrashRestoreResult {
  const TrashRestoreResult({
    required this.entry,
    required this.placement,
    this.restoredNodeId,
    this.createdSectionId,
  });

  final ResourceTrashEntry entry;
  final TrashRestorePlacement placement;

  /// The node that now exists in the live tree.
  final String? restoredNodeId;

  /// Set only when [placement] is a fallback: the freshly created Section the
  /// node was placed under.
  final String? createdSectionId;

  bool get isIdempotentRepeat =>
      placement == TrashRestorePlacement.alreadyRestored;

  /// Message the UI shows verbatim so a fallback restore is never silent.
  String get userMessage => placement.displayLabel;
}

/// Result of one permanent-delete call.
final class TrashPurgeResult {
  const TrashPurgeResult({
    required this.trashId,
    required this.deletedNodeIds,
    this.alreadyGone = false,
  });

  final String trashId;
  final List<String> deletedNodeIds;

  /// True when the entry was already physically gone; the call is still a
  /// success, which keeps "delete twice" idempotent.
  final bool alreadyGone;
}

/// Retention policy of the recycle bin.
///
/// Kept in the domain layer so the repository, the cleanup job and the UI all
/// read one number instead of restating it.
abstract final class TrashRetentionPolicy {
  /// How long a deleted node stays recoverable before cleanup may purge it.
  static const Duration retentionPeriod = Duration(days: 30);

  /// Deadline written into `resource_trash.expires_at` for a delete at [from].
  static DateTime expiresAt(DateTime from) => from.add(retentionPeriod);

  /// True when [expiresAtToken] has passed at [now].
  static bool isExpired(String expiresAtToken, DateTime now) {
    final parsed = DateTime.tryParse(expiresAtToken);
    if (parsed == null) {
      throw ResourceTrashException('回收站过期时间无法解析：$expiresAtToken');
    }
    return !parsed.isAfter(now);
  }
}
