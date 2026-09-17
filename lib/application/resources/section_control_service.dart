import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_edit_command.dart';
import '../../domain/resources/section_control.dart';
import '../../domain/resources/section_control_events.dart';
import '../../domain/resources/section_control_repository.dart';
import '../../domain/resources/section_generation_binding.dart';
import '../../services/repositories/resource_tree_repository.dart';
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
    this.errorMessage = '',
  });

  final SectionId sectionId;

  /// Orchestration id for this section run. The per-Part protocol ids are
  /// owned by the Phase 5 runtime and are not re-invented here.
  final String generationId;
  final int partCount;
  final int completedPartCount;
  final int characterCount;
  final bool success;
  final String errorMessage;

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
    this.defaultPageSize = 20,
    this.maxPageSize = 100,
  })  : _repository = repository,
        _treeRepository = treeRepository,
        _regenerationExecutor = regenerationExecutor,
        _eventBus = eventBus ?? SectionControlEventBus(),
        _ownsEventBus = eventBus == null,
        assert(defaultPageSize > 0, 'defaultPageSize must be positive'),
        assert(
            maxPageSize >= defaultPageSize, 'maxPageSize must cover default');

  final ISectionControlRepository _repository;
  final IResourceTreeRepository _treeRepository;
  final SectionRegenerationExecutor _regenerationExecutor;
  final SectionControlEventBus _eventBus;
  final bool _ownsEventBus;

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
    await _treeRepository.softDeleteNode(
      id: command.sectionId,
      expectedUpdatedAt: command.expectedUpdatedAt,
    );
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
  Future<SectionControlEntry> updatePart(UpdatePartCommand command) async {
    ResourceEditCommandValidator.validate(command);
    await _treeRepository.updatePart(
      id: command.partId,
      expectedUpdatedAt: command.expectedUpdatedAt,
      title: command.title?.trim(),
      content: command.content,
    );
    await _invalidateSectionValidation(
      command.sectionId,
      reason: 'Part ${command.partId.value} 正文已修改',
    );
    return readSection(command.sectionId);
  }

  /// Soft deletes one Part, then invalidates the owning section's verdict.
  Future<SectionControlEntry> deletePart(DeletePartCommand command) async {
    ResourceEditCommandValidator.validate(command);
    await _treeRepository.softDeleteNode(
      id: command.partId,
      expectedUpdatedAt: command.expectedUpdatedAt,
    );
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
      message: result.issues.map((issue) => issue.message).join('；'),
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
          errorMessage: result.issues.map((issue) => issue.message).join('；'),
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
    var failureMessage = '';
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
          failureMessage = outcome.errorMessage.isEmpty
              ? 'Part ${task.partId.value} 生成失败'
              : outcome.errorMessage;
          break;
        }
        completed++;
        characterCount += outcome.characterCount;
      } catch (error) {
        // A binding mismatch (stale generation, sibling section, wrong Part)
        // and any runtime failure both stop this section run: the remaining
        // Parts must not be generated on top of a half-applied section.
        failureMessage = error.toString();
        break;
      }
    }

    final success = failureMessage.isEmpty && completed == tasks.length;
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
          errorMessage: failureMessage.isEmpty ? '生成被中止' : failureMessage,
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
      errorMessage: failureMessage,
    );
  }

  // ─── Internals ───

  /// A section's stored verdict is invalidated by any content edit.
  ///
  /// Uses the token read immediately before the write, so a concurrently edited
  /// section is left alone rather than overwritten.
  Future<void> _invalidateSectionValidation(
    SectionId sectionId, {
    required String reason,
  }) async {
    final row = await _repository.findSectionControlRow(sectionId);
    if (row == null) return;
    if (row.validationState == SectionValidationState.unvalidated) return;

    await _repository.updateSectionValidation(
      id: sectionId,
      expectedUpdatedAt: row.updatedAt,
      state: SectionValidationState.unvalidated,
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
