import 'package:flutter/foundation.dart';

import '../../application/use_cases/resource_trash_runtime.dart';
import '../../domain/models/resource_trash_view_state.dart';
import '../../../../core/localization/app_error_localizer.dart';

/// View-model of the recycle-bin sheet.
///
/// Holds no business rule: it lists, restores and purges through the runtime,
/// and reports the placement message so a fallback restore is shown to the user
/// instead of being applied silently.
final class ResourceTrashController extends ChangeNotifier {
  ResourceTrashController({required ResourceTrashRuntime runtime})
      : _runtime = runtime;

  final ResourceTrashRuntime _runtime;

  ResourceTrashViewState _state = const ResourceTrashViewState.initial();
  bool _disposed = false;
  bool _busy = false;
  int _loadGeneration = 0;

  ResourceTrashViewState get state => _state;

  bool get isBusy => _busy;

  /// Loads the bin and runs one retention pass over already-expired entries.
  ///
  /// The pass runs here — when the user is looking at the bin — rather than at
  /// application start, so a retention bug cannot silently delete data the user
  /// never opened a screen for.
  Future<void> load() async {
    if (_disposed || _busy) return;
    final generation = ++_loadGeneration;
    _emit(
      _state.copyWith(
        status: ResourceTrashViewStatus.loading,
        clearMessages: true,
      ),
    );
    try {
      await _runtime.purgeExpired();
      final items = await _runtime.list();
      if (!_isCurrentLoad(generation)) return;
      _emit(
        _state.copyWith(
          status: ResourceTrashViewStatus.ready,
          items: items,
          busyTrashId: '',
        ),
      );
    } catch (error) {
      if (!_isCurrentLoad(generation)) return;
      _emit(
        _state.copyWith(
          status: ResourceTrashViewStatus.error,
          errorMessage: error.toString(),
          error: asAppDomainError(error),
          errorKind: ResourceTrashErrorKind.load,
          items: const <ResourceTrashItem>[],
        ),
      );
    }
  }

  Future<void> refresh() => load();

  /// Restores one entry. A second tap while one is in flight is dropped.
  Future<TrashRestoreSummary?> restore(String trashId) async {
    if (_busy) return null;
    _busy = true;
    _loadGeneration++;
    _emit(_state.copyWith(busyTrashId: trashId, clearMessages: true));
    try {
      final summary = await _runtime.restore(trashId);
      final items = await _runtime.list();
      _emit(
        _state.copyWith(
          status: ResourceTrashViewStatus.ready,
          items: items,
          notice: ResourceTrashNotice(
            kind: ResourceTrashNoticeKind.restored,
            placement: summary.placement,
          ),
          busyTrashId: '',
        ),
      );
      return summary;
    } catch (error) {
      _emit(
        _state.copyWith(
          status: ResourceTrashViewStatus.error,
          errorMessage: error.toString(),
          error: asAppDomainError(error),
          errorKind: ResourceTrashErrorKind.restore,
          busyTrashId: '',
        ),
      );
      return null;
    } finally {
      _busy = false;
    }
  }

  /// Permanently deletes one entry. Callers must have confirmed with the user
  /// first; this method does not ask.
  Future<bool> permanentDelete(String trashId) async {
    if (_busy) return false;
    _busy = true;
    _loadGeneration++;
    _emit(_state.copyWith(busyTrashId: trashId, clearMessages: true));
    try {
      await _runtime.permanentDelete(trashId);
      final items = await _runtime.list();
      _emit(
        _state.copyWith(
          status: ResourceTrashViewStatus.ready,
          items: items,
          notice: const ResourceTrashNotice(
            kind: ResourceTrashNoticeKind.permanentlyDeleted,
          ),
          busyTrashId: '',
        ),
      );
      return true;
    } catch (error) {
      _emit(
        _state.copyWith(
          status: ResourceTrashViewStatus.error,
          errorMessage: error.toString(),
          error: asAppDomainError(error),
          errorKind: ResourceTrashErrorKind.permanentDelete,
          busyTrashId: '',
        ),
      );
      return false;
    } finally {
      _busy = false;
    }
  }

  void _emit(ResourceTrashViewState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  bool _isCurrentLoad(int generation) =>
      !_disposed && generation == _loadGeneration;

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration++;
    _runtime.dispose();
    super.dispose();
  }
}
