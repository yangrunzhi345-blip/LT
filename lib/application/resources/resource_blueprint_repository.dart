import 'dart:convert';
import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_blueprint.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_revision.dart';
import '../../services/repositories/resource_tree_repository.dart';
import '../../services/repositories/resource_tree_repository_impl.dart';
import 'blueprint_parser.dart';
import 'blueprint_validator.dart';
import 'resource_creation_contracts.dart';
import 'resource_revision_service.dart';

/// Outcome of confirming a [ResourceBlueprint].
final class ResourceBlueprintConfirmResult {
  const ResourceBlueprintConfirmResult({
    required this.blueprint,
    required this.resourceId,
    this.reusedExisting = false,
  });

  final ResourceBlueprint blueprint;
  final ResourceId resourceId;
  final bool reusedExisting;

  @override
  String toString() =>
      'ResourceBlueprintConfirmResult(resource: ${resourceId.value}, reused: $reusedExisting)';
}

/// One persisted generation task placeholder created upon blueprint confirmation.
final class ResourceGenerationTask {
  const ResourceGenerationTask({
    required this.taskId,
    required this.blueprintId,
    required this.resourceId,
    required this.sectionId,
    required this.partId,
    required this.promptGoal,
    required this.estimatedLength,
    this.dependencies = const <String>[],
    this.status = 'pending',
    this.sortOrder = 0,
    this.currentAttemptId = '',
    this.errorMessage = '',
    this.createdAt = '',
    this.updatedAt = '',
  });

  final String taskId;
  final String blueprintId;
  final String resourceId;
  final String sectionId;
  final String partId;
  final String promptGoal;
  final int estimatedLength;
  final List<String> dependencies;
  final String status;
  final int sortOrder;
  final String currentAttemptId;
  final String errorMessage;
  final String createdAt;
  final String updatedAt;

  @override
  String toString() =>
      'ResourceGenerationTask(id: $taskId, part: $partId, goal: $promptGoal, status: $status)';
}

/// Contract for persisting and managing [ResourceBlueprint] and generation tasks.
abstract interface class IResourceBlueprintRepository {
  Future<void> saveBlueprint(ResourceBlueprint blueprint);

  Future<ResourceBlueprint?> findBlueprint(String blueprintId);

  Future<ResourceBlueprint?> findLatestBlueprint(String sessionId);

  Future<List<ResourceBlueprint>> listBlueprints(String sessionId);

  Future<ResourceBlueprintConfirmResult> confirmBlueprint({
    required String blueprintId,
    String? nameOverride,
    ResourceId? explicitResourceId,
  });

  Future<List<ResourceGenerationTask>> findGenerationTasks(String blueprintId);

  Future<List<ResourceGenerationTask>> findGenerationTasksForResource(
      String resourceId);
}

/// SQLite implementation of [IResourceBlueprintRepository].
class ResourceBlueprintRepositoryImpl implements IResourceBlueprintRepository {
  ResourceBlueprintRepositoryImpl({
    required Future<Database> Function() getDb,
    ResourceTreeRepositoryImpl? treeRepository,
    RevisionCaptureEngine? revisionCapture,
  })  : _getDb = getDb,
        _treeRepository =
            treeRepository ?? ResourceTreeRepositoryImpl(getDb: getDb),
        _revisionCapture = revisionCapture;

  static const String blueprintsTable = 'resource_blueprints';
  static const String generationTasksTable = 'resource_generation_tasks';
  static const String sessionsTable = 'resource_creation_sessions';
  static const String resourcesTable = 'resources';

  final Future<Database> Function() _getDb;
  final ResourceTreeRepositoryImpl _treeRepository;

  /// Phase 9 revision boundary.
  ///
  /// Confirming a blueprint replaces the whole tree of an existing resource
  /// (`updateResourceTreeInTransaction` deletes every Section/Part and rewrites
  /// them), so it is a lossy write and must record a before/after revision in
  /// the same transaction. The branch is believed unreachable today with
  /// confirmed content — the session must be `planning`/`persisted` and the
  /// blueprint `draft` (audit P9-I2) — so this closes the hole before Phase 10
  /// starts re-planning resources.
  final RevisionCaptureEngine? _revisionCapture;

  String _now() => DateTime.now().toIso8601String();

  @override
  Future<void> saveBlueprint(ResourceBlueprint blueprint) async {
    final db = await _getDb();
    final now = _now();

    await db.transaction((txn) async {
      // If revision > 1, mark previous draft blueprints of the same session as superseded
      if (blueprint.revision > 1) {
        await txn.update(
          blueprintsTable,
          {
            'status': BlueprintStatus.superseded.storageValue,
            'updated_at': now,
          },
          where: 'session_id = ? AND status = ?',
          whereArgs: [
            blueprint.sessionId,
            BlueprintStatus.draft.storageValue,
          ],
        );
      }

      final jsonPayload = BlueprintParser.serializeToJson(blueprint);

      await txn.insert(
        blueprintsTable,
        {
          'blueprint_id': blueprint.blueprintId,
          'session_id': blueprint.sessionId,
          'resource_type': blueprint.resourceType.storageValue,
          'suggested_name': blueprint.suggestedName,
          'summary': blueprint.summary,
          'revision': blueprint.revision,
          'status': blueprint.status.storageValue,
          'target_capacity': blueprint.targetCapacity,
          'blueprint_json': jsonPayload,
          'resource_id': blueprint.resourceId?.value,
          'created_at': blueprint.createdAt.isEmpty ? now : blueprint.createdAt,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  @override
  Future<ResourceBlueprint?> findBlueprint(String blueprintId) async {
    final db = await _getDb();
    final rows = await db.query(
      blueprintsTable,
      where: 'blueprint_id = ?',
      whereArgs: [blueprintId],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return _mapRowToBlueprint(rows.first);
  }

  @override
  Future<ResourceBlueprint?> findLatestBlueprint(String sessionId) async {
    final db = await _getDb();
    final rows = await db.query(
      blueprintsTable,
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'revision DESC, created_at DESC',
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return _mapRowToBlueprint(rows.first);
  }

  @override
  Future<List<ResourceBlueprint>> listBlueprints(String sessionId) async {
    final db = await _getDb();
    final rows = await db.query(
      blueprintsTable,
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'revision ASC, created_at ASC',
    );

    return rows.map(_mapRowToBlueprint).toList();
  }

  @override
  Future<ResourceBlueprintConfirmResult> confirmBlueprint({
    required String blueprintId,
    String? nameOverride,
    ResourceId? explicitResourceId,
  }) async {
    return _treeRepository.runInTransaction((txn) async {
      final bpRows = await txn.query(
        blueprintsTable,
        where: 'blueprint_id = ?',
        whereArgs: [blueprintId],
        limit: 1,
      );

      if (bpRows.isEmpty) {
        throw ResourceTreeNotFoundException('Blueprint 不存在：$blueprintId');
      }

      final blueprint = _mapRowToBlueprint(bpRows.first);

      // Duplicate confirm idempotency check
      if (blueprint.status == BlueprintStatus.confirmed) {
        final existingResourceId = blueprint.resourceId;
        if (existingResourceId != null) {
          return ResourceBlueprintConfirmResult(
            blueprint: blueprint,
            resourceId: existingResourceId,
            reusedExisting: true,
          );
        }
      }

      if (blueprint.status != BlueprintStatus.draft) {
        throw StateError(
            '只有处于 draft 状态的 Blueprint 允许确认，当前状态: ${blueprint.status.storageValue}');
      }

      // Re-validate blueprint integrity before committing into formal resource tree (M4)
      BlueprintValidator.validate(blueprint);

      // Verify creation session
      final sessionRows = await txn.query(
        sessionsTable,
        where: 'session_id = ?',
        whereArgs: [blueprint.sessionId],
        limit: 1,
      );

      if (sessionRows.isEmpty) {
        throw ResourceTreeNotFoundException(
            '对应的创建会话不存在：${blueprint.sessionId}');
      }

      final sessionStatusStr = sessionRows.first['status'] as String? ?? '';
      final sessionStatus = CreationSessionStatus.fromStorage(sessionStatusStr);
      if (sessionStatus != CreationSessionStatus.planning &&
          sessionStatus != CreationSessionStatus.persisted) {
        throw ResourceCreationException(
          '创建会话当前状态为 ${sessionStatus.storageValue}，无法确认 Blueprint',
        );
      }

      final sessionResourceId = sessionRows.first['resource_id'] as String?;
      final encodedOrigin = sessionRows.first['origin']?.toString() ?? '';
      final originParts = encodedOrigin.split('|library_mode=');
      final creationOrigin = originParts.first;
      final libraryMode = originParts.length == 2 && originParts.last.isNotEmpty
          ? originParts.last
          : 'adventure';
      final allocatedResId = explicitResourceId ??
          (sessionResourceId != null && sessionResourceId.isNotEmpty
              ? ResourceId(sessionResourceId)
              : ResourceId('res_${blueprint.sessionId}'));

      // Ownership Boundary Check (H1): If an explicitResourceId was provided,
      // or if session recorded a resource_id, ensure that any existing resource
      // in the database actually belongs to this creation session / blueprint.
      final existingRes = await txn.query(
        resourcesTable,
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [allocatedResId.value],
        limit: 1,
      );

      if (existingRes.isNotEmpty) {
        // Resource already exists. Check ownership via metadata or session linkage.
        final rawMeta = existingRes.first['metadata_json'] as String? ?? '{}';
        Map<String, dynamic>? decodedMeta;
        try {
          final dynamic parsed = jsonDecode(rawMeta);
          if (parsed is Map<String, dynamic>) {
            decodedMeta = parsed;
          }
        } catch (_) {
          decodedMeta = null;
        }

        final existingSessionId =
            decodedMeta?['creation_session_id'] as String?;

        final isOwnSession = existingSessionId == blueprint.sessionId ||
            sessionResourceId == allocatedResId.value;

        if (!isOwnSession) {
          throw ResourceCreationException(
            '无法确认 Blueprint：指定资源 ${allocatedResId.value} 不属于当前创建会话 (${blueprint.sessionId})，禁止覆盖非本会话资源',
          );
        }
      }

      final now = _now();
      final finalName = nameOverride?.trim().isNotEmpty == true
          ? nameOverride!.trim()
          : blueprint.suggestedName.trim();

      // Build ResourceTreeDraft with Section and Part placeholders
      final treeSections = <ResourceTreeSectionDraft>[];
      for (final sec in blueprint.sections) {
        final secId = SectionId('${allocatedResId.value}_${sec.id}');
        final treeParts = <ResourceTreePartDraft>[];

        for (final p in sec.parts) {
          final partId = PartId('${allocatedResId.value}_${p.id}');
          treeParts.add(ResourceTreePartDraft(
            id: partId,
            title: p.title,
            content: '', // STRICTLY EMPTY: No prose is generated in Phase 4!
            status: NodeStatus.draft,
          ));
        }

        treeSections.add(ResourceTreeSectionDraft(
          id: secId,
          title: sec.title,
          summary: sec.summary,
          status: NodeStatus.draft,
          parts: treeParts,
        ));
      }

      final treeDraft = ResourceTreeDraft(
        id: allocatedResId,
        type: blueprint.resourceType,
        name: finalName,
        summary: blueprint.summary,
        status: NodeStatus.draft,
        metadata: {
          'creation_session_id': blueprint.sessionId,
          'confirmed_blueprint_id': blueprint.blueprintId,
          'blueprint_revision': blueprint.revision,
          ResourceTreeSchema.metadataAuthoringMethodKey: 'aiReference',
          'mode': libraryMode,
          if (creationOrigin.isNotEmpty) 'creation_origin': creationOrigin,
        },
        sections: treeSections,
      );

      // Check whether resource already exists
      if (existingRes.isEmpty) {
        await _treeRepository.createResourceTreeInTransaction(txn, treeDraft);
      } else {
        // Lossy: the whole tree is replaced, so the state being overwritten is
        // recorded first (in this same transaction, so a failure leaves the head
        // untouched) and the outcome is recorded after.
        final capture = _revisionCapture;
        if (capture != null) {
          await capture.captureBeforeWrite(
            txn,
            resourceId: allocatedResId,
            cause: RevisionCause.planning,
            now: _now(),
          );
        }
        await _treeRepository.updateResourceTreeInTransaction(txn, treeDraft);
        if (capture != null) {
          await capture.captureAfterWrite(
            txn,
            resourceId: allocatedResId,
            cause: RevisionCause.planning,
            now: _now(),
            label: '大纲确认',
          );
        }
      }

      // Create generation tasks for each Part placeholder
      for (final part in blueprint.allParts) {
        final taskId = 'task_${allocatedResId.value}_${part.id}';
        final mappedDeps =
            part.dependencies.map((d) => '${allocatedResId.value}_$d').toList();

        await txn.insert(
          generationTasksTable,
          {
            'task_id': taskId,
            'blueprint_id': blueprint.blueprintId,
            'resource_id': allocatedResId.value,
            'section_id': '${allocatedResId.value}_${part.sectionId}',
            'part_id': '${allocatedResId.value}_${part.id}',
            'prompt_goal': part.generationGoal,
            'estimated_length': part.estimatedLength,
            'dependencies_json': jsonEncode(mappedDeps),
            'status': 'pending',
            'sort_order': part.sortOrder,
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // Update blueprint status to confirmed
      final confirmedBlueprint = blueprint.copyWith(
        status: BlueprintStatus.confirmed,
        resourceId: allocatedResId,
        updatedAt: now,
      );
      await txn.update(
        blueprintsTable,
        {
          'status': BlueprintStatus.confirmed.storageValue,
          'resource_id': allocatedResId.value,
          'updated_at': now,
        },
        where: 'blueprint_id = ?',
        whereArgs: [blueprint.blueprintId],
      );

      // Update creation session status to completed
      await txn.update(
        sessionsTable,
        {
          'status': CreationSessionStatus.completed.storageValue,
          'resource_id': allocatedResId.value,
          'updated_at': now,
        },
        where: 'session_id = ?',
        whereArgs: [blueprint.sessionId],
      );

      return ResourceBlueprintConfirmResult(
        blueprint: confirmedBlueprint,
        resourceId: allocatedResId,
        reusedExisting: false,
      );
    });
  }

  @override
  Future<List<ResourceGenerationTask>> findGenerationTasks(
      String blueprintId) async {
    final db = await _getDb();
    final rows = await db.query(
      generationTasksTable,
      where: 'blueprint_id = ?',
      whereArgs: [blueprintId],
      orderBy: 'sort_order ASC, task_id ASC',
    );

    return rows.map(_mapRowToGenerationTask).toList();
  }

  @override
  Future<List<ResourceGenerationTask>> findGenerationTasksForResource(
      String resourceId) async {
    final db = await _getDb();
    final rows = await db.query(
      generationTasksTable,
      where: 'resource_id = ?',
      whereArgs: [resourceId],
      orderBy: 'sort_order ASC, task_id ASC',
    );

    return rows.map(_mapRowToGenerationTask).toList();
  }

  ResourceBlueprint _mapRowToBlueprint(Map<String, dynamic> row) {
    final jsonStr = row['blueprint_json'] as String? ?? '{}';
    final blueprintId = row['blueprint_id'] as String;
    final sessionId = row['session_id'] as String;
    final resourceTypeStr = row['resource_type'] as String;
    final revision = (row['revision'] as num?)?.toInt() ?? 1;
    final statusStr = row['status'] as String? ?? 'draft';
    final resourceIdStr = row['resource_id'] as String?;
    final createdAt = row['created_at'] as String? ?? '';
    final updatedAt = row['updated_at'] as String? ?? '';

    return BlueprintParser.deserializeFromJson(
      jsonStr,
      blueprintId: blueprintId,
      sessionId: sessionId,
      resourceType: ResourceType.fromStorageValue(resourceTypeStr),
      revision: revision,
      status: BlueprintStatus.fromStorage(statusStr),
      resourceId: resourceIdStr != null && resourceIdStr.isNotEmpty
          ? ResourceId(resourceIdStr)
          : null,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  ResourceGenerationTask _mapRowToGenerationTask(Map<String, dynamic> row) {
    final depsJson = row['dependencies_json'] as String? ?? '[]';
    final dynamic decodedDeps = jsonDecode(depsJson);
    final dependencies = <String>[];
    if (decodedDeps is List) {
      for (final d in decodedDeps) {
        if (d is String) dependencies.add(d);
      }
    }

    return ResourceGenerationTask(
      taskId: row['task_id'] as String,
      blueprintId: row['blueprint_id'] as String,
      resourceId: row['resource_id'] as String,
      sectionId: row['section_id'] as String,
      partId: row['part_id'] as String,
      promptGoal: row['prompt_goal'] as String? ?? '',
      estimatedLength: (row['estimated_length'] as num?)?.toInt() ?? 0,
      dependencies: dependencies,
      status: row['status'] as String? ?? 'pending',
      sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
      currentAttemptId: row['current_attempt_id'] as String? ?? '',
      errorMessage: row['error_message'] as String? ?? '',
      createdAt: row['created_at'] as String? ?? '',
      updatedAt: row['updated_at'] as String? ?? '',
    );
  }
}
