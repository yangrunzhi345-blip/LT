import '../../domain/resources/resource_contracts.dart';
import 'resource_revision_service.dart';

/// Runs the revision retention pass at a controlled point.
///
/// Phase 9 shipped `pruneRevisions` with no caller at all, so a revision chain
/// grew forever and every later capture had to replay the whole thing
/// (Phase 9 audit P9-M3). This is the production trigger.
///
/// Design constraints, all of them deliberate:
/// - **no background timer**: cleanup must be observable and must never race a
///   live edit, so it runs from a lifecycle hook the app already has;
/// - **at most one pass per interval** ([minInterval]), because the work is a
///   full chain walk per resource and doing it on every editor switch would be
///   worse than the growth it prevents;
/// - **never throws**: retention is maintenance, and a failure must not break
///   the code path that triggered it. The failure is reported through
///   [lastError] instead;
/// - **never deletes protected history**: the service itself refuses to drop
///   heads, assembly references, recycle-bin references or in-retention
///   revisions — this class only decides *when* to ask.
final class ResourceRevisionMaintenance {
  ResourceRevisionMaintenance({
    required ResourceRevisionService revisionService,
    this.minInterval = const Duration(hours: 6),
  }) : _revisions = revisionService;

  final ResourceRevisionService _revisions;

  /// Shortest gap between two automatic passes in one process.
  final Duration minInterval;

  DateTime? _lastRunAt;

  /// Last failure, for diagnostics. Never rethrown to the caller.
  String lastError = '';

  /// True when [runIfDue] would actually run a pass.
  bool isDue(DateTime now) {
    final last = _lastRunAt;
    if (last == null) return true;
    return now.difference(last) >= minInterval;
  }

  /// Runs a pass when the interval has elapsed, otherwise does nothing.
  ///
  /// Returns null when the pass was skipped or failed.
  Future<RevisionPruneReport?> runIfDue({DateTime? now}) async {
    final clock = now ?? DateTime.now();
    if (!isDue(clock)) return null;
    // Marked before the await so two near-simultaneous triggers cannot both run.
    _lastRunAt = clock;
    try {
      return await _revisions.pruneRevisions(now: clock);
    } catch (error) {
      lastError = '$error';
      return null;
    }
  }

  /// Runs a pass unconditionally, for an explicit maintenance action or a test.
  Future<RevisionPruneReport> run({DateTime? now, ResourceId? resourceId}) {
    _lastRunAt = now ?? DateTime.now();
    return _revisions.pruneRevisions(now: now, resourceId: resourceId);
  }
}
