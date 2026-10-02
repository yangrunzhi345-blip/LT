import '../../models/custom_attribute_item.dart';
import '../../models/tracked_state_definition.dart';
import '../../models/typed_runtime_state.dart';

/// Compatibility bridge from the legacy `custom_attributes` protocol to the
/// unified [TrackedStateDefinition].
///
/// This exists **only** as a fallback for resources and adventures created
/// before explicit `tracked_state_definitions` existed. When a resource carries
/// explicit definitions those are the authority and this adapter must not be
/// consulted for that entity — otherwise the same status would be monitored
/// twice.
///
/// A legacy item mixes a static attribute and a runtime value in one record
/// (`CustomAttributeItem.currentValue`). The adapter deliberately keeps the
/// *shape* (name, range, importance, rule) and drops the current value: the
/// legacy value is a runtime fact, and the definition must never carry it.
final class TrackedStateLegacyAdapter {
  const TrackedStateLegacyAdapter._();

  static TrackedStateDefinition fromCustomAttribute(
    CustomAttributeItem item,
  ) {
    final numeric = item.isNumeric;
    return TrackedStateDefinition(
      id: item.identityRef,
      name: item.name.trim(),
      valueKind:
          numeric ? RuntimeStateValueKind.integer : RuntimeStateValueKind.text,
      description: item.description?.trim() ?? '',
      importance: item.importance,
      minimum: numeric ? 0 : null,
      maximum: numeric ? item.effectiveMaxValue : null,
      icon: item.icon,
    );
  }

  /// Projects a list of legacy items, skipping blanks and de-duplicating by id.
  static List<TrackedStateDefinition> fromCustomAttributes(
    Iterable<CustomAttributeItem> items, {
    List<String>? diagnostics,
    String source = 'legacy',
  }) {
    final result = <TrackedStateDefinition>[];
    final seen = <String>{};
    for (final item in items) {
      if (item.name.trim().isEmpty) continue;
      final definition = fromCustomAttribute(item);
      if (definition.effectiveId.isEmpty) continue;
      if (!seen.add(definition.effectiveId)) {
        diagnostics?.add(
            'legacy_tracked_state:duplicate:$source:${definition.effectiveId}');
        continue;
      }
      result.add(definition);
    }
    return List.unmodifiable(result);
  }
}
