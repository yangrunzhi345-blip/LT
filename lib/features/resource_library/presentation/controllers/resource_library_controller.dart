import 'package:flutter/foundation.dart';

import '../../../../../models/resource_library_mode.dart';
import '../../application/use_cases/resource_library_runtime.dart';
import '../../domain/models/resource_library_view_state.dart';

import '../resolvers/resource_presentation_resolver.dart';

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

  void search(String query) =>
      _setState(_state.copyWith(query: query, page: 1));

  void filter(ResourceLibraryFilter filter) =>
      _setState(_state.copyWith(filter: filter, page: 1));

  void filterStatus(ResourceStatusFilter statusFilter) =>
      _setState(_state.copyWith(statusFilter: statusFilter, page: 1));

  void changeSort(ResourceSortOption sortOption) =>
      _setState(_state.copyWith(sortOption: sortOption, page: 1));

  void setPage(int page) =>
      _setState(_state.copyWith(page: page.clamp(1, _state.totalPages)));

  void previousPage() {
    if (_state.currentPage > 1) {
      setPage(_state.currentPage - 1);
    }
  }

  void nextPage() {
    if (_state.currentPage < _state.totalPages) {
      setPage(_state.currentPage + 1);
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
