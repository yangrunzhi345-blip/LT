import 'resource_contracts.dart';

/// Why a node was moved to the recycle bin.
///
/// Stored as text so a later phase can add a producer without a migration.
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
}

/// Where a recycle-bin entry's content actually lives.
///
/// A legacy library row is never physically deleted; its entry is a **marker**
/// that hides the untouched legacy row until restored. Recording the origin on
/// the entry keeps restore and lookup deterministic.
enum TrashOrigin {
  /// The node lives in the unified content tree (the default).
  tree,

  /// The content lives in a legacy library table; nothing was soft deleted.
  legacy;

  String get storageValue => name;

  /// Metadata key holding the origin.
  static const String metadataOriginKey = 'origin';

  /// Metadata key holding the legacy table name (`origin == legacy` only).
  static const String metadataSourceTableKey = 'source_table';

  /// Metadata key holding the legacy row id (`origin == legacy` only).
  static const String metadataSourceIdKey = 'source_id';

  static TrashOrigin fromMetadata(Map<String, Object?> metadata) =>
      metadata[metadataOriginKey]?.toString() == TrashOrigin.legacy.storageValue
          ? TrashOrigin.legacy
          : TrashOrigin.tree;
}

/// One recycle-bin record.
///
/// Only metadata is stored: the deleted body stays in its original table behind
/// the soft-delete marker, so the bin never duplicates long text.
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

  /// The deleted node's id.
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

  /// Where this entry's content lives (see [TrashOrigin]).
  TrashOrigin get origin => TrashOrigin.fromMetadata(metadata);

  /// True when the entry only hides a legacy row and nothing was deleted.
  bool get isLegacyOrigin => origin == TrashOrigin.legacy;

  /// Legacy table this entry hides or duplicates.
  String get linkedSourceTable =>
      metadata[TrashOrigin.metadataSourceTableKey]?.toString() ?? '';

  /// Legacy row id this entry hides or duplicates. See [linkedSourceTable].
  String get linkedSourceId =>
      metadata[TrashOrigin.metadataSourceIdKey]?.toString() ?? '';

  NodeId get identity => switch (nodeKind) {
        RevisionNodeKindRef.resource => ResourceId(nodeId),
        RevisionNodeKindRef.section => SectionId(nodeId),
        RevisionNodeKindRef.part => PartId(nodeId),
      };
}

/// Node kind as stored in the recycle bin.
///
/// A separate enum from any other node-kind vocabulary so the two tables can
/// evolve independently; the values are intentionally identical strings.
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
    throw ArgumentError.value(raw, 'raw', 'Unknown trash node kind');
  }

  static RevisionNodeKindRef of(NodeId id) => switch (id) {
        ResourceId() => RevisionNodeKindRef.resource,
        SectionId() => RevisionNodeKindRef.section,
        PartId() => RevisionNodeKindRef.part,
      };
}

/// Result of moving a node to the recycle bin.
final class TrashDeleteResult {
  const TrashDeleteResult({
    required this.entry,
    required this.alreadyDeleted,
  });

  final ResourceTrashEntry entry;

  /// True when the node was already in the bin, so this call changed nothing.
  final bool alreadyDeleted;
}

/// Retention policy of the recycle bin.
///
/// Kept in the domain layer so the store, the cleanup job and the UI all read
/// one number instead of restating it.
abstract final class TrashRetentionPolicy {
  /// How long a deleted node stays recoverable before cleanup may purge it.
  static const Duration retentionPeriod = Duration(days: 30);

  /// Deadline written into `resource_trash.expires_at` for a delete at [from].
  static DateTime expiresAt(DateTime from) => from.add(retentionPeriod);
}
