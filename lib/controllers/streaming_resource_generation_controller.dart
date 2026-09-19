import 'dart:async';

import '../application/resources/streaming_generation_session_repository.dart';
import '../application/resources/streaming_resource_generation_service.dart';
import '../domain/resources/streaming_generation_runtime_contracts.dart';
import '../services/llm_service.dart';

/// Controller managing streaming resource generation runtime interactions for UI and clients.
class StreamingResourceGenerationController {
  StreamingResourceGenerationController({
    required StreamingResourceGenerationService service,
    required IStreamingGenerationSessionRepository sessionRepository,
    bool ownsService = true,
  })  : _service = service,
        _sessionRepository = sessionRepository,
        _ownsService = ownsService;

  final StreamingResourceGenerationService _service;
  final IStreamingGenerationSessionRepository _sessionRepository;
  final bool _ownsService;

  /// Stream of generation runtime events for observation.
  Stream<GenerationRuntimeEvent> get events => _service.eventStream;

  /// Creates a new generation runtime session in `created` status.
  Future<StreamingGenerationSession> createSession({
    required String resourceId,
    required String blueprintId,
    String creationSessionId = '',
    String? sessionId,
  }) {
    return _service.createSession(
      resourceId: resourceId,
      blueprintId: blueprintId,
      creationSessionId: creationSessionId,
      sessionId: sessionId,
    );
  }

  /// Starts or advances generation through the full runtime lifecycle.
  Future<bool> start({
    required String sessionId,
    GenerationTaskHandle? taskHandle,
    int maxRetriesPerPart = 2,
  }) {
    return _service.startGeneration(
      sessionId: sessionId,
      taskHandle: taskHandle,
      maxRetriesPerPart: maxRetriesPerPart,
    );
  }

  /// Pauses an active generation session.
  Future<void> pause({
    required String sessionId,
    GenerationTaskHandle? taskHandle,
  }) {
    return _service.pauseGeneration(
      sessionId,
      taskHandle: taskHandle,
    );
  }

  /// Resumes a paused or recovering generation session.
  Future<bool> resume({
    required String sessionId,
    GenerationTaskHandle? taskHandle,
  }) {
    return _service.resumeGeneration(
      sessionId,
      taskHandle: taskHandle,
    );
  }

  /// Cancels generation for [sessionId].
  Future<void> cancel({
    required String sessionId,
    GenerationTaskHandle? taskHandle,
  }) {
    return _service.cancelGeneration(
      sessionId,
      taskHandle: taskHandle,
    );
  }

  /// Retries a single failed Part in [sessionId].
  Future<bool> retryPart({
    required String sessionId,
    required String partId,
    GenerationTaskHandle? taskHandle,
  }) {
    return _service.retryPart(
      sessionId,
      partId,
      taskHandle: taskHandle,
    );
  }

  /// Recovers an interrupted session and its underlying tasks after app restart.
  Future<bool> recover({
    required String sessionId,
    GenerationTaskHandle? taskHandle,
    bool autoResume = true,
  }) {
    return _service.recoverInterruptedGeneration(
      sessionId,
      taskHandle: taskHandle,
      autoResume: autoResume,
    );
  }

  /// Gets the current state of a generation session.
  Future<StreamingGenerationSession?> getSession(String sessionId) {
    return _sessionRepository.findSession(sessionId);
  }

  /// Gets the latest generation session for a resource.
  Future<StreamingGenerationSession?> getLatestSessionForResource(
    String resourceId,
  ) {
    return _sessionRepository.findLatestSessionForResource(resourceId);
  }

  /// Disposes resources.
  void dispose() {
    if (_ownsService) {
      _service.dispose();
    }
  }
}
