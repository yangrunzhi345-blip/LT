import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/streaming_generation_runtime_contracts.dart';

/// Repository interface for persisting and managing streaming generation runtime sessions.
abstract interface class IStreamingGenerationSessionRepository {
  /// Creates and persists a new generation session.
  Future<StreamingGenerationSession> createSession(
    StreamingGenerationSession session,
  );

  /// Finds a generation session by its unique [sessionId].
  Future<StreamingGenerationSession?> findSession(String sessionId);

  /// Finds the latest generation session for [resourceId].
  Future<StreamingGenerationSession?> findLatestSessionForResource(
    String resourceId,
  );

  /// Lists all generation sessions associated with [resourceId].
  Future<List<StreamingGenerationSession>> findSessionsForResource(
    String resourceId,
  );

  /// Finds all currently active (non-terminal) sessions.
  Future<List<StreamingGenerationSession>> findActiveSessions();

  /// Updates an entire session state.
  Future<void> updateSession(StreamingGenerationSession session);

  /// Atomically transitions the session to a new [status] using [StreamingLifecycleStateMachine].
  Future<void> updateStatus(
    String sessionId,
    StreamingLifecycleStatus status, {
    String? currentPartId,
    String? currentTaskId,
    String? currentAttemptId,
    String? errorMessage,
  });

  /// Updates completed parts count and total parts count for [sessionId].
  Future<void> updateProgress(
    String sessionId, {
    required int completedCount,
    int? totalCount,
  });

  /// Finds sessions that were interrupted in mid-generation (e.g. app killed).
  Future<List<StreamingGenerationSession>> findInterruptedSessions();

  /// Transitions an interrupted session to `recovering` status.
  Future<void> markSessionRecovering(String sessionId);
}

/// SQLite implementation of [IStreamingGenerationSessionRepository].
class StreamingGenerationSessionRepositoryImpl
    implements IStreamingGenerationSessionRepository {
  StreamingGenerationSessionRepositoryImpl({
    required Future<Database> Function() getDb,
  }) : _getDb = getDb;

  static const String table = 'resource_generation_sessions';

  final Future<Database> Function() _getDb;
  bool _schemaEnsured = false;

  String _now() => DateTime.now().toIso8601String();

  /// Ensures table and indexes exist in the target database.
  static Future<void> ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $table (
        session_id TEXT PRIMARY KEY,
        resource_id TEXT NOT NULL,
        blueprint_id TEXT NOT NULL,
        creation_session_id TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'created',
        current_part_id TEXT,
        current_task_id TEXT,
        current_attempt_id TEXT,
        completed_parts_count INTEGER NOT NULL DEFAULT 0,
        total_parts_count INTEGER NOT NULL DEFAULT 0,
        error_message TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_gen_sessions_resource '
        'ON $table(resource_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_gen_sessions_blueprint '
        'ON $table(blueprint_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_gen_sessions_status '
        'ON $table(status, updated_at DESC)');
  }

  Future<Database> _db() async {
    final db = await _getDb();
    if (!_schemaEnsured) {
      await ensureSchema(db);
      _schemaEnsured = true;
    }
    return db;
  }

  @override
  Future<StreamingGenerationSession> createSession(
    StreamingGenerationSession session,
  ) async {
    final db = await _db();
    final now = _now();

    await db.insert(
      table,
      {
        'session_id': session.sessionId,
        'resource_id': session.resourceId.value,
        'blueprint_id': session.blueprintId,
        'creation_session_id': session.creationSessionId,
        'status': session.status.storageValue,
        'current_part_id': session.currentPartId?.value,
        'current_task_id': session.currentTaskId,
        'current_attempt_id': session.currentAttemptId,
        'completed_parts_count': session.completedPartsCount,
        'total_parts_count': session.totalPartsCount,
        'error_message': session.errorMessage,
        'created_at': session.createdAt.toIso8601String(),
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return session;
  }

  @override
  Future<StreamingGenerationSession?> findSession(String sessionId) async {
    final db = await _db();
    final rows = await db.query(
      table,
      where: 'session_id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _mapRowToSession(rows.first);
  }

  @override
  Future<StreamingGenerationSession?> findLatestSessionForResource(
    String resourceId,
  ) async {
    final db = await _db();
    final rows = await db.query(
      table,
      where: 'resource_id = ?',
      whereArgs: [resourceId],
      orderBy: 'updated_at DESC, created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _mapRowToSession(rows.first);
  }

  @override
  Future<List<StreamingGenerationSession>> findSessionsForResource(
    String resourceId,
  ) async {
    final db = await _db();
    final rows = await db.query(
      table,
      where: 'resource_id = ?',
      whereArgs: [resourceId],
      orderBy: 'created_at ASC',
    );
    return rows.map(_mapRowToSession).toList();
  }

  @override
  Future<List<StreamingGenerationSession>> findActiveSessions() async {
    final db = await _db();
    final rows = await db.query(
      table,
      where: 'status NOT IN (?, ?)',
      whereArgs: [
        StreamingLifecycleStatus.completed.storageValue,
        StreamingLifecycleStatus.cancelled.storageValue,
      ],
      orderBy: 'updated_at DESC',
    );
    return rows.map(_mapRowToSession).toList();
  }

  @override
  Future<void> updateSession(StreamingGenerationSession session) async {
    final db = await _db();
    final now = _now();
    await db.update(
      table,
      {
        'status': session.status.storageValue,
        'current_part_id': session.currentPartId?.value,
        'current_task_id': session.currentTaskId,
        'current_attempt_id': session.currentAttemptId,
        'completed_parts_count': session.completedPartsCount,
        'total_parts_count': session.totalPartsCount,
        'error_message': session.errorMessage,
        'updated_at': now,
      },
      where: 'session_id = ?',
      whereArgs: [session.sessionId],
    );
  }

  @override
  Future<void> updateStatus(
    String sessionId,
    StreamingLifecycleStatus status, {
    String? currentPartId,
    String? currentTaskId,
    String? currentAttemptId,
    String? errorMessage,
  }) async {
    final db = await _db();
    final now = _now();

    await db.transaction((txn) async {
      final rows = await txn.query(
        table,
        where: 'session_id = ?',
        whereArgs: [sessionId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('未找到生成运行时会话: $sessionId');
      }

      final existing = _mapRowToSession(rows.first);
      // Validate transition via domain state machine
      StreamingLifecycleStateMachine.advance(existing.status, status);

      final updateMap = <String, dynamic>{
        'status': status.storageValue,
        'updated_at': now,
      };

      if (currentPartId != null) {
        updateMap['current_part_id'] = currentPartId;
      }
      if (currentTaskId != null) {
        updateMap['current_task_id'] = currentTaskId;
      }
      if (currentAttemptId != null) {
        updateMap['current_attempt_id'] = currentAttemptId;
      }
      if (errorMessage != null) {
        updateMap['error_message'] = errorMessage;
      }

      await txn.update(
        table,
        updateMap,
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
    });
  }

  @override
  Future<void> updateProgress(
    String sessionId, {
    required int completedCount,
    int? totalCount,
  }) async {
    final db = await _db();
    final now = _now();
    final updateMap = <String, dynamic>{
      'completed_parts_count': completedCount,
      'updated_at': now,
    };
    if (totalCount != null) {
      updateMap['total_parts_count'] = totalCount;
    }

    await db.update(
      table,
      updateMap,
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  @override
  Future<List<StreamingGenerationSession>> findInterruptedSessions() async {
    final db = await _db();
    final inFlightStatuses = [
      StreamingLifecycleStatus.planning.storageValue,
      StreamingLifecycleStatus.generatingPart.storageValue,
      StreamingLifecycleStatus.receivingPatch.storageValue,
      StreamingLifecycleStatus.validating.storageValue,
      StreamingLifecycleStatus.committing.storageValue,
      StreamingLifecycleStatus.recovering.storageValue,
    ];

    final placeholders = List.filled(inFlightStatuses.length, '?').join(',');
    final rows = await db.query(
      table,
      where: 'status IN ($placeholders)',
      whereArgs: inFlightStatuses,
      orderBy: 'updated_at DESC',
    );
    return rows.map(_mapRowToSession).toList();
  }

  @override
  Future<void> markSessionRecovering(String sessionId) async {
    await updateStatus(
      sessionId,
      StreamingLifecycleStatus.recovering,
      errorMessage: 'System restart recovery in progress',
    );
  }

  StreamingGenerationSession _mapRowToSession(Map<String, dynamic> row) {
    final partIdRaw = row['current_part_id'] as String?;
    return StreamingGenerationSession(
      sessionId: row['session_id'] as String,
      resourceId: ResourceId(row['resource_id'] as String),
      blueprintId: row['blueprint_id'] as String,
      creationSessionId: row['creation_session_id'] as String? ?? '',
      status:
          StreamingLifecycleStatus.fromStorage(row['status'] as String? ?? ''),
      currentPartId:
          partIdRaw != null && partIdRaw.isNotEmpty ? PartId(partIdRaw) : null,
      currentTaskId: row['current_task_id'] as String?,
      currentAttemptId: row['current_attempt_id'] as String?,
      completedPartsCount: row['completed_parts_count'] as int? ?? 0,
      totalPartsCount: row['total_parts_count'] as int? ?? 0,
      errorMessage: row['error_message'] as String? ?? '',
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
