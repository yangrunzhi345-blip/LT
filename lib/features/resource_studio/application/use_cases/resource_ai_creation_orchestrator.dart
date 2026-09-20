import 'dart:async';

import '../../../../application/llm/llm_gateway.dart';
import '../../../../application/resources/resource_blueprint_repository.dart';
import '../../../../application/resources/resource_creation_contracts.dart';
import '../../../../application/resources/resource_creation_pipeline.dart';
import '../../../../application/resources/streaming_generation_session_repository.dart';
import '../../../../controllers/streaming_resource_generation_controller.dart';
import '../../../../domain/resources/resource_blueprint.dart';
import '../../../../domain/resources/resource_contracts.dart';
import '../../../../domain/resources/streaming_generation_runtime_contracts.dart';
import '../../../../services/repositories/resource_tree_repository_impl.dart';

/// Single orchestration authority for starting persisted AI resource creation.
///
/// Planning and confirmation complete before this use case returns because
/// they establish the stable resource identity. Body generation starts in the
/// background; its progress and errors remain authoritative in the persisted
/// [StreamingGenerationSession].
final class ResourceAiCreationOrchestrator {
  ResourceAiCreationOrchestrator({
    required StreamingResourceGenerationController controller,
    required IStreamingGenerationSessionRepository sessionRepository,
    required ResourceTreeRepositoryImpl treeRepository,
    required IResourceBlueprintRepository blueprintRepository,
    required ResourceCreationPipeline pipeline,
    required LlmGateway gateway,
  })  : _controller = controller,
        _sessionRepository = sessionRepository,
        _treeRepository = treeRepository,
        _blueprintRepository = blueprintRepository,
        _pipeline = pipeline,
        _gateway = gateway;

  final StreamingResourceGenerationController _controller;
  final IStreamingGenerationSessionRepository _sessionRepository;
  final ResourceTreeRepositoryImpl _treeRepository;
  final IResourceBlueprintRepository _blueprintRepository;
  final ResourceCreationPipeline _pipeline;
  final LlmGateway _gateway;
  final Map<String, Future<ResourceAiCreationIdentity>> _operations = {};

  /// Creates a logical AI request, or continues its idempotent earlier submit.
  Future<ResourceAiCreationIdentity> createAndStart(
    ResourceAiCreationDraft draft,
  ) {
    final operationKey = 'request:${draft.idempotencyKey.trim()}';
    return _runOnce(operationKey, () async {
      final plan = await _createAndPlan(draft);
      return confirmAndStart(plan.creationSessionId);
    });
  }

  /// Persists the creation request and its Blueprint without confirming it.
  ///
  /// Scene Batch uses this boundary to present the planned Parts as stable
  /// candidates. No resource, task, attempt, or model generation exists until
  /// [confirmAndStart] is called with the selected Part identities.
  Future<ResourceAiCreationPlan> createAndPlan(
    ResourceAiCreationDraft draft,
  ) {
    final operationKey = 'plan:${draft.idempotencyKey.trim()}';
    return _runPlanOnce(operationKey, () => _createAndPlan(draft));
  }

  Future<ResourceAiCreationPlan> _createAndPlan(
    ResourceAiCreationDraft draft,
  ) async {
    final resolvedReference = await _resolveReference(
      draft.referenceSource,
      originWorldviewId: draft.originWorldviewId,
    );
    final target = draft.targetResourceId;
    var expectedSourceToken = '';
    if (target != null) {
      final resource = await _treeRepository.findResource(target);
      if (resource == null) {
        throw StateError('要重新生成的资源已不存在');
      }
      if (resource.type != draft.resourceType) {
        throw StateError('要重新生成的资源类型不匹配');
      }
      expectedSourceToken =
          (await _treeRepository.readNodeState(target))?.updatedAt ?? '';
      if (expectedSourceToken.isEmpty) {
        throw StateError('无法读取既有资源版本，已拒绝启动 AI 重新生成');
      }
    }
    final origin = ResourceCreationOriginEnvelope(
      origin: draft.origin,
      libraryMode: draft.libraryMode,
      targetResourceId: target?.value ?? '',
      expectedSourceToken: expectedSourceToken,
      originWorldviewId: draft.originWorldviewId,
    );
    final creation = await _pipeline.create(ResourceCreationRequest(
      resourceType: draft.resourceType,
      method: CreationMethod.aiReference,
      name: draft.name,
      idempotencyKey: draft.idempotencyKey,
      referenceSource: resolvedReference,
      origin: origin.encode(),
      libraryMode: draft.libraryMode,
      targetCharacters: draft.targetCharacters,
    ));
    final creationSessionId = creation.sessionId;
    if (creationSessionId == null || creationSessionId.isEmpty) {
      throw StateError('创建流程未返回规划会话');
    }
    final blueprint =
        await _blueprintRepository.findLatestBlueprint(creationSessionId) ??
            await _pipeline.planAiSession(
              sessionId: creationSessionId,
              gateway: _gateway,
            );
    return ResourceAiCreationPlan(
      creationSessionId: creationSessionId,
      blueprint: blueprint,
    );
  }

  /// Continues an already persisted AI creation session without duplicating
  /// its blueprint, resource, generation tasks, or generation session.
  Future<ResourceAiCreationIdentity> continueAndStart(
    String creationSessionId,
  ) =>
      confirmAndStart(creationSessionId);

  /// Confirms a persisted Blueprint selection and starts the shared Runtime.
  Future<ResourceAiCreationIdentity> confirmAndStart(
    String creationSessionId, {
    Set<String>? selectedPartIds,
  }) {
    final normalizedId = creationSessionId.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError.value(
        creationSessionId,
        'creationSessionId',
        '创建会话 ID 不能为空',
      );
    }
    return _runOnce(
      'session:$normalizedId',
      () => _continuePersistedSession(
        normalizedId,
        selectedPartIds: selectedPartIds,
      ),
    );
  }

  Future<ResourceAiCreationIdentity> _continuePersistedSession(
    String creationSessionId, {
    Set<String>? selectedPartIds,
  }) async {
    final creationSession = await _pipeline.findSession(creationSessionId);
    if (creationSession == null) {
      throw ResourceCreationException('创建会话不存在：$creationSessionId');
    }
    if (!creationSession.isAi) {
      throw const ResourceCreationException('仅 AI 创建会话可以启动生成');
    }
    if (creationSession.status == CreationSessionStatus.cancelled ||
        creationSession.status == CreationSessionStatus.failed) {
      throw ResourceCreationException(
        '创建会话当前状态为 ${creationSession.status.storageValue}，无法继续',
      );
    }

    var blueprint =
        await _blueprintRepository.findLatestBlueprint(creationSessionId);
    blueprint ??= await _pipeline.planAiSession(
      sessionId: creationSessionId,
      gateway: _gateway,
    );

    final origin = ResourceCreationOriginEnvelope.decode(
      creationSession.origin,
    );
    final targetResourceId = origin.targetResourceId.isEmpty
        ? null
        : ResourceId(origin.targetResourceId);

    final ResourceId resourceId;
    switch (blueprint.status) {
      case BlueprintStatus.draft:
        final confirmation = await _pipeline.confirmAiBlueprint(
          blueprintId: blueprint.blueprintId,
          explicitResourceId: targetResourceId,
          expectedResourceUpdatedAt: origin.expectedSourceToken.isEmpty
              ? null
              : origin.expectedSourceToken,
          selectedPartIds: selectedPartIds,
        );
        resourceId = confirmation.resourceId;
      case BlueprintStatus.confirmed:
        final confirmedResourceId = blueprint.resourceId;
        if (confirmedResourceId == null) {
          throw const ResourceCreationException(
            '已确认的 Blueprint 缺少资源身份',
          );
        }
        resourceId = confirmedResourceId;
      case BlueprintStatus.superseded:
      case BlueprintStatus.cancelled:
        throw ResourceCreationException(
          'Blueprint 当前状态为 ${blueprint.status.storageValue}，无法继续',
        );
    }

    final generationSession = await _findOrCreateGenerationSession(
      creationSessionId: creationSessionId,
      resourceId: resourceId,
      blueprintId: blueprint.blueprintId,
    );
    if (generationSession.status == StreamingLifecycleStatus.created) {
      unawaited(_startInBackground(generationSession.sessionId));
    }
    return ResourceAiCreationIdentity(
      creationSessionId: creationSessionId,
      resourceId: resourceId,
      generationSessionId: generationSession.sessionId,
    );
  }

  Future<StreamingGenerationSession> _findOrCreateGenerationSession({
    required String creationSessionId,
    required ResourceId resourceId,
    required String blueprintId,
  }) async {
    final existingSessions =
        await _sessionRepository.findSessionsForResource(resourceId.value);
    for (final session in existingSessions.reversed) {
      if (session.creationSessionId == creationSessionId &&
          session.blueprintId == blueprintId) {
        return session;
      }
    }

    final deterministicSessionId = 'gen_$creationSessionId';
    final deterministicExisting =
        await _sessionRepository.findSession(deterministicSessionId);
    if (deterministicExisting != null) {
      if (deterministicExisting.resourceId != resourceId ||
          deterministicExisting.blueprintId != blueprintId) {
        throw StateError('生成会话身份与创建会话不一致');
      }
      return deterministicExisting;
    }

    try {
      return await _controller.createSession(
        resourceId: resourceId.value,
        blueprintId: blueprintId,
        creationSessionId: creationSessionId,
        sessionId: deterministicSessionId,
      );
    } on Object {
      // A concurrent continuation can win the unique session insert. Resolve
      // the deterministic identity and reuse it instead of allocating again.
      final winner =
          await _sessionRepository.findSession(deterministicSessionId);
      if (winner != null &&
          winner.resourceId == resourceId &&
          winner.blueprintId == blueprintId) {
        return winner;
      }
      rethrow;
    }
  }

  Future<void> _startInBackground(String sessionId) async {
    try {
      await _controller.start(sessionId: sessionId);
    } on Object {
      // The runtime converges generation failures into its persisted session
      // before rethrowing. A concurrent caller can also observe `created` and
      // lose the in-memory active-run race; in both cases persistence remains
      // the authority consumed by Resource Studio.
      await _sessionRepository.findSession(sessionId);
    }
  }

  Future<ReferenceSource> _resolveReference(
    ReferenceSource reference, {
    required String originWorldviewId,
  }) async {
    var resolved = reference;
    if (reference.kind == ReferenceSourceKind.existingResource) {
      final resourceId = reference.existingResourceId.trim();
      if (resourceId.isEmpty) throw StateError('请选择参考资源');
      final tree = await _treeRepository.readTree(ResourceId(resourceId));
      if (tree == null) throw StateError('参考资源已不存在');
      resolved = _withBody(reference, _treeBody(tree));
    }

    final worldviewId = originWorldviewId.trim();
    if (worldviewId.isEmpty ||
        resolved.existingResourceId.trim() == worldviewId) {
      return resolved;
    }
    final worldview = await _treeRepository.readTree(ResourceId(worldviewId));
    if (worldview == null ||
        worldview.resource.type != ResourceType.worldview) {
      throw StateError('关联的世界观已不存在或类型不正确');
    }
    final worldviewBody = _treeBody(worldview);
    final body = [
      if (resolved.body.trim().isNotEmpty) '[主要参考资料]\n${resolved.body}',
      '[关联世界观]\n$worldviewBody',
    ].join('\n\n');
    return _withBody(resolved, body);
  }

  ReferenceSource _withBody(ReferenceSource source, String body) {
    return ReferenceSource(
      kind: source.kind,
      label: source.label,
      body: body,
      fileName: source.fileName,
      existingResourceId: source.existingResourceId,
      characterCount: body.length,
    );
  }

  String _treeBody(ResourceTree tree) {
    return <String>[
      tree.resource.name,
      if (tree.resource.summary.trim().isNotEmpty) tree.resource.summary,
      for (final section in tree.orderedSections) ...[
        'Section: ${section.title}',
        if (section.summary.trim().isNotEmpty) section.summary,
        for (final part in tree.orderedPartsOf(section.id)) ...[
          'Part: ${part.title}',
          if (part.content.trim().isNotEmpty) part.content,
        ],
      ],
    ].join('\n');
  }

  Future<ResourceAiCreationIdentity> _runOnce(
    String key,
    Future<ResourceAiCreationIdentity> Function() operation,
  ) {
    final existing = _operations[key];
    if (existing != null) return existing;
    final future = operation();
    _operations[key] = future;
    return future.whenComplete(() {
      if (identical(_operations[key], future)) {
        _operations.remove(key);
      }
    });
  }

  final Map<String, Future<ResourceAiCreationPlan>> _planOperations = {};

  Future<ResourceAiCreationPlan> _runPlanOnce(
    String key,
    Future<ResourceAiCreationPlan> Function() operation,
  ) {
    final existing = _planOperations[key];
    if (existing != null) return existing;
    final future = operation();
    _planOperations[key] = future;
    return future.whenComplete(() {
      if (identical(_planOperations[key], future)) {
        _planOperations.remove(key);
      }
    });
  }
}
