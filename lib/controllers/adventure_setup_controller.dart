import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../application/adventure/adventure_setup_use_case.dart';
import '../core/utils/worldview_character_scope_policy.dart';
import '../models/character_card_entry.dart';
import '../models/worldview_details.dart';
import '../models/worldview_preset.dart';
import '../models/worldview_preset_entry.dart';
import '../services/repositories/library_repository_impl.dart';
import '../services/database_service.dart';
import '../services/worldview_snapshot_service.dart';

/// 冒险创建流程的 5 步向导状态管理。
///
/// 步骤: worldview → characters → npcs → opening → confirm
/// 单一数据源替代 home_controller 的双状态源。
/// 数据加载经 [AdventureSetupUseCase]，不再直接访问 DatabaseService。
class AdventureSetupController extends ChangeNotifier {
  final AdventureSetupUseCase _useCase;

  List<Map<String, dynamic>> _worldviewPresets = const [];
  List<Map<String, dynamic>> _characterCards = const [];
  bool _loading = false;
  String? _error;

  List<Map<String, dynamic>> get worldviewPresets => _worldviewPresets;
  List<Map<String, dynamic>> get characterCards => _characterCards;
  bool get loading => _loading;
  String? get error => _error;

  AdventureSetupController({AdventureSetupUseCase? useCase})
      : _useCase = useCase ??
            AdventureSetupUseCase(
              LibraryRepositoryImpl(getDb: () => DatabaseService.database),
            );

  /// 全量角色卡的结构化视图（页面不再直接解析 json_data）。
  List<CharacterCardEntry> get characterCardEntries =>
      _characterCards.map(CharacterCardEntry.fromRow).toList(growable: false);

  /// 按选中世界观过滤后的角色卡条目（与行级 scope 策略语义一致）。
  List<CharacterCardEntry> scopedCharacterCardEntries(
          String? selectedWorldviewId) =>
      WorldviewCharacterScopePolicy.filterSceneResources(
        _characterCards,
        selectedWorldviewId,
      ).map(CharacterCardEntry.fromRow).toList(growable: false);

  /// 按 id 查找角色卡条目（未找到返回 null）。
  CharacterCardEntry? entryById(String id) {
    for (final row in _characterCards) {
      if (row['id']?.toString() == id) return CharacterCardEntry.fromRow(row);
    }
    return null;
  }

  /// 世界观预设的结构化视图（页面不再直接解析 detail_json）。
  List<WorldviewPresetEntry> get worldviewEntries => _worldviewPresets
      .map(WorldviewPresetEntry.fromRow)
      .toList(growable: false);

  /// 按 id 构建世界观快照（页面不再直接解析 detail_json 或调用
  /// WorldviewSnapshotService）。
  Map<String, dynamic>? buildWorldviewSnapshot({
    required String id,
    required String worldview,
  }) {
    final matches = _worldviewPresets.where((item) => item['id'] == id);
    if (matches.isEmpty) return null;
    final item = matches.first;
    Map<String, dynamic>? detail;
    final raw = item['detail_json'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) detail = decoded;
      } catch (_) {}
    }
    return WorldviewSnapshotService.snapshot(WorldviewPreset(
      id: item['id'] as String?,
      name: item['name'] as String? ?? '',
      description: worldview,
      details:
          WorldviewDetails.fromJson(detail, fallbackDescription: worldview),
    ));
  }

  /// 加载初始数据。
  Future<void> loadInitialData() async {
    _loading = true;
    _notify();
    try {
      _worldviewPresets = await _useCase.loadWorldviewPresets();
      _characterCards = await _useCase.loadCharacterCards();
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    _notify();
  }

  void reset() {
    _loading = false;
    _error = null;
    _notify();
  }

  void _notify() {
    notifyListeners();
  }
}
