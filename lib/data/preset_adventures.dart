/// 预设冒险数据 — 从 landing_screen 提取为独立模块
///
/// 添加新预设：向 `all` 列表追加 `_PresetData` 条目即可。
/// 未来可改为从 JSON 文件或远程 API 加载。
library preset_adventures;

import '../models/adventure_config.dart';
import '../models/supporting_character.dart';

class PresetAdventureData {
  final String title;
  final String difficulty;
  final String worldview;
  final String charName;
  final String gender;
  final String age;
  final String profession;
  final String background;
  final String openingScene;
  final List<String> options;
  final List<SupportingCharacter> supportingCharacters;

  /// Full-fidelity configuration restored from a saved wizard preview.
  ///
  /// When present it carries characters, relationships, custom attributes,
  /// NPC snapshots and opening branches that the legacy flat fields cannot
  /// represent.  Legacy presets leave it null.
  final AdventureConfig? restoredConfig;

  PresetAdventureData({
    required this.title,
    required this.difficulty,
    required this.worldview,
    required this.charName,
    required this.gender,
    required this.age,
    required this.profession,
    required this.background,
    required this.openingScene,
    this.options = const [],
    this.supportingCharacters = const [],
    this.restoredConfig,
  });

  AdventureConfig toConfig() =>
      restoredConfig ??
      AdventureConfig(
        name: charName,
        worldview: worldview,
        personality: background,
        openingScene: openingScene,
        openingOptions:
            options.isNotEmpty ? options : ['探索前方的道路', '观察周围环境', '检查随身物品'],
        gender: gender,
        age: age,
        protagonistClass: profession,
        supportingCharacters:
            List<SupportingCharacter>.from(supportingCharacters),
      );
}

/// 全部预设冒险列表（纯净版 — 无内置预设）
final presetAdventures = <PresetAdventureData>[];
