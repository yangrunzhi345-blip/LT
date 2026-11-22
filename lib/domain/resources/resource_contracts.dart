/// Frozen value contracts for the resource library.
///
/// Pure Dart: no Flutter, SQLite or outer-layer imports. Only the types the
/// card-backed library, the legacy CRUD paths, the migration and the tombstone
/// store still need are kept here. The retired tree / revision / assembly
/// pipeline used to live in this library and was removed with it.
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

// ---------------------------------------------------------------------------
// Resource type
// ---------------------------------------------------------------------------

/// The three resources that share one content shape.
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

/// Identity of one node in the logical resource hierarchy.
///
/// Ids are opaque, non-empty and immutable; `sortOrder` is separate from
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

/// Identity of a resource node (tree root).
final class ResourceId extends NodeId {
  const ResourceId(super.value);

  @override
  String get nodeKind => 'resource';
}

/// Identity of a section node (direct child of a resource).
final class SectionId extends NodeId {
  const SectionId(super.value);

  @override
  String get nodeKind => 'section';
}

/// Identity of a part node (direct child of a section).
final class PartId extends NodeId {
  const PartId(super.value);

  @override
  String get nodeKind => 'part';
}

// ---------------------------------------------------------------------------
// Node / capacity / readiness state
// ---------------------------------------------------------------------------

/// Editorial state of a single node.
enum NodeStatus {
  draft,
  confirmed,
  archived;

  String get storageValue => name;
}

/// How a resource's content came into existence.
///
/// Kept because the legacy migration still records the authoring method in
/// metadata and must use the same stable storage vocabulary.
enum CreationMethod {
  manual,
  aiReference;

  String get storageValue => name;
}

/// Measured content size relative to the capacity policy.
///
/// `overflow` never means "must truncate": overflow content is still saved in
/// full, it only classifies the content.
enum CapacityStatus {
  normal,
  elastic,
  overflow;

  String get storageValue => name;
}

/// Assembled-version readiness of a resource.
enum ReadinessState {
  preparing,
  ready,
  failed,
  stale;

  String get storageValue => name;
}
