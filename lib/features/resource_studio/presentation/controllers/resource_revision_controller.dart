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
      _emit(
        _state.copyWith(
          status: ResourceRevisionViewStatus.ready,
          resourceId: resourceId,
          items: items,
          canRestore: true,
        ),
      );
    } catch (error) {
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
  /// dropped instead of racing the first.
  Future<RevisionRestoreSummary?> restore(
    String revisionId, {
    String expectedUpdatedAt = '',
  }) async {
    if (_busy || !_state.canRestore) return null;
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
      _emit(
        _state.copyWith(
          status: ResourceRevisionViewStatus.ready,
          items: items,
          statusMessage: resourceStudioUserMessage(summary.message),
          canRestore: true,
        ),
      );
      return summary;
    } catch (error) {
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
