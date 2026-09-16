import 'dart:convert';
import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_generation_protocol.dart';
import '../../services/repositories/resource_tree_row_mapper.dart';
import 'resource_blueprint_repository.dart';

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

  /// Starts a new generation attempt for [taskId], marking task status as `generating`.
  Future<String> startAttempt({
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
  /// Throws [StateError] if attemptId is stale or task was cancelled.
  Future<void> commitPartContent({
    required PartGenerationResponse response,
    required String taskId,
    required String attemptId,
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

  /// Transitions a failed or pending task to ready status, allowing retry dispatch.
  Future<void> markTaskReady(String taskId);
}

/// SQLite implementation of [IPartGenerationTaskRepository].
class PartGenerationTaskRepositoryImpl
    implements IPartGenerationTaskRepository {
  PartGenerationTaskRepositoryImpl({
    required Future<Database> Function() getDb,
  }) : _getDb = getDb;

  static const String tasksTable = 'resource_generation_tasks';
  static const String attemptsTable = 'resource_generation_attempts';
  static const String partsTable = 'resource_parts';
  static const String sectionsTable = 'resource_sections';
  static const String resourcesTable = 'resources';

  final Future<Database> Function() _getDb;

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
    final allTasks = await findTasksForResource(resourceId);
    final completedPartIds = allTasks
        .where((t) => t.status == PartTaskStatus.completed.storageValue)
        .map((t) => t.partId)
        .toSet();

    final readyTasks = <ResourceGenerationTask>[];
    final db = await _getDb();
    final now = _now();

    for (final task in allTasks) {
      if (task.status != PartTaskStatus.pending.storageValue &&
          task.status != PartTaskStatus.ready.storageValue) {
        continue;
      }

      // Check if all dependencies are completed
      final allDepsMet = task.dependencies.every(completedPartIds.contains);
      if (allDepsMet) {
        if (task.status == PartTaskStatus.pending.storageValue) {
          await db.update(
            tasksTable,
            {
              'status': PartTaskStatus.ready.storageValue,
              'updated_at': now,
            },
            where: 'task_id = ?',
            whereArgs: [task.taskId],
          );
        }
        readyTasks.add(task);
      }
    }

    return readyTasks;
  }

  @override
  Future<String> startAttempt({
    required String taskId,
    required String generationId,
    required int attemptNumber,
  }) async {
    final db = await _getDb();
    final now = _now();
    final attemptId =
        'att_${taskId}_${attemptNumber}_${DateTime.now().microsecondsSinceEpoch}';

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
      if (currentStatus == PartTaskStatus.completed) {
        throw StateError('任务已完成，禁止重新发起生成：$taskId');
      }
      if (currentStatus == PartTaskStatus.generating) {
        throw StateError(
          '任务正在执行中 (generating)，存在未释放的独占 lease，禁止并发发起新的 Attempt：$taskId',
        );
      }

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

    return attemptId;
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

      // 1. Update the Part content in resource_parts
      final contentHash =
          ResourceTreeRowMapper.contentHashFor(response.content);
      final updatedPartRows = await txn.update(
        partsTable,
        {
          'content': response.content,
          'content_hash': contentHash,
          'updated_at': now,
        },
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [response.partId.value],
      );

      if (updatedPartRows == 0) {
        throw StateError(
          '提交失败：在 resource_parts 中未找到对应的部件节点 ${response.partId.value}',
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

      // 3. Mark the task as completed
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

      // 4. Mark the attempt as completed
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
    });
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
        if (currentAttempt == attemptId) {
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

      if (interruptedRows.isEmpty) return;

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
        final depsJson = row['dependencies_json'] as String? ?? '[]';
        final dynamic decoded = jsonDecode(depsJson);
        final deps = <String>[];
        if (decoded is List) {
          for (final d in decoded) {
            if (d is String) deps.add(d);
          }
        }

        final allDepsMet = deps.every(completedPartIds.contains);
        final targetStatus = allDepsMet
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
              'error_message': 'System restart or crash recovery',
              'updated_at': now,
            },
            where: 'attempt_id = ? AND status = ?',
            whereArgs: [currentAttempt, 'started'],
          );
        }

        recoveredCount++;
      }
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
    await db.update(
      tasksTable,
      {
        'status': PartTaskStatus.ready.storageValue,
        'updated_at': now,
      },
      where: 'task_id = ?',
      whereArgs: [taskId],
    );
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
