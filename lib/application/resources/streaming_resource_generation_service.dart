import 'dart:async';

import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_generation_protocol.dart';
import '../../domain/resources/streaming_generation_runtime_contracts.dart';
import '../../domain/resources/resource_blueprint.dart';
import '../../services/llm_service.dart';
import 'part_generation_coordinator.dart';
import 'resource_blueprint_repository.dart';
import 'resource_creation_pipeline.dart';
import 'resource_generation_task_repository.dart';
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
  })  : _sessionRepository = sessionRepository,
        _taskRepository = taskRepository,
        _blueprintRepository = blueprintRepository,
        _coordinator = coordinator;

  final IStreamingGenerationSessionRepository _sessionRepository;
  final IPartGenerationTaskRepository _taskRepository;
  final IResourceBlueprintRepository _blueprintRepository;
  final PartGenerationCoordinator _coordinator;

  final StreamController<GenerationRuntimeEvent> _eventController =
      StreamController<GenerationRuntimeEvent>.broadcast();
  final Map<String, GenerationTaskHandle> _activeTaskHandles = {};
  final Map<String, Future<bool>> _activeRuns = {};
  final Map<String, StreamingLifecycleStatus> _requestedStops = {};

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
      onPatchReceived: ({
        required generationId,
        required resourceId,
        required partId,
        required taskId,
        required attemptId,
        required patch,
        required accumulatedLength,
      }) async {
        if (activePartStatus == StreamingLifecycleStatus.generatingPart) {
          activePartStatus = StreamingLifecycleStatus.receivingPatch;
          await _sessionRepository.updateStatus(
            sessionId,
            StreamingLifecycleStatus.receivingPatch,
          );
        }

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
          );
        }
      },
    );

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

      final requestedStop = _requestedStops[sessionId] ??
          (taskHandle.isCancelled ? StreamingLifecycleStatus.cancelled : null);
      if (requestedStop != null) {
        await _sessionRepository.updateStatus(
          sessionId,
          requestedStop,
        );
        return false;
      }

      if (success) {
        await _sessionRepository.updateStatus(
          sessionId,
          StreamingLifecycleStatus.completed,
        );

        _emit(GenerationCompleted(
          generationId: sessionId,
          resourceId: session.resourceId,
          totalParts: completedCount,
          totalCharacters: totalCommittedChars,
          timestamp: DateTime.now(),
        ));
        return true;
      } else {
        await _sessionRepository.updateStatus(
          sessionId,
          StreamingLifecycleStatus.failed,
          errorMessage: 'One or more required parts failed generation',
        );

        _emit(GenerationFailed(
          generationId: sessionId,
          resourceId: session.resourceId,
          errorMessage: 'One or more required parts failed generation',
          timestamp: DateTime.now(),
        ));
        return false;
      }
    } catch (e) {
      final requestedStop = _requestedStops[sessionId] ??
          (taskHandle.isCancelled ? StreamingLifecycleStatus.cancelled : null);
      if (requestedStop != null) {
        await _sessionRepository.updateStatus(sessionId, requestedStop);
        return false;
      }
      await _sessionRepository.updateStatus(
        sessionId,
        StreamingLifecycleStatus.failed,
        errorMessage: e.toString(),
      );

      _emit(GenerationFailed(
        generationId: sessionId,
        resourceId: session.resourceId,
        errorMessage: e.toString(),
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
    _requestedStops[sessionId] = StreamingLifecycleStatus.paused;
    final activeTaskHandle = _activeTaskHandles[sessionId] ?? taskHandle;
    await activeTaskHandle?.cancel();
    final activeRun = _activeRuns[sessionId];
    if (activeRun != null) {
      await activeRun;
      return;
    }
    await _sessionRepository.updateStatus(
        sessionId, StreamingLifecycleStatus.paused);
  }

  /// Resumes a paused or recovering generation session.
  Future<bool> resumeGeneration(
    String sessionId, {
    GenerationTaskHandle? taskHandle,
  }) async {
    final session = await _sessionRepository.findSession(sessionId);
    if (session == null) {
      throw StateError('未找到生成会话: $sessionId');
    }

    if (session.status != StreamingLifecycleStatus.paused &&
        session.status != StreamingLifecycleStatus.recovering) {
      throw StateError(
        '仅处于 paused 或 recovering 状态的会话允许恢复，当前状态: ${session.status.storageValue}',
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

  /// Explicitly cancels generation for [sessionId].
  Future<void> cancelGeneration(
    String sessionId, {
    GenerationTaskHandle? taskHandle,
  }) async {
    _requestedStops[sessionId] = StreamingLifecycleStatus.cancelled;
    final activeTaskHandle = _activeTaskHandles[sessionId] ?? taskHandle;
    await activeTaskHandle?.cancel();
    final session = await _sessionRepository.findSession(sessionId);
    if (session != null) {
      await _taskRepository.cancelTasks(
        resourceId: session.resourceId.value,
      );
      final activeRun = _activeRuns[sessionId];
      if (activeRun != null) {
        await activeRun;
      } else {
        await _sessionRepository.updateStatus(
          sessionId,
          StreamingLifecycleStatus.cancelled,
        );
      }
    }
  }

  /// Retries generating a specific failed Part.
  Future<bool> retryPart(
    String sessionId,
    String partId, {
    GenerationTaskHandle? taskHandle,
  }) async {
    final session = await _sessionRepository.findSession(sessionId);
    if (session == null) {
      throw StateError('未找到生成会话: $sessionId');
    }

    await _sessionRepository.updateStatus(
      sessionId,
      StreamingLifecycleStatus.generatingPart,
      currentPartId: partId,
    );

    final success = await _coordinator.retrySinglePart(
      blueprintId: session.blueprintId,
      partId: partId,
      taskHandle: taskHandle,
      callbacks: PartGenerationLifecycleCallbacks(
        onPartStarted: ({
          required generationId,
          required resourceId,
          required partId,
          required taskId,
          required attemptId,
          required attemptNumber,
        }) {
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
      );
      _emit(GenerationCompleted(
        generationId: sessionId,
        resourceId: session.resourceId,
        totalParts: allTasks.length,
        totalCharacters: 0,
        timestamp: DateTime.now(),
      ));
    } else {
      await _sessionRepository.updateStatus(
        sessionId,
        StreamingLifecycleStatus.paused,
      );
    }

    return success;
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

    // 1. Mark session as recovering in database
    await _sessionRepository.markSessionRecovering(sessionId);

    // 2. Recover interrupted tasks in task repository
    await _taskRepository.recoverInterruptedTasks(session.resourceId.value);

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
}
