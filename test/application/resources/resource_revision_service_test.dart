import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_service.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_revision.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _resourceId = ResourceId('res_rev');
const _sectionId = SectionId('res_rev_sec_1');
const _partA = PartId('res_rev_sec_1_part_a');
const _partB = PartId('res_rev_sec_1_part_b');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late ResourceTreeRepositoryImpl tree;
  late ResourceRevisionRepositoryImpl revisions;
  late RevisionCaptureEngine engine;
  late ResourceRevisionService service;
  late PartGenerationTaskRepositoryImpl tasks;

  Future<Database> getDb() => DatabaseService.database;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_phase9_rev_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();

    tree = ResourceTreeRepositoryImpl(getDb: getDb);
    revisions = ResourceRevisionRepositoryImpl(getDb: getDb);
    engine = RevisionCaptureEngine(
      revisionRepository: revisions,
      treeBoundary: tree,
    );
    tasks = PartGenerationTaskRepositoryImpl(
      getDb: getDb,
      revisionBoundary: engine,
    );
    service = ResourceRevisionService(
      revisionRepository: revisions,
      captureEngine: engine,
      treeBoundary: tree,
      getDb: getDb,
      taskReset: tasks,
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
        name: '版本测试资源',
        sections: [
          ResourceTreeSectionDraft(
            id: _sectionId,
            title: '第一章',
            parts: [
              ResourceTreePartDraft(
                id: _partA,
                title: '开场',
                content: '第一版正文',
              ),
              ResourceTreePartDraft(
                id: _partB,
                title: '发展',
                content: '未改动的正文',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> seedTask({
    String partId = 'res_rev_sec_1_part_a',
    String taskId = 'task_rev_a',
    String status = 'completed',
  }) async {
    final db = await getDb();
    await db.insert('resource_generation_tasks', {
      'task_id': taskId,
      'blueprint_id': 'bp_rev',
      'resource_id': _resourceId.value,
      'section_id': _sectionId.value,
      'part_id': partId,
      'prompt_goal': '写开场',
      'estimated_length': 800,
      'dependencies_json': '[]',
      'status': status,
      'sort_order': 0,
      'current_attempt_id': '',
      'error_message': '',
      'created_at': '2026-09-17T00:00:00.000',
      'updated_at': '2026-09-17T00:00:00.000',
    });
  }

  Future<String> liveContent(PartId partId) async {
    final state = await tree.readNodeState(partId);
    expect(state, isNotNull);
    final db = await getDb();
    final rows = await db.query(
      'resource_parts',
      columns: const ['content'],
      where: 'id = ?',
      whereArgs: <Object?>[partId.value],
      limit: 1,
    );
    return rows.single['content']!.toString();
  }

  Future<String> liveToken(PartId partId) async {
    final state = await tree.readNodeState(partId);
    return state!.updatedAt;
  }

  Future<void> editPart(PartId partId, String content) async {
    await tree.updatePart(
      id: partId,
      expectedUpdatedAt: await liveToken(partId),
      content: content,
    );
  }

  group('capture', () {
    test('the first revision is a self-contained root', () async {
      await seedTree();

      final report = await service.captureRevision(
        _resourceId,
        cause: RevisionCause.migration,
      );

      expect(report.captured, isTrue);
      expect(report.wasNoOp, isFalse);
      final revision = report.revision!;
      expect(
        revision.parentRevisionId,
        isNull,
        reason: 'the root has nothing to replay from, so it must be complete',
      );
      expect(revision.cause, RevisionCause.migration);
      expect(revision.isHead, isTrue);
      expect(revision.nodeCount, 4, reason: '1 resource + 1 section + 2 parts');

      final state = await service.readState(revision.revisionId);
      expect(state.nodes.length, 4);
      expect(
        state.nodes.values
            .firstWhere((node) => node.nodeId == _partA.value)
            .content,
        '第一版正文',
      );
    });

    test('a second capture with no change writes nothing', () async {
      await seedTree();
      final first = await service.captureRevision(
        _resourceId,
        cause: RevisionCause.manualSave,
      );

      final second = await service.captureRevision(
        _resourceId,
        cause: RevisionCause.manualSave,
      );

      expect(second.wasNoOp, isTrue);
      expect(second.revision!.revisionId, first.revision!.revisionId);
      expect(await service.countRevisions(_resourceId), 1);
    });

    test('a later capture stores only the changed node', () async {
      await seedTree();
      final first = await service.captureRevision(
        _resourceId,
        cause: RevisionCause.generation,
      );
      await editPart(_partA, '第二版正文');

      final second = await service.captureRevision(
        _resourceId,
        cause: RevisionCause.manualSave,
      );

      expect(second.wasNoOp, isFalse);
      expect(
        second.revision!.parentRevisionId,
        first.revision!.revisionId,
        reason: 'revisions form a chain so replay can reconstruct any state',
      );
      final deltas = await revisions.readDeltas(second.revision!.revisionId);
      expect(
        deltas.map((node) => node.nodeId).toList(),
        <String>[_partA.value],
        reason: 'an edit must not copy the untouched parts of the tree',
      );
      expect(deltas.single.content, '第二版正文');
    });

    test('an empty result means no revision is invented', () async {
      final report = await service.captureRevision(
        const ResourceId('res_missing'),
        cause: RevisionCause.manualSave,
      );
      expect(report.captured, isFalse);
      expect(report.revision, isNull);
    });

    test('history is newest-first and head is unique', () async {
      await seedTree();
      await service.captureRevision(_resourceId,
          cause: RevisionCause.migration);
      await editPart(_partA, 'v2');
      await service.captureRevision(_resourceId,
          cause: RevisionCause.manualSave);
      await editPart(_partA, 'v3');
      await service.captureRevision(_resourceId,
          cause: RevisionCause.manualSave);

      final history = await service.history(_resourceId);
      expect(history, hasLength(3));
      expect(history.first.isHead, isTrue);
      expect(
        history.where((revision) => revision.isHead),
        hasLength(1),
        reason: 'a head pointer that is not unique would make reads ambiguous',
      );
      expect(
        history.first.createdAtToken.compareTo(history.last.createdAtToken),
        greaterThanOrEqualTo(0),
      );
    });
  });

  group('immutability', () {
    test('a historical revision still describes its own content', () async {
      await seedTree();
      final v1 = await service.captureRevision(
        _resourceId,
        cause: RevisionCause.generation,
      );
      await editPart(_partA, 'v2');
      await service.captureRevision(_resourceId,
          cause: RevisionCause.manualSave);
      await editPart(_partA, 'v3');
      await service.captureRevision(_resourceId,
          cause: RevisionCause.manualSave);

      final state = await service.readState(v1.revision!.revisionId);
      expect(
        state.nodes.values
            .firstWhere((node) => node.nodeId == _partA.value)
            .content,
        '第一版正文',
        reason: 'revisions are immutable: later edits must not rewrite history',
      );
      final current = await service.readState(
        (await service.latestHead(_resourceId))!.revisionId,
      );
      expect(
        current.nodes.values
            .firstWhere((node) => node.nodeId == _partA.value)
            .content,
        'v3',
      );
    });

    test('revision rows are never updated in place', () async {
      await seedTree();
      final v1 = await service.captureRevision(
        _resourceId,
        cause: RevisionCause.generation,
      );
      final db = await getDb();
      final before = (await db.query(
        'resource_revisions',
        where: 'revision_id = ?',
        whereArgs: <Object?>[v1.revision!.revisionId.value],
      ))
          .single;
      await editPart(_partA, 'v2');
      await service.captureRevision(_resourceId,
          cause: RevisionCause.manualSave);
      final after = (await db.query(
        'resource_revisions',
        where: 'revision_id = ?',
        whereArgs: <Object?>[v1.revision!.revisionId.value],
      ))
          .single;

      expect(after['content_hash'], before['content_hash']);
      expect(after['cause'], before['cause']);
      expect(after['parent_revision_id'], before['parent_revision_id']);
      expect(after['created_at'], before['created_at']);
      expect(
        after['is_head'],
        0,
        reason: 'only the head flag may move; the revision itself is frozen',
      );
    });
  });

  group('head switching and assembly publication', () {
    test('no assembly revision means preparing, not ready', () async {
      await seedTree();
      await service.captureRevision(_resourceId,
          cause: RevisionCause.migration);

      final selection = await service.select(_resourceId);
      expect(selection.readiness, ReadinessState.preparing);
      expect(selection.hasAssemblyRevision, isFalse);
      expect(selection.canAssemble, isFalse);
    });

    test('publishing an assembly revision keeps the two heads independent',
        () async {
      await seedTree();
      final head = await service.captureRevision(
        _resourceId,
        cause: RevisionCause.migration,
      );

      await service.publishAssemblyRevision(
        resourceId: _resourceId,
        revisionId: head.revision!.revisionId,
      );

      final selection = await service.select(_resourceId);
      expect(selection.readiness, ReadinessState.ready);
      expect(selection.canAssemble, isTrue);
      expect(
        selection.latestHead!.revisionId,
        head.revision!.revisionId,
        reason: 'publishing must not move the latest-head pointer',
      );
      expect(
        selection.assemblyRevision!.revisionId,
        isNot(head.revision!.revisionId),
        reason: 'the assembly version is its own row so the two can diverge',
      );
      expect(
        selection.assemblyRevision!.kind,
        ResourceRevisionKind.assembly,
      );
    });

    test('a later edit makes the published assembly version stale', () async {
      await seedTree();
      final head = await service.captureRevision(
        _resourceId,
        cause: RevisionCause.migration,
      );
      await service.publishAssemblyRevision(
        resourceId: _resourceId,
        revisionId: head.revision!.revisionId,
      );
      await editPart(_partA, '编辑后的正文');
      // Every production write path records a revision, which is what moves the
      // latest head away from the published one.
      await service.captureRevision(_resourceId,
          cause: RevisionCause.manualSave);

      final selection = await service.select(_resourceId);
      expect(selection.readiness, ReadinessState.stale);
      expect(selection.canAssemble, isFalse);
    });

    test('publishing a revision of another resource is refused', () async {
      await seedTree();
      final head = await service.captureRevision(
        _resourceId,
        cause: RevisionCause.migration,
      );

      await expectLater(
        service.publishAssemblyRevision(
          resourceId: const ResourceId('res_other'),
          revisionId: head.revision!.revisionId,
        ),
        throwsA(isA<ResourceRevisionNotFoundException>()),
      );
    });
  });

  group('restore', () {
    test('rolls the live tree back to the recorded version', () async {
      await seedTree();
      final v1 = await service.captureRevision(
        _resourceId,
        cause: RevisionCause.generation,
      );
      await editPart(_partA, '被覆盖的第二版');
      final v2 = await service.captureRevision(
        _resourceId,
        cause: RevisionCause.regeneration,
      );

      final result = await service.restoreRevision(v1.revision!.revisionId);

      expect(result.alreadyAtRevision, isFalse);
      expect(result.sourceCause, RevisionCause.generation);
      expect(await liveContent(_partA), '第一版正文');
      expect(
        result.beforeRevisionId,
        isNotNull,
        reason: 'the restore must snapshot what it replaced, so it is itself '
            'reversible',
      );
      expect(
        result.headRevisionId,
        isNot(v1.revision!.revisionId),
        reason: 'restoring appends a new revision instead of rewriting one',
      );
      // The replaced state is still reachable.
      final before = await service.readState(result.beforeRevisionId!);
      expect(
        before.nodes.values
            .firstWhere((node) => node.nodeId == _partA.value)
            .content,
        '被覆盖的第二版',
      );
      expect(v2.revision, isNotNull);
    });

    test('repeating the same restore changes nothing', () async {
      await seedTree();
      final v1 = await service.captureRevision(
        _resourceId,
        cause: RevisionCause.generation,
      );
      await editPart(_partA, 'v2');
      await service.captureRevision(_resourceId,
          cause: RevisionCause.manualSave);

      await service.restoreRevision(v1.revision!.revisionId);
      final countAfterFirst = await service.countRevisions(_resourceId);

      final second = await service.restoreRevision(v1.revision!.revisionId);

      expect(second.alreadyAtRevision, isTrue);
      expect(second.restoredNodeCount, 0);
      expect(second.removedNodeCount, 0);
      expect(
        await service.countRevisions(_resourceId),
        countAfterFirst,
        reason: 'an idempotent repeat must not append duplicate revisions',
      );
      expect(await liveContent(_partA), '第一版正文');
    });

    test('restoring a revision that predates a section removes it again',
        () async {
      await seedTree();
      final v1 = await service.captureRevision(
        _resourceId,
        cause: RevisionCause.generation,
      );
      await tree.mount(
        const AppendSectionPatch(resourceId: _resourceId, title: '第二章'),
      );
      await service.captureRevision(_resourceId,
          cause: RevisionCause.manualSave);
      expect((await tree.readSections(_resourceId)).length, 2);

      await service.restoreRevision(v1.revision!.revisionId);

      expect(
        (await tree.readSections(_resourceId)).length,
        1,
        reason: 'a restore must shrink the tree, not only revert text',
      );
    });

    test('restoring revives a section that was deleted afterwards', () async {
      await seedTree();
      final v1 = await service.captureRevision(
        _resourceId,
        cause: RevisionCause.generation,
      );
      final sectionState = await tree.readNodeState(_sectionId);
      await tree.softDeleteNode(
        id: _sectionId,
        expectedUpdatedAt: sectionState!.updatedAt,
      );
      await service.captureRevision(_resourceId,
          cause: RevisionCause.manualSave);
      expect(await tree.readSections(_resourceId), isEmpty);

      await service.restoreRevision(v1.revision!.revisionId);

      expect((await tree.readSections(_resourceId)).length, 1);
      expect(await liveContent(_partA), '第一版正文');
    });

    test('a stale token refuses the restore and keeps the tree untouched',
        () async {
      await seedTree();
      final v1 = await service.captureRevision(
        _resourceId,
        cause: RevisionCause.generation,
      );
      await editPart(_partA, '当前正文');
      await service.captureRevision(_resourceId,
          cause: RevisionCause.manualSave);

      await expectLater(
        service.restoreRevision(
          v1.revision!.revisionId,
          expectedUpdatedAt: 'stale-token',
        ),
        throwsA(isA<ResourceRevisionConflictException>()),
      );

      expect(
        await liveContent(_partA),
        '当前正文',
        reason: 'a rejected restore must not half-apply',
      );
      expect(await service.countRevisions(_resourceId), 2);
    });

    test('a missing revision target is refused', () async {
      await seedTree();
      await expectLater(
        service.restoreRevision(const ResourceRevisionId('rev_missing')),
        throwsA(isA<ResourceRevisionNotFoundException>()),
      );
    });

    test('restore reopens the generation tasks of the changed parts', () async {
      await seedTree();
      await seedTask();
      final v1 = await service.captureRevision(
        _resourceId,
        cause: RevisionCause.generation,
      );
      await editPart(_partA, 'v2');
      await service.captureRevision(_resourceId,
          cause: RevisionCause.manualSave);

      final result = await service.restoreRevision(v1.revision!.revisionId);

      expect(result.reopenedPartIds, contains(_partA.value));
      final db = await getDb();
      final task = (await db.query(
        'resource_generation_tasks',
        where: 'task_id = ?',
        whereArgs: <Object?>['task_rev_a'],
      ))
          .single;
      expect(
        task['status'],
        'ready',
        reason: 'a completed task whose content was replaced must be '
            'regenerable again',
      );
    });

    test('a failed restore rolls back the revision it tried to record',
        () async {
      await seedTree();
      final v1 = await service.captureRevision(
        _resourceId,
        cause: RevisionCause.generation,
      );
      await editPart(_partA, 'v2');
      await service.captureRevision(_resourceId,
          cause: RevisionCause.manualSave);
      final before = await service.countRevisions(_resourceId);

      // Permanently remove the resource root: applying the target state can no
      // longer update it, so the whole restore must roll back.
      final db = await getDb();
      await db.delete('resource_parts');
      await db.delete('resource_sections');
      await db.delete('resources',
          where: 'id = ?', whereArgs: <Object?>['res_rev']);

      await expectLater(
        service.restoreRevision(v1.revision!.revisionId),
        throwsA(isA<ResourceRevisionException>()),
      );

      expect(
        await service.countRevisions(_resourceId),
        before,
        reason: 'no revision may be created by a failed restore',
      );
    });
  });

  group('beginLossyOperation', () {
    test('records the pre-operation state and reopens completed tasks',
        () async {
      await seedTree();
      await seedTask(status: 'completed');
      await service.captureRevision(_resourceId,
          cause: RevisionCause.generation);
      final countBefore = await service.countRevisions(_resourceId);

      final report = await service.beginLossyOperation(
        _resourceId,
        cause: RevisionCause.regeneration,
        partIds: <String>[_partA.value],
        label: 'regenerate 前快照',
      );

      expect(report.captured, isTrue);
      expect(
        report.wasNoOp,
        isTrue,
        reason: 'the head already described the current content, so the '
            'boundary is free when nothing drifted',
      );
      expect(
        await service.countRevisions(_resourceId),
        countBefore,
        reason: 'a redundant before-revision would duplicate history',
      );
      final db = await getDb();
      final task = (await db.query(
        'resource_generation_tasks',
        where: 'task_id = ?',
        whereArgs: <Object?>['task_rev_a'],
      ))
          .single;
      expect(task['status'], 'ready');
    });

    test('captures drift that no earlier path recorded', () async {
      await seedTree();
      await service.captureRevision(_resourceId,
          cause: RevisionCause.generation);
      // Simulate a write path that changed the tree without recording anything.
      await editPart(_partA, '未被记录的改动');

      final report = await service.beginLossyOperation(
        _resourceId,
        cause: RevisionCause.regeneration,
      );

      expect(report.wasNoOp, isFalse);
      final state = await service.readState(report.revision!.revisionId);
      expect(
        state.nodes.values
            .firstWhere((node) => node.nodeId == _partA.value)
            .content,
        '未被记录的改动',
        reason: 'a missed hook degrades into a coarser revision, never into '
            'unrecoverable data',
      );
    });

    test('keeps an in-flight generation task untouched', () async {
      await seedTree();
      await seedTask(status: 'generating');

      await service.beginLossyOperation(
        _resourceId,
        cause: RevisionCause.regeneration,
        partIds: <String>[_partA.value],
      );

      final db = await getDb();
      final task = (await db.query(
        'resource_generation_tasks',
        where: 'task_id = ?',
        whereArgs: <Object?>['task_rev_a'],
      ))
          .single;
      expect(
        task['status'],
        'generating',
        reason: 'the reset must never hijack a run that is already in flight',
      );
    });
  });

  group('retention cleanup', () {
    test('keeps everything inside the retention window', () async {
      await seedTree();
      await service.captureRevision(_resourceId,
          cause: RevisionCause.migration);
      await editPart(_partA, 'v2');
      await service.captureRevision(_resourceId,
          cause: RevisionCause.manualSave);

      final report = await service.pruneRevisions(resourceId: _resourceId);

      expect(report.deletedRevisions, 0);
      expect(report.rerootedRevisions, 0);
      expect(await service.countRevisions(_resourceId), 2);
    });

    test('prunes the old prefix, re-roots the survivor and stays replayable',
        () async {
      await seedTree();
      final aggressive = ResourceRevisionService(
        revisionRepository: revisions,
        captureEngine: engine,
        treeBoundary: tree,
        getDb: getDb,
        retention: Duration.zero,
      );
      await aggressive.captureRevision(
        _resourceId,
        cause: RevisionCause.generation,
      );
      await editPart(_partA, 'v2');
      await aggressive.captureRevision(
        _resourceId,
        cause: RevisionCause.manualSave,
      );
      await editPart(_partA, 'v3');
      final head = await aggressive.captureRevision(
        _resourceId,
        cause: RevisionCause.manualSave,
      );

      final report = await aggressive.pruneRevisions(resourceId: _resourceId);

      expect(report.deletedRevisions, greaterThan(0));
      expect(report.rerootedRevisions, 1);
      expect(report.skippedResources, isEmpty);

      // Exactly the head survives, and it is now self-contained.
      final history = await aggressive.history(_resourceId);
      expect(history, hasLength(1));
      expect(history.single.revisionId, head.revision!.revisionId);
      expect(
        history.single.parentRevisionId,
        isNull,
        reason: 'the survivor must be re-rooted so the chain cannot dangle',
      );
      final state = await aggressive.readState(head.revision!.revisionId);
      expect(state.nodes.length, 4);
      expect(
        state.nodes.values
            .firstWhere((node) => node.nodeId == _partA.value)
            .content,
        'v3',
        reason: 'pruning must not lose the surviving state',
      );
    });

    test('never deletes the current head', () async {
      await seedTree();
      final aggressive = ResourceRevisionService(
        revisionRepository: revisions,
        captureEngine: engine,
        treeBoundary: tree,
        getDb: getDb,
        retention: Duration.zero,
      );
      final head = await aggressive.captureRevision(
        _resourceId,
        cause: RevisionCause.generation,
      );

      await aggressive.pruneRevisions(resourceId: _resourceId);

      final surviving = await aggressive.history(_resourceId);
      expect(surviving.single.revisionId, head.revision!.revisionId);
      expect(surviving.single.isHead, isTrue);
    });

    test('never deletes a revision an assembly pointer still needs', () async {
      await seedTree();
      final aggressive = ResourceRevisionService(
        revisionRepository: revisions,
        captureEngine: engine,
        treeBoundary: tree,
        getDb: getDb,
        retention: Duration.zero,
      );
      final published = await aggressive.captureRevision(
        _resourceId,
        cause: RevisionCause.migration,
      );
      await aggressive.publishAssemblyRevision(
        resourceId: _resourceId,
        revisionId: published.revision!.revisionId,
      );
      await editPart(_partA, 'v2');
      await aggressive.captureRevision(
        _resourceId,
        cause: RevisionCause.manualSave,
      );

      final report = await aggressive.pruneRevisions(resourceId: _resourceId);

      expect(
        report.protectedRevisions.map((revision) => revision.value),
        contains(isNotNull),
      );
      final db = await getDb();
      final assemblyRows = await db.query(
        'resource_revisions',
        where: 'resource_id = ? AND kind = ?',
        whereArgs: <Object?>[_resourceId.value, 'assembly'],
      );
      expect(assemblyRows, isNotEmpty);
      expect(
        assemblyRows.where((row) => row['is_head'] == 1),
        hasLength(1),
        reason: 'the assembly head must survive cleanup',
      );
      final selection = await aggressive.select(_resourceId);
      expect(
        selection.readiness,
        ReadinessState.stale,
        reason: 'the published version no longer matches the latest head',
      );
    });

    test('never deletes a revision an unresolved bin entry points at',
        () async {
      await seedTree();
      final aggressive = ResourceRevisionService(
        revisionRepository: revisions,
        captureEngine: engine,
        treeBoundary: tree,
        getDb: getDb,
        retention: Duration.zero,
      );
      final referenced = await aggressive.captureRevision(
        _resourceId,
        cause: RevisionCause.generation,
      );
      final db = await getDb();
      await db.insert('resource_trash', {
        'trash_id': 'trash_ref',
        'resource_id': _resourceId.value,
        'node_id': 'part_deleted',
        'node_kind': 'part',
        'parent_node_id': _sectionId.value,
        'original_sort_order': 0,
        'original_status': 'draft',
        'original_title': '已删除',
        'reason': 'userDelete',
        'revision_id': referenced.revision!.revisionId.value,
        'deleted_at': '2026-09-17T00:00:00.000',
        'expires_at': '2027-09-17T00:00:00.000',
        'restore_outcome': '',
        'metadata_json': '{}',
      });
      await editPart(_partA, 'v2');
      await aggressive.captureRevision(
        _resourceId,
        cause: RevisionCause.manualSave,
      );

      final report = await aggressive.pruneRevisions(resourceId: _resourceId);

      expect(
        report.protectedRevisions.map((revision) => revision.value).toList(),
        contains(referenced.revision!.revisionId.value),
      );
      // Deleting it would also delete the node this guards, so the prefix
      // before it must be kept.
      expect(
        await db.query(
          'resource_revisions',
          where: 'revision_id = ?',
          whereArgs: <Object?>[referenced.revision!.revisionId.value],
        ),
        isNotEmpty,
      );
    });

    test('reports a broken chain instead of truncating it', () async {
      await seedTree();
      final aggressive = ResourceRevisionService(
        revisionRepository: revisions,
        captureEngine: engine,
        treeBoundary: tree,
        getDb: getDb,
        retention: Duration.zero,
      );
      await aggressive.captureRevision(_resourceId,
          cause: RevisionCause.generation);
      await editPart(_partA, 'v2');
      await aggressive.captureRevision(_resourceId,
          cause: RevisionCause.manualSave);

      // Break the chain behind the service's back.
      final db = await getDb();
      await db.update(
        'resource_revisions',
        <String, Object?>{'parent_revision_id': 'rev_missing'},
        where: 'resource_id = ? AND parent_revision_id IS NOT NULL',
        whereArgs: <Object?>[_resourceId.value],
      );

      final report = await aggressive.pruneRevisions(resourceId: _resourceId);

      expect(report.skippedResources, isNotEmpty);
      expect(report.deletedRevisions, 0);
      expect(
        await aggressive.countRevisions(_resourceId),
        2,
        reason: 'destroying history to make cleanup succeed would be worse '
            'than leaving it alone',
      );
    });

    test('leaves a resource with no history completely alone', () async {
      await seedTree();
      final report = await service.pruneRevisions(resourceId: _resourceId);
      expect(report.deletedRevisions, 0);
      expect(report.rerootedRevisions, 0);
      expect(report.skippedResources, isEmpty);
    });
  });

  group('latestHead', () {
    test('is null before any revision exists', () async {
      await seedTree();
      expect(await service.latestHead(_resourceId), isNull);
    });

    test('returns the recorded head with its kind and time', () async {
      await seedTree();
      final captured = await service.captureRevision(
        _resourceId,
        cause: RevisionCause.generation,
      );

      final head = await service.latestHead(_resourceId);
      expect(head, isNotNull);
      expect(head!.revisionId, captured.revision!.revisionId);
      expect(head.kind, ResourceRevisionKind.latestHead);
      expect(head.createdAt, isNotNull);
    });

    test('ignores the assembly head', () async {
      await seedTree();
      final captured = await service.captureRevision(
        _resourceId,
        cause: RevisionCause.generation,
      );
      await service.publishAssemblyRevision(
        resourceId: _resourceId,
        revisionId: captured.revision!.revisionId,
      );

      final head = await service.latestHead(_resourceId);
      expect(
        head!.revisionId,
        captured.revision!.revisionId,
        reason: 'latestHead must not drift to the published version',
      );
    });
  });
}
