import '../../models/resource_library_mode.dart';

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

enum WorldviewImportMode { simple, detailed }

class WorldviewImportRequest {
  final String source;
  final ResourceLibraryMode libraryMode;
  final WorldviewImportMode mode;
  final int? targetTotalCharacters;

  const WorldviewImportRequest({
    required this.source,
    this.libraryMode = ResourceLibraryMode.adventure,
    this.mode = WorldviewImportMode.simple,
    this.targetTotalCharacters,
  });
}

class WorldviewImportDraft {
  final String name;
  final String description;
  final String detailJson;

  const WorldviewImportDraft({
    required this.name,
    required this.description,
    this.detailJson = '{}',
  });

  WorldviewImportDraft copyWith({
    String? name,
    String? description,
    String? detailJson,
  }) =>
      WorldviewImportDraft(
        name: name ?? this.name,
        description: description ?? this.description,
        detailJson: detailJson ?? this.detailJson,
      );
}

/// 场景资料库角色/NPC 批量导入请求。UI 只负责收集这些值，具体识别、生成
/// 和持久化由应用层完成。
class SceneBatchImportRequest {
  final String source;
  final String kind;
  final String detailInstruction;
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
    required this.minimumTotalLength,
    required this.maximumTotalLength,
    this.worldview = '',
    this.worldviewId = '',
    this.relatedCharacters = const [],
    this.libraryMode = ResourceLibraryMode.adventure,
  });
}

enum ResourceCardImportKind { character, npc }

class ResourceCardImportRequest {
  final ResourceCardImportKind kind;
  final String source;
  final String worldview;
  final String worldviewId;
  final List<Map<String, String>> associatedCharacters;
  final String detailInstruction;
  final ResourceLibraryMode libraryMode;

  const ResourceCardImportRequest({
    required this.kind,
    required this.source,
    this.worldview = '',
    this.worldviewId = '',
    this.associatedCharacters = const [],
    this.detailInstruction = '',
    this.libraryMode = ResourceLibraryMode.adventure,
  });
}

class ResourceCardImportDraft {
  final ResourceCardImportKind kind;
  final List<Map<String, dynamic>> items;
  final String matchingWorldviewId;

  const ResourceCardImportDraft({
    required this.kind,
    required this.items,
    this.matchingWorldviewId = '',
  });

  bool get isEmpty => items.isEmpty;
  String get firstName => items.first['name']?.toString().trim() ?? '';
}
