import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_repository.dart';
import '../../domain/resources/resource_revision.dart';

/// Base type for unified-resource-tree persistence failures.
class ResourceTreeException implements Exception {
  const ResourceTreeException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when a write loses an optimistic-locking race, or targets a node that
/// is not part of the sibling set the caller claims to be editing.
class ResourceTreeConflictException extends ResourceTreeException {
  const ResourceTreeConflictException(super.message);
}

/// Thrown when the requested node does not exist, or is already soft deleted.
class ResourceTreeNotFoundException extends ResourceTreeException {
  const ResourceTreeNotFoundException(super.message);
}

/// Thrown when a stored row cannot be mapped back into the domain model.
class ResourceTreeCorruptedException extends ResourceTreeException {
  const ResourceTreeCorruptedException(super.message);
}

/// Persistence-facing state of one stored node.
///
/// Phase 0 froze [Resource] / [ResourceSection] / [ResourcePart] without
/// timestamps, so callers read their optimistic-locking token here instead of
/// changing the frozen entities. Changing them would require re-reviewing
/// Phase 0, which Phase 1 must not do unilaterally.
final class ResourceNodeState {
  const ResourceNodeState({
    required this.id,
    required this.updatedAt,
    this.deletedAt,
    this.contentHash = '',
  });

  final NodeId id;

  /// Optimistic-locking token: pass this back as `expectedUpdatedAt`.
  final String updatedAt;

  /// Soft-delete marker; null while the node is live.
  final String? deletedAt;

  /// Part body hash; empty for resources and sections.
  final String contentHash;

  bool get isDeleted => deletedAt != null;
}

/// Frozen persistence constants of the unified content tree.
abstract final class ResourceTreeSchema {
  /// `resources.schema_version` written by Phase 1.
  ///
  /// Phase 0's [Resource] intentionally has no schema-version field; the column
  /// exists so later phases can evolve per-type metadata without another table
  /// shape change.
  static const int currentResourceSchemaVersion = 1;

  /// Reserved metadata keys carrying provenance (legacy column names, so
  /// Phase 2 can map `worldview_presets` / `character_cards` without inventing
  /// new vocabulary). Provenance is explicitly allowed metadata content.
  static const String metadataAuthoringMethodKey = 'authoring_method';
  static const String metadataAiGenerationDepthKey = 'ai_generation_depth';
}

/// One Part to be written by a bulk tree create.
final class ResourceTreePartDraft {
  const ResourceTreePartDraft({
    required this.title,
    required this.content,
    this.status = NodeStatus.draft,
    this.id,
  });

  /// Optional caller-supplied identity.
  ///
  /// A migration supplies a deterministic id so re-runs cannot create a second
  /// copy and so metadata can reference the node it just created. When omitted
  /// the repository allocates the id.
  final PartId? id;

  final String title;
  final String content;
  final NodeStatus status;
}

/// One Section, with its ordered Parts, to be written by a bulk tree create.
final class ResourceTreeSectionDraft {
  const ResourceTreeSectionDraft({
    required this.title,
    this.summary = '',
    this.status = NodeStatus.draft,
    this.parts = const <ResourceTreePartDraft>[],
    this.id,
  });

  /// Optional caller-supplied identity; see [ResourceTreePartDraft.id].
  final SectionId? id;

  final String title;
  final String summary;
  final NodeStatus status;
  final List<ResourceTreePartDraft> parts;
}

/// A complete tree to create in one transaction.
///
/// [id] is supplied by the caller rather than allocated here so a migration can
/// use a deterministic id. That makes re-runs safe: a duplicate insert fails on
/// the primary key instead of silently producing a second tree.
final class ResourceTreeDraft {
  const ResourceTreeDraft({
    required this.id,
    required this.type,
    required this.name,
    this.summary = '',
    this.metadata = const <String, Object?>{},
    this.status = NodeStatus.draft,
    this.sections = const <ResourceTreeSectionDraft>[],
  });

  final ResourceId id;
  final ResourceType type;
  final String name;
  final String summary;
  final Map<String, Object?> metadata;
  final NodeStatus status;
  final List<ResourceTreeSectionDraft> sections;

  /// Same content under a different identity.
  ///
  /// Used by the creation bridge: the legacy mapper produces a draft whose id is
  /// in the migration namespace, while an entry-created resource must keep the
  /// caller's id so it stays the same resource across repeated saves.
  ResourceTreeDraft withId(ResourceId id) => ResourceTreeDraft(
        id: id,
        type: type,
        name: name,
        summary: summary,
        metadata: metadata,
        status: status,
        sections: sections,
      );

  /// Same content with extra metadata merged in.
  ResourceTreeDraft withMetadata(Map<String, Object?> metadata) =>
      ResourceTreeDraft(
        id: id,
        type: type,
        name: name,
        summary: summary,
        metadata: metadata,
        status: status,
        sections: sections,
      );

  /// Same content without the given metadata keys.
  ResourceTreeDraft withoutMetadataKeys(Set<String> keys) => ResourceTreeDraft(
        id: id,
        type: type,
        name: name,
        summary: summary,
        metadata: Map<String, Object?>.fromEntries(
          metadata.entries.where((entry) => !keys.contains(entry.key)),
        ),
        status: status,
        sections: sections,
      );
}

/// Unified Resource → Section → Part repository.
///
/// Implements the Phase 0 read / mount / creation contracts; `ResourceRevision-
/// Selector` and `ResourceAssemblySnapshotProvider` are deliberately NOT
/// implemented here because revisions and assembly readiness belong to
/// Phase 9 / Phase 10.
///
/// Every multi-statement operation runs inside one database transaction, and
/// every update that can race requires an explicit optimistic-locking token.
abstract interface class IResourceTreeRepository
    implements
        ResourceTreeReader,
        ResourceNodeMounter,
        ResourceCreationGateway {
  /// Creates a resource root. The id is allocated here, never by the caller.
  Future<Resource> createResource({
    required ResourceType type,
    required String name,
    CreationMethod method = CreationMethod.manual,
    String summary = '',
    Map<String, Object?> metadata = const <String, Object?>{},
  });

  /// Creates a resource and its whole tree in a single transaction.
  ///
  /// Added for the Phase 2 legacy migration, which needs a caller-supplied
  /// deterministic id and per-node [NodeStatus] values that
  /// [ResourceCreationSession] cannot express. It stays the only writer of the
  /// three tree tables, so migrations do not introduce a second one.
  Future<ResourceId> createResourceTree(ResourceTreeDraft draft);

  /// Replaces the whole tree of an existing resource, keeping its identity.
  ///
  /// Phase 3 needs this because the legacy save paths are upserts: saving an
  /// existing worldview or card must update the same resource instead of
  /// creating a second one. The replacement runs in one transaction, so a
  /// failure leaves the previous tree intact.
  Future<void> updateResourceTree(ResourceTreeDraft draft);

  /// Updates name / summary / metadata of one resource.
  Future<void> updateResource({
    required ResourceId id,
    required String expectedUpdatedAt,
    String? name,
    String? summary,
    Map<String, Object?>? metadata,
  });

  /// Updates title / summary / status of one section.
  Future<void> updateSection({
    required SectionId id,
    required String expectedUpdatedAt,
    String? title,
    String? summary,
    NodeStatus? status,
  });

  /// Updates title / content / status of exactly one part.
  ///
  /// Only this part's row (and the owning resource's `updated_at`) is written:
  /// sibling parts are never rewritten.
  Future<void> updatePart({
    required PartId id,
    required String expectedUpdatedAt,
    String? title,
    String? content,
    NodeStatus? status,
  });

  /// Soft deletes one node and its descendants (`deleted_at`), in one
  /// transaction. Recycle-bin UX, delete history and retention belong to
  /// Phase 9; this is only the persistence primitive.
  Future<void> softDeleteNode({
    required NodeId id,
    required String expectedUpdatedAt,
  });

  /// Rewrites the sibling order of a resource's sections in one transaction.
  ///
  /// [orderedIds] must list every live section of [resourceId] exactly once;
  /// otherwise a [ResourceTreeConflictException] is thrown and no order change
  /// is kept.
  Future<void> reorderSections({
    required ResourceId resourceId,
    required List<SectionId> orderedIds,
  });

  /// Rewrites the sibling order of a section's parts in one transaction.
  Future<void> reorderParts({
    required SectionId sectionId,
    required List<PartId> orderedIds,
  });

  /// Reads the optimistic-locking state of one node, or null when unknown.
  Future<ResourceNodeState?> readNodeState(NodeId id);

  /// Batch variant of [readNodeState], preserving no particular order.
  Future<List<ResourceNodeState>> readNodeStates(Iterable<NodeId> ids);
}

/// Tree-table access the Phase 9 revision/trash boundary needs.
///
/// Declared as its own interface, and implemented by the same SQLite class,
/// for one reason: these operations take a [DatabaseExecutor] the caller
/// already opened. A revision restore must revive/soft-delete nodes and switch
/// the revision head in **one** transaction, so the boundary cannot open its
/// own. Keeping the SQL here means the three tree tables still have exactly one
/// writer instead of a second copy in the revision service.
abstract interface class IResourceTreeRevisionBoundary {
  /// Snapshot of the live (non soft-deleted) tree of [resourceId].
  ///
  /// Returns an empty map when the resource row itself is gone or deleted,
  /// which is the caller's signal that there is nothing to snapshot.
  Future<Map<String, RevisionNodeSnapshot>> readLiveState(
    DatabaseExecutor db,
    ResourceId resourceId,
  );

  /// Applies a whole revision state to the live tree inside [db].
  ///
  /// Nodes in [target] are created or revived; live nodes of [resourceId] that
  /// [target] does not mention are soft deleted. Returns the ids of Parts whose
  /// body actually changed, so the caller can reset those generation tasks in
  /// the same transaction.
  Future<Set<String>> applyRevisionState(
    DatabaseExecutor db, {
    required ResourceId resourceId,
    required Map<String, RevisionNodeSnapshot> target,
    required String now,
  });

  /// Soft deletes one node and its descendants inside an existing transaction.
  ///
  /// Same semantics as [IResourceTreeRepository.softDeleteNode]; exists so the
  /// trash service can write the recycle-bin row and the delete together.
  Future<void> softDeleteNodeInTransaction(
    DatabaseExecutor db, {
    required NodeId id,
    required String expectedUpdatedAt,
    String now = '',
  });

  /// Clears `deleted_at` for one node and its live descendants.
  ///
  /// Used by trash restore. [expectedDeletedAt] is the token the delete wrote;
  /// a mismatch means the node state moved and the restore is refused instead
  /// of silently reviving a different state.
  Future<void> reviveNodeInTransaction(
    DatabaseExecutor db, {
    required NodeId id,
    required String expectedDeletedAt,
    String now = '',
  });

  /// Reads the stored `updated_at` / `deleted_at` of one node, or null.
  Future<({String updatedAt, String? deletedAt})?> readNodesTimestamps(
    DatabaseExecutor db,
    NodeId id,
  );

  /// Everything a recycle-bin record must remember about a node.
  ///
  /// Returns null when the row does not exist at all (as opposed to existing
  /// with a delete marker), which is how a permanent delete is distinguished
  /// from a recoverable one.
  Future<TrashNodePlacement?> readNodePlacement(
    DatabaseExecutor db,
    NodeId id,
  );

  /// Moves a Part to another Section (or a Section to another Resource).
  ///
  /// Needed only by the recycle-bin fallback: when a Part's original Section is
  /// gone, the Part is placed in a freshly created Section under the Resource
  /// root, which requires re-parenting rather than un-deleting in place.
  Future<void> reparentNodeInTransaction(
    DatabaseExecutor db, {
    required NodeId id,
    required String newParentId,
    required int sortOrder,
    required String now,
  });

  /// Deletes one node and everything under it, permanently.
  ///
  /// Only the recycle-bin purge calls this, and it refuses to run when the node
  /// is still live, so a permanent delete can never be reached by accident from
  /// a normal delete path.
  Future<void> purgeNodeInTransaction(
    DatabaseExecutor db,
    NodeId id,
  );

  /// Creates an empty Section directly under [resourceId] and returns its id.
  ///
  /// Used by the recycle-bin fallback when a Part's original Section no longer
  /// exists: the Part must land somewhere visible instead of failing.
  Future<SectionId> createSectionInTransaction(
    DatabaseExecutor db, {
    required ResourceId resourceId,
    required String title,
    String now = '',
  });

  /// Updates exactly one Part inside an existing transaction.
  ///
  /// The autosave/commit path needs the content write, the revision head flip
  /// and the draft-journal cleanup to share one commit; that is only possible
  /// if the guarded Part update can join a transaction the caller opened.
  Future<void> updatePartInTransaction(
    DatabaseExecutor db, {
    required PartId id,
    required String expectedUpdatedAt,
    String? title,
    String? content,
    NodeStatus? status,
    String now = '',
  });
}

/// Placement metadata of a node, as the recycle bin stores it.
final class TrashNodePlacement {
  const TrashNodePlacement({
    required this.nodeId,
    required this.nodeKind,
    required this.resourceId,
    required this.parentNodeId,
    required this.sortOrder,
    required this.status,
    required this.title,
    this.updatedAt = '',
    this.deletedAt,
  });

  final NodeId nodeId;

  /// `resource` / `section` / `part`.
  final String nodeKind;

  final String resourceId;

  /// Owning resource for a Section, owning Section for a Part, empty for a
  /// Resource.
  final String parentNodeId;

  final int sortOrder;
  final String status;
  final String title;
  final String updatedAt;
  final String? deletedAt;

  bool get isLive => deletedAt == null;
}
