import '../../models/adventure_config.dart';
import '../../models/adventure_runtime_state.dart';
import '../../models/tracked_state_definition.dart';
import '../../models/typed_runtime_state.dart';
import 'adventure_tracked_state_registry.dart';

/// Read-only projection of the frozen tracked-state definitions plus the runtime
/// overlay into the per-turn `custom_status` **presentation snapshot** carried
/// by an assistant message.
///
/// This is presentation data, never authority. It writes nothing and never
/// reads the resource library. The value chain it reads is exactly the runtime
/// authority:
///
/// `AdventureConfig.trackedStateDefinitions → AdventureTrackedStateRegistry →
/// RuntimeEntityState.overlay`
///
/// with this turn's already-accepted changes applied on top, so the snapshot
/// equals the value the atomic commit will persist. A definition with no value
/// is emitted as an explicit untriggered item — it is never dropped, and never
/// fabricated into `0`.
///
/// The output is serialized with the existing `custom_status` item shape
/// (compatible with `CustomAttributeItem.fromJson`) plus two additive,
/// presentation-only keys (`untriggered`, `value_kind`). No parallel protocol is
/// introduced.
final class TrackedStateSnapshotBuilder {
  const TrackedStateSnapshotBuilder();

  /// Only character/NPC monitors are shown inline in the narrative body. World /
  /// faction / location monitors stay in the Runtime State Hub, so the inline
  /// block never crowds the reading area with non-character state.
  static const Set<RuntimeEntityType> _inlineEntityTypes = {
    RuntimeEntityType.character,
    RuntimeEntityType.npc,
  };

  List<Map<String, dynamic>> build({
    required AdventureConfig config,
    required Iterable<RuntimeEntityState> runtimeEntities,
    List<RuntimeStateChangeProposal> acceptedChanges = const [],
  }) {
    final registry = AdventureTrackedStateRegistry.fromConfig(config);
    if (registry.isEmpty) return const [];

    final names = AdventureTrackedStateRegistry.entityDisplayNames(config);

    // 1. Project this turn's accepted `custom_attributes.*` changes onto a copy
    //    of the current overlay, mirroring the store's apply rules (bounds clamp
    //    from the frozen definition, increments accumulate on the current value).
    final overlayByEntity = <String, Map<String, Object?>>{
      for (final entity in runtimeEntities)
        _entityKey(entity.entityType, entity.entityId):
            Map<String, Object?>.from(entity.overlay),
    };
    for (final change in acceptedChanges) {
      final attributeId =
          RuntimeStateChangeProposal.customAttributeIdFromPath(change.path);
      if (attributeId == null) continue;
      final overlay = overlayByEntity.putIfAbsent(
          _entityKey(change.entityType, change.entityId),
          () => <String, Object?>{});
      final definition = registry
          .find(change.entityType, change.entityId, attributeId)
          ?.definition;
      final before = overlay[change.path] ??
          _legacyBaselineValue(config, change.entityId, attributeId);
      final after = _apply(before, change, definition);
      if (after == null) {
        overlay.remove(change.path);
      } else {
        overlay[change.path] = after;
      }
    }

    // 2. Emit every inline definition, in registry order, with its post-turn
    //    value (or an explicit untriggered marker).
    final items = <Map<String, dynamic>>[];
    for (final binding in registry.all) {
      if (!_inlineEntityTypes.contains(binding.entityType)) continue;
      final definition = binding.definition;
      final overlay =
          overlayByEntity[_entityKey(binding.entityType, binding.entityId)] ??
              const <String, Object?>{};
      final path = RuntimeStateChangeProposal.customAttributePath(
        definition.effectiveId,
      );
      final value = overlay[path] ??
          _legacyBaselineValue(
              config, binding.entityId, definition.effectiveId);
      final name = names[binding.entityId]?.trim();
      items.add(_item(
        definition,
        value,
        characterName:
            (name != null && name.isNotEmpty) ? name : binding.entityId,
      ));
    }
    return items;
  }

  Map<String, dynamic> _item(
    TrackedStateDefinition definition,
    Object? value, {
    required String characterName,
  }) {
    final item = <String, dynamic>{
      'id': definition.effectiveId,
      'name': definition.name,
      'value': '',
      'characterName': characterName,
      'value_kind': definition.valueKind.name,
      if (definition.icon?.trim().isNotEmpty == true)
        'icon': definition.icon!.trim(),
      if (definition.description.trim().isNotEmpty)
        'description': definition.description.trim(),
    };
    if (value == null) {
      // "Exists but has no runtime value" is a first-class state.
      item['untriggered'] = true;
      return item;
    }
    if (definition.valueKind == RuntimeStateValueKind.boolean) {
      item['value'] =
          (value == true || value.toString() == 'true') ? 'true' : 'false';
      return item;
    }
    if (definition.isNumeric && value is num) {
      final clamped = definition.clampNumeric(value);
      final maximum = definition.maximum;
      if (maximum != null) {
        final current = clamped.truncate();
        final max = maximum.truncate();
        item['value'] = '$current/$max';
        item['currentValue'] = current;
        item['maxValue'] = max;
      } else {
        item['value'] = _formatNumber(clamped);
      }
      return item;
    }
    item['value'] = value.toString();
    return item;
  }

  /// Mirrors the store's `_applyRuntimeOperation` for `custom_attributes.*`:
  /// bounds from the frozen definition clamp the settled numeric value, and an
  /// increment accumulates on the current value. Returns the committed value.
  Object? _apply(
    Object? before,
    RuntimeStateChangeProposal change,
    TrackedStateDefinition? definition,
  ) {
    final result = switch (change.operation) {
      RuntimeChangeOperation.set => change.value,
      RuntimeChangeOperation.remove => null,
      RuntimeChangeOperation.increment
          when before is num && change.value is num =>
        before + (change.value as num),
      RuntimeChangeOperation.increment
          when before == null && change.value is num =>
        change.value,
      _ => before,
    };
    if (result is num) {
      var clamped = result;
      final minimum = definition?.minimum;
      final maximum = definition?.maximum;
      if (minimum != null && clamped < minimum) clamped = minimum;
      if (maximum != null && clamped > maximum) clamped = maximum;
      return clamped;
    }
    return result;
  }

  /// Legacy `custom_attributes` baseline value for an entity, used only for
  /// adventures created before explicit definitions existed. Never written back.
  Object? _legacyBaselineValue(
    AdventureConfig config,
    String entityId,
    String attributeId,
  ) {
    final protagonistId =
        config.protagonistCharacter?.characterId ?? 'protagonist';
    final attributes = (entityId == protagonistId || entityId == 'protagonist')
        ? config.customAttributes
        : config.supportingCharacters
                .where((character) => character.id == entityId)
                .firstOrNull
                ?.customAttributes ??
            const [];
    final attribute =
        attributes.where((item) => item.identityRef == attributeId).firstOrNull;
    if (attribute == null) return null;
    return attribute.isNumeric
        ? attribute.effectiveCurrentValue
        : attribute.value.trim();
  }

  static String _formatNumber(num value) => value == value.truncate()
      ? value.truncate().toString()
      : value.toString();

  static String _entityKey(RuntimeEntityType type, String entityId) =>
      '${type.name}:$entityId';
}
