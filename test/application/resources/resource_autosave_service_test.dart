import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/resource_autosave_repository.dart';
import 'package:lt_dialogue/application/resources/resource_autosave_service.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_service.dart';
import 'package:lt_dialogue/application/resources/part_content_commit_service.dart';
import 'package:lt_dialogue/domain/resources/resource_autosave.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_revision.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/section_control_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _resourceId = ResourceId('res_auto');
const _sectionId = SectionId('res_auto_sec_1');
const _partId = PartId('res_auto_sec_1_part_1');

/// Counts the SQLite writes the autosave path actually issues.
///
/// The Phase 9 requirement is "typing must not produce one write per
/// keystroke"; a counter on the real write methods is the actionable proof,
/// not a code reading.
final class _CountingJournal implements IResourceAutosaveRepository {
  _CountingJournal(this._inner);

  final IResourceAutosaveRepository _inner;

  int upserts = 0;
  int deletes = 0;

  @override
  Future<ResourceAutosaveDraft> upsertDraftInTransaction(
    DatabaseExecutor txn, {
    required ResourceId resourceId,
    required PartId partId,
    required String content,
    required String baseUpdatedAt,
    required String now,
  }) {
    upserts++;
    return _inner.upsertDraftInTransaction(
      txn,
      resourceId: resourceId,
      partId: partId,
      content: content,
      baseUpdatedAt: baseUpdatedAt,
      now: now,
    );
  }

  @override
  Future<int> deleteDraftInTransaction(
      DatabaseExecutor txn, String checkpointId) {
    deletes++;
    return _inner.deleteDraftInTransaction(txn, checkpointId);
  }

  @override
  Future<ResourceAutosaveDraft?> findDraft(String nodeId) =>
      _inner.findDraft(nodeId);

  @override
  Future<List<ResourceAutosaveDraft>> listDrafts({
    ResourceId? resourceId,
    int limit = 100,
  }) =>
      _inner.listDrafts(resourceId: resourceId, limit: limit);

  @override
  Future<int> countDrafts(ResourceId resourceId) =>
      _inner.countDrafts(resourceId);
}

/// Counts how many times the Part body was actually written.
final class _CountingTreeBoundary implements IResourceTreeRevisionBoundary {
  _CountingTreeBoundary(this._inner);

  final IResourceTreeRevisionBoundary _inner;

  int partWrites = 0;

  @override
  Future<void> updatePartInTransaction(
    DatabaseExecutor db, {
    required PartId id,
    required String expectedUpdatedAt,
    String? title,
    String? content,
    NodeStatus? status,
    String now = '',
  }) {
    partWrites++;
    return _inner.updatePartInTransaction(
      db,
      id: id,
      expectedUpdatedAt: expectedUpdatedAt,
      title: title,
      content: content,
      status: status,
      now: now,
    );
  }

  @override
  Future<Set<String>> applyRevisionState(
    DatabaseExecutor db, {
    required ResourceId resourceId,
    required Map<String, RevisionNodeSnapshot> target,
    required String now,
  }) =>
      _inner.applyRevisionState(
        db,
        resourceId: resourceId,
        target: target,
        now: now,
      );

  @override
  Future<SectionId> createSectionInTransaction(
    DatabaseExecutor db, {
    required ResourceId resourceId,
    required String title,
    String now = '',
  }) =>
      _inner.createSectionInTransaction(
        db,
        resourceId: resourceId,
        title: title,
        now: now,
      );

  @override
  Future<void> purgeNodeInTransaction(DatabaseExecutor db, NodeId id) =>
      _inner.purgeNodeInTransaction(db, id);

  @override
  Future<TrashNodePlacement?> readNodePlacement(
          DatabaseExecutor db, NodeId id) =>
      _inner.readNodePlacement(db, id);

  @override
  Future<({String updatedAt, String? deletedAt})?> readNodesTimestamps(
    DatabaseExecutor db,
    NodeId id,
  ) =>
      _inner.readNodesTimestamps(db, id);

  @override
  Future<Map<String, RevisionNodeSnapshot>> readLiveState(
    DatabaseExecutor db,
    ResourceId resourceId,
  ) =>
      _inner.readLiveState(db, resourceId);

  @override
  Future<void> reparentNodeInTransaction(
    DatabaseExecutor db, {
    required NodeId id,
    required String newParentId,
    required int sortOrder,
    required String now,
  }) =>
      _inner.reparentNodeInTransaction(
        db,
        id: id,
        newParentId: newParentId,
        sortOrder: sortOrder,
        now: now,
      );

  @override
  Future<void> reviveNodeInTransaction(
    DatabaseExecutor db, {
    required NodeId id,
    required String expectedDeletedAt,
    String now = '',
  }) =>
      _inner.reviveNodeInTransaction(
        db,
        id: id,
        expectedDeletedAt: expectedDeletedAt,
        now: now,
      );

  @override
  Future<void> softDeleteNodeInTransaction(
    DatabaseExecutor db, {
    required NodeId id,
    required String expectedUpdatedAt,
    String now = '',
  }) =>
      _inner.softDeleteNodeInTransaction(
        db,
        id: id,
        expectedUpdatedAt: expectedUpdatedAt,
        now: now,
      );
}

/// Tree boundary that injects a "second race" external write (R2-M1).
///
/// The write lands inside the session's live-read transaction but is reported
/// with the pre-race token, which is exactly the state the session sees when
/// another writer commits between its live read and its CAS write.
final class _RacingTreeBoundary extends _CountingTreeBoundary {
  _RacingTreeBoundary(super.inner);

  /// Content the other writer commits; consumed on the next live read.
  String? raceContent;

  @override
  Future<({String updatedAt, String? deletedAt})?> readNodesTimestamps(
    DatabaseExecutor db,
    NodeId id,
  ) async {
    final before = await super.readNodesTimestamps(db, id);
    final content = raceContent;
    if (content != null && before != null) {
      raceContent = null;
      await _inner.updatePartInTransaction(
        db,
        id: PartId(id.value),
        expectedUpdatedAt: before.updatedAt,
        content: content,
        now: '${before.updatedAt}#race',
      );
    }
    return before;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late ResourceTreeRepositoryImpl tree;
  late ResourceRevisionRepositoryImpl revisions;
  late RevisionCaptureEngine engine;
  late ResourceAutosaveRepositoryImpl journalRepository;
  late _CountingJournal journal;
  late _CountingTreeBoundary boundary;
  late ResourceAutosaveService autosave;

  const fastDebounce = Duration(milliseconds: 40);

  Future<Database> getDb() => DatabaseService.database;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_phase9_autosave_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();

    tree = ResourceTreeRepositoryImpl(getDb: getDb);
    revisions = ResourceRevisionRepositoryImpl(getDb: getDb);
    engine = RevisionCaptureEngine(
      revisionRepository: revisions,
      treeBoundary: tree,
    );
    journalRepository = ResourceAutosaveRepositoryImpl(getDb: getDb);
    journal = _CountingJournal(journalRepository);
    boundary = _CountingTreeBoundary(tree);

    final commitService = PartContentCommitService(
      treeBoundary: boundary,
      validationBoundary: SectionControlRepositoryImpl(getDb: getDb),
      captureEngine: engine,
      autosaveRepository: journal,
      getDb: getDb,
      taskReset: PartGenerationTaskRepositoryImpl(getDb: getDb),
    );
    autosave = ResourceAutosaveService(
      journal: journal,
      committer: commitService,
      treeBoundary: boundary,
      getDb: getDb,
      debounce: fastDebounce,
      maxBufferedAge: const Duration(seconds: 2),
    );

    await tree.createResourceTree(
      const ResourceTreeDraft(
        id: _resourceId,
        type: ResourceType.worldview,
        name: '自动保存测试',
        sections: [
          ResourceTreeSectionDraft(
            id: _sectionId,
            title: '第一章',
            parts: [
              ResourceTreePartDraft(
                id: _partId,
                title: '开场',
                content: '原始正文',
              ),
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

  /// Token the editor currently believes it is writing against. Every test
  /// refreshes it from the tree after a successful save, exactly as the widget
  /// does.
  var currentToken = '';

  Future<String> liveContent() async {
    final parts = await tree.readParts(_sectionId);
    return parts.single.content;
  }

  Future<String> token() async =>
      (await tree.readNodeState(_partId))!.updatedAt;

  void type(String text, {String? tokenOverride}) {
    autosave.schedule(
      resourceId: _resourceId,
      partId: _partId,
      content: text,
      expectedUpdatedAt: tokenOverride ?? currentToken,
    );
  }

  group('debounce', () {
    test('typing only touches memory, never SQLite', () async {
      currentToken = await token();

      for (var i = 0; i < 25; i++) {
        type('原始正文 + $i');
      }

      expect(
        journal.upserts,
        0,
        reason: 'a keystroke must not issue a database write',
      );
      expect(boundary.partWrites, 0);
      expect(await journalRepository.countDrafts(_resourceId), 0);
      expect(autosave.pendingCount, 1);
      expect(autosave.bufferedContent(_partId), '原始正文 + 24');

      await autosave.dispose();
    });

    test('a pause coalesces the burst into a single write', () async {
      currentToken = await token();
      for (var i = 0; i < 25; i++) {
        type('原始正文 + $i');
      }

      await Future<void>.delayed(fastDebounce * 3);

      expect(
        journal.upserts,
        1,
        reason: '25 keystrokes inside one debounce window are one checkpoint',
      );
      expect(
        boundary.partWrites,
        1,
        reason: 'the tree is written once for the whole burst',
      );
      expect(await liveContent(), '原始正文 + 24');
      expect(
        await journalRepository.countDrafts(_resourceId),
        0,
        reason: 'the checkpoint row is consumed by the write it belongs to',
      );
      await autosave.dispose();
    });

    test('continuous typing is still checkpointed by the max buffered age',
        () async {
      final continuous = ResourceAutosaveService(
        journal: journal,
        committer: PartContentCommitService(
          treeBoundary: boundary,
          validationBoundary: SectionControlRepositoryImpl(getDb: getDb),
          captureEngine: engine,
          autosaveRepository: journal,
          getDb: getDb,
        ),
        treeBoundary: boundary,
        getDb: getDb,
        debounce: const Duration(milliseconds: 500),
        maxBufferedAge: const Duration(milliseconds: 60),
      );
      currentToken = await token();
      continuous.schedule(
        resourceId: _resourceId,
        partId: _partId,
        content: '连续输入中',
        expectedUpdatedAt: currentToken,
      );

      // Keep "typing" faster than the debounce, but past the max age.
      final deadline = DateTime.now().add(const Duration(milliseconds: 300));
      while (DateTime.now().isBefore(deadline)) {
        continuous.schedule(
          resourceId: _resourceId,
          partId: _partId,
          content: '连续输入中',
          expectedUpdatedAt: currentToken,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(
        boundary.partWrites,
        greaterThanOrEqualTo(1),
        reason: 'a fast typist must not be able to keep text in memory forever',
      );
      await continuous.dispose();
      await autosave.dispose();
    });
  });

  group('final flush boundaries', () {
    test('dispose writes the buffered edit', () async {
      currentToken = await token();
      type('在关闭时保存');

      await autosave.dispose();

      expect(await liveContent(), '在关闭时保存');
      expect(boundary.partWrites, 1);
    });

    test('a forced page-leave flush runs before the debounce fires', () async {
      currentToken = await token();
      type('离开页面时保存');

      final result = await autosave.flushOnBoundary(
        AutosaveFlushTrigger.pageLeave,
      );

      expect(result.applied, 1);
      expect(result.trigger, AutosaveFlushTrigger.pageLeave);
      expect(await liveContent(), '离开页面时保存');
      await autosave.dispose();
    });

    test('a cancel flush keeps what the user already confirmed', () async {
      currentToken = await token();
      type('取消前确认的内容');

      await autosave.flushOnBoundary(AutosaveFlushTrigger.cancel);

      expect(await liveContent(), '取消前确认的内容');
      expect(autosave.pendingCount, 0);
      await autosave.dispose();
    });

    test('a generation-error flush persists rather than drops', () async {
      currentToken = await token();
      type('生成失败前的内容');

      await autosave.flushOnBoundary(AutosaveFlushTrigger.generationError);

      expect(await liveContent(), '生成失败前的内容');
      await autosave.dispose();
    });

    test('a lifecycle flush persists rather than drops', () async {
      currentToken = await token();
      type('退到后台时保存');

      await autosave.flushOnBoundary(AutosaveFlushTrigger.appLifecycle);

      expect(await liveContent(), '退到后台时保存');
      await autosave.dispose();
    });

    test('a flush with nothing buffered is a no-op', () async {
      final result = await autosave.flush();
      expect(result.hadWork, isFalse);
      expect(result.applied, 0);
      await autosave.dispose();
    });

    test('disposing twice is safe', () async {
      await autosave.dispose();
      final second = await autosave.dispose();
      expect(second.hadWork, isFalse);
    });

    test('an empty-title-only edit does not invent content', () async {
      currentToken = await token();
      autosave.schedule(
        resourceId: _resourceId,
        partId: _partId,
        content: '',
        expectedUpdatedAt: currentToken,
      );

      await autosave.flush(trigger: AutosaveFlushTrigger.manual);

      expect(await liveContent(), '');
      await autosave.dispose();
    });
  });

  group('conflict and loss protection', () {
    test('a stale token keeps the text in the journal instead of losing it',
        () async {
      currentToken = 'stale-token';
      type('基于陈旧版本的编辑');

      final result = await autosave.flush();

      expect(result.conflicted, 1);
      expect(result.hasUnsavedConflict, isTrue);
      expect(
        await liveContent(),
        '原始正文',
        reason: 'a conflicting write must not overwrite the newer version',
      );
      final drafts = await journalRepository.listDrafts(
        resourceId: _resourceId,
      );
      expect(drafts, hasLength(1));
      expect(
        drafts.single.content,
        '基于陈旧版本的编辑',
        reason: 'the user text must survive a refused save',
      );
      await autosave.dispose();
    });

    test('a deleted target drops the draft instead of resurrecting it',
        () async {
      currentToken = await token();
      type('目标已被删除');
      await tree.softDeleteNode(
        id: _partId,
        expectedUpdatedAt: await token(),
      );

      final result = await autosave.flush();

      expect(result.discarded, 1);
      expect(
        await journalRepository.countDrafts(_resourceId),
        0,
        reason: 'a draft for a node that no longer exists cannot be applied',
      );
      await autosave.dispose();
    });
  });

  group('write-through wiring', () {
    test('a flush downgrades the section verdict and records a revision',
        () async {
      final db = await getDb();
      await db.update(
        'resource_sections',
        <String, Object?>{
          'validation_state': 'valid',
          'validation_message': '',
          'updated_at': '2026-09-17T00:00:00.000',
        },
        where: 'id = ?',
        whereArgs: <Object?>[_sectionId.value],
      );
      currentToken = await token();
      type('新的正文');

      await autosave.flush();

      final section = (await db.query(
        'resource_sections',
        where: 'id = ?',
        whereArgs: <Object?>[_sectionId.value],
      ))
          .single;
      expect(
        section['validation_state'],
        'stale',
        reason: 'a recorded verdict must stop being valid for new content',
      );
      final history = await ResourceRevisionService(
        revisionRepository: revisions,
        captureEngine: engine,
        treeBoundary: tree,
        getDb: getDb,
      ).history(_resourceId);
      expect(
        history,
        isNotEmpty,
        reason: 'a manual save is a revision-worthy change',
      );
      expect(history.first.cause, RevisionCause.manualSave);
      await autosave.dispose();
    });

    test('a flush makes a completed generation task regenerable again',
        () async {
      final db = await getDb();
      await db.insert('resource_generation_tasks', {
        'task_id': 'task_auto',
        'blueprint_id': 'bp_auto',
        'resource_id': _resourceId.value,
        'section_id': _sectionId.value,
        'part_id': _partId.value,
        'prompt_goal': '写开场',
        'estimated_length': 800,
        'dependencies_json': '[]',
        'status': 'completed',
        'sort_order': 0,
        'current_attempt_id': '',
        'error_message': '',
        'created_at': '2026-09-17T00:00:00.000',
        'updated_at': '2026-09-17T00:00:00.000',
      });
      currentToken = await token();
      type('手工重写后的正文');

      await autosave.flush();

      final task = (await db.query(
        'resource_generation_tasks',
        where: 'task_id = ?',
        whereArgs: <Object?>['task_auto'],
      ))
          .single;
      expect(
        task['status'],
        'ready',
        reason: 'content that no longer came from the model must be '
            'regenerable',
      );
      await autosave.dispose();
    });

    test('the second save uses the token the first save produced', () async {
      currentToken = await token();
      type('第一次保存');
      await autosave.flush();
      final firstToken = await token();

      currentToken = firstToken;
      type('第二次保存');
      final result = await autosave.flush();

      expect(result.applied, 1);
      expect(await liveContent(), '第二次保存');
      await autosave.dispose();
    });
  });

  group('token ownership (P9-M2)', () {
    test('a save right after a successful one is not a conflict', () async {
      currentToken = await token();
      type('第一次输入');
      final first = await autosave.flush();
      expect(first.applied, 1);

      // The editor's copy of the token is now one save behind. Before the fix
      // that made every later save fail forever; the session's own token wins.
      expect(
        currentToken,
        isNot(await token()),
        reason: 'the widget token really is stale here',
      );
      type('第二次输入');
      final second = await autosave.flush();

      expect(
        second.applied,
        1,
        reason: 'the session advances its own token, so its own save cannot '
            'poison the next one',
      );
      expect(second.conflicted, 0);
      expect(await liveContent(), '第二次输入');
      await autosave.dispose();
    });

    test('repeated save cycles never get stuck', () async {
      currentToken = await token();
      for (var i = 0; i < 5; i++) {
        type('第 $i 次输入');
        final result = await autosave.flush();
        expect(result.applied, 1, reason: 'cycle $i must still save');
      }
      expect(await liveContent(), '第 4 次输入');
      expect(
        await journalRepository.countDrafts(_resourceId),
        0,
        reason: 'a healthy cycle leaves no draft behind',
      );
      await autosave.dispose();
    });

    test('continuous typing across a forced flush still saves the last text',
        () async {
      final continuous = ResourceAutosaveService(
        journal: journal,
        committer: PartContentCommitService(
          treeBoundary: boundary,
          validationBoundary: SectionControlRepositoryImpl(getDb: getDb),
          captureEngine: engine,
          autosaveRepository: journal,
          getDb: getDb,
        ),
        treeBoundary: boundary,
        getDb: getDb,
        debounce: const Duration(milliseconds: 200),
        maxBufferedAge: const Duration(milliseconds: 60),
      );
      currentToken = await token();
      final deadline = DateTime.now().add(const Duration(milliseconds: 320));
      while (DateTime.now().isBefore(deadline)) {
        continuous.schedule(
          resourceId: _resourceId,
          partId: _partId,
          content: '连续输入 ${DateTime.now().millisecondsSinceEpoch}',
          // The editor keeps handing over its stale token; the session must not
          // let that turn into a permanent conflict.
          expectedUpdatedAt: currentToken,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      continuous.schedule(
        resourceId: _resourceId,
        partId: _partId,
        content: '最终正文',
        expectedUpdatedAt: currentToken,
      );
      final finalResult = await continuous.flush();

      expect(
        finalResult.applied,
        1,
        reason: 'the last text of a continuous typing session must land',
      );
      expect(await liveContent(), '最终正文');
      expect(await journalRepository.countDrafts(_resourceId), 0);
      await continuous.dispose();
      await autosave.dispose();
    });
  });

  group('conflict still protects newer content (P9-M2)', () {
    test('an edit buffered before an external write does not overwrite it',
        () async {
      currentToken = await token();
      type('用户的编辑');
      await autosave.flush();
      expect(await liveContent(), '用户的编辑');

      // Another writer (generation / restore / compression publish) replaces the
      // body *after* the session's own save.
      await tree.updatePart(
        id: _partId,
        expectedUpdatedAt: await token(),
        content: '模型新写入的正文',
      );

      type('用户继续输入');
      final result = await autosave.flush();

      expect(
        result.conflicted,
        1,
        reason: 'the conflict is not self-inflicted, so the session must not '
            'retry over the other writer',
      );
      expect(
        await liveContent(),
        '模型新写入的正文',
        reason: 'a stale draft must never overwrite newer content',
      );
      final drafts = await journalRepository.listDrafts(
        resourceId: _resourceId,
      );
      expect(drafts.single.content, '用户继续输入');
      await autosave.dispose();
    });

    test('the retry is bounded to one attempt per flush', () async {
      currentToken = await token();
      type('基于陈旧版本');
      // Two writers land before the flush, so the token is stale twice.
      await tree.updatePart(
        id: _partId,
        expectedUpdatedAt: await token(),
        content: '外部写入一',
      );
      await tree.updatePart(
        id: _partId,
        expectedUpdatedAt: await token(),
        content: '外部写入二',
      );

      final result = await autosave.flush();

      expect(
        result.conflicted,
        1,
        reason: 'no self-inflicted history exists, so no retry is allowed',
      );
      expect(await liveContent(), '外部写入二');
      await autosave.dispose();
    });
  });

  group('branch: confirmed content survives', () {
    test('an applied save removes its draft and records the text', () async {
      currentToken = await token();
      type('确认正文');
      await autosave.flush();

      expect(await liveContent(), '确认正文');
      expect(await journalRepository.countDrafts(_resourceId), 0);
      await autosave.dispose();
    });
  });

  group('crash recovery', () {
    test('a draft whose content already landed is dropped', () async {
      currentToken = await token();
      type('已经写入的正文');
      // Simulate a crash between the journal write and the tree commit: the
      // draft exists, but the body was written anyway.
      await journalRepository.upsertDraftInTransaction(
        await getDb(),
        resourceId: _resourceId,
        partId: _partId,
        content: '已经写入的正文',
        baseUpdatedAt: currentToken,
        now: DateTime.now().toIso8601String(),
      );
      await tree.updatePart(
        id: _partId,
        expectedUpdatedAt: currentToken,
        content: '已经写入的正文',
      );

      final outcomes = await autosave.reconcilePendingDrafts(
        resourceId: _resourceId,
      );

      expect(outcomes, hasLength(1));
      expect(
        outcomes.single.disposition,
        AutosaveRecoveryDisposition.alreadyApplied,
      );
      expect(await journalRepository.countDrafts(_resourceId), 0);
      await autosave.dispose();
    });

    test('a draft newer than the tree is kept for the user', () async {
      currentToken = await token();
      await journalRepository.upsertDraftInTransaction(
        await getDb(),
        resourceId: _resourceId,
        partId: _partId,
        content: '崩溃前未保存的编辑',
        baseUpdatedAt: currentToken,
        now: DateTime.now().toIso8601String(),
      );

      final outcomes = await autosave.reconcilePendingDrafts(
        resourceId: _resourceId,
      );

      expect(
        outcomes.single.disposition,
        AutosaveRecoveryDisposition.needsUserDecision,
      );
      expect(
        await journalRepository.countDrafts(_resourceId),
        1,
        reason: 'dropping it would silently discard the user\'s text',
      );
      expect(
        (await journalRepository.listDrafts(resourceId: _resourceId))
            .single
            .content,
        '崩溃前未保存的编辑',
      );
      await autosave.dispose();
    });

    test('a draft for a vanished node is dropped', () async {
      await journalRepository.upsertDraftInTransaction(
        await getDb(),
        resourceId: _resourceId,
        partId: _partId,
        content: '孤儿草稿',
        baseUpdatedAt: 'tok',
        now: DateTime.now().toIso8601String(),
      );
      await getDb().then(
        (db) => db.delete(
          'resource_parts',
          where: 'id = ?',
          whereArgs: <Object?>[_partId.value],
        ),
      );

      final outcomes = await autosave.reconcilePendingDrafts(
        resourceId: _resourceId,
      );

      expect(outcomes.single.disposition, AutosaveRecoveryDisposition.orphaned);
      expect(await journalRepository.countDrafts(_resourceId), 0);
      await autosave.dispose();
    });

    test('only one unresolved draft per node is ever stored', () async {
      final now = DateTime.now().toIso8601String();
      final db = await getDb();
      for (var i = 0; i < 3; i++) {
        await journalRepository.upsertDraftInTransaction(
          db,
          resourceId: _resourceId,
          partId: _partId,
          content: '版本 $i',
          baseUpdatedAt: 'tok',
          now: now,
        );
      }

      final drafts = await journalRepository.listDrafts(
        resourceId: _resourceId,
      );
      expect(drafts, hasLength(1));
      expect(drafts.single.content, '版本 2');
      await autosave.dispose();
    });

    test('reconciliation with an empty journal does nothing', () async {
      final outcomes = await autosave.reconcilePendingDrafts();
      expect(outcomes, isEmpty);
      await autosave.dispose();
    });
  });

  group('external conflict resolution (R2-M1)', () {
    Future<void> externalWrite(String content) async {
      await tree.updatePart(
        id: _partId,
        expectedUpdatedAt: await token(),
        content: content,
      );
    }

    test('external write → keep mine → same-session autosave recovers',
        () async {
      currentToken = await token();
      type('v1');
      await autosave.flush();
      expect(await liveContent(), 'v1');

      // Another writer (generation / restore / compression) replaces the body.
      await externalWrite('external-v2');

      // The user's next flush is refused and asks for an explicit decision.
      type('mine-v3');
      final conflict = await autosave.flush();
      expect(conflict.conflicted, 1);
      expect(conflict.outcomes.single.requiresUserResolution, isTrue);
      expect(
        await liveContent(),
        'external-v2',
        reason: 'the external content must not be auto-overwritten',
      );
      expect(await journalRepository.countDrafts(_resourceId), 1);

      // Typing more must not silently write either: the edit is held.
      type('mine-v3-revised');
      final held = await autosave.flush();
      expect(held.conflicted, 1);
      expect(held.outcomes.single.requiresUserResolution, isTrue);
      expect(await liveContent(), 'external-v2');
      expect(autosave.pendingCount, 1, reason: 'the held edit stays buffered');

      // The user chooses to keep their text.
      final resolved = await autosave.resolveConflictKeepMine(
        resourceId: _resourceId,
        partId: _partId,
        content: 'mine-v3-revised',
      );
      expect(resolved.persisted, isTrue);
      expect(await liveContent(), 'mine-v3-revised');
      expect(
        await journalRepository.countDrafts(_resourceId),
        0,
        reason: 'a resolved conflict consumes its journal row',
      );

      // The same session autosaves again without any conflict.
      type('v4');
      final next = await autosave.flush();
      expect(next.applied, 1);
      expect(next.conflicted, 0);
      expect(await liveContent(), 'v4');
      await autosave.dispose();
    });

    test('external write → discard mine → the live content is adopted',
        () async {
      currentToken = await token();
      type('v1');
      await autosave.flush();
      await externalWrite('external-v2');

      type('stale-draft');
      final conflict = await autosave.flush();
      expect(conflict.outcomes.single.requiresUserResolution, isTrue);

      final resolved = await autosave.resolveConflictDiscardMine(
        resourceId: _resourceId,
        partId: _partId,
      );
      expect(resolved.status, AutosaveWriteStatus.adoptedLive);
      expect(resolved.adoptedLiveContent, 'external-v2');
      expect(await liveContent(), 'external-v2');
      expect(
        await journalRepository.countDrafts(_resourceId),
        0,
        reason: 'discarding consumes the draft instead of stranding it',
      );
      expect(autosave.pendingCount, 0);

      // Editing continues normally afterwards.
      type('after-discard');
      final next = await autosave.flush();
      expect(next.applied, 1);
      expect(await liveContent(), 'after-discard');
      await autosave.dispose();
    });

    test('an external write between confirm and commit is refused again',
        () async {
      final racing = _RacingTreeBoundary(boundary);
      final raceAutosave = ResourceAutosaveService(
        journal: journal,
        committer: PartContentCommitService(
          treeBoundary: racing,
          validationBoundary: SectionControlRepositoryImpl(getDb: getDb),
          captureEngine: engine,
          autosaveRepository: journal,
          getDb: getDb,
          taskReset: PartGenerationTaskRepositoryImpl(getDb: getDb),
        ),
        treeBoundary: racing,
        getDb: getDb,
        debounce: fastDebounce,
        maxBufferedAge: const Duration(seconds: 2),
      );
      currentToken = await token();
      raceAutosave.schedule(
        resourceId: _resourceId,
        partId: _partId,
        content: 'v1',
        expectedUpdatedAt: currentToken,
      );
      await raceAutosave.flush();
      await externalWrite('external-v2');

      raceAutosave.schedule(
        resourceId: _resourceId,
        partId: _partId,
        content: 'mine-v3',
        expectedUpdatedAt: currentToken,
      );
      final conflict = await raceAutosave.flush();
      expect(conflict.outcomes.single.requiresUserResolution, isTrue);

      // The user confirms — and another writer lands between the session's
      // live read and its CAS commit.
      racing.raceContent = 'external-v3-race';
      final resolved = await raceAutosave.resolveConflictKeepMine(
        resourceId: _resourceId,
        partId: _partId,
        content: 'mine-v3',
      );
      expect(resolved.persisted, isFalse);
      expect(resolved.status, AutosaveWriteStatus.conflict);
      expect(resolved.requiresUserResolution, isTrue);
      expect(
        await liveContent(),
        'external-v3-race',
        reason: 'the second external write must not be overwritten',
      );
      expect(
        await journalRepository.countDrafts(_resourceId),
        1,
        reason: 'the draft stays durable across the second race',
      );

      // Once the race settles, the same resolution succeeds.
      final retry = await raceAutosave.resolveConflictKeepMine(
        resourceId: _resourceId,
        partId: _partId,
        content: 'mine-v3',
      );
      expect(retry.persisted, isTrue);
      expect(await liveContent(), 'mine-v3');
      expect(await journalRepository.countDrafts(_resourceId), 0);
      await raceAutosave.dispose();
      await autosave.dispose();
    });

    test('an unresolved conflict still recovers through editor reopen',
        () async {
      currentToken = await token();
      type('v1');
      await autosave.flush();
      await externalWrite('external-v2');
      type('unsaved-draft');
      await autosave.flush();

      // The user closes the editor without resolving.
      await autosave.dispose();
      expect(
        await journalRepository.countDrafts(_resourceId),
        1,
        reason: 'closing without a decision keeps the draft durable',
      );

      // A reopened editor classifies and offers the draft (crash recovery).
      final reopened = ResourceAutosaveService(
        journal: journal,
        committer: PartContentCommitService(
          treeBoundary: boundary,
          validationBoundary: SectionControlRepositoryImpl(getDb: getDb),
          captureEngine: engine,
          autosaveRepository: journal,
          getDb: getDb,
          taskReset: PartGenerationTaskRepositoryImpl(getDb: getDb),
        ),
        treeBoundary: boundary,
        getDb: getDb,
        debounce: fastDebounce,
        maxBufferedAge: const Duration(seconds: 2),
      );
      final outcomes = await reopened.reconcilePendingDrafts(
        resourceId: _resourceId,
      );
      expect(
        outcomes.single.disposition,
        AutosaveRecoveryDisposition.needsUserDecision,
      );
      expect(outcomes.single.draft.content, 'unsaved-draft');

      // Choosing to drop it restores a working session without a reopen.
      final discard = await reopened.resolveConflictDiscardMine(
        resourceId: _resourceId,
        partId: _partId,
      );
      expect(discard.status, AutosaveWriteStatus.adoptedLive);
      expect(await journalRepository.countDrafts(_resourceId), 0);
      reopened.schedule(
        resourceId: _resourceId,
        partId: _partId,
        content: 'fresh-after-reopen',
        expectedUpdatedAt: await token(),
      );
      final next = await reopened.flush();
      expect(next.applied, 1);
      expect(await liveContent(), 'fresh-after-reopen');
      await reopened.dispose();
    });
  });
}
