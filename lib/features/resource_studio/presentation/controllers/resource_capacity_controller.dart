import 'dart:async';

import '../../../../core/localization/app_error_localizer.dart';

import 'package:flutter/foundation.dart';

import '../../../../domain/resources/resource_compression.dart';
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

  /// Monotonic request token captured by every async entrypoint. A slow
  /// summarize/measure/queue run for an older resource or an older request
  /// must never publish over the current one, so every emit re-validates it.
  int _generation = 0;

  ResourceCapacityViewState get state => _state;

  /// Loads the cached measurement for [resourceId].
  ///
  /// Reading the panel must not have side effects: the automatic compression
  /// trigger belongs to the editor lifecycle ([notifyEditorLeft]), not to
  /// opening a screen, and crash recovery belongs to the worker lifecycle.
  Future<void> load(String resourceId) async {
    final generation = ++_generation;
    _emit(_state.copyWith(
      status: ResourceCapacityViewStatus.loading,
      resourceId: ResourceId(resourceId),
      errorMessage: '',
      clearNotice: true,
    ));
    try {
      final summary = await _runtime.summarize(resourceId);
      if (_disposed || generation != _generation) return;
      _emit(ResourceCapacityViewState(
        status: ResourceCapacityViewStatus.ready,
        resourceId: summary.snapshot.resourceId,
        summary: summary,
      ));
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _emit(_state.copyWith(
        status: ResourceCapacityViewStatus.failed,
        errorMessage: '',
        error: asAppDomainError(error),
      ));
    }
  }

  /// Signals that the editor for the currently shown resource is being left.
  ///
  /// This is the automatic compression trigger: the runtime measures the
  /// resource, queues when the threshold says so, and processes the queue in
  /// the background. It is deliberately fire-and-forget — leaving the editor
  /// must never wait on a request — and the runtime swallows its own failures.
  void notifyEditorLeft() {
    final resourceId = _state.resourceId?.value;
    if (resourceId == null) return;
    unawaited(_triggerEditorLeave(resourceId));
  }

  Future<void> _triggerEditorLeave(String resourceId) async {
    try {
      await _runtime.onEditorLeave(resourceId);
    } catch (error) {
      // The runtime is expected to record its own failure and never throw; this
      // guard exists only so a throwing implementation cannot become an
      // unhandled async error while the page is being disposed.
      debugPrint('[ResourceCapacity] 离开编辑器后的压缩触发失败: $error');
    }
  }

  /// Re-measures from the tree.
  Future<void> refresh() async {
    final resourceId = _state.resourceId?.value;
    if (resourceId == null) return;
    final generation = ++_generation;
    _emit(_state.copyWith(
      status: ResourceCapacityViewStatus.loading,
      errorMessage: '',
      clearNotice: true,
    ));
    try {
      final summary = await _runtime.refresh(resourceId);
      if (_disposed || generation != _generation) return;
      _emit(ResourceCapacityViewState(
        status: ResourceCapacityViewStatus.ready,
        resourceId: summary.snapshot.resourceId,
        summary: summary,
      ));
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _emit(_state.copyWith(
        status: ResourceCapacityViewStatus.failed,
        errorMessage: '',
        error: asAppDomainError(error),
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

    final generation = _generation;
    _emit(_state.copyWith(
      status: ResourceCapacityViewStatus.working,
      errorMessage: '',
      clearNotice: true,
    ));
    try {
      final queued = await _runtime.queueCompression(resourceId);
      if (_disposed || generation != _generation) return;
      if (queued == 0) {
        _emit(_state.copyWith(
          status: ResourceCapacityViewStatus.ready,
          notice: const ResourceCapacityNotice(
            type: ResourceCapacityNoticeType.noCompressionNeeded,
          ),
        ));
        return;
      }
      unawaited(_runQueue(resourceId, generation: generation));
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _emit(_state.copyWith(
        status: ResourceCapacityViewStatus.failed,
        errorMessage: '',
        error: asAppDomainError(error),
      ));
    }
  }

  /// Re-queues the resource's retryable failed jobs and runs them.
  ///
  /// The attempt budget is enforced by the coordinator: a job that already spent
  /// `maxAttempts` is refused, and a job whose target already has an active job
  /// is reported as skipped instead of failing the batch, so pressing this can
  /// never loop and never surfaces a database error. As with
  /// [requestCompression], only queueing is awaited.
  Future<void> retryFailedCompression() async {
    final resourceId = _state.resourceId?.value;
    if (resourceId == null) return;
    if (_state.status == ResourceCapacityViewStatus.working) return;

    final generation = _generation;
    _emit(_state.copyWith(
      status: ResourceCapacityViewStatus.working,
      errorMessage: '',
      clearNotice: true,
    ));
    try {
      final outcome = await _runtime.retryFailedCompression(resourceId);
      if (_disposed || generation != _generation) return;
      if (outcome.requeued == 0) {
        _emit(_state.copyWith(
          status: ResourceCapacityViewStatus.ready,
          notice: _retryNotice(outcome),
        ));
        return;
      }
      unawaited(_runQueue(resourceId,
          retryNotice: _retryNotice(outcome), generation: generation));
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _emit(_state.copyWith(
        status: ResourceCapacityViewStatus.failed,
        errorMessage: '',
        error: asAppDomainError(error),
      ));
    }
  }

  /// Publishes the newest validated compression candidate as the new head.
  ///
  /// The revision boundary records the pre-compression content first, so this
  /// overwrite is reversible from the version history. The panel is refreshed
  /// afterwards because publishing changes the measured character count.
  Future<void> publishCompression() async {
    final resourceId = _state.resourceId?.value;
    if (resourceId == null) return;
    if (_state.status == ResourceCapacityViewStatus.working) return;

    final generation = _generation;
    _emit(_state.copyWith(
      status: ResourceCapacityViewStatus.working,
      errorMessage: '',
      clearNotice: true,
    ));
    try {
      final outcome = await _runtime.publishLatestCompression(resourceId);
      final refreshed = await _runtime.refresh(resourceId);
      if (_disposed || generation != _generation) return;
      _emit(_state.copyWith(
        status: ResourceCapacityViewStatus.ready,
        summary: refreshed,
        notice: ResourceCapacityNotice(
          type: outcome.alreadyApplied
              ? ResourceCapacityNoticeType.compressionAlreadyPublished
              : ResourceCapacityNoticeType.compressionPublished,
          savedCharacters: outcome.savedCharacters,
        ),
      ));
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _emit(_state.copyWith(
        status: ResourceCapacityViewStatus.failed,
        errorMessage: '',
        error: asAppDomainError(error),
      ));
    }
  }

  /// Explains what a retry did, including the jobs it deliberately skipped.
  static ResourceCapacityNotice _retryNotice(
    CompressionRetryOutcome outcome,
  ) {
    if (outcome.requeued == 0) {
      if (outcome.skippedActiveTarget > 0) {
        return ResourceCapacityNotice(
          type: ResourceCapacityNoticeType.retryBlockedByActiveTarget,
          skippedActiveTargets: outcome.skippedActiveTarget,
        );
      }
      if (outcome.skippedExhausted > 0) {
        return ResourceCapacityNotice(
          type: ResourceCapacityNoticeType.retryBudgetExhausted,
          skippedExhaustedJobs: outcome.skippedExhausted,
        );
      }
      return const ResourceCapacityNotice(
        type: ResourceCapacityNoticeType.retryUnavailable,
      );
    }
    return ResourceCapacityNotice(
      type: ResourceCapacityNoticeType.compressionRunSummary,
      requeuedJobs: outcome.requeued,
      skippedActiveTargets: outcome.skippedActiveTarget,
      skippedExhaustedJobs: outcome.skippedExhausted,
    );
  }

  Future<void> _runQueue(
    String resourceId, {
    ResourceCapacityNotice? retryNotice,
    required int generation,
  }) async {
    try {
      final progress = await _runtime.runQueuedCompression(resourceId);
      final summary = await _runtime.summarize(resourceId);
      if (_disposed || generation != _generation) return;
      final notice = progress.succeededJobs == 0 &&
              progress.failedJobs == 0 &&
              (retryNotice == null ||
                  (retryNotice.requeuedJobs == 0 &&
                      retryNotice.skippedActiveTargets == 0 &&
                      retryNotice.skippedExhaustedJobs == 0))
          ? null
          : ResourceCapacityNotice(
              type: ResourceCapacityNoticeType.compressionRunSummary,
              requeuedJobs: retryNotice?.requeuedJobs ?? 0,
              skippedActiveTargets: retryNotice?.skippedActiveTargets ?? 0,
              skippedExhaustedJobs: retryNotice?.skippedExhaustedJobs ?? 0,
              succeededJobs: progress.succeededJobs,
              failedJobs: progress.failedJobs,
            );
      _emit(ResourceCapacityViewState(
        status: progress.failedJobs > 0
            ? ResourceCapacityViewStatus.failed
            : ResourceCapacityViewStatus.ready,
        resourceId: summary.snapshot.resourceId,
        summary: summary,
        notice: notice,
      ));
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _emit(_state.copyWith(
        status: ResourceCapacityViewStatus.failed,
        errorMessage: '',
        error: asAppDomainError(error),
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
    // Leaving the editor is the automatic compression boundary: queue if the
    // resource is over budget and let the worker process it in the background.
    // Called before `_disposed` is set so the trigger can still read the state.
    notifyEditorLeft();
    _disposed = true;
    _runtime.dispose();
    super.dispose();
  }
}
