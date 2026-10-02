import 'package:flutter/foundation.dart';

import '../../../../models/resource_library_mode.dart';
import '../../application/use_cases/tracked_state_library_runtime.dart';
import '../../domain/models/tracked_state_library_view_state.dart';
import '../resolvers/resource_presentation_resolver.dart';

/// Loads, searches, filters and sorts the read-only「检测项目」surface.
///
/// It owns no persistence: editing still happens in the owner resource editor,
/// and this controller only reloads the projection afterwards.
final class TrackedStateLibraryController extends ChangeNotifier {
  TrackedStateLibraryController({
    required TrackedStateLibraryRuntime runtime,
    required ResourceLibraryMode mode,
  })  : _runtime = runtime,
        _mode = mode;

  final TrackedStateLibraryRuntime _runtime;
  final ResourceLibraryMode _mode;
  TrackedStateLibraryViewState _state = const TrackedStateLibraryViewState();
  int _requestGeneration = 0;
  bool _disposed = false;

  TrackedStateLibraryViewState get state => _state;

  Future<void> load() async {
    final requestGeneration = ++_requestGeneration;
    _setState(_state.copyWith(status: TrackedStateLibraryStatus.loading));
    try {
      final entries = await _runtime.load(_mode);
      if (!_isCurrent(requestGeneration)) return;
      _setState(_state.copyWith(
        status: TrackedStateLibraryStatus.ready,
        entries: entries,
      ));
    } catch (_) {
      if (!_isCurrent(requestGeneration)) return;
      _setState(_state.copyWith(status: TrackedStateLibraryStatus.error));
    }
  }

  void search(String query) =>
      _setState(_state.copyWith(query: query, page: 1));

  void filterOwner(TrackedStateOwnerFilter ownerFilter) =>
      _setState(_state.copyWith(ownerFilter: ownerFilter, page: 1));

  void changeSort(ResourceSortOption sortOption) =>
      _setState(_state.copyWith(sortOption: sortOption, page: 1));

  void setPage(int page) =>
      _setState(_state.copyWith(page: page.clamp(1, _state.totalPages)));

  void previousPage() {
    if (_state.currentPage > 1) setPage(_state.currentPage - 1);
  }

  void nextPage() {
    if (_state.currentPage < _state.totalPages) {
      setPage(_state.currentPage + 1);
    }
  }

  void _setState(TrackedStateLibraryViewState state) {
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
