import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/assembly_readiness_repository.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';

import '../../helpers/phase10_fixture.dart';

void main() {
  late Phase10Fixture fixture;

  setUp(() async {
    fixture = Phase10Fixture();
    await fixture.setUp(prefix: 'lt_phase10_coord_');
  });

  tearDown(() => fixture.tearDown());

  group('NORMAL head', () {
    test('prepare reaches ready and publishes an assembly revision', () async {
      final resourceId = await fixture.createWorldview(
          'res_c1',
          [
            ['正文一'],
          ],
          summary: '概览文本');

      final outcome = await fixture.coordinator.prepare(resourceId);

      expect(outcome.record.state, ReadinessState.ready);
      expect(outcome.published, isTrue);
      expect(outcome.awaitedCompression, isFalse);
      expect(outcome.record.targetContentHash, isNotEmpty);
      expect(outcome.record.assemblyRevisionId, isNotEmpty);
      expect(
          outcome.record.assemblyContentHash, outcome.record.targetContentHash);

      final assembly = await fixture.revisionRepository.readHead(
        resourceId,
        ResourceRevisionKind.assembly,
      );
      expect(assembly, isNotNull);
      expect(assembly!.contentHash, outcome.record.assemblyContentHash);

      // The index documents were written and bound to the assembly revision.
      final docs = await fixture.readinessRepository.readIndexDocs(
        resourceId.value,
        assembly.revisionId.value,
      );
      expect(docs, isNotEmpty);
    });

    test('re-preparing an unchanged head stays ready (idempotent)', () async {
      final resourceId = await fixture.createWorldview('res_c2', [
        ['正文'],
      ]);
      await fixture.coordinator.prepare(resourceId);
      final second = await fixture.coordinator.prepare(resourceId);
      expect(second.record.state, ReadinessState.ready);
    });
  });

  group('OVERFLOW head', () {
    test('stays preparing with the compression message and never readies',
        () async {
      // Worldview absolute budget is 60000 characters.
      final bigBody = '超' * 61000;
      final resourceId = await fixture.createWorldview('res_c3', [
        [bigBody],
      ]);

      final outcome = await fixture.coordinator.prepare(resourceId);

      expect(outcome.awaitedCompression, isTrue);
      expect(outcome.published, isFalse);
      expect(outcome.record.state, ReadinessState.preparing);
      expect(outcome.record.failureReason, isEmpty);

      final assembly = await fixture.revisionRepository.readHead(
        resourceId,
        ResourceRevisionKind.assembly,
      );
      expect(assembly, isNull);
    });
  });

  group('head changes mid-flight', () {
    test('a result for an old head becomes stale, never ready', () async {
      final resourceId = await fixture.createWorldview(
          'res_c4',
          [
            ['旧正文'],
          ],
          summary: '概览');
      final coordinator = fixture.coordinator;

      coordinator.debugInterleaveHook = () async {
        // The user edits the resource while the build is in flight.
        await fixture.editResourceBody(resourceId, '编辑后的新正文');
      };

      final outcome = await coordinator.prepare(resourceId);

      expect(outcome.superseded, isTrue);
      expect(outcome.record.state, ReadinessState.stale);
      expect(outcome.published, isFalse);

      final assembly = await fixture.revisionRepository.readHead(
        resourceId,
        ResourceRevisionKind.assembly,
      );
      // The old run must not have published an assembly for the *new* head.
      expect(assembly, isNull);
    });

    test('a late run drops its result when a newer run owns the row', () async {
      final resourceId = await fixture.createWorldview(
          'res_c5',
          [
            ['版本一'],
          ],
          summary: '概览');

      final slow = fixture.coordinator;
      final fast = fixture.secondCoordinator();

      slow.debugInterleaveHook = () async {
        // While the slow run is between build and commit, the user edits and
        // a second coordinator completes a full preparation for head B.
        await fixture.editResourceBody(resourceId, '版本二');
        await fast.prepare(resourceId);
      };

      final slowOutcome = await slow.prepare(resourceId);

      // The fast run legitimately reached ready for head B.
      final record = await fixture.readinessRepository.read(resourceId.value);
      expect(record, isNotNull);
      expect(record!.state, ReadinessState.ready);
      // The slow run must NOT have overwritten that state with its own stale
      // result for head A.
      expect(slowOutcome.record.state, ReadinessState.ready);
      expect(slowOutcome.record.targetContentHash, record.targetContentHash);

      final assembly = await fixture.revisionRepository.readHead(
        resourceId,
        ResourceRevisionKind.assembly,
      );
      expect(assembly, isNotNull);
      // The published assembly is head B's content, not head A's.
      expect(assembly!.contentHash, record.assemblyContentHash);
    });
  });

  group('stale / refresh / recovery', () {
    test('ready goes stale after the resource is edited (ready → stale)',
        () async {
      final resourceId = await fixture.createWorldview(
          'res_c6',
          [
            ['初版'],
          ],
          summary: '概览');
      await fixture.coordinator.prepare(resourceId);
      final before = await fixture.readinessRepository.read(resourceId.value);
      expect(before!.state, ReadinessState.ready);

      await fixture.editResourceBody(resourceId, '修改后的内容');

      final after = await fixture.coordinator.refresh(resourceId);
      expect(after!.state, ReadinessState.stale);
      // The old ready assembly is preserved for explicit user choice.
      expect(after.assemblyRevisionId, isNotEmpty);
    });

    test('stale resource re-prepares back to ready (stale → preparing → ready)',
        () async {
      final resourceId = await fixture.createWorldview(
          'res_c7',
          [
            ['初版'],
          ],
          summary: '概览');
      await fixture.coordinator.prepare(resourceId);
      await fixture.editResourceBody(resourceId, '修改后的内容');
      await fixture.coordinator.refresh(resourceId);

      final outcome = await fixture.coordinator.prepare(resourceId);
      expect(outcome.record.state, ReadinessState.ready);
      final head = await fixture.latestHeadRevision(resourceId);
      expect(outcome.record.assemblyContentHash, head.contentHash);
    });

    test('failed retries through preparing (failed → preparing → ready)',
        () async {
      final resourceId = await fixture.createWorldview(
          'res_c8',
          [
            ['正文'],
          ],
          summary: '概览');

      // Simulate a failure: intercept the builder by an interleave hook that
      // throws once.
      final coordinator = fixture.coordinator;
      coordinator.debugInterleaveHook = () async {
        throw const ResourceContractException('注入的构建失败');
      };
      final failed = await coordinator.prepare(resourceId);
      expect(failed.record.state, ReadinessState.failed);
      expect(failed.record.failureReason, contains('注入的构建失败'));

      // Remove the injected fault; the retry must succeed.
      coordinator.debugInterleaveHook = null;
      final retried = await coordinator.prepare(resourceId);
      expect(retried.record.state, ReadinessState.ready);
    });

    test('recoverInterrupted marks orphaned preparing rows failed', () async {
      final resourceId = await fixture.createWorldview(
          'res_c9',
          [
            ['正文'],
          ],
          summary: '概览');
      // Simulate a process that died mid-prepare: write a preparing row.
      final repo = fixture.readinessRepository;
      final db = fixture.db;
      await db.transaction((txn) async {
        await repo.writeInTransaction(
          txn,
          const AssemblyReadinessRecord(
            resourceId: 'res_c9',
            state: ReadinessState.preparing,
            attemptToken: 'attempt_dead_process',
          ),
        );
      });
      // Use a fresh coordinator: the dead owner is not in flight.
      final recovered = await fixture.coordinator.recoverInterrupted();
      expect(recovered, 1);
      final record = await repo.read(resourceId.value);
      expect(record!.state, ReadinessState.failed);
      expect(record.failureReason, contains('中断'));
    });
  });
}
