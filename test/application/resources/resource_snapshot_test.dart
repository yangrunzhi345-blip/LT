import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/resource_snapshot.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';

void main() {
  test('creates an initial snapshot and preserves metadata', () {
    final snapshot = ResourceSnapshot.initial(
      resourceId: const ResourceId('r'),
      revisionId: const ResourceRevisionId('rev-1'),
      createdAt: '2026-01-01',
      metadata: const {'reason': 'created'},
    );
    expect(snapshot.source, 'initial');
    expect(snapshot.metadata['reason'], 'created');
  });

  test('revision identity remains stable across metadata changes', () {
    final snapshot = ResourceSnapshot.initial(
      resourceId: const ResourceId('r'),
      revisionId: const ResourceRevisionId('rev-1'),
      createdAt: '2026-01-01',
    );
    expect(snapshot.copyWith(source: 'edit').revisionId, snapshot.revisionId);
  });

  test('latest returns the newest snapshot', () {
    final snapshots = [
      ResourceSnapshot.initial(
        resourceId: const ResourceId('r'),
        revisionId: const ResourceRevisionId('old'),
        createdAt: '2026-01-01',
      ),
      ResourceSnapshot.initial(
        resourceId: const ResourceId('r'),
        revisionId: const ResourceRevisionId('new'),
        createdAt: '2026-02-01',
      ),
    ];
    expect(ResourceSnapshot.latest(snapshots)?.revisionId.value, 'new');
  });
}
