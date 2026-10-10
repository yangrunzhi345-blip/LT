import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../core/debug/generation_diagnostics.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_generation_protocol.dart';
import '../../domain/resources/streaming_generation_runtime_contracts.dart';
import '../../domain/resources/resource_blueprint.dart';
import '../../services/llm_service.dart';
import 'part_generation_coordinator.dart';
import 'resource_blueprint_repository.dart';
import 'resource_creation_pipeline.dart';
import 'resource_generation_task_repository.dart';
import 'resource_generation_error.dart';
import 'streaming_generation_session_repository.dart';

/// Core application service driving the streaming resource generation runtime lifecycle.
///
/// Orchestrates Blueprint planning, topological DAG task execution, streaming patch reception,
/// validation, atomic database commit, event streaming, and failure recovery.
final class StreamingResourceGenerationService {
  StreamingResourceGenerationService({
    required IStreamingGenerationSessionRepository sessionRepository,
    required IPartGenerationTaskRepository taskRepository,
    required IResourceBlueprintRepository blueprintRepository,
    ResourceCreationPipeline? pipeline,
    required PartGenerationCoordinator coordinator,
    Future<void> Function(ResourceId resourceId)?
        onGenerationCompletedForAssembly,
  })  : _sessionRepository = sessionRepository,
        _taskRepository = taskRepository,
        _blueprintRepository = blueprintRepository,
        _coordinator = coordinator,
        _onGenerationCompletedForAssembly = onGenerationCompletedForAssembly;

  final IStreamingGenerationSessionRepository _sessionRepository;
  final IPartGenerationTaskRepository _taskRepository;
  final IResourceBlueprintRepository _blueprintRepository;
  final PartGenerationCoordinator _coordinator;
  final Future<void> Function(ResourceId resourceId)?
      _onGenerationCompletedForAssembly;

  final StreamController<GenerationRuntimeEvent> _eventController =
      StreamController<GenerationRuntimeEvent>.broadcast();
  final Map<String, GenerationTaskHandle> _activeTaskHandles = {};
  final Map<String, Future<bool>> _activeRuns = {};

  /// In-flight Part-scoped retries, keyed `sessionId::partId`.
  ///
  /// The application-level duplicate guard: at most one active regeneration may
  /// exist per (session, Part), so two rapid triggers can never create two
  /// attempts for the same Part.
  final Set<String> _activeRetryParts = <String>{};
  final Map<String, StreamingLifecycleStatus> _requestedStops = {};

  void _requestStop(
    String sessionId,
    StreamingLifecycleStatus requestedStatus,
  ) {
    if (_requestedStops[sessionId] == StreamingLifecycleStatus.cancelled) {
      return;
    }
    _requestedStops[sessionId] = requestedStatus;
  }

  Future<bool> _convergeRequestedStop({
    required String sessionId,
    required String resourceId,
    required StreamingLifecycleStatus requestedStatus,
  }) async {
    final tasks = await _taskRepository.findTasksForResource(resourceId);
    final allPartsCompleted = tasks.isNotEmpty &&
        tasks.every(
          (task) => task.status == PartTaskStatus.completed.storageValue,
        );
    if (requestedStatus == StreamingLifecycleStatus.paused &&
        allPartsCompleted) {
      await _sessionRepository.updateStatus(
        sessionId,
        StreamingLifecycleStatus.completed,
      );
      return true;
    }

    if (requestedStatus == StreamingLifecycleStatus.paused) {
      await _taskRepository.recoverInterruptedTasks(resourceId);
      final persisted = await _sessionRepository.findSession(sessionId);
      if (persisted?.status == StreamingLifecycleStatus.committing) {
        await _sessionRepository.updateStatus(
          sessionId,
          StreamingLifecycleStatus.recovering,
        );
      }
    } else {
      await _taskRepository.cancelTasks(resourceId: resourceId);
    }
    await _sessionRepository.updateStatus(sessionId, requestedStatus);
    return false;
  }

  /// Converges a requested stop and, when that convergence actually completed
  /// the whole generation (all Parts done), runs assembly readiness once.
  ///
  /// The paused→all-parts-completed path marks the session `completed` without
  /// going through the ordinary success branch; without this hook the resource
  /// would finish generation with no readiness row and stay permanently
  /// "validating". Readiness preparation is idempotent and single-flight.
  Future<bool> _convergeRequestedStopAndPrepare({
    required String sessionId,
    required ResourceId resourceId,
    required StreamingLifecycleStatus requestedStatus,
  }) async {
    final completed = await _convergeRequestedStop(
      sessionId: sessionId,
      resourceId: resourceId.value,
      requestedStatus: requestedStatus,
    );
    if (completed) {
      await _prepareAssemblyAfterCompletion(resourceId);
    }
    return completed;
  }

  /// Runs the single assembly-readiness boundary after a generation reaches
  /// `completed`. Never throws into the generation path: readiness is a
  /// separate authority and a failed preparation stays retryable via the
  /// lifecycle reconciler.
  Future<void> _prepareAssemblyAfterCompletion(ResourceId resourceId) async {
    final prepare = _onGenerationCompletedForAssembly;
    if (prepare == null) return;
    GenerationDiagnostics.instance.mark(
      'ASSEMBLY_PREPARE_BEGIN',
      {'resource': resourceId.value},
    );
    try {
      await prepare(resourceId);
      GenerationDiagnostics.instance.mark(
        'ASSEMBLY_PREPARE_END',
        {'resource': resourceId.value},
      );
    } catch (error) {
      GenerationDiagnostics.instance.mark(
        'ASSEMBLY_PREPARE_FAILED',
        {
          'resource': resourceId.value,
          'exceptionType': error.runtimeType.toString()
        },
      );
    }
  }

  /// Broadcast stream of generation runtime events for UI or observers.
  Stream<GenerationRuntimeEvent> get eventStream => _eventController.stream;

  void _emit(GenerationRuntimeEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  /// Creates and persists a new generation session in `created` state.
  Future<StreamingGenerationSession> createSession({
    required String resourceId,
    required String blueprintId,
    String creationSessionId = '',
    String? sessionId,
  }) async {
    final blueprint = await _blueprintRepository.findBlueprint(blueprintId);
    if (blueprint == null) {
      throw StateError('未找到对应的 Blueprint: $blueprintId');
    }
    if (blueprint.resourceId case final blueprintResourceId?) {
      if (blueprintResourceId.value != resourceId) {
        throw StateError('生成会话资源与 Blueprint 已绑定资源不一致');
      }
    }

    final activeSessionExists = (await _sessionRepository.findActiveSessions())
        .any((session) => session.resourceId.value == resourceId);
    if (activeSessionExists) {
      throw StateError('资源已有未结束的生成会话: $resourceId');
    }

    final now = DateTime.now();
    final effectiveSessionId =
        sessionId ?? 'gen_sess_${DateTime.now().microsecondsSinceEpoch}';

    final tasks = await _taskRepository.findTasksForBlueprint(blueprintId);
    final totalParts = tasks.isNotEmpty ? tasks.length : 0;

    final session = StreamingGenerationSession(
      sessionId: effectiveSessionId,
      resourceId: ResourceId(resourceId),
      blueprintId: blueprintId,
      creationSessionId: creationSessionId,
      status: StreamingLifecycleStatus.created,
      totalPartsCount: totalParts,
      createdAt: now,
      updatedAt: now,
    );

    return _sessionRepository.createSession(session);
  }

  /// Starts or advances generation through the full runtime lifecycle.
  Future<bool> startGeneration({
    required String sessionId,
    GenerationTaskHandle? taskHandle,
    int maxRetriesPerPart = 2,
  }) {
    if (_activeRuns.containsKey(sessionId)) {
      throw StateError('生成会话已在运行: $sessionId');
    }

    final effectiveTaskHandle = taskHandle ??
        GenerationTaskHandle(
          taskId: sessionId,
        );
    _activeTaskHandles[sessionId] = effectiveTaskHandle;
    if (GenerationDiagnostics.enabled) {
      GenerationDiagnostics.instance
        ..startWatchdog()
        ..beginRun('session:$sessionId');
    }
    final run = _runGeneration(
      sessionId: sessionId,
      taskHandle: effectiveTaskHandle,
      maxRetriesPerPart: maxRetriesPerPart,
    );
    _activeRuns[sessionId] = run;
    return run.whenComplete(() {
      if (identical(_activeRuns[sessionId], run)) {
        _activeRuns.remove(sessionId);
        _activeTaskHandles.remove(sessionId);
        _requestedStops.remove(sessionId);
      }
      GenerationDiagnostics.instance
        ..endRun('session:$sessionId')
        ..mark('SESSION[$sessionId] RUN_SETTLED');
    });
  }

  Future<bool> _runGeneration({
    required String sessionId,
    required GenerationTaskHandle taskHandle,
    required int maxRetriesPerPart,
  }) async {
    var session = await _sessionRepository.findSession(sessionId);
    if (session == null) {
      throw StateError('未找到生成运行时会话: $sessionId');
    }

    final blueprint =
        await _blueprintRepository.findBlueprint(session.blueprintId);
    if (blueprint == null) {
      throw StateError('未找到对应的 Blueprint: ${session.blueprintId}');
    }

    // 1. Every new session passes through planning, even if a blueprint was
    // confirmed before the runtime session was created.
    if (session.status == StreamingLifecycleStatus.created) {
      await _sessionRepository.updateStatus(
        sessionId,
        StreamingLifecycleStatus.planning,
      );
      session = await _sessionRepository.findSession(sessionId);
      if (session == null) {
        throw StateError('生成运行时会话在规划期间丢失: $sessionId');
      }
    }

    // Confirm a draft blueprint to create placeholders and tasks.
    if (blueprint.status == BlueprintStatus.draft) {
      final confirmation = await _blueprintRepository.confirmBlueprint(
        blueprintId: session.blueprintId,
        explicitResourceId: session.resourceId,
      );
      if (confirmation.resourceId != session.resourceId) {
        throw StateError('Blueprint 确认后的资源与生成会话资源不一致');
      }

      // Refresh task count from newly created tasks
      final tasks =
          await _taskRepository.findTasksForBlueprint(session.blueprintId);
      await _sessionRepository.updateProgress(
        sessionId,
        completedCount: 0,
        totalCount: tasks.length,
      );

      session = await _sessionRepository.findSession(sessionId);
      if (session == null) {
        throw StateError('生成运行时会话在 Blueprint 确认后丢失: $sessionId');
      }
    }

    // 2. Prepare tasks count
    final allTasks =
        await _taskRepository.findTasksForResource(session.resourceId.value);
    final totalParts = allTasks.length;
    final initialCompleted = allTasks
        .where((t) => t.status == PartTaskStatus.completed.storageValue)
        .length;

    await _sessionRepository.updateProgress(
      sessionId,
      completedCount: initialCompleted,
      totalCount: totalParts,
    );

    // 3. Transition to generatingPart and emit GenerationStarted
    await _sessionRepository.updateStatus(
      sessionId,
      StreamingLifecycleStatus.generatingPart,
    );

    _emit(GenerationStarted(
      generationId: sessionId,
      resourceId: session.resourceId,
      blueprintId: session.blueprintId,
      timestamp: DateTime.now(),
    ));

    var totalCommittedChars = 0;
    var completedCount = initialCompleted;
    var activePartStatus = StreamingLifecycleStatus.generatingPart;

    final callbacks = PartGenerationLifecycleCallbacks(
      onPartStarted: ({
        required generationId,
        required resourceId,
        required partId,
        required taskId,
        required attemptId,
        required attemptNumber,
      }) async {
        GenerationDiagnostics.instance
          ..runtimeHeartbeat('service.partStarted')
          ..mark('SESSION[$sessionId] PART_STARTED', {'part': partId.value});
        activePartStatus = StreamingLifecycleStatus.generatingPart;
        await _sessionRepository.updateStatus(
          sessionId,
          StreamingLifecycleStatus.generatingPart,
          currentPartId: partId.value,
          currentTaskId: taskId,
          currentAttemptId: attemptId,
        );

        _emit(PartStarted(
          generationId: sessionId,
          resourceId: resourceId,
          partId: partId,
          taskId: taskId,
          attemptId: attemptId,
          attemptNumber: attemptNumber,
          timestamp: DateTime.now(),
        ));
      },
      onPartPreviewUpdated: ({
        required generationId,
        required resourceId,
        required partId,
        required taskId,
        required attemptId,
        required accumulatedContent,
        required accumulatedLength,
      }) async {
        GenerationDiagnostics.instance
          ..runtimeHeartbeat('service.previewUpdated')
          ..counter('service.previewEvents');
        if (activePartStatus == StreamingLifecycleStatus.generatingPart) {
          activePartStatus = StreamingLifecycleStatus.receivingPatch;
          await _sessionRepository.updateStatus(
            sessionId,
            StreamingLifecycleStatus.receivingPatch,
          );
        }

        // Presentation-plane snapshot, throttled by the coordinator. Not the
        // content authority: the validated accumulator + DB commit are.
        _emit(PartPreviewUpdated(
          generationId: sessionId,
          resourceId: resourceId,
          partId: partId,
          taskId: taskId,
          attemptId: attemptId,
          accumulatedContent: accumulatedContent,
          accumulatedLength: accumulatedLength,
          timestamp: DateTime.now(),
        ));
      },
      onValidationStarted: ({
        required generationId,
        required resourceId,
        required partId,
        required taskId,
        required attemptId,
      }) async {
        activePartStatus = StreamingLifecycleStatus.validating;
        await _sessionRepository.updateStatus(
          sessionId,
          StreamingLifecycleStatus.validating,
        );

        _emit(ValidationStarted(
          generationId: sessionId,
          resourceId: resourceId,
          partId: partId,
          taskId: taskId,
          attemptId: attemptId,
          timestamp: DateTime.now(),
        ));
      },
      onValidationPassed: ({
        required generationId,
        required resourceId,
        required partId,
        required taskId,
        required attemptId,
        required characterCount,
      }) {
        _emit(ValidationPassed(
          generationId: sessionId,
          resourceId: resourceId,
          partId: partId,
          taskId: taskId,
          attemptId: attemptId,
          characterCount: characterCount,
          timestamp: DateTime.now(),
        ));
      },
      onValidationFailed: ({
        required generationId,
        required resourceId,
        required partId,
        required taskId,
        required attemptId,
        required errorMessage,
      }) {
        _emit(ValidationFailed(
          generationId: sessionId,
          resourceId: resourceId,
          partId: partId,
          taskId: taskId,
          attemptId: attemptId,
          errorMessage: errorMessage,
          error: resourceGenerationErrorFromCode(errorMessage),
          timestamp: DateTime.now(),
        ));
      },
      onBeforeCommit: ({
        required generationId,
        required resourceId,
        required partId,
        required taskId,
        required attemptId,
      }) async {
        activePartStatus = StreamingLifecycleStatus.committing;
        await _sessionRepository.updateStatus(
          sessionId,
          StreamingLifecycleStatus.committing,
        );
      },
      onPartCommitted: ({
        required generationId,
        required resourceId,
        required partId,
        required taskId,
        required attemptId,
        required characterCount,
      }) async {
        GenerationDiagnostics.instance
          ..runtimeHeartbeat('service.partCommitted')
          ..mark('SESSION[$sessionId] PART_COMPLETED_EVENT', {
            'part': partId.value,
            'chars': characterCount,
          });
        totalCommittedChars += characterCount;
        completedCount++;

        await _sessionRepository.updateProgress(
          sessionId,
          completedCount: completedCount,
          totalCount: totalParts,
        );

        _emit(PartCompleted(
          generationId: sessionId,
          resourceId: resourceId,
          partId: partId,
          taskId: taskId,
          attemptId: attemptId,
          characterCount: characterCount,
          timestamp: DateTime.now(),
        ));

        if (completedCount < totalParts) {
          activePartStatus = StreamingLifecycleStatus.generatingPart;
          await _sessionRepository.updateStatus(
            sessionId,
            StreamingLifecycleStatus.generatingPart,
            clearActiveTask: true,
          );
        }
      },
    );

    var failureStage = ResourceGenerationFailureStage.unknown;
    try {
      final success = await _coordinator.generateAllParts(
        blueprintId: session.blueprintId,
        taskHandle: taskHandle,
        operationId: sessionId,
        maxRetriesPerPart: maxRetriesPerPart,
        maxConcurrentParts: 1,
        cancelTasksOnCancellation: false,
        callbacks: callbacks,
      );

      failureStage = ResourceGenerationFailureStage.lifecycle;
      final requestedStop = _requestedStops[sessionId] ??
          (taskHandle.isCancelled ? StreamingLifecycleStatus.cancelled : null);
      if (requestedStop != null) {
        final completed = await _convergeRequestedStopAndPrepare(
          sessionId: sessionId,
          resourceId: session.resourceId,
          requestedStatus: requestedStop,
        );
        if (completed) {
          _emit(GenerationCompleted(
            generationId: sessionId,
            resourceId: session.resourceId,
            totalParts: completedCount,
            totalCharacters: totalCommittedChars,
            timestamp: DateTime.now(),
          ));
        }
        return completed;
      }

      if (success) {
        await _sessionRepository.updateStatus(
          sessionId,
          StreamingLifecycleStatus.completed,
          errorMessage: '',
          clearActiveTask: true,
        );

        // Generation and assembly readiness are separate authorities. The
        // completed session is durable before readiness is attempted; a
        // readiness failure must never rewrite successful generation state.
        await _prepareAssemblyAfterCompletion(session.resourceId);

        GenerationDiagnostics.instance
          ..runtimeHeartbeat('service.generationCompleted')
          ..mark('SESSION[$sessionId] GENERATION_COMPLETED_EVENT');
        _emit(GenerationCompleted(
          generationId: sessionId,
          resourceId: session.resourceId,
          totalParts: completedCount,
          totalCharacters: totalCommittedChars,
          timestamp: DateTime.now(),
        ));
        return true;
      } else {
        final failure = await _failedTask(session.resourceId.value);
        final failedPartId = failure == null ? null : PartId(failure.partId);
        final failureError =
            resourceGenerationErrorFromCode(failure?.errorMessage ?? 'unknown');
        await _sessionRepository.updateStatus(
          sessionId,
          StreamingLifecycleStatus.failed,
          errorMessage: failureError.code.name,
          clearActiveTask: failedPartId == null,
        );

        _emit(GenerationFailed(
          generationId: sessionId,
          resourceId: session.resourceId,
          errorMessage: failureError.code.name,
          error: failureError,
          failedPartId: failedPartId,
          timestamp: DateTime.now(),
        ));
        return false;
      }
    } catch (e) {
      final requestedStop = _requestedStops[sessionId] ??
          (taskHandle.isCancelled ? StreamingLifecycleStatus.cancelled : null);
      if (requestedStop != null) {
        final persisted = await _sessionRepository.findSession(sessionId);
        if (persisted?.status != StreamingLifecycleStatus.committing) {
          return _convergeRequestedStopAndPrepare(
            sessionId: sessionId,
            resourceId: session.resourceId,
            requestedStatus: requestedStop,
          );
        }
      }
      final failureError = resourceGenerationError(e, stage: failureStage);
      final errorMessage = failureError.code.name;
      await _sessionRepository.updateStatus(
        sessionId,
        StreamingLifecycleStatus.failed,
        errorMessage: errorMessage,
      );

      _emit(GenerationFailed(
        generationId: sessionId,
        resourceId: session.resourceId,
        errorMessage: errorMessage,
        error: failureError,
        failedPartId: await _failedPartId(session.resourceId.value),
        timestamp: DateTime.now(),
      ));
      rethrow;
    }
  }

  /// Pauses an in-flight generation session.
  Future<void> pauseGeneration(
    String sessionId, {
    GenerationTaskHandle? taskHandle,
  }) async {
    _requestStop(sessionId, StreamingLifecycleStatus.paused);
    final activeTaskHandle = _activeTaskHandles[sessionId] ?? taskHandle;
    await activeTaskHandle?.cancel();
    final activeRun = _activeRuns[sessionId];
    if (activeRun != null) {
      await activeRun;
      return;
    }
    try {
      final session = await _sessionRepository.findSession(sessionId);
      if (session == null) {
        throw StateError('未找到生成会话: $sessionId');
      }
      if (session.status == StreamingLifecycleStatus.paused ||
          session.status.isTerminal) {
        return;
      }
      final completed = await _convergeRequestedStopAndPrepare(
        sessionId: sessionId,
        resourceId: session.resourceId,
        requestedStatus: StreamingLifecycleStatus.paused,
      );
      if (completed) {
        GenerationDiagnostics.instance.mark(
          'SESSION[$sessionId] GENERATION_COMPLETED_EVENT',
          {'resource': session.resourceId.value, 'via': 'pauseConverged'},
        );
      }
    } finally {
      _requestedStops.remove(sessionId);
    }
  }

  /// Resumes a paused, recovering, or failed generation session.
  Future<bool> resumeGeneration(
    String sessionId, {
    GenerationTaskHandle? taskHandle,
  }) async {
    final activeRun = _activeRuns[sessionId];
    if (activeRun != null &&
        _requestedStops[sessionId] == StreamingLifecycleStatus.paused) {
      await activeRun;
    }
    final session = await _sessionRepository.findSession(sessionId);
    if (session == null) {
      throw StateError('未找到生成会话: $sessionId');
    }

    if (session.status != StreamingLifecycleStatus.paused &&
        session.status != StreamingLifecycleStatus.recovering &&
        session.status != StreamingLifecycleStatus.failed) {
      throw StateError(
        '仅处于 paused、recovering 或 failed 状态的会话允许恢复，'
        '当前状态: ${session.status.storageValue}',
      );
    }

    // Recover any tasks that were left in generating/validating state
    await _taskRepository.recoverInterruptedTasks(session.resourceId.value);
    _requestedStops.remove(sessionId);

    return startGeneration(
      sessionId: sessionId,
      taskHandle: taskHandle,
    );
  }

  Future<ResourceGenerationTask?> _failedTask(String resourceId) async {
    final tasks = await _taskRepository.findTasksForResource(resourceId);
    for (final task in tasks) {
      if (task.status == PartTaskStatus.failed.storageValue) return task;
    }
    return null;
  }

  Future<PartId?> _failedPartId(String resourceId) async {
    final task = await _failedTask(resourceId);
    return task == null ? null : PartId(task.partId);
  }

  /// Explicitly cancels generation for [sessionId].
  Future<void> cancelGeneration(
    String sessionId, {
    GenerationTaskHandle? taskHandle,
  }) async {
    _requestStop(sessionId, StreamingLifecycleStatus.cancelled);
    final activeTaskHandle = _activeTaskHandles[sessionId] ?? taskHandle;
    await activeTaskHandle?.cancel();
    final activeRun = _activeRuns[sessionId];
    if (activeRun != null) {
      await activeRun;
      return;
    }

    try {
      final session = await _sessionRepository.findSession(sessionId);
      if (session != null) {
        await _taskRepository.cancelTasks(
          resourceId: session.resourceId.value,
        );
        await _sessionRepository.updateStatus(
          sessionId,
          StreamingLifecycleStatus.cancelled,
        );
      }
    } finally {
      _requestedStops.remove(sessionId);
    }
  }

  /// Reads the persisted per-Part generation task status for [resourceId].
  ///
  /// Read-only projection so the Studio can offer a retry that targets only the
  /// Parts that actually failed. The task rows remain the single authority —
  /// no parallel status store is introduced.
  Future<Map<String, PartTaskStatus>> listPartTaskStatuses(
    String resourceId,
  ) async {
    final tasks = await _taskRepository.findTasksForResource(resourceId);
    return <String, PartTaskStatus>{
      for (final task in tasks)
        task.partId: PartTaskStatus.fromStorage(task.status),
    };
  }

  /// Retries generating a specific failed Part.
  ///
  /// Duplicate protection is enforced here, not only by UI disabling: at most
  /// one active regeneration may exist per (session, Part). The in-flight retry
  /// is registered synchronously, so a second concurrent trigger is rejected
  /// before it can touch the session or create an attempt. The task `ready`
  /// lease inside the coordinator is the second, persistent guard.
  Future<bool> retryPart(
    String sessionId,
    String partId, {
    GenerationTaskHandle? taskHandle,
    String userInstruction = '',
  }) {
    // A full run in flight is the max-concurrency owner; a Part-scoped retry
    // must never interleave with it (max concurrency stays 1).
    if (_activeRuns.containsKey(sessionId)) {
      throw StateError('生成会话正在运行，禁止并发重试: $sessionId');
    }
    final retryKey = '$sessionId::$partId';
    if (!_activeRetryParts.add(retryKey)) {
      throw StateError('该 Part 正在重新生成，禁止重复触发: $partId');
    }
    return _retryPartOnce(
      sessionId,
      partId,
      taskHandle: taskHandle,
      userInstruction: userInstruction,
    ).whenComplete(() => _activeRetryParts.remove(retryKey));
  }

  Future<bool> _retryPartOnce(
    String sessionId,
    String partId, {
    GenerationTaskHandle? taskHandle,
    String userInstruction = '',
  }) async {
    final session = await _sessionRepository.findSession(sessionId);
    if (session == null) {
      throw StateError('未找到生成会话: $sessionId');
    }

    // Promote dependency-satisfied pending tasks before validating the
    // part-scoped retry target. Unmet pending tasks remain fail-closed.
    await _taskRepository.findReadyTasks(session.resourceId.value);
    final task = await _taskRepository.findTaskByPartId(partId);
    if (task == null) {
      throw StateError('未找到对应的 Part 生成任务: $partId');
    }
    final taskStatus = PartTaskStatus.fromStorage(task.status);
    if (taskStatus == PartTaskStatus.completed) {
      throw StateError('任务已完成，禁止重新发起生成：${task.taskId}');
    }
    if (taskStatus != PartTaskStatus.failed &&
        taskStatus != PartTaskStatus.ready) {
      throw StateError(
        '仅 failed 或 ready 任务允许重试，当前状态: ${task.status}',
      );
    }

    String? retryAttemptId;
    var failureStage = ResourceGenerationFailureStage.lifecycle;
    try {
      await _sessionRepository.updateStatus(
        sessionId,
        StreamingLifecycleStatus.generatingPart,
        currentPartId: partId,
      );

      failureStage = ResourceGenerationFailureStage.unknown;
      final success = await _coordinator.retrySinglePart(
        blueprintId: session.blueprintId,
        partId: partId,
        taskHandle: taskHandle,
        userInstruction: userInstruction,
        callbacks: PartGenerationLifecycleCallbacks(
          onPartStarted: ({
            required generationId,
            required resourceId,
            required partId,
            required taskId,
            required attemptId,
            required attemptNumber,
          }) {
            retryAttemptId = attemptId;
            _emit(PartStarted(
              generationId: sessionId,
              resourceId: resourceId,
              partId: partId,
              taskId: taskId,
              attemptId: attemptId,
              attemptNumber: attemptNumber,
              timestamp: DateTime.now(),
            ));
          },
          onPatchReceived: ({
            required generationId,
            required resourceId,
            required partId,
            required taskId,
            required attemptId,
            required patch,
            required accumulatedLength,
          }) async {
            _emit(PatchReceived(
              generationId: sessionId,
              resourceId: resourceId,
              partId: partId,
              taskId: taskId,
              attemptId: attemptId,
              patch: patch,
              accumulatedLength: accumulatedLength,
              timestamp: DateTime.now(),
            ));
          },
          onValidationStarted: ({
            required generationId,
            required resourceId,
            required partId,
            required taskId,
            required attemptId,
          }) async {
            await _sessionRepository.updateStatus(
              sessionId,
              StreamingLifecycleStatus.validating,
            );

            _emit(ValidationStarted(
              generationId: sessionId,
              resourceId: resourceId,
              partId: partId,
              taskId: taskId,
              attemptId: attemptId,
              timestamp: DateTime.now(),
            ));
          },
          onValidationPassed: ({
            required generationId,
            required resourceId,
            required partId,
            required taskId,
            required attemptId,
            required characterCount,
          }) {
            _emit(ValidationPassed(
              generationId: sessionId,
              resourceId: resourceId,
              partId: partId,
              taskId: taskId,
              attemptId: attemptId,
              characterCount: characterCount,
              timestamp: DateTime.now(),
            ));
          },
          onValidationFailed: ({
            required generationId,
            required resourceId,
            required partId,
            required taskId,
            required attemptId,
            required errorMessage,
          }) {
            _emit(ValidationFailed(
              generationId: sessionId,
              resourceId: resourceId,
              partId: partId,
              taskId: taskId,
              attemptId: attemptId,
              errorMessage: errorMessage,
              error: resourceGenerationErrorFromCode(errorMessage),
              timestamp: DateTime.now(),
            ));
          },
          onBeforeCommit: ({
            required generationId,
            required resourceId,
            required partId,
            required taskId,
            required attemptId,
          }) async {
            await _sessionRepository.updateStatus(
              sessionId,
              StreamingLifecycleStatus.committing,
            );
          },
          onPartCommitted: ({
            required generationId,
            required resourceId,
            required partId,
            required taskId,
            required attemptId,
            required characterCount,
          }) {
            _emit(PartCompleted(
              generationId: sessionId,
              resourceId: resourceId,
              partId: partId,
              taskId: taskId,
              attemptId: attemptId,
              characterCount: characterCount,
              timestamp: DateTime.now(),
            ));
          },
        ),
      );

      failureStage = ResourceGenerationFailureStage.lifecycle;
      // Refresh completed parts count
      final allTasks =
          await _taskRepository.findTasksForResource(session.resourceId.value);
      final completedCount = allTasks
          .where((t) => t.status == PartTaskStatus.completed.storageValue)
          .length;
      await _sessionRepository.updateProgress(
        sessionId,
        completedCount: completedCount,
        totalCount: allTasks.length,
      );

      if (allTasks
          .every((t) => t.status == PartTaskStatus.completed.storageValue)) {
        await _sessionRepository.updateStatus(
          sessionId,
          StreamingLifecycleStatus.completed,
          errorMessage: '',
          clearActiveTask: true,
        );
        await _prepareAssemblyAfterCompletion(session.resourceId);
        _emit(GenerationCompleted(
          generationId: sessionId,
          resourceId: session.resourceId,
          totalParts: allTasks.length,
          totalCharacters: 0,
          timestamp: DateTime.now(),
        ));
      } else {
        // A successful commit leaves the session in `committing`; leave that
        // state through its one legal backward edge before parking the run, so
        // a retry that does not finish every Part still settles as paused.
        final current = await _sessionRepository.findSession(sessionId);
        if (current?.status == StreamingLifecycleStatus.committing) {
          await _sessionRepository.updateStatus(
            sessionId,
            StreamingLifecycleStatus.generatingPart,
            clearActiveTask: true,
          );
        }
        final remainingFailure = await _failedTask(session.resourceId.value);
        await _sessionRepository.updateStatus(
          sessionId,
          StreamingLifecycleStatus.paused,
          errorMessage: remainingFailure == null
              ? ''
              : resourceGenerationErrorFromCode(remainingFailure.errorMessage)
                  .code
                  .name,
          clearActiveTask: true,
        );
      }

      return success;
    } catch (error) {
      await _convergeAfterRegenerationFailure(
        session: session,
        partId: partId,
        error: error,
        failureStage: failureStage,
        retryAttemptId: retryAttemptId,
      );
      return false;
    }
  }

  Future<void> _convergeAfterRegenerationFailure({
    required StreamingGenerationSession session,
    required String partId,
    required Object error,
    required String? retryAttemptId,
    required ResourceGenerationFailureStage failureStage,
  }) async {
    // Use only the failure owned by this retry, never an earlier attempt.
    final task = await _taskRepository.findTaskByPartId(partId);
    final failureError = task != null &&
            task.status == PartTaskStatus.failed.storageValue &&
            retryAttemptId != null &&
            task.currentAttemptId == retryAttemptId
        ? resourceGenerationErrorFromCode(task.errorMessage)
        : resourceGenerationError(error, stage: failureStage);
    final errorMessage = failureError.code.name;
    final current = await _sessionRepository.findSession(session.sessionId);
    if (current != null &&
        StreamingLifecycleStateMachine.canTransition(
          current.status,
          StreamingLifecycleStatus.failed,
        )) {
      await _sessionRepository.updateStatus(
        session.sessionId,
        StreamingLifecycleStatus.failed,
        errorMessage: errorMessage,
      );
    }

    _emit(GenerationFailed(
      generationId: session.sessionId,
      resourceId: session.resourceId,
      errorMessage: errorMessage,
      error: failureError,
      failedPartId: PartId(partId),
      timestamp: DateTime.now(),
    ));
  }

  /// Recovers an interrupted generation session and its underlying tasks after app restart.
  Future<bool> recoverInterruptedGeneration(
    String sessionId, {
    GenerationTaskHandle? taskHandle,
    bool autoResume = true,
  }) async {
    final session = await _sessionRepository.findSession(sessionId);
    if (session == null) {
      throw StateError('未找到生成会话: $sessionId');
    }

    // Recover tasks first so a repository failure leaves the session in its
    // original interrupted state for a later startup attempt.
    await _taskRepository.recoverInterruptedTasks(session.resourceId.value);

    await _sessionRepository.markSessionRecovering(sessionId);

    // 3. Resume if requested
    if (autoResume) {
      return resumeGeneration(sessionId, taskHandle: taskHandle);
    }
    return true;
  }

  /// Closes the event stream controller.
  void dispose() {
    _eventController.close();
  }

  /// Test/observability seam: number of generation runs still in flight.
  @visibleForTesting
  int get activeRunCount => _activeRuns.length;

  /// Test/observability seam: task handles not yet cleaned up.
  @visibleForTesting
  int get activeTaskHandleCount => _activeTaskHandles.length;

  /// Test/observability seam: pending stop requests not yet consumed.
  @visibleForTesting
  int get pendingStopCount => _requestedStops.length;
}
