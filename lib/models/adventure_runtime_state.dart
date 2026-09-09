import 'dart:collection';

/// Long-lived, branch-local facts that overlay an adventure's frozen source.
///
/// These types intentionally contain only deltas. Character cards and world
/// snapshots remain the immutable baseline and are never copied into runtime.
enum RuntimeEntityType {
  character,
  npc,
  faction,
  location,
  relationship,
  world
}

enum RuntimeChangeKind { primary, derived }

enum RuntimeChangeOperation { set, remove, appendUnique, increment }

final class RuntimeStateChangeProposal {
  static const int maximumChangesPerTurn = 32;
  static const Set<String> allowedPaths = {
    'life_status',
    'affinity',
    'relationship',
    'faction_id',
    'former_faction_id',
    'goal',
    'controller_id',
    'lifecycle_status',
    'status',
  };

  final RuntimeEntityType entityType;
  final String entityId;
  final RuntimeChangeKind changeKind;
  final RuntimeChangeOperation operation;
  final String path;
  final Object? value;
  final String reason;

  const RuntimeStateChangeProposal({
    required this.entityType,
    required this.entityId,
    required this.changeKind,
    required this.operation,
    required this.path,
    required this.value,
    required this.reason,
  });

  static List<RuntimeStateChangeProposal> parse(
    Object? raw, {
    required List<String> diagnostics,
  }) {
    if (raw == null) return const [];
    if (raw is! List) {
      diagnostics.add('runtime_state_changes:type');
      return const [];
    }
    final proposals = <RuntimeStateChangeProposal>[];
    for (final item in raw.take(maximumChangesPerTurn)) {
      if (item is! Map) {
        diagnostics.add('runtime_state_changes:item');
        continue;
      }
      final value = Map<String, Object?>.from(item);
      final entityType = RuntimeEntityType.values
          .where(
            (candidate) => candidate.name == value['entity_type']?.toString(),
          )
          .firstOrNull;
      final kind = RuntimeChangeKind.values
          .where(
            (candidate) => candidate.name == value['change_kind']?.toString(),
          )
          .firstOrNull;
      final operation = RuntimeChangeOperation.values
          .where(
            (candidate) => candidate.name == value['operation']?.toString(),
          )
          .firstOrNull;
      final entityId = value['entity_id']?.toString().trim() ?? '';
      final path = value['path']?.toString().trim() ?? '';
      final reason = value['reason']?.toString().trim() ?? '';
      if (entityType == null ||
          kind == null ||
          operation == null ||
          !_isIdentifier(entityId) ||
          !allowedPaths.contains(path) ||
          reason.isEmpty ||
          reason.length > 500 ||
          !_isSafeValue(value['value'])) {
        diagnostics.add('runtime_state_changes:invalid');
        continue;
      }
      proposals.add(RuntimeStateChangeProposal(
        entityType: entityType,
        entityId: entityId,
        changeKind: kind,
        operation: operation,
        path: path,
        value: _copyValue(value['value']),
        reason: reason,
      ));
    }
    if (raw.length > maximumChangesPerTurn) {
      diagnostics.add('runtime_state_changes:limit');
    }
    return List.unmodifiable(proposals);
  }

  static bool _isIdentifier(String value) =>
      value.isNotEmpty &&
      value.length <= 200 &&
      RegExp(r'^[A-Za-z0-9_.:-]+$').hasMatch(value);

  static bool _isSafeValue(Object? value, [int depth = 0]) {
    if (depth > 3) return false;
    if (value == null || value is bool || value is num) return true;
    if (value is String) return value.length <= 1000;
    if (value is List) return false;
    if (value is Map) {
      if (value.length > 20) return false;
      return value.entries.every((entry) =>
          entry.key is String &&
          (entry.key as String).length <= 100 &&
          _isSafeValue(entry.value, depth + 1));
    }
    return false;
  }

  static Object? _copyValue(Object? value) => value is Map
      ? UnmodifiableMapView(Map<String, Object?>.from(value))
      : value;
}

final class RuntimeStateCommitDraft {
  final int expectedRevision;
  final List<RuntimeStateChangeProposal> changes;
  final String summary;
  final String? contextSnapshotId;
  final String? sourceMessageId;

  const RuntimeStateCommitDraft({
    required this.expectedRevision,
    required this.changes,
    required this.summary,
    this.contextSnapshotId,
    this.sourceMessageId,
  });
}

final class RuntimeHead {
  final int adventureId;
  final int branchId;
  final int revision;
  final String? headCommitId;

  const RuntimeHead({
    required this.adventureId,
    required this.branchId,
    this.revision = 0,
    this.headCommitId,
  });
}

final class RuntimeEntityState {
  final RuntimeEntityType entityType;
  final String entityId;
  final Map<String, Object?> overlay;
  final String lifecycleStatus;
  final String? lastCommitId;

  RuntimeEntityState({
    required this.entityType,
    required this.entityId,
    Map<String, Object?> overlay = const {},
    this.lifecycleStatus = 'active',
    this.lastCommitId,
  }) : overlay = UnmodifiableMapView(Map<String, Object?>.from(overlay));
}

final class RuntimeHeadConflict implements Exception {
  final int expectedRevision;
  final int currentRevision;
  const RuntimeHeadConflict(this.expectedRevision, this.currentRevision);
}
