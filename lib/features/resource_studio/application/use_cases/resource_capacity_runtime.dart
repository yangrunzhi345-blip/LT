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
    );
  }
}
