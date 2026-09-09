import '../../models/resource_library_mode.dart';
import '../../models/resource_provenance.dart';

class ConversationCharacterImportRequest {
  final String source;
  final ResourceLibraryMode mode;

  const ConversationCharacterImportRequest({
    required this.source,
    this.mode = ResourceLibraryMode.conversation,
  });
}

class ConversationCharacterDraft {
  final Map<String, String> fields;

  const ConversationCharacterDraft(this.fields);

  String get name => fields['name']?.trim() ?? '';

  ConversationCharacterDraft copyWith(Map<String, String> updates) =>
      ConversationCharacterDraft({...fields, ...updates});
}

class WorldviewImportRequest {
  final String source;
  final ResourceLibraryMode libraryMode;
  final ResourceAuthoringMethod authoringMethod;
  final AiGenerationDepth aiDepth;
  final int? targetTotalCharacters;

  const WorldviewImportRequest({
    required this.source,
    this.libraryMode = ResourceLibraryMode.adventure,
    this.authoringMethod = ResourceAuthoringMethod.aiReference,
    required this.aiDepth,
    this.targetTotalCharacters,
  });
}

class WorldviewImportDraft {
  final String name;
  final String description;
  final String detailJson;
  final ResourceProvenance provenance;
  final int? targetTotalCharacters;

  const WorldviewImportDraft({
    required this.name,
    required this.description,
    this.detailJson = '{}',
    required this.provenance,
    this.targetTotalCharacters,
  });

  WorldviewImportDraft copyWith({
    String? name,
    String? description,
    String? detailJson,
    ResourceProvenance? provenance,
    int? targetTotalCharacters,
  }) =>
      WorldviewImportDraft(
        name: name ?? this.name,
        description: description ?? this.description,
        detailJson: detailJson ?? this.detailJson,
        provenance: provenance ?? this.provenance,
        targetTotalCharacters:
            targetTotalCharacters ?? this.targetTotalCharacters,
      );
}

/// 场景资料库角色/NPC 批量导入请求。UI 只负责收集这些值，具体识别、生成
/// 和持久化由应用层完成。
class SceneBatchImportRequest {
  final String source;
  final String kind;
  final String detailInstruction;
  final AiGenerationDepth aiDepth;
  final int minimumTotalLength;
  final int maximumTotalLength;
  final String worldview;
  final String worldviewId;
  final List<Map<String, dynamic>> relatedCharacters;
  final ResourceLibraryMode libraryMode;

  const SceneBatchImportRequest({
    required this.source,
    required this.kind,
    required this.detailInstruction,
    required this.aiDepth,
    required this.minimumTotalLength,
    required this.maximumTotalLength,
    this.worldview = '',
    this.worldviewId = '',
    this.relatedCharacters = const [],
    this.libraryMode = ResourceLibraryMode.adventure,
  });
}

enum ResourceCardImportKind { character, npc }

/// A role-specific relationship supplied to character generation.
///
/// It is deliberately separate from Adventure's frozen relationship model:
/// this is only library-generation context and never becomes runtime state.
class CharacterGenerationRelationInput {
  final String characterId;
  final String characterName;
  final String relationType;
  final String customRelationName;
  final String contextSummary;

  const CharacterGenerationRelationInput({
    this.characterId = '',
    required this.characterName,
    required this.relationType,
    this.customRelationName = '',
    this.contextSummary = '',
  });

  String get effectiveRelation => customRelationName.trim().isNotEmpty
      ? customRelationName.trim()
      : relationType.trim();

  Map<String, String> toPromptMap() => {
        'id': characterId,
        'name': characterName.trim(),
        'relation': effectiveRelation,
        'background': contextSummary.trim(),
      };
}

class ResourceCardImportRequest {
  final ResourceCardImportKind kind;
  final String source;
  final String worldview;
  final String worldviewId;
  final List<Map<String, String>> associatedCharacters;
  final List<CharacterGenerationRelationInput> associatedRelations;
  final String detailInstruction;
  final ResourceAuthoringMethod authoringMethod;
  final AiGenerationDepth aiDepth;
  final ResourceLibraryMode libraryMode;
  final int? targetTotalCharacters;

  const ResourceCardImportRequest({
    required this.kind,
    required this.source,
    this.worldview = '',
    this.worldviewId = '',
    this.associatedCharacters = const [],
    this.associatedRelations = const [],
    this.detailInstruction = '',
    this.authoringMethod = ResourceAuthoringMethod.aiReference,
    required this.aiDepth,
    this.libraryMode = ResourceLibraryMode.adventure,
    this.targetTotalCharacters,
  });
}

class ResourceCardImportDraft {
  final ResourceCardImportKind kind;
  final List<Map<String, dynamic>> items;
  final String matchingWorldviewId;
  final ResourceProvenance provenance;
  final int? targetTotalCharacters;

  const ResourceCardImportDraft({
    required this.kind,
    required this.items,
    this.matchingWorldviewId = '',
    required this.provenance,
    this.targetTotalCharacters,
  });

  bool get isEmpty => items.isEmpty;
  String get firstName => items.first['name']?.toString().trim() ?? '';
}
