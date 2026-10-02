import '../../models/adventure_config.dart';
import '../../models/adventure_runtime_state.dart';
import '../../models/adventure_tracked_state.dart';
import 'adventure_character_identity.dart';
import 'tracked_state_legacy_adapter.dart';

/// The **only** projection from a frozen [AdventureConfig] to the monitoring
/// definitions the rest of the app is allowed to read.
///
/// Every consumer (settlement candidate planner, runtime validator, UI) goes
/// through this registry. That is what removes the old dual-track authority
/// where the protagonist was read from `config.customAttributes` and companions
/// from `supportingCharacters`, and what guarantees an NPC or the world is
/// never silently dropped because it is "not the protagonist".
///
/// Authority order:
/// 1. [AdventureConfig.trackedStateDefinitions] — the frozen, adventure-local
///    authority. Present once an adventure has been assembled by the current
///    version.
/// 2. Legacy `customAttributes` projection — a compatibility fallback for
///    adventures created before definitions existed.
final class AdventureTrackedStateRegistry {
  final List<AdventureTrackedStateDefinition> _definitions;
  final Map<String, List<AdventureTrackedStateDefinition>> _byEntity;

  AdventureTrackedStateRegistry._(this._definitions)
      : _byEntity = _index(_definitions);

  factory AdventureTrackedStateRegistry(
    Iterable<AdventureTrackedStateDefinition> definitions,
  ) =>
      AdventureTrackedStateRegistry._(_dedupe(definitions));

  /// Builds the registry for [config], falling back to the legacy projection
  /// only when the config carries no frozen definitions at all.
  static AdventureTrackedStateRegistry fromConfig(
    AdventureConfig? config, {
    List<String>? diagnostics,
  }) {
    if (config == null) {
      return AdventureTrackedStateRegistry(const []);
    }
    if (config.trackedStateDefinitions.isNotEmpty) {
      return AdventureTrackedStateRegistry(config.trackedStateDefinitions);
    }
    return AdventureTrackedStateRegistry(
      _legacyProjection(config, diagnostics: diagnostics),
    );
  }

  /// The stable character id used for the protagonist of [config].
  static String protagonistEntityId(AdventureConfig config) {
    final selected = config.protagonistCharacter;
    if (selected != null) {
      final id = AdventureCharacterIdentity.effectiveId(selected);
      if (id.isNotEmpty) return id;
    }
    final characterId = config.protagonistCharacter?.characterId.trim() ?? '';
    return characterId.isNotEmpty ? characterId : 'protagonist';
  }

  List<AdventureTrackedStateDefinition> get all => _definitions;

  bool get isEmpty => _definitions.isEmpty;
  bool get isNotEmpty => _definitions.isNotEmpty;

  /// Every `(entityType, entityId)` pair that owns at least one definition.
  Set<String> get entityKeys => _byEntity.keys.toSet();

  List<AdventureTrackedStateDefinition> forEntity(
    RuntimeEntityType entityType,
    String entityId,
  ) =>
      _byEntity[_entityKey(entityType, entityId)] ?? const [];

  AdventureTrackedStateDefinition? find(
    RuntimeEntityType entityType,
    String entityId,
    String definitionId,
  ) {
    final clean = definitionId.trim();
    if (clean.isEmpty) return null;
    for (final binding in forEntity(entityType, entityId)) {
      if (binding.definitionId == clean) return binding;
    }
    return null;
  }

  bool hasDefinition(
    RuntimeEntityType entityType,
    String entityId,
    String definitionId,
  ) =>
      find(entityType, entityId, definitionId) != null;

  static String _entityKey(RuntimeEntityType type, String entityId) =>
      '${type.name}:$entityId';

  static Map<String, List<AdventureTrackedStateDefinition>> _index(
    List<AdventureTrackedStateDefinition> definitions,
  ) {
    final result = <String, List<AdventureTrackedStateDefinition>>{};
    for (final binding in definitions) {
      result
          .putIfAbsent(
              _entityKey(binding.entityType, binding.entityId), () => [])
          .add(binding);
    }
    return {
      for (final entry in result.entries)
        entry.key: List.unmodifiable(entry.value)
    };
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

  static List<AdventureTrackedStateDefinition> _legacyProjection(
    AdventureConfig config, {
    List<String>? diagnostics,
  }) {
    final result = <AdventureTrackedStateDefinition>[];
    final protagonistId = protagonistEntityId(config);
    for (final definition in TrackedStateLegacyAdapter.fromCustomAttributes(
      config.customAttributes,
      diagnostics: diagnostics,
      source: 'protagonist',
    )) {
      result.add(AdventureTrackedStateDefinition(
        entityType: RuntimeEntityType.character,
        entityId: protagonistId,
        definition: definition,
      ));
    }
    for (final character in config.supportingCharacters) {
      final id = character.id.trim();
      if (id.isEmpty) continue;
      for (final definition in TrackedStateLegacyAdapter.fromCustomAttributes(
        character.customAttributes,
        diagnostics: diagnostics,
        source: 'supporting:$id',
      )) {
        result.add(AdventureTrackedStateDefinition(
          entityType: RuntimeEntityType.character,
          entityId: id,
          definition: definition,
        ));
      }
    }
    return _dedupe(result);
  }
}
