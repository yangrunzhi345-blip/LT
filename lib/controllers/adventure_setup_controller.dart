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
  List<Map<String, dynamic>> _npcCards = const [];
  bool _loading = false;
  String? _worldviewError;
  String? _characterError;
  String? _npcError;

  List<Map<String, dynamic>> get worldviewPresets => _worldviewPresets;
  List<Map<String, dynamic>> get characterCards => _characterCards;
  List<Map<String, dynamic>> get npcCards => _npcCards;
  bool get loading => _loading;

  /// Error of one asset type; loading never stops early because of another.
  String? get worldviewError => _worldviewError;
  String? get characterError => _characterError;
  String? get npcError => _npcError;

  /// Aggregate error kept for callers that only need "did anything fail".
  String? get error => _worldviewError ?? _characterError ?? _npcError;

  /// True when at least one asset type failed while another still loaded.
  bool get hasPartialFailure =>
      error != null &&
      (_worldviewPresets.isNotEmpty ||
          _characterCards.isNotEmpty ||
          _npcCards.isNotEmpty);

  AdventureSetupController({AdventureSetupUseCase? useCase})
      : _useCase = useCase ??
            AdventureSetupUseCase(
              LibraryRepositoryImpl(getDb: () => DatabaseService.database),
            );

  /// Rows the parser kept but could not turn into a complete card.
  ///
  /// These stay visible through [characterCardEntries] so the user knows which
  /// asset is damaged, and are counted here for the Wizard status banner.
  int get malformedCharacterCardCount =>
      characterCardEntries.where((entry) => entry.hasParseError).length;

  /// 全量角色卡的结构化视图（页面不再直接解析 json_data）。
  List<CharacterCardEntry> get characterCardEntries =>
      _characterCards.map(CharacterCardEntry.fromRow).toList(growable: false);

  /// Returns every character card ordered by origin compatibility.
  ///
  /// The historical name remains for source compatibility; origin is a display
  /// preference, not an eligibility filter.
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
  ///
  /// worldview、character、NPC 三类资源彼此独立加载：任一类型失败只记录该类
  /// 自己的错误，其余类型仍会加载完成并可继续使用，避免一体式 try/catch 让
  /// 一个坏行拖垮整个向导。
  Future<void> loadInitialData() async {
    _loading = true;
    _notify();
    final results = await Future.wait([
      _loadWorldview(),
      _loadCharacters(),
      _loadNpcs(),
    ]);
    _worldviewPresets = results[0];
    _characterCards = results[1];
    _npcCards = results[2];
    _loading = false;
    _notify();
  }

  Future<List<Map<String, dynamic>>> _loadWorldview() async {
    try {
      final rows = await _useCase.loadWorldviewPresets();
      _worldviewError = null;
      return rows;
    } catch (e) {
      _worldviewError = '世界观资源加载失败：$e';
      return const <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> _loadCharacters() async {
    try {
      final rows = await _useCase.loadCharacterCards();
      _characterError = null;
      return rows;
    } catch (e) {
      _characterError = '角色卡资源加载失败：$e';
      return const <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> _loadNpcs() async {
    try {
      final rows = await _useCase.loadNpcCards();
      _npcError = null;
      return rows;
    } catch (e) {
      _npcError = 'NPC 资源加载失败：$e';
      return const <Map<String, dynamic>>[];
    }
  }

  void reset() {
    _loading = false;
    _worldviewError = null;
    _characterError = null;
    _npcError = null;
    _notify();
  }

  void _notify() {
    notifyListeners();
  }
}
