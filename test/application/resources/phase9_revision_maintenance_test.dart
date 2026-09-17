import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/resource_revision_maintenance.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_revision.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/phase9_recovery_fixtures.dart';

/// P9-M3 / P9-M7: the retention pass must have a production trigger, and it
/// must cover the assembly chain as well as the latest-head chain without ever
/// deleting history something still references.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late Phase9RecoveryFixture phase9;

  const resourceId = ResourceId('res_maint');
  const sectionId = SectionId('res_maint_sec');
  const partA = PartId('res_maint_sec_a');
  const partB = PartId('res_maint_sec_b');

  Future<Database> getDb() => DatabaseService.database;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_p9_maint_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    // Zero retention so "old enough to prune" holds for revisions created a
    // moment ago; the protection rules must still apply.
    phase9 = Phase9RecoveryFixture(
      getDb: getDb,
      retention: Duration.zero,
    );
    await phase9.tree.createResourceTree(
      const ResourceTreeDraft(
        id: resourceId,
        type: ResourceType.worldview,
        name: '维护测试资源',
        sections: <ResourceTreeSectionDraft>[
          ResourceTreeSectionDraft(
            id: sectionId,
            title: '第一章',
            parts: <ResourceTreePartDraft>[
              ResourceTreePartDraft(id: partA, title: 'A', content: 'A 正文'),
              ResourceTreePartDraft(id: partB, title: 'B', content: 'B 正文'),
            ],
          ),
        ],
      ),
    );
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> editPart(PartId partId, String content) async {
    final state = await phase9.tree.readNodeState(partId);
    await phase9.tree.updatePart(
      id: partId,
      expectedUpdatedAt: state!.updatedAt,
      content: content,
    );
  }

  Future<int> countKind(String kind) async {
    final db = await getDb();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM resource_revisions '
      'WHERE resource_id = ? AND kind = ?',
      <Object?>[resourceId.value, kind],
    );
    return (rows.first['c'] as num).toInt();
  }

  group('production trigger (P9-M3)', () {
    test('the first pass runs and an immediate second one is skipped',
        () async {
      final maintenance = ResourceRevisionMaintenance(
        revisionService: phase9.revisionService,
      );
      final now = DateTime(2026, 9, 17, 12);

      final first = await maintenance.runIfDue(now: now);
      expect(first, isNotNull, reason: 'startup must actually run a pass');
      expect(maintenance.lastError, isEmpty);

      final second = await maintenance.runIfDue(
        now: now.add(const Duration(minutes: 1)),
      );
      expect(
        second,
        isNull,
        reason: 'a pass per interval, not per trigger',
      );
    });

    test('a due pass runs again once the interval elapsed', () async {
      final maintenance = ResourceRevisionMaintenance(
        revisionService: phase9.revisionService,
        minInterval: const Duration(hours: 1),
      );
      final now = DateTime(2026, 9, 17, 12);

      expect(await maintenance.runIfDue(now: now), isNotNull);
      expect(
        await maintenance.runIfDue(now: now.add(const Duration(hours: 2))),
        isNotNull,
      );
    });

    test('a zero interval always runs', () async {
      final maintenance = ResourceRevisionMaintenance(
        revisionService: phase9.revisionService,
        minInterval: Duration.zero,
      );
      final now = DateTime(2026, 9, 17, 12);
      expect(maintenance.isDue(now), isTrue);
      expect(await maintenance.runIfDue(now: now), isNotNull);
      expect(maintenance.isDue(now), isTrue);
    });

    test('a failing pass is reported instead of thrown', () async {
      final maintenance = ResourceRevisionMaintenance(
        revisionService: phase9.revisionService,
      );
      await phase9.revisionService.captureRevision(
        resourceId,
        cause: RevisionCause.migration,
      );
      await editPart(partA, 'A 第二版');
      await phase9.revisionService.captureRevision(
        resourceId,
        cause: RevisionCause.manualSave,
      );
      // Break the chain behind the service's back by dangling the head's parent.
      final db = await getDb();
      await db.update(
        'resource_revisions',
        <String, Object?>{'parent_revision_id': 'rev_missing'},
        where: 'resource_id = ? AND is_head = 1',
        whereArgs: <Object?>[resourceId.value],
      );

      final report = await maintenance.runIfDue();

      expect(report, isNotNull);
      expect(report!.skippedResources, isNotEmpty);
      expect(
        await countKind('latestHead'),
        2,
        reason: 'a broken chain is reported, never truncated',
      );
    });
  });

  group('assembly chain coverage (P9-M7)', () {
    test('the assembly chain is pruned too, and its head survives', () async {
      final first = await phase9.revisionService.captureRevision(
        resourceId,
        cause: RevisionCause.migration,
      );
      await phase9.revisionService.publishAssemblyRevision(
        resourceId: resourceId,
        revisionId: first.revision!.revisionId,
      );
      await editPart(partA, 'A 第二版');
      final second = await phase9.revisionService.captureRevision(
        resourceId,
        cause: RevisionCause.manualSave,
      );
      await phase9.revisionService.publishAssemblyRevision(
        resourceId: resourceId,
        revisionId: second.revision!.revisionId,
      );

      expect(await countKind('assembly'), 2);
      final latestHeadBefore =
          (await phase9.revisionService.latestHead(resourceId))!;
      final assemblyBefore =
          (await phase9.revisionService.select(resourceId)).assemblyRevision!;

      final report = await phase9.revisionService.pruneRevisions(
        resourceId: resourceId,
      );

      expect(
        report.deletedRevisions,
        greaterThan(0),
        reason: 'both chains must actually shrink',
      );
      expect(
        report.rerootedRevisions,
        greaterThanOrEqualTo(2),
        reason: 'one re-root per pruned chain keeps replay possible',
      );
      expect(report.skippedResources, isEmpty);

      expect(await countKind('latestHead'), 1);
      expect(
        await countKind('assembly'),
        1,
        reason: 'the assembly chain must not grow forever',
      );

      final latestHeadAfter =
          (await phase9.revisionService.latestHead(resourceId))!;
      expect(latestHeadAfter.revisionId, latestHeadBefore.revisionId);
      final assemblyAfter =
          (await phase9.revisionService.select(resourceId)).assemblyRevision!;
      expect(assemblyAfter.revisionId, assemblyBefore.revisionId);

      // Both surviving heads still replay to a real state.
      final headState = await phase9.revisionService.readState(
        latestHeadAfter.revisionId,
      );
      expect(headState.nodes[partA.value]?.content, 'A 第二版');
      final assemblyState = await phase9.revisionService.readState(
        assemblyAfter.revisionId,
      );
      expect(assemblyState.nodes[partA.value]?.content, 'A 第二版');
      expect(assemblyState.nodes.containsKey(partB.value), isTrue);
    });

    test('a bin-referenced revision survives an aggressive prune', () async {
      await phase9.revisionService.captureRevision(
        resourceId,
        cause: RevisionCause.migration,
      );
      final deleted = await phase9.trash.deleteNode(
        id: partB,
        expectedUpdatedAt: (await phase9.tree.readNodeState(partB))!.updatedAt,
      );
      expect(deleted.entry.revisionId, isNotEmpty);

      final report = await phase9.revisionService.pruneRevisions(
        resourceId: resourceId,
      );

      expect(
        report.protectedRevisions.map((revision) => revision.value).toList(),
        contains(deleted.entry.revisionId),
      );
      final db = await getDb();
      expect(
        await db.query(
          'resource_revisions',
          where: 'revision_id = ?',
          whereArgs: <Object?>[deleted.entry.revisionId],
        ),
        isNotEmpty,
        reason: 'an unresolved bin entry still points at it',
      );
    });

    test('the head of the other kind survives either pass', () async {
      final captured = await phase9.revisionService.captureRevision(
        resourceId,
        cause: RevisionCause.migration,
      );
      await phase9.revisionService.publishAssemblyRevision(
        resourceId: resourceId,
        revisionId: captured.revision!.revisionId,
      );

      await phase9.revisionService.pruneRevisions(resourceId: resourceId);

      expect(
        await phase9.revisionService.latestHead(resourceId),
        isNotNull,
      );
      final selection = await phase9.revisionService.select(resourceId);
      expect(selection.assemblyRevision, isNotNull);
      expect(selection.readiness, ReadinessState.ready);
    });

    test('an empty resource is left completely alone', () async {
      final report = await phase9.revisionService.pruneRevisions(
        resourceId: const ResourceId('res_unknown'),
      );
      expect(report.deletedRevisions, 0);
      expect(report.rerootedRevisions, 0);
      expect(report.skippedResources, isEmpty);
    });
  });
}
