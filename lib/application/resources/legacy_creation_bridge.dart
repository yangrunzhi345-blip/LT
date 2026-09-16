import '../../domain/resources/resource_blueprint.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../services/llm_service.dart';
import '../../services/repositories/resource_tree_repository.dart';
import '../llm/llm_gateway.dart';
import 'legacy_resource_mapper.dart';
import 'resource_blueprint_repository.dart';
import 'resource_creation_contracts.dart';
import 'resource_creation_pipeline.dart';

final class LegacyCardSave {
  const LegacyCardSave({
    required this.type,
    required this.id,
    required this.name,
    required this.jsonData,
    required this.mode,
    required this.origin,
    this.authoringMethod = 'manual',
    this.aiGenerationDepth = '',
    this.source = '',
    this.matchingWorldviewId = '',
    this.operationId,
  });

  final ResourceType type;
  final String id;
  final String name;
  final String jsonData;
  final String mode;
  final String origin;
  final String authoringMethod;
  final String aiGenerationDepth;
  final String source;
  final String matchingWorldviewId;
  final String? operationId;
}

/// Adapter that lets every existing entry point hand its payload to the unified
/// creation pipeline without knowing anything about the content tree.
///
/// Subclassable so tests can record what an entry handed over.
///
/// This is what makes "old pages are only compatibility shells" true: the page
/// still builds its worldview/card payload exactly as before, then calls one of
/// these methods instead of writing a legacy table. Mapping, validation,
/// provenance and persistence all happen in one place.
class LegacyCreationBridge {
  LegacyCreationBridge(
    this._pipeline, {
    LegacyResourceMapper mapper = const LegacyResourceMapper(),
  }) : _mapper = mapper;

  final ResourceCreationPipeline _pipeline;
  final LegacyResourceMapper _mapper;
  static int _operationSequence = 0;

  /// Returns the underlying creation pipeline.
  ResourceCreationPipeline get pipeline => _pipeline;

  /// Retrieves sessions waiting for adaptive blueprint planning.
  Future<List<ResourceCreationSession>> pendingPlanningSessions() =>
      _pipeline.pendingPlanningSessions();

  /// Plans an adaptive blueprint for an existing planning session.
  Future<ResourceBlueprint> planAiSession({
    required String sessionId,
    required LlmGateway gateway,
    GenerationTaskHandle? taskHandle,
    Duration timeout = const Duration(seconds: 60),
    BlueprintIdPool? idPool,
  }) {
    return _pipeline.planAiSession(
      sessionId: sessionId,
      gateway: gateway,
      taskHandle: taskHandle,
      timeout: timeout,
      idPool: idPool,
    );
  }

  /// Confirms a blueprint, creating placeholder nodes and generation tasks in the tree.
  Future<ResourceBlueprintConfirmResult> confirmAiBlueprint({
    required String blueprintId,
    String? nameOverride,
    ResourceId? explicitResourceId,
  }) {
    return _pipeline.confirmAiBlueprint(
      blueprintId: blueprintId,
      nameOverride: nameOverride,
      explicitResourceId: explicitResourceId,
    );
  }

  static String newOperationId(String origin) =>
      '${origin}_${DateTime.now().microsecondsSinceEpoch}_${++_operationSequence}';

  /// Starts the formal AI creation path. It persists only a planning session.
  Future<ResourceCreationResult> planAiCreation({
    required ResourceType type,
    required String name,
    required ReferenceSource referenceSource,
    required String origin,
    required String mode,
    String? operationId,
  }) {
    return _pipeline.create(ResourceCreationRequest(
      resourceType: type,
      method: CreationMethod.aiReference,
      name: name,
      idempotencyKey: operationId ?? newOperationId(origin),
      referenceSource: referenceSource,
      origin: origin,
      libraryMode: mode,
    ));
  }

  /// Metadata keys the mapper adds for *migration*; an entry-created resource
  /// has no legacy source, so they must not be recorded.
  static const Set<String> _migrationOnlyMetadataKeys = {
    LegacyResourceMapper.metadataLegacySourceTable,
    LegacyResourceMapper.metadataLegacySourceId,
    LegacyResourceMapper.metadataLegacySourceHash,
  };

  /// Saves a worldview preset through the pipeline.
  ///
  /// Upserts by [id]: saving an existing worldview updates that same resource.
  Future<ResourceCreationResult> saveWorldview({
    required String id,
    required String name,
    required String description,
    required String detailJson,
    required String entriesJson,
    required String mode,
    String authoringMethod = 'manual',
    String aiGenerationDepth = '',
    String source = '',
    String matchingWorldviewId = '',
    required String origin,
    String? operationId,
  }) {
    final row = <String, Object?>{
      'id': id,
      'name': name,
      'description': description,
      'detail_json': detailJson,
      'entries_json': entriesJson,
      'mode': mode,
      'authoring_method': authoringMethod,
      'ai_generation_depth': aiGenerationDepth,
      'source': source,
      'matching_worldview_id': matchingWorldviewId,
    };
    final draft = _normalize(_mapper.mapWorldview(row), id);
    return _submit(
      draft: draft,
      type: ResourceType.worldview,
      name: name.isEmpty ? id : name,
      summary: description,
      mode: mode,
      authoringMethod: authoringMethod,
      origin: origin,
      resourceId: id,
      operationId: operationId,
    );
  }

  /// Saves a character card or NPC through the pipeline.
  Future<ResourceCreationResult> saveCard({
    required ResourceType type,
    required String id,
    required String name,
    required String jsonData,
    required String mode,
    String authoringMethod = 'manual',
    String aiGenerationDepth = '',
    String source = '',
    String matchingWorldviewId = '',
    Map<String, Object?> extraMetadata = const <String, Object?>{},
    required String origin,
    String? operationId,
  }) {
    final row = <String, Object?>{
      'id': id,
      'name': name,
      'json_data': jsonData,
      'mode': mode,
      'authoring_method': authoringMethod,
      'ai_generation_depth': aiGenerationDepth,
      'source': source,
      'matching_worldview_id': matchingWorldviewId,
    };
    final draft = _normalize(
      type == ResourceType.npc
          ? _mapper.mapNpc(row)
          : _mapper.mapCharacter(row),
      id,
    );
    return _submit(
      draft: draft,
      type: type,
      name: name.isEmpty ? id : name,
      summary: '',
      mode: mode,
      authoringMethod: authoringMethod,
      origin: origin,
      resourceId: id,
      operationId: operationId,
    );
  }

  Future<List<ResourceCreationResult>> saveCards(
    List<LegacyCardSave> cards,
  ) async {
    final requests = <ResourceCreationRequest>[];
    for (final card in cards) {
      final row = <String, Object?>{
        'id': card.id,
        'name': card.name,
        'json_data': card.jsonData,
        'mode': card.mode,
        'authoring_method': card.authoringMethod,
        'ai_generation_depth': card.aiGenerationDepth,
        'source': card.source,
        'matching_worldview_id': card.matchingWorldviewId,
      };
      final draft = _normalize(
        card.type == ResourceType.npc
            ? _mapper.mapNpc(row)
            : _mapper.mapCharacter(row),
        card.id,
      );
      final opId = card.operationId ??
          await _resolveOperationId(
            draft: draft,
            type: card.type,
            name: card.name.isEmpty ? card.id : card.name,
            summary: '',
            mode: card.mode,
            origin: card.origin,
            resourceId: card.id,
          );
      requests.add(_request(
        draft: draft,
        type: card.type,
        name: card.name.isEmpty ? card.id : card.name,
        summary: '',
        mode: card.mode,
        origin: card.origin,
        resourceId: card.id,
        operationId: opId,
      ));
    }
    return _pipeline.createBatch(requests);
  }

  /// The tree resource id backing a legacy id.
  ///
  /// Entry-created resources keep the caller's id, so a legacy row and its tree
  /// resource are the same identity and can never show up twice.
  static ResourceId resourceIdFor(String legacyId) => ResourceId(legacyId);

  ResourceTreeDraft _normalize(ResourceTreeDraft draft, String id) => draft
      .withId(resourceIdFor(id))
      .withoutMetadataKeys(_migrationOnlyMetadataKeys);

  Future<ResourceCreationResult> _submit({
    required ResourceTreeDraft draft,
    required ResourceType type,
    required String name,
    required String summary,
    required String mode,
    required String authoringMethod,
    required String origin,
    required String resourceId,
    String? operationId,
  }) async {
    final resolvedOpId = operationId ??
        await _resolveOperationId(
          draft: draft,
          type: type,
          name: name,
          summary: summary,
          mode: mode,
          origin: origin,
          resourceId: resourceId,
        );
    return _pipeline.create(_request(
      draft: draft,
      type: type,
      name: name,
      summary: summary,
      mode: mode,
      origin: origin,
      resourceId: resourceId,
      operationId: resolvedOpId,
    ));
  }

  Future<String> _resolveOperationId({
    required ResourceTreeDraft draft,
    required ResourceType type,
    required String name,
    required String summary,
    required String mode,
    required String origin,
    required String resourceId,
  }) async {
    final candidate = _request(
      draft: draft,
      type: type,
      name: name,
      summary: summary,
      mode: mode,
      origin: origin,
      resourceId: resourceId,
      operationId: 'probe',
    );
    final candidateFingerprint = _pipeline.requestFingerprint(candidate);
    final latestSession = await _pipeline.latestSessionForResource(
      ResourceId(resourceId),
    );
    if (latestSession != null &&
        latestSession.status == CreationSessionStatus.persisted &&
        latestSession.requestFingerprint.isNotEmpty &&
        latestSession.requestFingerprint == candidateFingerprint) {
      return latestSession.idempotencyKey;
    }
    return newOperationId(origin);
  }

  ResourceCreationRequest _request({
    required ResourceTreeDraft draft,
    required ResourceType type,
    required String name,
    required String summary,
    required String mode,
    required String origin,
    required String resourceId,
    String? operationId,
  }) =>
      ResourceCreationRequest(
        resourceType: type,
        method: CreationMethod.manual,
        name: name,
        idempotencyKey: operationId ?? newOperationId(origin),
        summary: summary,
        resourceId: resourceId,
        initialSections: draft.sections,
        initialMetadata: draft.metadata,
        origin: origin,
        libraryMode: mode,
      );
}
