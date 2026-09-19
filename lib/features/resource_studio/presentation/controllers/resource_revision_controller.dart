import 'package:flutter/foundation.dart';

import '../../application/use_cases/resource_revision_runtime.dart';
import '../../domain/models/resource_revision_view_state.dart';
import '../resource_studio_user_message.dart';

/// View-model of the Studio revision-history panel.
///
/// Holds no business rule: it asks the runtime for a display list, remembers
/// the last restore outcome and reports failures so the panel can show them
/// instead of silently doing nothing.
final class ResourceRevisionController extends ChangeNotifier {
  ResourceRevisionController({
    required ResourceRevisionRuntime runtime,
    this.historyLimit = 30,
  }) : _runtime = runtime;

  final ResourceRevisionRuntime _runtime;
  final int historyLimit;

  ResourceRevisionViewState _state = const ResourceRevisionViewState.initial();
  String _resourceId = '';
  bool _disposed = false;
  bool _busy = false;

  ResourceRevisionViewState get state => _state;

  /// Token of the resource being viewed, used to guard a restore.
  Future<String?> readResourceUpdatedAt() =>
      _runtime.readResourceUpdatedAt(_resourceId);

  /// True while a request is in flight.
  bool get isBusy => _busy;

  /// Loads history for [resourceId]. Re-loading the same resource refreshes it.
  Future<void> load(String resourceId) async {
    // Loads are bound to the resource identity itself: a result (or error)
    // for a resource that is no longer the viewed one is discarded below, so
    // a late A cannot overwrite B.
    _resourceId = resourceId;
    _emit(
      _state.copyWith(
        status: ResourceRevisionViewStatus.loading,
        resourceId: resourceId,
        clearMessages: true,
      ),
    );
    try {
      final items = await _runtime.listHistory(
        resourceId,
        limit: historyLimit,
      );
      if (_disposed || _resourceId != resourceId) return;
      _emit(
        _state.copyWith(
          status: ResourceRevisionViewStatus.ready,
          resourceId: resourceId,
          items: items,
          canRestore: true,
        ),
      );
    } catch (error) {
      if (_disposed || _resourceId != resourceId) return;
      _emit(
        _state.copyWith(
          status: ResourceRevisionViewStatus.error,
          resourceId: resourceId,
          errorMessage: resourceStudioUserMessage(error),
          items: const <ResourceRevisionItem>[],
        ),
      );
    }
  }

  Future<void> refresh() => load(_resourceId);

  /// Restores one revision and refreshes the list.
  ///
  /// Guards against a double tap: a second restore while one is in flight is
  /// dropped instead of racing the first. The post-restore refresh is bound to
  /// the resource that was current when the restore started; if the panel
  /// switched resources meanwhile, the outcome message is not published onto
  /// the wrong resource's state (the restore itself is keyed by revision id
  /// and stays committed — it is reconciled by reloading, never faked back).
  Future<RevisionRestoreSummary?> restore(
    String revisionId, {
    String expectedUpdatedAt = '',
  }) async {
    if (_busy || !_state.canRestore) return null;
    final viewedResource = _resourceId;
    _busy = true;
    _emit(_state.copyWith(canRestore: false, clearMessages: true));
    try {
      final summary = await _runtime.restoreRevision(
        revisionId,
        expectedUpdatedAt: expectedUpdatedAt,
      );
      final items = await _runtime.listHistory(
        _resourceId,
        limit: historyLimit,
      );
      if (_disposed) return summary;
      final switched = _resourceId != viewedResource;
      _emit(
        _state.copyWith(
          status: ResourceRevisionViewStatus.ready,
          items: items,
          // A restore outcome belongs to the resource it was started for;
          // after a resource switch only the refreshed list is published.
          statusMessage:
              switched ? '' : resourceStudioUserMessage(summary.message),
          canRestore: true,
        ),
      );
      return summary;
    } catch (error) {
      if (_disposed || _resourceId != viewedResource) return null;
      _emit(
        _state.copyWith(
          status: ResourceRevisionViewStatus.error,
          errorMessage: '恢复失败：${resourceStudioUserMessage(error)}',
          canRestore: true,
        ),
      );
      return null;
    } finally {
      _busy = false;
    }
  }

  void clearStatusMessage() {
    if (_state.statusMessage.isEmpty && _state.errorMessage.isEmpty) return;
    _emit(_state.copyWith(clearMessages: true));
  }

  void _emit(ResourceRevisionViewState next) {
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
