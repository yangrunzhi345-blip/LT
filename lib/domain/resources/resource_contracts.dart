/// Frozen architecture contracts for the LT adaptive resource system.
///
/// Everything in this library is pure Dart: it must not import Flutter,
/// SQLite, HTTP or any outer application layer. Later phases implement these
/// definitions (see `docs/architecture/adaptive-resource-system.md`), so the
/// meanings frozen here must not be re-invented per phase.
///
/// Frozen content model (ADR-0001):
/// - `Resource -> Section -> Part` is a logical tree.
/// - A `ResourceSection` must be a direct child of a `Resource`.
/// - A `ResourcePart` must be a direct child of a `ResourceSection`.
/// - Sibling order is stored explicitly (`sortOrder`) and resolved by
///   `(sortOrder, id)` so ordering is always deterministic.
/// - Node ids are assigned at creation and never change afterwards.
/// - Long body text lives only on `ResourcePart`.
library;

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

/// Thrown when a contract invariant is violated.
class ResourceContractException implements Exception {
  const ResourceContractException(this.message);

  final String message;

  @override
  String toString() => 'ResourceContractException: $message';
}

/// Thrown when an illegal state transition is requested.
///
/// Kept non-const because the message is derived from the rejected edge.
class ResourceStateTransitionException extends ResourceContractException {
  ResourceStateTransitionException({
    required this.domain,
    required this.from,
    required this.to,
  }) : super('Illegal $domain transition: $from -> $to');

  /// Name of the state machine that rejected the transition.
  final String domain;

  final String from;
  final String to;
}

// ---------------------------------------------------------------------------
// Resource type
// ---------------------------------------------------------------------------

/// The three resources that share one creation content tree.
///
/// `npc` stays a distinct type because NPC cards are stored and budgeted
/// separately from full character cards, even though they share a content
/// shape.
enum ResourceType {
  worldview,
  character,
  npc;

  /// Stable value used by storage and transport.
  String get storageValue => name;

  /// Parses [storageValue]; unknown input is rejected instead of defaulted so
  /// a typo cannot silently create a resource of the wrong type.
  static ResourceType fromStorageValue(String? value) {
    for (final type in ResourceType.values) {
      if (type.storageValue == value) return type;
    }
    throw ResourceContractException('Unknown resource type: $value');
  }
}

// ---------------------------------------------------------------------------
// Node identity
// ---------------------------------------------------------------------------

/// Identity of one node in the logical tree.
///
/// The hierarchy is sealed on purpose: the type system prevents inventing a
/// fourth level or a nested section/part, which is how "fake logical trees"
/// made of physically nested payloads are kept out of the codebase.
///
/// Ids are opaque, non-empty and immutable. `sortOrder` is separate from
/// identity so reordering never rewrites identity.
sealed class NodeId {
  const NodeId(this.value) : assert(value != '', 'node id must not be empty');

  /// Opaque storage identity of the node.
  final String value;

  /// Human readable node kind, used in diagnostics and error messages.
  String get nodeKind;

  @override
  bool operator ==(Object other) =>
      other is NodeId &&
      other.runtimeType == runtimeType &&
      other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => '$nodeKind($value)';
}

/// Identity of a [Resource] node (tree root).
final class ResourceId extends NodeId {
  const ResourceId(super.value);

  @override
  String get nodeKind => 'resource';
}

/// Identity of a [ResourceSection] node (direct child of a [Resource]).
final class SectionId extends NodeId {
  const SectionId(super.value);

  @override
  String get nodeKind => 'section';
}

/// Identity of a [ResourcePart] node (direct child of a [ResourceSection]).
final class PartId extends NodeId {
  const PartId(super.value);

  @override
  String get nodeKind => 'part';
}

/// Identity of one immutable resource revision.
final class ResourceRevisionId {
  const ResourceRevisionId(this.value)
      : assert(value != '', 'ResourceRevisionId must not be empty');

  final String value;

  @override
  bool operator ==(Object other) =>
      other is ResourceRevisionId && other.value == value;

  @override
  int get hashCode => Object.hash(ResourceRevisionId, value);

  @override
  String toString() => 'ResourceRevisionId($value)';
}

// ---------------------------------------------------------------------------
// Node / generation / capacity / readiness state
// ---------------------------------------------------------------------------

/// Editorial state of a single node.
///
/// `confirmed` is what may become canon; `draft` is user- or AI-authored but
/// not yet canon; `archived` keeps the content recoverable without deleting
/// it. Reuse of the existing worldview `draft/confirmed/archived` semantics is
/// intentional (see ADR-0001).
enum NodeStatus {
  draft,
  confirmed,
  archived;

  String get storageValue => name;
}

/// How a resource's content came into existence.
///
/// The values mirror the existing stable `ResourceAuthoringMethod` semantics
/// instead of inventing a parallel vocabulary; import currently flows through
/// the same two values, so no third value is frozen here.
enum CreationMethod {
  manual,
  aiReference;

  String get storageValue => name;
}

/// Lifecycle of one bounded generation task.
///
/// A generation task plans (at most one blueprint), then mounts a finite
/// number of node patches, then stops. `completed`, `failed` and `cancelled`
/// are reachable only from an active state; restarting always goes through
/// `planning` so a stale task can never resume mid-flight.
enum GenerationStatus {
  idle,
  planning,
  generating,
  completed,
  failed,
  cancelled;

  String get storageValue => name;
}

/// Measured content size relative to the frozen capacity policy.
///
/// `overflow` never means "must truncate": overflow content is still saved in
/// full, it only decides whether compression/assembly work is scheduled.
enum CapacityStatus {
  normal,
  elastic,
  overflow;

  String get storageValue => name;
}

/// Assembled-version readiness of a resource.
///
/// A resource always has a latest head; the assembly revision is optional
/// until one is published. Runtime consumers may only read a `ready` revision.
enum ReadinessState {
  preparing,
  ready,
  failed,
  stale;

  String get storageValue => name;
}

// ---------------------------------------------------------------------------
// State machines
// ---------------------------------------------------------------------------

/// The single source of truth for every legal state transition.
///
/// Self transitions are legal so that re-applying the current state is an
/// idempotent write rather than an error. Everything not listed is illegal and
/// must be rejected before any persistence happens.
abstract final class ResourceStateMachines {
  static const Map<GenerationStatus, Set<GenerationStatus>> generation = {
    GenerationStatus.idle: {
      GenerationStatus.idle,
      GenerationStatus.planning,
    },
    GenerationStatus.planning: {
      GenerationStatus.planning,
      GenerationStatus.generating,
      GenerationStatus.failed,
      GenerationStatus.cancelled,
    },
    GenerationStatus.generating: {
      GenerationStatus.generating,
      GenerationStatus.completed,
      GenerationStatus.failed,
      GenerationStatus.cancelled,
    },
    GenerationStatus.completed: {
      GenerationStatus.completed,
      GenerationStatus.planning,
    },
    GenerationStatus.failed: {
      GenerationStatus.failed,
      GenerationStatus.planning,
    },
    GenerationStatus.cancelled: {
      GenerationStatus.cancelled,
      GenerationStatus.planning,
    },
  };

  static const Map<NodeStatus, Set<NodeStatus>> nodeStatus = {
    NodeStatus.draft: {
      NodeStatus.draft,
      NodeStatus.confirmed,
      NodeStatus.archived,
    },
    NodeStatus.confirmed: {
      NodeStatus.confirmed,
      NodeStatus.draft,
      NodeStatus.archived,
    },
    // Archived content must return to draft for review; it can never become
    // confirmed in one step.
    NodeStatus.archived: {
      NodeStatus.archived,
      NodeStatus.draft,
    },
  };

  static const Map<ReadinessState, Set<ReadinessState>> readiness = {
    ReadinessState.preparing: {
      ReadinessState.preparing,
      ReadinessState.ready,
      ReadinessState.failed,
    },
    // A ready revision is either invalidated (`stale`) or rebuilt
    // (`preparing`); it never fails in place.
    ReadinessState.ready: {
      ReadinessState.ready,
      ReadinessState.stale,
      ReadinessState.preparing,
    },
    ReadinessState.failed: {
      ReadinessState.failed,
      ReadinessState.preparing,
    },
    ReadinessState.stale: {
      ReadinessState.stale,
      ReadinessState.preparing,
    },
  };

  static bool canTransitionGeneration(
          GenerationStatus from, GenerationStatus to) =>
      generation[from]!.contains(to);

  static bool canTransitionNodeStatus(NodeStatus from, NodeStatus to) =>
      nodeStatus[from]!.contains(to);

  static bool canTransitionReadiness(ReadinessState from, ReadinessState to) =>
      readiness[from]!.contains(to);

  /// Returns [to] when the generation edge is legal, otherwise throws.
  static GenerationStatus advanceGeneration(
    GenerationStatus from,
    GenerationStatus to,
  ) {
    if (!canTransitionGeneration(from, to)) {
      throw ResourceStateTransitionException(
        domain: 'generation',
        from: from.storageValue,
        to: to.storageValue,
      );
    }
    return to;
  }

  /// Returns [to] when the node-status edge is legal, otherwise throws.
  static NodeStatus advanceNodeStatus(NodeStatus from, NodeStatus to) {
    if (!canTransitionNodeStatus(from, to)) {
      throw ResourceStateTransitionException(
        domain: 'nodeStatus',
        from: from.storageValue,
        to: to.storageValue,
      );
    }
    return to;
  }

  /// Returns [to] when the readiness edge is legal, otherwise throws.
  static ReadinessState advanceReadiness(
      ReadinessState from, ReadinessState to) {
    if (!canTransitionReadiness(from, to)) {
      throw ResourceStateTransitionException(
        domain: 'readiness',
        from: from.storageValue,
        to: to.storageValue,
      );
    }
    return to;
  }
}

// ---------------------------------------------------------------------------
// Tree nodes
// ---------------------------------------------------------------------------

/// A node that can sit in an explicitly ordered sibling list.
///
/// Exposes only what canonical ordering needs, so sorting never has to reach
/// for `dynamic`.
abstract interface class OrderedTreeNode {
  NodeId get id;

  /// Explicit sibling position inside the parent node.
  int get sortOrder;
}

/// Root of the logical content tree.
///
/// A resource only holds identity, classification and small runtime metadata.
/// Body text is never stored here, and `metadata` must stay a small set of
/// type-specific runtime core fields, not a serialized full resource.
final class Resource {
  const Resource({
    required this.id,
    required this.type,
    required this.name,
    this.summary = '',
    this.metadata = const <String, Object?>{},
    this.status = NodeStatus.draft,
  });

  final ResourceId id;
  final ResourceType type;
  final String name;
  final String summary;

  /// Type-specific runtime core fields only (for example an NPC's link to its
  /// worldview). Never body text, never a serialized content tree.
  final Map<String, Object?> metadata;

  final NodeStatus status;

  Resource copyWith({
    String? name,
    String? summary,
    Map<String, Object?>? metadata,
    NodeStatus? status,
  }) {
    return Resource(
      id: id,
      type: type,
      name: name ?? this.name,
      summary: summary ?? this.summary,
      metadata: metadata ?? this.metadata,
      status: status ?? this.status,
    );
  }
}

/// A section is always a direct child of exactly one [Resource].
///
/// There is deliberately no "section inside a section" type: nesting content
/// by physically embedding payloads is how a fake logical tree would be built,
/// and it is not representable here.
final class ResourceSection implements OrderedTreeNode {
  const ResourceSection({
    required this.id,
    required this.resourceId,
    required this.title,
    required this.sortOrder,
    this.summary = '',
    this.status = NodeStatus.draft,
  }) : assert(sortOrder >= 0, 'sortOrder must not be negative');

  @override
  final SectionId id;

  /// Parent resource. Ownership is data, not containment.
  final ResourceId resourceId;

  final String title;
  final String summary;

  /// Explicit sibling position inside the parent resource.
  @override
  final int sortOrder;

  final NodeStatus status;

  ResourceSection copyWith({
    String? title,
    String? summary,
    int? sortOrder,
    NodeStatus? status,
  }) {
    return ResourceSection(
      id: id,
      resourceId: resourceId,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      sortOrder: sortOrder ?? this.sortOrder,
      status: status ?? this.status,
    );
  }
}

/// A part is always a direct child of exactly one [ResourceSection], and it is
/// the only node that owns long body text.
final class ResourcePart implements OrderedTreeNode {
  const ResourcePart({
    required this.id,
    required this.sectionId,
    required this.title,
    required this.content,
    required this.sortOrder,
    this.status = NodeStatus.draft,
    this.contentHash = '',
  }) : assert(sortOrder >= 0, 'sortOrder must not be negative');

  @override
  final PartId id;

  /// Parent section. Ownership is data, not containment.
  final SectionId sectionId;

  final String title;

  /// The only place long body text is allowed to live. May be empty while a
  /// streaming mount is still filling this part in.
  final String content;

  /// Explicit sibling position inside the parent section.
  @override
  final int sortOrder;

  final NodeStatus status;

  /// Hash of [content] for revision/assembly comparison; empty until computed.
  final String contentHash;

  ResourcePart copyWith({
    String? title,
    String? content,
    int? sortOrder,
    NodeStatus? status,
    String? contentHash,
  }) {
    return ResourcePart(
      id: id,
      sectionId: sectionId,
      title: title ?? this.title,
      content: content ?? this.content,
      sortOrder: sortOrder ?? this.sortOrder,
      status: status ?? this.status,
      contentHash: contentHash ?? this.contentHash,
    );
  }
}

/// An assembled view of one resource's tree.
///
/// This is a read model, not a storage format: Phase 1 assembles it from
/// per-node rows instead of parsing one giant JSON column.
final class ResourceTree {
  ResourceTree({
    required this.resource,
    required List<ResourceSection> sections,
    required List<ResourcePart> parts,
  })  : sections = List<ResourceSection>.unmodifiable(sections),
        parts = List<ResourcePart>.unmodifiable(parts);

  final Resource resource;
  final List<ResourceSection> sections;
  final List<ResourcePart> parts;

  /// Sections in canonical sibling order.
  List<ResourceSection> get orderedSections => _sorted(sections);

  /// Parts of [sectionId] in canonical sibling order.
  List<ResourcePart> orderedPartsOf(SectionId sectionId) => _sorted(
        parts.where((part) => part.sectionId == sectionId).toList(),
      );

  /// Canonical order is `(sortOrder, id)`, so equal `sortOrder` values still
  /// resolve deterministically instead of depending on read order.
  static List<T> _sorted<T extends OrderedTreeNode>(List<T> nodes) {
    final sorted = List<T>.from(nodes);
    sorted.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) return byOrder;
      return a.id.value.compareTo(b.id.value);
    });
    return sorted;
  }

  /// Verifies every frozen tree invariant and throws on the first violation.
  ///
  /// Called at mount/commit boundaries so an illegal tree never reaches
  /// persistence.
  void validate() {
    final sectionIds = <SectionId>{};
    for (final section in sections) {
      if (section.resourceId != resource.id) {
        throw ResourceContractException(
          'Section ${section.id} belongs to ${section.resourceId} but was '
          'assembled under resource ${resource.id}',
        );
      }
      if (!sectionIds.add(section.id)) {
        throw ResourceContractException('Duplicate section id: ${section.id}');
      }
    }

    final partIds = <PartId>{};
    for (final part in parts) {
      if (!sectionIds.contains(part.sectionId)) {
        throw ResourceContractException(
          'Part ${part.id} references unknown section ${part.sectionId}',
        );
      }
      if (!partIds.add(part.id)) {
        throw ResourceContractException('Duplicate part id: ${part.id}');
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Node-scoped mount patches
// ---------------------------------------------------------------------------

/// One finite change produced by one bounded step (a user edit or a single
/// model response).
///
/// A patch always targets exactly one node. There is intentionally no patch
/// that accepts a whole serialized resource, because a single request must
/// never carry an entire worldview or character card.
sealed class ResourceNodePatch {
  const ResourceNodePatch();

  /// The one node this patch acts on.
  ///
  /// Append patches name the parent that gains a child; update, rename,
  /// reorder and archive patches name the node they rewrite.
  NodeId get targetNodeId;
}

/// Appends one new section directly under a resource.
final class AppendSectionPatch extends ResourceNodePatch {
  const AppendSectionPatch({
    required this.resourceId,
    required this.title,
    this.summary = '',
  });

  final ResourceId resourceId;
  final String title;
  final String summary;

  @override
  NodeId get targetNodeId => resourceId;
}

/// Appends one new part directly under a section. Body text starts here.
final class AppendPartPatch extends ResourceNodePatch {
  const AppendPartPatch({
    required this.sectionId,
    required this.title,
    this.content = '',
  });

  final SectionId sectionId;
  final String title;
  final String content;

  @override
  NodeId get targetNodeId => sectionId;
}

/// Replaces the body text of exactly one existing part.
final class UpdatePartContentPatch extends ResourceNodePatch {
  const UpdatePartContentPatch({
    required this.partId,
    required this.content,
    this.contentHash = '',
  });

  final PartId partId;
  final String content;
  final String contentHash;

  @override
  NodeId get targetNodeId => partId;
}

/// Renames exactly one node.
final class RenameNodePatch extends ResourceNodePatch {
  const RenameNodePatch({required this.nodeId, required this.title});

  final NodeId nodeId;
  final String title;

  @override
  NodeId get targetNodeId => nodeId;
}

/// Moves exactly one node to an explicit sibling position.
final class ReorderNodePatch extends ResourceNodePatch {
  const ReorderNodePatch({required this.nodeId, required this.sortOrder})
      : assert(sortOrder >= 0, 'sortOrder must not be negative');

  final NodeId nodeId;
  final int sortOrder;

  @override
  NodeId get targetNodeId => nodeId;
}

/// Archives exactly one node without deleting its content.
final class ArchiveNodePatch extends ResourceNodePatch {
  const ArchiveNodePatch({required this.nodeId});

  final NodeId nodeId;

  @override
  NodeId get targetNodeId => nodeId;
}

/// Outcome of mounting one [ResourceNodePatch].
final class ResourceMountResult {
  const ResourceMountResult({
    required this.nodeId,
    required this.sortOrder,
  });

  /// The node that was created or rewritten by the patch.
  final NodeId nodeId;

  /// Effective sibling position after the mount.
  final int sortOrder;
}

// ---------------------------------------------------------------------------
// Revision / assembly contract values
// ---------------------------------------------------------------------------

/// Which revision of a resource a reference points at.
///
/// The user's latest saved edit (`latestHead`) and the version Adventure may
/// consume (`assembly`) are different concepts and are allowed to diverge.
enum ResourceRevisionKind {
  latestHead,
  assembly;

  String get storageValue => name;
}

/// A pointer to one immutable revision of one resource.
final class ResourceRevisionRef {
  const ResourceRevisionRef({
    required this.resourceId,
    required this.revisionId,
    required this.kind,
    this.createdAt,
  });

  final ResourceId resourceId;
  final ResourceRevisionId revisionId;
  final ResourceRevisionKind kind;
  final DateTime? createdAt;
}

/// The resolution of "which version may be consumed right now".
final class ResourceRevisionSelection {
  const ResourceRevisionSelection({
    required this.resourceId,
    required this.readiness,
    this.latestHead,
    this.assemblyRevision,
  });

  final ResourceId resourceId;
  final ReadinessState readiness;

  /// Latest saved edit; null only when no revision has been recorded yet.
  final ResourceRevisionRef? latestHead;

  /// Version Adventure is allowed to read; null until one is published.
  final ResourceRevisionRef? assemblyRevision;

  bool get hasLatestHead => latestHead != null;
  bool get hasAssemblyRevision => assemblyRevision != null;

  /// Runtime may only assemble from a published, ready revision.
  bool get canAssemble =>
      readiness == ReadinessState.ready && hasAssemblyRevision;
}

/// One node-scoped fragment of an assembled snapshot.
///
/// Fragments keep assembly output bounded per node; the snapshot is never one
/// serialized copy of the whole resource.
final class ResourceAssemblyFragment {
  const ResourceAssemblyFragment({
    required this.sourceNodeId,
    required this.text,
    required this.sortOrder,
    this.isCanon = true,
  }) : assert(sortOrder >= 0, 'sortOrder must not be negative');

  /// The section or part this fragment was derived from.
  final NodeId sourceNodeId;

  final String text;
  final int sortOrder;

  /// Whether this fragment may enter canon. Draft nodes must not be injected
  /// as facts.
  final bool isCanon;
}

/// Immutable, ready-to-consume assembly output for one resource revision.
final class ResourceAssemblySnapshot {
  const ResourceAssemblySnapshot({
    required this.resourceId,
    required this.revisionId,
    required this.readiness,
    required this.contentHash,
    this.fragments = const <ResourceAssemblyFragment>[],
  });

  final ResourceId resourceId;
  final ResourceRevisionId revisionId;
  final ReadinessState readiness;

  /// Hash of the revision this snapshot was built from. Used to detect a head
  /// change during assembly and to keep semantic indexes on one revision.
  final String contentHash;

  final List<ResourceAssemblyFragment> fragments;
}
