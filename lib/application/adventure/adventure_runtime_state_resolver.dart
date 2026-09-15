import '../../models/adventure_config.dart';
import '../../models/adventure_runtime_state.dart';
import '../../models/custom_attribute_item.dart';

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
    final protagonistId =
        result.protagonistCharacter?.characterId ?? 'protagonist';
    final protagonistRuntime = byId[protagonistId] ?? byId['protagonist'];
    if (protagonistRuntime != null) {
      result.customAttributes = _effectiveCustomAttributes(
        result.customAttributes,
        protagonistRuntime.overlay,
      );
    }
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
      character.customAttributes = _effectiveCustomAttributes(
        character.customAttributes,
        values,
      );
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
    final protagonistId =
        priorBaseline.protagonistCharacter?.characterId ?? 'protagonist';
    final protagonistOverlay =
        overlays[protagonistId]?.overlay ?? overlays['protagonist']?.overlay;
    if (protagonistOverlay != null) {
      result.customAttributes = _restoreOverlaidCustomAttributes(
        result.customAttributes,
        priorBaseline.customAttributes,
        protagonistOverlay,
      );
    }
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
      character.customAttributes = _restoreOverlaidCustomAttributes(
        character.customAttributes,
        old.customAttributes,
        overlay,
      );
    }
    return result;
  }

  List<CustomAttributeItem> _effectiveCustomAttributes(
    List<CustomAttributeItem> baseline,
    Map<String, Object?> overlay,
  ) =>
      baseline.map((attribute) {
        final path = RuntimeStateChangeProposal.customAttributePath(
          attribute.identityRef,
        );
        if (!overlay.containsKey(path)) return attribute;
        return _withRuntimeValue(attribute, overlay[path]);
      }).toList(growable: false);

  List<CustomAttributeItem> _restoreOverlaidCustomAttributes(
    List<CustomAttributeItem> edited,
    List<CustomAttributeItem> baseline,
    Map<String, Object?> overlay,
  ) {
    final initialByIdentity = {
      for (final attribute in baseline) attribute.identityRef: attribute,
    };
    return edited.map((attribute) {
      final path = RuntimeStateChangeProposal.customAttributePath(
        attribute.identityRef,
      );
      if (!overlay.containsKey(path)) return attribute;
      return initialByIdentity[attribute.identityRef] ?? attribute;
    }).toList(growable: false);
  }

  CustomAttributeItem _withRuntimeValue(
    CustomAttributeItem attribute,
    Object? value,
  ) {
    if (attribute.isNumeric && value is num) {
      final current = value.toInt().clamp(0, attribute.effectiveMaxValue);
      return attribute.copyWith(
        currentValue: current,
        value: '$current/${attribute.effectiveMaxValue}',
      );
    }
    if (!attribute.isNumeric && value is String && value.trim().isNotEmpty) {
      return attribute.copyWith(value: value.trim());
    }
    return attribute;
  }
}
