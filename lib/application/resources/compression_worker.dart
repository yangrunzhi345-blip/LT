import 'dart:async';

import '../../domain/resources/resource_contracts.dart';
import 'compression_coordinator.dart';
import 'resource_capacity_service.dart';

/// Phase 8's minimal compression worker lifecycle.
///
/// It exists so the automatic compression path has a runtime owner that is not
/// a UI lifecycle event:
///
/// - [start] is the worker startup hook. It reclaims jobs whose owner died, so
///   crash recovery happens whether or not any screen is open.
/// - [onEditorLeave] is the automatic trigger. It measures the resource, asks
///   [CompressionTriggers] whether compression is warranted, queues jobs when it
///   is, and then starts a **non-blocking** background pass for that resource.
/// - [scheduleProcessing] consumes the queue in the background. It coalesces
///   repeats per resource, and the coordinator's atomic claim is what actually
///   guarantees one execution per job.
///
/// Nothing here publishes a candidate; publishing stays with Phase 9.
///
/// Compression is a derived task: every entry point catches its own failures and
/// records them in [lastError] instead of throwing, so a model or database
/// problem can never fail the editor action that triggered it. Per-job failures
/// are still recorded on the job row and shown by the capacity panel.
final class CompressionBackgroundWorker {
  CompressionBackgroundWorker({
    required CompressionCoordinator coordinator,
    required ResourceCapacityService capacityService,
  })  : _coordinator = coordinator,
        _capacityService = capacityService;

  final CompressionCoordinator _coordinator;
  final ResourceCapacityService _capacityService;

  final Set<String> _processing = <String>{};
  String _lastError = '';

  /// Identity the underlying coordinator claims jobs with.
  String get workerId => _coordinator.workerId;

  /// Resources that currently have a background pass scheduled.
  int get processingCount => _processing.length;

  /// Most recent background failure, empty when the last pass was clean.
  String get lastError => _lastError;

  /// Worker startup: reclaims jobs left `running` by a process that died.
  ///
  /// Returns how many rows were released. Safe to call once per process at
  /// startup; it is also idempotent.
  Future<int> start() async {
    try {
      final reclaimed = await _coordinator.recoverStaleJobs();
      _lastError = '';
      return reclaimed;
    } catch (error) {
      _lastError = error.toString();
      return 0;
    }
  }

  /// Automatic trigger for [resourceId]: queue if needed, then process it in
  /// the background.
  ///
  /// Returns the number of active jobs after the call. Queueing never waits on
  /// the model, and the returned future does not wait for the background pass,
  /// so leaving the editor never blocks on a request.
  Future<int> onEditorLeave(String resourceId) async {
    try {
      final id = ResourceId(resourceId);
      final snapshot = await _capacityService.measure(id);
      final decision = _capacityService.evaluateResource(snapshot);
      final jobs = decision.shouldCompress
          ? await _coordinator.enqueueForResource(id)
          : await _coordinator.jobsForResource(id);
      final active = jobs.where((job) => job.isActive).length;
      if (active > 0) scheduleProcessing(resourceId);
      return active;
    } catch (error) {
      _lastError = error.toString();
      return 0;
    }
  }

  /// Starts one background pass for [resourceId], coalescing repeats.
  void scheduleProcessing(String resourceId) {
    if (resourceId.isEmpty) return;
    if (!_processing.add(resourceId)) return;
    unawaited(_process(resourceId));
  }

  Future<void> _process(String resourceId) async {
    try {
      await _coordinator.drain(resourceId: ResourceId(resourceId));
      _lastError = '';
    } catch (error) {
      _lastError = error.toString();
    } finally {
      _processing.remove(resourceId);
    }
  }
}
