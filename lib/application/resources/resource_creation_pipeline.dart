import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_contracts.dart';
import '../../services/repositories/resource_tree_repository.dart';
import '../../services/repositories/resource_tree_repository_impl.dart';
import 'resource_creation_contracts.dart';

/// Reports whether AI creation is currently possible (model + API key present).
typedef AiCapabilityProbe = bool Function();

/// Read-only creation counters, safe for diagnostics.
final class ResourceCreationStats {
  const ResourceCreationStats({
    required this.total,
    required this.awaitingPlanning,
    required this.completed,
    required this.failed,
    required this.cancelled,
  });

  final int total;
  final int awaitingPlanning;
  final int completed;
  final int failed;
  final int cancelled;

  @override
  String toString() =>
      'creation(total: $total, awaitingPlanning: $awaitingPlanning, '
      'completed: $completed, failed: $failed, cancelled: $cancelled)';
}

/// The single creation pipeline every entry point goes through.
///
/// Both creation semantics are handled here so no entry point can own its own
/// validation, persistence or save flow:
/// - manual: validate, then write the resource tree in one transaction;
/// - AI: validate, then persist a session that awaits Phase 4 planning.
///
/// The AI path deliberately never generates body text — Phase 4 plans from the
/// persisted session and reference source.
final class ResourceCreationPipeline {
  ResourceCreationPipeline({
    required Future<Database> Function() getDb,
    required AiCapabilityProbe hasAiCredentials,
    ResourceTreeRepositoryImpl? treeRepository,
  })  : _getDb = getDb,
        _hasAiCredentials = hasAiCredentials,
        _treeRepository =
            treeRepository ?? ResourceTreeRepositoryImpl(getDb: getDb);

  static const String table = 'resource_creation_sessions';

  final Future<Database> Function() _getDb;
  final AiCapabilityProbe _hasAiCredentials;
  final ResourceTreeRepositoryImpl _treeRepository;

  int _sequence = 0;

  /// Metadata keys this pipeline records on the created resource.
  static const String metadataCreationSessionId = 'creation_session_id';
  static const String metadataCreationOrigin = 'creation_origin';
  static const String metadataReferenceKind = 'reference_kind';
  static const String metadataReferenceLabel = 'reference_label';
  static const String metadataReferenceCharCount = 'reference_char_count';

  /// Submits a creation request.
  ///
  /// Repeated submits with the same [ResourceCreationRequest.idempotencyKey]
  /// return the first result instead of creating again.
  Future<ResourceCreationResult> create(ResourceCreationRequest request) async {
    ResourceCreationValidator.validateResourceType(request.resourceType);
    ResourceCreationValidator.validate(
      request,
      hasAiCredentials: _hasAiCredentials,
    );

    final existing = await findByIdempotencyKey(request.idempotencyKey);
    if (existing != null) {
      _ensureSameRequest(existing, request);
      if (existing.status == CreationSessionStatus.cancelled) {
        throw const ResourceCreationException('该创建请求已取消');
      }
      // Anything already past validation is this request's own earlier attempt:
      // return it instead of creating a second resource. A failed session is
      // deliberately excluded so a retry can actually retry.
      if (existing.status == CreationSessionStatus.persisted ||
          existing.status == CreationSessionStatus.planning ||
          existing.status == CreationSessionStatus.completed) {
        return ResourceCreationResult(
          status: existing.status,
          idempotencyKey: request.idempotencyKey,
          resourceId: existing.resourceId,
          sessionId: existing.sessionId,
          reusedExisting: true,
        );
      }
    }

    final sessionId = existing?.sessionId ?? _newId('cre');
    final now = _now();

    if (existing == null) {
      await _insertSession(
        sessionId: sessionId,
        request: request,
        status: CreationSessionStatus.draft,
        now: now,
      );
    }
    var session = await _requireSession(sessionId);
    session = session.copyWith(
      status: _advance(session.status, CreationSessionStatus.validating),
    );
    await _updateSession(session, now: _now());

    if (request.isAi) {
      // Session only: nothing is generated and no resource row is created.
      final planned = session.copyWith(
        status: _advance(
          CreationSessionStatus.validating,
          CreationSessionStatus.planning,
        ),
      );
      await _updateSession(planned, now: _now());
      return ResourceCreationResult(
        status: CreationSessionStatus.planning,
        idempotencyKey: request.idempotencyKey,
        sessionId: sessionId,
      );
    }

    // Manual: persistence failure must leave no half-written resource.
    final explicitId = request.resourceId;
    final resourceId = explicitId == null
        ? ResourceId('res_$sessionId')
        : ResourceId(explicitId);
    final draft = ResourceTreeDraft(
      id: resourceId,
      type: request.resourceType,
      name: request.name.trim(),
      summary: request.summary,
      metadata: _metadataFor(request: request, sessionId: sessionId),
      sections: _sectionsFor(request),
    );
    try {
      // Upsert: an entry saving an existing resource updates it in place
      // instead of creating a second one.
      if (explicitId != null &&
          await _treeRepository.findResource(resourceId) != null) {
        await _treeRepository.updateResourceTree(draft);
      } else {
        await _treeRepository.createResourceTree(draft);
      }
    } catch (error) {
      // A previous attempt may have written the tree and then died before the
      // session row was updated. The deterministic resource id makes that
      // detectable, so reconcile instead of reporting a failure.
      final existingTree = await _treeRepository.findResource(resourceId);
      if (existingTree != null) {
        final reconciled = session.copyWith(
          status: _advance(
            CreationSessionStatus.validating,
            CreationSessionStatus.persisted,
          ),
          resourceId: resourceId,
        );
        await _updateSession(reconciled, now: _now());
        return ResourceCreationResult(
          status: CreationSessionStatus.persisted,
          idempotencyKey: request.idempotencyKey,
          resourceId: resourceId,
          sessionId: sessionId,
          reusedExisting: true,
        );
      }
      final failed = session.copyWith(
        status: _advance(
          CreationSessionStatus.validating,
          CreationSessionStatus.failed,
        ),
        errorMessage: '$error',
      );
      await _updateSession(failed, now: _now());
      throw ResourceCreationException('资源创建失败：$error');
    }

    final completed = session.copyWith(
      status: _advance(
        CreationSessionStatus.validating,
        CreationSessionStatus.persisted,
      ),
      resourceId: resourceId,
    );
    await _updateSession(completed, now: _now());

    return ResourceCreationResult(
      status: CreationSessionStatus.persisted,
      idempotencyKey: request.idempotencyKey,
      resourceId: resourceId,
      sessionId: sessionId,
    );
  }

  /// Cancels the session owning [idempotencyKey] or [sessionId].
  ///
  /// A completed manual creation cannot be cancelled: the resource exists, and
  /// pretending otherwise would strand it.
  Future<ResourceCreationSession> cancel({
    String? idempotencyKey,
    String? sessionId,
  }) async {
    final session = idempotencyKey != null
        ? await findByIdempotencyKey(idempotencyKey)
        : await findSession(sessionId ?? '');
    if (session == null) {
      throw const ResourceCreationException('创建会话不存在');
    }
    final cancelled = session.copyWith(
      status: _advance(session.status, CreationSessionStatus.cancelled),
    );
    await _updateSession(cancelled, now: _now());
    return cancelled;
  }

  /// Sessions that Phase 4 still has to plan.
  Future<List<ResourceCreationSession>> pendingPlanningSessions() async {
    final db = await _getDb();
    final rows = await db.query(
      table,
      where: 'status = ?',
      whereArgs: [CreationSessionStatus.planning.storageValue],
      orderBy: 'updated_at ASC',
    );
    return rows.map(_rowToSession).toList();
  }

  Future<ResourceCreationSession?> findByIdempotencyKey(String key) async {
    final db = await _getDb();
    final rows = await db.query(
      table,
      where: 'idempotency_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : _rowToSession(rows.first);
  }

  Future<ResourceCreationSession?> findSession(String sessionId) async {
    final db = await _getDb();
    final rows = await db.query(
      table,
      where: 'session_id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    return rows.isEmpty ? null : _rowToSession(rows.first);
  }

  Future<ResourceCreationStats> stats() async {
    final db = await _getDb();
    Future<int> count(CreationSessionStatus status) async {
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM $table WHERE status = ?',
        [status.storageValue],
      );
      return (rows.first['c'] as num).toInt();
    }

    final all = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    return ResourceCreationStats(
      total: (all.first['c'] as num).toInt(),
      awaitingPlanning: await count(CreationSessionStatus.planning),
      completed: await count(CreationSessionStatus.persisted),
      failed: await count(CreationSessionStatus.failed),
      cancelled: await count(CreationSessionStatus.cancelled),
    );
  }

  // ─── internals ───

  void _ensureSameRequest(
    ResourceCreationSession existing,
    ResourceCreationRequest request,
  ) {
    final same = existing.resourceType == request.resourceType &&
        existing.method == request.method &&
        existing.name.trim() == request.name.trim();
    if (!same) {
      throw ResourceCreationIdempotencyConflict(
        '幂等键 ${request.idempotencyKey} 已用于另一个创建请求',
      );
    }
  }

  List<ResourceTreeSectionDraft> _sectionsFor(
    ResourceCreationRequest request,
  ) {
    if (request.initialSections.isNotEmpty) return request.initialSections;
    if (request.createInitialEmptySection) {
      return <ResourceTreeSectionDraft>[
        ResourceTreeSectionDraft(
          title: request.initialSectionTitle.isEmpty
              ? '概览'
              : request.initialSectionTitle,
        ),
      ];
    }
    return const <ResourceTreeSectionDraft>[];
  }

  /// Minimal provenance: no reference body ever reaches metadata or logs.
  Map<String, Object?> _metadataFor({
    required ResourceCreationRequest request,
    required String sessionId,
  }) {
    final reference = request.referenceSource;
    return <String, Object?>{
      ...request.initialMetadata,
      'authoring_method': request.method.storageValue,
      'mode': request.libraryMode,
      metadataCreationSessionId: sessionId,
      if (request.origin.isNotEmpty) metadataCreationOrigin: request.origin,
      metadataReferenceKind: reference.kind.storageValue,
      if (reference.label.isNotEmpty) metadataReferenceLabel: reference.label,
      metadataReferenceCharCount: reference.characterCount,
      if (reference.existingResourceId.isNotEmpty)
        'reference_resource_id': reference.existingResourceId,
    };
  }

  CreationSessionStatus _advance(
    CreationSessionStatus from,
    CreationSessionStatus to,
  ) {
    try {
      return ResourceCreationStateMachine.advance(from, to);
    } on ResourceCreationException catch (error) {
      throw ResourceCreationException(error.message, field: 'status');
    }
  }

  Future<void> _insertSession({
    required String sessionId,
    required ResourceCreationRequest request,
    required CreationSessionStatus status,
    required String now,
  }) async {
    final db = await _getDb();
    final reference = request.referenceSource;
    try {
      await db.insert(table, {
        'session_id': sessionId,
        'idempotency_key': request.idempotencyKey,
        'resource_type': request.resourceType.storageValue,
        'method': request.method.storageValue,
        'name': request.name.trim(),
        'summary': request.summary,
        'status': status.storageValue,
        'reference_kind': reference.kind.storageValue,
        'reference_label': reference.label,
        'reference_file_name': reference.fileName,
        'reference_resource_id': reference.existingResourceId,
        'reference_body': reference.body,
        'reference_char_count': reference.characterCount,
        'origin': request.origin,
        'created_at': now,
        'updated_at': now,
      });
    } on DatabaseException catch (error) {
      // A concurrent submit won the race on the unique idempotency key.
      final winner = await findByIdempotencyKey(request.idempotencyKey);
      if (winner == null) rethrow;
      _ensureSameRequest(winner, request);
      throw ResourceCreationIdempotencyConflict(
        '并发提交被合并：${error.toString()}',
      );
    }
  }

  Future<ResourceCreationSession> _requireSession(String sessionId) async {
    final session = await findSession(sessionId);
    if (session == null) {
      throw const ResourceCreationException('创建会话不存在');
    }
    return session;
  }

  Future<void> _updateSession(
    ResourceCreationSession session, {
    required String now,
  }) async {
    final db = await _getDb();
    await db.update(
      table,
      {
        'status': session.status.storageValue,
        'resource_id': session.resourceId?.value,
        'error_message': session.errorMessage,
        'updated_at': now,
      },
      where: 'session_id = ?',
      whereArgs: [session.sessionId],
    );
  }

  ResourceCreationSession _rowToSession(Map<String, Object?> row) {
    final resourceId = row['resource_id']?.toString();
    return ResourceCreationSession(
      sessionId: row['session_id']?.toString() ?? '',
      idempotencyKey: row['idempotency_key']?.toString() ?? '',
      resourceType: ResourceType.fromStorageValue(
        row['resource_type']?.toString(),
      ),
      method:
          row['method']?.toString() == CreationMethod.aiReference.storageValue
              ? CreationMethod.aiReference
              : CreationMethod.manual,
      name: row['name']?.toString() ?? '',
      status: CreationSessionStatus.fromStorage(row['status']?.toString()),
      referenceSource: ReferenceSource(
        kind: ReferenceSourceKind.fromStorage(
          row['reference_kind']?.toString(),
        ),
        label: row['reference_label']?.toString() ?? '',
        body: row['reference_body']?.toString() ?? '',
        fileName: row['reference_file_name']?.toString() ?? '',
        existingResourceId: row['reference_resource_id']?.toString() ?? '',
        characterCount: (row['reference_char_count'] as num?)?.toInt() ?? 0,
      ),
      resourceId: (resourceId == null || resourceId.isEmpty)
          ? null
          : ResourceId(resourceId),
      errorMessage: row['error_message']?.toString() ?? '',
    );
  }

  String _now() => DateTime.now().toIso8601String();

  String _newId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${++_sequence}';
}
