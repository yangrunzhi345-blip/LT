import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_repository.dart';

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
