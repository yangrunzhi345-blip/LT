import 'dart:async';

import 'package:flutter/foundation.dart';

/// 当前可见页面的刷新状态。
enum PageRefreshStatus { idle, refreshing, success, failure }

/// 由页面刷新回调返回的轻量结果。
class PageRefreshResult {
  const PageRefreshResult._(this.isSuccess, [this.error]);

  const PageRefreshResult.success() : this._(true);
  const PageRefreshResult.failure([String? error]) : this._(false, error);

  final bool isSuccess;
  final String? error;
}

typedef PageRefreshCallback = FutureOr<PageRefreshResult?> Function();

/// 单一的当前页面刷新入口。
///
/// 页面通过 [register] 注册自身回调，侧边栏按钮和下拉手势均调用
/// [refresh]。注册项被替换或移除后，旧页面的异步结果不会再更新状态。
class PageRefreshController extends ChangeNotifier {
  Object? _owner;
  PageRefreshCallback? _callback;
  Future<PageRefreshResult>? _activeTask;

  PageRefreshStatus _status = PageRefreshStatus.idle;
  DateTime? _lastRefreshedAt;
  String? _lastError;
  int _generation = 0;

  PageRefreshStatus get status => _status;
  bool get isRefreshing => _status == PageRefreshStatus.refreshing;
  bool get isAvailable => _callback != null;
  DateTime? get lastRefreshedAt => _lastRefreshedAt;
  String? get lastError => _lastError;

  void register(Object owner, PageRefreshCallback callback) {
    if (identical(_owner, owner) && identical(_callback, callback)) return;
    _owner = owner;
    _callback = callback;
    _generation++;
    _lastError = null;
    if (!isRefreshing) _status = PageRefreshStatus.idle;
    notifyListeners();
  }

  void unregister(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _callback = null;
    _generation++;
    _activeTask = null;
    if (!isRefreshing) _status = PageRefreshStatus.idle;
    notifyListeners();
  }

  Future<PageRefreshResult> refresh() {
    final active = _activeTask;
    if (active != null) return active;
    final callback = _callback;
    if (callback == null) {
      return Future.value(const PageRefreshResult.failure('当前页面无需刷新'));
    }

    final generation = _generation;
    _status = PageRefreshStatus.refreshing;
    _lastError = null;
    notifyListeners();

    late final Future<PageRefreshResult> task;
    task = Future<PageRefreshResult?>.sync(callback).then((result) {
      return result ?? const PageRefreshResult.success();
    }).catchError((Object error, StackTrace stackTrace) {
      debugPrint('[PageRefresh] failed: $error\n$stackTrace');
      return const PageRefreshResult.failure('刷新失败，请稍后重试');
    }).then((result) {
      if (generation == _generation) {
        _status = result.isSuccess
            ? PageRefreshStatus.success
            : PageRefreshStatus.failure;
        _lastError = result.error;
        if (result.isSuccess) _lastRefreshedAt = DateTime.now();
        _activeTask = null;
        notifyListeners();
      }
      return result;
    });
    _activeTask = task;
    return task;
  }
}
