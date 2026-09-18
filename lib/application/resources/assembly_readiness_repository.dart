import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_contracts.dart';

/// Thrown when a readiness row cannot be mapped back into the domain.
class AssemblyReadinessException implements Exception {
  const AssemblyReadinessException(this.message);

  final String message;

  @override
  String toString() => 'AssemblyReadinessException: $message';
}

/// One deterministic semantic-index document bound to one assembly revision.
///
/// Documents are the worldview's managed-entry shape (keys + content + order),
/// persisted per `(resource_id, revision_id)` so that "assembly revision A →
/// index A" is a stored fact rather than a recomputation. Old revisions keep
/// their documents so an explicitly chosen previous ready revision still has a
/// consistent index.
final class AssemblyIndexDoc {
  const AssemblyIndexDoc({
    required this.docId,
    required this.keys,
    required this.content,
    required this.insertionOrder,
    required this.sticky,
  });

  final String docId;
  final List<String> keys;
  final String content;
  final int insertionOrder;
  final int sticky;
}

/// Persisted assembly readiness of one resource (Phase 10).
///
/// One row per resource. [attemptToken] is the CAS ownership token: only the
/// task that wrote the current token may move the row out of `preparing`, so a
/// late task can never publish a result for a head it no longer owns.
final class AssemblyReadinessRecord {
  const AssemblyReadinessRecord({
    required this.resourceId,
    required this.state,
    this.targetRevisionId = '',
    this.targetContentHash = '',
    this.assemblyRevisionId = '',
    this.assemblyContentHash = '',
    this.attemptToken = '',
    this.validationMessage = '',
    this.failureReason = '',
    this.startedAt = '',
    this.completedAt = '',
    this.updatedAt = '',
  });

  final String resourceId;
  final ReadinessState state;

  /// The latest-head revision this preparation run targeted.
  final String targetRevisionId;
  final String targetContentHash;

  /// The assembly revision that is currently consumable. Kept across
  /// `stale`/`preparing` transitions so a previous ready revision stays
  /// selectable; only overwritten when a new assembly is published.
  final String assemblyRevisionId;
  final String assemblyContentHash;

  /// Ownership token of the current (or last) preparation run.
  final String attemptToken;

  /// Human-readable progress note (e.g. the compression wait message).
  final String validationMessage;

  /// Why the last run failed; empty when not failed.
  final String failureReason;

  final String startedAt;
  final String completedAt;
  final String updatedAt;

  bool get hasAssemblyRevision => assemblyRevisionId.isNotEmpty;

  @override
  String toString() => 'AssemblyReadinessRecord(${resourceId.substring(0, 8)}, '
      '${state.storageValue}, target=$targetRevisionId, '
      'assembly=$assemblyRevisionId)';
}

/// Persistence boundary of the Phase 10 readiness state.
///
/// Everything that must be atomic (CAS transitions, index replacement) runs on
/// a caller-provided [DatabaseExecutor]; the interface exists so the
/// coordinator and its tests share one contract.
abstract interface class IAssemblyReadinessRepository {
  Future<AssemblyReadinessRecord?> read(String resourceId);

  Future<AssemblyReadinessRecord?> readInTransaction(
    DatabaseExecutor txn,
    String resourceId,
  );

  /// Upserts the full row. Callers own state-machine and CAS validation.
  Future<void> writeInTransaction(
    DatabaseExecutor txn,
    AssemblyReadinessRecord record,
  );

  /// Rows currently in [state]; used by startup recovery.
  Future<List<AssemblyReadinessRecord>> listByState(ReadinessState state);

  Future<List<AssemblyIndexDoc>> readIndexDocs(
    String resourceId,
    String revisionId,
  );

  Future<List<AssemblyIndexDoc>> readIndexDocsInTransaction(
    DatabaseExecutor txn,
    String resourceId,
    String revisionId,
  );

  /// Replaces the index documents of `(resourceId, revisionId)` in one
  /// transaction. Documents of other revisions are untouched.
  Future<void> replaceIndexDocsInTransaction(
    DatabaseExecutor txn, {
    required String resourceId,
    required String revisionId,
    required String revisionContentHash,
    required List<AssemblyIndexDoc> docs,
    required String now,
  });
}

final class AssemblyReadinessRepositoryImpl
    implements IAssemblyReadinessRepository {
  AssemblyReadinessRepositoryImpl({required Future<Database> Function() getDb})
      : _getDb = getDb;

  final Future<Database> Function() _getDb;

  static const String readinessTable = 'resource_assembly_readiness';
  static const String entriesTable = 'resource_assembly_entries';

  @override
  Future<AssemblyReadinessRecord?> read(String resourceId) async {
    final db = await _getDb();
    return db.transaction((txn) => readInTransaction(txn, resourceId));
  }

  @override
  Future<AssemblyReadinessRecord?> readInTransaction(
    DatabaseExecutor txn,
    String resourceId,
  ) async {
    final rows = await txn.query(
      readinessTable,
      where: 'resource_id = ?',
      whereArgs: <Object?>[resourceId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  @override
  Future<void> writeInTransaction(
    DatabaseExecutor txn,
    AssemblyReadinessRecord record,
  ) async {
    await txn.insert(
      readinessTable,
      <String, Object?>{
        'resource_id': record.resourceId,
        'target_revision_id': record.targetRevisionId,
        'target_content_hash': record.targetContentHash,
        'state': record.state.storageValue,
        'assembly_revision_id': record.assemblyRevisionId,
        'assembly_content_hash': record.assemblyContentHash,
        'attempt_token': record.attemptToken,
        'validation_message': record.validationMessage,
        'failure_reason': record.failureReason,
        'started_at': record.startedAt,
        'completed_at': record.completedAt,
        'updated_at': record.updatedAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<AssemblyReadinessRecord>> listByState(
    ReadinessState state,
  ) async {
    final db = await _getDb();
    final rows = await db.query(
      readinessTable,
      where: 'state = ?',
      whereArgs: <Object?>[state.storageValue],
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<List<AssemblyIndexDoc>> readIndexDocs(
    String resourceId,
    String revisionId,
  ) async {
    final db = await _getDb();
    return db.transaction(
      (txn) => readIndexDocsInTransaction(txn, resourceId, revisionId),
    );
  }

  @override
  Future<List<AssemblyIndexDoc>> readIndexDocsInTransaction(
    DatabaseExecutor txn,
    String resourceId,
    String revisionId,
  ) async {
    final rows = await txn.query(
      entriesTable,
      where: 'resource_id = ? AND revision_id = ?',
      whereArgs: <Object?>[resourceId, revisionId],
      orderBy: 'insertion_order ASC, entry_id ASC',
    );
    return rows.map(_docFromRow).toList(growable: false);
  }

  @override
  Future<void> replaceIndexDocsInTransaction(
    DatabaseExecutor txn, {
    required String resourceId,
    required String revisionId,
    required String revisionContentHash,
    required List<AssemblyIndexDoc> docs,
    required String now,
  }) async {
    await txn.delete(
      entriesTable,
      where: 'resource_id = ? AND revision_id = ?',
      whereArgs: <Object?>[resourceId, revisionId],
    );
    for (final doc in docs) {
      await txn.insert(
        entriesTable,
        <String, Object?>{
          'entry_id': doc.docId,
          'resource_id': resourceId,
          'revision_id': revisionId,
          'revision_content_hash': revisionContentHash,
          'keys_json': jsonEncode(doc.keys),
          'content': doc.content,
          'insertion_order': doc.insertionOrder,
          'sticky': doc.sticky,
          'created_at': now,
        },
      );
    }
  }

  AssemblyReadinessRecord _fromRow(Map<String, Object?> row) {
    final state = ReadinessState.values
        .where((s) => s.storageValue == row['state'])
        .firstOrNull;
    if (state == null) {
      throw AssemblyReadinessException(
        '未知的 readiness 状态: ${row['state']}（resource=${row['resource_id']}）',
      );
    }
    return AssemblyReadinessRecord(
      resourceId: row['resource_id'].toString(),
      state: state,
      targetRevisionId: row['target_revision_id'].toString(),
      targetContentHash: row['target_content_hash'].toString(),
      assemblyRevisionId: row['assembly_revision_id'].toString(),
      assemblyContentHash: row['assembly_content_hash'].toString(),
      attemptToken: row['attempt_token'].toString(),
      validationMessage: row['validation_message'].toString(),
      failureReason: row['failure_reason'].toString(),
      startedAt: row['started_at'].toString(),
      completedAt: row['completed_at'].toString(),
      updatedAt: row['updated_at'].toString(),
    );
  }

  AssemblyIndexDoc _docFromRow(Map<String, Object?> row) {
    final rawKeys = row['keys_json'].toString();
    final keys = <String>[];
    try {
      final decoded = jsonDecode(rawKeys);
      if (decoded is List) {
        keys.addAll(decoded.whereType<String>());
      }
    } on FormatException {
      // Legacy/ damaged row: keep the doc with no keys rather than dropping
      // index content silently.
    }
    return AssemblyIndexDoc(
      docId: row['entry_id'].toString(),
      keys: keys,
      content: row['content'].toString(),
      insertionOrder: (row['insertion_order'] as int?) ?? 0,
      sticky: (row['sticky'] as int?) ?? 0,
    );
  }
}
