import 'package:flutter/foundation.dart';

import '../../../../../domain/resources/resource_contracts.dart';
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

  ResourceLibraryViewState get state => _state;

  Future<void> load() async {
    _setState(_state.copyWith(
      status: ResourceLibraryStatus.loading,
      errorMessage: '',
    ));
    try {
      final items = await _runtime.load(_mode);
      _setState(_state.copyWith(
        status: ResourceLibraryStatus.ready,
        items: items,
        errorMessage: '',
      ));
    } catch (_) {
      _setState(_state.copyWith(
        status: ResourceLibraryStatus.error,
        errorMessage: '资源库加载失败，请重试',
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
        errorMessage: '资源创建失败，请重试',
      ));
      return null;
    }
  }

  void _setState(ResourceLibraryViewState state) {
    _state = state;
    notifyListeners();
  }
}
