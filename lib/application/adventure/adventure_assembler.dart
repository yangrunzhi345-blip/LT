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

  /// Keeps legacy supporting relations aligned with frozen relationships.
  ///
  /// [AdventureConfig.supportingCharacters] remains available to old UI paths,
  /// but its relation is only a protagonist-to-character relationship when such
  /// a relationship was explicitly frozen.
  void _normalizeLegacySupportingRelations(AdventureConfig snapshot) {
    AdventureSelectedCharacter? protagonist;
    for (final selected in snapshot.selectedCharacters) {
      if (selected.isProtagonist) {
        protagonist = selected;
        break;
      }
    }
    if (protagonist == null) return;

    final protagonistIds = _characterIds(protagonist);
    for (var index = 0; index < snapshot.supportingCharacters.length; index++) {
      final supporting = snapshot.supportingCharacters[index];
      AdventureSelectedCharacter? selected;
      for (final candidate in snapshot.selectedCharacters) {
        if (candidate.isProtagonist ||
            !_characterIds(candidate).contains(supporting.id.trim())) {
          continue;
        }
        selected = candidate;
        break;
      }
      if (selected == null) continue;
      final selectedIds = _characterIds(selected);
      AdventureCharacterRelationship? relationship;
      for (final candidate in snapshot.characterRelationships) {
        final sourceIsProtagonist = protagonistIds.contains(
          candidate.sourceCharacterId.trim(),
        );
        final targetIsSelected = selectedIds.contains(
          candidate.targetCharacterId.trim(),
        );
        final sourceIsSelected = selectedIds.contains(
          candidate.sourceCharacterId.trim(),
        );
        final targetIsProtagonist = protagonistIds.contains(
          candidate.targetCharacterId.trim(),
        );
        if ((sourceIsProtagonist && targetIsSelected) ||
            (sourceIsSelected && targetIsProtagonist)) {
          relationship = candidate;
          break;
        }
      }
      final relation = relationship != null &&
              AdventureRelationType.normalize(relationship.relationType) !=
                  AdventureRelationType.unset
          ? relationship.effectiveRelation
          : '';
      snapshot.supportingCharacters[index] = supporting.copyWith(
        relation: relation,
      );
    }
  }

  Set<String> _characterIds(AdventureSelectedCharacter character) => {
        if (character.id.trim().isNotEmpty) character.id.trim(),
        if (character.characterId.trim().isNotEmpty)
          character.characterId.trim(),
      };

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
