import 'dart:async';

import 'package:lt_dialogue/application/resources/section_control_service.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_edit_command.dart';
import 'package:lt_dialogue/domain/resources/section_control.dart';
import 'package:lt_dialogue/domain/resources/section_control_events.dart';
import 'package:lt_dialogue/features/resource_studio/application/use_cases/section_control_runtime.dart';

/// In-memory [SectionControlRuntime] for widget tests.
///
/// It is deliberately a real little implementation rather than a mock: a
/// mutation is persisted in the in-memory list and the next page read returns
/// it, so tests exercise the same refresh-after-write contract the production
/// service has.
final class FakeSectionControlRuntime implements SectionControlRuntime {
  FakeSectionControlRuntime({List<SectionControlEntry>? entries})
      : entries = List<SectionControlEntry>.from(entries ?? const []);

  List<SectionControlEntry> entries;

  final List<String> renameCalls = <String>[];
  final List<String> deleteCalls = <String>[];
  final List<String> validateCalls = <String>[];
  final List<String> regenerateCalls = <String>[];
  final List<String> createCalls = <String>[];
  final List<String> loadMoreOffsets = <String>[];
  final List<String> partEditCalls = <String>[];
  final List<String> deletedParts = <String>[];

  /// When set, the next regenerate call reports this section id in its
  /// outcome, simulating a cross-section mismatch.
  SectionId? mismatchOutcomeSectionId;

  /// When set, the next operation throws this error.
  Object? nextError;

  int _tokenSeed = 0;
  bool _disposed = false;

  final StreamController<SectionControlEvent> _events =
      StreamController<SectionControlEvent>.broadcast();

  @override
  Stream<SectionControlEvent> get events => _events.stream;

  @override
  Future<SectionControlPage> listSections({
    required ResourceId resourceId,
    int limit = 20,
    int offset = 0,
  }) async {
    _throwIfNeeded();
    final ordered = List<SectionControlEntry>.from(entries)
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final slice = ordered.skip(offset).take(limit).toList();
    return SectionControlPage(
      entries: slice,
      totalCount: ordered.length,
      offset: offset,
    );
  }

  @override
  Future<SectionControlEntry> readSection(SectionId id) async =>
      entries.firstWhere((entry) => entry.id == id);

  @override
  Future<SectionControlEntry> createSection({
    required ResourceId resourceId,
    required String title,
  }) async {
    _throwIfNeeded();
    createCalls.add(title);
    final entry = SectionControlEntry(
      id: SectionId('sec_${entries.length + 1}'),
      resourceId: resourceId,
      title: title,
      orderIndex: entries.length,
      generationState: SectionGenerationState.pending,
      updatedAtToken: _nextToken(),
    );
    entries = [...entries, entry];
    _emit(
      SectionCreatedEvent(
        resourceId: resourceId,
        sectionId: entry.id,
        timestamp: DateTime(2026),
        title: title,
      ),
    );
    return entry;
  }

  @override
  Future<SectionControlEntry> renameSection({
    required SectionId id,
    required String title,
    required String expectedUpdatedAt,
  }) async {
    _throwIfNeeded();
    renameCalls.add('${id.value}:$title');
    final index = entries.indexWhere((entry) => entry.id == id);
    final updated = entries[index].copyWith(
      title: title,
      updatedAtToken: _nextToken(),
    );
    entries = [...entries]..[index] = updated;
    _emit(
      SectionUpdatedEvent(
        resourceId: updated.resourceId,
        sectionId: id,
        timestamp: DateTime(2026),
        title: title,
      ),
    );
    return updated;
  }

  @override
  Future<void> moveSection({
    required ResourceId resourceId,
    required SectionId id,
    required int targetIndex,
    required String expectedUpdatedAt,
  }) async {
    _throwIfNeeded();
    final ordered = List<SectionControlEntry>.from(entries)
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final moving = ordered.firstWhere((entry) => entry.id == id);
    ordered.remove(moving);
    ordered.insert(targetIndex.clamp(0, ordered.length), moving);
    entries = [
      for (var i = 0; i < ordered.length; i++)
        ordered[i].copyWith(orderIndex: i, updatedAtToken: _nextToken()),
    ];
  }

  @override
  Future<void> deleteSection({
    required SectionId id,
    required String expectedUpdatedAt,
  }) async {
    _throwIfNeeded();
    deleteCalls.add(id.value);
    final removed = entries.firstWhere((entry) => entry.id == id);
    entries = entries.where((entry) => entry.id != id).toList();
    _emit(
      SectionDeletedEvent(
        resourceId: removed.resourceId,
        sectionId: id,
        timestamp: DateTime(2026),
      ),
    );
  }

  @override
  Future<SectionControlEntry> updatePart({
    required SectionId sectionId,
    required PartId partId,
    required String expectedUpdatedAt,
    required String content,
    String? title,
  }) async {
    _throwIfNeeded();
    partEditCalls.add(partId.value);
    final index = entries.indexWhere((entry) => entry.id == sectionId);
    if (index < 0) {
      throw StateError('Section ${sectionId.value} 不存在');
    }
    final entry = entries[index];
    entries = [...entries]..[index] = entry.copyWith(
        content: content,
        updatedAtToken: _nextToken(),
        validationState: SectionValidationState.unvalidated,
        validationMessage: '',
      );
    return entries[index];
  }

  @override
  Future<void> deletePart({
    required SectionId sectionId,
    required PartId partId,
    required String expectedUpdatedAt,
  }) async {
    _throwIfNeeded();
    deletedParts.add(partId.value);
  }

  @override
  Future<String?> readPartUpdatedAt(PartId partId) async {
    _throwIfNeeded();
    return 'tok_${partId.value}';
  }

  @override
  Future<SectionValidationResult> validateSection(SectionId id) async {
    _throwIfNeeded();
    validateCalls.add(id.value);
    final index = entries.indexWhere((entry) => entry.id == id);
    final entry = entries[index];
    final result = entry.content.trim().isEmpty
        ? SectionValidationResult(
            sectionId: id,
            state: SectionValidationState.invalid,
            issues: const [
              SectionValidationIssue(message: 'Section 没有任何 Part，无法构成可组装内容'),
            ],
          )
        : SectionValidationResult(
            sectionId: id,
            state: SectionValidationState.valid,
            characterCount: entry.content.length,
          );
    entries = [...entries]..[index] = entry.copyWith(
        validationState: result.state,
        validationMessage:
            result.issues.map((issue) => issue.message).join('；'),
        updatedAtToken: _nextToken(),
      );
    _emit(
      result.isValid
          ? SectionValidationPassedEvent(
              resourceId: entry.resourceId,
              sectionId: id,
              timestamp: DateTime(2026),
              characterCount: result.characterCount,
            )
          : SectionValidationFailedEvent(
              resourceId: entry.resourceId,
              sectionId: id,
              timestamp: DateTime(2026),
              issues: result.issues,
              errorMessage: '校验未通过',
            ),
    );
    return result;
  }

  @override
  Future<SectionGenerationOutcome> regenerateSection({
    required SectionId id,
    required String expectedUpdatedAt,
    AiRewriteMode mode = AiRewriteMode.regenerate,
    String instruction = '',
  }) async {
    _throwIfNeeded();
    regenerateCalls.add('${id.value}:${mode.storageValue}');
    final entry = entries.firstWhere((item) => item.id == id);
    if (expectedUpdatedAt != entry.updatedAtToken) {
      throw SectionControlException(
        'Section ${id.value} 已被并发修改'
        '（期望 updated_at=$expectedUpdatedAt，当前 ${entry.updatedAtToken}），'
        '重新生成被拒绝',
      );
    }
    final reportedSectionId = mismatchOutcomeSectionId ?? id;
    return SectionGenerationOutcome(
      sectionId: reportedSectionId,
      generationId: 'secgen_fake',
      partCount: entry.partCount,
      completedPartCount: entry.partCount,
      characterCount: entry.content.length,
      success: true,
    );
  }

  void _throwIfNeeded() {
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
  }

  String _nextToken() =>
      '2026-09-17T00:00:00.${(++_tokenSeed).toString().padLeft(6, '0')}';

  void _emit(SectionControlEvent event) {
    if (!_disposed) _events.add(event);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_events.close());
  }
}
