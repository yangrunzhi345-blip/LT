import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_revision.dart';
import '../../domain/resources/section_control.dart';
import '../../services/repositories/resource_tree_repository.dart';
import '../../services/repositories/section_validation_boundary.dart';
import 'resource_autosave_repository.dart';
import 'resource_revision_service.dart';

/// One manual Part body change.
final class PartContentCommitRequest {
  const PartContentCommitRequest({
    required this.partId,
    required this.expectedUpdatedAt,
    required this.content,
    this.title,
    this.cause = RevisionCause.manualSave,
    this.checkpointId = '',
    this.reason = '',
  });

  final PartId partId;

  /// Optimistic-locking token; a stale value is rejected instead of overwriting
  /// a newer write.
  final String expectedUpdatedAt;

  final String content;
  final String? title;
  final RevisionCause cause;

  /// Autosave journal row consumed by this commit, or empty when the write did
  /// not come from the editor's debounce buffer.
  final String checkpointId;

  /// Human reason recorded when the section verdict is downgraded.
  final String reason;
}

/// What one Part commit changed in addition to the body.
final class PartContentCommitResult {
  const PartContentCommitResult({
    required this.resourceId,
    required this.sectionId,
    required this.validationDowngraded,
    required this.taskReopened,
    required this.contentCharacters,
  });

  final ResourceId resourceId;
  final SectionId sectionId;

  /// True when a recorded verdict stopped being valid for the new content.
  final bool validationDowngraded;

  /// True when a `completed` generation task was reopened, which is what makes
  /// the Part regenerable again after a manual rewrite.
  final bool taskReopened;

  final int contentCharacters;
}

/// The single writer of manual Part body changes.
///
/// Everything that must agree with the new body happens in one transaction:
/// - the pre-write revision snapshot (the previous text stays recoverable),
/// - the guarded Part update,
/// - the owning section's verdict downgrade,
/// - the controlled reset of a `completed` generation task,
/// - the post-write revision head,
/// - the removal of the autosave draft that this write just made obsolete.
///
/// Splitting any of these into its own transaction would leave a window where
/// the stored body, the verdict or the revision head disagree.
final class PartContentCommitService {
  PartContentCommitService({
    required IResourceTreeRevisionBoundary treeBoundary,
    required ISectionValidationBoundary validationBoundary,
    required RevisionCaptureEngine captureEngine,
    required IResourceAutosaveRepository autosaveRepository,
    required Future<Database> Function() getDb,
    IGenerationTaskResetPort? taskReset,
  })  : _tree = treeBoundary,
        _validation = validationBoundary,
        _capture = captureEngine,
        _autosave = autosaveRepository,
        _getDb = getDb,
        _taskReset = taskReset;

  final IResourceTreeRevisionBoundary _tree;
  final ISectionValidationBoundary _validation;
  final RevisionCaptureEngine _capture;
  final IResourceAutosaveRepository _autosave;
  final Future<Database> Function() _getDb;
  final IGenerationTaskResetPort? _taskReset;

  Future<PartContentCommitResult> applyContent(
    PartContentCommitRequest request,
  ) async {
    final db = await _getDb();
    final now = _now();
    return db.transaction((txn) async {
      // The Part → Section → Resource mapping is read from the stored rows, so
      // a caller cannot attach the write to the wrong section.
      final placement = await _tree.readNodePlacement(txn, request.partId);
      if (placement == null || !placement.isLive) {
        throw ResourceTreeNotFoundException(
          'Part ${request.partId.value} 不存在或已删除，编辑未保存',
        );
      }
      if (placement.resourceId.isEmpty || placement.parentNodeId.isEmpty) {
        throw ResourceTreeException(
          'Part ${request.partId.value} 缺少归属信息，编辑未保存',
        );
      }
      final resourceId = ResourceId(placement.resourceId);
      final sectionId = SectionId(placement.parentNodeId);

      await _capture.captureBeforeWrite(
        txn,
        resourceId: resourceId,
        cause: request.cause,
        now: now,
      );

      // The verdict is downgraded BEFORE the body write: the body write bumps
      // the section token, and the verdict update is guarded by the token read
      // here. Doing it the other way round would fail the guard on every edit.
      var downgraded = false;
      final row = await _validation.findSectionControlRowInTransaction(
        txn,
        sectionId,
      );
      if (row != null) {
        final next = SectionValidationState.afterContentChange(
          row.validationState,
        );
        if (next != row.validationState) {
          await _validation.updateSectionValidationInTransaction(
            txn,
            id: sectionId,
            expectedUpdatedAt: row.updatedAt,
            state: next,
            message: '',
          );
          downgraded = true;
        }
      }

      await _tree.updatePartInTransaction(
        txn,
        id: request.partId,
        expectedUpdatedAt: request.expectedUpdatedAt,
        title: request.title,
        content: request.content,
        now: now,
      );

      var reopened = false;
      final reset = _taskReset;
      if (reset != null) {
        final ids = await reset.reopenCompletedTasksInTransaction(
          txn,
          partIds: <String>[request.partId.value],
          now: now,
        );
        reopened = ids.isNotEmpty;
      }

      await _capture.captureAfterWrite(
        txn,
        resourceId: resourceId,
        cause: request.cause,
        now: now,
        label: request.cause.displayLabel,
      );

      if (request.checkpointId.isNotEmpty) {
        await _autosave.deleteDraftInTransaction(txn, request.checkpointId);
      }

      return PartContentCommitResult(
        resourceId: resourceId,
        sectionId: sectionId,
        validationDowngraded: downgraded,
        taskReopened: reopened,
        contentCharacters: request.content.length,
      );
    });
  }

  static String _now() => DateTime.now().toIso8601String();
}
