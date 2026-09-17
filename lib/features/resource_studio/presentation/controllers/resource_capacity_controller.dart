import 'dart:async';

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

  ResourceCapacityViewState get state => _state;

  /// Loads the cached measurement for [resourceId].
  ///
  /// Reading the panel must not have side effects: the automatic compression
  /// trigger belongs to the editor lifecycle ([notifyEditorLeft]), not to
  /// opening a screen, and crash recovery belongs to the worker lifecycle.
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
    } catch (error) {
      _emit(_state.copyWith(
        status: ResourceCapacityViewStatus.failed,
        errorMessage: error.toString(),
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
  /// `maxAttempts` is refused, and a job whose target already has an active job
  /// is reported as skipped instead of failing the batch, so pressing this can
  /// never loop and never surfaces a database error. As with
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
      final outcome = await _runtime.retryFailedCompression(resourceId);
      if (outcome.requeued == 0) {
        _emit(_state.copyWith(
          status: ResourceCapacityViewStatus.ready,
          lastMessage: _retryMessage(outcome),
        ));
        return;
      }
      unawaited(_runQueue(resourceId, skippedNote: _retryMessage(outcome)));
    } catch (error) {
      _emit(_state.copyWith(
        status: ResourceCapacityViewStatus.failed,
        errorMessage: error.toString(),
      ));
    }
  }

  /// Explains what a retry did, including the jobs it deliberately skipped.
  static String _retryMessage(CompressionRetryOutcome outcome) {
    if (outcome.requeued == 0) {
      if (outcome.skippedActiveTarget > 0) {
        return '${outcome.skippedActiveTarget} 个失败任务的目标已有进行中的压缩，已跳过';
      }
      if (outcome.skippedExhausted > 0) {
        return '没有可重试的压缩任务（${outcome.skippedExhausted} 个已达重试上限）';
      }
      return '没有可重试的压缩任务（可能已达重试上限）';
    }
    final parts = <String>['已重试 ${outcome.requeued} 个压缩任务'];
    if (outcome.skippedActiveTarget > 0) {
      parts.add('${outcome.skippedActiveTarget} 个目标已有进行中的压缩，已跳过');
    }
    return parts.join('；');
  }

  Future<void> _runQueue(String resourceId, {String skippedNote = ''}) async {
    try {
      final progress = await _runtime.runQueuedCompression(resourceId);
      final summary = await _runtime.summarize(resourceId);
      final succeededNote = progress.succeededJobs > 0
          ? '已生成 ${progress.succeededJobs} 个压缩候选（需确认后才会替换正文）'
          : '';
      _emit(ResourceCapacityViewState(
        status: progress.failedJobs > 0
            ? ResourceCapacityViewStatus.failed
            : ResourceCapacityViewStatus.ready,
        resourceId: summary.snapshot.resourceId,
        summary: summary,
        lastMessage: [succeededNote, skippedNote]
            .where((part) => part.isNotEmpty)
            .join('；'),
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
    // Leaving the editor is the automatic compression boundary: queue if the
    // resource is over budget and let the worker process it in the background.
    // Called before `_disposed` is set so the trigger can still read the state.
    notifyEditorLeft();
    _disposed = true;
    _runtime.dispose();
    super.dispose();
  }
}
