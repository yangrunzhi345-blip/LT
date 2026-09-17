import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_autosave.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../utils/content_hasher.dart';

/// Persistence port of the autosave draft journal.
///
/// The journal holds only drafts that are not yet in the tree. A row is deleted
/// by the same commit that writes `resource_parts.content`, so the table stays
/// small and a leftover row always means "this edit never landed".
abstract interface class IResourceAutosaveRepository {
  /// Unresolved draft of one Part, or null.
  Future<ResourceAutosaveDraft?> findDraft(String nodeId);

  /// Unresolved drafts, newest first.
  Future<List<ResourceAutosaveDraft>> listDrafts({
    ResourceId? resourceId,
    int limit = 100,
  });

  /// How many unresolved drafts a resource has.
  Future<int> countDrafts(ResourceId resourceId);

  /// Writes or replaces the draft of one Part inside [txn].
  ///
  /// At most one unresolved draft per node exists (enforced by a unique index),
  /// so a debounce window that fires twice collapses into one row instead of
  /// accumulating a keystroke history.
  Future<ResourceAutosaveDraft> upsertDraftInTransaction(
    DatabaseExecutor txn, {
    required ResourceId resourceId,
    required PartId partId,
    required String content,
    required String baseUpdatedAt,
    required String now,
  });

  /// Deletes one draft inside [txn].
  Future<int> deleteDraftInTransaction(
      DatabaseExecutor txn, String checkpointId);
}

final class ResourceAutosaveRepositoryImpl
    implements IResourceAutosaveRepository {
  ResourceAutosaveRepositoryImpl({required Future<Database> Function() getDb})
      : _getDb = getDb;

  final Future<Database> Function() _getDb;

  static const String table = 'resource_autosaves';

  @override
  Future<ResourceAutosaveDraft?> findDraft(String nodeId) async {
    final db = await _getDb();
    final rows = await db.query(
      table,
      where: 'node_id = ?',
      whereArgs: <Object?>[nodeId],
      limit: 1,
    );
    return rows.isEmpty ? null : _mapDraft(rows.first);
  }

  @override
  Future<List<ResourceAutosaveDraft>> listDrafts({
    ResourceId? resourceId,
    int limit = 100,
  }) async {
    final db = await _getDb();
    final rows = await db.query(
      table,
      where: resourceId == null ? null : 'resource_id = ?',
      whereArgs: resourceId == null ? null : <Object?>[resourceId.value],
      orderBy: 'updated_at DESC, checkpoint_id DESC',
      limit: limit,
    );
    return rows.map(_mapDraft).toList();
  }

  @override
  Future<int> countDrafts(ResourceId resourceId) async {
    final db = await _getDb();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM $table WHERE resource_id = ?',
      <Object?>[resourceId.value],
    );
    return _intOf(rows.first['cnt']);
  }

  @override
  Future<ResourceAutosaveDraft> upsertDraftInTransaction(
    DatabaseExecutor txn, {
    required ResourceId resourceId,
    required PartId partId,
    required String content,
    required String baseUpdatedAt,
    required String now,
  }) async {
    final hash = contentHash(content);
    final existing = await txn.query(
      table,
      where: 'node_id = ?',
      whereArgs: <Object?>[partId.value],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final row = existing.first;
      await txn.update(
        table,
        <String, Object?>{
          'resource_id': resourceId.value,
          'content': content,
          'content_hash': hash,
          'base_updated_at': baseUpdatedAt,
          'updated_at': now,
        },
        where: 'checkpoint_id = ?',
        whereArgs: <Object?>[row['checkpoint_id']],
      );
      return ResourceAutosaveDraft(
        checkpointId: row['checkpoint_id'].toString(),
        resourceId: resourceId,
        partId: partId,
        content: content,
        contentHash: hash,
        baseUpdatedAt: baseUpdatedAt,
        createdAtToken: row['created_at']?.toString() ?? now,
        updatedAtToken: now,
      );
    }

    final checkpointId =
        'auto_${DateTime.now().microsecondsSinceEpoch}_${partId.value}';
    await txn.insert(table, <String, Object?>{
      'checkpoint_id': checkpointId,
      'resource_id': resourceId.value,
      'node_id': partId.value,
      'node_kind': 'part',
      'content': content,
      'content_hash': hash,
      'base_updated_at': baseUpdatedAt,
      'created_at': now,
      'updated_at': now,
    });
    return ResourceAutosaveDraft(
      checkpointId: checkpointId,
      resourceId: resourceId,
      partId: partId,
      content: content,
      contentHash: hash,
      baseUpdatedAt: baseUpdatedAt,
      createdAtToken: now,
      updatedAtToken: now,
    );
  }

  @override
  Future<int> deleteDraftInTransaction(
    DatabaseExecutor txn,
    String checkpointId,
  ) {
    return txn.delete(
      table,
      where: 'checkpoint_id = ?',
      whereArgs: <Object?>[checkpointId],
    );
  }

  /// Draft content hash, using the same hasher as the stored Part body so a
  /// recovered draft can be compared with the live row by hash alone.
  static String contentHash(String content) => ContentHasher.hash(content);

  ResourceAutosaveDraft _mapDraft(Map<String, Object?> row) =>
      ResourceAutosaveDraft(
        checkpointId: row['checkpoint_id'].toString(),
        resourceId: ResourceId(row['resource_id'].toString()),
        partId: PartId(row['node_id'].toString()),
        content: row['content']?.toString() ?? '',
        contentHash: row['content_hash']?.toString() ?? '',
        baseUpdatedAt: row['base_updated_at']?.toString() ?? '',
        createdAtToken: row['created_at']?.toString() ?? '',
        updatedAtToken: row['updated_at']?.toString() ?? '',
      );

  static int _intOf(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }
}
