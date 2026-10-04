import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/part_content_commit_service.dart';
import 'package:lt_dialogue/application/resources/resource_autosave_repository.dart';
import 'package:lt_dialogue/application/resources/resource_autosave_service.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_service.dart';
import 'package:lt_dialogue/domain/resources/resource_autosave.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/section_control_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _resourceId = ResourceId('res_manual');
const _sectionId = SectionId('res_manual_sec_1');
const _partId = PartId('res_manual_sec_1_part_1');

/// Counts the journal writes the autosave path issues.
///
/// The manual Save button is only an explicit flush of the same session, so a
/// faithful "no duplicate write" assertion can count journal upserts/deletes:
/// one applied Part body is one upsert plus one draft delete.
final class _CountingJournal implements IResourceAutosaveRepository {
  _CountingJournal(this._inner);

  final IResourceAutosaveRepository _inner;

  int upserts = 0;
  int deletes = 0;

  /// Injects one journal failure, mirroring an I/O fault on the write path.
  bool throwOnNextUpsert = false;

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
    if (throwOnNextUpsert) {
      throwOnNextUpsert = false;
      return Future.error(StateError('injected journal failure'));
    }
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late ResourceTreeRepositoryImpl tree;
  late ResourceAutosaveRepositoryImpl journalRepository;
  late _CountingJournal journal;
  late ResourceAutosaveService autosave;

  const fastDebounce = Duration(milliseconds: 40);

  Future<Database> getDb() => DatabaseService.database;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_manual_save_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();

    tree = ResourceTreeRepositoryImpl(getDb: getDb);
    final revisions = ResourceRevisionRepositoryImpl(getDb: getDb);
    final engine = RevisionCaptureEngine(
      revisionRepository: revisions,
      treeBoundary: tree,
    );
    journalRepository = ResourceAutosaveRepositoryImpl(getDb: getDb);
    journal = _CountingJournal(journalRepository);

    final commitService = PartContentCommitService(
      treeBoundary: tree,
      validationBoundary: SectionControlRepositoryImpl(getDb: getDb),
      captureEngine: engine,
      autosaveRepository: journal,
      getDb: getDb,
      taskReset: PartGenerationTaskRepositoryImpl(getDb: getDb),
    );
    autosave = ResourceAutosaveService(
      journal: journal,
      committer: commitService,
      treeBoundary: tree,
      getDb: getDb,
      debounce: fastDebounce,
      maxBufferedAge: const Duration(seconds: 2),
    );

    await tree.createResourceTree(
      const ResourceTreeDraft(
        id: _resourceId,
        type: ResourceType.worldview,
        name: '手动保存测试',
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

  Future<String> liveContent() async =>
      (await tree.readParts(_sectionId)).single.content;

  Future<String> token() async =>
      (await tree.readNodeState(_partId))!.updatedAt;

  void type(String text, {String tokenOverride = ''}) {
    autosave.schedule(
      resourceId: _resourceId,
      partId: _partId,
      content: text,
      expectedUpdatedAt: tokenOverride,
    );
  }

  test('a manual flush persists the buffered body', () async {
    final startToken = await token();
    type('世界观正文 A', tokenOverride: startToken);

    final result = await autosave.flush(trigger: AutosaveFlushTrigger.manual);

    expect(result.applied, 1);
    expect(result.hasUnsavedConflict, isFalse);
    expect(await liveContent(), '世界观正文 A');
    expect(autosave.pendingCount, 0);
    expect(journal.upserts, 1);
    expect(journal.deletes, 1);
  });

  test('a repeated manual flush with nothing buffered writes nothing',
      () async {
    final startToken = await token();
    type('世界观正文 B', tokenOverride: startToken);
    await autosave.flush(trigger: AutosaveFlushTrigger.manual);

    final tokenAfterFirst = await token();
    final upsertsAfterFirst = journal.upserts;
    final deletesAfterFirst = journal.deletes;

    final second = await autosave.flush(trigger: AutosaveFlushTrigger.manual);

    expect(second.applied, 0);
    expect(second.hadWork, isFalse);
    expect(journal.upserts, upsertsAfterFirst,
        reason: 'a second save with no edits must not touch the journal');
    expect(journal.deletes, deletesAfterFirst);
    expect(await token(), tokenAfterFirst,
        reason: 'a no-op save must not bump the Part token');
    expect(await liveContent(), '世界观正文 B');
  });

  test('autosave debounce and a manual flush persist one body once', () async {
    final startToken = await token();
    type('世界观正文 C', tokenOverride: startToken);

    // Let the debounce checkpoint land on its own.
    await Future<void>.delayed(fastDebounce + const Duration(milliseconds: 80));
    expect(await liveContent(), '世界观正文 C');
    expect(autosave.pendingCount, 0);

    final upsertsAfterDebounce = journal.upserts;
    final tokenAfterDebounce = await token();

    final manual = await autosave.flush(trigger: AutosaveFlushTrigger.manual);

    expect(manual.applied, 0);
    expect(journal.upserts, upsertsAfterDebounce,
        reason: 'the manual flush must not re-write an already-persisted body');
    expect(await token(), tokenAfterDebounce);
    expect(await liveContent(), '世界观正文 C');
  });

  test('a failed manual flush keeps the edit pending', () async {
    final startToken = await token();
    type('世界观正文 D', tokenOverride: startToken);
    journal.throwOnNextUpsert = true;

    final result = await autosave.flush(trigger: AutosaveFlushTrigger.manual);

    expect(result.failed, 1);
    expect(result.applied, 0);
    expect(autosave.pendingCount, 1,
        reason: 'a refused write must stay buffered for a retry');
    expect(await liveContent(), '原始正文',
        reason: 'the failed save must not pretend the body was persisted');
  });
}
