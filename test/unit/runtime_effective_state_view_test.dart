import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/adventure/runtime_effective_state_view.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/typed_runtime_state.dart';

void main() {
  test('effective view overlays a replay projection without mutating baseline',
      () {
    final baseline = AdventureConfig(name: 'Baseline');
    final snapshot = RuntimeStateSnapshot(
      adventureId: 1,
      branchId: 0,
      revision: 4,
      entities: {
        'character:protagonist': RuntimeEntityState(
          entityType: RuntimeEntityType.character,
          entityId: 'protagonist',
          overlay: {'custom_attributes.mood': 'injured'},
        ),
      },
    );

    final view = RuntimeEffectiveStateView.fromSnapshot(
      baseline: baseline,
      snapshot: snapshot,
    );

    expect(view.revision, 4);
    expect(view.baseline, isNot(same(view.effectiveConfig)));
    expect(view.snapshot.entities, hasLength(1));
    expect(view.isPartOfBaseline('protagonist'), isFalse);
    expect(view.isPartOfBaseline('joined-later'), isFalse);
  });
}
