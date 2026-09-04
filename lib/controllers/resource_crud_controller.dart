import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../application/resource_library/edit_drafts.dart';
import '../services/repositories/library_repository.dart';
import '../models/conversation_character_card.dart';
import '../models/resource_library_mode.dart';
import '../models/worldview_details.dart';
import '../services/resource_integrity_validator.dart';

/// 资料库操作结果 — 区分成功与失败，调用方据此决定 UI 分支。
class ResourceOperationResult {
  final bool success;
  final String? errorMessage;

  const ResourceOperationResult.success()
      : success = true,
        errorMessage = null;

  const ResourceOperationResult.failure(String message)
      : success = false,
        errorMessage = message;
}

/// 资料库 CRUD 控制器 — 统一 worldview/npc/character 的保存、删除、校验编排。
///
/// 收编 worldview_tab.dart、npc_tab.dart、character_card_tab.dart 与
/// app_dialogs.dart 中散落的 Repository 直调、ID 生成、Validator 和
/// MutationCoordinator。操作结果通过 [ResourceOperationResult] 返回，
/// 不再吞异常。
class ResourceCrudController extends ChangeNotifier {
  final ILibraryRepository _repository;
  final VoidCallback? _onLibraryChanged;

  bool _busy = false;
  String? _error;

  ResourceCrudController({
    required ILibraryRepository repository,
    VoidCallback? onLibraryChanged,
  })  : _repository = repository,
        _onLibraryChanged = onLibraryChanged;

  bool get busy => _busy;
  String? get error => _error;

  /// 删除世界观预设。
  Future<ResourceOperationResult> deleteWorldviewPreset(String id,
      {ResourceLibraryMode mode = ResourceLibraryMode.adventure}) async {
    _busy = true;
    _error = null;
    _notify();
    try {
      await _repository.deleteWorldviewPreset(id, mode: mode);
      _onLibraryChanged?.call();
      return const ResourceOperationResult.success();
    } catch (e) {
      _error = e.toString();
      return ResourceOperationResult.failure(e.toString());
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// 删除角色卡。
  Future<ResourceOperationResult> deleteCharacterCard(String id,
      {ResourceLibraryMode mode = ResourceLibraryMode.adventure}) async {
    _busy = true;
    _error = null;
    _notify();
    try {
      await _repository.deleteCharacterCard(id, mode: mode);
      _onLibraryChanged?.call();
      return const ResourceOperationResult.success();
    } catch (e) {
      _error = e.toString();
      return ResourceOperationResult.failure(e.toString());
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// 删除 NPC 卡。
  Future<ResourceOperationResult> deleteNpcCard(String id,
      {ResourceLibraryMode mode = ResourceLibraryMode.adventure}) async {
    _busy = true;
    _error = null;
    _notify();
    try {
      await _repository.deleteNpcCard(id, mode: mode);
      _onLibraryChanged?.call();
      return const ResourceOperationResult.success();
    } catch (e) {
      _error = e.toString();
      return ResourceOperationResult.failure(e.toString());
    } finally {
      _busy = false;
      _notify();
    }
  }

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
  }) async {
    _busy = true;
    _error = null;
    _notify();
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
        mode: mode,
      );
      _onLibraryChanged?.call();
      return const ResourceOperationResult.success();
    } catch (e) {
      _error = e.toString();
      return ResourceOperationResult.failure(e.toString());
    } finally {
      _busy = false;
      _notify();
    }
  }

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
  }) async {
    _busy = true;
    _error = null;
    _notify();
    try {
      ResourceIntegrityValidator.validateCharacterCard(
        name: name,
        jsonData: jsonData,
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
        mode: mode,
      );
      _onLibraryChanged?.call();
      return const ResourceOperationResult.success();
    } catch (e) {
      _error = e.toString();
      return ResourceOperationResult.failure(e.toString());
    } finally {
      _busy = false;
      _notify();
    }
  }

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
      await _repository.saveCharacterCard(
        id: ConversationCharacterCardDefaults.id,
        name: ConversationCharacterCardDefaults.name,
        jsonData: ConversationCharacterCardDefaults.jsonData,
        source: '系统预设',
        now: DateTime.now().toIso8601String(),
        mode: ResourceLibraryMode.conversation,
      );
      cards = await _repository.getCharacterCards(
        mode: ResourceLibraryMode.conversation,
      );
    }
    return cards;
  }

  /// 删除冒险模板。
  Future<ResourceOperationResult> deleteAdventureTemplate(
    String id, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    _busy = true;
    _error = null;
    _notify();
    try {
      await _repository.deleteAdventureTemplate(id, mode: mode);
      _onLibraryChanged?.call();
      return const ResourceOperationResult.success();
    } catch (e) {
      _error = e.toString();
      return ResourceOperationResult.failure(e.toString());
    } finally {
      _busy = false;
      _notify();
    }
  }

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
  }) async {
    _busy = true;
    _error = null;
    _notify();
    try {
      final details = draft.toDetails();
      ResourceIntegrityValidator.validateWorldview(
        name: draft.name,
        description: draft.description,
        details: details,
      );
      await _repository.saveWorldviewPreset(
        id: draft.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        name: draft.name,
        description: draft.description,
        entriesJson: draft.entriesJson,
        now: DateTime.now().toIso8601String(),
        source: draft.source,
        detailJson: details.encode(),
        mode: mode,
      );
      _onLibraryChanged?.call();
      return const ResourceOperationResult.success();
    } catch (e) {
      _error = e.toString();
      return ResourceOperationResult.failure(e.toString());
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// 保存 NPC 编辑草稿：存储 JSON 构造、完整性校验与落库统一处理。
  Future<ResourceOperationResult> saveNpcDraft(
    NpcEditDraft draft, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    _busy = true;
    _error = null;
    _notify();
    try {
      final jsonData = draft.toStoredJson();
      ResourceIntegrityValidator.validateNpcCard(
        name: draft.name,
        jsonData: jsonData,
      );
      await _repository.saveNpcCard(
        id: draft.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        name: draft.name,
        jsonData: jsonData,
        source: draft.source,
        now: DateTime.now().toIso8601String(),
        matchingWorldviewId: draft.worldviewId,
        mode: mode,
      );
      _onLibraryChanged?.call();
      return const ResourceOperationResult.success();
    } catch (e) {
      _error = e.toString();
      return ResourceOperationResult.failure(e.toString());
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// 保存角色卡编辑草稿：overlay 合并、完整性校验与落库统一处理。
  Future<ResourceOperationResult> saveCharacterCardDraft(
    CharacterCardEditDraft draft, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    _busy = true;
    _error = null;
    _notify();
    try {
      final jsonData = draft.toStoredJson();
      ResourceIntegrityValidator.validateCharacterCard(
        name: draft.name,
        jsonData: jsonData,
      );
      await _repository.saveCharacterCard(
        id: draft.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        name: draft.name,
        jsonData: jsonData,
        source: draft.source,
        now: DateTime.now().toIso8601String(),
        matchingWorldviewId: draft.worldviewId,
        weight: '',
        mode: mode,
      );
      _onLibraryChanged?.call();
      return const ResourceOperationResult.success();
    } catch (e) {
      _error = e.toString();
      return ResourceOperationResult.failure(e.toString());
    } finally {
      _busy = false;
      _notify();
    }
  }

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
    notifyListeners();
  }
}
