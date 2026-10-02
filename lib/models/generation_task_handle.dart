/// 生成任务句柄与取消注册模型。
library;

class GenerationTaskHandle {
  GenerationTaskHandle({String? taskId, int? generationEpoch})
      : taskId =
            taskId ?? 'generation_${DateTime.now().microsecondsSinceEpoch}',
        generationEpoch =
            generationEpoch ?? DateTime.now().microsecondsSinceEpoch,
        _owner = null,
        _requestId = null;

  GenerationTaskHandle._scoped(this._owner, this._requestId)
      : taskId = _owner!.taskId,
        generationEpoch = _owner.generationEpoch;

  final String taskId;
  final int generationEpoch;
  String get requestId => _requestId ?? taskId;
  final String? _requestId;
  final GenerationTaskHandle? _owner;

  /// Adds subrequest identity while sharing the turn's cancellation authority.
  GenerationTaskHandle forRequest(String requestId) =>
      GenerationTaskHandle._scoped(_owner ?? this, requestId);
  bool _cancelled = false;
  final Set<void Function()> _cancelRequests = {};

  bool get isCancelled => _owner?.isCancelled ?? _cancelled;

  /// Registers one independently cancellable request. Call [dispose] after the
  /// request finishes so a completed request never keeps its transport alive.
  GenerationCancellationRegistration registerCancel(
      void Function() cancelRequest) {
    if (_owner case final owner?) return owner.registerCancel(cancelRequest);
    if (_cancelled) {
      cancelRequest();
      return const GenerationCancellationRegistration._(null, null);
    }
    _cancelRequests.add(cancelRequest);
    return GenerationCancellationRegistration._(_cancelRequests, cancelRequest);
  }

  /// Compatibility entry point for legacy single-request callers.
  void bindCancel(void Function() cancelRequest) {
    registerCancel(cancelRequest);
  }

  Future<void> cancel() async {
    if (_owner case final owner?) return owner.cancel();
    if (_cancelled) return;
    _cancelled = true;
    final requests = List<void Function()>.from(_cancelRequests);
    _cancelRequests.clear();
    for (final cancelRequest in requests) {
      cancelRequest();
    }
  }

  int get activeCancelRequestCount =>
      _owner?.activeCancelRequestCount ?? _cancelRequests.length;
}

class GenerationCancellationRegistration {
  const GenerationCancellationRegistration._(this._requests, this._callback);

  final Set<void Function()>? _requests;
  final void Function()? _callback;

  void dispose() {
    final callback = _callback;
    if (callback != null) _requests?.remove(callback);
  }
}
