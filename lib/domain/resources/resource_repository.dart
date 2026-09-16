/// Domain interfaces for the unified resource content tree.
///
/// This library is interfaces only: no storage, no transaction, no ORM and no
/// Flutter/SQLite/HTTP dependency. Phase 1 and later phases implement these
/// against the real database without changing their signatures, so the layer
/// direction stays `application -> domain` and never the other way around.
///
/// Protocol bound (ADR-0001): a caller may only ever hand over one
/// [ResourceNodePatch] at a time. No method here accepts a serialized whole
/// resource, which is what keeps a single model call from carrying an entire
/// worldview or character card.
library;

import 'resource_contracts.dart';

/// Reads the logical tree.
abstract interface class ResourceTreeReader {
  /// Returns the resource root, or null when [id] is unknown or hidden.
  Future<Resource?> findResource(ResourceId id);

  /// Lists resource roots of [type], newest-first by the caller's convention.
  Future<List<Resource>> listResources({
    required ResourceType type,
    bool includeArchived = false,
  });

  /// Sections of [resourceId] in canonical `(sortOrder, id)` order.
  Future<List<ResourceSection>> readSections(ResourceId resourceId);

  /// Parts of [sectionId] in canonical `(sortOrder, id)` order.
  Future<List<ResourcePart>> readParts(SectionId sectionId);

  /// Assembles the whole tree of [resourceId], or null when it does not exist.
  ///
  /// Implementations must assemble per-node rows; parsing one giant JSON column
  /// is not an acceptable implementation of this method.
  Future<ResourceTree?> readTree(ResourceId resourceId);
}

/// Applies finite, node-scoped mounts to an existing tree.
abstract interface class ResourceNodeMounter {
  /// Mounts exactly one patch and returns the affected node.
  ///
  /// Implementations must reject a patch whose target does not exist, whose
  /// parent relationship is illegal, or whose resulting tree violates the
  /// frozen invariants. They must not accept a bulk payload.
  Future<ResourceMountResult> mount(ResourceNodePatch patch);
}

/// Starts a creation session for a new resource.
abstract interface class ResourceCreationGateway {
  /// Opens a session that owns one new resource identity.
  ///
  /// The id is allocated here (never by the caller) and never changes
  /// afterwards.
  Future<ResourceCreationSession> begin({
    required ResourceType type,
    required String name,
    CreationMethod method = CreationMethod.manual,
    String summary = '',
  });
}

/// A single in-progress creation flow.
///
/// Nodes appended through a session are only published by [commit]; [abandon]
/// must leave no partial resource behind, so implementations are expected to
/// write transactionally.
abstract interface class ResourceCreationSession {
  ResourceId get resourceId;

  ResourceType get type;

  CreationMethod get creationMethod;

  /// Appends one section directly under this session's resource.
  Future<SectionId> appendSection({required String title, String summary = ''});

  /// Appends one part directly under [sectionId], which must belong to this
  /// session's resource.
  Future<PartId> appendPart({
    required SectionId sectionId,
    required String title,
    required String content,
  });

  /// Publishes the session as one complete resource.
  Future<void> commit();

  /// Discards the session without publishing anything.
  Future<void> abandon();
}

/// Resolves which revision of a resource may be read or consumed.
///
/// The user's latest saved edit and the version Adventure consumes are
/// deliberately different concepts and are allowed to diverge.
abstract interface class ResourceRevisionSelector {
  /// Latest saved edit of [resourceId], or null when none exists yet.
  Future<ResourceRevisionRef?> latestHead(ResourceId resourceId);

  /// Current selection: readiness plus the optional assembly revision.
  Future<ResourceRevisionSelection> select(ResourceId resourceId);

  /// Publishes [revisionId] as the assembly revision for [resourceId].
  ///
  /// Phase 10 wires this to the real builder; the contract exists now so the
  /// separation is frozen before any consumer exists.
  Future<void> publishAssemblyRevision({
    required ResourceId resourceId,
    required ResourceRevisionId revisionId,
  });
}

/// Produces the immutable snapshot Runtime consumes for a revision.
abstract interface class ResourceAssemblySnapshotProvider {
  /// Reads the snapshot for one published revision, or null when it is not
  /// available (still preparing, failed, or unknown).
  Future<ResourceAssemblySnapshot?> readSnapshot({
    required ResourceId resourceId,
    required ResourceRevisionId revisionId,
  });
}
