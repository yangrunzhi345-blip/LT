import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';

import '../../helpers/phase10_fixture.dart';

/// Phase 10 acceptance: the semantic index may only ever correspond to the
/// selected assembly revision. revision A → docs A, revision B → docs B, and
/// the two sets must never mix; the previous ready revision's documents stay
/// intact so an explicitly chosen old revision keeps a consistent index.
void main() {
  late Phase10Fixture fixture;

  setUp(() async {
    fixture = Phase10Fixture();
    await fixture.setUp(prefix: 'lt_phase10_index_');
  });

  tearDown(() => fixture.tearDown());

  test('revision A and revision B keep separate, complete index documents',
      () async {
    final resourceId = await fixture.createWorldview(
        'idx_wv',
        [
          ['版本A的世界规则：禁用魔法。'],
        ],
        summary: '概览A',
        confirmed: true);

    // Revision A → ready, docs A written.
    final first = await fixture.coordinator.prepare(resourceId);
    expect(first.record.state, ReadinessState.ready);
    final revisionA = first.record.assemblyRevisionId;

    // User edits → head B; re-prepare → docs B.
    await fixture.editResourceBody(resourceId, '版本B的世界规则：魔法 liberated。');
    final second = await fixture.coordinator.prepare(resourceId);
    expect(second.record.state, ReadinessState.ready);
    final revisionB = second.record.assemblyRevisionId;

    expect(revisionA, isNot(revisionB));

    final docsA = await fixture.readinessRepository
        .readIndexDocs(resourceId.value, revisionA);
    final docsB = await fixture.readinessRepository
        .readIndexDocs(resourceId.value, revisionB);

    // Both sets are non-empty and revision-bound.
    expect(docsA, isNotEmpty);
    expect(docsB, isNotEmpty);

    // No content mixing: A docs mention the A rule and not the B rule, and
    // vice versa.
    final contentA = docsA.map((doc) => doc.content).join('\n');
    final contentB = docsB.map((doc) => doc.content).join('\n');
    expect(contentA.contains('版本A'), isTrue);
    expect(contentA.contains('版本B'), isFalse);
    expect(contentB.contains('版本B'), isTrue);
    expect(contentB.contains('版本A'), isFalse);

    // Doc ids are revision-scoped, so A and B rows cannot collide.
    final idsA = docsA.map((doc) => doc.docId).toSet();
    final idsB = docsB.map((doc) => doc.docId).toSet();
    expect(idsA.intersection(idsB), isEmpty);

    // The previous ready revision's documents were not deleted when B was
    // published — an explicitly chosen old revision keeps its index.
    final docsAAfterB = await fixture.readinessRepository
        .readIndexDocs(resourceId.value, revisionA);
    expect(docsAAfterB.map((doc) => doc.docId), idsA);
  });
}
