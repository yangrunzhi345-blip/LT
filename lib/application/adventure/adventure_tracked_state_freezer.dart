import '../../models/adventure_config.dart';
import '../../models/adventure_runtime_state.dart';
import '../../models/adventure_tracked_state.dart';
import '../../models/custom_attribute_item.dart';
import '../../models/supporting_character.dart';
import '../../models/tracked_state_definition.dart';
import '../../models/worldview_details.dart';
import 'adventure_character_identity.dart';
import 'adventure_tracked_state_registry.dart';
import 'tracked_state_legacy_adapter.dart';

/// Builds an adventure's frozen monitoring definitions from every resource
/// source, at assembly time.
///
/// This is the "Freeze" step of
/// `Resource → Assembly → Freeze → AdventureConfig.trackedStateDefinitions`.
/// It deliberately walks **all** entities — protagonist, every
/// `selectedCharacters` row (including selected-only companions),
/// `supportingCharacters` fallback, NPC snapshots and the world snapshot — so
/// the "only the protagonist is monitored" defect cannot recur.
///
/// Per-entity authority rule: if an entity carries explicit
/// `tracked_state_definitions`, those are its authority (even when empty) and
/// its legacy `custom_attributes` are treated as static lore. Only when the
/// entity has no explicit definitions does the legacy projection apply, so a
/// status is never monitored twice.
final class AdventureTrackedStateFreezer {
  const AdventureTrackedStateFreezer();

  List<AdventureTrackedStateDefinition> freeze(
    AdventureConfig config, {
    List<String>? diagnostics,
  }) {
    // Already frozen (idempotent): never rebuild over an adventure's authority.
    if (config.trackedStateDefinitions.isNotEmpty) {
      return config.trackedStateDefinitions;
    }

    final result = <AdventureTrackedStateDefinition>[];

    if (config.selectedCharacters.isNotEmpty) {
      final rostered = <String>{};
      for (final selected in config.selectedCharacters) {
        final id = AdventureCharacterIdentity.effectiveId(selected);
        if (id.isEmpty) continue;
        rostered.add(id);
        result.addAll(_fromSelection(
          config: config,
          selected: selected,
          entityId: id,
          diagnostics: diagnostics,
        ));
      }
      for (final supporting in config.supportingCharacters) {
        final id = supporting.id.trim();
        if (id.isEmpty || rostered.contains(id)) continue;
        result.addAll(_fromSupporting(
          supporting,
          entityId: id,
          diagnostics: diagnostics,
        ));
      }
    } else {
      // Legacy config with no selection roster: protagonist + supporting.
      final protagonistId =
          AdventureTrackedStateRegistry.protagonistEntityId(config);
      final cardDefinitions = config.characterCard?.trackedStateDefinitions;
      if (cardDefinitions != null && cardDefinitions.isNotEmpty) {
        result.addAll(_bind(
          RuntimeEntityType.character,
          protagonistId,
          cardDefinitions,
        ));
      } else {
        result.addAll(_bind(
          RuntimeEntityType.character,
          protagonistId,
          TrackedStateLegacyAdapter.fromCustomAttributes(
            config.customAttributes,
            diagnostics: diagnostics,
            source: 'protagonist',
          ),
        ));
      }
      for (final supporting in config.supportingCharacters) {
        final id = supporting.id.trim();
        if (id.isEmpty) continue;
        result.addAll(_fromSupporting(
          supporting,
          entityId: id,
          diagnostics: diagnostics,
        ));
      }
    }

    for (final npc in config.npcSnapshots) {
      final id = npc.assetId.trim();
      if (id.isEmpty) continue;
      result.addAll(
          _fromNpc(npc.npcJson, entityId: id, diagnostics: diagnostics));
    }

    result
        .addAll(_fromWorld(config.worldviewSnapshot, diagnostics: diagnostics));

    return _dedupe(result);
  }

  List<AdventureTrackedStateDefinition> _fromSelection({
    required AdventureConfig config,
    required AdventureSelectedCharacter selected,
    required String entityId,
    List<String>? diagnostics,
  }) {
    final cardJson = selected.characterCardJson;
    if (cardJson != null) {
      final data = _unwrap(cardJson);
      if (_hasExplicitDefinitions(data)) {
        return _bind(
          RuntimeEntityType.character,
          entityId,
          TrackedStateDefinition.parseList(
            data['tracked_state_definitions'] ??
                data['trackedStateDefinitions'],
            diagnostics: diagnostics,
            source: 'character:$entityId',
            fromResource: true,
          ),
        );
      }
    }
    final index = AdventureCharacterIdentity.indexOfSupporting(
      config.supportingCharacters,
      selected,
    );
    final legacy = index >= 0
        ? config.supportingCharacters[index].customAttributes
        : const <CustomAttributeItem>[];
    return _bind(
      RuntimeEntityType.character,
      entityId,
      TrackedStateLegacyAdapter.fromCustomAttributes(
        legacy,
        diagnostics: diagnostics,
        source: 'character:$entityId',
      ),
    );
  }

  List<AdventureTrackedStateDefinition> _fromSupporting(
    SupportingCharacter supporting, {
    required String entityId,
    List<String>? diagnostics,
  }) {
    if (supporting.trackedStateDefinitions.isNotEmpty) {
      return _bind(
        RuntimeEntityType.character,
        entityId,
        supporting.trackedStateDefinitions,
      );
    }
    return _bind(
      RuntimeEntityType.character,
      entityId,
      TrackedStateLegacyAdapter.fromCustomAttributes(
        supporting.customAttributes,
        diagnostics: diagnostics,
        source: 'supporting:$entityId',
      ),
    );
  }

  List<AdventureTrackedStateDefinition> _fromNpc(
    Map<String, dynamic> npcJson, {
    required String entityId,
    List<String>? diagnostics,
  }) {
    final data = _unwrap(npcJson);
    if (_hasExplicitDefinitions(data)) {
      return _bind(
        RuntimeEntityType.npc,
        entityId,
        TrackedStateDefinition.parseList(
          data['tracked_state_definitions'] ?? data['trackedStateDefinitions'],
          diagnostics: diagnostics,
          source: 'npc:$entityId',
          fromResource: true,
        ),
      );
    }
    final legacy = <CustomAttributeItem>[];
    final raw = data['custom_attributes'] ?? data['customAttributes'];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          legacy.add(
              CustomAttributeItem.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return _bind(
      RuntimeEntityType.npc,
      entityId,
      TrackedStateLegacyAdapter.fromCustomAttributes(
        legacy,
        diagnostics: diagnostics,
        source: 'npc:$entityId',
      ),
    );
  }

  List<AdventureTrackedStateDefinition> _fromWorld(
    Map<String, dynamic>? snapshot, {
    List<String>? diagnostics,
  }) {
    if (snapshot == null) return const [];
    final raw = snapshot['detail_json'];
    final details = WorldviewDetails.fromJson(
      raw is Map ? Map<String, dynamic>.from(raw) : null,
    );
    if (details.trackedStateDefinitions.isEmpty) return const [];
    return _bind(
      RuntimeEntityType.world,
      AdventureRuntimeEntityIds.world,
      details.trackedStateDefinitions,
    );
  }

  List<AdventureTrackedStateDefinition> _bind(
    RuntimeEntityType entityType,
    String entityId,
    Iterable<TrackedStateDefinition> definitions,
  ) =>
      [
        for (final definition in definitions)
          AdventureTrackedStateDefinition(
            entityType: entityType,
            entityId: entityId,
            definition: definition,
          ),
      ];

  static bool _hasExplicitDefinitions(Map<String, dynamic> data) =>
      data.containsKey('tracked_state_definitions') ||
      data.containsKey('trackedStateDefinitions');

  /// Unwraps a SillyTavern `data` envelope, mirroring [CharacterCard.fromJson].
  static Map<String, dynamic> _unwrap(Map<String, dynamic> raw) {
    final nested = raw['data'];
    return nested is Map ? Map<String, dynamic>.from(nested) : raw;
  }

  static List<AdventureTrackedStateDefinition> _dedupe(
    Iterable<AdventureTrackedStateDefinition> definitions,
  ) {
    final seen = <String>{};
    final result = <AdventureTrackedStateDefinition>[];
    for (final binding in definitions) {
      if (binding.entityId.trim().isEmpty) continue;
      if (binding.definition.effectiveId.isEmpty) continue;
      if (seen.add(binding.key)) result.add(binding);
    }
    return List.unmodifiable(result);
  }
}
