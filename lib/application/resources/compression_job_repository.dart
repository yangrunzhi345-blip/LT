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

  Future<void> updateJob(CompressionJob job);

  Future<List<CompressionJob>> findJobsByStatus(
    CompressionJobStatus status, {
    int limit = 50,
  });

  Future<List<CompressionJob>> findJobsForResource(String resourceId);

  /// Releases jobs whose owning worker died (application restart or crash).
  ///
  /// A `running` job can only be written by the worker that owns it, so after a
  /// restart the row is orphaned and — because the active-target index also
  /// covers `running` — it would block its target forever. This reclaims those
  /// rows: a job that still has attempt budget returns to `queued`, and a job
  /// that already spent its budget becomes terminal `failed`. That second rule
  /// is what makes recovery bounded instead of an infinite restart loop.
  ///
  /// Returns the number of rows reclaimed. Idempotent: a second call finds
  /// nothing to do.
  Future<int> recoverInterruptedJobs();

  Future<void> insertCandidate(CompressionCandidate candidate);

  Future<CompressionCandidate?> findCandidateForJob(String jobId);

  Future<List<CompressionCandidate>> findCandidatesForResource(
    String resourceId,
  );

  /// Total characters saved by validated candidates of one resource.
  Future<int> sumSavedCharacters(String resourceId);
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
  Future<void> updateJob(CompressionJob job) async {
    final db = await _getDb();
    final now = (job.updatedAt ?? DateTime.now()).toIso8601String();
    await db.update(
      jobsTable,
      {
        'status': job.status.storageValue,
        'attempts': job.attempts,
        'error_message': job.errorMessage,
        'updated_at': now,
      },
      where: 'job_id = ?',
      whereArgs: [job.jobId],
    );
  }

  @override
  Future<List<CompressionJob>> findJobsByStatus(
    CompressionJobStatus status, {
    int limit = 50,
  }) async {
    final db = await _getDb();
    final rows = await db.query(
      jobsTable,
      where: 'status = ?',
      whereArgs: [status.storageValue],
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
  Future<int> recoverInterruptedJobs() async {
    final db = await _getDb();
    final now = DateTime.now().toIso8601String();
    final running = CompressionJobStatus.running.storageValue;

    // Two constant statements, no per-row loop. `attempts < max_attempts` is
    // evaluated per row, so a job created with a different budget is handled
    // correctly.
    final requeued = await db.update(
      jobsTable,
      {
        'status': CompressionJobStateMachine.recoveryTarget.storageValue,
        'error_message': '应用重启，已释放中断的压缩任务',
        'updated_at': now,
      },
      where: 'status = ? AND attempts < max_attempts',
      whereArgs: [running],
    );

    final exhausted = await db.update(
      jobsTable,
      {
        'status': CompressionJobStatus.failed.storageValue,
        'error_message': '应用中断且重试次数已用尽，需显式重试',
        'updated_at': now,
      },
      where: 'status = ? AND attempts >= max_attempts',
      whereArgs: [running],
    );

    return requeued + exhausted;
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
    );
  }

  static int _intOrZero(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
