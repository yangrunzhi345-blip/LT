import 'adventure_runtime_state.dart';

/// A read-only, branch-local projection of all accepted runtime changes
/// associated with one dialogue turn.
final class TurnStateChangeGroup {
  final int adventureId;
  final int branchId;
  final String turnId;
  final int turnRowId;
  final int turnNumber;
  final String requestId;
  final String? assistantMessageId;
  final DateTime occurredAt;
  final int revisionStart;
  final int revisionEnd;
  final List<TurnStateChange> changes;

  const TurnStateChangeGroup({
    required this.adventureId,
    required this.branchId,
    required this.turnId,
    required this.turnRowId,
    required this.turnNumber,
    required this.requestId,
    required this.occurredAt,
    required this.revisionStart,
    required this.revisionEnd,
    required this.changes,
    this.assistantMessageId,
  });

  int get changeCount => changes.length;
  bool get hasChanges => changes.isNotEmpty;
}

final class TurnStateChange {
  final RuntimeEntityType entityType;
  final String entityId;
  final String path;
  final Object? before;
  final Object? after;
  final String reason;
  final String commitId;
  final int revision;
  final String? sourceMessageId;
  final String causeType;
  final bool isLegacy;

  const TurnStateChange({
    required this.entityType,
    required this.entityId,
    required this.path,
    required this.before,
    required this.after,
    required this.reason,
    required this.commitId,
    required this.revision,
    required this.causeType,
    this.sourceMessageId,
    this.isLegacy = false,
  });
}
