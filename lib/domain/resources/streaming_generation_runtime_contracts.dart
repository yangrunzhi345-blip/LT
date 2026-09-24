import 'resource_contracts.dart';
import 'resource_generation_patch.dart';
import '../errors/app_error.dart';

/// Explicit lifecycle states of the streaming resource generation runtime.
enum StreamingLifecycleStatus {
  /// Generation session created, not yet started.
  created('created'),

  /// Planning outline/blueprint or preparing tasks.
  planning('planning'),

  /// Currently generating a specific Part via the language model.
  generatingPart('generating_part'),

  /// Streaming incremental patches are arriving from the LLM.
  receivingPatch('receiving_patch'),

  /// Part patch stream finished; performing structural & semantic validation.
  validating('validating'),

  /// Validated content is being committed atomically to the resource tree.
  committing('committing'),

  /// All Parts have been generated, validated, and committed successfully.
  completed('completed'),

  /// Generation encountered an unrecoverable failure.
  failed('failed'),

  /// Generation has been paused by the user or controller.
  paused('paused'),

  /// Generation has been explicitly cancelled.
  cancelled('cancelled'),

  /// Session is being recovered from a previous interrupted state.
  recovering('recovering');

  const StreamingLifecycleStatus(this.storageValue);

  final String storageValue;

  static StreamingLifecycleStatus fromStorage(String? value) {
    for (final status in StreamingLifecycleStatus.values) {
      if (status.storageValue == value) return status;
    }
    return StreamingLifecycleStatus.created;
  }

  bool get isTerminal =>
      this == StreamingLifecycleStatus.completed ||
      this == StreamingLifecycleStatus.cancelled;

  bool get isInFlight =>
      this == StreamingLifecycleStatus.planning ||
      this == StreamingLifecycleStatus.generatingPart ||
      this == StreamingLifecycleStatus.receivingPatch ||
      this == StreamingLifecycleStatus.validating ||
      this == StreamingLifecycleStatus.committing;
}

/// State machine governing explicit transitions across generation runtime lifecycle states.
abstract final class StreamingLifecycleStateMachine {
  static const Map<StreamingLifecycleStatus, Set<StreamingLifecycleStatus>>
      _allowedTransitions = {
    StreamingLifecycleStatus.created: {
      StreamingLifecycleStatus.created,
      StreamingLifecycleStatus.planning,
      StreamingLifecycleStatus.recovering,
      StreamingLifecycleStatus.cancelled,
      StreamingLifecycleStatus.paused,
    },
    StreamingLifecycleStatus.planning: {
      StreamingLifecycleStatus.planning,
      StreamingLifecycleStatus.generatingPart,
      StreamingLifecycleStatus.failed,
      StreamingLifecycleStatus.cancelled,
      StreamingLifecycleStatus.paused,
      StreamingLifecycleStatus.recovering,
    },
    StreamingLifecycleStatus.generatingPart: {
      StreamingLifecycleStatus.generatingPart,
      StreamingLifecycleStatus.receivingPatch,
      StreamingLifecycleStatus.validating,
      StreamingLifecycleStatus.failed,
      StreamingLifecycleStatus.cancelled,
      StreamingLifecycleStatus.paused,
      StreamingLifecycleStatus.recovering,
    },
    StreamingLifecycleStatus.receivingPatch: {
      StreamingLifecycleStatus.receivingPatch,
      StreamingLifecycleStatus.generatingPart,
      StreamingLifecycleStatus.validating,
      StreamingLifecycleStatus.failed,
      StreamingLifecycleStatus.cancelled,
      StreamingLifecycleStatus.paused,
      StreamingLifecycleStatus.recovering,
    },
    StreamingLifecycleStatus.validating: {
      StreamingLifecycleStatus.validating,
      StreamingLifecycleStatus.committing,
      // Backward edge for the AUTOMATIC RETRY of a failed Part.
      //
      // A Part that fails validation (malformed NDJSON, structural or
      // semantic rejection) leaves this session in `validating`: the failure
      // callback runs before any commit. The coordinator then reopens the
      // task and starts another attempt for the SAME Part, whose
      // `onPartStarted` reports a session that is re-entering generation.
      //
      // Without this edge that callback throws, the attempt aborts before its
      // HTTP request, and the scheduler spins. It is deliberately the ONLY
      // backward edge into `generatingPart` and it does not weaken any other
      // guard: the success path still goes validating -> committing ->
      // generatingPart (next Part) or -> completed.
      StreamingLifecycleStatus.generatingPart,
      StreamingLifecycleStatus.failed,
      StreamingLifecycleStatus.cancelled,
      StreamingLifecycleStatus.paused,
      StreamingLifecycleStatus.recovering,
    },
    StreamingLifecycleStatus.committing: {
      StreamingLifecycleStatus.committing,
      StreamingLifecycleStatus.generatingPart,
      StreamingLifecycleStatus.completed,
      StreamingLifecycleStatus.failed,
      StreamingLifecycleStatus.cancelled,
      StreamingLifecycleStatus.recovering,
    },
    StreamingLifecycleStatus.completed: {
      StreamingLifecycleStatus.completed,
      StreamingLifecycleStatus.generatingPart,
    },
    StreamingLifecycleStatus.failed: {
      StreamingLifecycleStatus.failed,
      StreamingLifecycleStatus.recovering,
      StreamingLifecycleStatus.generatingPart,
      StreamingLifecycleStatus.planning,
      StreamingLifecycleStatus.cancelled,
    },
    StreamingLifecycleStatus.paused: {
      StreamingLifecycleStatus.paused,
      StreamingLifecycleStatus.generatingPart,
      StreamingLifecycleStatus.planning,
      StreamingLifecycleStatus.cancelled,
    },
    StreamingLifecycleStatus.cancelled: {
      StreamingLifecycleStatus.cancelled,
      StreamingLifecycleStatus.recovering,
      StreamingLifecycleStatus.generatingPart,
      StreamingLifecycleStatus.planning,
    },
    StreamingLifecycleStatus.recovering: {
      StreamingLifecycleStatus.recovering,
      StreamingLifecycleStatus.generatingPart,
      StreamingLifecycleStatus.planning,
      StreamingLifecycleStatus.failed,
      StreamingLifecycleStatus.cancelled,
      StreamingLifecycleStatus.paused,
    },
  };

  static bool canTransition(
    StreamingLifecycleStatus from,
    StreamingLifecycleStatus to,
  ) {
    return _allowedTransitions[from]?.contains(to) ?? false;
  }

  static StreamingLifecycleStatus advance(
    StreamingLifecycleStatus from,
    StreamingLifecycleStatus to,
  ) {
    if (!canTransition(from, to)) {
      throw StateError(
        'Invalid StreamingLifecycleStatus transition: '
        '${from.storageValue} -> ${to.storageValue}',
      );
    }
    return to;
  }
}

/// Sealed base class for typed runtime generation events.
///
/// Observers (UI, Riverpod providers, analytics) can listen to the event stream
/// without coupling directly to Flutter widgets or persistence layers.
sealed class GenerationRuntimeEvent {
  const GenerationRuntimeEvent({
    required this.generationId,
    required this.resourceId,
    required this.timestamp,
  });

  final String generationId;
  final ResourceId resourceId;
  final DateTime timestamp;
}

/// Emitted when overall resource generation begins.
final class GenerationStarted extends GenerationRuntimeEvent {
  const GenerationStarted({
    required super.generationId,
    required super.resourceId,
    required this.blueprintId,
    required super.timestamp,
  });

  final String blueprintId;

  @override
  String toString() =>
      'GenerationStarted(gen: $generationId, res: ${resourceId.value}, bp: $blueprintId)';
}

/// Emitted when generation for a specific Part task begins.
final class PartStarted extends GenerationRuntimeEvent {
  const PartStarted({
    required super.generationId,
    required super.resourceId,
    required this.partId,
    required this.taskId,
    required this.attemptId,
    required this.attemptNumber,
    required super.timestamp,
  });

  final PartId partId;
  final String taskId;
  final String attemptId;
  final int attemptNumber;

  @override
  String toString() =>
      'PartStarted(part: ${partId.value}, task: $taskId, attempt: $attemptId #$attemptNumber)';
}

/// Emitted whenever an incremental patch is received for a Part.
final class PatchReceived extends GenerationRuntimeEvent {
  const PatchReceived({
    required super.generationId,
    required super.resourceId,
    required this.partId,
    required this.taskId,
    required this.attemptId,
    required this.patch,
    required this.accumulatedLength,
    required super.timestamp,
  });

  final PartId partId;
  final String taskId;
  final String attemptId;
  final ResourceGenerationPatch patch;
  final int accumulatedLength;

  @override
  String toString() =>
      'PatchReceived(part: ${partId.value}, op: ${patch.op.wireValue}, '
      'seq: ${patch.sequence}, cursor: ${patch.cursor}, accLen: $accumulatedLength)';
}

/// Throttled presentation-plane snapshot of one Part's accumulated preview.
///
/// Emitted at most every ~150ms per Part (plus a final flush before
/// validation/commit) by the streaming runtime. This replaces the former
/// one-[PatchReceived]-per-protocol-patch firehose on the continuous DAG
/// path: the UI preview is NOT the content authority — the validated
/// accumulator plus the DB commit remain authoritative.
final class PartPreviewUpdated extends GenerationRuntimeEvent {
  const PartPreviewUpdated({
    required super.generationId,
    required super.resourceId,
    required this.partId,
    required this.taskId,
    required this.attemptId,
    required this.accumulatedContent,
    required this.accumulatedLength,
    required super.timestamp,
  });

  final PartId partId;
  final String taskId;
  final String attemptId;

  /// Full accumulated preview text of the Part at emission time.
  final String accumulatedContent;
  final int accumulatedLength;

  @override
  String toString() =>
      'PartPreviewUpdated(part: ${partId.value}, len: $accumulatedLength)';
}

/// Emitted when validation begins for accumulated Part content.
final class ValidationStarted extends GenerationRuntimeEvent {
  const ValidationStarted({
    required super.generationId,
    required super.resourceId,
    required this.partId,
    required this.taskId,
    required this.attemptId,
    required super.timestamp,
  });

  final PartId partId;
  final String taskId;
  final String attemptId;

  @override
  String toString() =>
      'ValidationStarted(part: ${partId.value}, attempt: $attemptId)';
}

/// Emitted when Part content passes all structural and semantic validation rules.
final class ValidationPassed extends GenerationRuntimeEvent {
  const ValidationPassed({
    required super.generationId,
    required super.resourceId,
    required this.partId,
    required this.taskId,
    required this.attemptId,
    required this.characterCount,
    required super.timestamp,
  });

  final PartId partId;
  final String taskId;
  final String attemptId;
  final int characterCount;

  @override
  String toString() =>
      'ValidationPassed(part: ${partId.value}, chars: $characterCount)';
}

/// Emitted when Part content fails validation rules.
final class ValidationFailed extends GenerationRuntimeEvent {
  const ValidationFailed({
    required super.generationId,
    required super.resourceId,
    required this.partId,
    required this.taskId,
    required this.attemptId,
    required this.errorMessage,
    this.error,
    required super.timestamp,
  });

  final PartId partId;
  final String taskId;
  final String attemptId;
  final String errorMessage;
  final AppDomainError? error;

  @override
  String toString() =>
      'ValidationFailed(part: ${partId.value}, error: $errorMessage)';
}

/// Emitted when a Part has been validated and atomically committed to the content tree.
final class PartCompleted extends GenerationRuntimeEvent {
  const PartCompleted({
    required super.generationId,
    required super.resourceId,
    required this.partId,
    required this.taskId,
    required this.attemptId,
    required this.characterCount,
    required super.timestamp,
  });

  final PartId partId;
  final String taskId;
  final String attemptId;
  final int characterCount;

  @override
  String toString() =>
      'PartCompleted(part: ${partId.value}, chars: $characterCount)';
}

/// Emitted when all Parts in the resource generation have succeeded.
final class GenerationCompleted extends GenerationRuntimeEvent {
  const GenerationCompleted({
    required super.generationId,
    required super.resourceId,
    required this.totalParts,
    required this.totalCharacters,
    required super.timestamp,
  });

  final int totalParts;
  final int totalCharacters;

  @override
  String toString() =>
      'GenerationCompleted(res: ${resourceId.value}, parts: $totalParts, chars: $totalCharacters)';
}

/// Emitted when overall resource generation fails or aborts.
final class GenerationFailed extends GenerationRuntimeEvent {
  const GenerationFailed({
    required super.generationId,
    required super.resourceId,
    required this.errorMessage,
    required super.timestamp,
    this.failedPartId,
    this.error,
  });

  final String errorMessage;
  final AppDomainError? error;
  final PartId? failedPartId;

  @override
  String toString() =>
      'GenerationFailed(res: ${resourceId.value}, error: $errorMessage, part: ${failedPartId?.value})';
}

/// Pure domain value object representing a persistent streaming generation session.
final class StreamingGenerationSession {
  const StreamingGenerationSession({
    required this.sessionId,
    required this.resourceId,
    required this.blueprintId,
    this.creationSessionId = '',
    required this.status,
    this.currentPartId,
    this.currentTaskId,
    this.currentAttemptId,
    this.completedPartsCount = 0,
    this.totalPartsCount = 0,
    this.errorMessage = '',
    required this.createdAt,
    required this.updatedAt,
  });

  final String sessionId;
  final ResourceId resourceId;
  final String blueprintId;
  final String creationSessionId;
  final StreamingLifecycleStatus status;
  final PartId? currentPartId;
  final String? currentTaskId;
  final String? currentAttemptId;
  final int completedPartsCount;
  final int totalPartsCount;
  final String errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;

  StreamingGenerationSession copyWith({
    String? sessionId,
    ResourceId? resourceId,
    String? blueprintId,
    String? creationSessionId,
    StreamingLifecycleStatus? status,
    PartId? currentPartId,
    String? currentTaskId,
    String? currentAttemptId,
    int? completedPartsCount,
    int? totalPartsCount,
    String? errorMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return StreamingGenerationSession(
      sessionId: sessionId ?? this.sessionId,
      resourceId: resourceId ?? this.resourceId,
      blueprintId: blueprintId ?? this.blueprintId,
      creationSessionId: creationSessionId ?? this.creationSessionId,
      status: status ?? this.status,
      currentPartId: currentPartId ?? this.currentPartId,
      currentTaskId: currentTaskId ?? this.currentTaskId,
      currentAttemptId: currentAttemptId ?? this.currentAttemptId,
      completedPartsCount: completedPartsCount ?? this.completedPartsCount,
      totalPartsCount: totalPartsCount ?? this.totalPartsCount,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StreamingGenerationSession &&
          other.sessionId == sessionId &&
          other.resourceId == resourceId &&
          other.blueprintId == blueprintId &&
          other.creationSessionId == creationSessionId &&
          other.status == status &&
          other.currentPartId == currentPartId &&
          other.currentTaskId == currentTaskId &&
          other.currentAttemptId == currentAttemptId &&
          other.completedPartsCount == completedPartsCount &&
          other.totalPartsCount == totalPartsCount &&
          other.errorMessage == errorMessage;

  @override
  int get hashCode => Object.hash(
        sessionId,
        resourceId,
        blueprintId,
        creationSessionId,
        status,
        currentPartId,
        currentTaskId,
        currentAttemptId,
        completedPartsCount,
        totalPartsCount,
        errorMessage,
      );

  @override
  String toString() =>
      'StreamingGenerationSession($sessionId, res: ${resourceId.value}, '
      'status: ${status.storageValue}, progress: $completedPartsCount/$totalPartsCount)';
}
