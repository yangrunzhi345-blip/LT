import '../../../../domain/resources/resource_capacity.dart';
import '../../../../domain/resources/resource_contracts.dart';
import '../../../../domain/errors/app_error.dart';

/// Presentation status of the capacity panel.
enum ResourceCapacityViewStatus {
  idle,
  loading,
  ready,
  working,
  failed,
}

enum ResourceCapacityNoticeType {
  noCompressionNeeded,
  compressionAlreadyPublished,
  compressionPublished,
  retryBlockedByActiveTarget,
  retryBudgetExhausted,
  retryUnavailable,
  compressionRunSummary,
}

final class ResourceCapacityNotice {
  const ResourceCapacityNotice({
    required this.type,
    this.savedCharacters = 0,
    this.requeuedJobs = 0,
    this.skippedActiveTargets = 0,
    this.skippedExhaustedJobs = 0,
    this.succeededJobs = 0,
    this.failedJobs = 0,
  });

  final ResourceCapacityNoticeType type;
  final int savedCharacters;
  final int requeuedJobs;
  final int skippedActiveTargets;
  final int skippedExhaustedJobs;
  final int succeededJobs;
  final int failedJobs;
}

/// Aggregated capacity view for one resource.
final class ResourceCapacitySummary {
  const ResourceCapacitySummary({
    required this.snapshot,
    this.queuedJobs = 0,
    this.candidateCount = 0,
    this.publishableCandidateCount = 0,
    this.potentialSavedCharacters = 0,
    this.retryableFailedJobs = 0,
    this.latestFailureReason = '',
    this.latestFailure,
  });

  final ResourceCapacitySnapshot snapshot;

  /// Compression jobs waiting to run.
  final int queuedJobs;

  /// Validated compression candidates produced so far (applied or not).
  final int candidateCount;

  /// Validated, unapplied, part-scoped candidates — the ones a publish action
  /// can actually act on. Counted separately from [candidateCount] because a
  /// section-scoped or already published candidate is not publishable, and
  /// offering an action that would fail is worse than not offering it.
  final int publishableCandidateCount;

  /// Characters a full adoption of the candidates would save.
  final int potentialSavedCharacters;

  /// Failed jobs that still have attempt budget, i.e. the ones a retry can
  /// actually re-queue. Distinguishing these from terminal failures is what
  /// makes the retry affordance honest.
  final int retryableFailedJobs;

  /// The most recent failure reason, so the panel can explain *why* rather than
  /// only reporting a count.
  final String latestFailureReason;

  /// Stable presentation failure classification. [latestFailureReason] is
  /// retained as a legacy diagnostic for recovery tooling and tests.
  final AppDomainError? latestFailure;

  bool get hasRetryableFailures => retryableFailedJobs > 0;

  bool get hasPublishableCandidates => publishableCandidateCount > 0;
}

/// Immutable state exposed by `ResourceCapacityController`.
final class ResourceCapacityViewState {
  const ResourceCapacityViewState({
    required this.status,
    this.resourceId,
    this.summary,
    this.errorMessage = '',
    this.notice,
    this.error,
  });

  const ResourceCapacityViewState.initial()
      : this(status: ResourceCapacityViewStatus.idle);

  final ResourceCapacityViewStatus status;
  final ResourceId? resourceId;
  final ResourceCapacitySummary? summary;
  final String errorMessage;
  final ResourceCapacityNotice? notice;
  final AppDomainError? error;

  bool get isLoading => status == ResourceCapacityViewStatus.loading;

  bool get isWorking => status == ResourceCapacityViewStatus.working;

  bool get hasCapacity => summary != null;

  ResourceCapacityViewState copyWith({
    ResourceCapacityViewStatus? status,
    ResourceId? resourceId,
    ResourceCapacitySummary? summary,
    String? errorMessage,
    ResourceCapacityNotice? notice,
    bool clearNotice = false,
    AppDomainError? error,
  }) {
    return ResourceCapacityViewState(
      status: status ?? this.status,
      resourceId: resourceId ?? this.resourceId,
      summary: summary ?? this.summary,
      errorMessage: errorMessage ?? this.errorMessage,
      notice: clearNotice ? null : (notice ?? this.notice),
      error: error ?? this.error,
    );
  }
}
