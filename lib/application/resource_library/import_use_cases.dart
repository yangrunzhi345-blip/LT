import 'dart:convert';

import '../../core/config/generation_limits.dart';
import '../../domain/resources/resource_blueprint.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../models/resource_library_mode.dart';
import '../../models/resource_provenance.dart';
import '../../models/scene_batch_candidate.dart';
import '../../models/worldview_details.dart';
import '../../services/character_card_generation_guard.dart';
import '../../services/character_card_storage_adapter.dart';
import '../../services/database_service.dart';
import '../../services/llm_service.dart';
import '../../services/repositories/library_repository.dart';
import '../../services/resource_integrity_validator.dart';
import '../../services/worldview_length_guard.dart';
import '../llm/llm_gateway.dart';
import '../resources/legacy_creation_bridge.dart';
import '../resources/resource_blueprint_repository.dart';
import '../resources/resource_creation_contracts.dart';
import '../resources/resource_creation_pipeline.dart';
import 'character_generation_context_builder.dart';
import 'import_models.dart';

class ImportValidationException implements Exception {
  final String message;

  const ImportValidationException(this.message);

  @override
  String toString() => message;
}

class ImportConversationCharacterUseCase {
  /// Unified creation pipeline adapter: saves go to the content tree.
  final LegacyCreationBridge? bridge;

  LegacyCreationBridge get _bridge =>
      bridge ??
      LegacyCreationBridge(ResourceCreationPipeline(
        getDb: () => DatabaseService.database,
        hasAiCredentials: () => true,
      ));

  final LlmGateway gateway;
  final ILibraryRepository repository;

  const ImportConversationCharacterUseCase({
    required this.gateway,
    required this.repository,
    this.bridge,
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
    await _bridge.saveCard(
      type: ResourceType.character,
      id: id ?? 'character_${draft.operationId}',
      name: draft.name,
      jsonData: jsonEncode(draft.fields),
      source: 'AI导入',
      mode: ResourceLibraryMode.conversation.storageValue,
      origin: 'import.conversation-character',
      operationId: draft.operationId,
    );
  }
}

class ResourceCardImportUseCase {
  /// Unified creation pipeline adapter: saves go to the content tree.
  final LegacyCreationBridge? bridge;

  LegacyCreationBridge get _bridge =>
      bridge ??
      LegacyCreationBridge(ResourceCreationPipeline(
        getDb: () => DatabaseService.database,
        hasAiCredentials: () => true,
      ));

  final LlmGateway gateway;
  final ILibraryRepository repository;

  const ResourceCardImportUseCase({
    required this.gateway,
    required this.repository,
    this.bridge,
  });

  Future<ResourceCreationResult> plan(ResourceCardImportRequest request) {
    final source = request.source.trim();
    if (source.isEmpty) {
      throw const ImportValidationException('原文内容不能为空');
    }
    return _bridge.planAiCreation(
      type: request.kind == ResourceCardImportKind.character
          ? ResourceType.character
          : ResourceType.npc,
      name: request.kind == ResourceCardImportKind.character
          ? 'AI 角色卡规划'
          : 'AI NPC 规划',
      referenceSource: ReferenceSource.text(source, label: '资料库 AI 创建'),
      origin: 'import.resource-card.ai',
      mode: request.libraryMode.storageValue,
    );
  }

  /// Queries sessions awaiting blueprint planning for characters or NPCs.
  Future<List<ResourceCreationSession>> pendingPlanningSessions() async {
    final sessions = await _bridge.pendingPlanningSessions();
    return sessions
        .where((s) =>
            s.resourceType == ResourceType.character ||
            s.resourceType == ResourceType.npc)
        .toList();
  }

  /// Plans an adaptive blueprint for an AI card planning session.
  Future<ResourceBlueprint> planBlueprint(
    String sessionId, {
    GenerationTaskHandle? taskHandle,
    Duration timeout = const Duration(seconds: 60),
    BlueprintIdPool? idPool,
  }) {
    return _bridge.planAiSession(
      sessionId: sessionId,
      gateway: gateway,
      taskHandle: taskHandle,
      timeout: timeout,
      idPool: idPool,
    );
  }

  /// Confirms a planned blueprint.
  Future<ResourceBlueprintConfirmResult> confirmBlueprint(
    String blueprintId, {
    String? nameOverride,
    ResourceId? explicitResourceId,
  }) {
    return _bridge.confirmAiBlueprint(
      blueprintId: blueprintId,
      nameOverride: nameOverride,
      explicitResourceId: explicitResourceId,
    );
  }

  Future<ResourceCardImportDraft> generate(
    ResourceCardImportRequest request, {
    void Function(int currentStage, int totalStages, String stageName)?
        onProgress,
  }) async {
    if (request.authoringMethod != ResourceAuthoringMethod.aiReference) {
      throw const ImportValidationException(
        '手写资料应直接校验并保存，不应进入 AI 生成管线',
      );
    }
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
    final associatedCharacters = request.associatedRelations.isEmpty
        ? request.associatedCharacters
        : request.associatedRelations
            .map((relation) => relation.toPromptMap())
            .toList(growable: false);
    final context = const CharacterGenerationContextBuilder().build(
      source: prompt,
      worldview: request.worldview,
      associatedCharacters: associatedCharacters,
    );
    if (request.kind == ResourceCardImportKind.character) {
      if (request.aiDepth == AiGenerationDepth.detailed &&
          (request.targetTotalCharacters != null &&
              (request.targetTotalCharacters! <
                      GenerationLimits.detailedCharacterMinimumCharacters ||
                  request.targetTotalCharacters! >
                      GenerationLimits.detailedCharacterMaximumCharacters))) {
        throw const ImportValidationException('详细角色卡目标字数必须在 1000–5000 之间');
      }
      final target = request.aiDepth == AiGenerationDepth.detailed
          ? request.targetTotalCharacters ??
              GenerationLimits.detailedCharacterDefaultCharacters
          : null;
      final result = request.aiDepth == AiGenerationDepth.detailed
          ? await gateway.generateDetailedResourceCharacter(
              source: prompt,
              worldview: context.worldview,
              associatedCharacters: context.associatedCharacters,
              targetTotalCharacters: target,
              onProgress: onProgress,
              generationMode: request.generationMode,
            )
          : await gateway.generateResourceCharacter(
              source: prompt,
              worldview: context.worldview,
              associatedCharacters: context.associatedCharacters,
              generationMode: request.generationMode,
            );
      final item = CharacterCardStorageAdapter.canonicalizeGenerated(result);
      if (item['name'].toString().trim().isEmpty) {
        throw const ImportValidationException('AI 未返回有效的角色名称');
      }
      return ResourceCardImportDraft(
        kind: request.kind,
        items: [item],
        matchingWorldviewId: request.worldviewId,
        provenance: ResourceProvenance(
          method: request.authoringMethod,
          aiDepth: request.aiDepth,
          originWorldviewId: request.worldviewId,
        ),
        targetTotalCharacters: target,
      );
    }

    final result = await gateway.generateResourceNpcs(
      source: '请从以下内容中提取所有 NPC 角色：\n\n$prompt',
      worldview: context.worldview,
      associatedCharacters: context.associatedCharacters,
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
      provenance: ResourceProvenance(
        method: request.authoringMethod,
        aiDepth: request.aiDepth,
        originWorldviewId: request.worldviewId,
      ),
    );
  }

  Future<int> save(
    ResourceCardImportDraft draft, {
    required ResourceLibraryMode mode,
  }) async {
    if (draft.isEmpty) {
      throw const ImportValidationException('没有可保存的资料');
    }
    if (draft.kind == ResourceCardImportKind.character) {
      final item = draft.items.first;
      final name = item['name']?.toString().trim() ?? '';
      final jsonData = jsonEncode(item);
      ResourceIntegrityValidator.validateCharacterCard(
        name: name,
        jsonData: jsonData,
      );
      if (draft.targetTotalCharacters case final target?) {
        final report = const CharacterCardGenerationGuard().evaluate(
          card: item,
          targetCharacters: target,
        );
        if (!report.completed) {
          throw ImportValidationException(
            '详细角色卡尚未达到完成标准（${report.currentCharacters} / $target），不能保存',
          );
        }
      }
      await _bridge.saveCard(
        type: ResourceType.character,
        id: 'character_${draft.operationId}',
        name: name,
        jsonData: jsonData,
        source: 'AI导入',
        matchingWorldviewId: draft.matchingWorldviewId,
        mode: mode.storageValue,
        authoringMethod: draft.provenance.methodStorageValue,
        aiGenerationDepth: draft.provenance.aiDepthStorageValue,
        origin: 'import.resource-card',
        operationId: draft.operationId,
      );
      return 1;
    }
    final cards = <LegacyCardSave>[];
    for (var index = 0; index < draft.items.length; index++) {
      final item = draft.items[index];
      final name = item['name']?.toString().trim() ?? '';
      final jsonData = jsonEncode(item);
      ResourceIntegrityValidator.validateNpcCard(
        name: name,
        jsonData: jsonData,
      );
      // One pipeline call per NPC; identical content maps to the same
      // idempotency key, so a re-import cannot duplicate it.
      cards.add(LegacyCardSave(
        type: ResourceType.npc,
        id: 'npc_${draft.operationId}_$index',
        name: name,
        jsonData: jsonData,
        source: 'AI导入',
        matchingWorldviewId: draft.matchingWorldviewId,
        mode: mode.storageValue,
        authoringMethod: draft.provenance.methodStorageValue,
        aiGenerationDepth: draft.provenance.aiDepthStorageValue,
        origin: 'import.resource-card-npc',
        operationId: '${draft.operationId}_$index',
      ));
    }
    await _bridge.saveCards(cards);
    return cards.length;
  }
}

class ImportWorldviewUseCase {
  /// Unified creation pipeline adapter: saves go to the content tree.
  final LegacyCreationBridge? bridge;

  LegacyCreationBridge get _bridge =>
      bridge ??
      LegacyCreationBridge(ResourceCreationPipeline(
        getDb: () => DatabaseService.database,
        hasAiCredentials: () => true,
      ));

  final LlmGateway gateway;
  final ILibraryRepository repository;

  const ImportWorldviewUseCase({
    required this.gateway,
    required this.repository,
    this.bridge,
  });

  Future<ResourceCreationResult> plan(WorldviewImportRequest request) {
    final source = request.source.trim();
    if (source.isEmpty) {
      throw const ImportValidationException('原文内容不能为空');
    }
    return _bridge.planAiCreation(
      type: ResourceType.worldview,
      name: 'AI 世界观规划',
      referenceSource: ReferenceSource.text(source, label: '世界观 AI 创建'),
      origin: 'import.worldview.ai',
      mode: request.libraryMode.storageValue,
    );
  }

  /// Queries sessions awaiting blueprint planning for worldviews.
  Future<List<ResourceCreationSession>> pendingPlanningSessions() async {
    final sessions = await _bridge.pendingPlanningSessions();
    return sessions
        .where((s) => s.resourceType == ResourceType.worldview)
        .toList();
  }

  /// Plans an adaptive blueprint for an AI worldview planning session.
  Future<ResourceBlueprint> planBlueprint(
    String sessionId, {
    GenerationTaskHandle? taskHandle,
    Duration timeout = const Duration(seconds: 60),
    BlueprintIdPool? idPool,
  }) {
    return _bridge.planAiSession(
      sessionId: sessionId,
      gateway: gateway,
      taskHandle: taskHandle,
      timeout: timeout,
      idPool: idPool,
    );
  }

  /// Confirms a planned blueprint, creating placeholder sections and parts.
  Future<ResourceBlueprintConfirmResult> confirmBlueprint(
    String blueprintId, {
    String? nameOverride,
    ResourceId? explicitResourceId,
  }) {
    return _bridge.confirmAiBlueprint(
      blueprintId: blueprintId,
      nameOverride: nameOverride,
      explicitResourceId: explicitResourceId,
    );
  }

  Future<WorldviewImportDraft> generate(
    WorldviewImportRequest request, {
    void Function(WorldviewGenerationProgress progress)? onProgress,
  }) async {
    if (request.authoringMethod != ResourceAuthoringMethod.aiReference) {
      throw const ImportValidationException(
        '手写世界观应直接校验并保存，不应进入 AI 生成管线',
      );
    }
    final source = request.source.trim();
    if (source.isEmpty) throw const ImportValidationException('原文内容不能为空');
    if (!gateway.isConfigured) {
      throw const ImportValidationException('请先在设置中配置 API Key');
    }
    if (request.aiDepth == AiGenerationDepth.detailed &&
        (request.targetTotalCharacters == null ||
            request.targetTotalCharacters! <
                GenerationLimits.detailedWorldviewMinimumCharacters ||
            request.targetTotalCharacters! >
                GenerationLimits.detailedWorldviewMaximumCharacters)) {
      throw const ImportValidationException(
        '期望总字数必须是 ${GenerationLimits.detailedWorldviewMinimumCharacters}–${GenerationLimits.detailedWorldviewMaximumCharacters} 之间的整数',
      );
    }
    final result = request.aiDepth == AiGenerationDepth.simple
        ? await gateway.generateWorldview(
            source,
            generationMode: request.generationMode,
          )
        : await gateway.generateDetailedWorldview(
            source,
            targetTotalCharacters: request.targetTotalCharacters,
            onProgress: onProgress,
            generationMode: request.generationMode,
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
      provenance: ResourceProvenance(
        method: request.authoringMethod,
        aiDepth: request.aiDepth,
      ),
      targetTotalCharacters: request.aiDepth == AiGenerationDepth.detailed
          ? request.targetTotalCharacters
          : null,
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
    if (draft.targetTotalCharacters case final target?) {
      final decoded = jsonDecode(draft.detailJson);
      final detail = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      final actual = const WorldviewLengthGuard().count(
        detailJson: detail,
        fallbackDescription: draft.description,
      );
      if (actual < target) {
        throw ImportValidationException(
          '详细世界观尚未达到目标字数（$actual / $target），不能作为完成结果保存',
        );
      }
    }
    await _bridge.saveWorldview(
      id: id ?? 'worldview_${draft.operationId}',
      name: draft.name.trim(),
      description: draft.description.trim(),
      detailJson: draft.detailJson,
      entriesJson: '[]',
      source: 'AI导入',
      mode: mode.storageValue,
      authoringMethod: draft.provenance.methodStorageValue,
      aiGenerationDepth: draft.provenance.aiDepthStorageValue,
      origin: 'import.worldview',
      operationId: draft.operationId,
    );
  }
}

class SceneBatchImportUseCase {
  /// Unified creation pipeline adapter: saves go to the content tree.
  final LegacyCreationBridge? bridge;

  LegacyCreationBridge get _bridge =>
      bridge ??
      LegacyCreationBridge(ResourceCreationPipeline(
        getDb: () => DatabaseService.database,
        hasAiCredentials: () => true,
      ));

  final LlmGateway gateway;
  final ILibraryRepository repository;

  const SceneBatchImportUseCase({
    required this.gateway,
    required this.repository,
    this.bridge,
  });

  Future<ResourceCreationResult> plan(SceneBatchImportRequest request) {
    final source = request.source.trim();
    if (source.isEmpty) {
      throw const ImportValidationException('原文内容不能为空');
    }
    return _bridge.planAiCreation(
      type: request.kind == 'character'
          ? ResourceType.character
          : ResourceType.npc,
      name: request.kind == 'character' ? 'AI 批量角色规划' : 'AI 批量 NPC 规划',
      referenceSource: ReferenceSource.text(source, label: '场景批量 AI 创建'),
      origin: 'import.scene-batch.ai',
      mode: request.libraryMode.storageValue,
    );
  }

  /// Queries sessions awaiting blueprint planning for scene batch creations.
  Future<List<ResourceCreationSession>> pendingPlanningSessions() async {
    final sessions = await _bridge.pendingPlanningSessions();
    return sessions
        .where((s) => s.idempotencyKey.startsWith('import.scene-batch.ai'))
        .toList();
  }

  /// Plans an adaptive blueprint for an AI batch planning session.
  Future<ResourceBlueprint> planBlueprint(
    String sessionId, {
    GenerationTaskHandle? taskHandle,
    Duration timeout = const Duration(seconds: 60),
    BlueprintIdPool? idPool,
  }) {
    return _bridge.planAiSession(
      sessionId: sessionId,
      gateway: gateway,
      taskHandle: taskHandle,
      timeout: timeout,
      idPool: idPool,
    );
  }

  /// Confirms a planned blueprint.
  Future<ResourceBlueprintConfirmResult> confirmBlueprint(
    String blueprintId, {
    String? nameOverride,
    ResourceId? explicitResourceId,
  }) {
    return _bridge.confirmAiBlueprint(
      blueprintId: blueprintId,
      nameOverride: nameOverride,
      explicitResourceId: explicitResourceId,
    );
  }

  /// 识别候选并分配稳定的 [SceneBatchCandidate.sourceId]。
  ///
  /// ID 由识别顺序派生，同一次识别内唯一。后续所有阶段都以该 ID 作为身份键，
  /// 展示名允许被模型改写而不影响候选归属。
  Future<List<SceneBatchCandidate>> identify(String source) async {
    if (source.trim().isEmpty) {
      throw const ImportValidationException('原文内容不能为空');
    }
    if (!gateway.isConfigured) {
      throw const ImportValidationException('请先在设置中配置 API Key');
    }
    final names = await gateway.identifyCharacterNames(source.trim());
    return [
      for (var index = 0; index < names.length; index++)
        SceneBatchCandidate(
          sourceId: 'scene_candidate_${(index + 1).toString().padLeft(3, '0')}',
          displayName: names[index],
        ),
    ];
  }

  /// 逐候选生成并保存。
  ///
  /// 每个已确认候选独占一次结构化生成请求（[maxItemAttempts] 为单候选的有界
  /// 内容重试次数），单个候选失败只丢弃该候选，不波及已成功的其它候选。所有
  /// 候选生成、校验通过后才进行一次原子 [ILibraryRepository.saveCardBatch]；
  /// [isCancelled] 在生成期间或保存前返回 true 时不落库，避免取消后仍写入半成品。
  Future<int> importSelected(
    SceneBatchImportRequest request,
    List<SceneBatchCandidate> selectedCandidates, {
    int maxItemAttempts = 2,
    bool Function()? isCancelled,
  }) async {
    final source = request.source.trim();
    if (source.isEmpty) throw const ImportValidationException('原文内容不能为空');
    if (selectedCandidates.isEmpty) {
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
    final label = request.kind == 'npc' ? 'NPC' : '角色卡';
    final relatedById = <String, Map<String, dynamic>>{
      for (final item in request.relatedCharacters)
        item['id']?.toString().trim() ?? '': item,
    };
    final items = <Map<String, dynamic>>[];
    Object? lastError;
    for (final candidate in selectedCandidates) {
      if (isCancelled?.call() ?? false) {
        throw const ImportValidationException('批量导入已取消');
      }
      final item = await _generateOne(
        request,
        candidate,
        source: source,
        label: label,
        maxItemAttempts: maxItemAttempts,
        onError: (error) => lastError = error,
      );
      if (item == null) continue;
      try {
        items.add(_normalizeGeneratedItem(
          item,
          candidate: candidate,
          request: request,
          relatedById: relatedById,
        ));
      } on ImportValidationException catch (error) {
        lastError = error;
      }
    }
    if (isCancelled?.call() ?? false) {
      throw const ImportValidationException('批量导入已取消');
    }
    if (items.isEmpty) {
      // 全部失败时保留底层错误，便于控制台与用户看到真实原因。
      final error = lastError;
      if (error is ImportValidationException) throw error;
      if (error != null) throw ImportValidationException('$error');
      throw ImportValidationException('未识别到可导入的$label');
    }
    final operationId =
        LegacyCreationBridge.newOperationId('import.scene-batch');
    final cards = <LegacyCardSave>[
      for (var index = 0; index < items.length; index++)
        LegacyCardSave(
          type: request.kind == 'character'
              ? ResourceType.character
              : ResourceType.npc,
          id: 'scene_batch_${operationId}_$index',
          name: items[index]['name']?.toString().trim() ?? '',
          jsonData: jsonEncode(items[index]),
          source: '批量AI导入',
          matchingWorldviewId: request.worldviewId,
          mode: request.libraryMode.storageValue,
          authoringMethod: ResourceAuthoringMethod.aiReference.name,
          aiGenerationDepth: request.aiDepth.name,
          origin: 'import.scene-batch',
          operationId: '${operationId}_$index',
        ),
    ];
    await _bridge.saveCards(cards);
    return cards.length;
  }

  /// 单候选的有界生成。返回 null 表示该候选在 [maxItemAttempts] 次内均失败。
  Future<Map<String, dynamic>?> _generateOne(
    SceneBatchImportRequest request,
    SceneBatchCandidate candidate, {
    required String source,
    required String label,
    required int maxItemAttempts,
    required void Function(Object error) onError,
  }) async {
    for (var attempt = 0; attempt < maxItemAttempts; attempt++) {
      try {
        return await gateway.generateSceneBatchCharacter(
          source: source,
          label: label,
          worldview: request.worldview,
          relatedCharacters: request.relatedCharacters,
          candidate: candidate,
          minimumTotalLength: request.minimumTotalLength,
          maximumTotalLength: request.maximumTotalLength,
          detailInstruction: request.detailInstruction,
        );
      } catch (error) {
        onError(error);
      }
    }
    return null;
  }

  /// 校验并规范化单个候选的生成结果；不合法时抛出 [ImportValidationException]。
  Map<String, dynamic> _normalizeGeneratedItem(
    Map<String, dynamic> raw, {
    required SceneBatchCandidate candidate,
    required SceneBatchImportRequest request,
    required Map<String, Map<String, dynamic>> relatedById,
  }) {
    final item = Map<String, dynamic>.from(raw);
    // 身份以 sourceId 为准：缺失或被模型改写为未知值的条目一律拒绝。
    final sourceId = item['sourceId']?.toString().trim() ?? '';
    if (sourceId != candidate.sourceId) {
      throw const ImportValidationException('生成结果缺少稳定的候选标识');
    }
    final generatedName = item['name']?.toString().trim() ?? '';
    final name = generatedName.isEmpty ? candidate.displayName : generatedName;
    item['name'] = name;
    // sourceId 只是导入会话内的身份，不写入最终卡片 JSON，保持存档兼容。
    item.remove('sourceId');
    final links = _validatedLinks(
      item['relationship_links'],
      relatedById: relatedById,
    );
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
    return item;
  }

  /// 关系绑定完全以稳定 `targetResourceId` 为准。
  ///
  /// 生成提示词要求每个 link 回传 `targetResourceId`；身份契约不再依赖可变的
  /// 展示名：
  /// - 缺失 `targetResourceId` 或命中未知/未关联 ID 的 link 一律拒绝，避免
  ///   同名与展示名变体造成的错误绑定或静默丢失。
  /// - `targetName` 仅用于展示；缺失时回退到关联资源的名称。
  ///
  /// 这是对旧版“无 ID 时按精确展示名回退”行为的显式收紧：旧响应若缺少 ID，
  /// 现在会丢弃该关系而不是按名称猜测。
  List<Map<String, dynamic>> _validatedLinks(
    Object? raw, {
    required Map<String, Map<String, dynamic>> relatedById,
  }) {
    if (raw is! List) return const [];
    final seen = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final value in raw.whereType<Map>()) {
      final link = Map<String, dynamic>.from(value);
      final targetId = link['targetResourceId']?.toString().trim() ?? '';
      if (targetId.isEmpty) continue; // 身份契约要求稳定 ID，拒绝名称回退
      final target = relatedById[targetId];
      if (target == null) continue; // 未知/未关联 ID 拒绝
      final targetName = link['targetName']?.toString().trim() ?? '';
      final relationType = link['relationType']?.toString().trim() ?? '';
      final description = link['description']?.toString().trim() ?? '';
      if (relationType.isEmpty || description.isEmpty) continue;
      final key = '${target['id']}:$relationType:$description';
      if (!seen.add(key)) {
        continue;
      }
      final resolvedName = targetName.isNotEmpty
          ? targetName
          : target['name']?.toString().trim() ?? '';
      result.add({
        'targetResourceId': target['id'],
        'targetName': resolvedName,
        'relationType': relationType,
        'description': description,
      });
    }
    return result;
  }
}
