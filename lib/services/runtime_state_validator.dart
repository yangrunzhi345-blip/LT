import '../application/adventure/adventure_character_identity.dart';
import '../application/adventure/adventure_tracked_state_registry.dart';
import '../models/adventure_runtime_state.dart';
import '../models/adventure_config.dart';
import '../models/tracked_state_definition.dart';
import '../models/typed_runtime_state.dart';

/// Validates persistent narrative proposals before repository transaction work.
/// Scene consistency remains intentionally separate from this data boundary.
final class RuntimeStateValidator {
  const RuntimeStateValidator();

  List<RuntimeStateChangeProposal> accept(
    Iterable<RuntimeStateChangeProposal> proposals, {
    AdventureConfig? config,
  }) {
    final accepted = <RuntimeStateChangeProposal>[];
    final paths = <String>{};
    for (final proposal in proposals) {
      final key =
          '${proposal.entityType.name}:${proposal.entityId}:${proposal.path}';
      if (!paths.add(key)) {
        throw ArgumentError('Conflicting runtime changes for $key');
      }
      if (!_isValid(proposal, config)) continue;
      accepted.add(proposal);
    }
    return List.unmodifiable(accepted);
  }

  bool _isValid(
    RuntimeStateChangeProposal proposal,
    AdventureConfig? config,
  ) {
    if (config != null && proposal.entityType == RuntimeEntityType.character) {
      if (!knownCharacterIds(config).contains(proposal.entityId)) {
        return false;
      }
    }
    if (proposal.changeKind == RuntimeChangeKind.derived &&
        proposal.reason.trim().isEmpty) {
      return false;
    }
    final customAttributeId =
        RuntimeStateChangeProposal.customAttributeIdFromPath(proposal.path);
    if (customAttributeId != null) {
      return _isValidCustomAttribute(proposal, customAttributeId, config);
    }
    final definition = RuntimeStateSchemaRegistry.find(proposal.path);
    if (definition != null &&
        definition.accepts(proposal.entityType, proposal.value)) {
      return switch (proposal.operation) {
        RuntimeChangeOperation.set => true,
        RuntimeChangeOperation.increment => proposal.value is num &&
            (definition.valueKind == RuntimeStateValueKind.integer ||
                definition.valueKind == RuntimeStateValueKind.number),
        RuntimeChangeOperation.remove => true,
        RuntimeChangeOperation.appendUnique => false,
      };
    }
    return switch (proposal.path) {
      'hp' ||
      'mp' ||
      'energy' ||
      'experience' ||
      'level' ||
      'base_atk' ||
      'base_def' ||
      'base_speed'
          when proposal.operation == RuntimeChangeOperation.increment &&
              proposal.value is num =>
        true,
      'life_status' => proposal.operation == RuntimeChangeOperation.set &&
          const {'alive', 'dead'}.contains(proposal.value),
      'lifecycle_status' => proposal.operation == RuntimeChangeOperation.set &&
          const {'active', 'dead', 'destroyed', 'inactive'}
              .contains(proposal.value),
      'affinity' => proposal.operation == RuntimeChangeOperation.increment &&
          proposal.value is num,
      'relationship' ||
      'faction_id' ||
      'former_faction_id' ||
      'goal' ||
      'controller_id' ||
      'status' =>
        proposal.operation == RuntimeChangeOperation.set &&
            proposal.value is String,
      _ => false,
    };
  }

  /// Validates a `custom_attributes.<definitionId>` proposal against the single
  /// [AdventureTrackedStateRegistry].
  ///
  /// A monitor exists only when the frozen AdventureConfig declares it for this
  /// exact `(entityType, entityId)`. A model that invents
  /// `custom_attributes.random_mood` — or attaches a real monitor to the wrong
  /// entity — is rejected, so the model can never create state on its own. The
  /// same path applies to characters, NPCs and the world; there is no
  /// character-only branch.
  bool _isValidCustomAttribute(
    RuntimeStateChangeProposal proposal,
    String attributeId,
    AdventureConfig? config,
  ) {
    if (config == null) return false;
    final binding = AdventureTrackedStateRegistry.fromConfig(config)
        .find(proposal.entityType, proposal.entityId, attributeId);
    if (binding == null) return false;
    final definition = binding.definition;
    final value = proposal.value;
    return switch (proposal.operation) {
      RuntimeChangeOperation.set => _acceptsDefinition(definition, value),
      RuntimeChangeOperation.increment =>
        definition.isNumeric && value is num && value.isFinite,
      RuntimeChangeOperation.remove => true,
      RuntimeChangeOperation.appendUnique => false,
    };
  }

  /// Every stable character id the adventure roster knows.
  ///
  /// `selectedCharacters` is the authoritative roster; `supportingCharacters` is
  /// kept as a compatibility fallback. Reading only `supportingCharacters` used
  /// to reject every selected-only companion, which is exactly the defect the
  /// unified tracking system removes.
  static Set<String> knownCharacterIds(AdventureConfig config) => {
        'protagonist',
        if (config.protagonistCharacter != null)
          ...AdventureCharacterIdentity.candidateIds(
              config.protagonistCharacter!),
        for (final selected in config.selectedCharacters)
          ...AdventureCharacterIdentity.candidateIds(selected),
        for (final character in config.supportingCharacters)
          character.id.trim(),
      };

  bool _acceptsDefinition(
    TrackedStateDefinition definition,
    Object? value,
  ) {
    if (definition.valueKind == RuntimeStateValueKind.text) {
      return value is String && value.trim().isNotEmpty && value.length <= 1000;
    }
    return definition.accepts(value);
  }
}
