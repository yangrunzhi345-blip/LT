import 'dart:convert';

import '../../core/config/generation_limits.dart';
import '../../models/resource_library_mode.dart';
import '../../models/worldview_details.dart';
import '../../services/repositories/library_repository.dart';
import '../../services/resource_integrity_validator.dart';
import '../../utils/content_hasher.dart';
import '../llm/llm_gateway.dart';
import 'import_models.dart';

class ImportValidationException implements Exception {
  final String message;

  const ImportValidationException(this.message);

  @override
  String toString() => message;
}

class ImportConversationCharacterUseCase {
  final LlmGateway gateway;
  final ILibraryRepository repository;

  const ImportConversationCharacterUseCase({
    required this.gateway,
    required this.repository,
  });

  Future<ConversationCharacterDraft> generate(
    ConversationCharacterImportRequest request,
  ) async {
    final source = request.source.trim();
    if (source.isEmpty) throw const ImportValidationException('原文内容不能为空');
    if (!gateway.isConfigured) {
      throw const ImportValidationException('请先在设置中配置 API Key');
    }
    if (request.mode != ResourceLibraryMode.conversation) {
      throw const ImportValidationException('对话角色卡必须保存到对话资料库');
    }
    final result = await gateway.generateConversationCharacter(source);
    return ConversationCharacterDraft(Map<String, String>.from(result));
  }

  Future<void> save(
    ConversationCharacterDraft draft, {
    String? id,
    DateTime? now,
  }) async {
    if (draft.name.isEmpty) {
      throw const ImportValidationException('角色名称不能为空');
    }
    final timestamp = (now ?? DateTime.now()).toIso8601String();
    await repository.saveCharacterCard(
      id: id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: draft.name,
      jsonData: jsonEncode(draft.fields),
      source: 'AI导入',
      now: timestamp,
      mode: ResourceLibraryMode.conversation,
    );
  }
}

class ResourceCardImportUseCase {
  final LlmGateway gateway;
  final ILibraryRepository repository;

  const ResourceCardImportUseCase({
    required this.gateway,
    required this.repository,
  });

  Future<ResourceCardImportDraft> generate(
    ResourceCardImportRequest request, {
    void Function(int currentStage, int totalStages, String stageName)? onProgress,
  }) async {
    final source = request.source.trim();
    if (source.isEmpty) {
      throw const ImportValidationException('原文内容不能为空');
    }
    if (!gateway.isConfigured) {
      throw const ImportValidationException('请先在设置中配置 API Key');
    }
    final prompt = request.detailInstruction.trim().isEmpty
        ? source
        : '$source\n\n${request.detailInstruction.trim()}';
    if (request.kind == ResourceCardImportKind.character) {
      final isDetailed = request.detailInstruction.contains('详细模式') ||
          request.detailInstruction.contains('详细');
      final result = isDetailed
          ? await gateway.generateDetailedResourceCharacter(
              source: prompt,
              worldview: request.worldview,
              associatedCharacters: request.associatedCharacters,
              onProgress: onProgress,
            )
          : await gateway.generateResourceCharacter(
              source: prompt,
              worldview: request.worldview,
              associatedCharacters: request.associatedCharacters,
            );
      final item = <String, dynamic>{
        'name': result['name'] ?? '',
        'gender': result['gender'] ?? '',
        'age': result['age'] ?? '',
        'profession': result['profession'] ?? '',
        'personality': result['personality'] ?? '',
        'description': result['background'] ?? result['description'] ?? '',
        'appearance': result['appearance'] ?? '',
        'bodyDescription': result['bodyDescription'] ?? '',
        'world_profile': result['world_profile'] is Map
            ? Map<String, dynamic>.from(result['world_profile'] as Map)
            : _decodeObject(result['world_profile']),
      };
      if (item['name'].toString().trim().isEmpty) {
        throw const ImportValidationException('AI 未返回有效的角色名称');
      }
      return ResourceCardImportDraft(
        kind: request.kind,
        items: [item],
        matchingWorldviewId: request.worldviewId,
      );
    }

    final result = await gateway.generateResourceNpcs(
      source: '请从以下内容中提取所有 NPC 角色：\n\n$prompt',
      worldview: request.worldview,
      associatedCharacters: request.associatedCharacters,
    );
    final items = result
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item['name']?.toString().trim().isNotEmpty == true)
        .toList();
    if (items.isEmpty) {
      throw const ImportValidationException('AI 未返回可导入的 NPC');
    }
    return ResourceCardImportDraft(
      kind: request.kind,
      items: items,
      matchingWorldviewId: request.worldviewId,
    );
  }

  Future<int> save(
    ResourceCardImportDraft draft, {
    required ResourceLibraryMode mode,
  }) async {
    if (draft.isEmpty) {
      throw const ImportValidationException('没有可保存的资料');
    }
    final now = DateTime.now().toIso8601String();
    if (draft.kind == ResourceCardImportKind.character) {
      final item = draft.items.first;
      final name = item['name']?.toString().trim() ?? '';
      final jsonData = jsonEncode(item);
      ResourceIntegrityValidator.validateCharacterCard(
        name: name,
        jsonData: jsonData,
      );
      await repository.saveCharacterCard(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        jsonData: jsonData,
        source: 'AI导入',
        now: now,
        matchingWorldviewId: draft.matchingWorldviewId,
        mode: mode,
      );
      return 1;
    }
    final items = <LibraryCardBatchItem>[];
    for (var index = 0; index < draft.items.length; index++) {
      final item = draft.items[index];
      final name = item['name']?.toString().trim() ?? '';
      final jsonData = jsonEncode(item);
      ResourceIntegrityValidator.validateNpcCard(
        name: name,
        jsonData: jsonData,
      );
      items.add(LibraryCardBatchItem(
        id: '${DateTime.now().millisecondsSinceEpoch}_$index',
        name: name,
        jsonData: jsonData,
        source: 'AI导入',
        now: now,
        matchingWorldviewId: draft.matchingWorldviewId,
        contentHash: ContentHasher.hashString(jsonData),
      ));
    }
    return repository.saveCardBatch(
      type: LibraryCardType.npc,
      items: items,
      mode: mode,
    );
  }

  Map<String, dynamic> _decodeObject(String? value) {
    if (value == null || value.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(value);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}

class ImportWorldviewUseCase {
  final LlmGateway gateway;
  final ILibraryRepository repository;

  const ImportWorldviewUseCase({
    required this.gateway,
    required this.repository,
  });

  Future<WorldviewImportDraft> generate(
    WorldviewImportRequest request, {
    void Function(WorldviewGenerationProgress progress)? onProgress,
  }) async {
    final source = request.source.trim();
    if (source.isEmpty) throw const ImportValidationException('原文内容不能为空');
    if (!gateway.isConfigured) {
      throw const ImportValidationException('请先在设置中配置 API Key');
    }
    if (request.mode == WorldviewImportMode.detailed &&
        (request.targetTotalCharacters == null ||
            request.targetTotalCharacters! <
                GenerationLimits.detailedWorldviewMinimumCharacters ||
            request.targetTotalCharacters! >
                GenerationLimits.detailedWorldviewMaximumCharacters)) {
      throw const ImportValidationException(
        '期望总字数必须是 ${GenerationLimits.detailedWorldviewMinimumCharacters}–${GenerationLimits.detailedWorldviewMaximumCharacters} 之间的整数',
      );
    }
    final result = request.mode == WorldviewImportMode.simple
        ? await gateway.generateWorldview(source)
        : await gateway.generateDetailedWorldview(
            source,
            targetTotalCharacters: request.targetTotalCharacters,
            onProgress: onProgress,
          );
    final name = result['name']?.toString().trim() ?? '';
    final description = result['description']?.toString().trim() ?? '';
    if (name.isEmpty || description.isEmpty) {
      throw const ImportValidationException('AI 未返回完整的世界观名称和描述');
    }
    final detail = WorldviewDetails.fromJson(
      result['detail_json'] is Map
          ? Map<String, dynamic>.from(result['detail_json'] as Map)
          : null,
      fallbackDescription: description,
    );
    return WorldviewImportDraft(
      name: name,
      description: description,
      detailJson: detail.encode(),
    );
  }

  Future<void> save(
    WorldviewImportDraft draft, {
    String? id,
    DateTime? now,
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    if (draft.name.trim().isEmpty || draft.description.trim().isEmpty) {
      throw const ImportValidationException('世界观名称和描述不能为空');
    }
    if (mode == ResourceLibraryMode.conversation) {
      throw const ImportValidationException('世界观不能保存到对话资料库');
    }
    await repository.saveWorldviewPreset(
      id: id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: draft.name.trim(),
      description: draft.description.trim(),
      entriesJson: '[]',
      detailJson: draft.detailJson,
      source: 'AI导入',
      now: (now ?? DateTime.now()).toIso8601String(),
      mode: mode,
    );
  }
}

class SceneBatchImportUseCase {
  final LlmGateway gateway;
  final ILibraryRepository repository;

  const SceneBatchImportUseCase({
    required this.gateway,
    required this.repository,
  });

  Future<List<String>> identify(String source) async {
    if (source.trim().isEmpty) {
      throw const ImportValidationException('原文内容不能为空');
    }
    if (!gateway.isConfigured) {
      throw const ImportValidationException('请先在设置中配置 API Key');
    }
    return gateway.identifyCharacterNames(source.trim());
  }

  Future<int> importSelected(
    SceneBatchImportRequest request,
    Set<String> selectedNames,
  ) async {
    final source = request.source.trim();
    if (source.isEmpty) throw const ImportValidationException('原文内容不能为空');
    if (selectedNames.isEmpty) {
      throw const ImportValidationException('请至少选择一个角色');
    }
    if (!gateway.isConfigured) {
      throw const ImportValidationException('请先在设置中配置 API Key');
    }
    final maximumAllowed = request.kind == 'npc' ? 3000 : 5000;
    if (request.minimumTotalLength < 1 ||
        request.maximumTotalLength < request.minimumTotalLength ||
        request.maximumTotalLength > maximumAllowed) {
      throw const ImportValidationException('总字数范围无效');
    }
    final result = await gateway.generateSceneBatchCharacters(
      source: source,
      label: request.kind == 'npc' ? 'NPC' : '角色卡',
      worldview: request.worldview,
      relatedCharacters: request.relatedCharacters,
      selectedNames: selectedNames.toList(growable: false),
      minimumTotalLength: request.minimumTotalLength,
      maximumTotalLength: request.maximumTotalLength,
      detailInstruction: request.detailInstruction,
    );
    final items = (result['items'] as List)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where(
            (item) => selectedNames.contains(item['name']?.toString().trim()))
        .toList();
    if (items.isEmpty) {
      throw ImportValidationException(
        '未识别到可导入的${request.kind == 'npc' ? 'NPC' : '角色卡'}',
      );
    }
    final relatedByName = <String, Map<String, dynamic>>{
      for (final item in request.relatedCharacters)
        item['name']?.toString().trim() ?? '': item,
    };
    final batch = <LibraryCardBatchItem>[];
    final now = DateTime.now().toIso8601String();
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final name = item['name']?.toString().trim() ?? '';
      final links = _validatedLinks(item['relationship_links'], relatedByName);
      item['relationship_links'] = links;
      final summary = links
          .map((link) =>
              '${link['targetName']}：${link['relationType']}，${link['description']}')
          .join('\n');
      item['relationship_summary'] = summary;
      if (request.kind == 'character') {
        final profile = item['world_profile'] is Map
            ? Map<String, dynamic>.from(item['world_profile'] as Map)
            : <String, dynamic>{};
        profile['relationship_notes'] = summary;
        item['world_profile'] = profile;
      } else {
        item['relation'] ??= summary;
      }
      final jsonData = jsonEncode(item);
      if (request.kind == 'character') {
        ResourceIntegrityValidator.validateCharacterCard(
            name: name, jsonData: jsonData);
      } else {
        ResourceIntegrityValidator.validateNpcCard(
            name: name, jsonData: jsonData);
      }
      batch.add(LibraryCardBatchItem(
        id: 'scene_batch_${DateTime.now().microsecondsSinceEpoch}_$index',
        name: name,
        jsonData: jsonData,
        source: '批量AI导入',
        now: now,
        matchingWorldviewId: request.worldviewId,
        contentHash: ContentHasher.hashString(jsonData),
      ));
    }
    return repository.saveCardBatch(
      type: request.kind == 'character'
          ? LibraryCardType.character
          : LibraryCardType.npc,
      items: batch,
      mode: request.libraryMode,
    );
  }

  List<Map<String, dynamic>> _validatedLinks(
    Object? raw,
    Map<String, Map<String, dynamic>> relatedByName,
  ) {
    if (raw is! List) return const [];
    final seen = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final value in raw.whereType<Map>()) {
      final link = Map<String, dynamic>.from(value);
      final targetName = link['targetName']?.toString().trim() ?? '';
      final relationType = link['relationType']?.toString().trim() ?? '';
      final description = link['description']?.toString().trim() ?? '';
      final target = relatedByName[targetName];
      if (target == null || relationType.isEmpty || description.isEmpty) {
        continue;
      }
      final key = '${target['id']}:$relationType:$description';
      if (!seen.add(key)) {
        continue;
      }
      result.add({
        'targetResourceId': target['id'],
        'targetName': targetName,
        'relationType': relationType,
        'description': description,
      });
    }
    return result;
  }
}
