import '../../models/adventure_config.dart';
import '../../models/adventure_runtime_state.dart';
import '../../models/adventure_tracked_state.dart';
import '../../models/tracked_state_definition.dart';

/// Adventure-local authoring of monitoring definitions.
///
/// Editing a definition here changes **only this adventure**. It never writes
/// back to the character card, NPC resource or worldview resource; those are
/// frozen snapshots owned by the resource library.
///
/// A definition id is stable. Renaming or re-describing a monitor keeps the id
/// and therefore its runtime value. Changing the *shape* (kind or bounds) so an
/// existing runtime value is no longer legal is reported via
/// [DefinitionUpdate.clearRuntimeValue]; the caller then removes the overlay
/// value through the normal append-only runtime mutation, so the monitor simply
/// returns to "untriggered" and can be re-initialised later.
final class AdventureTrackedStateDefinitionStore {
  const AdventureTrackedStateDefinitionStore();

  AdventureConfig add({
    required AdventureConfig config,
    required AdventureTrackedStateDefinition binding,
  }) {
    final existing = config.trackedStateDefinitions
        .where((candidate) => candidate.key == binding.key);
    if (existing.isNotEmpty) return config;
    return config.copyWith(
      trackedStateDefinitions: [...config.trackedStateDefinitions, binding],
    );
  }

  /// Removes a definition from the adventure. History is never touched here:
  /// runtime events and diffs remain append-only and keep pointing at the
  /// removed id, so past timeline entries are still readable.
  AdventureConfig remove({
    required AdventureConfig config,
    required RuntimeEntityType entityType,
    required String entityId,
    required String definitionId,
  }) {
    final key = '${entityType.name}:$entityId:$definitionId';
    final next = config.trackedStateDefinitions
        .where((binding) => binding.key != key)
        .toList();
    if (next.length == config.trackedStateDefinitions.length) return config;
    return config.copyWith(trackedStateDefinitions: next);
  }

  /// Updates [definitionId]'s shape/text. [currentValue] is the runtime HEAD
  /// value (if any) used to decide whether the edit invalidated it.
  DefinitionUpdate update({
    required AdventureConfig config,
    required RuntimeEntityType entityType,
    required String entityId,
    required String definitionId,
    required TrackedStateDefinition definition,
    Object? currentValue,
  }) {
    final key = '${entityType.name}:$entityId:$definitionId';
    AdventureTrackedStateDefinition? existing;
    for (final binding in config.trackedStateDefinitions) {
      if (binding.key == key) {
        existing = binding;
        break;
      }
    }
    if (existing == null) {
      return DefinitionUpdate(config: config, clearRuntimeValue: false);
    }
    // The id is the identity: an edit can never silently re-target it.
    final updatedDefinition = definition.copyWith(id: existing.definitionId);
    final next = [
      for (final binding in config.trackedStateDefinitions)
        if (binding.key == key)
          binding.copyWith(definition: updatedDefinition)
        else
          binding,
    ];
    final clearRuntimeValue =
        currentValue != null && !updatedDefinition.accepts(currentValue);
    return DefinitionUpdate(
      config: config.copyWith(trackedStateDefinitions: next),
      clearRuntimeValue: clearRuntimeValue,
    );
  }
}

/// Result of [AdventureTrackedStateDefinitionStore.update].
final class DefinitionUpdate {
  final AdventureConfig config;

  /// True when the edited definition no longer accepts the runtime value, so
  /// the caller must remove the overlay value (append-only) and let the monitor
  /// return to "untriggered".
  final bool clearRuntimeValue;

  const DefinitionUpdate({
    required this.config,
    required this.clearRuntimeValue,
  });
}
