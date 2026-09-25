import '../../models/adventure_config.dart';
import '../../models/typed_runtime_state.dart';
import 'adventure_runtime_state_resolver.dart';

/// Read-only presentation projection of a frozen adventure baseline plus a
/// replayed runtime overlay. It is never written back as current state.
final class RuntimeEffectiveStateView {
  final AdventureConfig baseline;
  final RuntimeStateSnapshot snapshot;
  final AdventureConfig effectiveConfig;

  const RuntimeEffectiveStateView({
    required this.baseline,
    required this.snapshot,
    required this.effectiveConfig,
  });

  int get revision => snapshot.revision;

  bool isPartOfBaseline(String entityId) {
    if (baseline.protagonistCharacter?.characterId == entityId ||
        (entityId == 'protagonist' && baseline.protagonistCharacter != null)) {
      return true;
    }
    return baseline.supportingCharacters
        .any((character) => character.id == entityId);
  }

  factory RuntimeEffectiveStateView.fromSnapshot({
    required AdventureConfig baseline,
    required RuntimeStateSnapshot snapshot,
    AdventureRuntimeStateResolver resolver =
        const AdventureRuntimeStateResolver(),
  }) {
    return RuntimeEffectiveStateView(
      baseline: baseline,
      snapshot: snapshot,
      effectiveConfig: resolver.effectiveConfig(
        baseline,
        snapshot.entities.values,
      ),
    );
  }
}
