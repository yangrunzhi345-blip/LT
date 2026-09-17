import '../../../../application/resources/section_control_service.dart';
import '../../../../domain/resources/resource_contracts.dart';
import '../../../../domain/resources/resource_edit_command.dart';
import '../../../../domain/resources/section_control.dart';
import '../../../../domain/resources/section_control_events.dart';

/// Narrow section-control boundary consumed by the Studio UI.
///
/// Keeping the widget layer behind this interface means the section controls
/// can be widget-tested without SQLite, an LLM gateway or a generation runtime,
/// while production still goes through [SectionControlService] (the only place
/// that may write sections).
abstract interface class SectionControlRuntime {
  Stream<SectionControlEvent> get events;

  Future<SectionControlPage> listSections({
    required ResourceId resourceId,
    int limit,
    int offset,
  });

  Future<SectionControlEntry> readSection(SectionId id);

  Future<SectionControlEntry> createSection({
    required ResourceId resourceId,
    required String title,
  });

  Future<SectionControlEntry> renameSection({
    required SectionId id,
    required String title,
    required String expectedUpdatedAt,
  });

  Future<void> moveSection({
    required ResourceId resourceId,
    required SectionId id,
    required int targetIndex,
    required String expectedUpdatedAt,
  });

  Future<void> deleteSection({
    required SectionId id,
    required String expectedUpdatedAt,
  });

  Future<SectionValidationResult> validateSection(SectionId id);

  /// Writes one Part body.
  ///
  /// Added by Phase 9 so the Studio has an editable Part surface at all: the
  /// write goes through [SectionControlService] (the Phase 7 owner of Part
  /// edits) and therefore keeps the section verdict and the revision boundary
  /// consistent with the new text.
  Future<SectionControlEntry> updatePart({
    required SectionId sectionId,
    required PartId partId,
    required String expectedUpdatedAt,
    required String content,
    String? title,
  });

  Future<void> deletePart({
    required SectionId sectionId,
    required PartId partId,
    required String expectedUpdatedAt,
  });

  /// Current optimistic-locking token of a live Resource, or null when gone.
  Future<String?> readResourceUpdatedAt(ResourceId id);

  /// Current optimistic-locking token of a live Part, or null when it is gone.
  ///
  /// The editor needs it to write under a token instead of blind-overwriting;
  /// a null answer is what tells the editor the Part disappeared underneath it.
  Future<String?> readPartUpdatedAt(PartId partId);

  Future<SectionGenerationOutcome> regenerateSection({
    required SectionId id,
    required String expectedUpdatedAt,
    AiRewriteMode mode,
    String instruction,
  });

  void dispose();
}

/// Production adapter that forwards every command to [SectionControlService].
final class SectionControlServiceRuntime implements SectionControlRuntime {
  SectionControlServiceRuntime({required SectionControlService service})
      : _service = service;

  final SectionControlService _service;

  @override
  Stream<SectionControlEvent> get events => _service.events;

  @override
  Future<SectionControlPage> listSections({
    required ResourceId resourceId,
    int limit = 20,
    int offset = 0,
  }) =>
      _service.listSections(
        resourceId: resourceId,
        limit: limit,
        offset: offset,
      );

  @override
  Future<SectionControlEntry> readSection(SectionId id) =>
      _service.readSection(id);

  @override
  Future<SectionControlEntry> createSection({
    required ResourceId resourceId,
    required String title,
  }) =>
      _service.createSection(
        CreateSectionCommand(resourceId: resourceId, title: title),
      );

  @override
  Future<SectionControlEntry> renameSection({
    required SectionId id,
    required String title,
    required String expectedUpdatedAt,
  }) =>
      _service.updateSection(
        RenameSectionCommand(
          sectionId: id,
          title: title,
          expectedUpdatedAt: expectedUpdatedAt,
        ),
      );

  @override
  Future<void> moveSection({
    required ResourceId resourceId,
    required SectionId id,
    required int targetIndex,
    required String expectedUpdatedAt,
  }) =>
      _service.moveSection(
        MoveSectionCommand(
          resourceId: resourceId,
          sectionId: id,
          targetIndex: targetIndex,
          expectedUpdatedAt: expectedUpdatedAt,
        ),
      );

  @override
  Future<void> deleteSection({
    required SectionId id,
    required String expectedUpdatedAt,
  }) =>
      _service.deleteSection(
        DeleteSectionCommand(
          sectionId: id,
          expectedUpdatedAt: expectedUpdatedAt,
        ),
      );

  @override
  Future<SectionValidationResult> validateSection(SectionId id) =>
      _service.validateSection(id);

  @override
  Future<SectionControlEntry> updatePart({
    required SectionId sectionId,
    required PartId partId,
    required String expectedUpdatedAt,
    required String content,
    String? title,
  }) =>
      _service.updatePart(
        UpdatePartCommand(
          sectionId: sectionId,
          partId: partId,
          expectedUpdatedAt: expectedUpdatedAt,
          title: title,
          content: content,
        ),
      );

  @override
  Future<void> deletePart({
    required SectionId sectionId,
    required PartId partId,
    required String expectedUpdatedAt,
  }) =>
      _service.deletePart(
        DeletePartCommand(
          sectionId: sectionId,
          partId: partId,
          expectedUpdatedAt: expectedUpdatedAt,
        ),
      );

  @override
  Future<String?> readResourceUpdatedAt(ResourceId id) =>
      _service.readResourceUpdatedAt(id);

  @override
  Future<String?> readPartUpdatedAt(PartId partId) =>
      _service.readPartUpdatedAt(partId);

  @override
  Future<SectionGenerationOutcome> regenerateSection({
    required SectionId id,
    required String expectedUpdatedAt,
    AiRewriteMode mode = AiRewriteMode.regenerate,
    String instruction = '',
  }) =>
      _service.regenerateSection(
        RegenerateSectionCommand(
          sectionId: id,
          expectedUpdatedAt: expectedUpdatedAt,
          mode: mode,
          instruction: instruction,
        ),
      );

  @override
  void dispose() => _service.dispose();
}
