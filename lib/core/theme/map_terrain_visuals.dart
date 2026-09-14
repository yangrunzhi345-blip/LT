import 'package:flutter/material.dart';

import '../../models/narrative_map.dart';

/// Presentation-only terrain colors for [MapTerrainType].
///
/// The domain enum stays free of UI types; map rendering opts into this
/// extension explicitly.
extension MapTerrainTypeVisuals on MapTerrainType {
  Color get color {
    return switch (this) {
      MapTerrainType.plains => const Color(0xFF8FBC8F),
      MapTerrainType.forest => const Color(0xFF2E8B57),
      MapTerrainType.ocean => const Color(0xFF1E90FF),
      MapTerrainType.river => const Color(0xFF4169E1),
      MapTerrainType.mountain => const Color(0xFF8B7355),
      MapTerrainType.snowMountain => const Color(0xFFB0C4DE),
      MapTerrainType.desert => const Color(0xFFDAA520),
      MapTerrainType.swamp => const Color(0xFF556B2F),
      MapTerrainType.city => const Color(0xFFA9A9A9),
      MapTerrainType.village => const Color(0xFFDEB887),
      MapTerrainType.kingdom => const Color(0xFFDAA520),
      MapTerrainType.ruins => const Color(0xFF696969),
      MapTerrainType.volcano => const Color(0xFFB22222),
      MapTerrainType.grassland => const Color(0xFF90EE90),
      MapTerrainType.tundra => const Color(0xFFB0C4DE),
    };
  }
}
