import '../../domain/resources/resource_contracts.dart';
import '../../services/repositories/resource_tree_repository.dart';
import '../../utils/content_hasher.dart';
import 'legacy_resource_mapper.dart';
import 'resource_creation_contracts.dart';
import 'resource_creation_pipeline.dart';

/// Adapter that lets every existing entry point hand its payload to the unified
/// creation pipeline without knowing anything about the content tree.
///
/// This is what makes "old pages are only compatibility shells" true: the page
/// still builds its worldview/card payload exactly as before, then calls one of
/// these methods instead of writing a legacy table. Mapping, validation,
/// provenance and persistence all happen in one place.
final class LegacyCreationBridge {
  LegacyCreationBridge(
    this._pipeline, {
    LegacyResourceMapper mapper = const LegacyResourceMapper(),
  }) : _mapper = mapper;

  final ResourceCreationPipeline _pipeline;
  final LegacyResourceMapper _mapper;

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
    );
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
  }) {
    return _pipeline.create(ResourceCreationRequest(
      resourceType: type,
      method: authoringMethod == CreationMethod.aiReference.storageValue
          ? CreationMethod.aiReference
          : CreationMethod.manual,
      name: name,
      idempotencyKey: idempotencyKeyFor(
        origin: origin,
        resourceId: resourceId,
        draft: draft,
      ),
      summary: summary,
      resourceId: resourceId,
      initialSections: draft.sections,
      initialMetadata: draft.metadata,
      origin: origin,
      libraryMode: mode,
    ));
  }

  /// Stable key for one (entry, resource, content) combination.
  ///
  /// Re-saving identical content is idempotent, while a real edit produces a new
  /// key and therefore a real update instead of a silently ignored save.
  static String idempotencyKeyFor({
    required String origin,
    required String resourceId,
    required ResourceTreeDraft draft,
  }) {
    final canonical = <String, Object?>{
      'origin': origin,
      'resource': resourceId,
      'name': draft.name,
      'summary': draft.summary,
      'sections': draft.sections
          .map((section) => <String, Object?>{
                'title': section.title,
                'status': section.status.storageValue,
                'parts': section.parts
                    .map((part) => <String, Object?>{
                          'title': part.title,
                          'content': part.content,
                          'status': part.status.storageValue,
                        })
                    .toList(),
              })
          .toList(),
    };
    return 'create_${origin}_${ContentHasher.hash(canonical)}';
  }
}
