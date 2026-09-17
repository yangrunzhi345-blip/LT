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

  /// Loads the cached measurement for [resourceId], falling back to a measure.
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
