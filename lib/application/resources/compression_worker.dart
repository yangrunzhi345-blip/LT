import 'dart:async';

import '../../domain/resources/resource_contracts.dart';
import 'compression_coordinator.dart';
import 'resource_capacity_service.dart';

/// Owns bounded compression passes, leases and queue continuation.
/// Candidates remain proposals; this worker never replaces resource content.
final class CompressionBackgroundWorker {
  CompressionBackgroundWorker({
    required CompressionCoordinator coordinator,
    required ResourceCapacityService capacityService,
  })  : _coordinator = coordinator,
        _capacityService = capacityService;

  final CompressionCoordinator _coordinator;
  final ResourceCapacityService _capacityService;
  final Map<String, Future<void>> _processing = {};
  final Set<String> _scheduledAgain = {};
  String _lastError = '';

  Future<void> Function(ResourceId resourceId)? onSettled;
  void Function(ResourceId resourceId)? onProgress;

  String get workerId => _coordinator.workerId;
  int get processingCount => _processing.length;
  String get lastError => _lastError;
  bool isProcessing(String resourceId) => _processing.containsKey(resourceId);

  Future<int> start() async {
    try {
      final reclaimed = await _coordinator.recoverStaleJobs();
      for (final resourceId in await _coordinator.queuedResourceIds()) {
        scheduleProcessing(resourceId);
      }
      return reclaimed;
    } catch (_) {
      _lastError = 'resourceGenerationFailed';
      return 0;
    }
  }

  Future<int> onEditorLeave(String resourceId) async {
    try {
      final id = ResourceId(resourceId);
      final snapshot = await _capacityService.measure(id);
      final jobs = _capacityService.evaluateResource(snapshot).shouldCompress
          ? await _coordinator.enqueueForResource(id)
          : await _coordinator.jobsForResource(id);
      final active = jobs.where((job) => job.isActive).length;
      if (active > 0) scheduleProcessing(resourceId);
      return active;
    } catch (_) {
      _lastError = 'resourceGenerationFailed';
      return 0;
    }
  }

  void scheduleProcessing(String resourceId) {
    if (resourceId.isEmpty) return;
    unawaited(process(resourceId));
  }

  /// Coalesces callers while draining every queued job in bounded batches.
  /// Failed jobs are never automatically requeued.
  Future<void> process(String resourceId) {
    final existing = _processing[resourceId];
    if (existing != null) {
      _scheduledAgain.add(resourceId);
      return existing;
    }
    final future = Future<void>.microtask(() => _process(resourceId));
    _processing[resourceId] = future;
    return future;
  }

  Future<void> _process(String resourceId) async {
    final id = ResourceId(resourceId);
    try {
      do {
        _scheduledAgain.remove(resourceId);
        while (true) {
          final progress = await _coordinator.drain(
              resourceId: id, onProgress: (_) => onProgress?.call(id));
          if (progress.processedJobs == 0) break;
        }
      } while (_scheduledAgain.remove(resourceId));
      _lastError = '';
    } catch (_) {
      _lastError = 'resourceGenerationFailed';
    } finally {
      try {
        await onSettled?.call(id);
      } catch (_) {
        _lastError = 'resourceGenerationFailed';
      } finally {
        _processing.remove(resourceId);
        if (_scheduledAgain.remove(resourceId)) scheduleProcessing(resourceId);
      }
    }
  }
}
