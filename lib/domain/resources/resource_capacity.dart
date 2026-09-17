import 'resource_contracts.dart';
import 'resource_limits.dart';

/// Measured capacity of one resource.
///
/// This is a *measurement*, not a policy: it reports what the tree currently
/// holds and classifies it through [ResourceLimits.policyFor]. It never
/// truncates, and an [CapacityStatus.overflow] measurement is a normal,
/// fully-persisted state that only schedules compression work.
///
/// Counts are produced by a single aggregate query over the live tree, so
/// building a snapshot is O(parts of one resource), never O(sections × parts).
final class ResourceCapacitySnapshot {
  const ResourceCapacitySnapshot({
    required this.resourceId,
    required this.type,
    required this.totalCharacters,
    required this.activeCharacters,
    required this.archivedCharacters,
    required this.estimatedTokens,
    required this.sectionCount,
    required this.partCount,
    required this.historicalRevisionCount,
    required this.status,
    this.measuredAt,
  });

  final ResourceId resourceId;
  final ResourceType type;

  /// Total live body characters across every non-deleted Part.
  final int totalCharacters;

  /// Characters held by Parts whose status is not `archived`.
  final int activeCharacters;

  /// Characters held by `archived` Parts; still stored, only excluded from the
  /// active head by later phases.
  final int archivedCharacters;

  /// Conservative token estimate derived from [totalCharacters].
  final int estimatedTokens;

  final int sectionCount;
  final int partCount;

  /// How many recorded generation attempts exist for this resource.
  ///
  /// Immutable revisions belong to Phase 9; until then the attempt history is
  /// the only durable record of previous content versions, so it is reported
  /// here under a name that stays honest about what it counts.
  final int historicalRevisionCount;

  final CapacityStatus status;

  /// When the measurement was taken; null for a freshly computed snapshot that
  /// has not been persisted yet.
  final DateTime? measuredAt;

  /// Archived content is measured in characters, so "size" and "characters"
  /// are the same unit and never drift apart.
  int get archiveSize => archivedCharacters;

  /// Measured characters as a fraction of the absolute budget.
  double get fillRatio {
    final absolute = ResourceLimits.policyFor(type).absoluteCharacters;
    if (absolute <= 0) return 0;
    return totalCharacters / absolute;
  }

  bool get needsCompression => status != CapacityStatus.normal;

  ResourceCapacitySnapshot copyWith({
    int? totalCharacters,
    int? activeCharacters,
    int? archivedCharacters,
    int? estimatedTokens,
    int? sectionCount,
    int? partCount,
    int? historicalRevisionCount,
    CapacityStatus? status,
    DateTime? measuredAt,
  }) {
    return ResourceCapacitySnapshot(
      resourceId: resourceId,
      type: type,
      totalCharacters: totalCharacters ?? this.totalCharacters,
      activeCharacters: activeCharacters ?? this.activeCharacters,
      archivedCharacters: archivedCharacters ?? this.archivedCharacters,
      estimatedTokens: estimatedTokens ?? this.estimatedTokens,
      sectionCount: sectionCount ?? this.sectionCount,
      partCount: partCount ?? this.partCount,
      historicalRevisionCount:
          historicalRevisionCount ?? this.historicalRevisionCount,
      status: status ?? this.status,
      measuredAt: measuredAt ?? this.measuredAt,
    );
  }

  @override
  String toString() => 'ResourceCapacitySnapshot($resourceId, '
      '$totalCharacters chars, $sectionCount sections, $partCount parts, '
      '${status.storageValue})';
}

/// Measured capacity of one Section.
///
/// Sections have no independent budget in the frozen capacity policy; this
/// snapshot exists to rank compression targets by redundancy within the
/// resource budget.
final class SectionCapacitySnapshot {
  const SectionCapacitySnapshot({
    required this.sectionId,
    required this.title,
    required this.characters,
    required this.partCount,
    required this.largestPartCharacters,
    required this.isComplete,
  });

  final SectionId sectionId;
  final String title;
  final int characters;
  final int partCount;

  /// Size of the biggest Part in the section; a section whose largest Part is
  /// already bounded is cheaper to compress Part-by-Part.
  final int largestPartCharacters;

  /// True when the section has Parts and every Part holds non-empty content.
  final bool isComplete;

  /// A section is a plausible compression target when it is complete and its
  /// combined body is at least the minimum compressible size.
  bool get isCompressionCandidate =>
      isComplete && characters >= ResourceLimits.minCompressibleNodeCharacters;

  /// Average characters per Part; used to rank the most redundant sections
  /// first. A part count of zero reports zero rather than dividing by zero.
  double get averagePartCharacters =>
      partCount == 0 ? 0 : characters / partCount;

  @override
  String toString() => 'SectionCapacitySnapshot($sectionId, '
      '$characters chars, $partCount parts, complete: $isComplete)';
}

/// Pure capacity arithmetic shared by the repository and the services.
abstract final class ResourceCapacityMath {
  /// Conservative token estimate for an aggregated character count.
  ///
  /// Per-text estimation still belongs to `TokenEstimator`; this exists only
  /// because an aggregate query returns a character total, not the text.
  static int tokensForCharacters(int characters) {
    if (characters <= 0) return 0;
    return (characters * ResourceLimits.capacityTokenWeightPerCharacter).ceil();
  }

  /// Classifies a measured character count for [type] through the single
  /// capacity policy. Never accepts a negative count.
  static CapacityStatus statusFor(ResourceType type, int characters) =>
      ResourceLimits.policyFor(type).statusFor(characters);
}
