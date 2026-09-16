import 'dart:async';

import '../../domain/resources/resource_blueprint.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_generation_protocol.dart';
import '../../domain/resources/resource_limits.dart';
import '../../models/llm_task.dart';
import '../../services/llm_service.dart';
import '../llm/llm_gateway.dart';
import 'generation_patch_parser.dart';
import 'part_generation_parser.dart';
import 'part_generation_prompt_builder.dart';
import 'part_generation_validator.dart';
import 'resource_blueprint_repository.dart';
import 'resource_creation_pipeline.dart';
import 'resource_generation_task_repository.dart';

/// Progress snapshot of the incremental generation process.
final class PartGenerationProgress {
  const PartGenerationProgress({
    required this.resourceId,
    required this.totalTasks,
    required this.completedTasks,
    required this.inFlightTasks,
    required this.failedTasks,
    this.latestCompletedPartId,
    this.statusMessage = '',
  });

  final String resourceId;
  final int totalTasks;
  final int completedTasks;
  final int inFlightTasks;
  final int failedTasks;
  final String? latestCompletedPartId;
  final String statusMessage;

  double get fraction =>
      totalTasks == 0 ? 0.0 : (completedTasks / totalTasks).clamp(0.0, 1.0);

  bool get isDone => totalTasks > 0 && completedTasks == totalTasks;

  @override
  String toString() =>
      'PartGenerationProgress($completedTasks/$totalTasks completed, '
      '$inFlightTasks in-flight, $failedTasks failed)';
}

/// Raw LLM completion invoker for Part body generation.
typedef PartRawCompleter = Future<String> Function({
  required String systemPrompt,
  required String instruction,
  required LlmTask task,
  GenerationTaskHandle? taskHandle,
});

/// Coordinator that orchestrates the topological DAG generation of Part body text.
final class PartGenerationCoordinator {
  PartGenerationCoordinator({
    required IPartGenerationTaskRepository taskRepository,
    required IResourceBlueprintRepository blueprintRepository,
    required ResourceCreationPipeline pipeline,
    PartRawCompleter? completer,
    LlmGateway? gateway,
    this.maxConcurrency = 2,
  })  : _taskRepository = taskRepository,
        _blueprintRepository = blueprintRepository,
        _pipeline = pipeline,
        _completer = completer ?? _createGatewayCompleter(gateway);

  final IPartGenerationTaskRepository _taskRepository;
  final IResourceBlueprintRepository _blueprintRepository;
  final ResourceCreationPipeline _pipeline;
  final PartRawCompleter _completer;
  final int maxConcurrency;

  static PartRawCompleter _createGatewayCompleter(LlmGateway? gateway) {
    if (gateway == null) {
      throw ArgumentError(
        'PartGenerationCoordinator 需要提供 completer 或 LlmGateway',
      );
    }
    return ({
      required String systemPrompt,
      required String instruction,
      required LlmTask task,
      GenerationTaskHandle? taskHandle,
    }) {
      return gateway.rawCompletion(
        systemPrompt: systemPrompt,
        instruction: instruction,
        task: task,
        taskHandle: taskHandle,
      );
    };
  }

  /// Generates all parts for a confirmed blueprint across its topological DAG.
  Future<bool> generateAllParts({
    required String blueprintId,
    GenerationTaskHandle? taskHandle,
    void Function(PartGenerationProgress progress)? onProgress,
    int maxRetriesPerPart = 2,
    String? operationId,
  }) async {
    final blueprint = await _blueprintRepository.findBlueprint(blueprintId);
    if (blueprint == null) {
      throw StateError('未找到 Blueprint: $blueprintId');
    }

    if (blueprint.status != BlueprintStatus.confirmed) {
      throw StateError(
        '无法启动正文生成：Blueprint 尚未确认（当前状态: ${blueprint.status.storageValue}）',
      );
    }

    final resourceId = blueprint.resourceId?.value;
    if (resourceId == null || resourceId.isEmpty) {
      throw StateError('Blueprint 缺少已绑定的 resourceId: $blueprintId');
    }

    // Recover any interrupted tasks from previous crashes
    await _taskRepository.recoverInterruptedTasks(resourceId);

    // Retrieve the reference source from creation session if available
    final session = await _pipeline.findSession(blueprint.sessionId);
    final referenceBody = session?.referenceSource.body ?? '';

    final generationId =
        operationId ?? 'gen_${blueprint.sessionId}_${blueprint.blueprintId}';

    // Track in-flight tasks and retry counters per task
    final inFlight = <String, Future<void>>{};
    final retryCounts = <String, int>{};
    String? lastCompletedPartId;
    Object? firstTerminalError;

    Future<void> emitProgress() async {
      if (onProgress == null) return;
      final allTasks = await _taskRepository.findTasksForResource(resourceId);
      final completed = allTasks
          .where((t) => t.status == PartTaskStatus.completed.storageValue)
          .length;
      final failed = allTasks
          .where((t) => t.status == PartTaskStatus.failed.storageValue)
          .length;

      onProgress(PartGenerationProgress(
        resourceId: resourceId,
        totalTasks: allTasks.length,
        completedTasks: completed,
        inFlightTasks: inFlight.length,
        failedTasks: failed,
        latestCompletedPartId: lastCompletedPartId,
      ));
    }

    while (true) {
      if (taskHandle?.isCancelled == true) {
        await _taskRepository.cancelTasks(resourceId: resourceId);
        await emitProgress();
        return false;
      }

      final allTasks = await _taskRepository.findTasksForResource(resourceId);
      final isAllDone = allTasks.every(
        (t) => t.status == PartTaskStatus.completed.storageValue,
      );
      if (isAllDone) {
        await emitProgress();
        return true;
      }

      // Check if tasks are ready to run
      final readyTasks = await _taskRepository.findReadyTasks(resourceId);
      final unstartedReady = readyTasks.where(
        (t) => !inFlight.containsKey(t.taskId),
      );

      // Dispatch as many ready tasks as allowed by maxConcurrency
      for (final task in unstartedReady) {
        if (inFlight.length >= maxConcurrency) break;
        if (taskHandle?.isCancelled == true) break;

        final taskId = task.taskId;
        final currentRetries = retryCounts[taskId] ?? 0;

        final future = _generateSinglePart(
          blueprint: blueprint,
          task: task,
          generationId: generationId,
          attemptNumber: currentRetries + 1,
          referenceBody: referenceBody,
          taskHandle: taskHandle,
        ).then((_) {
          lastCompletedPartId = task.partId;
        }).catchError((Object error) {
          firstTerminalError ??= error;
          retryCounts[taskId] = currentRetries + 1;
        }).whenComplete(() {
          inFlight.remove(taskId);
        });

        inFlight[taskId] = future;
      }

      await emitProgress();

      if (inFlight.isNotEmpty) {
        // Wait for at least one in-flight task to complete before next scheduling cycle
        await Future.any(inFlight.values);
      } else {
        // No tasks in flight. If not all tasks are done and no ready tasks can be dispatched:
        final currentTasks =
            await _taskRepository.findTasksForResource(resourceId);
        final stillPendingOrReady = currentTasks.any((t) =>
            t.status == PartTaskStatus.pending.storageValue ||
            t.status == PartTaskStatus.ready.storageValue);
        final hasFailed = currentTasks
            .any((t) => t.status == PartTaskStatus.failed.storageValue);

        if (hasFailed) {
          // Check if any failed task can be retried
          var scheduledRetry = false;
          for (final failedTask in currentTasks
              .where((t) => t.status == PartTaskStatus.failed.storageValue)) {
            final retries = retryCounts[failedTask.taskId] ?? 0;
            if (retries < maxRetriesPerPart) {
              // Persist retry transition in database
              await _taskRepository.markTaskReady(failedTask.taskId);
              scheduledRetry = true;
            }
          }
          if (!scheduledRetry) {
            // Reached max retries on a required part; abort generation
            return false;
          }
        } else if (stillPendingOrReady) {
          // Deadlock: pending tasks remain but cannot become ready
          throw StateError(
            '正文生成调度死锁：存在未完成的 Part，但无任何前置依赖被满足',
          );
        } else {
          // All done
          break;
        }
      }
    }

    await emitProgress();
    return await _taskRepository.areAllTasksCompleted(resourceId);
  }

  /// Retries generating a single Part.
  Future<bool> retrySinglePart({
    required String blueprintId,
    required String partId,
    GenerationTaskHandle? taskHandle,
  }) async {
    final blueprint = await _blueprintRepository.findBlueprint(blueprintId);
    if (blueprint == null) {
      throw StateError('未找到 Blueprint: $blueprintId');
    }

    final task = await _taskRepository.findTaskByPartId(partId);
    if (task == null) {
      throw StateError('未找到对应的 Part 生成任务: $partId');
    }

    final session = await _pipeline.findSession(blueprint.sessionId);
    final referenceBody = session?.referenceSource.body ?? '';
    final generationId =
        'retry_${task.resourceId}_${DateTime.now().millisecondsSinceEpoch}';

    await _generateSinglePart(
      blueprint: blueprint,
      task: task,
      generationId: generationId,
      attemptNumber: 1,
      referenceBody: referenceBody,
      taskHandle: taskHandle,
    );

    final updated = await _taskRepository.findTask(task.taskId);
    return updated?.status == PartTaskStatus.completed.storageValue;
  }

  /// Executes one generation attempt for a single Part.
  Future<void> _generateSinglePart({
    required ResourceBlueprint blueprint,
    required ResourceGenerationTask task,
    required String generationId,
    required int attemptNumber,
    required String referenceBody,
    GenerationTaskHandle? taskHandle,
  }) async {
    if (taskHandle?.isCancelled == true) {
      await _taskRepository.cancelTasks(
        resourceId: task.resourceId,
        specificTaskId: task.taskId,
      );
      return;
    }

    // 1. Start attempt in database
    final attemptId = await _taskRepository.startAttempt(
      taskId: task.taskId,
      generationId: generationId,
      attemptNumber: attemptNumber,
    );

    try {
      if (taskHandle?.isCancelled == true) {
        await _taskRepository.cancelTasks(
          resourceId: task.resourceId,
          specificTaskId: task.taskId,
        );
        return;
      }

      // 2. Fetch completed dependencies content for context
      final depsMap = await _taskRepository.getPartsContent(task.dependencies);
      final depSummaries = <DependencyPartSummary>[];
      for (final depId in task.dependencies) {
        final data = depsMap[depId];
        if (data != null) {
          depSummaries.add(DependencyPartSummary(
            partId: PartId(depId),
            title: data.title,
            contentSummary: data.content,
          ));
        }
      }

      // 3. Find Section and Part metadata from Blueprint
      final rawPartId = _stripPrefix(task.partId, '${task.resourceId}_');
      final rawSectionId = _stripPrefix(task.sectionId, '${task.resourceId}_');

      final bpSection = blueprint.findSection(rawSectionId);
      final bpPart = blueprint.findPart(rawPartId);

      final sectionTitle = bpSection?.title ?? task.sectionId;
      final sectionSummary = bpSection?.summary ?? '';
      final partTitle = bpPart?.title ?? task.partId;

      final context = PartGenerationContext(
        resourceName: blueprint.suggestedName,
        resourceType: blueprint.resourceType,
        resourceSummary: blueprint.summary,
        sectionTitle: sectionTitle,
        sectionSummary: sectionSummary,
        partTitle: partTitle,
        dependencySummaries: depSummaries,
        referenceExcerpt: referenceBody,
      );

      final request = PartGenerationRequest(
        protocolVersion: currentPartGenerationProtocolVersion,
        generationId: generationId,
        resourceId: ResourceId(task.resourceId),
        sectionId: SectionId(task.sectionId),
        partId: PartId(task.partId),
        attemptId: attemptId,
        attemptNumber: attemptNumber,
        targetBudget: task.estimatedLength,
        promptGoal: task.promptGoal,
        context: context,
      );

      // 4. Build prompt and invoke LLM
      final systemPrompt =
          PartGenerationPromptBuilder.buildSystemPrompt(request);
      final instruction = PartGenerationPromptBuilder.buildInstruction(request);

      final rawCompletion = await _completer(
        systemPrompt: systemPrompt,
        instruction: instruction,
        task: LlmTask.resourcePartGeneration,
        taskHandle: taskHandle,
      );

      // 5. Parse and Validate
      await _taskRepository.recordValidating(
        taskId: task.taskId,
        attemptId: attemptId,
      );

      if (taskHandle?.isCancelled == true) {
        await _taskRepository.cancelTasks(
          resourceId: task.resourceId,
          specificTaskId: task.taskId,
        );
        return;
      }

      // 5. Parse via Patch Stream or Single Part JSON, and validate through Patch Accumulator
      final accumulator = GenerationPatchAccumulator(
        expectedGenerationId: request.generationId,
        expectedResourceId: request.resourceId,
        expectedSectionId: request.sectionId,
        expectedPartId: request.partId,
        expectedAttemptId: attemptId,
        maxCharacters: ResourceLimits.maxPartCharacters,
      );

      final PartGenerationResponse response;
      if (rawCompletion.contains('"op"') && rawCompletion.contains('part')) {
        final patches = GenerationPatchParser.parseNdjson(rawCompletion);
        for (final patch in patches) {
          accumulator.applyPatch(patch);
        }
        response = accumulator.toResponse();
      } else {
        response = PartGenerationParser.parse(rawCompletion);
        final patches = GenerationPatchParser.responseToPatches(response);
        for (final patch in patches) {
          accumulator.applyPatch(patch);
        }
      }

      PartGenerationValidator.validate(request: request, response: response);

      // 6. Atomically commit content
      await _taskRepository.commitPartContent(
        response: response,
        taskId: task.taskId,
        attemptId: attemptId,
      );
    } catch (e) {
      await _taskRepository.recordFailedAttempt(
        taskId: task.taskId,
        attemptId: attemptId,
        errorMessage: e.toString(),
      );
      rethrow;
    }
  }

  String _stripPrefix(String text, String prefix) {
    if (text.startsWith(prefix)) {
      return text.substring(prefix.length);
    }
    return text;
  }
}
