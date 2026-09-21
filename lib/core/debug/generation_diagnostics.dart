import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Debug/profile-only structured tracing for the streaming resource generation
/// pipeline (P0 freeze investigation).
///
/// Every Part lifecycle boundary in the production path records a monotonic
/// marker here, plus two independent heartbeats that let a real-device freeze
/// be classified into one of four cases:
///
/// - CASE 1: UI heartbeat AND runtime heartbeat stop -> main isolate
///   starvation (synchronous infinite work).
/// - CASE 2: UI heartbeat alive, runtime heartbeat stopped -> generation
///   Future/DB/network/scheduler stall.
/// - CASE 3: runtime heartbeat alive, UI heartbeat stopped -> Flutter
///   layout/render/event queue starvation.
/// - CASE 4: both alive but input dead -> pointer/modal interception bug.
///
/// The watchdog dumps the last markers, heartbeat ages, durations, counters
/// and caller-registered state snapshots without ever mutating generation
/// data. Everything is a no-op in release builds.
final class GenerationDiagnostics {
  GenerationDiagnostics._();

  static final GenerationDiagnostics instance = GenerationDiagnostics._();

  /// Tracing is active in debug and profile builds only.
  static bool get enabled => kDebugMode || kProfileMode;

  /// Console printing gate for tests: markers/counters stay recorded even
  /// when printing is off, so high-volume soak runs keep test output sane.
  static bool printingEnabled = true;

  static const int _maxMarkers = 2000;
  static const int _dumpTailMarkers = 120;

  final Stopwatch _clock = Stopwatch()..start();

  final Queue<String> _markers = Queue<String>();
  final Map<String, int> _counters = <String, int>{};
  final Map<String, List<Duration>> _durations = <String, List<Duration>>{};

  Duration _lastUiHeartbeat = Duration.zero;
  int _uiHeartbeatTicks = 0;
  int _uiHeartbeatOwners = 0;
  Timer? _uiHeartbeatTimer;
  Duration _uiHeartbeatInterval = const Duration(milliseconds: 250);

  Duration _lastRuntimeHeartbeat = Duration.zero;
  String _lastRuntimeStage = '';
  int _runtimeHeartbeatSeq = 0;

  final Set<String> _activeRuns = <String>{};

  Timer? _watchdogTimer;
  Duration _stallThreshold = const Duration(seconds: 10);

  /// Starts the periodic watchdog that dumps diagnostics when the runtime
  /// heartbeat stalls (generation side) or the UI heartbeat shows a gap
  /// (isolate was blocked and recovered). Idempotent. Never mutates
  /// generation data.
  void startWatchdog({
    Duration interval = const Duration(seconds: 5),
    Duration stallThreshold = const Duration(seconds: 10),
  }) {
    if (!enabled) return;
    _stallThreshold = stallThreshold;
    if (_watchdogTimer != null) return;
    _watchdogTimer = Timer.periodic(interval, (_) {
      final now = _now;
      final runtimeAge = now - _lastRuntimeHeartbeat;
      if (_activeRuns.isNotEmpty && runtimeAge > _stallThreshold) {
        if (_runtimeStallDumped) return;
        _runtimeStallDumped = true;
        dump(
          reason: 'RUNTIME_HEARTBEAT_STALLED '
              'age=${_formatElapsed(runtimeAge)} '
              'lastStage=$_lastRuntimeStage',
        );
      }
      // UI gaps are detected inside the UI heartbeat tick itself (a frozen
      // isolate cannot run the watchdog either); nothing to check here.
    });
  }

  /// Caller-registered state snapshots included in every dump (scheduler
  /// queues, coordinator in-flight maps, service run counters...). Providers
  /// must be cheap and non-mutating.
  final Map<String, Map<String, Object?> Function()> _snapshotProviders =
      <String, Map<String, Object?> Function()>{};

  Duration get _now => _clock.elapsed;

  String _formatElapsed(Duration d) =>
      '${(d.inMicroseconds / 1000).toStringAsFixed(1)}ms';

  // ─── Markers ───

  /// Records a lifecycle marker (and prints it in debug/profile so the last
  /// line before a real-device freeze identifies the frozen boundary).
  void mark(String label, [Map<String, Object?>? details]) {
    if (!enabled) return;
    final buffer = StringBuffer('[gen-diag +${_formatElapsed(_now)}] $label');
    if (details != null && details.isNotEmpty) {
      buffer.write(' {');
      buffer.write(
        details.entries.map((e) => '${e.key}: ${e.value}').join(', '),
      );
      buffer.write('}');
    }
    final line = buffer.toString();
    _markers.addLast(line);
    while (_markers.length > _maxMarkers) {
      _markers.removeFirst();
    }
    if (printingEnabled) debugPrint(line);
  }

  // ─── Heartbeats ───

  /// Runtime heartbeat: called at every major await boundary of the
  /// generation pipeline. Cheap (counter + timestamp only).
  void runtimeHeartbeat(String stage) {
    if (!enabled) return;
    _lastRuntimeHeartbeat = _now;
    _lastRuntimeStage = stage;
    _runtimeHeartbeatSeq++;
    _runtimeStallDumped = false;
  }

  bool _runtimeStallDumped = false;

  /// Starts the UI-isolate heartbeat (250ms timer ticks). Idempotent and
  /// ref-counted so multiple pages can own it.
  void startUiHeartbeat(
      {Duration interval = const Duration(milliseconds: 250)}) {
    if (!enabled) return;
    _uiHeartbeatOwners++;
    _uiHeartbeatInterval = interval;
    _uiHeartbeatTimer ??= Timer.periodic(interval, (_) {
      // Freeze detection: if this tick ran long after the previous one, the
      // main isolate was blocked in between (frames, input and timers all
      // stalled together). Dump on recovery so the gap is measurable.
      final now = _now;
      if (_uiHeartbeatTicks > 0 &&
          now - _lastUiHeartbeat > _uiHeartbeatInterval * 4) {
        dump(
          reason: 'UI_HEARTBEAT_GAP '
              'age=${_formatElapsed(now - _lastUiHeartbeat)} '
              '(main isolate was blocked; check the last marker printed '
              'before this gap)',
        );
      }
      _uiHeartbeatTicks++;
      _lastUiHeartbeat = now;
    });
  }

  void stopUiHeartbeat() {
    if (!enabled) return;
    _uiHeartbeatOwners = _uiHeartbeatOwners > 0 ? _uiHeartbeatOwners - 1 : 0;
    if (_uiHeartbeatOwners == 0) {
      _uiHeartbeatTimer?.cancel();
      _uiHeartbeatTimer = null;
    }
  }

  // ─── Counters and durations ───

  void counter(String key, [int delta = 1]) {
    if (!enabled) return;
    _counters[key] = (_counters[key] ?? 0) + delta;
  }

  /// Tracks a high-water mark (queue depths, SSE pending backlog...).
  void observeMax(String key, int value) {
    if (!enabled) return;
    final current = _counters[key] ?? 0;
    if (value > current) _counters[key] = value;
  }

  void setCounter(String key, int value) {
    if (!enabled) return;
    _counters[key] = value;
  }

  /// Test seam: current value of one counter (0 when never recorded).
  int counterValue(String key) => _counters[key] ?? 0;

  /// Records one duration sample for a named pipeline step (commit stages,
  /// revision capture steps, validation...).
  void recordDuration(String key, Duration duration) {
    if (!enabled) return;
    final samples = _durations.putIfAbsent(key, () => <Duration>[]);
    samples.add(duration);
    if (samples.length > 64) samples.removeAt(0);
  }

  // ─── Runs and snapshots ───

  void beginRun(String label) {
    if (!enabled) return;
    _activeRuns.add(label);
  }

  void endRun(String label) {
    if (!enabled) return;
    _activeRuns.remove(label);
    // Idle means no reason to keep the watchdog timer alive: a widget test
    // that pumped a full generation must not end with a pending timer.
    if (_activeRuns.isEmpty) {
      _watchdogTimer?.cancel();
      _watchdogTimer = null;
    }
  }

  void registerSnapshotProvider(
    String name,
    Map<String, Object?> Function() provider,
  ) {
    if (!enabled) return;
    _snapshotProviders[name] = provider;
  }

  void unregisterSnapshotProvider(String name) {
    if (!enabled) return;
    _snapshotProviders.remove(name);
  }

  // ─── Dumping ───

  /// Builds (and prints) a full diagnostic dump. Never mutates generation
  /// state; used by the stall watchdog and available to tests.
  String dump({required String reason}) {
    if (!enabled) return '';
    final report = StringBuffer()
      ..writeln('==== GENERATION DIAGNOSTICS DUMP ====')
      ..writeln('reason: $reason')
      ..writeln('uptime: ${_formatElapsed(_now)}')
      ..writeln('activeRuns: $_activeRuns');

    final uiAge = _now - _lastUiHeartbeat;
    final runtimeAge = _now - _lastRuntimeHeartbeat;
    report
      ..writeln('uiHeartbeat: ticks=$_uiHeartbeatTicks, '
          'interval=${_uiHeartbeatInterval.inMilliseconds}ms, '
          'age=${_formatElapsed(uiAge)}')
      ..writeln('runtimeHeartbeat: seq=$_runtimeHeartbeatSeq, '
          'lastStage=$_lastRuntimeStage, age=${_formatElapsed(runtimeAge)}')
      ..writeln('-- durations --');
    for (final entry in _durations.entries) {
      var max = Duration.zero;
      var sum = Duration.zero;
      for (final sample in entry.value) {
        if (sample > max) max = sample;
        sum += sample;
      }
      final last = entry.value.last;
      report.writeln('${entry.key}: n=${entry.value.length}, '
          'last=${_formatElapsed(last)}, max=${_formatElapsed(max)}, '
          'avg=${_formatElapsed(sum ~/ entry.value.length)}');
    }
    report.writeln('-- counters --');
    for (final entry in _counters.entries) {
      report.writeln('${entry.key}: ${entry.value}');
    }
    for (final entry in _snapshotProviders.entries) {
      try {
        report.writeln('-- snapshot[${entry.key}] --');
        report.writeln(entry.value());
      } catch (error) {
        report.writeln('snapshot[${entry.key}] failed: $error');
      }
    }
    report.writeln('-- last markers --');
    final tail = _markers.toList(growable: false);
    final start =
        tail.length > _dumpTailMarkers ? tail.length - _dumpTailMarkers : 0;
    for (var i = start; i < tail.length; i++) {
      report.writeln(tail[i]);
    }
    report.writeln('==== END DUMP ====');
    final text = report.toString();
    if (printingEnabled) debugPrint(text, wrapWidth: 240);
    _dumpReasons.add(reason);
    while (_dumpReasons.length > 32) {
      _dumpReasons.removeAt(0);
    }
    return text;
  }

  final List<String> _dumpReasons = <String>[];

  /// Test seam: reasons of the most recent diagnostic dumps.
  List<String> get dumpReasons => List<String>.unmodifiable(_dumpReasons);

  /// Clears recorded markers/counters/durations between tests.
  void resetForTesting() {
    _markers.clear();
    _counters.clear();
    _durations.clear();
    _dumpReasons.clear();
    _activeRuns.clear();
    _runtimeStallDumped = false;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
  }

  /// Test/inspection seam: the raw marker tail.
  List<String> markerTail([int count = 50]) {
    final markers = _markers.toList(growable: false);
    final start = markers.length > count ? markers.length - count : 0;
    return markers.sublist(start);
  }

  int get uiHeartbeatTicks => _uiHeartbeatTicks;
  int get runtimeHeartbeatSeq => _runtimeHeartbeatSeq;
}
