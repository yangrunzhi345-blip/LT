import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_blueprint.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_limits.dart';
import '../../domain/resources/resource_revision.dart';
import '../../services/repositories/resource_tree_repository.dart';
import '../../services/repositories/resource_tree_repository_impl.dart';
import '../../utils/content_hasher.dart';
import '../../services/llm_service.dart';
import '../llm/llm_gateway.dart';
import 'blueprint_planner.dart';
import 'part_generation_coordinator.dart';
import 'resource_blueprint_repository.dart';
import 'resource_creation_contracts.dart';
import 'resource_generation_task_repository.dart';
import 'resource_revision_service.dart';

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
final class ResourceCreationPipeline implements ResourceCreationSessionReader {
  ResourceCreationPipeline({
    required Future<Database> Function() getDb,
    required AiCapabilityProbe hasAiCredentials,
    Future<void> Function(ResourceId resourceId)? onResourceReadyForAssembly,
    ResourceTreeRepositoryImpl? treeRepository,
    IResourceBlueprintRepository? blueprintRepository,
    IPartGenerationTaskRepository? generationTaskRepository,
    BlueprintPlanner? planner,
    PartGenerationCoordinator? coordinator,
    RevisionCaptureEngine? revisionCapture,
  })  : _getDb = getDb,
        _hasAiCredentials = hasAiCredentials,
        _onResourceReadyForAssembly = onResourceReadyForAssembly,
        _treeRepository =
            treeRepository ?? ResourceTreeRepositoryImpl(getDb: getDb),
        _blueprintRepository = blueprintRepository ??
            ResourceBlueprintRepositoryImpl(
              getDb: getDb,
              treeRepository: treeRepository,
            ),
        _generationTaskRepository = generationTaskRepository,
        _planner = planner,
        _coordinator = coordinator,
        _revisionCapture = revisionCapture;

  static const String table = 'resource_creation_sessions';

  final Future<Database> Function() _getDb;
  final AiCapabilityProbe _hasAiCredentials;
  final Future<void> Function(ResourceId resourceId)?
      _onResourceReadyForAssembly;
  final ResourceTreeRepositoryImpl _treeRepository;
  final IResourceBlueprintRepository _blueprintRepository;
  IPartGenerationTaskRepository? _generationTaskRepository;
  BlueprintPlanner? _planner;
  PartGenerationCoordinator? _coordinator;

  /// Phase 9 revision boundary. Optional so a pipeline built without it keeps
  /// its previous behaviour exactly; the production composition root injects
  /// it, which is what makes "save over an existing resource" recoverable.
  final RevisionCaptureEngine? _revisionCapture;

  /// Records the state a save is about to replace.
  Future<void> _captureRevisionBeforeOverwrite(
    DatabaseExecutor txn,
    ResourceId resourceId,
  ) async {
    final capture = _revisionCapture;
    if (capture == null) return;
    await capture.captureBeforeWrite(
      txn,
      resourceId: resourceId,
      cause: RevisionCause.manualSave,
      now: _now(),
    );
  }

  /// Records the state a save just produced.
  Future<void> _captureRevisionAfterOverwrite(
    DatabaseExecutor txn,
    ResourceId resourceId,
  ) async {
    final capture = _revisionCapture;
    if (capture == null) return;
    await capture.captureAfterWrite(
      txn,
      resourceId: resourceId,
      cause: RevisionCause.manualSave,
      now: _now(),
      label: '保存后快照',
    );
  }

  /// Returns the blueprint repository backing this pipeline.
  IResourceBlueprintRepository get blueprintRepository => _blueprintRepository;

  /// Returns or lazily constructs the [IPartGenerationTaskRepository] wired to this pipeline.
  IPartGenerationTaskRepository get generationTaskRepository =>
      _generationTaskRepository ??=
          PartGenerationTaskRepositoryImpl(getDb: _getDb);

  /// Returns or lazily constructs the [BlueprintPlanner] wired to this pipeline.
  BlueprintPlanner plannerWithGateway(LlmGateway gateway) {
    return _planner ??= BlueprintPlanner(
      pipeline: this,
      blueprintRepository: _blueprintRepository,
      gateway: gateway,
    );
  }

  /// Returns the configured planner, if any.
  BlueprintPlanner? get planner => _planner;

  /// Returns or lazily constructs the [PartGenerationCoordinator] wired to this pipeline.
  PartGenerationCoordinator coordinatorWithGateway(
    LlmGateway gateway, {
    int maxConcurrency = 2,
  }) {
    return _coordinator ??= PartGenerationCoordinator(
      taskRepository: generationTaskRepository,
      blueprintRepository: _blueprintRepository,
      pipeline: this,
      gateway: gateway,
      maxConcurrency: maxConcurrency,
    );
  }

  /// Returns the configured coordinator, if any.
  PartGenerationCoordinator? get coordinator => _coordinator;

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
      if (existing.status == CreationSessionStatus.validating &&
          !request.isAi) {
        final explicitId = request.resourceId;
        final candidateId = explicitId == null
            ? ResourceId('res_${existing.sessionId}')
            : ResourceId(explicitId);
        final existingTree = await _treeRepository.findResource(candidateId);
        if (existingTree != null) {
          final isSameSessionResource = (explicitId == null &&
                  candidateId.value == 'res_${existing.sessionId}') ||
              (existingTree.metadata[metadataCreationSessionId] ==
                  existing.sessionId);
          final matchesTarget = existingTree.type == request.resourceType &&
              existingTree.name == request.name.trim();
          if (isSameSessionResource && matchesTarget) {
            final now = _now();
            final reconciled = existing.copyWith(
              status: CreationSessionStatus.persisted,
              resourceId: candidateId,
              errorMessage: '',
            );
            await _updateSession(reconciled, now: now);
            return ResourceCreationResult(
              status: CreationSessionStatus.persisted,
              idempotencyKey: request.idempotencyKey,
              resourceId: candidateId,
              sessionId: existing.sessionId,
              reusedExisting: true,
            );
          }
        }
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
    if (existing != null && existing.status == CreationSessionStatus.failed) {
      final db = await _getDb();
      final reference = request.referenceSource;
      await db.update(
        table,
        {
          'status': session.status.storageValue,
          'summary': request.summary,
          'reference_kind': reference.kind.storageValue,
          'reference_label': reference.label,
          'reference_file_name': reference.fileName,
          'reference_resource_id': reference.existingResourceId,
          'reference_body': reference.body,
          'reference_char_count': reference.characterCount,
          'target_characters': _effectiveTargetCharacters(request),
          'request_fingerprint': _requestFingerprint(request),
          'error_message': '',
          'updated_at': now,
        },
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
    } else {
      await _updateSession(session, now: _now());
    }

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
      await _treeRepository.runInTransaction((txn) async {
        final rows = await txn.query(
          table,
          columns: const ['status'],
          where: 'session_id = ?',
          whereArgs: [sessionId],
          limit: 1,
        );
        final status = rows.isEmpty
            ? null
            : CreationSessionStatus.fromStorage(
                rows.single['status']?.toString());
        if (status != CreationSessionStatus.validating) {
          throw const ResourceCreationException('创建请求已取消或不再允许提交');
        }

        final existingTree = await txn.query(
          'resources',
          columns: const ['id'],
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: [resourceId.value],
          limit: 1,
        );
        if (existingTree.isNotEmpty) {
          // Phase 9: replacing an existing tree overwrites confirmed content, so
          // the pre-save state is recorded as a revision first — in this same
          // transaction, which means a failed save leaves the head untouched.
          await _captureRevisionBeforeOverwrite(txn, resourceId);
          await _treeRepository.updateResourceTreeInTransaction(txn, draft);
          await _captureRevisionAfterOverwrite(txn, resourceId);
        } else {
          await _treeRepository.createResourceTreeInTransaction(txn, draft);
          // R05-B: a freshly created tree must record its initial head
          // revision, otherwise it has no "latest saved version" and the
          // adventure readiness gate can never become ready for it.
          await _captureRevisionAfterOverwrite(txn, resourceId);
        }

        final updated = await txn.update(
          table,
          {
            'status': CreationSessionStatus.persisted.storageValue,
            'resource_id': resourceId.value,
            'error_message': '',
            'updated_at': _now(),
          },
          where: 'session_id = ? AND status = ?',
          whereArgs: [sessionId, CreationSessionStatus.validating.storageValue],
        );
        if (updated != 1) {
          throw const ResourceCreationException('创建请求在提交前已取消');
        }
      });
    } catch (error) {
      final failed = session.copyWith(
        status: _advance(
          CreationSessionStatus.validating,
          CreationSessionStatus.failed,
        ),
        errorMessage: '$error',
      );
      await _updateSessionIfStatus(
        failed,
        expected: CreationSessionStatus.validating,
        now: _now(),
      );
      throw ResourceCreationException('资源创建失败：$error');
    }

    // Persistence and assembly are separate authoritative stages.  A newly
    // persisted resource must enter readiness preparation before callers can
    // present it as consumable by Adventure.
    await _onResourceReadyForAssembly?.call(resourceId);

    return ResourceCreationResult(
      status: CreationSessionStatus.persisted,
      idempotencyKey: request.idempotencyKey,
      resourceId: resourceId,
      sessionId: sessionId,
    );
  }

  /// Commits a manual logical batch as one SQLite transaction.
  Future<List<ResourceCreationResult>> createBatch(
    List<ResourceCreationRequest> requests,
  ) async {
    for (final request in requests) {
      ResourceCreationValidator.validateResourceType(request.resourceType);
      ResourceCreationValidator.validate(
        request,
        hasAiCredentials: _hasAiCredentials,
      );
      if (request.isAi) {
        throw const ResourceCreationException(
            'AI planning requests cannot be mixed into a persistence batch');
      }
    }
    final results = await _treeRepository.runInTransaction((txn) async {
      final results = <ResourceCreationResult>[];
      for (final request in requests) {
        final existingRows = await txn.query(
          table,
          where: 'idempotency_key = ?',
          whereArgs: [request.idempotencyKey],
          limit: 1,
        );
        if (existingRows.isNotEmpty) {
          final existing = _rowToSession(existingRows.single);
          _ensureSameRequest(existing, request);
          if (existing.status != CreationSessionStatus.persisted) {
            throw const ResourceCreationException('批量请求包含未完成的已有会话');
          }
          results.add(ResourceCreationResult(
            status: existing.status,
            idempotencyKey: request.idempotencyKey,
            resourceId: existing.resourceId,
            sessionId: existing.sessionId,
            reusedExisting: true,
          ));
          continue;
        }
        final sessionId = _newId('cre');
        final resourceId = ResourceId(request.resourceId ?? 'res_$sessionId');
        final now = _now();
        await _insertSessionWithExecutor(
          txn,
          sessionId: sessionId,
          request: request,
          status: CreationSessionStatus.validating,
          now: now,
        );
        final draft = ResourceTreeDraft(
          id: resourceId,
          type: request.resourceType,
          name: request.name.trim(),
          summary: request.summary,
          metadata: _metadataFor(request: request, sessionId: sessionId),
          sections: _sectionsFor(request),
        );
        final rows = await txn.query(
          'resources',
          columns: const ['id'],
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: [resourceId.value],
          limit: 1,
        );
        if (rows.isEmpty) {
          await _treeRepository.createResourceTreeInTransaction(txn, draft);
          // R05-B: record the initial head, see the single-resource path.
          await _captureRevisionAfterOverwrite(txn, resourceId);
        } else {
          // Phase 9: see the single-resource path above.
          await _captureRevisionBeforeOverwrite(txn, resourceId);
          await _treeRepository.updateResourceTreeInTransaction(txn, draft);
          await _captureRevisionAfterOverwrite(txn, resourceId);
        }
        await txn.update(
          table,
          {
            'status': CreationSessionStatus.persisted.storageValue,
            'resource_id': resourceId.value,
            'updated_at': now,
          },
          where: 'session_id = ? AND status = ?',
          whereArgs: [sessionId, CreationSessionStatus.validating.storageValue],
        );
        results.add(ResourceCreationResult(
          status: CreationSessionStatus.persisted,
          idempotencyKey: request.idempotencyKey,
          resourceId: resourceId,
          sessionId: sessionId,
        ));
      }
      return results;
    });

    final prepare = _onResourceReadyForAssembly;
    if (prepare != null) {
      for (final result in results.where(
          (result) => !result.reusedExisting && result.resourceId != null)) {
        await prepare(result.resourceId!);
      }
    }
    return results;
  }

  /// Cancels the session owning [idempotencyKey] or [sessionId].
  ///
  /// A completed manual creation cannot be cancelled: the resource exists, and
  /// pretending otherwise would strand it.
  Future<ResourceCreationSession> cancel({
    String? idempotencyKey,
    String? sessionId,
  }) async {
    final db = await _getDb();
    return db.transaction((txn) async {
      final where =
          idempotencyKey != null ? 'idempotency_key = ?' : 'session_id = ?';
      final value = idempotencyKey ?? sessionId ?? '';
      final rows =
          await txn.query(table, where: where, whereArgs: [value], limit: 1);
      if (rows.isEmpty) {
        throw const ResourceCreationException('创建会话不存在');
      }
      final session = _rowToSession(rows.single);
      final cancelled = session.copyWith(
        status: _advance(session.status, CreationSessionStatus.cancelled),
      );
      final updated = await txn.update(
        table,
        {'status': cancelled.status.storageValue, 'updated_at': _now()},
        where: '$where AND status = ?',
        whereArgs: [value, session.status.storageValue],
      );
      if (updated != 1) {
        throw const ResourceCreationException('创建会话状态已变化，无法取消');
      }
      return cancelled;
    });
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

  /// Plans a blueprint for a pending planning session using the pipeline's planner.
  Future<ResourceBlueprint> planAiSession({
    required String sessionId,
    required LlmGateway gateway,
    GenerationTaskHandle? taskHandle,
    Duration timeout = const Duration(seconds: 60),
    BlueprintIdPool? idPool,
  }) async {
    final activePlanner = plannerWithGateway(gateway);
    return activePlanner.plan(
      sessionId: sessionId,
      taskHandle: taskHandle,
      timeout: timeout,
      idPool: idPool,
    );
  }

  /// Confirms a blueprint, creating tree placeholders and tasks in one transaction.
  Future<ResourceBlueprintConfirmResult> confirmAiBlueprint({
    required String blueprintId,
    String? nameOverride,
    ResourceId? explicitResourceId,
    String? expectedResourceUpdatedAt,
    Set<String>? selectedPartIds,
  }) async {
    final result = await _blueprintRepository.confirmBlueprint(
      blueprintId: blueprintId,
      nameOverride: nameOverride,
      explicitResourceId: explicitResourceId,
      expectedResourceUpdatedAt: expectedResourceUpdatedAt,
      selectedPartIds: selectedPartIds,
    );
    // Blueprint confirmation only creates draft placeholders and generation
    // tasks.  The streaming service owns the later readiness boundary after
    // all required parts have committed and a latest-head revision exists.
    return result;
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

  /// Returns the latest persisted session that wrote to [resourceId].
  Future<ResourceCreationSession?> latestSessionForResource(
    ResourceId resourceId,
  ) async {
    final db = await _getDb();
    final rows = await db.query(
      table,
      where: 'resource_id = ? AND status = ?',
      whereArgs: [
        resourceId.value,
        CreationSessionStatus.persisted.storageValue,
      ],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : _rowToSession(rows.first);
  }

  @override
  Future<ResourceCreationSession?> latestCreationSessionForResource(
    ResourceId resourceId,
  ) async {
    final db = await _getDb();
    final rows = await db.query(
      table,
      where: 'resource_id = ?',
      whereArgs: [resourceId.value],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : _rowToSession(rows.first);
  }

  /// Calculates request fingerprint for callers comparing payload identity.
  String requestFingerprint(ResourceCreationRequest request) =>
      _requestFingerprint(request);

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
        existing.name.trim() == request.name.trim() &&
        (existing.status == CreationSessionStatus.failed ||
            existing.requestFingerprint.isEmpty ||
            existing.requestFingerprint == _requestFingerprint(request));
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
          parts: const [ResourceTreePartDraft(title: '正文', content: '')],
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
    final metadata = <String, Object?>{...request.initialMetadata};
    // A caller-provided provenance wins, so an entry that saved AI-generated
    // content keeps its aiReference provenance.
    metadata.putIfAbsent(
      'authoring_method',
      () => request.method.storageValue,
    );
    return <String, Object?>{
      ...metadata,
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
    try {
      await _insertSessionWithExecutor(db,
          sessionId: sessionId, request: request, status: status, now: now);
    } on DatabaseException catch (_) {
      // A concurrent submit won the race on the unique idempotency key.
      final winner = await findByIdempotencyKey(request.idempotencyKey);
      if (winner == null) rethrow;
      _ensureSameRequest(winner, request);
      throw const ResourceCreationIdempotencyConflict(
        'resourceConflict',
      );
    }
  }

  Future<void> _insertSessionWithExecutor(
    DatabaseExecutor executor, {
    required String sessionId,
    required ResourceCreationRequest request,
    required CreationSessionStatus status,
    required String now,
  }) async {
    final reference = request.referenceSource;
    await executor.insert(table, {
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
      'target_characters': _effectiveTargetCharacters(request),
      'origin': request.origin,
      'request_fingerprint': _requestFingerprint(request),
      'created_at': now,
      'updated_at': now,
    });
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

  Future<bool> _updateSessionIfStatus(
    ResourceCreationSession session, {
    required CreationSessionStatus expected,
    required String now,
  }) async {
    final db = await _getDb();
    final updated = await db.update(
      table,
      {
        'status': session.status.storageValue,
        'resource_id': session.resourceId?.value,
        'error_message': session.errorMessage,
        'updated_at': now,
      },
      where: 'session_id = ? AND status = ?',
      whereArgs: [session.sessionId, expected.storageValue],
    );
    return updated == 1;
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
      targetCharacters: _storedTargetCharacters(row),
      origin: row['origin']?.toString() ?? '',
      requestFingerprint: row['request_fingerprint']?.toString() ?? '',
      resourceId: (resourceId == null || resourceId.isEmpty)
          ? null
          : ResourceId(resourceId),
      errorMessage: row['error_message']?.toString() ?? '',
    );
  }

  String _now() => DateTime.now().toIso8601String();

  String _requestFingerprint(ResourceCreationRequest request) {
    return ContentHasher.hash({
      'type': request.resourceType.storageValue,
      'method': request.method.storageValue,
      'name': request.name.trim(),
      'summary': request.summary,
      'resourceId': request.resourceId,
      'origin': request.origin,
      'mode': request.libraryMode,
      'referenceKind': request.referenceSource.kind.storageValue,
      'referenceBody': request.referenceSource.body,
      'referenceResourceId': request.referenceSource.existingResourceId,
      if (request.targetCharacters != null)
        'targetCharacters': request.targetCharacters,
      'metadata': request.initialMetadata,
      'sections': request.initialSections
          .map((section) => {
                'id': section.id?.value,
                'title': section.title,
                'summary': section.summary,
                'status': section.status.storageValue,
                'parts': section.parts
                    .map((part) => {
                          'id': part.id?.value,
                          'title': part.title,
                          'content': part.content,
                          'status': part.status.storageValue,
                        })
                    .toList(growable: false),
              })
          .toList(growable: false),
    });
  }

  String _newId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${++_sequence}';

  int _effectiveTargetCharacters(ResourceCreationRequest request) =>
      request.isAi
          ? request.targetCharacters ??
              ResourceLimits.policyFor(request.resourceType).nominalCharacters
          : 0;

  int _storedTargetCharacters(Map<String, Object?> row) {
    final stored = (row['target_characters'] as num?)?.toInt() ?? 0;
    if (stored > 0) return stored;
    if (row['method']?.toString() != CreationMethod.aiReference.storageValue) {
      return 0;
    }
    final type =
        ResourceType.fromStorageValue(row['resource_type']?.toString());
    return ResourceLimits.policyFor(type).nominalCharacters;
  }
}
