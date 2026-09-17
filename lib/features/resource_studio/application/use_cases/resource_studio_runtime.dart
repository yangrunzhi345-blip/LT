import 'dart:async';

import '../../../../application/resources/streaming_generation_session_repository.dart';
import '../../../../application/resources/resource_blueprint_repository.dart';
import '../../../../application/resources/resource_creation_contracts.dart';
import '../../../../application/resources/resource_creation_pipeline.dart';
import '../../../../controllers/streaming_resource_generation_controller.dart';
import '../../../../domain/resources/resource_contracts.dart';
import '../../../../domain/resources/resource_blueprint.dart';
import '../../../../domain/resources/streaming_generation_runtime_contracts.dart';
import '../../../../services/repositories/resource_tree_repository_impl.dart';
import '../../../../application/llm/llm_gateway.dart';

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
    required String referenceText,
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
    required String referenceText,
  }) async {
    final operationId = 'studio_${DateTime.now().microsecondsSinceEpoch}';
    final creation = await _pipeline.create(ResourceCreationRequest(
      resourceType: resourceType,
      method: CreationMethod.aiReference,
      name: name,
      idempotencyKey: operationId,
      referenceSource: ReferenceSource.text(
        referenceText,
        label: 'Resource Studio reference',
      ),
      origin: 'resource-studio',
      libraryMode: 'adventure',
    ));
    final creationSessionId = creation.sessionId;
    if (creationSessionId == null) {
      throw StateError('创建流程未返回规划会话');
    }
    final blueprint = await _pipeline.planAiSession(
      sessionId: creationSessionId,
      gateway: _gateway,
    );
    final confirmation = await _pipeline.confirmAiBlueprint(
      blueprintId: blueprint.blueprintId,
    );
    final session = await _controller.createSession(
      resourceId: confirmation.resourceId.value,
      blueprintId: blueprint.blueprintId,
      creationSessionId: creationSessionId,
    );
    await _controller.start(sessionId: session.sessionId);
    return session;
  }

  @override
  void dispose() => _controller.dispose();
}
