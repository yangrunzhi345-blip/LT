import 'dart:async';

import '../../../../application/resources/streaming_generation_session_repository.dart';
import '../../../../application/resources/resource_blueprint_repository.dart';
import '../../../../application/resources/resource_creation_contracts.dart';
import '../../../../application/resources/resource_creation_pipeline.dart';
import '../../../../application/resource_library/accept_generated_related_character.dart';
import '../../../../application/resource_library/character_generation_reference.dart';
import '../../../../controllers/streaming_resource_generation_controller.dart';
import '../../../../domain/resources/resource_contracts.dart';
import '../../../../domain/resources/resource_blueprint.dart';
import '../../../../domain/resources/streaming_generation_runtime_contracts.dart';
import '../../../../services/repositories/resource_tree_repository_impl.dart';
import '../../../../services/repositories/character_relationship_repository.dart';
import '../../../../services/database_service.dart';
import '../../../../services/repositories/resource_tree_repository.dart';
import '../../../../application/llm/llm_gateway.dart';
import 'resource_ai_creation_orchestrator.dart';

/// Narrow application boundary consumed by the Studio controller.
///
/// Keeping the page behind this interface makes widget tests independent from
/// SQLite and the LLM gateway while production still uses the real runtime.
abstract interface class ResourceStudioRuntime {
  Stream<GenerationRuntimeEvent> get events;

  Future<ResourceTree?> readTree(ResourceId resourceId);

  Future<StreamingGenerationSession?> getSession(String sessionId);

  Future<StreamingGenerationSession?> getLatestSessionForResource(
    String resourceId,
  );

  Future<StreamingGenerationSession?> ensureSession(ResourceId resourceId);

  Future<List<StreamingGenerationSession>> findActiveSessions();

  Future<List<ResourceCreationSession>> pendingPlanningSessions();

  Future<List<Resource>> listResources();

  Future<bool> start(String sessionId);

  Future<void> pause(String sessionId);

  Future<bool> resume(String sessionId);

  Future<void> cancel(String sessionId);

  Future<bool> retryPart(String sessionId, String partId);

  Future<bool> recover(String sessionId);

  Future<StreamingGenerationSession> createAndStart({
    required ResourceType resourceType,
    required String name,
    required ReferenceSource referenceSource,
    required int targetCharacters,
    String origin = 'resource-studio',
    String libraryMode = 'adventure',
    String? idempotencyKey,
    ResourceId? targetResourceId,
    String originWorldviewId = '',
    CharacterRelationshipDraft? relationshipDraft,
  });

  /// Commits a reviewed generated character and its relationship edges.
  Future<ResourceId> acceptGeneratedCharacter({
    required ResourceId resourceId,
    required String creationSessionId,
    required String idempotencyKey,
  });

  Future<ResourceAiCreationPlan> createAndPlan(
    ResourceStudioCreationDraft draft,
  );

  Future<ResourceAiCreationIdentity> confirmAndStart(
    String creationSessionId, {
    Set<String>? selectedPartIds,
  });

  Future<Resource> createManual({
    required ResourceType resourceType,
    required String name,
    required String summary,
    required String libraryMode,
  });

  void dispose();
}

/// Production adapter connecting the headless runtime to the Studio feature.
final class StreamingResourceStudioRuntime implements ResourceStudioRuntime {
  StreamingResourceStudioRuntime({
    required StreamingResourceGenerationController controller,
    required IStreamingGenerationSessionRepository sessionRepository,
    required ResourceTreeRepositoryImpl treeRepository,
    required IResourceBlueprintRepository blueprintRepository,
    required ResourceCreationPipeline pipeline,
    required LlmGateway gateway,
    AcceptGeneratedRelatedCharacter? acceptance,
  })  : _controller = controller,
        _sessionRepository = sessionRepository,
        _treeRepository = treeRepository,
        _blueprintRepository = blueprintRepository,
        _pipeline = pipeline,
        _acceptance = acceptance ??
            AcceptGeneratedRelatedCharacter(
              resourceRepository: treeRepository,
              relationshipRepository: CharacterRelationshipRepositoryImpl(
                getDb: () => DatabaseService.database,
              ),
            ),
        _creationOrchestrator = ResourceAiCreationOrchestrator(
          controller: controller,
          sessionRepository: sessionRepository,
          treeRepository: treeRepository,
          blueprintRepository: blueprintRepository,
          pipeline: pipeline,
          gateway: gateway,
        );

  final StreamingResourceGenerationController _controller;
  final IStreamingGenerationSessionRepository _sessionRepository;
  final ResourceTreeRepositoryImpl _treeRepository;
  final IResourceBlueprintRepository _blueprintRepository;
  final ResourceCreationPipeline _pipeline;
  final AcceptGeneratedRelatedCharacter _acceptance;
  final ResourceAiCreationOrchestrator _creationOrchestrator;

  /// Shared AI creation authority used by Studio and legacy import adapters.
  ResourceAiCreationOrchestrator get creationOrchestrator =>
      _creationOrchestrator;

  @override
  Stream<GenerationRuntimeEvent> get events => _controller.events;

  /// The shared streaming controller.
  ///
  /// Exposed so the Phase 7 section-control executor reuses exactly one
  /// generation service and one event stream instead of constructing a second
  /// runtime that could not observe the same generation events.
  StreamingResourceGenerationController get controller => _controller;

  /// The shared generation-session repository, for the same reason.
  IStreamingGenerationSessionRepository get sessionRepository =>
      _sessionRepository;

  @override
  Future<ResourceTree?> readTree(ResourceId resourceId) =>
      _treeRepository.readTree(resourceId);

  @override
  Future<StreamingGenerationSession?> getSession(String sessionId) =>
      _controller.getSession(sessionId);

  @override
  Future<StreamingGenerationSession?> getLatestSessionForResource(
    String resourceId,
  ) =>
      _controller.getLatestSessionForResource(resourceId);

  @override
  Future<StreamingGenerationSession?> ensureSession(
      ResourceId resourceId) async {
    final existing = await getLatestSessionForResource(resourceId.value);
    if (existing != null) return existing;
    final tree = await readTree(resourceId);
    final creationSessionId =
        tree?.resource.metadata['creation_session_id']?.toString() ?? '';
    if (creationSessionId.isEmpty) return null;
    final blueprint =
        await _blueprintRepository.findLatestBlueprint(creationSessionId);
    if (blueprint == null ||
        blueprint.resourceId != resourceId ||
        blueprint.status != BlueprintStatus.confirmed) {
      return null;
    }
    return _controller.createSession(
      resourceId: resourceId.value,
      blueprintId: blueprint.blueprintId,
      creationSessionId: creationSessionId,
    );
  }

  @override
  Future<List<StreamingGenerationSession>> findActiveSessions() =>
      _sessionRepository.findActiveSessions();

  @override
  Future<List<ResourceCreationSession>> pendingPlanningSessions() =>
      _pipeline.pendingPlanningSessions();

  @override
  Future<List<Resource>> listResources() async {
    final resources = <Resource>[];
    for (final type in ResourceType.values) {
      resources.addAll(await _treeRepository.listResources(type: type));
    }
    resources.sort((a, b) => a.name.compareTo(b.name));
    return resources;
  }

  @override
  Future<bool> start(String sessionId) =>
      _controller.start(sessionId: sessionId);

  @override
  Future<void> pause(String sessionId) =>
      _controller.pause(sessionId: sessionId);

  @override
  Future<bool> resume(String sessionId) =>
      _controller.resume(sessionId: sessionId);

  @override
  Future<void> cancel(String sessionId) =>
      _controller.cancel(sessionId: sessionId);

  @override
  Future<bool> retryPart(String sessionId, String partId) =>
      _controller.retryPart(sessionId: sessionId, partId: partId);

  @override
  Future<bool> recover(String sessionId) =>
      _controller.recover(sessionId: sessionId);

  @override
  Future<StreamingGenerationSession> createAndStart({
    required ResourceType resourceType,
    required String name,
    required ReferenceSource referenceSource,
    required int targetCharacters,
    String origin = 'resource-studio',
    String libraryMode = 'adventure',
    String? idempotencyKey,
    ResourceId? targetResourceId,
    String originWorldviewId = '',
    CharacterRelationshipDraft? relationshipDraft,
  }) async {
    final operationId = idempotencyKey?.trim().isNotEmpty == true
        ? idempotencyKey!.trim()
        : 'studio_${DateTime.now().microsecondsSinceEpoch}';
    final identity = await _creationOrchestrator.createAndStart(
      ResourceAiCreationDraft(
        resourceType: resourceType,
        name: name,
        referenceSource: referenceSource,
        targetCharacters: targetCharacters,
        idempotencyKey: operationId,
        origin: origin,
        libraryMode: libraryMode,
        targetResourceId: targetResourceId,
        originWorldviewId: originWorldviewId,
        relationshipDraft: relationshipDraft,
      ),
    );
    final session =
        await _sessionRepository.findSession(identity.generationSessionId);
    if (session == null) throw StateError('创建的生成会话无法读取');
    return session;
  }

  @override
  Future<ResourceAiCreationPlan> createAndPlan(
    ResourceStudioCreationDraft draft,
  ) =>
      _creationOrchestrator.createAndPlan(
        ResourceAiCreationDraft(
          resourceType: draft.type,
          name: draft.name,
          referenceSource: draft.referenceSource,
          targetCharacters: draft.targetCharacters,
          idempotencyKey: draft.idempotencyKey ??
              'studio_${DateTime.now().microsecondsSinceEpoch}',
          origin: draft.origin,
          libraryMode: draft.libraryMode,
          targetResourceId: draft.targetResourceId,
          originWorldviewId: draft.originWorldviewId,
          relationshipDraft: draft.relationshipDraft,
        ),
      );

  @override
  Future<ResourceAiCreationIdentity> confirmAndStart(
    String creationSessionId, {
    Set<String>? selectedPartIds,
  }) =>
      _creationOrchestrator.confirmAndStart(
        creationSessionId,
        selectedPartIds: selectedPartIds,
      );

  @override
  Future<ResourceId> acceptGeneratedCharacter({
    required ResourceId resourceId,
    required String creationSessionId,
    required String idempotencyKey,
  }) async {
    final creation = await _pipeline.findSession(creationSessionId);
    if (creation == null || creation.resourceId != resourceId) {
      throw StateError('生成会话与候选资源不匹配');
    }
    final relationshipDraft = creation.relationshipDraft;
    if (relationshipDraft == null || relationshipDraft.isEmpty) {
      throw StateError('生成会话没有可接受的关系草稿');
    }
    final blueprint =
        await _blueprintRepository.findLatestBlueprint(creationSessionId);
    if (blueprint == null ||
        blueprint.status != BlueprintStatus.confirmed ||
        blueprint.resourceId != resourceId) {
      throw StateError('生成候选尚未完成确认或已过期');
    }
    final tree = await readTree(resourceId);
    if (tree == null) {
      throw ResourceTreeNotFoundException(
        '生成候选资源不存在：${resourceId.value}',
      );
    }
    final revision = blueprint.revision;
    final candidate = CharacterGenerationCandidate(
      candidateId: 'candidate_${creationSessionId}_r$revision',
      creationSessionId: creationSessionId,
      revision: revision,
      resourceId: resourceId,
    );
    final resource = ResourceTreeDraft(
      id: tree.resource.id,
      type: tree.resource.type,
      name: tree.resource.name,
      summary: tree.resource.summary,
      metadata: tree.resource.metadata,
      status: tree.resource.status,
      sections: [
        for (final section in tree.orderedSections)
          ResourceTreeSectionDraft(
            id: section.id,
            title: section.title,
            summary: section.summary,
            status: section.status,
            parts: [
              for (final part in tree.orderedPartsOf(section.id))
                ResourceTreePartDraft(
                  id: part.id,
                  title: part.title,
                  content: part.content,
                  status: part.status,
                ),
            ],
          ),
      ],
    );
    final edges = [
      for (final reference in relationshipDraft.relationship.references)
        CharacterRelationshipDraftInput(
          firstResourceId: reference.sourceResourceId,
          firstRole: reference.sourceRole,
          secondResourceId: resourceId,
          secondRole: reference.generatedCharacterRole,
          relationType: reference.relationshipType,
          description: reference.description,
        ),
    ];
    return _acceptance(
      resource: resource,
      relationships: edges,
      idempotencyKey: idempotencyKey,
      creationSessionId: creationSessionId,
      candidate: candidate,
    );
  }

  @override
  Future<Resource> createManual({
    required ResourceType resourceType,
    required String name,
    required String summary,
    required String libraryMode,
  }) async {
    final operationId = 'library_${DateTime.now().microsecondsSinceEpoch}';
    final result = await _pipeline.create(ResourceCreationRequest(
      resourceType: resourceType,
      method: CreationMethod.manual,
      name: name,
      summary: summary,
      idempotencyKey: operationId,
      origin: 'resource-library',
      libraryMode: libraryMode,
      createInitialEmptySection: true,
      initialSectionTitle: '正文',
    ));
    final resourceId = result.resourceId;
    if (resourceId == null) throw StateError('创建流程未返回资源');
    final tree = await _treeRepository.readTree(resourceId);
    if (tree == null) throw StateError('创建的资源无法读取');
    return tree.resource;
  }

  @override
  void dispose() => _controller.dispose();
}
