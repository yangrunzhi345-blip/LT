import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_contracts.dart';
import '../../services/repositories/resource_tree_repository_impl.dart';
import 'legacy_resource_mapper.dart';
import 'resource_migration_service.dart';

/// Which source actually answered a compatibility read.
enum ResourceReadSource {
  /// The migrated unified content tree.
  newTree,

  /// The pre-migration legacy table.
  legacyFallback,
}

/// Why a read fell back to the legacy table.
abstract final class ResourceReadFallbackReason {
  static const String none = '';
  static const String notMigrated = '尚未迁移';
  static const String migrationFailed = '迁移失败';
  static const String sourceChanged = '旧数据已变更';
  static const String treeMissing = '新树缺失';
  static const String legacyMissing = '旧记录不存在';
}

/// Outcome of a compatibility read.
final class ResourceReadResult {
  const ResourceReadResult({
    required this.source,
    required this.legacyId,
    this.fallbackReason = ResourceReadFallbackReason.none,
    this.tree,
    this.legacyRow,
  });

  final ResourceReadSource source;
  final String legacyId;
  final String fallbackReason;

  /// Present when [source] is [ResourceReadSource.newTree].
  final ResourceTree? tree;

  /// Present when [source] is [ResourceReadSource.legacyFallback].
  final Map<String, Object?>? legacyRow;

  bool get isFromTree => source == ResourceReadSource.newTree;
}

/// Transitional read path: unified tree first, legacy table as fallback.
///
/// Precedence frozen by Phase 2:
/// 1. a migrated, still-current tree wins;
/// 2. otherwise a tree that exists without any legacy row still wins (a
///    resource created only in the new model);
/// 3. otherwise the legacy row is returned, with a reason.
///
/// The legacy table is never written here, so this introduces no dual write.
/// The whole facade is expected to disappear in Phase 12; until then it is what
/// keeps old data readable while the new model takes over.
final class ResourceReadFacade {
  ResourceReadFacade({
    required Future<Database> Function() getDb,
    ResourceTreeRepositoryImpl? treeRepository,
    ResourceMigrationService? migrationService,
  })  : _getDb = getDb,
        _treeRepository =
            treeRepository ?? ResourceTreeRepositoryImpl(getDb: getDb),
        _migrationService =
            migrationService ?? ResourceMigrationService(getDb: getDb);

  final Future<Database> Function() _getDb;
  final ResourceTreeRepositoryImpl _treeRepository;
  final ResourceMigrationService _migrationService;

  /// The legacy table that backs [type].
  static String legacyTableFor(ResourceType type) => switch (type) {
        ResourceType.worldview => LegacySourceTables.worldviewPresets,
        ResourceType.character => LegacySourceTables.characterCards,
        ResourceType.npc => LegacySourceTables.npcCards,
      };

  /// Reads [legacyId] of [type], preferring the migrated tree.
  Future<ResourceReadResult> readPreferringTree({
    required ResourceType type,
    required String legacyId,
  }) async {
    final sourceTable = legacyTableFor(type);
    final resourceId =
        LegacyResourceMapper.resourceIdFor(sourceTable, legacyId);

    final tree = await _treeRepository.readTree(resourceId);
    final legacyRow =
        await _readLegacyRow(sourceTable: sourceTable, id: legacyId);
    final record = await _migrationService.readRecord(
      sourceTable: sourceTable,
      sourceId: legacyId,
    );

    if (tree != null) {
      if (record == null) {
        // No audit row at all: the resource only exists in the new model.
        return ResourceReadResult(
          source: ResourceReadSource.newTree,
          legacyId: legacyId,
          tree: tree,
        );
      }
      if (record.outcome == ResourceMigrationOutcome.succeeded) {
        if (legacyRow == null) {
          return ResourceReadResult(
            source: ResourceReadSource.newTree,
            legacyId: legacyId,
            tree: tree,
          );
        }
        final current = await _migrationService.isTreeCurrent(
          sourceTable: sourceTable,
          sourceId: legacyId,
          row: legacyRow,
        );
        if (current) {
          return ResourceReadResult(
            source: ResourceReadSource.newTree,
            legacyId: legacyId,
            tree: tree,
          );
        }
        // Migrated once, then edited in the legacy table: fall back so the user
        // sees their latest content instead of a stale tree.
        return _fallback(
          legacyId: legacyId,
          legacyRow: legacyRow,
          reason: ResourceReadFallbackReason.sourceChanged,
        );
      }
      if (record.outcome == ResourceMigrationOutcome.sourceChanged) {
        return _fallback(
          legacyId: legacyId,
          legacyRow: legacyRow,
          reason: ResourceReadFallbackReason.sourceChanged,
        );
      }
      if (record.outcome == ResourceMigrationOutcome.failed) {
        return _fallback(
          legacyId: legacyId,
          legacyRow: legacyRow,
          reason: ResourceReadFallbackReason.migrationFailed,
        );
      }
    }

    if (legacyRow == null) {
      return ResourceReadResult(
        source: ResourceReadSource.legacyFallback,
        legacyId: legacyId,
        fallbackReason: ResourceReadFallbackReason.legacyMissing,
      );
    }
    final reason = switch (record?.outcome) {
      null => ResourceReadFallbackReason.notMigrated,
      ResourceMigrationOutcome.failed =>
        ResourceReadFallbackReason.migrationFailed,
      ResourceMigrationOutcome.sourceChanged =>
        ResourceReadFallbackReason.sourceChanged,
      ResourceMigrationOutcome.pending =>
        ResourceReadFallbackReason.notMigrated,
      ResourceMigrationOutcome.succeeded =>
        ResourceReadFallbackReason.treeMissing,
    };
    return _fallback(
      legacyId: legacyId,
      legacyRow: legacyRow,
      reason: reason,
    );
  }

  ResourceReadResult _fallback({
    required String legacyId,
    required Map<String, Object?>? legacyRow,
    required String reason,
  }) {
    return ResourceReadResult(
      source: ResourceReadSource.legacyFallback,
      legacyId: legacyId,
      fallbackReason: reason,
      legacyRow: legacyRow,
    );
  }

  Future<Map<String, Object?>?> _readLegacyRow({
    required String sourceTable,
    required String id,
  }) async {
    final db = await _getDb();
    final List<Map<String, Object?>> rows;
    try {
      rows = await db.query(
        sourceTable,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
    } catch (_) {
      // A database without this legacy table has no fallback source.
      return null;
    }
    return rows.isEmpty ? null : rows.first;
  }
}
