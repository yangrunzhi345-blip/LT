import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_blueprint.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_limits.dart';

/// Resolves the frozen, authorized AI generation ceiling (C) of a persisted
/// resource.
///
/// An AI generation run freezes its effective elastic percent and budget policy
/// version on `resource_blueprints` when it is confirmed. That frozen budget is
/// the *authorization* that lets the run's committed body exceed the resource
/// type's ordinary absolute capacity A. Every downstream consumer that must
/// distinguish "an authorized elastic body" from "an over-budget write" reads
/// this one value:
///
/// - capacity classification (so an authorized body is `elastic`, not
///   `overflow`, and assembly is not forced to compress it);
/// - card-body validation when an authorized resource is re-edited.
///
/// It is deliberately *not* a global relaxation: a resource with no confirmed
/// AI run reports 0, and every caller keeps its ordinary A limit. The result is
/// the maximum over the resource's confirmed blueprints, so re-planning can
/// only ever widen the effective boundary, never narrow a legitimately larger
/// earlier run.
abstract interface class IAuthorizedGenerationBudgetReader {
  /// Maximum frozen ceiling C over [resourceId]'s confirmed blueprints, or 0
  /// when the resource has no confirmed AI generation run.
  Future<int> authorizedCeiling(String resourceId);

  /// [authorizedCeiling] for many resources in one query.
  ///
  /// Every requested id is present in the result (0 when unauthorized), so a
  /// caller never has to distinguish "absent" from "no budget".
  Future<Map<String, int>> authorizedCeilings(Iterable<String> resourceIds);
}

/// SQLite implementation of [IAuthorizedGenerationBudgetReader].
final class AuthorizedGenerationBudgetReader
    implements IAuthorizedGenerationBudgetReader {
  AuthorizedGenerationBudgetReader({required Future<Database> Function() getDb})
      : _getDb = getDb;

  static const String blueprintsTable = 'resource_blueprints';

  final Future<Database> Function() _getDb;

  @override
  Future<int> authorizedCeiling(String resourceId) async {
    if (resourceId.isEmpty) return 0;
    final ceilings = await authorizedCeilings([resourceId]);
    return ceilings[resourceId] ?? 0;
  }

  @override
  Future<Map<String, int>> authorizedCeilings(
    Iterable<String> resourceIds,
  ) async {
    final ids = resourceIds.where((id) => id.isNotEmpty).toSet();
    final result = <String, int>{for (final id in ids) id: 0};
    if (ids.isEmpty) return result;
    final db = await _getDb();
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT resource_id, target_capacity, resource_type, elastic_percent, '
      'budget_policy_version FROM $blueprintsTable '
      "WHERE status = ? AND resource_id IN ($placeholders)",
      [BlueprintStatus.confirmed.storageValue, ...ids],
    );
    for (final row in rows) {
      final resourceId = row['resource_id']?.toString() ?? '';
      if (resourceId.isEmpty) continue;
      final target = (row['target_capacity'] as num?)?.toInt() ?? 0;
      if (target <= 0) continue;
      final type = ResourceType.fromStorageValue(
        row['resource_type']?.toString(),
      );
      final ceiling = GenerationBudgetPolicy.ceilingFor(
        target: target,
        absolute: ResourceLimits.policyFor(type).absoluteCharacters,
        elasticPercent: (row['elastic_percent'] as num?)?.toInt() ??
            GenerationBudgetPolicy.defaultElasticPercent,
        // A row frozen before v50 has no version column value of its own
        // (DEFAULT 1), which keeps its historical `min(..., A)` budget.
        policyVersion: (row['budget_policy_version'] as num?)?.toInt() ??
            GenerationBudgetPolicy.legacyBudgetPolicyVersion,
      );
      final current = result[resourceId] ?? 0;
      if (ceiling > current) result[resourceId] = ceiling;
    }
    return result;
  }
}
