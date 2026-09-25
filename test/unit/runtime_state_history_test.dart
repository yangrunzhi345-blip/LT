import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/runtime_state_history.dart';
import 'package:lt_dialogue/models/typed_runtime_state.dart';

void main() {
  RuntimeStateSnapshot snapshot(int revision, Map<String, Object?> overlay) =>
      RuntimeStateSnapshot(
        adventureId: 1,
        branchId: 2,
        revision: revision,
        entities: {
          'character:alice': RuntimeEntityState(
            entityType: RuntimeEntityType.character,
            entityId: 'alice',
            overlay: overlay,
          ),
        },
      );

  test('comparison has stable FROM to TO direction and groups entities', () {
    final comparison = RuntimeStateComparison.fromSnapshots(
      snapshot(10, {'hp': 100, 'status': 'healthy'}),
      snapshot(20, {'hp': 30, 'new_flag': true}),
    );

    expect(comparison.fromRevision, 10);
    expect(comparison.toRevision, 20);
    expect(comparison.changeCount, 3);
    expect(comparison.diffs.map((diff) => diff.path),
        containsAll(<String>['hp', 'status', 'new_flag']));
    expect(
        comparison.diffs.firstWhere((diff) => diff.path == 'hp').before, 100);
    expect(comparison.diffs.firstWhere((diff) => diff.path == 'hp').after, 30);
  });

  test('same snapshots produce no changes', () {
    final comparison = RuntimeStateComparison.fromSnapshots(
      snapshot(4, {'hp': 1}),
      snapshot(4, {'hp': 1}),
    );
    expect(comparison.changeCount, 0);
    expect(comparison.entityGroups, isEmpty);
  });

  test('structured values use deep equality', () {
    final comparison = RuntimeStateComparison.fromSnapshots(
      snapshot(1, {
        'metadata': {
          'a': [1, 2]
        }
      }),
      snapshot(2, {
        'metadata': {
          'a': [1, 2]
        }
      }),
    );
    expect(comparison.changeCount, 0);
  });

  test('absent path remains distinct from an explicit null value', () {
    final comparison = RuntimeStateComparison.fromSnapshots(
      snapshot(1, const {}),
      snapshot(2, {'optional': null}),
    );
    expect(comparison.changeCount, 1);
    expect(comparison.diffs.single.isAdded, isTrue);
    expect(comparison.diffs.single.before, isNull);
    expect(comparison.diffs.single.after, isNull);
  });
}
