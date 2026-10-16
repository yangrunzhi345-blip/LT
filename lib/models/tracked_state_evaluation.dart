import 'adventure_runtime_state.dart';

/// Outcome of judging one **mandatory** monitored field for a single turn.
///
/// The sparse settlement protocol reports only fields whose value actually
/// moved, which is correct for optional monitors but cannot distinguish
/// "the model decided nothing changed" from "the model forgot". A critical
/// (`不可忽略项`) monitor therefore has to be *explicitly evaluated* every turn,
/// and an explicit evaluation carries one of three outcomes:
///
/// * [changed] — the story gave evidence the value moved. Requires an
///   `operation` and a `value`; converting it to a [RuntimeStateChangeProposal]
///   still goes through `RuntimeStateValidator`, so an illegal value is a
///   diagnostic, never a silent write.
/// * [unchanged] — the story was examined and the value must stay put. This is
///   explicitly **not** the same as "untriggered": a never-initialized monitor
///   stays untriggered, a monitored-and-unchanged one keeps its current value.
/// * [undetermined] — there was not enough in this turn's narrative to judge.
///   Recorded for traceability and never written.
///
/// Completing an evaluation is not the same as producing a change: `unchanged`
/// and `undetermined` never touch runtime state, and nothing here fabricates a
/// value.
enum TrackedEvaluationStatus {
  changed,
  unchanged,
  undetermined;

  static TrackedEvaluationStatus? fromString(Object? raw) {
    final text = raw?.toString().trim().toLowerCase() ?? '';
    if (text.isEmpty) return null;
    switch (text) {
      case 'changed':
      case 'change':
      case 'true':
      case 'yes':
      case '变化':
      case '有变化':
      case '已变化':
        return TrackedEvaluationStatus.changed;
      case 'unchanged':
      case 'no_change':
      case 'nochange':
      case 'stable':
      case 'false':
      case 'no':
      case '不变':
      case '无变化':
      case '未变化':
        return TrackedEvaluationStatus.unchanged;
      case 'undetermined':
      case 'unknown':
      case 'uncertain':
      case '无法确定':
      case '不确定':
      case '未知':
        return TrackedEvaluationStatus.undetermined;
      default:
        return null;
    }
  }
}

final class TrackedStateEvaluation {
  /// Hard cap mirroring the runtime proposal budget, so a runaway model cannot
  /// force unbounded merging.
  static const int maximumEvaluationsPerTurn =
      RuntimeStateChangeProposal.maximumChangesPerTurn;

  final RuntimeEntityType entityType;
  final String entityId;
  final String definitionId;
  final TrackedEvaluationStatus status;
  final RuntimeChangeOperation? operation;
  final Object? value;
  final String reason;

  const TrackedStateEvaluation({
    required this.entityType,
    required this.entityId,
    required this.definitionId,
    required this.status,
    this.operation,
    this.value,
    this.reason = '',
  });

  /// Stable identity triple used for completeness checks and de-duplication.
  String get key => '${entityType.name}:$entityId:$definitionId';

  bool get isChanged => status == TrackedEvaluationStatus.changed;

  /// Builds the runtime proposal for a `changed` evaluation.
  ///
  /// Returns `null` for `unchanged` / `undetermined`, and for a `changed`
  /// evaluation that is missing a usable operation/value — the caller records a
  /// diagnostic instead of inventing a value.
  RuntimeStateChangeProposal? toProposal() {
    if (!isChanged) return null;
    final op = operation;
    if (op == null) return null;
    if (op == RuntimeChangeOperation.increment) {
      if (value is! num || !(value as num).isFinite) return null;
    } else if (op == RuntimeChangeOperation.set) {
      if (value == null) return null;
    } else {
      return null;
    }
    return RuntimeStateChangeProposal(
      entityType: entityType,
      entityId: entityId,
      changeKind: RuntimeChangeKind.primary,
      operation: op,
      path: RuntimeStateChangeProposal.customAttributePath(definitionId),
      value: value,
      reason: reason.trim().isEmpty ? 'critical monitor evaluation' : reason,
    );
  }

  /// Parses `tracked_evaluations` from a settlement payload.
  ///
  /// Every recoverable problem is reported through [diagnostics]; malformed
  /// entries are skipped rather than throwing.
  static List<TrackedStateEvaluation> parse(
    Object? raw, {
    required List<String> diagnostics,
  }) {
    if (raw == null) return const [];
    if (raw is! List) {
      diagnostics.add('tracked_evaluations:type');
      return const [];
    }
    final result = <TrackedStateEvaluation>[];
    for (final item in raw.take(maximumEvaluationsPerTurn)) {
      if (item is! Map) {
        diagnostics.add('tracked_evaluations:item');
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      final entityType = RuntimeEntityType.values
          .where((candidate) =>
              candidate.name == map['entity_type']?.toString().trim())
          .firstOrNull;
      final entityId =
          (map['entity_id'] ?? map['character_id'])?.toString().trim() ?? '';
      final definitionId =
          (map['monitor_id'] ?? map['attribute_id'])?.toString().trim() ?? '';
      final status = TrackedEvaluationStatus.fromString(map['status']);
      if (entityType == null ||
          !isValidRuntimeEntityId(entityId) ||
          definitionId.isEmpty ||
          status == null) {
        diagnostics.add('tracked_evaluations:invalid');
        continue;
      }
      final operation = RuntimeChangeOperation.values
          .where((candidate) =>
              candidate.name == map['operation']?.toString().trim())
          .firstOrNull;
      result.add(TrackedStateEvaluation(
        entityType: entityType,
        entityId: entityId,
        definitionId: definitionId,
        status: status,
        operation: operation,
        value: map.containsKey('value') ? _copyValue(map['value']) : null,
        reason: map['reason']?.toString().trim() ?? '',
      ));
    }
    if (raw.length > maximumEvaluationsPerTurn) {
      diagnostics.add('tracked_evaluations:limit');
    }
    return List.unmodifiable(result);
  }

  static Object? _copyValue(Object? value) {
    if (value is Map) return Map<String, Object?>.from(value);
    if (value is List) return List<Object?>.from(value);
    return value;
  }
}
