import 'package:flutter/foundation.dart';

import '../../../../../controllers/resource_crud_controller.dart';
import '../../../../../domain/resources/resource_contracts.dart';
import '../../../../../core/localization/app_error_localizer.dart';
import '../../../../../models/resource_library_mode.dart';
import '../../application/use_cases/resource_library_runtime.dart';
import '../../domain/models/resource_library_view_state.dart';

final class ResourceLibraryController extends ChangeNotifier {
  ResourceLibraryController({
    required ResourceLibraryRuntime runtime,
    required ResourceLibraryMode mode,
  })  : _runtime = runtime,
        _mode = mode;

  final ResourceLibraryRuntime _runtime;
  final ResourceLibraryMode _mode;
  ResourceLibraryViewState _state = const ResourceLibraryViewState.loading();
  int _requestGeneration = 0;
  bool _disposed = false;

  ResourceLibraryViewState get state => _state;

  Future<void> load() async {
    final requestGeneration = ++_requestGeneration;
    _setState(_state.copyWith(
      status: ResourceLibraryStatus.loading,
      clearError: true,
    ));
    try {
      final items = await _runtime.load(_mode);
      if (!_isCurrent(requestGeneration)) return;
      _setState(_state.copyWith(
        status: ResourceLibraryStatus.ready,
        items: items,
        clearError: true,
      ));
    } catch (_) {
      if (!_isCurrent(requestGeneration)) return;
      _setState(_state.copyWith(
        status: ResourceLibraryStatus.error,
        error: ResourceLibraryError.loadFailed,
      ));
    }
  }

  void search(String query) => _setState(_state.copyWith(query: query));

  void filter(ResourceLibraryFilter filter) =>
      _setState(_state.copyWith(filter: filter));

  Future<String?> createManual({
    required ResourceType type,
    required String name,
    required String summary,
  }) async {
    try {
      final id = await _runtime.createManual(
        type: type,
        name: name,
        summary: summary,
        mode: _mode,
      );
      await load();
      return id;
    } catch (_) {
      _setState(_state.copyWith(
        status: ResourceLibraryStatus.error,
        error: ResourceLibraryError.createFailed,
      ));
      return null;
    }
  }

  Future<ResourceOperationResult> moveToTrash(ResourceLibraryItem item) async {
    try {
      return await _runtime.moveToTrash(item: item, mode: _mode);
    } catch (error) {
      return ResourceOperationResult.failure(
        error.toString(),
        error: asAppDomainError(error),
      );
    }
  }

  void _setState(ResourceLibraryViewState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  bool _isCurrent(int requestGeneration) =>
      !_disposed && requestGeneration == _requestGeneration;

  @override
  void dispose() {
    _disposed = true;
    _requestGeneration++;
    super.dispose();
  }
}
