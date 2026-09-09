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

    _normalizeLegacySupportingRelations(snapshot);
    return AdventureConfig.fromJson(_deepCopy(snapshot.toJson()));
  }

  /// `supportingCharacters` is retained for legacy runtime/UI consumers, while
  /// `selectedCharacters` + `characterRelationships` are the authoritative
  /// Adventure assembly model. Do not let a role label leak into the legacy
  /// relation field when no explicit relationship was defined.
  void _normalizeLegacySupportingRelations(AdventureConfig config) {
    AdventureSelectedCharacter? protagonist;
    for (final character in config.selectedCharacters) {
      if (character.isProtagonist) {
        protagonist = character;
        break;
      }
    }
    if (protagonist == null) return;

    final selectedIds = config.selectedCharacters
        .where((character) => !character.isProtagonist)
        .map((character) => character.characterId)
        .where((id) => id.trim().isNotEmpty)
        .toSet();
    if (selectedIds.isEmpty) return;

    for (var index = 0; index < config.supportingCharacters.length; index++) {
      final supporting = config.supportingCharacters[index];
      if (!selectedIds.contains(supporting.id)) continue;

      AdventureCharacterRelationship? relationship;
      for (final item in config.characterRelationships) {
        final connectsProtagonist =
            (item.sourceCharacterId == protagonist.characterId &&
                    item.targetCharacterId == supporting.id) ||
                (item.targetCharacterId == protagonist.characterId &&
                    item.sourceCharacterId == supporting.id);
        if (connectsProtagonist) {
          relationship = item;
          break;
        }
      }

      final relation = relationship == null ||
              AdventureRelationType.normalize(relationship.relationType) ==
                  AdventureRelationType.unset
          ? ''
          : relationship.effectiveRelation;
      config.supportingCharacters[index] = supporting.copyWith(
        relation: relation,
      );
    }
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
