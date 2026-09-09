import '../../models/adventure_config.dart';
import '../../models/adventure_runtime_state.dart';

/// The only adapter permitted to combine a frozen AdventureConfig with HEAD.
///
/// The returned config is a presentation value. It must never be persisted as
/// the baseline because its character fields can contain runtime overlays.
final class AdventureRuntimeStateResolver {
  const AdventureRuntimeStateResolver();

  AdventureConfig effectiveConfig(
    AdventureConfig baseline,
    Iterable<RuntimeEntityState> entities,
  ) {
    final result = AdventureConfig.fromJson(baseline.toJson());
    final byId = <String, RuntimeEntityState>{
      for (final entity in entities)
        if (entity.entityType == RuntimeEntityType.character ||
            entity.entityType == RuntimeEntityType.npc)
          entity.entityId: entity,
    };
    for (final character in result.supportingCharacters) {
      final runtime = byId[character.id];
      if (runtime == null) continue;
      final values = runtime.overlay;
      if (values['affinity'] is num) {
        character.affinity = (values['affinity'] as num).toInt().clamp(0, 100);
      }
      if (values['relationship'] is String) {
        character.relation = values['relationship'] as String;
      }
      final lifeStatus = values['life_status'];
      character.isAlive =
          runtime.lifecycleStatus != 'dead' && lifeStatus != 'dead';
    }
    return result;
  }

  /// Removes known overlays before a user-authored config edit is persisted.
  AdventureConfig baselineForPersistence(
    AdventureConfig editedEffective,
    AdventureConfig priorBaseline,
    Iterable<RuntimeEntityState> entities,
  ) {
    final result = AdventureConfig.fromJson(editedEffective.toJson());
    final oldById = {
      for (final character in priorBaseline.supportingCharacters)
        character.id: character
    };
    final overlays = {for (final entity in entities) entity.entityId: entity};
    for (final character in result.supportingCharacters) {
      final overlay = overlays[character.id]?.overlay;
      final old = oldById[character.id];
      if (overlay == null || old == null) continue;
      if (overlay.containsKey('affinity')) {
        character.affinity = old.affinity;
      }
      if (overlay.containsKey('relationship')) {
        character.relation = old.relation;
      }
      if (overlay.containsKey('life_status')) {
        character.isAlive = old.isAlive;
      }
    }
    return result;
  }
}
