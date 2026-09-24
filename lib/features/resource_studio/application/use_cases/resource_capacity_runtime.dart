import '../../../../application/resources/compression_coordinator.dart';
import '../../../../application/resources/compression_worker.dart';
import '../../../../application/resources/resource_capacity_service.dart';
import '../../../../application/resources/resource_compression_publisher.dart';
import '../../../../domain/resources/resource_capacity.dart';
import '../../../../domain/resources/resource_compression.dart';
import '../../../../domain/resources/resource_contracts.dart';
import '../../../../domain/errors/app_error.dart';
import '../../domain/models/resource_capacity_view_state.dart';

/// Narrow capacity boundary consumed by the Studio UI.
///
/// The panel never touches SQLite, the LLM gateway or a compression
/// coordinator directly, so it can be widget-tested with a tiny fake while
/// production still goes through the measured services.
abstract interface class ResourceCapacityRuntime {
  /// Reads the cached measurement without writing, so a first paint is cheap.
  Future<ResourceCapacitySummary> summarize(String resourceId);

  /// Re-measures from the tree and refreshes the cache.
  Future<ResourceCapacitySummary> refresh(String resourceId);

  /// Queues compression jobs for the resource. Never waits on the model.
  Future<int> queueCompression(String resourceId);

  /// Runs already-queued compression jobs **of one resource** once.
  ///
  /// Scoped by resource so a manual compression of A never consumes B's queue
  /// nor reports B's results on A's panel.
  Future<CompressionRunProgress> runQueuedCompression(
    String resourceId, {
    int maxJobs,
  });

  /// Automatic trigger for leaving the editor: measure, evaluate the threshold,
  /// queue when warranted, and start a non-blocking background pass.
  ///
  /// Returns the number of active jobs. It never waits on the model and never
  /// throws, because compression is a derived task.
  Future<int> onEditorLeave(String resourceId);

  /// Re-queues the failed jobs of [resourceId] that still have attempt budget.
  ///
  /// A job whose target already has an active job is skipped as a business
  /// result instead of failing the batch.
  Future<CompressionRetryOutcome> retryFailedCompression(String resourceId);

  /// Publishes the newest publishable compression candidate of [resourceId].
  ///
  /// This is the only Phase 9 path that replaces confirmed body text with a
  /// compressed version, and it does so behind the revision boundary: the
  /// previous content is recorded first and stays restorable. Throws
  /// [CompressionPublishException] when there is nothing publishable, so the
  /// caller can explain that instead of reporting a silent success.
  Future<CompressionPublishOutcome> publishLatestCompression(String resourceId);

  void dispose();
}

/// Production adapter over the measured capacity service, the compression
/// coordinator and the background worker.
final class ResourceCapacityServiceRuntime implements ResourceCapacityRuntime {
  ResourceCapacityServiceRuntime({
    required ResourceCapacityService capacityService,
    required CompressionCoordinator compressionCoordinator,
    CompressionPublisher? compressionPublisher,
    CompressionBackgroundWorker? worker,
  })  : _capacityService = capacityService,
        _compressionCoordinator = compressionCoordinator,
        _compressionPublisher = compressionPublisher,
        _worker = worker ??
            CompressionBackgroundWorker(
              coordinator: compressionCoordinator,
              capacityService: capacityService,
            );

  final ResourceCapacityService _capacityService;
  final CompressionCoordinator _compressionCoordinator;
  final CompressionPublisher? _compressionPublisher;
  final CompressionBackgroundWorker _worker;

  @override
  Future<ResourceCapacitySummary> summarize(String resourceId) async {
    final id = ResourceId(resourceId);
    final cached = await _capacityService.readCached(id);
    final snapshot = cached ?? await _capacityService.measure(id);
    return _decorate(snapshot);
  }

  @override
  Future<ResourceCapacitySummary> refresh(String resourceId) async {
    final id = ResourceId(resourceId);
    final snapshot = await _capacityService.measure(id);
    return _decorate(snapshot);
  }

  @override
  Future<int> queueCompression(String resourceId) async {
    final jobs = await _compressionCoordinator.enqueueForResource(
      ResourceId(resourceId),
    );
    return jobs.where((job) => job.isActive).length;
  }

  @override
  Future<CompressionRunProgress> runQueuedCompression(
    String resourceId, {
    int maxJobs = 4,
  }) =>
      _compressionCoordinator.drain(
        resourceId: ResourceId(resourceId),
        maxJobs: maxJobs,
      );

  @override
  Future<int> onEditorLeave(String resourceId) =>
      _worker.onEditorLeave(resourceId);

  @override
  Future<CompressionRetryOutcome> retryFailedCompression(String resourceId) =>
      _compressionCoordinator.retryFailedJobs(ResourceId(resourceId));

  @override
  Future<CompressionPublishOutcome> publishLatestCompression(
    String resourceId,
  ) async {
    final publisher = _compressionPublisher;
    if (publisher == null) {
      throw const CompressionPublishException(
        '压缩结果发布通道未接线，请更新应用配置',
      );
    }
    final candidates = await publisher.publishableCandidates(
      ResourceId(resourceId),
    );
    if (candidates.isEmpty) {
      throw const CompressionPublishException('没有可发布的压缩结果');
    }
    // `publishableCandidates` is newest-first, so the panel publishes the most
    // recent proposal instead of resurrecting the oldest one.
    return publisher.publish(candidates.first.candidateId);
  }

  @override
  void dispose() {}

  Future<ResourceCapacitySummary> _decorate(
    ResourceCapacitySnapshot snapshot,
  ) async {
    final jobs = await _compressionCoordinator.jobsForResource(
      snapshot.resourceId,
    );
    final candidates = await _compressionCoordinator.candidatesForResource(
      snapshot.resourceId,
    );
    final publisher = _compressionPublisher;
    final publishableCount = publisher == null
        ? 0
        : (await publisher.publishableCandidates(snapshot.resourceId)).length;
    final latestFailureReason = _firstFailureReason(jobs);
    return ResourceCapacitySummary(
      snapshot: snapshot,
      queuedJobs: jobs
          .where((job) =>
              job.status == CompressionJobStatus.queued ||
              job.status == CompressionJobStatus.running)
          .length,
      candidateCount:
          candidates.where((candidate) => candidate.isValidated).length,
      publishableCandidateCount: publishableCount,
      potentialSavedCharacters: await _compressionCoordinator
          .potentialSavedCharacters(snapshot.resourceId),
      retryableFailedJobs: jobs
          .where((job) =>
              job.status == CompressionJobStatus.failed && job.canRetry)
          .length,
      latestFailureReason: latestFailureReason,
      latestFailure: latestFailureReason.isEmpty
          ? null
          : const AppDomainError(
              code: AppErrorCode.resourceGenerationFailed,
            ),
    );
  }

  /// First recorded failure reason, so the panel can explain *why* a job failed
  /// instead of only reporting a count.
  static String _firstFailureReason(List<CompressionJob> jobs) {
    for (final job in jobs) {
      if (job.status == CompressionJobStatus.failed &&
          job.errorMessage.trim().isNotEmpty) {
        return job.errorMessage.trim();
      }
    }
    return '';
  }
}
