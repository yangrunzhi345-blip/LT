import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../application/resource_library/edit_drafts.dart';
import '../application/resources/authorized_generation_budget.dart';
import '../application/setting_cards/setting_card_service.dart';
import '../domain/setting_cards/setting_card.dart';
import '../services/repositories/library_repository.dart';
import '../models/conversation_character_card.dart';
import '../domain/resources/resource_contracts.dart';
import '../domain/resources/resource_limits.dart';
import '../domain/errors/app_error.dart';
import '../core/localization/app_error_localizer.dart';
import '../models/resource_library_mode.dart';
import '../models/worldview_details.dart';
import '../services/resource_integrity_validator.dart';

/// 资料库操作结果 — 区分成功与失败，调用方据此决定 UI 分支。
enum ResourceOperationNotice { movedToTrash }

class ResourceOperationResult {
  final bool success;
  final String? errorMessage;
  final ResourceId? resourceId;
  final String? sessionId;
  final AppDomainError? error;

  /// Optional success note the caller should surface (e.g. "已移入回收站").
  final String? message;
  final ResourceOperationNotice? notice;

  const ResourceOperationResult.success({
    this.resourceId,
    this.sessionId,
    this.message,
    this.notice,
  })  : success = true,
        errorMessage = null,
        error = null;

  const ResourceOperationResult.failure(String message, {this.error})
      : success = false,
        errorMessage = message,
        resourceId = null,
        sessionId = null,
        message = null,
        notice = null;
}

AppDomainError _resourceError(Object error) {
  if (error is ResourceValidationException) {
    return AppDomainError(
      code: AppErrorCode.resourceValidationFailed,
      // The validator message is a diagnostic/legacy compatibility string;
      // never pass the complete sentence into presentation parameters.
      parameters: const <String, Object?>{},
      debugMessage: error.message,
      cause: error,
    );
  }
  return asAppDomainError(error);
}

/// 资料库 CRUD 控制器 — 统一 worldview/npc/character 的保存、删除、校验编排。
///
/// 收编 worldview_tab.dart、character_card_tab.dart 与
/// app_dialogs.dart 中散落的 Repository 直调、ID 生成、Validator 和
/// MutationCoordinator。操作结果通过 [ResourceOperationResult] 返回，
/// 不再吞异常。
class ResourceCrudController extends ChangeNotifier {
  final ILibraryRepository _repository;
  final FutureOr<void> Function()? _onLibraryChanged;

  /// Mirrors each legacy save/delete into the lightweight card the library
  /// now reads. Null in tests that only exercise legacy persistence.
  final LegacyCardMirror? _mirror;

  /// Resolves a resource's authorized AI generation ceiling so re-editing an
  /// AI-generated resource validates against its frozen budget instead of the
  /// ordinary absolute capacity. Null (tests, manual-only wiring) keeps the
  /// ordinary absolute ceiling for every save.
  final IAuthorizedGenerationBudgetReader? _authorizedBudget;

  bool _busy = false;
  String? _error;

  /// Serialisation queue for mutating operations (saves and deletes).
  ///
  /// This is the explicit concurrency policy for destructive/reentrant
  /// actions: operations run one at a time in arrival order. The `busy` flag
  /// alone is UI state and was never a guard — without this queue two
  /// concurrent deletes/saves from different tabs would interleave their
  /// `_error`/`_busy` bookkeeping and race the underlying writes.
  Future<void> _mutationQueue = Future<void>.value();

  ResourceCrudController({
    required ILibraryRepository repository,
    FutureOr<void> Function()? onLibraryChanged,
    // Retained only so composition roots/tests that still pass the retired
    // creation pipeline keep compiling. Phase 5c writes the legacy row and the
    // card mirror directly, so the pipeline is never used.
    // ignore: avoid_unused_constructor_parameters
    Object? creationPipeline,
    IAuthorizedGenerationBudgetReader? authorizedBudget,
    LegacyCardMirror? cardMirror,
  })  : _repository = repository,
        _onLibraryChanged = onLibraryChanged,
        _authorizedBudget = authorizedBudget,
        _mirror = cardMirror;

  bool _disposed = false;

  bool get busy => _busy;
  String? get error => _error;

  /// The authorized AI ceiling of [resourceId] widened by its frozen budget, or
  /// null when the resource has no authorized AI run / no reader.
  ///
  /// Null means "keep the ordinary limit": the validators fall back to the
  /// type's absolute capacity (or the frozen worldview maximum), so a save with
  /// no authorization is never relaxed.
  Future<int?> _authorizedWidenedCeiling(
    String? resourceId,
    ResourceType type,
  ) async {
    final reader = _authorizedBudget;
    if (reader == null || resourceId == null || resourceId.isEmpty) return null;
    final authorized = await reader.authorizedCeiling(resourceId);
    if (authorized <= 0) return null;
    return ResourceLimits.policyFor(type).effectiveCharacters(authorized);
  }

  /// Runs [body] as the next serialised mutation, toggling [busy]/[error]
  /// around it. A failed earlier mutation must not stall the queue, so the
  /// chained continuation swallows everything [body] already reported.
  Future<ResourceOperationResult> _runMutation(
    Future<ResourceOperationResult> Function() body,
  ) {
    final run = _mutationQueue.then((_) async {
      if (_disposed) {
        return const ResourceOperationResult.failure(
          '',
          error: AppDomainError(code: AppErrorCode.unknown),
        );
      }
      _busy = true;
      _error = null;
      _notify();
      try {
        return await body();
      } finally {
        _busy = false;
        _notify();
      }
    });
    _mutationQueue = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// 删除世界观预设。
  Future<ResourceOperationResult> deleteWorldviewPreset(String id,
          {ResourceLibraryMode mode = ResourceLibraryMode.adventure}) =>
      _runMutation(() async {
        try {
          await _repository.deleteWorldviewPreset(id, mode: mode);
          await _mirror?.softDeleteLegacyMirror(
            kind: SettingCardKind.worldview,
            legacyId: id,
          );
          await _onLibraryChanged?.call();
          return const ResourceOperationResult.success(
            notice: ResourceOperationNotice.movedToTrash,
          );
        } catch (e) {
          _error = null;
          return ResourceOperationResult.failure(
            e is ResourceValidationException ? e.message : '',
            error: _resourceError(e),
          );
        }
      });

  /// 删除角色卡。
  Future<ResourceOperationResult> deleteCharacterCard(String id,
          {ResourceLibraryMode mode = ResourceLibraryMode.adventure}) =>
      _runMutation(() async {
        try {
          await _repository.deleteCharacterCard(id, mode: mode);
          await _mirror?.softDeleteLegacyMirror(
            kind: SettingCardKind.character,
            legacyId: id,
          );
          await _onLibraryChanged?.call();
          return const ResourceOperationResult.success(
            notice: ResourceOperationNotice.movedToTrash,
          );
        } catch (e) {
          _error = null;
          return ResourceOperationResult.failure(
            e is ResourceValidationException ? e.message : '',
            error: _resourceError(e),
          );
        }
      });

  /// 删除 NPC 卡。
  Future<ResourceOperationResult> deleteNpcCard(String id,
          {ResourceLibraryMode mode = ResourceLibraryMode.adventure}) =>
      _runMutation(() async {
        try {
          await _repository.deleteNpcCard(id, mode: mode);
          await _mirror?.softDeleteLegacyMirror(
            kind: SettingCardKind.npc,
            legacyId: id,
          );
          await _onLibraryChanged?.call();
          return const ResourceOperationResult.success(
            notice: ResourceOperationNotice.movedToTrash,
          );
        } catch (e) {
          _error = null;
          return ResourceOperationResult.failure(
            e is ResourceValidationException ? e.message : '',
            error: _resourceError(e),
          );
        }
      });

  /// 保存世界观预设（含完整性校验）。
  Future<ResourceOperationResult> saveWorldviewPreset({
    required String id,
    required String name,
    required String description,
    required String entriesJson,
    required String now,
    String source = '',
    String contentHash = '',
    String detailJson = '{}',
    bool validate = true,
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
    String authoringMethod = 'manual',
    String aiGenerationDepth = '',
    String matchingWorldviewId = '',
  }) =>
      _runMutation(() async {
        try {
          if (validate) {
            // 校验来源 detailJson 优先（与编辑器校验的表单内容一致），
            // 失败时回退 entriesJson。
            Map<String, dynamic>? detailsSource;
            try {
              final decoded = jsonDecode(detailJson);
              if (decoded is Map) {
                detailsSource = Map<String, dynamic>.from(decoded);
              }
            } catch (_) {
              detailsSource = null;
            }
            detailsSource ??= _tryDecodeMap(entriesJson);
            ResourceIntegrityValidator.validateWorldview(
              name: name,
              description: description,
              details: WorldviewDetails.fromJson(
                detailsSource,
                fallbackDescription: description,
              ),
              maxTotalCharacters:
                  await _authorizedWidenedCeiling(id, ResourceType.worldview),
            );
          }
          await _repository.saveWorldviewPreset(
            id: id,
            name: name,
            description: description,
            entriesJson: entriesJson,
            now: now,
            source: source,
            contentHash: contentHash,
            detailJson: detailJson,
            authoringMethod: authoringMethod,
            aiGenerationDepth: aiGenerationDepth,
            mode: mode,
          );
          await _mirror?.upsertLegacyMirror(
            kind: SettingCardKind.worldview,
            legacyId: id,
            name: name,
            summary: description,
            content: LegacyCardMirror.worldviewContent(
              description: description,
              detailJson: detailJson,
            ),
            mode: mode.storageValue,
          );
          await _onLibraryChanged?.call();
          return ResourceOperationResult.success(resourceId: ResourceId(id));
        } catch (e) {
          _error = null;
          return ResourceOperationResult.failure(
            e is ResourceValidationException ? e.message : '',
            error: _resourceError(e),
          );
        }
      });

  /// 保存角色卡（含完整性校验）。
  Future<ResourceOperationResult> saveCharacterCard({
    required String id,
    required String name,
    required String jsonData,
    required String source,
    required String now,
    String matchingWorldviewId = '',
    String weight = '',
    String contentHash = '',
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
    String authoringMethod = 'manual',
    String aiGenerationDepth = '',
  }) =>
      _runMutation(() async {
        try {
          ResourceIntegrityValidator.validateCharacterCard(
            name: name,
            jsonData: jsonData,
            effectiveCeiling:
                await _authorizedWidenedCeiling(id, ResourceType.character),
          );
          await _repository.saveCharacterCard(
            id: id,
            name: name,
            jsonData: jsonData,
            source: source,
            now: now,
            matchingWorldviewId: matchingWorldviewId,
            weight: weight,
            contentHash: contentHash,
            authoringMethod: authoringMethod,
            aiGenerationDepth: aiGenerationDepth,
            mode: mode,
          );
          await _mirror?.upsertLegacyMirror(
            kind: SettingCardKind.character,
            legacyId: id,
            name: name,
            summary: LegacyCardMirror.cardSummary(jsonData),
            content: LegacyCardMirror.cardContent(jsonData),
            mode: mode.storageValue,
          );
          await _onLibraryChanged?.call();
          return ResourceOperationResult.success(resourceId: ResourceId(id));
        } catch (e) {
          _error = null;
          return ResourceOperationResult.failure(
            e is ResourceValidationException ? e.message : '',
            error: _resourceError(e),
          );
        }
      });

  /// 加载世界观预设列表。
  Future<List<Map<String, dynamic>>> loadWorldviewPresets({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) {
    return _repository.getWorldviewPresets(mode: mode);
  }

  /// 加载角色卡列表。
  Future<List<Map<String, dynamic>>> loadCharacterCards({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) {
    return _repository.getCharacterCards(mode: mode);
  }

  /// 加载 NPC 卡列表。
  Future<List<Map<String, dynamic>>> loadNpcCards({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) {
    return _repository.getNpcCards(mode: mode);
  }

  /// 加载冒险模板列表。
  Future<List<Map<String, dynamic>>> loadAdventureTemplates({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) {
    return _repository.getAdventureTemplates(mode: mode);
  }

  /// 播种默认世界观（幂等）。
  Future<void> seedDefaultWorldviews() {
    return _repository.seedDefaultWorldviews();
  }

  /// 播种默认角色卡（幂等）。
  Future<void> seedDefaultCharacterCards() {
    return _repository.seedDefaultCharacterCards();
  }

  /// 确保对话角色卡就位：空库时写入对话默认卡，返回最新列表。
  Future<List<Map<String, dynamic>>> ensureConversationCharacterCards() async {
    var cards = await _repository.getCharacterCards(
      mode: ResourceLibraryMode.conversation,
    );
    if (cards.isEmpty) {
      final now = DateTime.now().toIso8601String();
      await _repository.saveCharacterCard(
        id: ConversationCharacterCardDefaults.id,
        name: ConversationCharacterCardDefaults.name,
        jsonData: ConversationCharacterCardDefaults.jsonData,
        source: '系统预设',
        now: now,
        mode: ResourceLibraryMode.conversation,
      );
      await _mirror?.upsertLegacyMirror(
        kind: SettingCardKind.character,
        legacyId: ConversationCharacterCardDefaults.id,
        name: ConversationCharacterCardDefaults.name,
        summary: LegacyCardMirror.cardSummary(
          ConversationCharacterCardDefaults.jsonData,
        ),
        content: LegacyCardMirror.cardContent(
          ConversationCharacterCardDefaults.jsonData,
        ),
        mode: ResourceLibraryMode.conversation.storageValue,
      );
      cards = await _repository.getCharacterCards(
        mode: ResourceLibraryMode.conversation,
      );
    }
    return cards;
  }

  /// 删除冒险模板。
  Future<ResourceOperationResult> deleteAdventureTemplate(String id,
          {ResourceLibraryMode mode = ResourceLibraryMode.adventure}) =>
      _runMutation(() async {
        try {
          await _repository.deleteAdventureTemplate(id, mode: mode);
          await _onLibraryChanged?.call();
          return const ResourceOperationResult.success();
        } catch (e) {
          _error = null;
          return ResourceOperationResult.failure(
            e is ResourceValidationException ? e.message : '',
            error: _resourceError(e),
          );
        }
      });

  /// 加载导入历史记录。
  Future<List<Map<String, dynamic>>> loadImportRecords({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) {
    return _repository.getImportRecords(mode: mode);
  }

  /// 保存世界观编辑草稿：detailJson 构造、完整性校验与落库统一处理。
  Future<ResourceOperationResult> saveWorldviewDraft(
    WorldviewEditDraft draft, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) =>
      _runMutation(() async {
        try {
          final details = draft.toDetails();
          ResourceIntegrityValidator.validateWorldview(
            name: draft.name,
            description: draft.description,
            details: details,
            maxTotalCharacters: await _authorizedWidenedCeiling(
                draft.id, ResourceType.worldview),
          );
          // Pin the generated id back onto the draft so a second save from the
          // same editor updates the resource instead of creating a duplicate.
          // Mirrors [saveCharacterCardDraft].
          final assignedId =
              draft.id ?? DateTime.now().millisecondsSinceEpoch.toString();
          draft.id = assignedId;
          final detailJson = details.encode();
          await _repository.saveWorldviewPreset(
            id: assignedId,
            name: draft.name,
            description: draft.description,
            entriesJson: draft.entriesJson,
            now: DateTime.now().toIso8601String(),
            source: draft.source,
            detailJson: detailJson,
            mode: mode,
          );
          await _mirror?.upsertLegacyMirror(
            kind: SettingCardKind.worldview,
            legacyId: assignedId,
            name: draft.name,
            summary: draft.description,
            content: LegacyCardMirror.worldviewContent(
              description: draft.description,
              detailJson: detailJson,
            ),
            mode: mode.storageValue,
          );
          await _onLibraryChanged?.call();
          return ResourceOperationResult.success(
              resourceId: ResourceId(assignedId));
        } catch (e) {
          _error = null;
          return ResourceOperationResult.failure(
            e is ResourceValidationException ? e.message : '',
            error: _resourceError(e),
          );
        }
      });

  /// 保存 NPC 编辑草稿：存储 JSON 构造、完整性校验与落库统一处理。
  Future<ResourceOperationResult> saveNpcDraft(
    NpcEditDraft draft, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) =>
      _runMutation(() async {
        try {
          final jsonData = draft.toStoredJson();
          ResourceIntegrityValidator.validateNpcCard(
            name: draft.name,
            jsonData: jsonData,
            effectiveCeiling:
                await _authorizedWidenedCeiling(draft.id, ResourceType.npc),
          );
          final assignedId =
              draft.id ?? DateTime.now().millisecondsSinceEpoch.toString();
          await _repository.saveNpcCard(
            id: assignedId,
            name: draft.name,
            jsonData: jsonData,
            source: draft.source,
            now: DateTime.now().toIso8601String(),
            matchingWorldviewId: draft.worldviewId,
            mode: mode,
          );
          await _mirror?.upsertLegacyMirror(
            kind: SettingCardKind.npc,
            legacyId: assignedId,
            name: draft.name,
            summary: LegacyCardMirror.cardSummary(jsonData),
            content: LegacyCardMirror.cardContent(jsonData),
            mode: mode.storageValue,
          );
          await _onLibraryChanged?.call();
          return ResourceOperationResult.success(
              resourceId: ResourceId(assignedId));
        } catch (e) {
          _error = null;
          return ResourceOperationResult.failure('',
              error: asAppDomainError(e));
        }
      });

  /// 保存角色卡编辑草稿：overlay 合并、完整性校验与落库统一处理。
  Future<ResourceOperationResult> saveCharacterCardDraft(
    CharacterCardEditDraft draft, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) =>
      _runMutation(() async {
        try {
          final jsonData = draft.toStoredJson();
          ResourceIntegrityValidator.validateCharacterCard(
            name: draft.name,
            jsonData: jsonData,
            effectiveCeiling: await _authorizedWidenedCeiling(
                draft.id, ResourceType.character),
          );
          final assignedId =
              draft.id ?? DateTime.now().millisecondsSinceEpoch.toString();
          draft.id = assignedId;
          await _repository.saveCharacterCard(
            id: assignedId,
            name: draft.name,
            jsonData: jsonData,
            source: draft.source,
            now: DateTime.now().toIso8601String(),
            matchingWorldviewId: draft.worldviewId,
            mode: mode,
          );
          await _mirror?.upsertLegacyMirror(
            kind: SettingCardKind.character,
            legacyId: assignedId,
            name: draft.name,
            summary: LegacyCardMirror.cardSummary(jsonData),
            content: LegacyCardMirror.cardContent(jsonData),
            mode: mode.storageValue,
          );
          await _onLibraryChanged?.call();
          return ResourceOperationResult.success(
              resourceId: ResourceId(assignedId));
        } catch (e) {
          _error = null;
          return ResourceOperationResult.failure(
            e is ResourceValidationException ? e.message : '',
            error: _resourceError(e),
          );
        }
      });

  /// 解码持久化 json_data 字段（页面不再在 Widget 中解析）。
  Map<String, dynamic> decodeCardData(Map<String, dynamic> item) {
    try {
      final decoded = jsonDecode(item['json_data'] as String? ?? '{}');
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// 解码持久化 weight 字段（页面不再在 Widget 中解析）。
  List<String> decodeWeights(Map<String, dynamic> item) {
    try {
      final wRaw = item['weight'] as String? ?? '';
      if (wRaw.isEmpty) return const [];
      return List<String>.from(jsonDecode(wRaw) as List);
    } catch (_) {
      return const [];
    }
  }

  void reset() {
    _busy = false;
    _error = null;
    _notify();
  }

  static Map<String, dynamic>? _tryDecodeMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
