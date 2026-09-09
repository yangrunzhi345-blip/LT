import '../models/adventure_runtime_state.dart';

/// Validates persistent narrative proposals before repository transaction work.
/// Scene consistency remains intentionally separate from this data boundary.
final class RuntimeStateValidator {
  const RuntimeStateValidator();

  List<RuntimeStateChangeProposal> accept(
    Iterable<RuntimeStateChangeProposal> proposals,
  ) {
    final accepted = <RuntimeStateChangeProposal>[];
    final paths = <String>{};
    for (final proposal in proposals) {
      final key =
          '${proposal.entityType.name}:${proposal.entityId}:${proposal.path}';
      if (!paths.add(key)) {
        throw ArgumentError('Conflicting runtime changes for $key');
      }
      if (!_isValid(proposal)) continue;
      accepted.add(proposal);
    }
    return List.unmodifiable(accepted);
  }

  bool _isValid(RuntimeStateChangeProposal proposal) {
    if (proposal.changeKind == RuntimeChangeKind.derived &&
        proposal.reason.trim().isEmpty) {
      return false;
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
}
