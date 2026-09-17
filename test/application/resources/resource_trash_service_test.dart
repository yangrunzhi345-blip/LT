import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_service.dart';
import 'package:lt_dialogue/application/resources/resource_trash_repository.dart';
import 'package:lt_dialogue/application/resources/resource_trash_service.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_trash.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _resourceId = ResourceId('res_trash');
const _sectionA = SectionId('res_trash_sec_a');
const _sectionB = SectionId('res_trash_sec_b');
const _partA1 = PartId('res_trash_sec_a_part_1');
const _partA2 = PartId('res_trash_sec_a_part_2');
const _partB1 = PartId('res_trash_sec_b_part_1');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late ResourceTreeRepositoryImpl tree;
  late ResourceRevisionRepositoryImpl revisions;
  late RevisionCaptureEngine engine;
  late ResourceTrashRepositoryImpl trashRepository;
  late ResourceTrashService trash;
  late ResourceRevisionService revisionService;

  Future<Database> getDb() => DatabaseService.database;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_phase9_trash_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();

    tree = ResourceTreeRepositoryImpl(getDb: getDb);
    revisions = ResourceRevisionRepositoryImpl(getDb: getDb);
    engine = RevisionCaptureEngine(
      revisionRepository: revisions,
      treeBoundary: tree,
    );
    trashRepository = ResourceTrashRepositoryImpl(getDb: getDb);
    trash = ResourceTrashService(
      repository: trashRepository,
      treeBoundary: tree,
      captureEngine: engine,
      getDb: getDb,
    );
    revisionService = ResourceRevisionService(
      revisionRepository: revisions,
      captureEngine: engine,
      treeBoundary: tree,
      getDb: getDb,
      taskReset: PartGenerationTaskRepositoryImpl(getDb: getDb),
    );
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> seedTree() async {
    await tree.createResourceTree(
      const ResourceTreeDraft(
        id: _resourceId,
        type: ResourceType.worldview,
        name: '回收站测试资源',
        sections: [
          ResourceTreeSectionDraft(
            id: _sectionA,
            title: '第一章',
            parts: [
              ResourceTreePartDraft(
                id: _partA1,
                title: '开场',
                content: '第一章的正文一',
              ),
              ResourceTreePartDraft(
                id: _partA2,
                title: '发展',
                content: '第一章的正文二',
              ),
            ],
          ),
          ResourceTreeSectionDraft(
            id: _sectionB,
            title: '第二章',
            parts: [
              ResourceTreePartDraft(
                id: _partB1,
                title: '转折',
                content: '第二章的正文',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<String> tokenOf(NodeId id) async =>
      (await tree.readNodeState(id))!.updatedAt;

  Future<TrashDeleteResult> deleteNode(NodeId id) async => trash.deleteNode(
        id: id,
        expectedUpdatedAt: await tokenOf(id),
      );

  Future<List<String>> liveSectionIds() async =>
      (await tree.readSections(_resourceId)).map((s) => s.id.value).toList();

  Future<List<String>> livePartIds(SectionId sectionId) async =>
      (await tree.readParts(sectionId)).map((p) => p.id.value).toList();

  group('delete', () {
    test('a resource delete goes to the bin, not to oblivion', () async {
      await seedTree();

      final result = await deleteNode(_resourceId);

      expect(result.alreadyDeleted, isFalse);
      expect(result.entry.nodeKind, RevisionNodeKindRef.resource);
      expect(result.entry.originalTitle, '回收站测试资源');
      expect(await tree.findResource(_resourceId), isNull);
      expect(await trash.list(), hasLength(1));
      final db = await getDb();
      expect(
        (await db.query('resource_parts')).length,
        3,
        reason: 'the bodies stay in the tree behind deleted_at; nothing is '
            'physically removed by a delete',
      );
    });

    test('a section delete records its original place and order', () async {
      await seedTree();

      final result = await deleteNode(_sectionB);

      expect(result.entry.nodeKind, RevisionNodeKindRef.section);
      expect(result.entry.parentNodeId, _resourceId.value);
      expect(result.entry.originalSortOrder, 1);
      expect(await liveSectionIds(), <String>[_sectionA.value]);
    });

    test('a part delete keeps its section and its sibling', () async {
      await seedTree();

      await deleteNode(_partA1);

      expect(await livePartIds(_sectionA), <String>[_partA2.value]);
      expect(await liveSectionIds(), hasLength(2));
    });

    test('deleting a section hides all of its parts', () async {
      await seedTree();

      await deleteNode(_sectionA);

      expect(await liveSectionIds(), <String>[_sectionB.value]);
      expect(
        await tree.readParts(_sectionA),
        isEmpty,
        reason: 'a live tree must never expose children of a deleted parent',
      );
    });

    test('repeating a delete is idempotent', () async {
      await seedTree();
      final first = await deleteNode(_partA1);

      final second = await trash.deleteNode(
        id: _partA1,
        expectedUpdatedAt: await tokenOf(_partA1),
      );

      expect(second.alreadyDeleted, isTrue);
      expect(second.entry.trashId, first.entry.trashId);
      expect(await trash.list(), hasLength(1));
    });

    test('records a pre-delete revision so the content is recoverable',
        () async {
      await seedTree();

      final result = await deleteNode(_resourceId);

      expect(result.entry.revisionId, isNotEmpty);
      final state = await revisionService.readState(
        ResourceRevisionId(result.entry.revisionId),
      );
      expect(
        state.nodes.values
            .firstWhere((node) => node.nodeId == _partA1.value)
            .content,
        '第一章的正文一',
        reason: 'the delete boundary must preserve the last live state',
      );
    });

    test('a stale token refuses the delete', () async {
      await seedTree();

      await expectLater(
        trash.deleteNode(id: _partA1, expectedUpdatedAt: 'stale'),
        throwsA(isA<ResourceTreeConflictException>()),
      );

      expect(await livePartIds(_sectionA), hasLength(2));
      expect(await trash.list(), isEmpty);
      expect(
        await revisionService.countRevisions(_resourceId),
        0,
        reason: 'the whole delete rolls back, including its revision',
      );
    });

    test('deleting an unknown node is rejected', () async {
      await seedTree();
      await expectLater(
        trash.deleteNode(
          id: const PartId('part_missing'),
          expectedUpdatedAt: 'any',
        ),
        throwsA(isA<ResourceTrashNotFoundException>()),
      );
    });
  });

  group('restore', () {
    test('a resource comes back with its whole tree', () async {
      await seedTree();
      final deleted = await deleteNode(_resourceId);

      final result = await trash.restore(deleted.entry.trashId);

      expect(result.placement, TrashRestorePlacement.original);
      expect(result.entry.isRestored, isTrue);
      final restored = await tree.readTree(_resourceId);
      expect(restored, isNotNull);
      expect(restored!.sections, hasLength(2));
      expect(restored.parts, hasLength(3));
      expect(
        restored.parts.firstWhere((part) => part.id == _partA1).content,
        '第一章的正文一',
      );
    });

    test('a section returns to its original parent and sort order', () async {
      await seedTree();
      final deleted = await deleteNode(_sectionB);

      await trash.restore(deleted.entry.trashId);

      final sections = await tree.readSections(_resourceId);
      expect(sections.map((section) => section.id.value).toList(),
          <String>[_sectionA.value, _sectionB.value]);
      expect(
        sections.firstWhere((section) => section.id == _sectionB).sortOrder,
        1,
        reason: 'restoring must not reshuffle the sibling order',
      );
    });

    test('a part returns after its siblings were reordered', () async {
      await seedTree();
      final deleted = await deleteNode(_partA1);
      await tree.reorderParts(
        sectionId: _sectionA,
        orderedIds: <PartId>[_partA2],
      );

      final result = await trash.restore(deleted.entry.trashId);

      expect(result.placement, TrashRestorePlacement.original);
      final parts = await tree.readParts(_sectionA);
      expect(parts.map((part) => part.id.value).toSet(),
          <String>{_partA1.value, _partA2.value});
      expect(
        parts.firstWhere((part) => part.id == _partA1).content,
        '第一章的正文一',
      );
    });

    test('a restored section does not resurrect a separately deleted part',
        () async {
      await seedTree();
      await deleteNode(_partA1);
      final sectionDelete = await deleteNode(_sectionA);

      await trash.restore(sectionDelete.entry.trashId);

      expect(
        await livePartIds(_sectionA),
        <String>[_partA2.value],
        reason: 'only the nodes deleted with the section may come back',
      );
      expect(
        (await trash.list()).map((entry) => entry.nodeId),
        contains(_partA1.value),
        reason: 'the separately deleted part is still in the bin',
      );
    });

    test('restoring twice is idempotent', () async {
      await seedTree();
      final deleted = await deleteNode(_sectionB);

      final first = await trash.restore(deleted.entry.trashId);
      final second = await trash.restore(deleted.entry.trashId);

      expect(first.placement, TrashRestorePlacement.original);
      expect(second.isIdempotentRepeat, isTrue);
      expect(second.placement, TrashRestorePlacement.alreadyRestored);
      expect(
        await liveSectionIds(),
        <String>[_sectionA.value, _sectionB.value],
        reason: 'a repeated restore must not create a second section',
      );
      expect(await trash.list(), isEmpty);
    });

    test('a missing parent falls back to a new section under the root',
        () async {
      await seedTree();
      // Delete the Part first, then remove its Section row entirely — the shape
      // of an orphaned Part whose original parent no longer exists at all.
      final partDelete = await deleteNode(_partA1);
      final db = await getDb();
      await db.execute('PRAGMA foreign_keys = OFF');
      await db.delete(
        'resource_parts',
        where: 'section_id = ? AND id != ?',
        whereArgs: <Object?>[_sectionA.value, _partA1.value],
      );
      await db.delete(
        'resource_sections',
        where: 'id = ?',
        whereArgs: <Object?>[_sectionA.value],
      );
      await db.execute('PRAGMA foreign_keys = ON');

      final result = await trash.restore(partDelete.entry.trashId);

      expect(
        result.placement,
        TrashRestorePlacement.recreatedSectionUnderRoot,
        reason: 'the user must be told the content did not return home',
      );
      expect(result.createdSectionId, isNotNull);
      expect(result.userMessage.trim(), isNotEmpty);

      final sections = await tree.readSections(_resourceId);
      final fallback = sections
          .firstWhere((section) => section.id.value == result.createdSectionId);
      expect(fallback.title, contains('已恢复'));
      final parts = await tree.readParts(fallback.id);
      expect(parts.single.id, _partA1);
      expect(parts.single.content, '第一章的正文一');
    });

    test('a parent still in the bin also triggers the fallback', () async {
      await seedTree();
      final partDelete = await deleteNode(_partA1);
      await deleteNode(_sectionA);

      final result = await trash.restore(partDelete.entry.trashId);

      expect(
        result.placement,
        TrashRestorePlacement.recreatedSectionUnderRoot,
        reason: 'being inside a deleted section would leave the part invisible',
      );
      final sections = await tree.readSections(_resourceId);
      final fallback = sections
          .firstWhere((section) => section.id.value == result.createdSectionId);
      expect((await tree.readParts(fallback.id)).single.id, _partA1);
    });

    test(
        'a section whose resource is gone fails explicitly and keeps the entry',
        () async {
      await seedTree();
      final sectionDelete = await deleteNode(_sectionB);
      final db = await getDb();
      await db.delete('resource_parts');
      await db.delete('resource_sections');
      await db.delete('resources');

      await expectLater(
        trash.restore(sectionDelete.entry.trashId),
        throwsA(isA<ResourceTrashException>()),
      );

      final entries = await trash.list();
      expect(entries, hasLength(1));
      expect(
        entries.single.isRestored,
        isFalse,
        reason: 'an unresolvable restore must not be recorded as done, and '
            'must not silently drop the record either',
      );
    });

    test('restoring an unknown entry is rejected', () async {
      await seedTree();
      await expectLater(
        trash.restore('trash_missing'),
        throwsA(isA<ResourceTrashNotFoundException>()),
      );
    });

    test('a Part whose own row is gone fails instead of pretending', () async {
      await seedTree();
      final partDelete = await deleteNode(_partA1);
      final db = await getDb();
      await db.delete(
        'resource_parts',
        where: 'id = ?',
        whereArgs: <Object?>[_partA1.value],
      );

      await expectLater(
        trash.restore(partDelete.entry.trashId),
        throwsA(isA<ResourceTrashNotFoundException>()),
      );
      // The difference from the fallback case: there is no content left to
      // place, so the honest answer is a failure, and the entry stays for the
      // user to see rather than being consumed.
      expect((await trash.list()).single.isRestored, isFalse);
    });

    test('restore records revisions so the undo is itself undoable', () async {
      await seedTree();
      final deleted = await deleteNode(_sectionB);
      final before = await revisionService.countRevisions(_resourceId);

      await trash.restore(deleted.entry.trashId);

      expect(
        await revisionService.countRevisions(_resourceId),
        greaterThan(before),
      );
      final state = await revisionService.readState(
        (await revisionService.latestHead(_resourceId))!.revisionId,
      );
      expect(
        state.nodes.values
            .where((node) => node.nodeId == _partB1.value)
            .single
            .content,
        '第二章的正文',
      );
    });
  });

  group('permanent delete', () {
    test('is a separate operation that physically removes the node', () async {
      await seedTree();
      final deleted = await deleteNode(_sectionB);

      final result = await trash.permanentDelete(deleted.entry.trashId);

      expect(result.deletedNodeIds, <String>[_sectionB.value]);
      final db = await getDb();
      expect(
        await db.query(
          'resource_sections',
          where: 'id = ?',
          whereArgs: <Object?>[_sectionB.value],
        ),
        isEmpty,
        reason: 'permanent delete is the only path that removes rows',
      );
      expect(
        await db.query(
          'resource_parts',
          where: 'section_id = ?',
          whereArgs: <Object?>[_sectionB.value],
        ),
        isEmpty,
      );
      expect(await trash.list(), isEmpty);
    });

    test('a live node is never permanently deleted', () async {
      await seedTree();
      final deleted = await deleteNode(_sectionB);
      // Put it back, then try to purge the stale bin row.
      await trash.restore(deleted.entry.trashId);

      final result = await trash.permanentDelete(deleted.entry.trashId);

      expect(result.alreadyGone, isTrue);
      final db = await getDb();
      expect(
        await db.query(
          'resource_sections',
          where: 'id = ?',
          whereArgs: <Object?>[_sectionB.value],
        ),
        isNotEmpty,
        reason: 'a stale bin row must never be able to delete live data',
      );
    });

    test('repeating a permanent delete is idempotent', () async {
      await seedTree();
      final deleted = await deleteNode(_partA1);

      await trash.permanentDelete(deleted.entry.trashId);
      final second = await trash.permanentDelete(deleted.entry.trashId);

      expect(second.alreadyGone, isTrue);
    });

    test('an unknown entry is a no-op, not an error', () async {
      await seedTree();
      final result = await trash.permanentDelete('trash_missing');
      expect(result.alreadyGone, isTrue);
    });
  });

  group('retention cleanup', () {
    test('never purges an entry inside its retention window', () async {
      await seedTree();
      await deleteNode(_sectionB);

      final purged = await trash.purgeExpired();

      expect(purged, 0);
      expect(await trash.list(), hasLength(1));
      final db = await getDb();
      expect(
        await db.query(
          'resource_sections',
          where: 'id = ?',
          whereArgs: <Object?>[_sectionB.value],
        ),
        isNotEmpty,
        reason: 'a cleanup pass must not shorten the promised recovery window',
      );
    });

    test('purges only entries whose deadline has passed', () async {
      await seedTree();
      final deleted = await deleteNode(_sectionB);
      final db = await getDb();
      final fresh = await deleteNode(_partA1);
      await db.update(
        'resource_trash',
        <String, Object?>{'expires_at': '2020-01-01T00:00:00.000'},
        where: 'trash_id = ?',
        whereArgs: <Object?>[deleted.entry.trashId],
      );

      final purged = await trash.purgeExpired();

      expect(purged, 1);
      final remaining = await trash.list();
      expect(
        remaining.map((entry) => entry.trashId).toList(),
        <String>[fresh.entry.trashId],
      );
      expect(
        await db.query(
          'resource_sections',
          where: 'id = ?',
          whereArgs: <Object?>[_sectionB.value],
        ),
        isEmpty,
      );
    });

    test('does not purge an already restored entry', () async {
      await seedTree();
      final deleted = await deleteNode(_sectionB);
      final db = await getDb();
      await db.update(
        'resource_trash',
        <String, Object?>{'expires_at': '2020-01-01T00:00:00.000'},
        where: 'trash_id = ?',
        whereArgs: <Object?>[deleted.entry.trashId],
      );
      await trash.restore(deleted.entry.trashId);

      final purged = await trash.purgeExpired();

      expect(purged, 0);
      expect(
        await db.query(
          'resource_sections',
          where: 'id = ?',
          whereArgs: <Object?>[_sectionB.value],
        ),
        isNotEmpty,
        reason: 'a restored node is live and must never be purged',
      );
    });
  });

  group('queries', () {
    test('lists newest delete first and filters by resource', () async {
      await seedTree();
      await deleteNode(_partA1);
      await deleteNode(_partA2);

      final entries = await trash.list();

      expect(entries, hasLength(2));
      expect(
        entries.first.deletedAtToken.compareTo(entries.last.deletedAtToken),
        greaterThanOrEqualTo(0),
      );
      expect(await trash.countActive(_resourceId), 2);
      expect(
        await trash.list(resourceId: const ResourceId('res_other')),
        isEmpty,
      );
    });

    test('includes restored entries only when asked', () async {
      await seedTree();
      final deleted = await deleteNode(_partA1);
      await trash.restore(deleted.entry.trashId);

      expect(await trash.list(), isEmpty);
      expect(await trash.list(includeRestored: true), hasLength(1));
    });
  });
}
