import 'typed_runtime_state.dart';
import 'adventure_runtime_state.dart';

/// A named, branch-local pointer to an immutable runtime revision.
///
/// Checkpoints deliberately contain no state payload. The revision is always
/// replayed through the runtime commit archive when a state projection is
/// needed.
final class RuntimeStateCheckpoint {
  static const maxNameLength = 100;
  static const maxNoteLength = 500;

  final String id;
  final int adventureId;
  final int branchId;
  final int revision;
  final String name;
  final String note;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RuntimeStateCheckpoint({
    required this.id,
    required this.adventureId,
    required this.branchId,
    required this.revision,
    required this.name,
    this.note = '',
    required this.createdAt,
    required this.updatedAt,
  });
}

final class RuntimeStateComparisonEntity {
  final RuntimeEntityType entityType;
  final String entityId;
  final List<RuntimeStateComparisonDiff> diffs;

  const RuntimeStateComparisonEntity({
    required this.entityType,
    required this.entityId,
    required this.diffs,
  });
}

final class RuntimeStateComparisonDiff {
  final RuntimeEntityType entityType;
  final String entityId;
  final String path;
  final Object? before;
  final Object? after;
  final bool beforePresent;
  final bool afterPresent;

  const RuntimeStateComparisonDiff({
    required this.entityType,
    required this.entityId,
    required this.path,
    required this.before,
    required this.after,
    this.beforePresent = true,
    this.afterPresent = true,
  });

  bool get isAdded => !beforePresent && afterPresent;
  bool get isRemoved => beforePresent && !afterPresent;
}

/// Pure read model for comparing two replay projections.
final class RuntimeStateComparison {
  final int fromRevision;
  final int toRevision;
  final List<RuntimeStateComparisonEntity> entityGroups;

  const RuntimeStateComparison({
    required this.fromRevision,
    required this.toRevision,
    required this.entityGroups,
  });

  List<RuntimeStateComparisonDiff> get diffs => [
        for (final group in entityGroups) ...group.diffs,
      ];

  int get changeCount => diffs.length;

  factory RuntimeStateComparison.fromSnapshots(
    RuntimeStateSnapshot from,
    RuntimeStateSnapshot to,
  ) {
    final keys = {...from.entities.keys, ...to.entities.keys}.toList()..sort();
    final groups = <RuntimeStateComparisonEntity>[];
    for (final key in keys) {
      final before = from.entities[key]?.overlay ?? const <String, Object?>{};
      final after = to.entities[key]?.overlay ?? const <String, Object?>{};
      final type =
          to.entities[key]?.entityType ?? from.entities[key]?.entityType;
      if (type == null) {
        continue;
      }
      final entityId =
          to.entities[key]?.entityId ?? from.entities[key]!.entityId;
      final paths = {...before.keys, ...after.keys}.toList()..sort();
      final diffs = <RuntimeStateComparisonDiff>[];
      for (final path in paths) {
        final beforePresent = before.containsKey(path);
        final afterPresent = after.containsKey(path);
        final beforeValue = before[path];
        final afterValue = after[path];
        if (beforePresent == afterPresent &&
            _valuesEqual(beforeValue, afterValue)) {
          continue;
        }
        diffs.add(RuntimeStateComparisonDiff(
          entityType: type,
          entityId: entityId,
          path: path,
          before: beforePresent ? beforeValue : null,
          after: afterPresent ? afterValue : null,
          beforePresent: beforePresent,
          afterPresent: afterPresent,
        ));
      }
      if (diffs.isNotEmpty) {
        groups.add(RuntimeStateComparisonEntity(
          entityType: type,
          entityId: entityId,
          diffs: List.unmodifiable(diffs),
        ));
      }
    }
    return RuntimeStateComparison(
      fromRevision: from.revision,
      toRevision: to.revision,
      entityGroups: List.unmodifiable(groups),
    );
  }

  static bool _valuesEqual(Object? left, Object? right) {
    if (identical(left, right)) return true;
    if (left is Map && right is Map) {
      if (left.length != right.length) return false;
      return left.keys.every((key) =>
          right.containsKey(key) && _valuesEqual(left[key], right[key]));
    }
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (var index = 0; index < left.length; index++) {
        if (!_valuesEqual(left[index], right[index])) return false;
      }
      return true;
    }
    return left == right;
  }
}
