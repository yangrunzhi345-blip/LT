import 'dart:async';
import 'dart:collection';

import '../../domain/resources/section_control_events.dart';

/// One published event together with its monotonic position in the bus.
final class SectionControlEventRecord {
  const SectionControlEventRecord({
    required this.sequence,
    required this.event,
    required this.recordedAt,
  });

  /// 1-based, strictly increasing across the lifetime of the bus.
  final int sequence;

  final SectionControlEvent event;
  final DateTime recordedAt;

  @override
  String toString() =>
      'SectionControlEventRecord(#$sequence, ${event.eventName})';
}

/// Broadcasts section-control events and keeps a bounded, ordered history.
///
/// The bus is the single place that assigns ordering, which makes the event
/// stream traceable (every event has a sequence), recoverable (a caller can
/// inspect what already happened without re-reading the database) and testable
/// (stream assertions do not depend on wall-clock ordering).
///
/// The history is bounded so a long generation session cannot grow memory
/// without limit; it is a diagnostic/replay window, not an audit log. Durable
/// history belongs to Phase 9 revisions.
final class SectionControlEventBus {
  SectionControlEventBus({this.historyLimit = 200})
      : assert(historyLimit > 0, 'historyLimit must be positive');

  final int historyLimit;

  final StreamController<SectionControlEvent> _controller =
      StreamController<SectionControlEvent>.broadcast();
  final Queue<SectionControlEventRecord> _history =
      Queue<SectionControlEventRecord>();
  int _sequence = 0;
  bool _disposed = false;

  Stream<SectionControlEvent> get stream => _controller.stream;

  /// Events published so far, oldest first, capped at [historyLimit].
  List<SectionControlEventRecord> get history =>
      List<SectionControlEventRecord>.unmodifiable(_history);

  int get lastSequence => _sequence;

  /// Publishes [event] and returns its ordered record.
  ///
  /// Publishing after [dispose] is a no-op for the stream but still returns a
  /// record, so a late event from an in-flight task cannot throw inside a
  /// service command.
  SectionControlEventRecord publish(SectionControlEvent event) {
    final record = SectionControlEventRecord(
      sequence: ++_sequence,
      event: event,
      recordedAt: DateTime.now(),
    );
    _history.addLast(record);
    while (_history.length > historyLimit) {
      _history.removeFirst();
    }
    if (!_disposed) _controller.add(event);
    return record;
  }

  void dispose() {
    _disposed = true;
    unawaited(_controller.close());
  }
}
