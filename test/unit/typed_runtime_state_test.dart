import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/typed_runtime_state.dart';
import 'package:lt_dialogue/services/runtime_state_validator.dart';

void main() {
  test('registry enforces typed paths and entity compatibility', () {
    final hp = RuntimeStateSchemaRegistry.find('hp')!;
    expect(hp.accepts(RuntimeEntityType.character, 12), isTrue);
    expect(hp.accepts(RuntimeEntityType.character, '12'), isFalse);
    expect(hp.accepts(RuntimeEntityType.faction, 12), isFalse);
    expect(
        RuntimeStateSchemaRegistry.find('control')!.accepts(
          RuntimeEntityType.location,
          'north',
        ),
        isTrue);
  });

  test('validator accepts typed world changes and rejects invalid values', () {
    const validator = RuntimeStateValidator();
    final accepted = validator.accept(const [
      RuntimeStateChangeProposal(
        entityType: RuntimeEntityType.location,
        entityId: 'ruins',
        changeKind: RuntimeChangeKind.primary,
        operation: RuntimeChangeOperation.set,
        path: 'condition',
        value: 'flooded',
        reason: 'storm',
      ),
      RuntimeStateChangeProposal(
        entityType: RuntimeEntityType.faction,
        entityId: 'guild',
        changeKind: RuntimeChangeKind.primary,
        operation: RuntimeChangeOperation.set,
        path: 'influence',
        value: 'high',
        reason: 'invalid type',
      ),
    ]);
    expect(accepted, hasLength(1));
    expect(accepted.single.path, 'condition');
  });

  test('event serialization is locale neutral and versioned', () {
    final event = RuntimeStateEvent(
      eventId: 'commit-event-0',
      eventTypeId: 'location_state_changed',
      adventureId: 1,
      branchId: 2,
      commitId: 'runtime-request',
      revision: 3,
      occurredAt: DateTime.utc(2026, 1, 1),
      source: RuntimeEventSource.aiProposal,
      importance: RuntimeEventImportance.normal,
      visibility: RuntimeEventVisibility.user,
      parameters: const {'path': 'condition', 'after': 'flooded'},
    );
    expect(event.toJson()['schema_version'], 1);
    expect(event.toJson()['event_type_id'], 'location_state_changed');
    expect(event.encode(), contains('location_state_changed'));
  });
}
