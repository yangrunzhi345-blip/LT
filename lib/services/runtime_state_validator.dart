import '../models/adventure_runtime_state.dart';
import '../models/adventure_config.dart';
import '../models/custom_attribute_item.dart';

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
    if (proposal.changeKind == RuntimeChangeKind.derived &&
        proposal.reason.trim().isEmpty) {
      return false;
    }
    final customAttributeId =
        RuntimeStateChangeProposal.customAttributeIdFromPath(proposal.path);
    if (customAttributeId != null) {
      return _isValidCustomAttribute(proposal, customAttributeId, config);
    }
    return switch (proposal.path) {
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

  bool _isValidCustomAttribute(
    RuntimeStateChangeProposal proposal,
    String attributeId,
    AdventureConfig? config,
  ) {
    if (config == null || proposal.entityType != RuntimeEntityType.character) {
      return false;
    }
    final attributes = _attributesForEntity(config, proposal.entityId);
    final attribute =
        attributes.where((item) => item.identityRef == attributeId).firstOrNull;
    if (attribute == null || proposal.operation != RuntimeChangeOperation.set) {
      return false;
    }
    final value = proposal.value;
    if (attribute.isNumeric) {
      return value is num &&
          value.isFinite &&
          value >= 0 &&
          value <= attribute.effectiveMaxValue;
    }
    return value is String && value.trim().isNotEmpty && value.length <= 1000;
  }

  List<CustomAttributeItem> _attributesForEntity(
    AdventureConfig config,
    String entityId,
  ) {
    final protagonistId =
        config.protagonistCharacter?.characterId ?? 'protagonist';
    if (entityId == protagonistId || entityId == 'protagonist') {
      return config.customAttributes;
    }
    return config.supportingCharacters
            .where((character) => character.id == entityId)
            .firstOrNull
            ?.customAttributes ??
        const [];
  }
}
