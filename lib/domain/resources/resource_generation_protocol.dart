import 'resource_contracts.dart';

/// Current version of the Incremental JSON Part Generation Protocol.
const int currentPartGenerationProtocolVersion = 1;

/// Lifecycle status of an individual Part generation task.
enum PartTaskStatus {
  /// Waiting for upstream dependencies to complete.
  pending,

  /// All dependencies are completed; ready for dispatch.
  ready,

  /// LLM request is currently in-flight.
  generating,

  /// Response received; undergoing structural and semantic validation.
  validating,

  /// Validation succeeded and Part content is committed to the resource tree.
  completed,

  /// Generation or validation failed; eligible for retry.
  failed,

  /// Cancelled by user or task handle; eligible for retry.
  cancelled;

  String get storageValue => name;

  static PartTaskStatus fromStorage(String? value) {
    for (final status in PartTaskStatus.values) {
      if (status.storageValue == value) return status;
    }
    return PartTaskStatus.pending;
  }

  bool get isTerminal =>
      this == PartTaskStatus.completed ||
      this == PartTaskStatus.failed ||
      this == PartTaskStatus.cancelled;

  bool get isInFlight =>
      this == PartTaskStatus.generating || this == PartTaskStatus.validating;
}

/// State machine governing valid transitions for a Part generation task.
abstract final class PartTaskStateMachine {
  static const Map<PartTaskStatus, Set<PartTaskStatus>> _allowedTransitions = {
    PartTaskStatus.pending: {
      PartTaskStatus.pending,
      PartTaskStatus.ready,
      PartTaskStatus.cancelled,
    },
    PartTaskStatus.ready: {
      PartTaskStatus.ready,
      PartTaskStatus.generating,
      PartTaskStatus.cancelled,
    },
    PartTaskStatus.generating: {
      PartTaskStatus.generating,
      PartTaskStatus.validating,
      PartTaskStatus.failed,
      PartTaskStatus.cancelled,
    },
    PartTaskStatus.validating: {
      PartTaskStatus.validating,
      PartTaskStatus.completed,
      PartTaskStatus.failed,
      PartTaskStatus.cancelled,
    },
    // Completed is terminal. Re-generating an already completed part requires
    // an explicit reset or revision.
    PartTaskStatus.completed: {
      PartTaskStatus.completed,
    },
    // Failed tasks can be retried to ready (if deps satisfied) or pending.
    PartTaskStatus.failed: {
      PartTaskStatus.failed,
      PartTaskStatus.ready,
      PartTaskStatus.pending,
    },
    // Cancelled tasks can be retried.
    PartTaskStatus.cancelled: {
      PartTaskStatus.cancelled,
      PartTaskStatus.ready,
      PartTaskStatus.pending,
    },
  };

  static bool canTransition(PartTaskStatus from, PartTaskStatus to) {
    return _allowedTransitions[from]?.contains(to) ?? false;
  }

  static PartTaskStatus advance(PartTaskStatus from, PartTaskStatus to) {
    if (!canTransition(from, to)) {
      throw StateError(
        'Invalid PartTaskStatus transition: ${from.storageValue} -> ${to.storageValue}',
      );
    }
    return to;
  }
}

/// Summary of a completed dependency part used for context assembly.
final class DependencyPartSummary {
  const DependencyPartSummary({
    required this.partId,
    required this.title,
    required this.contentSummary,
  });

  final PartId partId;
  final String title;
  final String contentSummary;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DependencyPartSummary &&
          other.partId == partId &&
          other.title == title &&
          other.contentSummary == contentSummary;

  @override
  int get hashCode => Object.hash(partId, title, contentSummary);

  @override
  String toString() =>
      'DependencyPartSummary(id: ${partId.value}, title: $title)';
}

/// Context provided to the model to generate body text for a single Part.
final class PartGenerationContext {
  const PartGenerationContext({
    required this.resourceName,
    required this.resourceType,
    required this.resourceSummary,
    required this.sectionTitle,
    required this.sectionSummary,
    required this.partTitle,
    this.dependencySummaries = const <DependencyPartSummary>[],
    this.referenceExcerpt = '',
  });

  final String resourceName;
  final ResourceType resourceType;
  final String resourceSummary;
  final String sectionTitle;
  final String sectionSummary;
  final String partTitle;
  final List<DependencyPartSummary> dependencySummaries;
  final String referenceExcerpt;
}

/// Strongly typed request for generating prose of exactly one Part.
final class PartGenerationRequest {
  const PartGenerationRequest({
    required this.generationId,
    required this.resourceId,
    required this.sectionId,
    required this.partId,
    required this.attemptId,
    required this.targetBudget,
    required this.promptGoal,
    required this.context,
    this.protocolVersion = currentPartGenerationProtocolVersion,
    this.attemptNumber = 1,
  });

  /// Incremental protocol version; must equal [currentPartGenerationProtocolVersion].
  final int protocolVersion;

  /// Unique identifier of the overall generation session run.
  final String generationId;

  /// Target Resource identity.
  final ResourceId resourceId;

  /// Parent Section identity.
  final SectionId sectionId;

  /// Target Part identity being generated.
  final PartId partId;

  /// Unique idempotency token for this specific attempt.
  final String attemptId;

  /// 1-based attempt sequence number for this Part.
  final int attemptNumber;

  /// Target character budget (estimated length).
  final int targetBudget;

  /// Specific goal/instruction for what this part should cover.
  final String promptGoal;

  /// Bounded contextual material needed for consistent generation.
  final PartGenerationContext context;

  @override
  String toString() =>
      'PartGenerationRequest(part: ${partId.value}, attempt: $attemptId, budget: $targetBudget)';
}

/// Validated response containing generated prose for exactly one Part.
final class PartGenerationResponse {
  const PartGenerationResponse({
    required this.protocolVersion,
    required this.generationId,
    required this.resourceId,
    required this.sectionId,
    required this.partId,
    required this.attemptId,
    required this.content,
    this.summary = '',
    this.status = 'completed',
  });

  final int protocolVersion;
  final String generationId;
  final ResourceId resourceId;
  final SectionId sectionId;
  final PartId partId;
  final String attemptId;
  final String content;
  final String summary;
  final String status;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PartGenerationResponse &&
          other.protocolVersion == protocolVersion &&
          other.generationId == generationId &&
          other.resourceId == resourceId &&
          other.sectionId == sectionId &&
          other.partId == partId &&
          other.attemptId == attemptId &&
          other.content == content &&
          other.summary == summary &&
          other.status == status;

  @override
  int get hashCode => Object.hash(
        protocolVersion,
        generationId,
        resourceId,
        sectionId,
        partId,
        attemptId,
        content,
        summary,
        status,
      );

  @override
  String toString() =>
      'PartGenerationResponse(part: ${partId.value}, attempt: $attemptId, chars: ${content.length})';
}
