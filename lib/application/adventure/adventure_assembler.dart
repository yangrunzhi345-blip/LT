import 'dart:convert';

import '../../models/adventure_config.dart';
import '../../models/worldview_details.dart';
import '../../models/worldview_preset.dart';
import '../../services/worldview_snapshot_service.dart';

/// Freezes mutable assembly input into an adventure-owned initial snapshot.
///
/// Every creation entry point passes through this boundary. Runtime receives
/// only the returned config and never needs to reload source library assets.
class AdventureAssembler {
  const AdventureAssembler();

  AdventureConfig assemble(AdventureConfig input) {
    final snapshot = AdventureConfig.fromJson(_deepCopy(input.toJson()));
    snapshot.worldviewSnapshot ??= _fallbackWorldviewSnapshot(snapshot);

    for (var index = 0; index < snapshot.selectedCharacters.length; index++) {
      final selected = snapshot.selectedCharacters[index];
      if (selected.characterCardJson != null) continue;
      final card = selected.isProtagonist ? snapshot.characterCard : null;
      if (card != null) {
        snapshot.selectedCharacters[index] = selected.copyWith(
          characterCardJson: _deepCopy(card.toJson()),
        );
      }
    }
    return AdventureConfig.fromJson(_deepCopy(snapshot.toJson()));
  }

  Map<String, dynamic>? _fallbackWorldviewSnapshot(AdventureConfig config) {
    final worldview = config.worldview.trim();
    if (worldview.isEmpty) return null;
    return WorldviewSnapshotService.snapshot(
      WorldviewPreset(
        name: worldview,
        description: worldview,
        details: WorldviewDetails.fromJson(
          null,
          fallbackDescription: worldview,
        ),
      ),
    );
  }

  Map<String, dynamic> _deepCopy(Map<String, dynamic> value) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
}
