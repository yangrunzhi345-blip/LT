import '../../../../application/resources/compression_coordinator.dart';
import '../../../../application/resources/resource_capacity_service.dart';
import '../../../../domain/resources/resource_capacity.dart';
import '../../../../domain/resources/resource_compression.dart';
import '../../../../domain/resources/resource_contracts.dart';
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

  /// Runs already-queued compression jobs once.
  Future<CompressionRunProgress> runQueuedCompression({int maxJobs});

  /// Releases compression jobs orphaned by a previous process. Idempotent, and
  /// the startup hook that keeps an interrupted job from blocking its target.
  Future<int> recoverInterruptedJobs();

  /// Measures the resource, evaluates the capacity trigger, and queues
  /// compression jobs only when the resource is over its budget.
  ///
  /// Returns the number of active jobs after the call. It only creates jobs:
  /// no model call, no write to Part content.
  Future<int> autoQueueCompressionIfNeeded(String resourceId);

  /// Re-queues the failed jobs of [resourceId] that still have attempt budget.
  Future<int> retryFailedCompression(String resourceId);

  void dispose();
}

/// Production adapter over the measured capacity service and the compression
/// coordinator.
final class ResourceCapacityServiceRuntime implements ResourceCapacityRuntime {
  ResourceCapacityServiceRuntime({
    required ResourceCapacityService capacityService,
    required CompressionCoordinator compressionCoordinator,
  })  : _capacityService = capacityService,
        _compressionCoordinator = compressionCoordinator;

  final ResourceCapacityService _capacityService;
  final CompressionCoordinator _compressionCoordinator;

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
  Future<CompressionRunProgress> runQueuedCompression({int maxJobs = 4}) =>
      _compressionCoordinator.drain(maxJobs: maxJobs);

  @override
  Future<int> recoverInterruptedJobs() =>
      _compressionCoordinator.recoverInterruptedJobs();

  @override
  Future<int> autoQueueCompressionIfNeeded(String resourceId) async {
    final id = ResourceId(resourceId);
    // Measure rather than read the cache: a trigger decision must never be made
    // from a stale projection.
    final snapshot = await _capacityService.measure(id);
    final decision = _capacityService.evaluateResource(snapshot);
    if (!decision.shouldCompress) return 0;
    final jobs = await _compressionCoordinator.enqueueForResource(id);
    return jobs.where((job) => job.isActive).length;
  }

  @override
  Future<int> retryFailedCompression(String resourceId) =>
      _compressionCoordinator.retryFailedJobs(ResourceId(resourceId));

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
    return ResourceCapacitySummary(
      snapshot: snapshot,
      queuedJobs: jobs
          .where((job) =>
              job.status == CompressionJobStatus.queued ||
              job.status == CompressionJobStatus.running)
          .length,
      candidateCount:
          candidates.where((candidate) => candidate.isValidated).length,
      potentialSavedCharacters: await _compressionCoordinator
          .potentialSavedCharacters(snapshot.resourceId),
      retryableFailedJobs: jobs
          .where((job) =>
              job.status == CompressionJobStatus.failed && job.canRetry)
          .length,
      latestFailureReason: _firstFailureReason(jobs),
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
