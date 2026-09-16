import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_contracts.dart';
import '../../services/repositories/resource_tree_repository.dart';
import '../../services/repositories/resource_tree_repository_impl.dart';
import 'legacy_resource_mapper.dart';

/// Persisted outcome of migrating one legacy source row.
enum ResourceMigrationOutcome {
  /// Never migrated (or a previous failure is about to be retried).
  pending,

  /// The tree was written for this source hash.
  succeeded,

  /// Mapping failed; the legacy row is untouched and the reason is recorded.
  failed,

  /// Migrated once, but the legacy row content changed afterwards. The tree is
  /// deliberately left alone so nothing is silently overwritten.
  sourceChanged;

  String get storageValue => switch (this) {
        ResourceMigrationOutcome.pending => 'pending',
        ResourceMigrationOutcome.succeeded => 'succeeded',
        ResourceMigrationOutcome.failed => 'failed',
        ResourceMigrationOutcome.sourceChanged => 'source_changed',
      };

  static ResourceMigrationOutcome fromStorage(String? value) {
    for (final outcome in ResourceMigrationOutcome.values) {
      if (outcome.storageValue == value) return outcome;
    }
    return ResourceMigrationOutcome.pending;
  }
}

/// One row of the migration audit table.
final class ResourceMigrationRecord {
  const ResourceMigrationRecord({
    required this.sourceTable,
    required this.sourceId,
    required this.migrationVersion,
    required this.outcome,
    required this.sourceHash,
    this.resourceId,
    this.errorReason = '',
  });

  final String sourceTable;
  final String sourceId;
  final int migrationVersion;
  final ResourceMigrationOutcome outcome;

  /// Hash of the source row at the time it was migrated.
  final String sourceHash;

  /// The tree resource created for this source row, when one exists.
  final ResourceId? resourceId;

  final String errorReason;
}

/// One un-migratable source row, for read-only reporting.
final class ResourceMigrationFailure {
  const ResourceMigrationFailure({
    required this.sourceTable,
    required this.sourceId,
    required this.reason,
  });

  final String sourceTable;
  final String sourceId;
  final String reason;

  @override
  String toString() => '$sourceTable/$sourceId: $reason';
}

/// Read-only migration counters.
///
/// Deliberately carries no resource body text, so it is safe to surface in
/// diagnostics.
final class ResourceMigrationStats {
  const ResourceMigrationStats({
    required this.total,
    required this.migrated,
    required this.skipped,
    required this.sourceChanged,
    required this.failed,
    required this.failures,
  });

  final int total;
  final int migrated;
  final int skipped;
  final int sourceChanged;
  final int failed;
  final List<ResourceMigrationFailure> failures;

  bool get hasFailures => failures.isNotEmpty;

  @override
  String toString() => 'migration(total: $total, migrated: $migrated, '
      'skipped: $skipped, sourceChanged: $sourceChanged, failed: $failed)';
}

/// Maps legacy resources into the unified content tree, repeatably.
///
/// Guarantees frozen by Phase 2:
/// - One transaction per resource: a failure rolls back only that resource and
///   never blocks the rest of the batch.
/// - The legacy row is never modified or deleted.
/// - Re-running skips anything already migrated with the same content hash, so
///   a second run cannot create a second Resource/Section/Part tree.
/// - A changed source hash is recorded as [ResourceMigrationOutcome.sourceChanged]
///   instead of overwriting the migrated tree.
/// - The legacy row survives a mapping failure, which is recorded with its
///   raw payload for diagnosis instead of being replaced by `{}`.
///
/// This service is the migration entry point but is intentionally NOT invoked
/// from app start-up or any UI in Phase 2: creation entries and the resource
/// library read path converge in Phase 3 / Phase 11.
final class ResourceMigrationService {
  ResourceMigrationService({
    required Future<Database> Function() getDb,
    ResourceTreeRepositoryImpl? treeRepository,
    LegacyResourceMapper mapper = const LegacyResourceMapper(),
    int migrationVersion = LegacyResourceMapper.migrationVersion,
  })  : _getDb = getDb,
        _mapper = mapper,
        _migrationVersion = migrationVersion,
        _treeRepository =
            treeRepository ?? ResourceTreeRepositoryImpl(getDb: getDb);

  static const String table = 'resource_migration_records';

  final Future<Database> Function() _getDb;
  final ResourceTreeRepositoryImpl _treeRepository;
  final LegacyResourceMapper _mapper;
  final int _migrationVersion;

  /// Runs the migration over every legacy source row.
  Future<ResourceMigrationStats> run() async {
    final db = await _getDb();
    var total = 0;
    var migrated = 0;
    var skipped = 0;
    var changed = 0;
    var failed = 0;
    final failures = <ResourceMigrationFailure>[];

    for (final sourceTable in LegacySourceTables.all) {
      final List<Map<String, Object?>> rows;
      try {
        rows = await db.query(sourceTable);
      } catch (_) {
        // A database without this legacy table simply has nothing to migrate.
        continue;
      }

      for (final row in rows) {
        total++;
        final sourceId = row['id']?.toString() ?? '';
        if (sourceId.isEmpty) {
          failed++;
          failures.add(ResourceMigrationFailure(
            sourceTable: sourceTable,
            sourceId: '',
            reason: '旧记录缺少 id',
          ));
          continue;
        }

        final hash = LegacyResourceMapper.sourceHash(sourceTable, row);
        final record = await readRecord(
          sourceTable: sourceTable,
          sourceId: sourceId,
        );

        if (record != null &&
            record.outcome == ResourceMigrationOutcome.succeeded) {
          if (record.sourceHash == hash) {
            skipped++;
          } else {
            // Content changed after migration: record it, do not overwrite.
            await _writeRecord(
              sourceTable: sourceTable,
              sourceId: sourceId,
              hash: hash,
              outcome: ResourceMigrationOutcome.sourceChanged,
              resourceId: record.resourceId,
              existing: record,
            );
            changed++;
          }
          continue;
        }

        if (record != null &&
            record.outcome == ResourceMigrationOutcome.sourceChanged) {
          if (record.sourceHash == hash) {
            // The source row went back to the migrated content.
            await _writeRecord(
              sourceTable: sourceTable,
              sourceId: sourceId,
              hash: hash,
              outcome: ResourceMigrationOutcome.succeeded,
              resourceId: record.resourceId,
              existing: record,
            );
            skipped++;
          } else {
            changed++;
          }
          continue;
        }

        final resourceId =
            LegacyResourceMapper.resourceIdFor(sourceTable, sourceId);
        // A tree may already exist if a previous run was interrupted between the
        // tree write and the audit write. The deterministic id makes this
        // detectable instead of producing a duplicate tree.
        final existing = await _treeRepository.findResource(resourceId);
        if (existing != null) {
          await _writeRecord(
            sourceTable: sourceTable,
            sourceId: sourceId,
            hash: hash,
            outcome: ResourceMigrationOutcome.succeeded,
            resourceId: resourceId,
            existing: record,
          );
          skipped++;
          continue;
        }

        try {
          final draft = _map(sourceTable: sourceTable, row: row);
          // One transaction: resource + sections + parts roll back together.
          await _treeRepository.createResourceTree(draft);
          await _writeRecord(
            sourceTable: sourceTable,
            sourceId: sourceId,
            hash: hash,
            outcome: ResourceMigrationOutcome.succeeded,
            resourceId: draft.id,
            existing: record,
          );
          migrated++;
        } catch (error) {
          // The failed resource rolled back on its own; the batch continues.
          await _writeRecord(
            sourceTable: sourceTable,
            sourceId: sourceId,
            hash: hash,
            outcome: ResourceMigrationOutcome.failed,
            resourceId: null,
            errorReason: '$error',
            rawPayload: _rawPayload(sourceTable: sourceTable, row: row),
            existing: record,
          );
          failed++;
          failures.add(ResourceMigrationFailure(
            sourceTable: sourceTable,
            sourceId: sourceId,
            reason: '$error',
          ));
        }
      }
    }

    return ResourceMigrationStats(
      total: total,
      migrated: migrated,
      skipped: skipped,
      sourceChanged: changed,
      failed: failed,
      failures: failures,
    );
  }

  /// Reads the audit record for one legacy source row.
  Future<ResourceMigrationRecord?> readRecord({
    required String sourceTable,
    required String sourceId,
  }) async {
    final db = await _getDb();
    final rows = await db.query(
      table,
      where: 'source_table = ? AND source_id = ? AND migration_version = ?',
      whereArgs: [sourceTable, sourceId, _migrationVersion],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final resourceId = row['resource_id']?.toString();
    return ResourceMigrationRecord(
      sourceTable: sourceTable,
      sourceId: sourceId,
      migrationVersion: _migrationVersion,
      outcome: ResourceMigrationOutcome.fromStorage(row['status']?.toString()),
      sourceHash: row['source_hash']?.toString() ?? '',
      resourceId: (resourceId == null || resourceId.isEmpty)
          ? null
          : ResourceId(resourceId),
      errorReason: row['error_reason']?.toString() ?? '',
    );
  }

  /// Whether the migrated tree still represents the current legacy row.
  ///
  /// True only when the row was migrated successfully and its content hash is
  /// unchanged, which is exactly the condition for preferring the tree over the
  /// legacy row on read.
  Future<bool> isTreeCurrent({
    required String sourceTable,
    required String sourceId,
    required Map<String, Object?> row,
  }) async {
    final record = await readRecord(
      sourceTable: sourceTable,
      sourceId: sourceId,
    );
    if (record == null) return false;
    if (record.outcome != ResourceMigrationOutcome.succeeded) return false;
    return record.sourceHash ==
        LegacyResourceMapper.sourceHash(sourceTable, row);
  }

  ResourceTreeDraft _map({
    required String sourceTable,
    required Map<String, Object?> row,
  }) {
    if (sourceTable == LegacySourceTables.worldviewPresets) {
      return _mapper.mapWorldview(row);
    }
    if (sourceTable == LegacySourceTables.characterCards) {
      return _mapper.mapCharacter(row);
    }
    if (sourceTable == LegacySourceTables.npcCards) {
      return _mapper.mapNpc(row);
    }
    throw LegacyMappingException('未知旧资源表：$sourceTable');
  }

  /// The payload preserved verbatim when a source row cannot be mapped.
  String _rawPayload({
    required String sourceTable,
    required Map<String, Object?> row,
  }) {
    if (sourceTable == LegacySourceTables.worldviewPresets) {
      final detail = row['detail_json']?.toString() ?? '';
      return detail.isNotEmpty ? detail : row['entries_json']?.toString() ?? '';
    }
    return row['json_data']?.toString() ?? '';
  }

  Future<void> _writeRecord({
    required String sourceTable,
    required String sourceId,
    required String hash,
    required ResourceMigrationOutcome outcome,
    required ResourceId? resourceId,
    required ResourceMigrationRecord? existing,
    String errorReason = '',
    String rawPayload = '',
  }) async {
    final db = await _getDb();
    final now = DateTime.now().toIso8601String();
    final values = <String, Object?>{
      'source_hash': hash,
      'status': outcome.storageValue,
      'resource_id': resourceId?.value,
      'error_reason': errorReason,
      'raw_payload': rawPayload,
      'updated_at': now,
    };

    if (existing == null) {
      await db.insert(table, {
        ...values,
        'source_table': sourceTable,
        'source_id': sourceId,
        'migration_version': _migrationVersion,
        'created_at': now,
      });
      return;
    }

    await db.update(
      table,
      values,
      where: 'source_table = ? AND source_id = ? AND migration_version = ?',
      whereArgs: [sourceTable, sourceId, _migrationVersion],
    );
  }
}
