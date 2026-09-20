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
      final resolvedReference = await _resolveReference(draft.referenceSource);
      final creation = await _pipeline.create(ResourceCreationRequest(
        resourceType: draft.resourceType,
        method: CreationMethod.aiReference,
        name: draft.name,
        idempotencyKey: draft.idempotencyKey,
        referenceSource: resolvedReference,
        // The frozen v44 creation-session schema has no library-mode column.
        // Persist it with origin so confirmation/restart can recover it without
        // a schema migration; ResourceBlueprintRepository decodes this value.
        origin: '${draft.origin}|library_mode=${draft.libraryMode}',
        libraryMode: draft.libraryMode,
        targetCharacters: draft.targetCharacters,
      ));
      final creationSessionId = creation.sessionId;
      if (creationSessionId == null || creationSessionId.isEmpty) {
        throw StateError('创建流程未返回规划会话');
      }
      return continueAndStart(creationSessionId);
    });
  }

  /// Continues an already persisted AI creation session without duplicating
  /// its blueprint, resource, generation tasks, or generation session.
  Future<ResourceAiCreationIdentity> continueAndStart(
    String creationSessionId,
  ) {
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
      () => _continuePersistedSession(normalizedId),
    );
  }

  Future<ResourceAiCreationIdentity> _continuePersistedSession(
    String creationSessionId,
  ) async {
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

    final ResourceId resourceId;
    switch (blueprint.status) {
      case BlueprintStatus.draft:
        final confirmation = await _pipeline.confirmAiBlueprint(
          blueprintId: blueprint.blueprintId,
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

  Future<ReferenceSource> _resolveReference(ReferenceSource reference) async {
    if (reference.kind != ReferenceSourceKind.existingResource) {
      return reference;
    }
    final resourceId = reference.existingResourceId.trim();
    if (resourceId.isEmpty) throw StateError('请选择参考资源');
    final tree = await _treeRepository.readTree(ResourceId(resourceId));
    if (tree == null) throw StateError('参考资源已不存在');
    final body = <String>[
      tree.resource.name,
      if (tree.resource.summary.trim().isNotEmpty) tree.resource.summary,
      for (final section in tree.orderedSections) ...[
        section.title,
        for (final part in tree.orderedPartsOf(section.id))
          if (part.content.trim().isNotEmpty) part.content,
      ],
    ].join('\n');
    return ReferenceSource(
      kind: ReferenceSourceKind.existingResource,
      label: reference.label,
      body: body,
      existingResourceId: resourceId,
      characterCount: body.length,
    );
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
}
