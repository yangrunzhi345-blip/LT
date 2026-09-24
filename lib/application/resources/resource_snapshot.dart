import '../../domain/resources/resource_contracts.dart';

/// Small identity record for a resource at one revision boundary.
final class ResourceSnapshot {
  const ResourceSnapshot({
    required this.resourceId,
    required this.revisionId,
    required this.createdAt,
    required this.source,
    this.metadata = const <String, Object?>{},
  });

  factory ResourceSnapshot.initial({
    required ResourceId resourceId,
    required ResourceRevisionId revisionId,
    required String createdAt,
    String source = 'initial',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) =>
      ResourceSnapshot(
        resourceId: resourceId,
        revisionId: revisionId,
        createdAt: createdAt,
        source: source,
        metadata: Map<String, Object?>.unmodifiable(metadata),
      );

  final ResourceId resourceId;
  final ResourceRevisionId revisionId;
  final String createdAt;
  final String source;
  final Map<String, Object?> metadata;

  ResourceSnapshot copyWith({
    ResourceRevisionId? revisionId,
    String? createdAt,
    String? source,
    Map<String, Object?>? metadata,
  }) =>
      ResourceSnapshot(
        resourceId: resourceId,
        revisionId: revisionId ?? this.revisionId,
        createdAt: createdAt ?? this.createdAt,
        source: source ?? this.source,
        metadata: Map<String, Object?>.unmodifiable(metadata ?? this.metadata),
      );

  static ResourceSnapshot? latest(Iterable<ResourceSnapshot> snapshots) {
    final values = snapshots.toList();
    if (values.isEmpty) return null;
    values.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return values.last;
  }
}
