/// Persistence contract for Phase 7 section controls.
///
/// The interface is deliberately narrow and page-bounded:
/// - section listing is always paginated (`limit` / `offset`), so the Studio
///   never loads a whole resource tree to show a section list;
/// - Part data is read either as an aggregate (counts + bounded preview) for a
///   page of sections, or as full rows for exactly one section during
///   validation.
///
/// Long body text stays in `resource_parts.content`; nothing here caches or
/// copies a whole resource.
library;

import 'resource_contracts.dart';
import 'section_control.dart';

/// Persisted columns of one section needed by section controls.
///
/// Timestamps stay in storage form (ISO-8601 strings) because they double as
/// optimistic-locking tokens; the application layer converts them to
/// `DateTime` when building a [SectionControlEntry].
final class SectionControlRow {
  const SectionControlRow({
    required this.id,
    required this.resourceId,
    required this.title,
    required this.summary,
    required this.orderIndex,
    required this.status,
    required this.validationState,
    required this.validationMessage,
    required this.createdAt,
    required this.updatedAt,
    this.validatedAt,
  });

  final SectionId id;
  final ResourceId resourceId;
  final String title;
  final String summary;
  final int orderIndex;
  final NodeStatus status;
  final SectionValidationState validationState;
  final String validationMessage;
  final String createdAt;
  final String updatedAt;

  /// Null while the section has never been validated.
  final String? validatedAt;

  @override
  String toString() => 'SectionControlRow(${id.value}, order: $orderIndex, '
      'validation: ${validationState.storageValue})';
}

/// Per-section aggregate of its Parts.
///
/// [preview] is a bounded prefix of the concatenated Part content: enough for
/// a list row or a status hint, never the whole section body.
final class SectionPartSummary {
  const SectionPartSummary({
    required this.partCount,
    required this.characterCount,
    required this.preview,
  });

  final int partCount;
  final int characterCount;
  final String preview;

  bool get hasContent => characterCount > 0;

  static const SectionPartSummary empty = SectionPartSummary(
    partCount: 0,
    characterCount: 0,
    preview: '',
  );
}

/// One page of section rows plus the total row count.
final class SectionControlPageData {
  const SectionControlPageData({
    required this.rows,
    required this.totalCount,
    required this.offset,
  });

  final List<SectionControlRow> rows;
  final int totalCount;
  final int offset;
}

/// One Phase 5 generation task bound to a section.
final class SectionTaskRow {
  const SectionTaskRow({
    required this.taskId,
    required this.blueprintId,
    required this.resourceId,
    required this.sectionId,
    required this.partId,
    required this.status,
  });

  final String taskId;
  final String blueprintId;
  final String resourceId;
  final SectionId sectionId;
  final PartId partId;

  /// Raw `PartTaskStatus` storage value; the domain rollup interprets it.
  final String status;

  @override
  String toString() =>
      'SectionTaskRow($taskId, part: ${partId.value}, status: $status)';
}

/// One full Part row, read only for a single section during validation.
final class SectionPartRow {
  const SectionPartRow({
    required this.id,
    required this.sectionId,
    required this.title,
    required this.content,
    required this.orderIndex,
  });

  final PartId id;
  final SectionId sectionId;
  final String title;
  final String content;
  final int orderIndex;
}

/// Section-control persistence boundary.
abstract interface class ISectionControlRepository {
  /// Reads one page of sections of [resourceId] in canonical order.
  ///
  /// Implementations must apply `LIMIT`/`OFFSET` in SQL and must not assemble
  /// the whole tree to answer this.
  Future<SectionControlPageData> readSectionPage({
    required ResourceId resourceId,
    required int limit,
    required int offset,
  });

  /// Reads one section row, or null when it does not exist / is deleted.
  Future<SectionControlRow?> findSectionControlRow(SectionId id);

  /// Aggregates Part counts and previews for [sectionIds] in one query.
  Future<Map<String, SectionPartSummary>> readPartSummaries(
    Iterable<SectionId> sectionIds,
  );

  /// Reads the Phase 5 generation tasks bound to [sectionIds] in one query.
  ///
  /// Tasks are what make a section regenerable; an empty result means the
  /// section was authored outside the AI pipeline and cannot be regenerated.
  Future<List<SectionTaskRow>> readSectionTasks(
    Iterable<SectionId> sectionIds,
  );

  /// Reads every live Part of exactly one section, with full content.
  ///
  /// Used only by validation, which is by definition section-scoped.
  Future<List<SectionPartRow>> readSectionParts(SectionId sectionId);

  /// Persists the validation outcome of one section under optimistic locking.
  ///
  /// Implementations must reject a stale [expectedUpdatedAt] instead of
  /// overwriting a newer edit.
  Future<void> updateSectionValidation({
    required SectionId id,
    required String expectedUpdatedAt,
    required SectionValidationState state,
    required String message,
    DateTime? validatedAt,
  });
}
