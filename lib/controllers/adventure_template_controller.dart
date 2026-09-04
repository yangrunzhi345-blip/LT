import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../application/adventure/adventure_template_use_case.dart';
import '../data/preset_adventures.dart';
import '../models/supporting_character.dart';
import '../services/database_service.dart';
import '../services/repositories/library_repository_impl.dart';

/// 冒险模板控制器 — 合并 home_controller 和 adventure_builder 中重复的模板逻辑。
///
/// 模板读取、去重保存与删除全部委托 [AdventureTemplateUseCase]。
class AdventureTemplateController extends ChangeNotifier {
  final AdventureTemplateUseCase _useCase;

  List<Map<String, dynamic>> _templates = const [];
  bool _loading = false;
  String? _error;

  List<Map<String, dynamic>> get templates => _templates;
  bool get loading => _loading;
  String? get error => _error;

  AdventureTemplateController({AdventureTemplateUseCase? useCase})
      : _useCase = useCase ??
            AdventureTemplateUseCase(
              LibraryRepositoryImpl(getDb: () => DatabaseService.database),
            );

  /// 由模板行构建预设冒险数据（char/npc JSON 解析与组装全部下沉；
  /// char_data_json 为空返回 null）。
  PresetAdventureData? buildPresetData(Map<String, dynamic> template) {
    final charDataJson = template['char_data_json'] as String? ?? '';
    final npcDataJson = template['npc_data_json'] as String? ?? '';
    if (charDataJson.isEmpty) return null;

    final wvName = template['worldview_name'] as String? ?? '';
    final wvDesc = template['worldview_desc'] as String? ?? '';
    final presetName = template['name'] as String? ?? '预设场景';

    final charData = jsonDecode(charDataJson) as Map<String, dynamic>;
    dynamic npcRaw;
    try {
      npcRaw = jsonDecode(npcDataJson);
    } catch (_) {
      npcRaw = null;
    }

    // Build NPC supporting characters list
    final chars = <SupportingCharacter>[];
    List npcList;
    if (npcRaw is Map<String, dynamic>) {
      npcList = (npcRaw['npcs'] as List?) ?? [];
    } else if (npcRaw is List) {
      npcList = npcRaw;
    } else {
      npcList = [];
    }
    for (final n in npcList.whereType<Map<String, dynamic>>()) {
      chars.add(SupportingCharacter(
        name: n['name'] as String? ?? '',
        gender: n['gender'] as String? ?? '',
        role: n['role'] as String? ?? '',
        personality: n['personality'] as String? ?? '',
        relation: n['relation'] as String? ?? '',
      ));
    }

    return PresetAdventureData(
      title: presetName,
      difficulty: 'normal',
      worldview: wvDesc.isNotEmpty ? wvDesc : wvName,
      charName: (charData['name'] as String?) ?? '冒险者',
      gender: (charData['gender'] as String?) ?? '男',
      age: (charData['age'] as String?) ?? '青年',
      profession: (charData['profession'] as String?) ??
          (charData['occupation'] as String?) ??
          '冒险者',
      background: (charData['background'] as String?) ??
          (charData['description'] as String?) ??
          '',
      openingScene: (charData['openingScene'] as String?) ??
          (charData['opening_scene'] as String?) ??
          '',
      options: (charData['openingOptions'] as List<dynamic>?)?.cast<String>() ??
          (charData['options'] as List<dynamic>?)?.cast<String>() ??
          [],
      supportingCharacters: chars,
    );
  }

  /// 加载所有模板。
  Future<void> loadTemplates() async {
    _loading = true;
    _error = null;
    _notify();
    try {
      _templates = await _useCase.loadTemplates();
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    _notify();
  }

  /// 保存冒险配置为模板（含 ContentHasher 去重）。
  Future<bool> saveAsTemplate({
    required String id,
    required String name,
    required String worldviewName,
    required String worldviewDesc,
    required String charDataJson,
    required String npcDataJson,
    required String createdAt,
    String status = 'draft',
    String updatedAt = '',
    String contentHash = '',
  }) async {
    try {
      final saved = await _useCase.saveAsTemplate(
        id: id,
        name: name,
        worldviewName: worldviewName,
        worldviewDesc: worldviewDesc,
        charDataJson: charDataJson,
        npcDataJson: npcDataJson,
        createdAt: createdAt,
        status: status,
        updatedAt: updatedAt,
        contentHash: contentHash,
      );
      if (saved) await loadTemplates();
      return saved;
    } catch (e) {
      _error = e.toString();
      _notify();
      return false;
    }
  }

  /// 删除模板。
  Future<void> deleteTemplate(String id) async {
    try {
      await _useCase.deleteTemplate(id);
      await loadTemplates();
    } catch (e) {
      _error = e.toString();
      _notify();
    }
  }

  void reset() {
    _templates = const [];
    _loading = false;
    _error = null;
  }

  void _notify() {
    notifyListeners();
  }
}
