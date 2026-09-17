import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_compression.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_limits.dart';

/// Persistence boundary for compression jobs and their candidates.
///
/// The repository only ever stores candidates; it has no method that writes a
/// candidate back into `resource_parts`, which is what keeps Phase 8 from
/// silently replacing a resource head (Phase 9 owns that boundary).
///
/// Every job state transition here is a single atomic statement guarded by the
/// expected source status (and, for terminal transitions, by the owning worker).
/// That is what makes two workers racing on the same job safe: the loser sees
/// zero affected rows instead of corrupting the row.
abstract interface class ICompressionJobRepository {
  /// Finds the job already recorded for one (resource, scope, target, version).
  Future<CompressionJob?> findByVersion({
    required String resourceId,
    required CompressionScope scope,
    required String targetNodeId,
    required String sourceToken,
  });

  /// Finds the unfinished job for one target, if any.
  Future<CompressionJob?> findActiveForTarget({
    required String resourceId,
    required String targetNodeId,
  });

  Future<CompressionJob?> findJob(String jobId);

  /// Inserts a new job, or returns the row that already occupies its identity.
  Future<CompressionJob> insertJob(CompressionJob job);

  /// Atomically claims one `queued` job for [workerId].
  ///
  /// Returns `true` only for the worker whose update affected the row, so two
  /// workers draining the same queue can never both run the same job.
  Future<bool> claimJob({
    required String jobId,
    required String workerId,
    required int attempts,
    required DateTime claimedAt,
    required DateTime leaseExpiresAt,
  });

  /// Atomically finishes a job the caller still owns.
  ///
  /// The update is guarded by `status = running AND worker_id = caller`, so a
  /// worker whose lease was reclaimed cannot overwrite the new owner's result.
  Future<bool> completeJob({
    required String jobId,
    required String workerId,
    required CompressionJobStatus status,
    required DateTime updatedAt,
    String errorMessage,
  });

  /// Finds queued jobs, optionally scoped to one resource.
  Future<List<CompressionJob>> findJobsByStatus(
    CompressionJobStatus status, {
    int limit = 50,
    String? resourceId,
  });

  Future<List<CompressionJob>> findJobsForResource(String resourceId);

  /// Releases jobs whose owning worker is gone.
  ///
  /// Only rows whose lease has expired — or that carry no lease at all, which
  /// cannot prove ownership — are reclaimed: a job that spent its attempt
  /// budget becomes terminal `failed`, the rest return to `queued`. A row that
  /// is still held under a live lease is never touched. Returns the number of
  /// rows reclaimed. Idempotent.
  Future<int> recoverStaleRunningJobs({required DateTime now});

  /// Atomically returns one `failed` job to the queue.
  ///
  /// Refuses (returns `false`) when the job is not retryable or when its target
  /// already has a queued/running job, so a retry can never create a second
  /// active row for one target and can never surface a constraint error.
  Future<bool> retryFailedJob({
    required String jobId,
    required DateTime updatedAt,
  });

  Future<void> insertCandidate(CompressionCandidate candidate);

  Future<CompressionCandidate?> findCandidateForJob(String jobId);

  Future<List<CompressionCandidate>> findCandidatesForResource(
    String resourceId,
  );

  /// Total characters saved by validated candidates of one resource.
  Future<int> sumSavedCharacters(String resourceId);

  /// One candidate read inside a transaction the caller already owns.
  ///
  /// Phase 9's publish path must read the candidate and write both the Part
  /// body and `applied_at` in one commit, so the read cannot open its own
  /// connection.
  Future<CompressionCandidate?> findCandidateInTransaction(
    DatabaseExecutor db,
    String candidateId,
  );

  /// Marks a candidate as published.
  ///
  /// Guarded by `applied_at IS NULL`, so two concurrent publishes cannot both
  /// apply the same candidate: the loser gets false and its transaction rolls
  /// back instead of writing the body twice.
  Future<bool> markCandidateAppliedInTransaction(
    DatabaseExecutor txn, {
    required String candidateId,
    required String appliedAt,
  });

  /// Validated candidates of one resource that have not been published yet.
  Future<List<CompressionCandidate>> findPublishableCandidates(
    String resourceId,
  );
}

/// SQLite-backed compression persistence.
///
/// `retention_json` carries only the small declared retention lists, never body
/// text, so a candidate row stays bounded by its compressed content.
final class CompressionJobRepositoryImpl implements ICompressionJobRepository {
  CompressionJobRepositoryImpl({required Future<Database> Function() getDb})
      : _getDb = getDb;

  final Future<Database> Function() _getDb;

  static const String jobsTable = 'resource_compression_jobs';
  static const String candidatesTable = 'resource_compression_candidates';

  @override
  Future<CompressionJob?> findByVersion({
    required String resourceId,
    required CompressionScope scope,
    required String targetNodeId,
    required String sourceToken,
  }) async {
    final db = await _getDb();
    final rows = await db.query(
      jobsTable,
      where: 'resource_id = ? AND scope = ? AND target_node_id = ? '
          'AND source_token = ?',
      whereArgs: [resourceId, scope.storageValue, targetNodeId, sourceToken],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _mapJob(rows.first);
  }

  @override
  Future<CompressionJob?> findActiveForTarget({
    required String resourceId,
    required String targetNodeId,
  }) async {
    final db = await _getDb();
    final rows = await db.query(
      jobsTable,
      where: "resource_id = ? AND target_node_id = ? "
          "AND status IN ('queued', 'running')",
      whereArgs: [resourceId, targetNodeId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _mapJob(rows.first);
  }

  @override
  Future<CompressionJob?> findJob(String jobId) async {
    final db = await _getDb();
    final rows = await db.query(
      jobsTable,
      where: 'job_id = ?',
      whereArgs: [jobId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _mapJob(rows.first);
  }

  @override
  Future<CompressionJob> insertJob(CompressionJob job) async {
    final db = await _getDb();
    final now = (job.createdAt ?? DateTime.now()).toIso8601String();
    final existing = await findByVersion(
      resourceId: job.resourceId.value,
      scope: job.scope,
      targetNodeId: job.targetNodeId,
      sourceToken: job.sourceToken,
    );
    if (existing != null) return existing;

    await db.insert(
      jobsTable,
      {
        'job_id': job.jobId,
        'resource_id': job.resourceId.value,
        'scope': job.scope.storageValue,
        'target_node_id': job.targetNodeId,
        'parent_node_id': job.parentNodeId,
        'source_token': job.sourceToken,
        'status': job.status.storageValue,
        'attempts': job.attempts,
        'max_attempts': job.maxAttempts,
        'error_message': job.errorMessage,
        'worker_id': '',
        'claimed_at': null,
        'lease_expires_at': null,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    final stored = await findByVersion(
      resourceId: job.resourceId.value,
      scope: job.scope,
      targetNodeId: job.targetNodeId,
      sourceToken: job.sourceToken,
    );
    if (stored == null) {
      throw StateError('压缩任务写入后无法读回：${job.jobId}');
    }
    return stored;
  }

  @override
  Future<bool> claimJob({
    required String jobId,
    required String workerId,
    required int attempts,
    required DateTime claimedAt,
    required DateTime leaseExpiresAt,
  }) async {
    final db = await _getDb();
    final now = claimedAt.toIso8601String();
    final affected = await db.update(
      jobsTable,
      {
        'status': CompressionJobStatus.running.storageValue,
        'attempts': attempts,
        'worker_id': workerId,
        'claimed_at': now,
        'lease_expires_at': leaseExpiresAt.toIso8601String(),
        'error_message': '',
        'updated_at': now,
      },
      // The claim is the concurrency gate: only `queued` can become `running`,
      // so exactly one of any number of competing workers sees 1 row.
      where: 'job_id = ? AND status = ?',
      whereArgs: [jobId, CompressionJobStatus.queued.storageValue],
    );
    return affected == 1;
  }

  @override
  Future<bool> completeJob({
    required String jobId,
    required String workerId,
    required CompressionJobStatus status,
    required DateTime updatedAt,
    String errorMessage = '',
  }) async {
    final db = await _getDb();
    final affected = await db.update(
      jobsTable,
      {
        'status': status.storageValue,
        'error_message': errorMessage,
        'worker_id': '',
        'claimed_at': null,
        'lease_expires_at': null,
        'updated_at': updatedAt.toIso8601String(),
      },
      // Ownership CAS: a worker whose lease was reclaimed must not be able to
      // overwrite the state written by the new owner.
      where: 'job_id = ? AND status = ? AND worker_id = ?',
      whereArgs: [
        jobId,
        CompressionJobStatus.running.storageValue,
        workerId,
      ],
    );
    return affected == 1;
  }

  @override
  Future<List<CompressionJob>> findJobsByStatus(
    CompressionJobStatus status, {
    int limit = 50,
    String? resourceId,
  }) async {
    final db = await _getDb();
    final rows = await db.query(
      jobsTable,
      where:
          resourceId == null ? 'status = ?' : 'status = ? AND resource_id = ?',
      whereArgs: resourceId == null
          ? [status.storageValue]
          : [status.storageValue, resourceId],
      orderBy: 'created_at ASC, job_id ASC',
      limit: limit,
    );
    return rows.map(_mapJob).toList();
  }

  @override
  Future<List<CompressionJob>> findJobsForResource(String resourceId) async {
    final db = await _getDb();
    final rows = await db.query(
      jobsTable,
      where: 'resource_id = ?',
      whereArgs: [resourceId],
      orderBy: 'created_at ASC, job_id ASC',
    );
    return rows.map(_mapJob).toList();
  }

  @override
  Future<int> recoverStaleRunningJobs({required DateTime now}) async {
    final db = await _getDb();
    final nowIso = now.toIso8601String();
    final running = CompressionJobStatus.running.storageValue;
    final requeued = CompressionJobStateMachine.recoveryTarget.storageValue;
    final failed = CompressionJobStatus.failed.storageValue;

    // One statement, no per-row loop: `attempts < max_attempts` is evaluated
    // per row, so a job created with a different budget is handled correctly.
    //
    // Only reclaimed rows are touched. A row with a live lease belongs to a
    // worker that is still running it and must not be disturbed; a row with no
    // lease can never prove ownership, which is how rows written before the
    // lease columns existed are recovered instead of being stuck forever.
    final affected = await db.rawUpdate(
      'UPDATE $jobsTable SET '
      'status = CASE WHEN attempts < max_attempts THEN ? ELSE ? END, '
      'error_message = CASE WHEN attempts < max_attempts THEN ? ELSE ? END, '
      "worker_id = '', claimed_at = NULL, lease_expires_at = NULL, "
      'updated_at = ? '
      'WHERE status = ? AND (lease_expires_at IS NULL OR lease_expires_at < ?)',
      [
        requeued,
        failed,
        '应用中断，已释放中断的压缩任务',
        '应用中断且重试次数已用尽，需显式重试',
        nowIso,
        running,
        nowIso,
      ],
    );

    return affected;
  }

  @override
  Future<bool> retryFailedJob({
    required String jobId,
    required DateTime updatedAt,
  }) async {
    final db = await _getDb();
    try {
      final affected = await db.rawUpdate(
        'UPDATE $jobsTable SET '
        "status = ?, error_message = '', worker_id = '', "
        'claimed_at = NULL, lease_expires_at = NULL, updated_at = ? '
        'WHERE job_id = ? AND status = ? AND attempts < max_attempts '
        'AND NOT EXISTS ('
        'SELECT 1 FROM $jobsTable AS active '
        'WHERE active.resource_id = $jobsTable.resource_id '
        'AND active.target_node_id = $jobsTable.target_node_id '
        'AND active.status IN (?, ?))',
        [
          CompressionJobStateMachine.recoveryTarget.storageValue,
          updatedAt.toIso8601String(),
          jobId,
          CompressionJobStatus.failed.storageValue,
          CompressionJobStatus.queued.storageValue,
          CompressionJobStatus.running.storageValue,
        ],
      );
      return affected == 1;
    } on DatabaseException catch (error) {
      // The `NOT EXISTS` guard makes a conflict unreachable in practice, but a
      // retry must never surface a raw constraint error to the caller: report
      // "not retried" instead.
      if (_isUniqueViolation(error)) return false;
      rethrow;
    }
  }

  /// True when [error] is a UNIQUE/PRIMARY KEY violation.
  static bool _isUniqueViolation(DatabaseException error) {
    final text = error.toString();
    return text.contains('UNIQUE constraint failed') ||
        text.contains('constraint failed');
  }

  @override
  Future<void> insertCandidate(CompressionCandidate candidate) async {
    final db = await _getDb();
    await db.insert(
      candidatesTable,
      {
        'candidate_id': candidate.candidateId,
        'job_id': candidate.jobId,
        'resource_id': candidate.resourceId.value,
        'scope': candidate.scope.storageValue,
        'target_node_id': candidate.targetNodeId,
        'original_char_count': candidate.originalCharacters,
        'compressed_char_count': candidate.compressedCharacters,
        'compressed_content': candidate.compressedContent,
        'retention_json': encodeRetention(candidate.retention),
        'validation_state': candidate.isValidated ? 'validated' : 'rejected',
        'validation_message': candidate.validationMessage,
        'applied_at': null,
        'created_at': (candidate.createdAt ?? DateTime.now()).toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<CompressionCandidate?> findCandidateForJob(String jobId) async {
    final db = await _getDb();
    final rows = await db.query(
      candidatesTable,
      where: 'job_id = ?',
      whereArgs: [jobId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _mapCandidate(rows.first);
  }

  @override
  Future<CompressionCandidate?> findCandidateInTransaction(
    DatabaseExecutor db,
    String candidateId,
  ) async {
    final rows = await db.query(
      candidatesTable,
      where: 'candidate_id = ?',
      whereArgs: <Object?>[candidateId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _mapCandidate(rows.first);
  }

  @override
  Future<bool> markCandidateAppliedInTransaction(
    DatabaseExecutor txn, {
    required String candidateId,
    required String appliedAt,
  }) async {
    final updated = await txn.update(
      candidatesTable,
      <String, Object?>{'applied_at': appliedAt},
      where: 'candidate_id = ? AND applied_at IS NULL',
      whereArgs: <Object?>[candidateId],
    );
    return updated > 0;
  }

  @override
  Future<List<CompressionCandidate>> findPublishableCandidates(
    String resourceId,
  ) async {
    final db = await _getDb();
    final rows = await db.query(
      candidatesTable,
      where: "resource_id = ? AND validation_state = 'validated' "
          'AND applied_at IS NULL AND scope = ?',
      whereArgs: <Object?>[resourceId, CompressionScope.part.storageValue],
      orderBy: 'created_at DESC, candidate_id ASC',
    );
    return rows.map(_mapCandidate).toList();
  }

  @override
  Future<List<CompressionCandidate>> findCandidatesForResource(
    String resourceId,
  ) async {
    final db = await _getDb();
    final rows = await db.query(
      candidatesTable,
      columns: [
        'candidate_id',
        'job_id',
        'resource_id',
        'scope',
        'target_node_id',
        'original_char_count',
        'compressed_char_count',
        'compressed_content',
        'retention_json',
        'validation_state',
        'validation_message',
        'created_at',
        'applied_at',
      ],
      where: 'resource_id = ?',
      whereArgs: [resourceId],
      orderBy: 'created_at DESC, candidate_id ASC',
    );
    return rows.map(_mapCandidate).toList();
  }

  @override
  Future<int> sumSavedCharacters(String resourceId) async {
    final db = await _getDb();
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(original_char_count - compressed_char_count), 0) '
      'AS saved FROM $candidatesTable '
      "WHERE resource_id = ? AND validation_state = 'validated'",
      [resourceId],
    );
    final saved = rows.first['saved'];
    if (saved is int) return saved;
    if (saved is num) return saved.toInt();
    return 0;
  }

  /// Encodes the small retention lists; never body text.
  static String encodeRetention(CompressionRetention retention) => jsonEncode({
        'entities': retention.entities,
        'relationships': retention.relationships,
        'timeline': retention.timeline,
      });

  /// Decodes retention defensively: a malformed payload degrades to "nothing
  /// declared" instead of throwing, because a corrupt retention list must not
  /// make the whole resource unreadable.
  static CompressionRetention decodeRetention(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) {
      return CompressionRetention.empty;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return CompressionRetention.empty;
      return CompressionRetention(
        entities: _stringList(decoded['entities']),
        relationships: _stringList(decoded['relationships']),
        timeline: _stringList(decoded['timeline']),
      );
    } catch (_) {
      return CompressionRetention.empty;
    }
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .whereType<Object>()
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static CompressionJob _mapJob(Map<String, Object?> row) {
    return CompressionJob(
      jobId: row['job_id']?.toString() ?? '',
      resourceId: ResourceId(row['resource_id']?.toString() ?? ''),
      scope: CompressionScope.fromStorage(row['scope']?.toString()),
      targetNodeId: row['target_node_id']?.toString() ?? '',
      parentNodeId: row['parent_node_id']?.toString() ?? '',
      sourceToken: row['source_token']?.toString() ?? '',
      status: CompressionJobStatus.fromStorage(row['status']?.toString()),
      attempts: _intOrZero(row['attempts']),
      maxAttempts: _intOrZero(row['max_attempts']) == 0
          ? ResourceLimits.maxCompressionAttempts
          : _intOrZero(row['max_attempts']),
      errorMessage: row['error_message']?.toString() ?? '',
      workerId: row['worker_id']?.toString() ?? '',
      claimedAt: DateTime.tryParse(row['claimed_at']?.toString() ?? ''),
      leaseExpiresAt:
          DateTime.tryParse(row['lease_expires_at']?.toString() ?? ''),
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? ''),
    );
  }

  static CompressionCandidate _mapCandidate(Map<String, Object?> row) {
    return CompressionCandidate(
      candidateId: row['candidate_id']?.toString() ?? '',
      jobId: row['job_id']?.toString() ?? '',
      resourceId: ResourceId(row['resource_id']?.toString() ?? ''),
      scope: CompressionScope.fromStorage(row['scope']?.toString()),
      targetNodeId: row['target_node_id']?.toString() ?? '',
      originalCharacters: _intOrZero(row['original_char_count']),
      compressedCharacters: _intOrZero(row['compressed_char_count']),
      compressedContent: row['compressed_content']?.toString() ?? '',
      retention: decodeRetention(row['retention_json']),
      isValidated: row['validation_state']?.toString() == 'validated',
      validationMessage: row['validation_message']?.toString() ?? '',
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? ''),
      appliedAt: DateTime.tryParse(row['applied_at']?.toString() ?? ''),
    );
  }

  static int _intOrZero(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
