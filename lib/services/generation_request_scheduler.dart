import 'dart:async';

import '../core/debug/generation_diagnostics.dart';
import 'api_error.dart';

/// Bounded, process-wide admission control for model requests.
///
/// A permit covers one actual HTTP attempt only. Retry backoff happens after a
/// permit is released so a temporarily throttled request cannot starve other
/// queued work.
class GenerationConcurrencyPolicy {
  const GenerationConcurrencyPolicy();

  int maximumConcurrentModelRequestsGlobally() => 2;

  int maximumConcurrentModelRequests(String providerId) {
    switch (providerId) {
      case 'deepseek':
        return 2;
      case 'custom':
      case '':
      default:
        return 1;
    }
  }
}

class GenerationRequestScheduler {
  GenerationRequestScheduler({
    this.policy = const GenerationConcurrencyPolicy(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    // Make queue state visible to the generation watchdog dump (P0).
    GenerationDiagnostics.instance.registerSnapshotProvider(
      'scheduler',
      debugSnapshot,
    );
  }

  static final shared = GenerationRequestScheduler();

  final GenerationConcurrencyPolicy policy;
  final DateTime Function() _clock;
  final Map<String, _ProviderRequestQueue> _queues = {};
  late final _globalQueue = _ProviderRequestQueue(
    maximum: policy.maximumConcurrentModelRequestsGlobally(),
    clock: _clock,
  );

  Future<T> schedule<T>({
    required String providerId,
    required Future<T> Function() request,
  }) async {
    final queue = _queues.putIfAbsent(
      providerId,
      () => _ProviderRequestQueue(
        maximum: policy.maximumConcurrentModelRequests(providerId),
        clock: _clock,
      ),
    );
    await queue.acquire();
    await _globalQueue.acquire();
    try {
      return await request();
    } on ApiError catch (error) {
      if (error.type == ApiErrorType.rateLimited) {
        queue.recordRateLimit(Duration(milliseconds: error.retryAfterMs));
      }
      rethrow;
    } finally {
      _globalQueue.release();
      queue.release();
    }
  }

  int activeRequests(String providerId) => _queues[providerId]?.active ?? 0;

  int effectiveLimit(String providerId) =>
      _queues[providerId]?.effectiveLimit ??
      policy.maximumConcurrentModelRequests(providerId);

  /// Debug/diagnostic seam (P0): waiter backlog per queue, so a permit leak or
  /// a waiter accumulating after cancellation is observable. Never grows
  /// across completed parts in a healthy run.
  int waiterCount(String providerId) => _queues[providerId]?.waiterCount ?? 0;

  int get activeRequestsGlobally => _globalQueue.active;

  int get globalWaiterCount => _globalQueue.waiterCount;

  /// One-shot diagnostic snapshot for the generation watchdog dump.
  Map<String, Object?> debugSnapshot() {
    final providers = <String, Object?>{
      for (final entry in _queues.entries)
        entry.key: <String, Object?>{
          'active': entry.value.active,
          'waiters': entry.value.waiterCount,
          'effectiveLimit': entry.value.effectiveLimit,
          'rateLimitedUntil': entry.value.rateLimitedUntil?.toIso8601String(),
        },
    };
    return <String, Object?>{
      'global': <String, Object?>{
        'active': _globalQueue.active,
        'waiters': _globalQueue.waiterCount,
        'effectiveLimit': _globalQueue.effectiveLimit,
      },
      'providers': providers,
    };
  }
}

class _ProviderRequestQueue {
  _ProviderRequestQueue({required this.maximum, required this.clock});

  final int maximum;
  final DateTime Function() clock;
  final List<Completer<void>> _waiters = [];
  int active = 0;
  DateTime? _rateLimitedUntil;
  Timer? _resumeTimer;

  int get waiterCount => _waiters.length;

  DateTime? get rateLimitedUntil => _rateLimitedUntil;

  int get effectiveLimit {
    final blocked = _rateLimitedUntil?.isAfter(clock()) ?? false;
    return blocked ? 1 : maximum;
  }

  Future<void> acquire() {
    final completer = Completer<void>();
    _waiters.add(completer);
    _drain();
    return completer.future;
  }

  void release() {
    if (active > 0) active--;
    _drain();
  }

  void recordRateLimit(Duration delay) {
    final until = clock().add(delay);
    if (_rateLimitedUntil == null || until.isAfter(_rateLimitedUntil!)) {
      _rateLimitedUntil = until;
    }
    _resumeTimer?.cancel();
    _resumeTimer = Timer(delay, _drain);
    _drain();
  }

  void _drain() {
    if (_rateLimitedUntil?.isBefore(clock()) ?? false) {
      _rateLimitedUntil = null;
    }
    while (_waiters.isNotEmpty && active < effectiveLimit) {
      active++;
      _waiters.removeAt(0).complete();
    }
  }
}
