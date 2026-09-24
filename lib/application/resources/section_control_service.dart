import '../../domain/resources/resource_contracts.dart';
import '../../domain/errors/app_error.dart';
import '../../core/localization/app_error_localizer.dart';
import '../../domain/resources/resource_edit_command.dart';
import '../../domain/resources/resource_revision.dart';
import '../../domain/resources/section_control.dart';
import '../../domain/resources/section_control_events.dart';
import '../../domain/resources/section_control_repository.dart';
import '../../domain/resources/section_generation_binding.dart';
import '../../services/repositories/resource_tree_repository.dart';
import 'part_content_commit_service.dart';
import 'resource_revision_service.dart';
import 'resource_trash_service.dart';
import 'section_control_event_bus.dart';
import 'section_regeneration.dart';

/// Aggregate result of regenerating one section.
final class SectionGenerationOutcome {
  const SectionGenerationOutcome({
    required this.sectionId,
    required this.generationId,
    required this.partCount,
    required this.completedPartCount,
    required this.characterCount,
    required this.success,
    @Deprecated('Use error for new runtime failures.') this.errorMessage = '',
    this.error,
  });

  final SectionId sectionId;

  /// Orchestration id for this section run. The per-Part protocol ids are
  /// owned by the Phase 5 runtime and are not re-invented here.
  final String generationId;
  final int partCount;
  final int completedPartCount;
  final int characterCount;
  final bool success;
  @Deprecated('Use error for new runtime failures.')
  final String errorMessage;
  final AppDomainError? error;

  @override
  String toString() => 'SectionGenerationOutcome(${sectionId.value}, '
      '$completedPartCount/$partCount, success: $success)';
}

/// The single entry point for every section-level operation.
///
/// UI code must not touch the database or the trees directly: create, edit,
/// move, delete, validate and regenerate all pass through this service, which
/// is where commands are validated, optimistic locking is enforced, and one
/// typed event is emitted per accepted state change.
///
/// Generation itself is delegated to a [SectionRegenerationExecutor], which
/// reuses the frozen Phase 5 incremental protocol per Part. This service never
/// builds JSON and never issues a whole-resource request.
final class SectionControlService {
  SectionControlService({
    required ISectionControlRepository repository,
    required IResourceTreeRepository treeRepository,
    required SectionRegenerationExecutor regenerationExecutor,
    SectionControlEventBus? eventBus,
    PartContentCommitService? partCommitService,
    ResourceTrashService? trashService,
    ResourceRevisionService? revisionService,
    this.defaultPageSize = 20,
    this.maxPageSize = 100,
  })  : _repository = repository,
        _treeRepository = treeRepository,
        _regenerationExecutor = regenerationExecutor,
        _eventBus = eventBus ?? SectionControlEventBus(),
        _ownsEventBus = eventBus == null,
        _partCommitService = partCommitService,
        _trashService = trashService,
        _revisionService = revisionService,
        assert(defaultPageSize > 0, 'defaultPageSize must be positive'),
        assert(
            maxPageSize >= defaultPageSize, 'maxPageSize must cover default');

  final ISectionControlRepository _repository;
  final IResourceTreeRepository _treeRepository;
  final SectionRegenerationExecutor _regenerationExecutor;
  final SectionControlEventBus _eventBus;
  final bool _ownsEventBus;

  /// Phase 9 boundaries. Optional so the Phase 7 unit tests that build this
  /// service with only its Phase 7 dependencies keep their exact behaviour; the
  /// production composition root always injects them.
  final PartContentCommitService? _partCommitService;
  final ResourceTrashService? _trashService;
  final ResourceRevisionService? _revisionService;

  /// Default number of sections returned per query.
  final int defaultPageSize;

  /// Hard cap so a caller cannot turn paging back into a whole-tree read.
  final int maxPageSize;

  /// Ordered stream of accepted section-control events.
  Stream<SectionControlEvent> get events => _eventBus.stream;

  /// Bounded history of published events; useful for tests and diagnostics.
  List<SectionControlEventRecord> get eventHistory => _eventBus.history;

  // ─── Queries ───

  /// Reads one page of sections for [resourceId].
  ///
  /// The page is bounded by [maxPageSize]; entries carry a bounded content
  /// preview rather than the whole section body.
  Future<SectionControlPage> listSections({
    required ResourceId resourceId,
    int? limit,
    int offset = 0,
  }) async {
    final effectiveLimit =
        (limit ?? defaultPageSize).clamp(1, maxPageSize).toInt();
    final page = await _repository.readSectionPage(
      resourceId: resourceId,
      limit: effectiveLimit,
      offset: offset,
    );
    if (page.rows.isEmpty) {
      return SectionControlPage(
        entries: const <SectionControlEntry>[],
        totalCount: page.totalCount,
        offset: page.offset,
      );
    }

    final ids = page.rows.map((row) => row.id).toList(growable: false);
    final summaries = await _repository.readPartSummaries(ids);
    final tasksBySection = _groupTaskStatuses(
      await _repository.readSectionTasks(ids),
    );

    return SectionControlPage(
      entries: [
        for (final row in page.rows)
          _entryFrom(
            row: row,
            summary: summaries[row.id.value] ?? SectionPartSummary.empty,
            taskStatuses: tasksBySection[row.id.value] ?? const <String>[],
          ),
      ],
      totalCount: page.totalCount,
      offset: page.offset,
    );
  }

  /// Reads exactly one section with its full Part content.
  Future<SectionControlEntry> readSection(SectionId id) async {
    final row = await _requireRow(id);
    final parts = await _repository.readSectionParts(id);
    final tasks = await _repository.readSectionTasks([id]);
    final content = parts.map((part) => part.content).join('\n');
    return _entryFrom(
      row: row,
      summary: SectionPartSummary(
        partCount: parts.length,
        characterCount: content.length,
        preview: content,
      ),
      taskStatuses: tasks.map((task) => task.status).toList(growable: false),
    );
  }

  // ─── Local edit commands ───

  /// Appends one new section and returns the created entry.
  Future<SectionControlEntry> createSection(
      CreateSectionCommand command) async {
    ResourceEditCommandValidator.validate(command);
    final result = await _treeRepository.mount(
      AppendSectionPatch(
        resourceId: command.resourceId,
        title: command.title.trim(),
        summary: command.summary,
      ),
    );
    final nodeId = result.nodeId;
    if (nodeId is! SectionId) {
      throw SectionControlException('创建 Section 返回了非 Section 节点：$nodeId');
    }
    final entry = await readSection(nodeId);
    _eventBus.publish(
      SectionCreatedEvent(
        resourceId: command.resourceId,
        sectionId: nodeId,
        timestamp: DateTime.now(),
        title: entry.title,
        orderIndex: entry.orderIndex,
      ),
    );
    return entry;
  }

  /// Renames or updates exactly one section.
  ///
  /// Accepts [RenameSectionCommand] or [UpdateSectionCommand]; the optimistic
  /// token inside the command is enforced by the tree repository.
  Future<SectionControlEntry> updateSection(ResourceEditCommand command) async {
    ResourceEditCommandValidator.validate(command);
    final SectionId sectionId;
    final String? title;
    final String? summary;
    switch (command) {
      case RenameSectionCommand():
        sectionId = command.sectionId;
        title = command.title.trim();
        summary = null;
      case UpdateSectionCommand():
        sectionId = command.sectionId;
        title = command.title?.trim();
        summary = command.summary;
      default:
        throw SectionControlException(
          '不支持的 Section 更新命令：${command.commandKind}',
        );
    }

    await _treeRepository.updateSection(
      id: sectionId,
      expectedUpdatedAt: command.expectedUpdatedAt,
      title: title,
      summary: summary,
    );
    final entry = await readSection(sectionId);
    _eventBus.publish(
      SectionUpdatedEvent(
        resourceId: entry.resourceId,
        sectionId: sectionId,
        timestamp: DateTime.now(),
        title: entry.title,
      ),
    );
    return entry;
  }

  /// Moves one section to an explicit sibling position.
  ///
  /// Only the sibling order changes; identities and content are untouched.
  Future<void> moveSection(MoveSectionCommand command) async {
    ResourceEditCommandValidator.validate(command);
    final sections = await _treeRepository.readSections(command.resourceId);
    final ids = sections.map((section) => section.id).toList();
    final fromIndex = ids.indexOf(command.sectionId);
    if (fromIndex < 0) {
      throw SectionControlException(
        'Section ${command.sectionId.value} 不属于资源 '
        '${command.resourceId.value}',
      );
    }
    if (fromIndex == command.targetIndex) return;

    final moving = ids.removeAt(fromIndex);
    final toIndex = command.targetIndex.clamp(0, ids.length);
    ids.insert(toIndex, moving);

    await _treeRepository.reorderSections(
      resourceId: command.resourceId,
      orderedIds: ids,
    );
    _eventBus.publish(
      SectionMovedEvent(
        resourceId: command.resourceId,
        sectionId: command.sectionId,
        timestamp: DateTime.now(),
        fromIndex: fromIndex,
        toIndex: toIndex,
      ),
    );
  }

  /// Soft deletes one section together with its Parts.
  Future<void> deleteSection(DeleteSectionCommand command) async {
    ResourceEditCommandValidator.validate(command);
    final row = await _requireRow(command.sectionId);
    final trash = _trashService;
    if (trash != null) {
      // Phase 9: the delete first becomes a recycle-bin record, so nothing is
      // physically lost and the section can come back with its order intact.
      await trash.deleteNode(
        id: command.sectionId,
        expectedUpdatedAt: command.expectedUpdatedAt,
      );
    } else {
      await _treeRepository.softDeleteNode(
        id: command.sectionId,
        expectedUpdatedAt: command.expectedUpdatedAt,
      );
    }
    _eventBus.publish(
      SectionDeletedEvent(
        resourceId: row.resourceId,
        sectionId: command.sectionId,
        timestamp: DateTime.now(),
      ),
    );
  }

  // ─── Part edit commands ───

  /// Updates one Part, then invalidates the owning section's verdict.
  ///
  /// With the Phase 9 boundary attached the body, the verdict downgrade, the
  /// revision head and the generation-task reset all commit together, so an
  /// autosave flush can never leave the stored text and the section verdict
  /// disagreeing.
  Future<SectionControlEntry> updatePart(UpdatePartCommand command) async {
    ResourceEditCommandValidator.validate(command);
    final commitService = _partCommitService;
    final content = command.content;
    if (commitService == null || content == null) {
      // Title-only edits (and unit tests without the Phase 9 boundary) keep the
      // Phase 7 path: nothing about the body changes, so there is no revision
      // to record and no session verdict to downgrade beyond the existing rule.
      await _treeRepository.updatePart(
        id: command.partId,
        expectedUpdatedAt: command.expectedUpdatedAt,
        title: command.title?.trim(),
        content: content,
      );
      await _invalidateSectionValidation(
        command.sectionId,
        reason: 'Part ${command.partId.value} 正文已修改',
      );
      return readSection(command.sectionId);
    }

    final result = await commitService.applyContent(
      PartContentCommitRequest(
        partId: command.partId,
        expectedUpdatedAt: command.expectedUpdatedAt,
        content: content,
        title: command.title?.trim(),
        reason: 'Part ${command.partId.value} 正文已修改',
      ),
    );
    if (result.validationDowngraded) {
      _eventBus.publish(
        SectionValidationResetEvent(
          resourceId: result.resourceId,
          sectionId: result.sectionId,
          timestamp: DateTime.now(),
          reason: 'Part ${command.partId.value} 正文已修改',
        ),
      );
    }
    return readSection(command.sectionId);
  }

  /// Reads the optimistic-locking token of one live Resource.
  ///
  /// Returns null when the resource is missing or already deleted.
  Future<String?> readResourceUpdatedAt(ResourceId id) async {
    final state = await _treeRepository.readNodeState(id);
    if (state == null || state.isDeleted) return null;
    return state.updatedAt;
  }

  /// Reads the optimistic-locking token of one live Part.
  ///
  /// Returns null for a Part that is missing or already deleted, so a caller
  /// about to write can tell "gone" apart from "changed".
  Future<String?> readPartUpdatedAt(PartId id) async {
    final state = await _treeRepository.readNodeState(id);
    if (state == null || state.isDeleted) return null;
    return state.updatedAt;
  }

  /// Soft deletes one Part, then invalidates the owning section's verdict.
  Future<SectionControlEntry> deletePart(DeletePartCommand command) async {
    ResourceEditCommandValidator.validate(command);
    final trash = _trashService;
    if (trash != null) {
      await trash.deleteNode(
        id: command.partId,
        expectedUpdatedAt: command.expectedUpdatedAt,
      );
    } else {
      await _treeRepository.softDeleteNode(
        id: command.partId,
        expectedUpdatedAt: command.expectedUpdatedAt,
      );
    }
    await _invalidateSectionValidation(
      command.sectionId,
      reason: 'Part ${command.partId.value} 已删除',
    );
    return readSection(command.sectionId);
  }

  /// Reorders one Part inside its section.
  Future<void> movePart(MovePartCommand command) async {
    ResourceEditCommandValidator.validate(command);
    final parts = await _treeRepository.readParts(command.sectionId);
    final ids = parts.map((part) => part.id).toList();
    final fromIndex = ids.indexOf(command.partId);
    if (fromIndex < 0) {
      throw SectionControlException(
        'Part ${command.partId.value} 不属于 Section '
        '${command.sectionId.value}',
      );
    }
    if (fromIndex == command.targetIndex) return;

    final moving = ids.removeAt(fromIndex);
    final toIndex = command.targetIndex.clamp(0, ids.length);
    ids.insert(toIndex, moving);
    await _treeRepository.reorderParts(
      sectionId: command.sectionId,
      orderedIds: ids,
    );
    await _invalidateSectionValidation(
      command.sectionId,
      reason: 'Part 顺序已调整',
    );
  }

  // ─── Validation ───

  /// Validates one section's committed content and persists the verdict.
  ///
  /// The stored verdict is written under the section's optimistic token, so a
  /// section edited between read and write rejects the verdict instead of
  /// recording a stale "valid".
  Future<SectionValidationResult> validateSection(SectionId sectionId) async {
    final row = await _requireRow(sectionId);
    final parts = await _repository.readSectionParts(sectionId);

    _eventBus.publish(
      SectionValidationStartedEvent(
        resourceId: row.resourceId,
        sectionId: sectionId,
        timestamp: DateTime.now(),
      ),
    );

    final result = SectionContentValidator.validate(
      sectionId: sectionId,
      parts: [
        for (final part in parts)
          SectionValidationPart(
            partId: part.id,
            title: part.title,
            content: part.content,
          ),
      ],
    );

    await _repository.updateSectionValidation(
      id: sectionId,
      expectedUpdatedAt: row.updatedAt,
      state: result.state,
      message:
          result.isValid ? '' : encodeSectionValidationIssues(result.issues),
      validatedAt: DateTime.now(),
    );

    if (result.isValid) {
      _eventBus.publish(
        SectionValidationPassedEvent(
          resourceId: row.resourceId,
          sectionId: sectionId,
          timestamp: DateTime.now(),
          characterCount: result.characterCount,
        ),
      );
    } else {
      _eventBus.publish(
        SectionValidationFailedEvent(
          resourceId: row.resourceId,
          sectionId: sectionId,
          timestamp: DateTime.now(),
          issues: result.issues,
          errorMessage: result.isValid
              ? ''
              : encodeSectionValidationIssues(result.issues),
        ),
      );
    }
    return result;
  }

  // ─── Generation ───

  /// Regenerates every Part of one section through the Phase 5 runtime.
  ///
  /// A section is only regenerable when it has persisted generation tasks. A
  /// manually authored section has none, so the command is rejected instead of
  /// inventing a second generation path.
  ///
  /// The command's `expectedUpdatedAt` token is checked against the persisted
  /// section before any Part is re-run: regenerating replaces the section's
  /// Part bodies, so a section edited (or whose Parts were edited) since the
  /// caller read it must be rejected rather than silently overwritten.
  Future<SectionGenerationOutcome> regenerateSection(
    RegenerateSectionCommand command,
  ) async {
    ResourceEditCommandValidator.validate(command);
    final row = await _requireRow(command.sectionId);
    if (row.updatedAt != command.expectedUpdatedAt) {
      throw SectionControlException(
        'Section ${command.sectionId.value} 已被并发修改'
        '（期望 updated_at=${command.expectedUpdatedAt}，'
        '当前 ${row.updatedAt}），重新生成被拒绝',
      );
    }
    final tasks = await _repository.readSectionTasks([command.sectionId]);
    if (tasks.isEmpty) {
      throw SectionControlException(
        'Section ${command.sectionId.value} 没有可重新生成的生成任务'
        '（该 Section 不是由 AI 蓝图创建的）',
      );
    }

    final generationId =
        'secgen_${command.sectionId.value}_${DateTime.now().microsecondsSinceEpoch}';

    // Phase 9 revision boundary: snapshot the current state and reopen the
    // completed tasks this regeneration is about to replace, before any model
    // call happens. Without the reset a fully generated section could never be
    // regenerated at all (Phase 5 refuses to restart a completed task); with it,
    // the previous content is always reachable through the recorded revision.
    final revisionService = _revisionService;
    if (revisionService != null) {
      await revisionService.beginLossyOperation(
        row.resourceId,
        cause: RevisionCause.regeneration,
        partIds: tasks.map((task) => task.partId.value),
        label: '${command.mode.storageValue} 前快照',
      );
    }

    _eventBus.publish(
      SectionGenerationStartedEvent(
        resourceId: row.resourceId,
        sectionId: command.sectionId,
        timestamp: DateTime.now(),
        generationId: generationId,
        mode: command.mode,
        partCount: tasks.length,
      ),
    );

    var completed = 0;
    var characterCount = 0;
    AppDomainError? failure;
    final userInstruction = _composeInstruction(
      command.mode,
      command.instruction,
    );

    for (final task in tasks) {
      final binding = SectionGenerationBinding(
        generationId: generationId,
        resourceId: row.resourceId,
        sectionId: command.sectionId,
        partId: task.partId,
      );
      try {
        final outcome = await _regenerationExecutor.regenerate(
          SectionRegenerationRequest(
            resourceId: row.resourceId,
            sectionId: command.sectionId,
            partId: task.partId,
            taskId: task.taskId,
            blueprintId: task.blueprintId,
            mode: command.mode,
            instruction: userInstruction,
          ),
        );
        _assertOutcomeBelongsToBinding(binding, outcome);
        if (!outcome.success) {
          failure = outcome.error ??
              const AppDomainError(
                code: AppErrorCode.resourceGenerationFailed,
              );
          break;
        }
        completed++;
        characterCount += outcome.characterCount;
      } on SectionGenerationBindingException catch (error) {
        // A binding mismatch (stale generation, sibling section, wrong Part)
        // and any runtime failure both stop this section run: the remaining
        // Parts must not be generated on top of a half-applied section.
        failure = AppDomainError(
          code: AppErrorCode.resourceConflict,
          parameters: {
            'field': error.field.name,
            'expected': error.expected,
            'actual': error.actual,
          },
          debugMessage: error.toString(),
          cause: error,
        );
        break;
      } catch (error, stackTrace) {
        failure = asAppDomainError(error, stackTrace);
        break;
      }
    }

    final success = failure == null && completed == tasks.length;
    if (success) {
      _eventBus.publish(
        SectionGenerationCompletedEvent(
          resourceId: row.resourceId,
          sectionId: command.sectionId,
          timestamp: DateTime.now(),
          generationId: generationId,
          completedPartCount: completed,
          characterCount: characterCount,
        ),
      );
    } else {
      _eventBus.publish(
        SectionGenerationFailedEvent(
          resourceId: row.resourceId,
          sectionId: command.sectionId,
          timestamp: DateTime.now(),
          generationId: generationId,
          error: failure ??
              const AppDomainError(
                code: AppErrorCode.resourceGenerationFailed,
              ),
        ),
      );
    }

    return SectionGenerationOutcome(
      sectionId: command.sectionId,
      generationId: generationId,
      partCount: tasks.length,
      completedPartCount: completed,
      characterCount: characterCount,
      success: success,
      error: failure,
    );
  }

  // ─── Internals ───

  /// A section's stored verdict is invalidated by any content edit.
  ///
  /// Uses the token read immediately before the write, so a concurrently edited
  /// section is left alone rather than overwritten. The resulting state comes
  /// from the single domain rule (`afterContentChange`), so a recorded verdict
  /// becomes `stale` and states that never described the current content are
  /// left untouched.
  Future<void> _invalidateSectionValidation(
    SectionId sectionId, {
    required String reason,
  }) async {
    final row = await _repository.findSectionControlRow(sectionId);
    if (row == null) return;
    final previous = row.validationState;
    final next = SectionValidationState.afterContentChange(previous);
    if (next == previous) return;

    await _repository.updateSectionValidation(
      id: sectionId,
      expectedUpdatedAt: row.updatedAt,
      state: next,
      message: '',
    );
    _eventBus.publish(
      SectionValidationResetEvent(
        resourceId: row.resourceId,
        sectionId: sectionId,
        timestamp: DateTime.now(),
        reason: reason,
      ),
    );
  }

  void _assertOutcomeBelongsToBinding(
    SectionGenerationBinding binding,
    SectionRegenerationOutcome outcome,
  ) {
    if (outcome.resourceId != binding.resourceId) {
      throw SectionGenerationBindingException(
        field: SectionBindingField.resourceId,
        expected: binding.resourceId.value,
        actual: outcome.resourceId.value,
      );
    }
    if (outcome.sectionId != binding.sectionId) {
      throw SectionGenerationBindingException(
        field: SectionBindingField.sectionId,
        expected: binding.sectionId.value,
        actual: outcome.sectionId.value,
      );
    }
    if (outcome.partId != binding.partId) {
      throw SectionGenerationBindingException(
        field: SectionBindingField.partId,
        expected: binding.partId.value,
        actual: outcome.partId.value,
      );
    }
  }

  /// Combines a rewrite mode's directive with the user's own instruction.
  ///
  /// `regenerate` with no instruction yields an empty string, so a plain
  /// regeneration keeps the original prompt unchanged.
  String _composeInstruction(AiRewriteMode mode, String instruction) {
    final trimmed = instruction.trim();
    return [
      if (mode.directive.isNotEmpty) mode.directive,
      if (trimmed.isNotEmpty) '用户补充要求：$trimmed',
    ].join('\n');
  }

  Future<SectionControlRow> _requireRow(SectionId id) async {
    final row = await _repository.findSectionControlRow(id);
    if (row == null) {
      throw SectionControlException('Section 不存在或已删除：${id.value}');
    }
    return row;
  }

  Map<String, List<String>> _groupTaskStatuses(List<SectionTaskRow> tasks) {
    final grouped = <String, List<String>>{};
    for (final task in tasks) {
      grouped
          .putIfAbsent(task.sectionId.value, () => <String>[])
          .add(task.status);
    }
    return grouped;
  }

  SectionControlEntry _entryFrom({
    required SectionControlRow row,
    required SectionPartSummary summary,
    required List<String> taskStatuses,
  }) {
    return SectionControlEntry(
      id: row.id,
      resourceId: row.resourceId,
      title: row.title,
      summary: row.summary,
      orderIndex: row.orderIndex,
      status: row.status,
      generationState: SectionGenerationRollup.fromTaskStatuses(
        taskStatuses,
        hasContent: summary.hasContent,
      ),
      validationState: row.validationState,
      validationMessage: row.validationMessage,
      content: summary.preview,
      partCount: summary.partCount,
      hasGenerationTasks: taskStatuses.isNotEmpty,
      createdAt: _parseDate(row.createdAt),
      updatedAt: _parseDate(row.updatedAt),
      updatedAtToken: row.updatedAt,
      validatedAt: _parseDate(row.validatedAt),
    );
  }

  DateTime? _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  /// Releases the internally created event bus.
  ///
  /// A caller-supplied bus is intentionally left open: the owner of an injected
  /// dependency is responsible for its lifetime.
  void dispose() {
    if (_ownsEventBus) _eventBus.dispose();
  }
}
