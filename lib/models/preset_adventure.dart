import 'adventure_config.dart';
import 'supporting_character.dart';

/// A saved adventure preset used by the preset-scenes workbench.
///
/// The model lives in `models/` so presentation can consume it without
/// depending on the `data/` layer. Catalog loading is an application concern.
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
  /// represent. Legacy presets leave it null.
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
