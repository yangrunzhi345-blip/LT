import 'resource_contracts.dart';
import 'resource_limits.dart';

/// Status of a blueprint in its lifecycle.
enum BlueprintStatus {
  draft,
  confirmed,
  superseded,
  cancelled;

  String get storageValue => name;

  static BlueprintStatus fromStorage(String? value) {
    for (final status in BlueprintStatus.values) {
      if (status.storageValue == value) return status;
    }
    return BlueprintStatus.draft;
  }
}

/// Pre-allocated pool of client-authorized IDs for blueprint nodes.
///
/// Models are only permitted to reference IDs authorized in this pool.
final class BlueprintIdPool {
  const BlueprintIdPool({
    required this.allowedSectionIds,
    required this.allowedPartIds,
  });

  /// Creates a default pool with sequential slot IDs (e.g. sec_1..sec_N, part_1..part_M).
  factory BlueprintIdPool.createDefault({
    int maxSections = 12,
    int maxParts = 36,
  }) {
    final sections = List<String>.generate(
      maxSections,
      (i) => 'sec_${i + 1}',
    );
    final parts = List<String>.generate(
      maxParts,
      (i) => 'part_${i + 1}',
    );
    return BlueprintIdPool(
      allowedSectionIds: List<String>.unmodifiable(sections),
      allowedPartIds: List<String>.unmodifiable(parts),
    );
  }

  final List<String> allowedSectionIds;
  final List<String> allowedPartIds;

  bool isSectionAllowed(String id) => allowedSectionIds.contains(id);

  bool isPartAllowed(String id) => allowedPartIds.contains(id);
}

/// One planned Part within a Section of the Blueprint.
///
/// A Part plan describes generation intent, budget and dependencies,
/// but deliberately NEVER contains full prose or body text.
final class BlueprintPart {
  const BlueprintPart({
    required this.id,
    required this.sectionId,
    required this.title,
    required this.generationGoal,
    required this.estimatedLength,
    this.dependencies = const <String>[],
    this.sortOrder = 0,
  });

  /// Client-controlled slot identity (e.g. "part_1").
  final String id;

  /// Identity of the parent Section.
  final String sectionId;

  /// Short descriptive title of the part.
  final String title;

  /// Specific goal/scope for what this part should generate.
  final String generationGoal;

  /// Target character length for this part.
  final int estimatedLength;

  /// Part IDs that must be generated before this part.
  final List<String> dependencies;

  /// Order of the part within its section.
  final int sortOrder;

  BlueprintPart copyWith({
    String? id,
    String? sectionId,
    String? title,
    String? generationGoal,
    int? estimatedLength,
    List<String>? dependencies,
    int? sortOrder,
  }) {
    return BlueprintPart(
      id: id ?? this.id,
      sectionId: sectionId ?? this.sectionId,
      title: title ?? this.title,
      generationGoal: generationGoal ?? this.generationGoal,
      estimatedLength: estimatedLength ?? this.estimatedLength,
      dependencies: dependencies != null
          ? List<String>.unmodifiable(dependencies)
          : this.dependencies,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BlueprintPart &&
          other.id == id &&
          other.sectionId == sectionId &&
          other.title == title &&
          other.generationGoal == generationGoal &&
          other.estimatedLength == estimatedLength &&
          other.sortOrder == sortOrder &&
          _listEquals(other.dependencies, dependencies);

  @override
  int get hashCode => Object.hash(
        id,
        sectionId,
        title,
        generationGoal,
        estimatedLength,
        sortOrder,
        Object.hashAll(dependencies),
      );

  @override
  String toString() =>
      'BlueprintPart(id: $id, section: $sectionId, title: $title, '
      'goal: $generationGoal, estLength: $estimatedLength, deps: $dependencies)';
}

/// One planned Section within the Blueprint.
final class BlueprintSection {
  BlueprintSection({
    required this.id,
    required this.title,
    this.summary = '',
    this.sortOrder = 0,
    List<BlueprintPart> parts = const <BlueprintPart>[],
  }) : parts = List<BlueprintPart>.unmodifiable(parts);

  /// Client-controlled slot identity (e.g. "sec_1").
  final String id;

  /// Short title of the section.
  final String title;

  /// Brief description of the section's thematic role.
  final String summary;

  /// Display and generation order.
  final int sortOrder;

  /// Ordered parts belonging to this section.
  final List<BlueprintPart> parts;

  int get totalEstimatedLength =>
      parts.fold<int>(0, (sum, part) => sum + part.estimatedLength);

  BlueprintSection copyWith({
    String? id,
    String? title,
    String? summary,
    int? sortOrder,
    List<BlueprintPart>? parts,
  }) {
    return BlueprintSection(
      id: id ?? this.id,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      sortOrder: sortOrder ?? this.sortOrder,
      parts: parts ?? this.parts,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BlueprintSection &&
          other.id == id &&
          other.title == title &&
          other.summary == summary &&
          other.sortOrder == sortOrder &&
          _listEquals(other.parts, parts);

  @override
  int get hashCode => Object.hash(
        id,
        title,
        summary,
        sortOrder,
        Object.hashAll(parts),
      );

  @override
  String toString() =>
      'BlueprintSection(id: $id, title: $title, parts: ${parts.length})';
}

/// A structured, compact plan for generating a resource.
///
/// Blueprint is the generation plan, NOT the prose. It outlines dynamic
/// sections, parts, goals, dependencies, and budgets.
final class ResourceBlueprint {
  ResourceBlueprint({
    required this.blueprintId,
    required this.sessionId,
    required this.resourceType,
    required this.suggestedName,
    required this.summary,
    this.revision = 1,
    this.status = BlueprintStatus.draft,
    int? targetCapacity,
    List<BlueprintSection> sections = const <BlueprintSection>[],
    this.resourceId,
    this.createdAt = '',
    this.updatedAt = '',
  })  : sections = List<BlueprintSection>.unmodifiable(sections),
        targetCapacity = targetCapacity ??
            ResourceLimits.policyFor(resourceType).nominalCharacters;

  final String blueprintId;
  final String sessionId;
  final ResourceType resourceType;
  final String suggestedName;
  final String summary;
  final int revision;
  final BlueprintStatus status;
  final int targetCapacity;
  final List<BlueprintSection> sections;
  final ResourceId? resourceId;
  final String createdAt;
  final String updatedAt;

  /// Sum of estimated character counts across all parts.
  int get totalEstimatedLength =>
      sections.fold<int>(0, (sum, sec) => sum + sec.totalEstimatedLength);

  /// Flattened list of all parts in the blueprint.
  List<BlueprintPart> get allParts =>
      sections.expand((sec) => sec.parts).toList(growable: false);

  int get sectionCount => sections.length;

  int get partCount => allParts.length;

  BlueprintSection? findSection(String sectionId) {
    for (final sec in sections) {
      if (sec.id == sectionId) return sec;
    }
    return null;
  }

  BlueprintPart? findPart(String partId) {
    for (final part in allParts) {
      if (part.id == partId) return part;
    }
    return null;
  }

  ResourceBlueprint copyWith({
    String? blueprintId,
    String? sessionId,
    ResourceType? resourceType,
    String? suggestedName,
    String? summary,
    int? revision,
    BlueprintStatus? status,
    int? targetCapacity,
    List<BlueprintSection>? sections,
    ResourceId? resourceId,
    String? createdAt,
    String? updatedAt,
  }) {
    return ResourceBlueprint(
      blueprintId: blueprintId ?? this.blueprintId,
      sessionId: sessionId ?? this.sessionId,
      resourceType: resourceType ?? this.resourceType,
      suggestedName: suggestedName ?? this.suggestedName,
      summary: summary ?? this.summary,
      revision: revision ?? this.revision,
      status: status ?? this.status,
      targetCapacity: targetCapacity ?? this.targetCapacity,
      sections: sections ?? this.sections,
      resourceId: resourceId ?? this.resourceId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResourceBlueprint &&
          other.blueprintId == blueprintId &&
          other.sessionId == sessionId &&
          other.resourceType == resourceType &&
          other.suggestedName == suggestedName &&
          other.summary == summary &&
          other.revision == revision &&
          other.status == status &&
          other.targetCapacity == targetCapacity &&
          other.resourceId == resourceId &&
          _listEquals(other.sections, sections);

  @override
  int get hashCode => Object.hash(
        blueprintId,
        sessionId,
        resourceType,
        suggestedName,
        summary,
        revision,
        status,
        targetCapacity,
        resourceId,
        Object.hashAll(sections),
      );

  @override
  String toString() =>
      'ResourceBlueprint(id: $blueprintId, session: $sessionId, '
      'type: ${resourceType.storageValue}, name: $suggestedName, '
      'revision: $revision, status: ${status.storageValue}, '
      'sections: $sectionCount, parts: $partCount, estLength: $totalEstimatedLength)';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
