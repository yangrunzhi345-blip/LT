import 'dart:convert';
import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_generation_protocol.dart';
import '../../domain/resources/resource_revision.dart';
import '../../domain/resources/section_control.dart';
import '../../services/repositories/resource_tree_repository.dart'
    show ResourceTreeConflictException;
import '../../services/repositories/resource_tree_row_mapper.dart';
import 'resource_blueprint_repository.dart';
import 'resource_revision_service.dart';

/// Ownership handle for one Part generation attempt.
///
/// [sourceToken] is the target Part's `updated_at` captured at the exact moment
/// the attempt acquired its lease — i.e. at the generation ownership point,
/// before any model work starts. It is the observed source version the commit
/// must CAS against, so a Part the user edits mid-generation can never be
/// overwritten by the stale response.
final class PartGenerationAttempt {
  const PartGenerationAttempt({
    required this.attemptId,
    required this.sourceToken,
  });

  final String attemptId;

  /// `resource_parts.updated_at` observed when this attempt started; empty when
  /// the Part row did not exist at that moment (the commit then refuses).
  final String sourceToken;

  @override
  String toString() => 'PartGenerationAttempt($attemptId, source=$sourceToken)';
}

/// Contract for managing Part generation tasks and execution attempts.
abstract interface class IPartGenerationTaskRepository {
  Future<List<ResourceGenerationTask>> findTasksForResource(String resourceId);

  Future<List<ResourceGenerationTask>> findTasksForBlueprint(
      String blueprintId);

  Future<ResourceGenerationTask?> findTask(String taskId);

  Future<ResourceGenerationTask?> findTaskByPartId(String partId);

  /// Computes DAG readiness and returns all tasks for [resourceId] that are
  /// ready to be generated (dependencies are all completed).
  Future<List<ResourceGenerationTask>> findReadyTasks(String resourceId);

  /// Starts a new generation attempt for [taskId], marking task status as
  /// `generating`, and captures the Part's source token atomically with the
  /// lease acquisition.
  Future<PartGenerationAttempt> startAttempt({
    required String taskId,
    required String generationId,
    required int attemptNumber,
  });

  /// Transitions task status from `generating` to `validating`.
  Future<void> recordValidating({
    required String taskId,
    required String attemptId,
  });

  /// Atomically commits generated Part content and marks task & attempt completed.
  ///
  /// [expectedSourceToken] is the token captured by [startAttempt]. The content
  /// write is guarded by `id = ? AND updated_at = ?`, so a Part the user changed
  /// after generation started is never overwritten: the whole transaction rolls
  /// back and a [ResourceTreeConflictException] is thrown instead. Throws
  /// [StateError] if the attemptId is stale, cancelled or the target is missing.
  ///
  /// When the injected revision boundary is present, the commit also records the
  /// pre-write state and the post-write head in this same transaction, so a
  /// generation can always be rolled back and a crash can never leave the
  /// revision head describing content that was never written.
  Future<void> commitPartContent({
    required PartGenerationResponse response,
    required String taskId,
    required String attemptId,
    required String expectedSourceToken,
  });

  /// Marks the attempt and task as `failed`.
  Future<void> recordFailedAttempt({
    required String taskId,
    required String attemptId,
    required String errorMessage,
  });

  /// Cancels in-flight tasks for [resourceId].
  Future<void> cancelTasks({
    required String resourceId,
    String? specificTaskId,
  });

  /// Resets interrupted tasks ('generating', 'validating') back to 'ready' or 'pending'.
  Future<int> recoverInterruptedTasks(String resourceId);

  /// Checks if all tasks for [resourceId] have reached `completed`.
  Future<bool> areAllTasksCompleted(String resourceId);

  /// Retrieves content for a set of Part IDs from `resource_parts`.
  Future<Map<String, ({String title, String content})>> getPartsContent(
    List<String> partIds,
  );

  /// Transitions a dependency-satisfied retryable task to ready.
  Future<void> markTaskReady(String taskId);
}

/// SQLite implementation of [IPartGenerationTaskRepository].
class PartGenerationTaskRepositoryImpl
    implements IPartGenerationTaskRepository, IGenerationTaskResetPort {
  PartGenerationTaskRepositoryImpl({
    required Future<Database> Function() getDb,
    IPartCommitRevisionBoundary? revisionBoundary,
  })  : _getDb = getDb,
        _revisionBoundary = revisionBoundary;

  static const String tasksTable = 'resource_generation_tasks';
  static const String attemptsTable = 'resource_generation_attempts';
  static const String partsTable = 'resource_parts';
  static const String sectionsTable = 'resource_sections';
  static const String resourcesTable = 'resources';

  final Future<Database> Function() _getDb;

  /// Phase 9 revision hooks. Optional so the Phase 5/6/7 unit tests that build
  /// this repository in isolation keep working unchanged; the production
  /// composition root always injects it.
  final IPartCommitRevisionBoundary? _revisionBoundary;

  String _now() => DateTime.now().toIso8601String();

  @override
  Future<List<ResourceGenerationTask>> findTasksForResource(
    String resourceId,
  ) async {
    final db = await _getDb();
    final rows = await db.query(
      tasksTable,
      where: 'resource_id = ?',
      whereArgs: [resourceId],
      orderBy: 'sort_order ASC, task_id ASC',
    );
    return rows.map(_mapRowToTask).toList();
  }

  @override
  Future<List<ResourceGenerationTask>> findTasksForBlueprint(
    String blueprintId,
  ) async {
    final db = await _getDb();
    final rows = await db.query(
      tasksTable,
      where: 'blueprint_id = ?',
      whereArgs: [blueprintId],
      orderBy: 'sort_order ASC, task_id ASC',
    );
    return rows.map(_mapRowToTask).toList();
  }

  @override
  Future<ResourceGenerationTask?> findTask(String taskId) async {
    final db = await _getDb();
    final rows = await db.query(
      tasksTable,
      where: 'task_id = ?',
      whereArgs: [taskId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _mapRowToTask(rows.first);
  }

  @override
  Future<ResourceGenerationTask?> findTaskByPartId(String partId) async {
    final db = await _getDb();
    final rows = await db.query(
      tasksTable,
      where: 'part_id = ?',
      whereArgs: [partId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _mapRowToTask(rows.first);
  }

  @override
  Future<List<ResourceGenerationTask>> findReadyTasks(String resourceId) async {
    final db = await _getDb();
    return db.transaction((txn) => _recomputeReadyTasksInTransaction(
          txn,
          resourceId: resourceId,
          now: _now(),
        ));
  }

  @override
  Future<PartGenerationAttempt> startAttempt({
    required String taskId,
    required String generationId,
    required int attemptNumber,
  }) async {
    final db = await _getDb();
    final now = _now();
    final attemptId =
        'att_${taskId}_${attemptNumber}_${DateTime.now().microsecondsSinceEpoch}';
    var sourceToken = '';

    await db.transaction((txn) async {
      final taskRows = await txn.query(
        tasksTable,
        where: 'task_id = ?',
        whereArgs: [taskId],
        limit: 1,
      );
      if (taskRows.isEmpty) {
        throw StateError('任务不存在：$taskId');
      }

      final task = _mapRowToTask(taskRows.first);
      final currentStatus = PartTaskStatus.fromStorage(task.status);
      if (currentStatus != PartTaskStatus.ready) {
        throw StateError(
          '任务尚未处于 ready 状态，禁止发起 Attempt：$taskId '
          '（当前状态: ${currentStatus.storageValue}）',
        );
      }
      final completedRows = await txn.query(
        tasksTable,
        columns: const ['part_id'],
        where: 'resource_id = ? AND status = ?',
        whereArgs: [task.resourceId, PartTaskStatus.completed.storageValue],
      );
      final completedPartIds =
          completedRows.map((row) => row['part_id'].toString()).toSet();
      final unmetDependencies = task.dependencies
          .where((id) => !completedPartIds.contains(id))
          .toList();
      if (unmetDependencies.isNotEmpty) {
        throw StateError(
          '任务依赖尚未满足，禁止发起 Attempt：taskId=$taskId '
          'partId=${task.partId} unmetDependencies=$unmetDependencies',
        );
      }

      // R02-B: capture the Part's source token in the same transaction that
      // grants this attempt its lease. Reading it before any model work starts
      // is what makes the later commit an honest compare-and-swap instead of a
      // blind overwrite of whatever the user typed in the meantime.
      final partRows = await txn.query(
        partsTable,
        columns: const ['updated_at'],
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [task.partId],
        limit: 1,
      );
      sourceToken = partRows.isEmpty
          ? ''
          : partRows.first['updated_at']?.toString() ?? '';

      await txn.insert(
        attemptsTable,
        {
          'attempt_id': attemptId,
          'task_id': taskId,
          'generation_id': generationId,
          'part_id': task.partId,
          'attempt_number': attemptNumber,
          'status': 'started',
          'content_length': 0,
          'error_message': '',
          'created_at': now,
          'updated_at': now,
        },
      );

      await txn.update(
        tasksTable,
        {
          'status': PartTaskStatus.generating.storageValue,
          'current_attempt_id': attemptId,
          'error_message': '',
          'updated_at': now,
        },
        where: 'task_id = ?',
        whereArgs: [taskId],
      );
    });

    return PartGenerationAttempt(
      attemptId: attemptId,
      sourceToken: sourceToken,
    );
  }

  @override
  Future<void> recordValidating({
    required String taskId,
    required String attemptId,
  }) async {
    final db = await _getDb();
    final now = _now();

    await db.transaction((txn) async {
      final rows = await txn.query(
        tasksTable,
        where: 'task_id = ?',
        whereArgs: [taskId],
        limit: 1,
      );
      if (rows.isEmpty) return;

      final currentAttempt = rows.first['current_attempt_id'] as String? ?? '';
      final currentStatus = rows.first['status'] as String? ?? '';

      // Only advance if attempt is current and status is generating
      if (currentAttempt == attemptId &&
          currentStatus == PartTaskStatus.generating.storageValue) {
        await txn.update(
          tasksTable,
          {
            'status': PartTaskStatus.validating.storageValue,
            'updated_at': now,
          },
          where: 'task_id = ?',
          whereArgs: [taskId],
        );
      }
    });
  }

  @override
  Future<void> commitPartContent({
    required PartGenerationResponse response,
    required String taskId,
    required String attemptId,
    required String expectedSourceToken,
  }) async {
    final db = await _getDb();
    final now = _now();

    await db.transaction((txn) async {
      final taskRows = await txn.query(
        tasksTable,
        where: 'task_id = ?',
        whereArgs: [taskId],
        limit: 1,
      );
      if (taskRows.isEmpty) {
        throw StateError('提交失败：未找到生成任务 $taskId');
      }

      final taskRow = taskRows.first;
      final currentAttempt = taskRow['current_attempt_id'] as String? ?? '';
      final currentStatus = taskRow['status'] as String? ?? '';
      final taskResourceId = taskRow['resource_id'] as String? ?? '';
      final taskPartId = taskRow['part_id'] as String? ?? '';

      // ID binding check: task row must match response IDs
      if (taskResourceId != response.resourceId.value) {
        throw StateError(
          '提交被拒绝：资源 ID 不匹配 (任务: $taskResourceId, 响应: ${response.resourceId.value})',
        );
      }
      if (taskPartId != response.partId.value) {
        throw StateError(
          '提交被拒绝：部件 ID 不匹配 (任务: $taskPartId, 响应: ${response.partId.value})',
        );
      }

      // Race detection: Ensure the attempt is still active and not superseded or cancelled
      if (currentAttempt != attemptId) {
        throw StateError(
          '提交被拒绝：尝试令牌不匹配 (当前: $currentAttempt, 提交: $attemptId)，可能已被重试取代',
        );
      }

      if (currentStatus == PartTaskStatus.cancelled.storageValue) {
        throw StateError('提交被拒绝：任务已被取消，晚到的生成响应不得提交');
      }

      // R02-B: the source-content CAS. The attempt/lease/status guards above only
      // prove "this is the current attempt"; they say nothing about whether the
      // user edited the Part after generation started. Comparing the live token
      // to the one captured at `startAttempt` is what stops a stale generation
      // from overwriting that manual edit. It is checked BEFORE the revision
      // snapshot so a rejected commit leaves no trace.
      final existingPartRows = await txn.query(
        partsTable,
        columns: const ['content', 'updated_at'],
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [response.partId.value],
        limit: 1,
      );
      if (existingPartRows.isEmpty) {
        throw StateError(
          '提交失败：在 resource_parts 中未找到对应的部件节点 ${response.partId.value}',
        );
      }
      final liveSourceToken =
          existingPartRows.first['updated_at']?.toString() ?? '';
      if (liveSourceToken != expectedSourceToken) {
        throw ResourceTreeConflictException(
          '提交被拒绝：部件 ${response.partId.value} 在生成开始后被修改'
          '（期望 updated_at=$expectedSourceToken，当前=$liveSourceToken），'
          '陈旧生成不得覆盖用户内容',
        );
      }
      final hadConfirmedContent =
          (existingPartRows.first['content']?.toString() ?? '').isNotEmpty;
      // A commit that replaces confirmed text is a regeneration; one that fills
      // an empty Part is a first generation. Deriving it from the stored row
      // keeps the revision cause honest without trusting the caller.
      final cause = hadConfirmedContent
          ? RevisionCause.regeneration
          : RevisionCause.generation;

      await _revisionBoundary?.captureBeforeWrite(
        txn,
        resourceId: response.resourceId,
        cause: cause,
        now: now,
      );

      // 1. Update the Part content in resource_parts. The `updated_at` predicate
      // repeats the CAS above as a defence in depth: the write is only allowed
      // to land on the exact source version it observed.
      final contentHash =
          ResourceTreeRowMapper.contentHashFor(response.content);
      final updatedPartRows = await txn.update(
        partsTable,
        {
          'content': response.content,
          'content_hash': contentHash,
          'updated_at': now,
        },
        where: 'id = ? AND deleted_at IS NULL AND updated_at = ?',
        whereArgs: [response.partId.value, expectedSourceToken],
      );

      if (updatedPartRows == 0) {
        throw ResourceTreeConflictException(
          '提交被拒绝：部件 ${response.partId.value} 的 updated_at 在提交过程中变化，'
          '陈旧生成不得覆盖用户内容',
        );
      }

      // 2. Bump the owning resource updated_at
      final updatedResRows = await txn.update(
        resourcesTable,
        {'updated_at': now},
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [response.resourceId.value],
      );
      if (updatedResRows == 0) {
        throw StateError(
          '提交失败：在 resources 中未找到资源 ${response.resourceId.value}',
        );
      }

      // 3. Sync the owning section, in this same transaction.
      //
      // Committing Part body text changes section content, so the section's
      // optimistic token must move and any verdict recorded for the previous
      // content must stop being `valid` (the single domain rule decides the
      // resulting state). The section id is read from the Part row itself —
      // the authoritative Part → Section mapping — never from a section row.
      await _syncOwningSection(
        txn,
        partId: response.partId.value,
        now: now,
      );

      // 4. Mark the task as completed
      final updatedTaskRows = await txn.update(
        tasksTable,
        {
          'status': PartTaskStatus.completed.storageValue,
          'error_message': '',
          'updated_at': now,
        },
        where: 'task_id = ?',
        whereArgs: [taskId],
      );
      if (updatedTaskRows == 0) {
        throw StateError('提交失败：未能更新任务状态 $taskId');
      }

      // 5. Mark the attempt as completed
      final updatedAttemptRows = await txn.update(
        attemptsTable,
        {
          'status': 'completed',
          'content_length': response.content.length,
          'error_message': '',
          'updated_at': now,
        },
        where: 'attempt_id = ?',
        whereArgs: [attemptId],
      );
      if (updatedAttemptRows == 0) {
        throw StateError('提交失败：未能更新尝试记录 $attemptId');
      }

      // 6. Record the resulting head inside the same transaction.
      //
      // Placed last on purpose: the revision must describe the fully committed
      // state, and because it shares this transaction a failure anywhere above
      // rolls the head back with the content.
      await _revisionBoundary?.captureAfterWrite(
        txn,
        resourceId: response.resourceId,
        cause: cause,
        now: now,
        label: cause.displayLabel,
      );
    });
  }

  @override
  Future<List<String>> reopenCompletedTasksInTransaction(
    DatabaseExecutor txn, {
    required Iterable<String> partIds,
    required String now,
  }) async {
    final ids = partIds.toSet().toList();
    if (ids.isEmpty) return const <String>[];

    final reopened = <String>[];
    for (final partId in ids) {
      // Guarded by `status = 'completed'`: a task that is currently generating
      // or failed is never hijacked by a content overwrite, and the second call
      // for the same Part is a no-op.
      final updated = await txn.update(
        tasksTable,
        {
          'status': PartTaskStatus.ready.storageValue,
          'error_message': '',
          'updated_at': now,
        },
        where: 'part_id = ? AND status = ?',
        whereArgs: <Object?>[partId, PartTaskStatus.completed.storageValue],
      );
      if (updated > 0) reopened.add(partId);
    }
    return reopened;
  }

  /// Keeps one section's version and verdict consistent with committed content.
  ///
  /// Must run inside the caller's transaction: a committed Part whose section
  /// was not refreshed would leave a stale token and a `valid` verdict standing
  /// for content that no longer exists — and committing the Part without them
  /// (or the reverse) would be exactly the split the Phase 7 invariant forbids.
  ///
  /// The Part → Section mapping is read from `resource_parts.section_id`, which
  /// is authoritative; a section row is never used to discover its own id.
  Future<void> _syncOwningSection(
    DatabaseExecutor txn, {
    required String partId,
    required String now,
  }) async {
    final partRows = await txn.query(
      partsTable,
      columns: ['section_id'],
      where: 'id = ?',
      whereArgs: [partId],
      limit: 1,
    );
    if (partRows.isEmpty) {
      throw StateError('提交失败：未找到部件 $partId 所属的 Section');
    }
    final sectionId = partRows.first['section_id']?.toString();
    if (sectionId == null || sectionId.isEmpty) {
      throw StateError('提交失败：部件 $partId 缺少 section_id，无法同步 Section 版本');
    }

    final sectionRows = await txn.query(
      sectionsTable,
      columns: ['validation_state'],
      where: 'id = ?',
      whereArgs: [sectionId],
      limit: 1,
    );
    if (sectionRows.isEmpty) {
      throw StateError('提交失败：未找到 Section $sectionId，无法同步 Section 版本');
    }

    final currentVerdict = SectionValidationState.fromStorage(
      sectionRows.first['validation_state']?.toString(),
    );
    final nextVerdict =
        SectionValidationState.afterContentChange(currentVerdict);

    // The version always moves (content changed). The verdict and its message
    // are only rewritten when a recorded verdict was actually downgraded, so an
    // untouched row keeps whatever it legitimately held.
    final values = <String, Object?>{'updated_at': now};
    if (nextVerdict != currentVerdict) {
      values['validation_state'] = nextVerdict.storageValue;
      values['validation_message'] = '';
    }

    await txn.update(
      sectionsTable,
      values,
      where: 'id = ?',
      whereArgs: [sectionId],
    );
  }

  @override
  Future<void> recordFailedAttempt({
    required String taskId,
    required String attemptId,
    required String errorMessage,
  }) async {
    final db = await _getDb();
    final now = _now();

    await db.transaction((txn) async {
      await txn.update(
        attemptsTable,
        {
          'status': 'failed',
          'error_message': errorMessage,
          'updated_at': now,
        },
        where: 'attempt_id = ?',
        whereArgs: [attemptId],
      );

      final taskRows = await txn.query(
        tasksTable,
        where: 'task_id = ?',
        whereArgs: [taskId],
        limit: 1,
      );
      if (taskRows.isNotEmpty) {
        final currentAttempt =
            taskRows.first['current_attempt_id'] as String? ?? '';
        final currentStatus = taskRows.first['status'] as String? ?? '';
        if (currentAttempt == attemptId &&
            currentStatus != PartTaskStatus.cancelled.storageValue) {
          await txn.update(
            tasksTable,
            {
              'status': PartTaskStatus.failed.storageValue,
              'error_message': errorMessage,
              'updated_at': now,
            },
            where: 'task_id = ?',
            whereArgs: [taskId],
          );
        }
      }
    });
  }

  @override
  Future<void> cancelTasks({
    required String resourceId,
    String? specificTaskId,
  }) async {
    final db = await _getDb();
    final now = _now();

    await db.transaction((txn) async {
      final whereClause = specificTaskId != null
          ? 'task_id = ? AND status NOT IN (?, ?)'
          : 'resource_id = ? AND status NOT IN (?, ?)';
      final whereArgs = specificTaskId != null
          ? [
              specificTaskId,
              PartTaskStatus.completed.storageValue,
              PartTaskStatus.cancelled.storageValue,
            ]
          : [
              resourceId,
              PartTaskStatus.completed.storageValue,
              PartTaskStatus.cancelled.storageValue,
            ];

      await txn.update(
        tasksTable,
        {
          'status': PartTaskStatus.cancelled.storageValue,
          'updated_at': now,
        },
        where: whereClause,
        whereArgs: whereArgs,
      );
    });
  }

  @override
  Future<int> recoverInterruptedTasks(String resourceId) async {
    final db = await _getDb();
    final now = _now();
    var recoveredCount = 0;

    await db.transaction((txn) async {
      final interruptedRows = await txn.query(
        tasksTable,
        where: 'resource_id = ? AND status IN (?, ?)',
        whereArgs: [
          resourceId,
          PartTaskStatus.generating.storageValue,
          PartTaskStatus.validating.storageValue,
        ],
      );

      // Find all completed parts to determine whether reset to ready or pending
      final completedRows = await txn.query(
        tasksTable,
        where: 'resource_id = ? AND status = ?',
        whereArgs: [resourceId, PartTaskStatus.completed.storageValue],
      );
      final completedPartIds =
          completedRows.map((r) => r['part_id'] as String).toSet();

      for (final row in interruptedRows) {
        final taskId = row['task_id'] as String;
        final currentAttempt = row['current_attempt_id'] as String? ?? '';
        var isDirectedRetry = false;
        if (currentAttempt.isNotEmpty) {
          final attemptRows = await txn.query(
            attemptsTable,
            columns: const ['generation_id'],
            where: 'attempt_id = ?',
            whereArgs: [currentAttempt],
            limit: 1,
          );
          isDirectedRetry = attemptRows.isNotEmpty &&
              (attemptRows.first['generation_id'] as String? ?? '')
                  .startsWith('directed_retry_');
        }
        final depsJson = row['dependencies_json'] as String? ?? '[]';
        final dynamic decoded = jsonDecode(depsJson);
        final deps = <String>[];
        if (decoded is List) {
          for (final d in decoded) {
            if (d is String) deps.add(d);
          }
        }

        final allDepsMet = deps.every(completedPartIds.contains);
        // A directed rewrite's user instruction is intentionally scoped to one
        // attempt and is not persisted as reusable task state. Replaying it as
        // a normal generation after restart would change semantics and could
        // overwrite the old Part with unrelated prose. Keep it cancelled until
        // the user explicitly issues the rewrite again; beginLossyOperation
        // will then reopen it with a fresh optimistic source token.
        final targetStatus = isDirectedRetry
            ? PartTaskStatus.cancelled.storageValue
            : allDepsMet
                ? PartTaskStatus.ready.storageValue
                : PartTaskStatus.pending.storageValue;

        await txn.update(
          tasksTable,
          {
            'status': targetStatus,
            'updated_at': now,
          },
          where: 'task_id = ?',
          whereArgs: [taskId],
        );

        if (currentAttempt.isNotEmpty) {
          await txn.update(
            attemptsTable,
            {
              'status': 'interrupted',
              'error_message': isDirectedRetry
                  ? 'Directed retry interrupted; explicit retry required'
                  : 'System restart or crash recovery',
              'updated_at': now,
            },
            where: 'attempt_id = ? AND status = ?',
            whereArgs: [currentAttempt, 'started'],
          );
        }

        recoveredCount++;
      }

      // Recovery must also re-evaluate pending rows that became unblocked
      // before the process died. Otherwise a valid confirmed DAG can be left
      // with no dispatchable work despite all of a child's dependencies being
      // completed.
      await _recomputeReadyTasksInTransaction(
        txn,
        resourceId: resourceId,
        now: now,
      );
    });

    return recoveredCount;
  }

  @override
  Future<bool> areAllTasksCompleted(String resourceId) async {
    final tasks = await findTasksForResource(resourceId);
    if (tasks.isEmpty) return false;
    return tasks
        .every((t) => t.status == PartTaskStatus.completed.storageValue);
  }

  @override
  Future<Map<String, ({String title, String content})>> getPartsContent(
    List<String> partIds,
  ) async {
    if (partIds.isEmpty) return const {};
    final db = await _getDb();
    final placeholders = List.filled(partIds.length, '?').join(',');
    final rows = await db.query(
      partsTable,
      columns: ['id', 'title', 'content'],
      where: 'id IN ($placeholders) AND deleted_at IS NULL',
      whereArgs: partIds,
    );

    final result = <String, ({String title, String content})>{};
    for (final row in rows) {
      final id = row['id'] as String;
      final title = row['title'] as String? ?? '';
      final content = row['content'] as String? ?? '';
      result[id] = (title: title, content: content);
    }
    return result;
  }

  @override
  Future<void> markTaskReady(String taskId) async {
    final db = await _getDb();
    final now = _now();
    await db.transaction((txn) async {
      final rows = await txn.query(
        tasksTable,
        where: 'task_id = ?',
        whereArgs: [taskId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('任务不存在：$taskId');
      final task = _mapRowToTask(rows.first);
      final status = PartTaskStatus.fromStorage(task.status);
      if (status != PartTaskStatus.failed &&
          status != PartTaskStatus.pending &&
          status != PartTaskStatus.cancelled &&
          status != PartTaskStatus.ready) {
        throw StateError(
          '任务当前状态不允许转为 ready：taskId=$taskId status=${status.storageValue}',
        );
      }
      final completedRows = await txn.query(
        tasksTable,
        columns: const ['part_id'],
        where: 'resource_id = ? AND status = ?',
        whereArgs: [task.resourceId, PartTaskStatus.completed.storageValue],
      );
      final completedPartIds =
          completedRows.map((row) => row['part_id'].toString()).toSet();
      final unmetDependencies = task.dependencies
          .where((id) => !completedPartIds.contains(id))
          .toList();
      if (unmetDependencies.isNotEmpty) {
        throw StateError(
          '任务依赖尚未满足，不能标记 ready：taskId=$taskId '
          'partId=${task.partId} unmetDependencies=$unmetDependencies',
        );
      }
      await txn.update(
        tasksTable,
        {
          'status': PartTaskStatus.ready.storageValue,
          'updated_at': now,
        },
        where: 'task_id = ?',
        whereArgs: [taskId],
      );
    });
  }

  /// Recomputes dispatchable work from the persisted completed task set.
  ///
  /// The task rows are the generation state source of truth; Part content is
  /// committed in the same transaction as `completed`, so readiness must not
  /// infer completion from potentially user-edited prose.
  Future<List<ResourceGenerationTask>> _recomputeReadyTasksInTransaction(
    DatabaseExecutor txn, {
    required String resourceId,
    required String now,
  }) async {
    final rows = await txn.query(
      tasksTable,
      where: 'resource_id = ?',
      whereArgs: [resourceId],
      orderBy: 'sort_order ASC, task_id ASC',
    );
    final tasks = rows.map(_mapRowToTask).toList(growable: false);
    final completedPartIds = tasks
        .where((task) => task.status == PartTaskStatus.completed.storageValue)
        .map((task) => task.partId)
        .toSet();
    for (final task in tasks) {
      if (task.status != PartTaskStatus.pending.storageValue &&
          task.status != PartTaskStatus.ready.storageValue) {
        continue;
      }
      if (task.dependencies.any((id) => !completedPartIds.contains(id))) {
        continue;
      }
      if (task.status == PartTaskStatus.pending.storageValue) {
        await txn.update(
          tasksTable,
          {'status': PartTaskStatus.ready.storageValue, 'updated_at': now},
          where: 'task_id = ? AND status = ?',
          whereArgs: [task.taskId, PartTaskStatus.pending.storageValue],
        );
      }
    }
    final refreshedRows = await txn.query(
      tasksTable,
      where: 'resource_id = ? AND status = ?',
      whereArgs: [resourceId, PartTaskStatus.ready.storageValue],
      orderBy: 'sort_order ASC, task_id ASC',
    );
    return refreshedRows
        .map(_mapRowToTask)
        .where((task) => task.dependencies.every(completedPartIds.contains))
        .toList(growable: false);
  }

  ResourceGenerationTask _mapRowToTask(Map<String, dynamic> row) {
    final depsJson = row['dependencies_json'] as String? ?? '[]';
    final dynamic decodedDeps = jsonDecode(depsJson);
    final dependencies = <String>[];
    if (decodedDeps is List) {
      for (final d in decodedDeps) {
        if (d is String) dependencies.add(d);
      }
    }

    return ResourceGenerationTask(
      taskId: row['task_id'] as String,
      blueprintId: row['blueprint_id'] as String,
      resourceId: row['resource_id'] as String,
      sectionId: row['section_id'] as String,
      partId: row['part_id'] as String,
      promptGoal: row['prompt_goal'] as String? ?? '',
      estimatedLength: (row['estimated_length'] as num?)?.toInt() ?? 0,
      dependencies: dependencies,
      status: row['status'] as String? ?? 'pending',
      sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
      currentAttemptId: row['current_attempt_id'] as String? ?? '',
      errorMessage: row['error_message'] as String? ?? '',
      createdAt: row['created_at'] as String? ?? '',
      updatedAt: row['updated_at'] as String? ?? '',
    );
  }
}
