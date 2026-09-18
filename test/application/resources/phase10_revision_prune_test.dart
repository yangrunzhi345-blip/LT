import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/assembly_readiness_repository.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';

import '../../helpers/phase10_fixture.dart';

void main() {
  late Phase10Fixture fixture;
  late ResourceId resourceId;
  late AssemblyReadinessRecord first;
  late AssemblyReadinessRecord second;

  setUp(() async {
    fixture = Phase10Fixture();
    await fixture.setUp(prefix: 'lt_phase10_prune_');
    resourceId = await fixture.createWorldview(
        'res_prune',
        [
          ['ALPHA canon'],
        ],
        confirmed: true);
    first = (await fixture.coordinator.prepare(resourceId)).record;
    await fixture.editResourceBody(resourceId, 'BETA canon');
    second = (await fixture.coordinator.prepare(resourceId)).record;
  });

  tearDown(() => fixture.tearDown());

  Future<void> prune({int maxRevisions = 0}) async {
    await fixture.revisionService.pruneRevisions(
      resourceId: resourceId,
      now: DateTime.now().add(const Duration(days: 365)),
      maxRevisions: maxRevisions,
    );
  }

  Future<void> expectDocs(String revisionId, {required bool present}) async {
    expect(
      await fixture.readinessRepository.readIndexDocs(
        resourceId.value,
        revisionId,
      ),
      present ? isNotEmpty : isEmpty,
    );
  }

  group('ResourceRevisionService assembly retention', () {
    test('should delete pruned index documents and retain replayable head',
        () async {
      await expectDocs(first.assemblyRevisionId, present: true);
      await prune();
      await expectDocs(first.assemblyRevisionId, present: false);
      await expectDocs(second.assemblyRevisionId, present: true);
      final state = await fixture.revisionService.readState(
        ResourceRevisionId(second.assemblyRevisionId),
      );
      expect(state.nodes.values.map((node) => node.content),
          contains('BETA canon'));
      await prune();
      await expectDocs(second.assemblyRevisionId, present: true);
    });

    test('should preserve readiness pointers even with a one-revision limit',
        () async {
      await fixture.db.update(
          'resource_assembly_readiness',
          {
            'target_revision_id': first.targetRevisionId,
            'assembly_revision_id': first.assemblyRevisionId,
          },
          where: 'resource_id = ?',
          whereArgs: [resourceId.value]);
      await prune(maxRevisions: 1);
      await expectDocs(first.assemblyRevisionId, present: true);
      for (final id in [first.targetRevisionId, first.assemblyRevisionId]) {
        final state = await fixture.revisionService.readState(
          ResourceRevisionId(id),
        );
        expect(state.nodes.values.map((node) => node.content),
            contains('ALPHA canon'));
      }
      await fixture.db.update(
          'resource_assembly_readiness',
          {
            'target_revision_id': second.targetRevisionId,
            'assembly_revision_id': second.assemblyRevisionId,
          },
          where: 'resource_id = ?',
          whereArgs: [resourceId.value]);
      await prune();
      await expectDocs(first.assemblyRevisionId, present: false);
    });

    test('should preserve trash-referenced documents until reference release',
        () async {
      await fixture.db.insert('resource_trash', {
        'trash_id': 'trash_prune',
        'resource_id': resourceId.value,
        'node_id': 'removed_part',
        'node_kind': 'part',
        'revision_id': first.assemblyRevisionId,
        'deleted_at': '2020-01-01',
        'expires_at': '2020-02-01',
      });
      await prune(maxRevisions: 1);
      await expectDocs(first.assemblyRevisionId, present: true);
      await fixture.db.update(
          'resource_trash',
          {
            'restored_at': DateTime.now().toIso8601String(),
          },
          where: 'trash_id = ?',
          whereArgs: ['trash_prune']);
      await prune();
      await expectDocs(first.assemblyRevisionId, present: false);
    });

    test(
        'should roll back assembly revision deletion if document cleanup fails',
        () async {
      await fixture.db.execute('''
        CREATE TRIGGER reject_entry_delete
        BEFORE DELETE ON resource_assembly_entries
        BEGIN SELECT RAISE(ABORT, 'test cleanup failure'); END
      ''');
      await expectLater(prune(), throwsA(isA<Exception>()));
      await expectDocs(first.assemblyRevisionId, present: true);
      final state = await fixture.revisionService.readState(
        ResourceRevisionId(first.assemblyRevisionId),
      );
      expect(state.nodes.values.map((node) => node.content),
          contains('ALPHA canon'));
      await fixture.db.execute('DROP TRIGGER reject_entry_delete');
      await prune();
      await expectDocs(first.assemblyRevisionId, present: false);
    });

    test(
        'should sweep legacy orphans even when their resource has no revisions',
        () async {
      await fixture.db.insert('resource_assembly_entries', {
        'entry_id': 'orphan_entry',
        'resource_id': 'missing_resource',
        'revision_id': 'missing_revision',
        'revision_content_hash': 'hash',
        'content': 'orphan text',
        'created_at': '2020-01-01',
      });
      await fixture.revisionService.pruneRevisions();
      expect(
        await fixture.db.query('resource_assembly_entries',
            where: 'entry_id = ?', whereArgs: ['orphan_entry']),
        isEmpty,
      );
      await expectDocs(first.assemblyRevisionId, present: true);
      await expectDocs(second.assemblyRevisionId, present: true);
    });
  });
}
