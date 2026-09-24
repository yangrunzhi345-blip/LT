import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../core/debug/generation_diagnostics.dart';
import '../../domain/resources/resource_blueprint.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_generation_patch.dart';
import '../../domain/resources/resource_generation_protocol.dart';
import '../../domain/resources/resource_limits.dart';
import '../../models/llm_task.dart';
import '../../services/llm_service.dart';
import '../../services/repositories/resource_tree_repository.dart'
    show ResourceTreeConflictException;
import '../llm/llm_gateway.dart';
import 'generation_patch_parser.dart';
import 'model_generation_patch_decoder.dart';
import 'part_generation_parser.dart' show PartGenerationParseException;
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

/// Granular callbacks emitted during the incremental Part generation lifecycle.
final class PartGenerationLifecycleCallbacks {
  const PartGenerationLifecycleCallbacks({
    this.onPartStarted,
    this.onPatchReceived,
    this.onPartPreviewUpdated,
    this.onValidationStarted,
    this.onValidationPassed,
    this.onValidationFailed,
    this.onBeforeCommit,
    this.onPartCommitted,
  });

  final FutureOr<void> Function({
    required String generationId,
    required ResourceId resourceId,
    required PartId partId,
    required String taskId,
    required String attemptId,
    required int attemptNumber,
  })? onPartStarted;

  final FutureOr<void> Function({
    required String generationId,
    required ResourceId resourceId,
    required PartId partId,
    required String taskId,
    required String attemptId,
    required ResourceGenerationPatch patch,
    required int accumulatedLength,
  })? onPatchReceived;

  /// Presentation-plane snapshot callback for the streaming path.
  ///
  /// Called at most once per [PartGenerationCoordinator.previewThrottleInterval]
  /// (plus one final flush when the patch stream ends). Carries the FULL
  /// accumulated preview text, so dropping intermediate snapshots loses
  /// nothing. UI preview is not the content authority.
  final FutureOr<void> Function({
    required String generationId,
    required ResourceId resourceId,
    required PartId partId,
    required String taskId,
    required String attemptId,
    required String accumulatedContent,
    required int accumulatedLength,
  })? onPartPreviewUpdated;

  final FutureOr<void> Function({
    required String generationId,
    required ResourceId resourceId,
    required PartId partId,
    required String taskId,
    required String attemptId,
  })? onValidationStarted;

  final FutureOr<void> Function({
    required String generationId,
    required ResourceId resourceId,
    required PartId partId,
    required String taskId,
    required String attemptId,
    required int characterCount,
  })? onValidationPassed;

  final FutureOr<void> Function({
    required String generationId,
    required ResourceId resourceId,
    required PartId partId,
    required String taskId,
    required String attemptId,
    required String errorMessage,
  })? onValidationFailed;

  final FutureOr<void> Function({
    required String generationId,
    required ResourceId resourceId,
    required PartId partId,
    required String taskId,
    required String attemptId,
  })? onBeforeCommit;

  final FutureOr<void> Function({
    required String generationId,
    required ResourceId resourceId,
    required PartId partId,
    required String taskId,
    required String attemptId,
    required int characterCount,
  })? onPartCommitted;
}

/// Coordinator that orchestrates the topological DAG generation of Part body text.
final class PartGenerationCoordinator {
  PartGenerationCoordinator({
    required IPartGenerationTaskRepository taskRepository,
    required IResourceBlueprintRepository blueprintRepository,
    required ResourceCreationPipeline pipeline,
    PartRawCompleter? completer,
    LlmGateway? gateway,
    this.maxConcurrency = 2,
    this.previewThrottleInterval = const Duration(milliseconds: 150),
    this.stallWatchdogThreshold = const Duration(seconds: 10),
  })  : _taskRepository = taskRepository,
        _blueprintRepository = blueprintRepository,
        _pipeline = pipeline,
        _completer = completer ?? _createGatewayCompleter(gateway),
        _streamingGateway = gateway is PartGenerationStreamingGateway
            ? gateway as PartGenerationStreamingGateway
            : null;

  final IPartGenerationTaskRepository _taskRepository;
  final IResourceBlueprintRepository _blueprintRepository;
  final ResourceCreationPipeline _pipeline;
  final PartRawCompleter _completer;
  final PartGenerationStreamingGateway? _streamingGateway;
  final int maxConcurrency;

  /// Minimum interval between presentation-plane preview snapshots of one
  /// Part. Protocol patches are still decoded and applied at full rate;
  /// only the UI publication is throttled (P0 presentation/protocol split).
  final Duration previewThrottleInterval;

  /// How long the scheduler may sit without any lifecycle transition before
  /// the stall watchdog dumps diagnostics. Never mutates task data.
  final Duration stallWatchdogThreshold;

  /// The retry allowance of the pass currently running, or null when no pass
  /// is in flight.
  ///
  /// Exposed so diagnostics and tests can assert the dispatch budget without
  /// reconstructing it: the budget is `1 + maxRetriesPerPart` dispatches per
  /// task (the original attempt plus the user's configured retries).
  @visibleForTesting
  int? get activeAttemptBudget =>
      _activeMaxRetriesPerPart == null ? null : _activeMaxRetriesPerPart! + 1;

  int? _activeMaxRetriesPerPart;

  // Presentation-queue metrics, accumulated across one coordinator lifetime
  // (one generateAllParts run) so tests can assert boundedness.
  int _presentationEnqueued = 0;
  int _presentationDrained = 0;
  int _presentationDropped = 0;
  int _presentationMaxQueueDepth = 0;

  @visibleForTesting
  int get presentationEnqueued => _presentationEnqueued;

  @visibleForTesting
  int get presentationDrained => _presentationDrained;

  @visibleForTesting
  int get presentationDropped => _presentationDropped;

  @visibleForTesting
  int get presentationMaxQueueDepth => _presentationMaxQueueDepth;

  /// Test seam: number of tasks with an in-flight generation Future.
  ///
  /// Must be 0 once a pass has settled — a non-zero value after cancellation
  /// or a retry-budget exhaustion would mean a leaked lease.
  @visibleForTesting
  int inFlightCount() => _inFlightCount;

  int _inFlightCount = 0;

  /// Test seam: dispatches consumed per task in the most recent pass.
  ///
  /// The anti-spin invariant is `dispatches[task] <= 1 + maxRetriesPerPart`
  /// for every task; a larger value means the dispatch gate was bypassed.
  @visibleForTesting
  Map<String, int> dispatchCountSnapshot() => Map<String, int>.unmodifiable(
      _lastDispatchCounts ?? const <String, int>{});

  Map<String, int>? _lastDispatchCounts;

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
    int? maxConcurrentParts,
    bool cancelTasksOnCancellation = true,
    String? operationId,
    PartGenerationLifecycleCallbacks? callbacks,
  }) async {
    final concurrentPartLimit = maxConcurrentParts ?? maxConcurrency;
    if (concurrentPartLimit <= 0) {
      throw ArgumentError.value(
        maxConcurrentParts,
        'maxConcurrentParts',
        '必须大于零',
      );
    }
    _activeMaxRetriesPerPart = maxRetriesPerPart;

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
    final referenceIndexWatch = Stopwatch()..start();
    final referenceIndex = ReferenceContextIndex(referenceBody);
    referenceIndexWatch.stop();
    // Worldview/dependency control-group evidence (P0): the resolved
    // reference length and index build cost, so a real-device run can
    // compare A (no worldview) / B / C (large worldview) runs.
    GenerationDiagnostics.instance
      ..recordDuration('reference.indexBuild', referenceIndexWatch.elapsed)
      ..mark('REFERENCE_INDEX_BUILT', {
        'resolvedReferenceLength': referenceBody.length,
        'paragraphs': referenceIndex.paragraphs.length,
        'elapsed': '${referenceIndexWatch.elapsedMilliseconds}ms',
      });

    final generationId =
        operationId ?? 'gen_${blueprint.sessionId}_${blueprint.blueprintId}';

    // Track in-flight tasks and retry counters per task
    final inFlight = <String, Future<void>>{};
    final retryCounts = <String, int>{};

    // ─── Retry budget (P0 spin fix) ───
    //
    // `retryCounts` is the SINGLE authority for how many automatic attempts a
    // task has consumed in this pass. It used to be incremented only on the
    // Future rejection path, so a failure that never reached an HTTP request
    // (startAttempt error, onPartStarted callback error, recovery flipping the
    // row back to `ready`) consumed nothing and the scheduler re-dispatched
    // the same task forever.
    //
    // Every dispatch now increments the budget BEFORE the attempt starts, and
    // the dispatch gate is evaluated before every dispatch, so the budget is
    // monotonic regardless of where the failure occurred: before
    // `startAttempt`, inside `onPartStarted`, while reading dependencies,
    // building the prompt, on HTTP, on NDJSON parse, on validation, or before
    // commit.
    // Dispatches consumed per task (diagnostic + invariant).
    final dispatchCounts = <String, int>{};
    _lastDispatchCounts = dispatchCounts;
    // Tasks whose budget was already spent and were force-converged, so the
    // scheduler does not repeat the terminal write every iteration.
    final budgetExhausted = <String>{};

    /// Attempts a single task may consume in this pass.
    ///
    /// The FIRST dispatch is the original generation, so the user's configured
    /// retry allowance `maxRetriesPerPart` maps to `1 + maxRetriesPerPart`
    /// total attempts exactly as before this fix.
    int attemptBudgetFor(String taskId) => maxRetriesPerPart + 1;

    int consumedAttemptsFor(String taskId) => retryCounts[taskId] ?? 0;

    bool canDispatch(String taskId) =>
        consumedAttemptsFor(taskId) < attemptBudgetFor(taskId);

    /// Anti-spin invariant (P0): no task may be dispatched more often than its
    /// attempt budget. Exposed for tests; a violation means the scheduler
    /// found a path around the dispatch gate.
    @visibleForTesting
    bool assertDispatchWithinBudget() {
      for (final entry in dispatchCounts.entries) {
        if (entry.value > attemptBudgetFor(entry.key)) {
          GenerationDiagnostics.instance.dump(
            reason: 'DISPATCH_BUDGET_INVARIANT_VIOLATED '
                'taskId=${entry.key} '
                'dispatchCount=${entry.value} '
                'budget=${attemptBudgetFor(entry.key)}',
          );
          return false;
        }
      }
      return true;
    }

    /// Consumes one attempt slot. Returns the 1-based attempt number to run.
    int consumeAttempt(String taskId) {
      final next = consumedAttemptsFor(taskId) + 1;
      retryCounts[taskId] = next;
      dispatchCounts[taskId] = (dispatchCounts[taskId] ?? 0) + 1;
      GenerationDiagnostics.instance
        ..counter('retry.dispatch')
        ..setCounter('retry.lastAttemptNumber', next)
        ..observeMax('retry.maxAttemptNumber', next);
      // Fail closed if the gate were ever bypassed: this fires the diagnostic
      // dump at the exact dispatch that exceeded the budget.
      assertDispatchWithinBudget();
      return next;
    }

    /// Leaves one event-loop turn so UI events, timers, cancellation and the
    /// stall watchdog can run between two immediate re-dispatches.
    ///
    /// This is scheduler fairness, not a race workaround: the fast-fail path
    /// (recover -> ready -> dispatch -> fail) performs no network await, so
    /// without it the loop can starve the event loop even though every step
    /// is individually correct. `scheduleMicrotask` is deliberately not used
    /// because microtasks drain before timers and would not help.
    Future<void> yieldToEventLoop() => Future<void>.delayed(Duration.zero);

    /// Converges an exhausted task to a terminal `failed` so no dispatchable
    /// `ready` row is left behind (and no permanent spin is possible).
    Future<void> exhaustBudget(
      ResourceGenerationTask task, {
      required String reason,
    }) async {
      if (!budgetExhausted.add(task.taskId)) return;
      GenerationDiagnostics.instance
        ..counter('retry.budgetExhausted')
        ..mark('PART[${task.partId}] RETRY_BUDGET_EXHAUSTED', {
          'dispatches': dispatchCounts[task.taskId] ?? 0,
          'budget': attemptBudgetFor(task.taskId),
          'reason': reason,
        });
      await _taskRepository.markRetryExhausted(
        taskId: task.taskId,
        errorMessage: reason,
      );
    }

    /// Tasks whose attempt lost the source-content CAS because the user edited
    /// the Part mid-generation. Re-running them would overwrite that edit, so
    /// they are terminal for this pass and are never auto-retried (R02-B).
    final sourceConflicted = <String>{};
    String? lastCompletedPartId;

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

    // Part-transition stall watchdog (P0). After a Part commits exactly one of
    // (next ATTEMPT_STARTED | GenerationCompleted | Failed/Cancelled) must
    // happen within [stallWatchdogThreshold]; otherwise the watchdog dumps a
    // diagnostic snapshot. It never mutates task or session data.
    var lastTransitionAt = DateTime.now();
    var lastTransitionLabel = 'RUN_STARTED';
    var stallDumped = false;
    Timer? stallTimer;

    void noteTransition(String label) {
      lastTransitionAt = DateTime.now();
      lastTransitionLabel = label;
      stallDumped = false;
      GenerationDiagnostics.instance
        ..runtimeHeartbeat('coordinator.transition:$label')
        ..mark('TRANSITION $label');
    }

    Future<void> dumpSchedulerStall() async {
      final tasks = await _taskRepository.findTasksForResource(resourceId);
      final statusLines =
          tasks.map((t) => '${t.partId}:${t.status}').join(', ');
      GenerationDiagnostics.instance.dump(
        reason: 'PART_TRANSITION_STALL '
            'sessionId=$generationId '
            'resourceId=$resourceId '
            'lastTransition=$lastTransitionLabel '
            'age=${DateTime.now().difference(lastTransitionAt)} '
            'inFlightTaskIds=${inFlight.keys.toList()} '
            'retryCounts=$retryCounts '
            'sourceConflicted=${sourceConflicted.toList()} '
            'tasks=[$statusLines]',
      );
    }

    void armStallWatchdog() {
      stallTimer?.cancel();
      if (stallWatchdogThreshold <= Duration.zero) return;
      stallTimer = Timer(stallWatchdogThreshold, () {
        if (stallDumped) return;
        stallDumped = true;
        unawaited(dumpSchedulerStall());
      });
    }

    try {
      while (true) {
        GenerationDiagnostics.instance
          ..runtimeHeartbeat('coordinator.loop')
          ..mark('SCHEDULER_NEXT_ITERATION', {'inFlight': inFlight.length});
        armStallWatchdog();

        if (taskHandle?.isCancelled == true) {
          if (cancelTasksOnCancellation) {
            await _taskRepository.cancelTasks(resourceId: resourceId);
          }
          await emitProgress();
          return false;
        }

        final allTasks = await _taskRepository.findTasksForResource(resourceId);
        final isAllDone = allTasks.every(
          (t) => t.status == PartTaskStatus.completed.storageValue,
        );
        if (isAllDone) {
          noteTransition('GENERATION_COMPLETED');
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
          if (inFlight.length >= concurrentPartLimit) break;
          if (taskHandle?.isCancelled == true) break;

          final taskId = task.taskId;

          // Hard retry-budget gate. Evaluated BEFORE every dispatch, so a task
          // that keeps failing without ever reaching an HTTP request cannot be
          // re-dispatched past its allowance — the previous gate only ran on
          // the `failed` branch, which `recoverInterruptedTasks` could bypass
          // by flipping `generating` straight back to `ready`.
          if (!canDispatch(taskId)) {
            await exhaustBudget(
              task,
              reason: '自动重试次数已用尽（budget=${attemptBudgetFor(taskId)}）',
            );
            await emitProgress();
            continue;
          }

          final attemptNumber = consumeAttempt(taskId);

          GenerationDiagnostics.instance.mark(
            'PART[${task.partId}] READY -> DISPATCH',
            {
              'attempt': attemptNumber,
              'budget': attemptBudgetFor(taskId),
              'deps': task.dependencies,
            },
          );

          final future = _generateSinglePart(
            blueprint: blueprint,
            task: task,
            generationId: generationId,
            attemptNumber: attemptNumber,
            referenceIndex: referenceIndex,
            taskHandle: taskHandle,
            callbacks: callbacks,
            cancelTasksOnCancellation: cancelTasksOnCancellation,
          ).then((_) {
            lastCompletedPartId = task.partId;
          }).catchError((Object error) {
            if (error is ResourceTreeConflictException) {
              // The Part changed after this attempt observed it. Surfaced as a
              // stale conflict below instead of a retry that would overwrite it.
              sourceConflicted.add(taskId);
            }
            // The attempt slot was already consumed before dispatch; the
            // failure itself is recorded on the task/attempt rows by
            // `_convergeFailedAttempt`.
          }).whenComplete(() {
            inFlight.remove(taskId);
            _inFlightCount = inFlight.length;
            noteTransition('PART[${task.partId}] FUTURE_SETTLED');
          });

          inFlight[taskId] = future;
          _inFlightCount = inFlight.length;
        }

        await emitProgress();

        if (inFlight.isNotEmpty) {
          // Wait for at least one in-flight task to complete before next
          // scheduling cycle. The stall watchdog armed above fires if this
          // await never returns.
          await Future.any(inFlight.values);
        } else {
          // The database is authoritative when no local Future owns a lease.
          // A cancelled UI task or a process interruption can otherwise leave a
          // persisted generating/validating row with no in-flight Future. First
          // converge such leases, then recompute readiness from a fresh snapshot
          // before declaring a persistent DAG inconsistency.
          final recovered =
              await _taskRepository.recoverInterruptedTasks(resourceId);
          if (recovered > 0) {
            // A recovery just produced dispatchable work without any network
            // await; give the event loop one turn so UI, timers, cancellation
            // and the stall watchdog are not starved by an immediate
            // re-dispatch.
            await yieldToEventLoop();
            continue;
          }
          final recomputedReady =
              await _taskRepository.findReadyTasks(resourceId);
          final currentTasks =
              await _taskRepository.findTasksForResource(resourceId);
          if (recomputedReady.isNotEmpty ||
              currentTasks.any(
                (task) => task.status == PartTaskStatus.ready.storageValue,
              )) {
            // Ready rows whose budget is spent are terminal, not dispatchable.
            // Converge them before deciding the pass can continue, otherwise
            // the loop would spin on a `ready` row it may never dispatch.
            var convergedAny = false;
            for (final readyTask in currentTasks.where(
              (t) => t.status == PartTaskStatus.ready.storageValue,
            )) {
              if (canDispatch(readyTask.taskId)) continue;
              await exhaustBudget(
                readyTask,
                reason: '自动重试次数已用尽'
                    '（budget=${attemptBudgetFor(readyTask.taskId)}）',
              );
              convergedAny = true;
            }
            if (convergedAny) {
              await emitProgress();
              await yieldToEventLoop();
            }
            continue;
          }
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
              // R02-B: a stale source conflict is terminal. Re-running it would
              // regenerate from — and then overwrite — the user's newer edit.
              if (sourceConflicted.contains(failedTask.taskId)) continue;
              if (!canDispatch(failedTask.taskId)) {
                await exhaustBudget(
                  failedTask,
                  reason: '自动重试次数已用尽'
                      '（budget=${attemptBudgetFor(failedTask.taskId)}）',
                );
                continue;
              }
              // Persist retry transition in database. The attempt slot is
              // consumed by the next dispatch, so nothing is spent here.
              await _taskRepository.markTaskReady(failedTask.taskId);
              scheduledRetry = true;
            }
            if (!scheduledRetry) {
              // Reached max retries on a required part, or the only failures are
              // stale source conflicts; abort generation
              noteTransition('RUN_FAILED_MAX_RETRIES');
              return false;
            }
            // A retry transition happened with no network await in between;
            // yield so the loop cannot starve the event loop.
            await yieldToEventLoop();
          } else if (stillPendingOrReady) {
            // Deadlock: pending tasks remain but cannot become ready
            throw StateError(await _deadlockDiagnostic(currentTasks));
          } else {
            // A cancelled prerequisite is never a normal pending-DAG deadlock.
            // This is persisted invalid state for this pass; fail closed with a
            // full snapshot so the lifecycle owner can distinguish it.
            noteTransition('SCHEDULER_DEADLOCK');
            throw StateError(await _deadlockDiagnostic(currentTasks));
          }
        }
      }
    } finally {
      stallTimer?.cancel();
    }

    // The loop returns as soon as the persisted task set is complete.
  }

  Future<String> _deadlockDiagnostic(List<ResourceGenerationTask> tasks) async {
    final completedPartIds = tasks
        .where((task) => task.status == PartTaskStatus.completed.storageValue)
        .map((task) => task.partId)
        .toSet();
    final knownPartIds = tasks.map((task) => task.partId).toSet();
    final rows = <String>[];
    for (final task in tasks.where(
      (task) => task.status != PartTaskStatus.completed.storageValue,
    )) {
      final unmet = task.dependencies
          .where((dependency) => !completedPartIds.contains(dependency))
          .toList(growable: false);
      final missing =
          unmet.where((dependency) => !knownPartIds.contains(dependency));
      final dependencyState = missing.isNotEmpty
          ? 'MISSING_DEPENDENCY'
          : unmet.isEmpty
              ? 'INVALID_STATE'
              : _dependencyBlockState(tasks, unmet);
      final attempt = task.currentAttemptId.isEmpty
          ? null
          : await _taskRepository.findAttempt(task.currentAttemptId);
      rows.add('taskId=${task.taskId}, partId=${task.partId}, '
          'status=${task.status}, dependencies=${task.dependencies}, '
          'unmetDependencies=$unmet, blockState=$dependencyState, '
          'currentAttemptId=${task.currentAttemptId}, '
          'attemptStatus=${attempt?.status ?? 'none'}, '
          'attemptGenerationId=${attempt?.generationId ?? 'none'}');
    }
    return '正文生成调度无法推进：持久化任务状态不满足可恢复条件。'
        '未完成任务全量状态：${rows.join('; ')}';
  }

  String _dependencyBlockState(
    List<ResourceGenerationTask> tasks,
    List<String> unmetDependencies,
  ) {
    final statuses = <String>{};
    for (final dependency in unmetDependencies) {
      statuses.addAll(
        tasks
            .where((task) => task.partId == dependency)
            .map((task) => task.status),
      );
    }
    if (statuses.contains(PartTaskStatus.cancelled.storageValue)) {
      return 'BLOCKED_BY_CANCELLED';
    }
    if (statuses.contains(PartTaskStatus.failed.storageValue)) {
      return 'BLOCKED_BY_FAILED';
    }
    if (statuses.contains(PartTaskStatus.generating.storageValue)) {
      return 'BLOCKED_BY_GENERATING';
    }
    if (statuses.contains(PartTaskStatus.validating.storageValue)) {
      return 'BLOCKED_BY_VALIDATING';
    }
    if (statuses.contains(PartTaskStatus.pending.storageValue) ||
        statuses.contains(PartTaskStatus.ready.storageValue)) {
      return 'BLOCKED_BY_PENDING';
    }
    return 'INVALID_STATE';
  }

  /// Retries generating a single Part.
  ///
  /// [userInstruction] is an optional Phase 7 node-scoped directive (for
  /// example a rewrite/expand/condense request). It only ever reaches the
  /// prompt for this one Part; the incremental protocol is unchanged, and an
  /// empty value reproduces the pre-Phase-7 prompt exactly.
  Future<bool> retrySinglePart({
    required String blueprintId,
    required String partId,
    GenerationTaskHandle? taskHandle,
    PartGenerationLifecycleCallbacks? callbacks,
    bool cancelTasksOnCancellation = true,
    String userInstruction = '',
  }) async {
    final blueprint = await _blueprintRepository.findBlueprint(blueprintId);
    if (blueprint == null) {
      throw StateError('未找到 Blueprint: $blueprintId');
    }

    final task = await _taskRepository.findTaskByPartId(partId);
    if (task == null) {
      throw StateError('未找到对应的 Part 生成任务: $partId');
    }
    if (task.status == PartTaskStatus.failed.storageValue) {
      await _taskRepository.markTaskReady(task.taskId);
    }
    final readyTask = await _taskRepository.findTask(task.taskId);
    if (readyTask == null ||
        readyTask.status != PartTaskStatus.ready.storageValue) {
      throw StateError('任务未处于可重试的 ready 状态：${task.taskId}');
    }

    final session = await _pipeline.findSession(blueprint.sessionId);
    final referenceBody = session?.referenceSource.body ?? '';
    final referenceIndex = ReferenceContextIndex(referenceBody);
    // A node-scoped directive cannot be reconstructed after a process crash.
    // Mark its attempt identity so recovery can fail closed instead of
    // silently replaying the task as an ordinary, instruction-less retry.
    final generationKind =
        userInstruction.trim().isEmpty ? 'retry' : 'directed_retry';
    final generationId =
        '${generationKind}_${task.resourceId}_${DateTime.now().millisecondsSinceEpoch}';

    await _generateSinglePart(
      blueprint: blueprint,
      task: readyTask,
      generationId: generationId,
      attemptNumber: 1,
      referenceIndex: referenceIndex,
      taskHandle: taskHandle,
      callbacks: callbacks,
      cancelTasksOnCancellation: cancelTasksOnCancellation,
      userInstruction: userInstruction,
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
    required ReferenceContextIndex referenceIndex,
    GenerationTaskHandle? taskHandle,
    PartGenerationLifecycleCallbacks? callbacks,
    required bool cancelTasksOnCancellation,
    String userInstruction = '',
  }) async {
    if (taskHandle?.isCancelled == true) {
      if (cancelTasksOnCancellation) {
        await _taskRepository.cancelTasks(
          resourceId: task.resourceId,
          specificTaskId: task.taskId,
        );
      }
      return;
    }

    // 1. Start attempt in database. The returned handle carries the Part's
    // source token captured atomically with the lease; the commit later CASes
    // against it so a mid-generation manual edit can never be overwritten.
    //
    // Ownership rule (P0 spin fix): once `startAttempt` returns, EVERY later
    // failure — including one thrown by `onPartStarted` itself — must run the
    // attempt lifecycle epilogue. Previously `onPartStarted` sat outside the
    // protected block, so an exception from it (e.g. an illegal session
    // transition) escaped with the attempt still `started`, the task still
    // `generating` and no failure recorded: the scheduler then recovered the
    // row to `ready` and dispatched it again, forever. The protected block
    // therefore opens BEFORE the callback and `attemptId` is captured first.
    PartGenerationAttempt? attempt;
    var attemptId = '';
    var commitOwned = false;
    try {
      attempt = await _taskRepository.startAttempt(
        taskId: task.taskId,
        generationId: generationId,
        attemptNumber: attemptNumber,
      );
      attemptId = attempt.attemptId;

      GenerationDiagnostics.instance
        ..runtimeHeartbeat('part.attemptStarted')
        ..mark('PART[${task.partId}] ATTEMPT_STARTED', {
          'attempt': attemptId,
          'attemptNumber': attemptNumber,
        });

      await callbacks?.onPartStarted?.call(
        generationId: generationId,
        resourceId: ResourceId(task.resourceId),
        partId: PartId(task.partId),
        taskId: task.taskId,
        attemptId: attemptId,
        attemptNumber: attemptNumber,
      );
    } catch (e) {
      await _convergeFailedAttempt(
        task: task,
        attemptId: attemptId,
        error: e,
        commitOwned: commitOwned,
        cancelTasksOnCancellation: cancelTasksOnCancellation,
        taskHandle: taskHandle,
      );
      rethrow;
    }

    Future<void> convergeCancellation() {
      if (cancelTasksOnCancellation) {
        return _taskRepository.cancelTasks(
          resourceId: task.resourceId,
          specificTaskId: task.taskId,
        );
      }
      return _taskRepository.interruptAttempt(
        taskId: task.taskId,
        attemptId: attemptId,
        reason: 'Generation interrupted by task-handle cancellation',
      );
    }

    try {
      if (taskHandle?.isCancelled == true) {
        await convergeCancellation();
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

      final excerptWatch = Stopwatch()..start();
      final referenceExcerpt =
          PartGenerationPromptBuilder.selectRelevantReference(
        referenceIndex,
        keywords: [partTitle, task.promptGoal],
      );
      excerptWatch.stop();
      GenerationDiagnostics.instance
        ..recordDuration('reference.excerptSelect', excerptWatch.elapsed)
        ..setCounter('reference.lastExcerptLength', referenceExcerpt.length);

      final context = PartGenerationContext(
        resourceName: blueprint.suggestedName,
        resourceType: blueprint.resourceType,
        resourceSummary: blueprint.summary,
        sectionTitle: sectionTitle,
        sectionSummary: sectionSummary,
        partTitle: partTitle,
        dependencySummaries: depSummaries,
        referenceExcerpt: referenceExcerpt,
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
        userInstruction: userInstruction,
      );

      // 4. Build prompt and invoke LLM
      final systemPrompt =
          PartGenerationPromptBuilder.buildSystemPrompt(request);
      final instruction = PartGenerationPromptBuilder.buildInstruction(request);
      GenerationDiagnostics.instance
        ..setCounter('prompt.lastSystemLength', systemPrompt.length)
        ..setCounter('prompt.lastInstructionLength', instruction.length)
        ..observeMax('prompt.maxInstructionLength', instruction.length);

      await _taskRepository.recordValidating(
        taskId: task.taskId,
        attemptId: attemptId,
      );

      if (taskHandle?.isCancelled == true) {
        await convergeCancellation();
        return;
      }

      final accumulator = GenerationPatchAccumulator(
        expectedGenerationId: request.generationId,
        expectedResourceId: request.resourceId,
        expectedSectionId: request.sectionId,
        expectedPartId: request.partId,
        expectedAttemptId: attemptId,
        maxCharacters: ResourceLimits.maxPartCharacters,
      );
      final patchDecoder = ModelGenerationPatchDecoder(request);

      PartGenerationResponse response;
      if (_streamingGateway != null) {
        final pendingLine = StringBuffer();
        // Presentation-plane queue: UI callbacks only, bounded by coalescing.
        // Protocol decode/validate/accumulate stays full-rate and fail-closed
        // and never waits on this queue.
        const maxQueuedPresentationCallbacks = 4;
        final patchCallbackQueue = Queue<Future<void> Function()>();
        Future<void>? callbackDrain;
        var drainingCallbacks = false;
        var sawFirstSseEvent = false;
        var sawFirstPatch = false;
        var lastPatchSummary = '';
        var lastPreviewPublishAt = DateTime.fromMillisecondsSinceEpoch(0);

        void diagMark(String stage) {
          GenerationDiagnostics.instance
            ..runtimeHeartbeat('part.$stage')
            ..mark('PART[${task.partId}] $stage', {'attempt': attemptId});
        }

        Future<void> drainPatchCallbacks() async {
          while (patchCallbackQueue.isNotEmpty) {
            final callback = patchCallbackQueue.removeFirst();
            GenerationDiagnostics.instance.setCounter(
              'presentation.queueDepth',
              patchCallbackQueue.length,
            );
            _presentationDrained++;
            GenerationDiagnostics.instance.counter('presentation.drained');
            await callback();
          }
          GenerationDiagnostics.instance.setCounter(
            'presentation.queueDepth',
            0,
          );
        }

        /// Enqueues one UI callback. When the consumer cannot keep up, the
        /// OLDEST queued callback is dropped: preview callbacks read the
        /// accumulator snapshot at execution time, so the newest entry always
        /// carries the full content and dropping stale ones loses nothing.
        void enqueuePresentationCallback(Future<void> Function() callback) {
          while (patchCallbackQueue.length >= maxQueuedPresentationCallbacks) {
            patchCallbackQueue.removeFirst();
            _presentationDropped++;
            GenerationDiagnostics.instance
              ..counter('presentation.dropped')
              ..setCounter(
                'presentation.queueDepth',
                patchCallbackQueue.length,
              );
          }
          patchCallbackQueue.add(callback);
          _presentationEnqueued++;
          if (patchCallbackQueue.length > _presentationMaxQueueDepth) {
            _presentationMaxQueueDepth = patchCallbackQueue.length;
          }
          GenerationDiagnostics.instance
            ..counter('presentation.enqueued')
            ..setCounter('presentation.queueDepth', patchCallbackQueue.length)
            ..observeMax(
                'presentation.maxQueueDepth', patchCallbackQueue.length);
          if (drainingCallbacks) return;
          drainingCallbacks = true;
          callbackDrain = drainPatchCallbacks().whenComplete(() {
            drainingCallbacks = false;
          });
        }

        /// Presentation plane: publish a throttled accumulated snapshot.
        /// [force] bypasses the throttle (final flush before validation).
        void schedulePreviewPublish({required bool force}) {
          if (callbacks?.onPartPreviewUpdated == null) return;
          final now = DateTime.now();
          if (!force &&
              now.difference(lastPreviewPublishAt) < previewThrottleInterval) {
            GenerationDiagnostics.instance.counter('preview.publishThrottled');
            return;
          }
          lastPreviewPublishAt = now;
          // Read the accumulator at execution time: after queue coalescing the
          // latest snapshot is always the one published.
          enqueuePresentationCallback(() async {
            await callbacks?.onPartPreviewUpdated?.call(
              generationId: generationId,
              resourceId: request.resourceId,
              partId: request.partId,
              taskId: task.taskId,
              attemptId: attemptId,
              accumulatedContent: accumulator.currentText,
              accumulatedLength: accumulator.currentLength,
            );
          });
        }

        /// Protocol plane: full-rate, strict, fail-closed. Only the FIRST
        /// patch prints a marker; the last one is summarized at stream end.
        void dispatchLine(String line) {
          if (line.trim().isEmpty) return;
          final patch = patchDecoder.decodeLine(line);
          accumulator.applyPatch(patch);
          GenerationDiagnostics.instance
            ..counter('protocol.patchApplied')
            ..setCounter('protocol.lastPatchSeq', patch.sequence)
            ..observeMax('protocol.maxPartPatchCount', patch.sequence + 1);
          if (!sawFirstPatch) {
            GenerationDiagnostics.instance.mark(
              'PART[${task.partId}] FIRST_NDJSON_PATCH',
              {'seq': patch.sequence, 'op': patch.op.wireValue},
            );
          }
          sawFirstPatch = true;
          lastPatchSummary = 'seq=${patch.sequence} op=${patch.op.wireValue}';
          if (callbacks?.onPatchReceived != null) {
            final accumulatedLength = accumulator.currentLength;
            enqueuePresentationCallback(() async {
              await callbacks?.onPatchReceived?.call(
                generationId: generationId,
                resourceId: request.resourceId,
                partId: request.partId,
                taskId: task.taskId,
                attemptId: attemptId,
                patch: patch,
                accumulatedLength: accumulatedLength,
              );
            });
          }
          schedulePreviewPublish(force: false);
        }

        void consume(String chunk) {
          if (!sawFirstSseEvent) {
            sawFirstSseEvent = true;
            GenerationDiagnostics.instance.mark(
              'PART[${task.partId}] FIRST_SSE_EVENT',
            );
          }
          GenerationDiagnostics.instance.runtimeHeartbeat('part.sseChunk');
          var segmentStart = 0;
          for (var index = 0; index < chunk.length; index++) {
            if (chunk.codeUnitAt(index) != 10) continue;
            final segment = chunk.substring(segmentStart, index);
            if (pendingLine.isEmpty) {
              dispatchLine(segment);
            } else {
              pendingLine.write(segment);
              dispatchLine(pendingLine.toString());
              pendingLine.clear();
            }
            segmentStart = index + 1;
          }
          if (segmentStart < chunk.length) {
            pendingLine.write(chunk.substring(segmentStart));
          }
        }

        try {
          diagMark('HTTP_REQUEST_START');
          await _streamingGateway!.streamPartGeneration(
            systemPrompt: systemPrompt,
            instruction: instruction,
            task: LlmTask.resourcePartGeneration,
            onChunk: consume,
            taskHandle: taskHandle,
          );
          diagMark('STREAM_RETURNED');
          if (pendingLine.isNotEmpty) {
            dispatchLine(pendingLine.toString());
            pendingLine.clear();
          }
          GenerationDiagnostics.instance
              .mark('PART[${task.partId}] LAST_NDJSON_PATCH', {
            'summary': lastPatchSummary,
            'accumulatedLength': accumulator.currentLength,
          });
          if (pendingLine.isNotEmpty) {
            dispatchLine(pendingLine.toString());
            pendingLine.clear();
          }
          // Final presentation flush: the last preview snapshot before
          // validation/commit must reflect the complete accumulated text.
          schedulePreviewPublish(force: true);
          diagMark('CALLBACK_DRAIN_BEGIN');
          if (callbackDrain != null) await callbackDrain;
          diagMark('CALLBACK_DRAIN_END');
          response = accumulator.toResponse();
        } catch (e) {
          if (e is PartGenerationParseException ||
              e is GenerationPatchParseException ||
              e is PatchSequenceGapException ||
              e is PatchCursorMismatchException) {
            await callbacks?.onValidationStarted?.call(
              generationId: generationId,
              resourceId: request.resourceId,
              partId: request.partId,
              taskId: task.taskId,
              attemptId: attemptId,
            );
            await callbacks?.onValidationFailed?.call(
              generationId: generationId,
              resourceId: request.resourceId,
              partId: request.partId,
              taskId: task.taskId,
              attemptId: attemptId,
              errorMessage: _failureCode(e),
            );
          }
          rethrow;
        }
      } else {
        final rawCompletion = await _completer(
          systemPrompt: systemPrompt,
          instruction: instruction,
          task: LlmTask.resourcePartGeneration,
          taskHandle: taskHandle,
        );
        try {
          // The prompt contract is NDJSON regardless of whether transport
          // delivers it incrementally or as one collected completion.
          final patches = patchDecoder.decodeNdjson(rawCompletion);
          for (final patch in patches) {
            accumulator.applyPatch(patch);
            await callbacks?.onPatchReceived?.call(
              generationId: generationId,
              resourceId: request.resourceId,
              partId: request.partId,
              taskId: task.taskId,
              attemptId: attemptId,
              patch: patch,
              accumulatedLength: accumulator.currentLength,
            );
          }
          // Presentation-plane final flush: mirror the streaming path so the
          // Studio receives one accumulated snapshot even when the transport
          // is non-streaming.
          final previewCallback = callbacks?.onPartPreviewUpdated;
          if (previewCallback != null) {
            await previewCallback(
              generationId: generationId,
              resourceId: request.resourceId,
              partId: request.partId,
              taskId: task.taskId,
              attemptId: attemptId,
              accumulatedContent: accumulator.currentText,
              accumulatedLength: accumulator.currentLength,
            );
          }
          response = accumulator.toResponse();
        } catch (e) {
          if (e is PartGenerationParseException ||
              e is GenerationPatchParseException ||
              e is PatchSequenceGapException ||
              e is PatchCursorMismatchException) {
            await callbacks?.onValidationStarted?.call(
              generationId: generationId,
              resourceId: request.resourceId,
              partId: request.partId,
              taskId: task.taskId,
              attemptId: attemptId,
            );
            await callbacks?.onValidationFailed?.call(
              generationId: generationId,
              resourceId: request.resourceId,
              partId: request.partId,
              taskId: task.taskId,
              attemptId: attemptId,
              errorMessage: _failureCode(e),
            );
          }
          rethrow;
        }
      }

      if (taskHandle?.isCancelled == true) {
        await convergeCancellation();
        return;
      }

      GenerationDiagnostics.instance.mark(
        'PART[${task.partId}] VALIDATION_BEGIN',
        {'chars': response.content.length},
      );
      GenerationDiagnostics.instance.runtimeHeartbeat('part.validationBegin');
      await callbacks?.onValidationStarted?.call(
        generationId: generationId,
        resourceId: request.resourceId,
        partId: request.partId,
        taskId: task.taskId,
        attemptId: attemptId,
      );

      try {
        PartGenerationValidator.validate(request: request, response: response);
        GenerationDiagnostics.instance.mark(
          'PART[${task.partId}] VALIDATION_END',
          {'passed': true},
        );
        await callbacks?.onValidationPassed?.call(
          generationId: generationId,
          resourceId: request.resourceId,
          partId: request.partId,
          taskId: task.taskId,
          attemptId: attemptId,
          characterCount: response.content.length,
        );
      } catch (e) {
        GenerationDiagnostics.instance.mark(
          'PART[${task.partId}] VALIDATION_END',
          {'passed': false, 'error': e.toString()},
        );
        await callbacks?.onValidationFailed?.call(
          generationId: generationId,
          resourceId: request.resourceId,
          partId: request.partId,
          taskId: task.taskId,
          attemptId: attemptId,
          errorMessage: _failureCode(e),
        );
        rethrow;
      }

      // A stop requested before this point may abandon the attempt safely.
      // Once onBeforeCommit runs, commit ownership lasts through
      // onPartCommitted so an atomic commit is never split by cancellation.
      if (taskHandle?.isCancelled == true) {
        await convergeCancellation();
        return;
      }

      commitOwned = true;
      GenerationDiagnostics.instance
        ..runtimeHeartbeat('part.beforeCommit')
        ..mark('PART[${task.partId}] BEFORE_COMMIT', {
          'chars': response.content.length,
        });
      await callbacks?.onBeforeCommit?.call(
        generationId: generationId,
        resourceId: request.resourceId,
        partId: request.partId,
        taskId: task.taskId,
        attemptId: attemptId,
      );

      // 6. Atomically commit content, guarded by the source token observed when
      // this attempt started. A user edit since then turns this into a typed
      // stale conflict instead of a silent overwrite.
      GenerationDiagnostics.instance
        ..runtimeHeartbeat('part.dbWriteBegin')
        ..mark('PART[${task.partId}] DB_PART_WRITE_BEGIN');
      final dbWriteWatch = Stopwatch()..start();
      await _taskRepository.commitPartContent(
        response: response,
        taskId: task.taskId,
        attemptId: attemptId,
        expectedSourceToken: attempt.sourceToken,
      );
      dbWriteWatch.stop();
      GenerationDiagnostics.instance
        ..recordDuration('commit.dbPartWrite', dbWriteWatch.elapsed)
        ..mark('PART[${task.partId}] DB_PART_WRITE_END', {
          'elapsed': '${dbWriteWatch.elapsedMilliseconds}ms',
        });

      GenerationDiagnostics.instance.runtimeHeartbeat('part.committed');
      await callbacks?.onPartCommitted?.call(
        generationId: generationId,
        resourceId: request.resourceId,
        partId: request.partId,
        taskId: task.taskId,
        attemptId: attemptId,
        characterCount: response.content.length,
      );
      GenerationDiagnostics.instance
        ..runtimeHeartbeat('part.completedEvent')
        ..mark('PART[${task.partId}] COMMIT_END');
    } catch (e) {
      await _convergeFailedAttempt(
        task: task,
        attemptId: attemptId,
        error: e,
        commitOwned: commitOwned,
        cancelTasksOnCancellation: cancelTasksOnCancellation,
        taskHandle: taskHandle,
      );
      rethrow;
    }
  }

  /// Attempt lifecycle epilogue for any failure after `startAttempt` returned.
  ///
  /// Contract (P0 spin fix): a failed attempt must never leave a lease behind.
  /// Either the task/attempt are converged to a terminal, budget-consuming
  /// state, or cancellation is converged — never "attempt started + task
  /// generating + local Future finished", which the scheduler would recover
  /// into `ready` and re-dispatch without bound.
  ///
  /// [commitOwned] protects an atomic commit: once `onBeforeCommit` has run,
  /// the attempt is no longer abandoned as cancelled (the commit may itself
  /// have landed) and the failure is recorded so the retry budget accounts
  /// for it.
  Future<void> _convergeFailedAttempt({
    required ResourceGenerationTask task,
    required String attemptId,
    required Object error,
    required bool commitOwned,
    required bool cancelTasksOnCancellation,
    required GenerationTaskHandle? taskHandle,
  }) async {
    GenerationDiagnostics.instance.mark(
      'PART[${task.partId}] ATTEMPT_FAILED',
      {'attempt': attemptId, 'commitOwned': commitOwned, 'error': error},
    );
    // `startAttempt` itself threw: no lease exists, so there is nothing to
    // converge here. The dispatch gate owns the budget accounting.
    if (attemptId.isEmpty) return;

    if (taskHandle?.isCancelled == true &&
        !cancelTasksOnCancellation &&
        !commitOwned) {
      await _taskRepository.interruptAttempt(
        taskId: task.taskId,
        attemptId: attemptId,
        reason: 'Generation interrupted by task-handle cancellation',
      );
      return;
    }
    await _taskRepository.recordFailedAttempt(
      taskId: task.taskId,
      attemptId: attemptId,
      errorMessage: _failureCode(error),
    );
  }

  String _stripPrefix(String text, String prefix) {
    if (text.startsWith(prefix)) {
      return text.substring(prefix.length);
    }
    return text;
  }

  String _failureCode(Object error) {
    if (error is PartGenerationParseException ||
        error is GenerationPatchParseException) {
      return 'resourceValidationFailed';
    }
    if (error is PatchSequenceGapException ||
        error is PatchCursorMismatchException) {
      return 'resourceConflict';
    }
    return 'resourceGenerationFailed';
  }
}
