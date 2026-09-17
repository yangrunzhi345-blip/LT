import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../domain/resources/resource_contracts.dart';
import '../../application/use_cases/resource_capacity_runtime.dart';
import '../../domain/models/resource_capacity_view_state.dart';

/// Drives the Studio capacity panel.
///
/// The controller keeps the database as the source of truth: it only ever
/// reflects what the runtime reports back, so the panel can never show a
/// capacity that was never measured.
final class ResourceCapacityController extends ChangeNotifier {
  ResourceCapacityController({required ResourceCapacityRuntime runtime})
      : _runtime = runtime;

  final ResourceCapacityRuntime _runtime;

  ResourceCapacityViewState _state = const ResourceCapacityViewState.initial();
  bool _disposed = false;

  ResourceCapacityViewState get state => _state;

  /// Loads the cached measurement for [resourceId], then starts the background
  /// capacity workflow.
  ///
  /// The workflow (interrupted-job recovery, then the automatic threshold
  /// trigger) is deliberately not awaited by the caller: the panel must paint
  /// immediately, and nothing may be triggered from `build`.
  Future<void> load(String resourceId) async {
    _emit(_state.copyWith(
      status: ResourceCapacityViewStatus.loading,
      resourceId: ResourceId(resourceId),
      errorMessage: '',
    ));
    try {
      final summary = await _runtime.summarize(resourceId);
      _emit(ResourceCapacityViewState(
        status: ResourceCapacityViewStatus.ready,
        resourceId: summary.snapshot.resourceId,
        summary: summary,
      ));
      unawaited(_runBackgroundWorkflow(resourceId));
    } catch (error) {
      _emit(_state.copyWith(
        status: ResourceCapacityViewStatus.failed,
        errorMessage: error.toString(),
      ));
    }
  }

  /// Recovers orphaned jobs, then runs the capacity trigger for [resourceId].
  ///
  /// Recovery comes first so a job left `running` by a previous process cannot
  /// block its target. If the trigger queued anything, the panel is refreshed
  /// once so the queued count reflects reality.
  Future<void> _runBackgroundWorkflow(String resourceId) async {
    // Capture what the panel is currently showing: if the user switches
    // resources while this runs, its results must be discarded rather than
    // applied to the wrong resource.
    final startedFor = _state.resourceId?.value;
    try {
      await _runtime.recoverInterruptedJobs();
      final queued = await _runtime.autoQueueCompressionIfNeeded(resourceId);
      if (queued == 0 || !_isStillShowing(startedFor)) return;
      final summary = await _runtime.summarize(resourceId);
      if (!_isStillShowing(startedFor)) return;
      _emit(ResourceCapacityViewState(
        status: ResourceCapacityViewStatus.ready,
        resourceId: summary.snapshot.resourceId,
        summary: summary,
      ));
    } catch (error) {
      // A background trigger failure must not break the panel; the user can
      // still refresh manually.
      if (!_isStillShowing(startedFor)) return;
      _emit(_state.copyWith(errorMessage: error.toString()));
    }
  }

  bool _isStillShowing(String? resourceId) =>
      resourceId != null && _state.resourceId?.value == resourceId;

  /// Re-measures from the tree.
  Future<void> refresh() async {
    final resourceId = _state.resourceId?.value;
    if (resourceId == null) return;
    _emit(_state.copyWith(
      status: ResourceCapacityViewStatus.loading,
      errorMessage: '',
    ));
    try {
      final summary = await _runtime.refresh(resourceId);
      _emit(ResourceCapacityViewState(
        status: ResourceCapacityViewStatus.ready,
        resourceId: summary.snapshot.resourceId,
        summary: summary,
      ));
    } catch (error) {
      _emit(_state.copyWith(
        status: ResourceCapacityViewStatus.failed,
        errorMessage: error.toString(),
      ));
    }
  }

  /// Queues compression, then runs the queue in the background.
  ///
  /// Queueing is what the caller waits on; the model work continues without
  /// blocking navigation, and the panel is refreshed once it finishes.
  Future<void> requestCompression() async {
    final resourceId = _state.resourceId?.value;
    if (resourceId == null) return;
    if (_state.status == ResourceCapacityViewStatus.working) return;

    _emit(_state.copyWith(
      status: ResourceCapacityViewStatus.working,
      errorMessage: '',
      lastMessage: '',
    ));
    try {
      final queued = await _runtime.queueCompression(resourceId);
      if (queued == 0) {
        _emit(_state.copyWith(
          status: ResourceCapacityViewStatus.ready,
          lastMessage: '没有需要压缩的章节',
        ));
        return;
      }
      unawaited(_runQueue(resourceId));
    } catch (error) {
      _emit(_state.copyWith(
        status: ResourceCapacityViewStatus.failed,
        errorMessage: error.toString(),
      ));
    }
  }

  /// Re-queues the resource's retryable failed jobs and runs them.
  ///
  /// The attempt budget is enforced by the coordinator: a job that already spent
  /// `maxAttempts` is refused, so pressing this cannot loop. As with
  /// [requestCompression], only queueing is awaited.
  Future<void> retryFailedCompression() async {
    final resourceId = _state.resourceId?.value;
    if (resourceId == null) return;
    if (_state.status == ResourceCapacityViewStatus.working) return;

    _emit(_state.copyWith(
      status: ResourceCapacityViewStatus.working,
      errorMessage: '',
      lastMessage: '',
    ));
    try {
      final requeued = await _runtime.retryFailedCompression(resourceId);
      if (requeued == 0) {
        _emit(_state.copyWith(
          status: ResourceCapacityViewStatus.ready,
          lastMessage: '没有可重试的压缩任务（可能已达重试上限）',
        ));
        return;
      }
      unawaited(_runQueue(resourceId));
    } catch (error) {
      _emit(_state.copyWith(
        status: ResourceCapacityViewStatus.failed,
        errorMessage: error.toString(),
      ));
    }
  }

  Future<void> _runQueue(String resourceId) async {
    try {
      final progress = await _runtime.runQueuedCompression();
      final summary = await _runtime.summarize(resourceId);
      _emit(ResourceCapacityViewState(
        status: progress.failedJobs > 0
            ? ResourceCapacityViewStatus.failed
            : ResourceCapacityViewStatus.ready,
        resourceId: summary.snapshot.resourceId,
        summary: summary,
        lastMessage: progress.succeededJobs > 0
            ? '已生成 ${progress.succeededJobs} 个压缩候选（需确认后才会替换正文）'
            : '',
        errorMessage: progress.failedJobs > 0
            ? '${progress.failedJobs} 个压缩任务失败，原稿保持不变'
            : '',
      ));
    } catch (error) {
      _emit(_state.copyWith(
        status: ResourceCapacityViewStatus.failed,
        errorMessage: error.toString(),
      ));
    }
  }

  void _emit(ResourceCapacityViewState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _runtime.dispose();
    super.dispose();
  }
}
