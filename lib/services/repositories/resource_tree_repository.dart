import '../../domain/resources/resource_contracts.dart';

/// Flat representation of the resource tree the setting-card migration reads.
///
/// Only the draft value types survive; the unified tree repository, its
/// exceptions and its interface were retired with the generation pipeline. The
/// migration still needs a neutral description of "one resource with sections
/// and parts" to map a legacy card into a setting card.

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
  /// copy and so metadata can reference the node it just created.
  final PartId? id;

  final String title;
  final String content;
  final NodeStatus status;
}

/// One Section, with its ordered Parts.
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

/// A complete tree description.
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
