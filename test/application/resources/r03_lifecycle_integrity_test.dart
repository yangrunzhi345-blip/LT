import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/compression_job_repository.dart';
import 'package:lt_dialogue/application/resources/legacy_library_row_purger.dart';
import 'package:lt_dialogue/application/resources/legacy_resource_mapper.dart';
import 'package:lt_dialogue/application/resources/resource_migration_service.dart';
import 'package:lt_dialogue/application/resources/resource_owned_state_purger.dart';
import 'package:lt_dialogue/application/resources/resource_revision_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_service.dart';
import 'package:lt_dialogue/application/resources/resource_trash_repository.dart';
import 'package:lt_dialogue/application/resources/resource_trash_service.dart';
import 'package:lt_dialogue/domain/resources/resource_compression.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_revision.dart';
import 'package:lt_dialogue/domain/resources/resource_trash.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// R03 — Resource Identity, Delete, Trash & Revision Lifecycle.
///
/// TG9 pins the lifecycle matrix of revision and child restore against real
/// SQLite; TG10 pins identity, soft delete, permanent delete (with its owned
/// auxiliary cascade) and retention. Every lifecycle operation here goes
/// through the production repositories — no mocks for the behaviour under
/// test.

const _resourceId = ResourceId('res_r03');
const _sectionA = SectionId('res_r03_sec_a');
const _sectionB = SectionId('res_r03_sec_b');
const _partA1 = PartId('res_r03_sec_a_part_1');
const _partA2 = PartId('res_r03_sec_a_part_2');
const _partB1 = PartId('res_r03_sec_b_part_1');

const _otherResourceId = ResourceId('res_r03_other');
const _otherSectionId = SectionId('res_r03_other_sec');
const _otherPartId = PartId('res_r03_other_sec_part_1');

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
  late CompressionJobRepositoryImpl compressionJobs;
  late ResourceMigrationService migrationService;

  Future<Database> getDb() => DatabaseService.database;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_r03_lifecycle_');
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
      legacyRowPort: LegacyLibraryRowPurger(getDb: getDb),
      ownedStatePort: ResourceOwnedStatePurger(),
    );
    compressionJobs = CompressionJobRepositoryImpl(getDb: getDb);
    migrationService = ResourceMigrationService(
      getDb: getDb,
      treeRepository: tree,
    );
    revisionService = ResourceRevisionService(
      revisionRepository: revisions,
      captureEngine: engine,
      treeBoundary: tree,
      getDb: getDb,
    );
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> seedTrees() async {
    await tree.createResourceTree(
      const ResourceTreeDraft(
        id: _resourceId,
        type: ResourceType.worldview,
        name: 'R03 资源',
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
    await tree.createResourceTree(
      const ResourceTreeDraft(
        id: _otherResourceId,
        type: ResourceType.character,
        name: 'R03 另一资源',
        sections: [
          ResourceTreeSectionDraft(
            id: _otherSectionId,
            title: '背景',
            parts: [
              ResourceTreePartDraft(
                id: _otherPartId,
                title: '来历',
                content: '另一资源的正文',
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

  /// Captures the current live state as a revision and returns its id.
  Future<String> captureHead(ResourceId resourceId) async {
    final db = await getDb();
    return db.transaction((txn) async {
      final revision = await engine.captureInTransaction(
        txn,
        resourceId: resourceId,
        cause: RevisionCause.manualSave,
        now: DateTime.now().toIso8601String(),
        label: 'R03 测试快照',
      );
      return revision!.revisionId.value;
    });
  }

  Future<int> countOf(String table, {String? resourceId}) async {
    final db = await getDb();
    final rows = resourceId == null
        ? await db.query(table)
        : await db
            .query(table, where: 'resource_id = ?', whereArgs: [resourceId]);
    return rows.length;
  }

  group('TG9 revision restore lifecycle', () {
    test(
        'a revision restore is refused while the resource sits in the bin '
        'and writes nothing', () async {
      await seedTrees();
      await captureHead(_resourceId);
      final revisionCountBefore = await countOf('resource_revisions');

      final deleted = await deleteNode(_resourceId);

      await expectLater(
        revisionService.restoreRevision(
          ResourceRevisionId(deleted.entry.revisionId),
        ),
        throwsA(
          isA<ResourceRevisionLifecycleException>()
              .having((e) => e.state, 'state', ResourceLifecycleState.trashed)
              .having((e) => e.resourceId, 'resourceId', _resourceId.value),
        ),
        reason: 'a revision must never be the side door out of the bin',
      );

      // Nothing was written: the row is still soft deleted, no new revision
      // was captured and the bin entry is still unresolved.
      final db = await getDb();
      final row = await db.query(
        'resources',
        where: 'id = ?',
        whereArgs: [_resourceId.value],
      );
      expect(row.single['deleted_at'], isNotNull);
      expect(await countOf('resource_revisions'), revisionCountBefore);
      final entry = await trashRepository.listEntries();
      expect(
          entry
              .where((e) => e.trashId == deleted.entry.trashId)
              .single
              .isRestored,
          isFalse);
    });

    test(
        'a purged resource takes its revision history with it, leaving no '
        'resurrection path', () async {
      await seedTrees();
      await captureHead(_resourceId);
      final deleted = await deleteNode(_resourceId);

      await trash.permanentDelete(deleted.entry.trashId);

      expect(
        await countOf('resource_revisions', resourceId: _resourceId.value),
        0,
        reason: 'the owned cascade removes the history with the resource',
      );
      await expectLater(
        revisionService.restoreRevision(
          ResourceRevisionId(deleted.entry.revisionId),
        ),
        throwsA(isA<ResourceRevisionNotFoundException>()),
      );
    });

    test('restoring a revision of a live resource still works', () async {
      await seedTrees();
      final head = await captureHead(_resourceId);
      await tree.updatePart(
        id: _partA1,
        expectedUpdatedAt: await tokenOf(_partA1),
        content: '被修改之后的正文',
      );
      await captureHead(_resourceId);

      final result = await revisionService.restoreRevision(
        ResourceRevisionId(head),
      );

      expect(result.alreadyAtRevision, isFalse);
      final parts = await tree.readParts(_sectionA);
      expect(
        parts.firstWhere((p) => p.id == _partA1).content,
        '第一章的正文一',
      );
    });

    test(
        'the explicit trash restore must come first; the revision restore '
        'then succeeds', () async {
      await seedTrees();
      await captureHead(_resourceId);
      final deleted = await deleteNode(_resourceId);

      await expectLater(
        revisionService.restoreRevision(
          ResourceRevisionId(deleted.entry.revisionId),
        ),
        throwsA(isA<ResourceRevisionLifecycleException>()),
      );

      await trash.restore(deleted.entry.trashId);

      final result = await revisionService.restoreRevision(
        ResourceRevisionId(deleted.entry.revisionId),
      );
      expect(result.alreadyAtRevision, isTrue,
          reason: 'the trash restore already brought back that exact state');
    });
  });

  group('TG9/CP-2 revision child belongs-to', () {
    RevisionNodeSnapshot resourceNode(ResourceId id) => RevisionNodeSnapshot(
          nodeId: id.value,
          kind: RevisionNodeKind.resource,
          parentNodeId: '',
          title: '根',
          sortOrder: 0,
        );

    test('a target section owned by another resource is refused', () async {
      await seedTrees();
      final db = await getDb();

      await expectLater(
        db.transaction((txn) => tree.applyRevisionState(
              txn,
              resourceId: _resourceId,
              target: <String, RevisionNodeSnapshot>{
                _resourceId.value: resourceNode(_resourceId),
                _otherSectionId.value: RevisionNodeSnapshot(
                  nodeId: _otherSectionId.value,
                  kind: RevisionNodeKind.section,
                  parentNodeId: _resourceId.value,
                  title: '外来章节',
                  sortOrder: 0,
                ),
              },
              now: DateTime.now().toIso8601String(),
            )),
        throwsA(isA<ResourceTreeConflictException>()),
      );
    });

    test('a target part owned by another resource is refused', () async {
      await seedTrees();
      final db = await getDb();

      await expectLater(
        db.transaction((txn) => tree.applyRevisionState(
              txn,
              resourceId: _resourceId,
              target: <String, RevisionNodeSnapshot>{
                _resourceId.value: resourceNode(_resourceId),
                _otherPartId.value: RevisionNodeSnapshot(
                  nodeId: _otherPartId.value,
                  kind: RevisionNodeKind.part,
                  parentNodeId: _sectionA.value,
                  title: '外来正文',
                  content: '不应落库',
                  sortOrder: 0,
                ),
              },
              now: DateTime.now().toIso8601String(),
            )),
        throwsA(isA<ResourceTreeConflictException>()),
      );
    });

    test(
        'a part whose target section belongs to another resource is '
        'refused', () async {
      await seedTrees();
      final db = await getDb();

      await expectLater(
        db.transaction((txn) => tree.applyRevisionState(
              txn,
              resourceId: _resourceId,
              target: <String, RevisionNodeSnapshot>{
                _resourceId.value: resourceNode(_resourceId),
                _partA1.value: RevisionNodeSnapshot(
                  nodeId: _partA1.value,
                  kind: RevisionNodeKind.part,
                  parentNodeId: _otherSectionId.value,
                  title: '开场',
                  content: '第一章的正文一',
                  sortOrder: 0,
                ),
              },
              now: DateTime.now().toIso8601String(),
            )),
        throwsA(isA<ResourceTreeConflictException>()),
      );
    });
  });

  group('TG9 child restore parent state', () {
    test(
        'a section cannot be restored while its resource is still in the '
        'bin; after the resource is restored it can', () async {
      await seedTrees();
      final sectionDelete = await deleteNode(_sectionA);
      await deleteNode(_resourceId);

      await expectLater(
        trash.restore(sectionDelete.entry.trashId),
        throwsA(isA<ResourceTrashConflictException>()),
        reason: 'restoring a child under a binned parent creates a dangling '
            'node; the parent must be restored first',
      );
      expect(
        (await trashRepository.listEntries())
            .where((e) => e.trashId == sectionDelete.entry.trashId)
            .single
            .isRestored,
        isFalse,
      );

      final resourceEntry = (await trashRepository.listEntries())
          .where((e) => e.nodeId == _resourceId.value && !e.isRestored)
          .single;
      await trash.restore(resourceEntry.trashId);
      await trash.restore(sectionDelete.entry.trashId);

      final sections = await tree.readSections(_resourceId);
      expect(
        sections.map((s) => s.id.value),
        containsAll(<String>[_sectionA.value, _sectionB.value]),
      );
    });
  });

  group('TG10 permanent delete cascade', () {
    /// Seeds one row in every owned auxiliary table of [_resourceId], plus a
    /// creation-session tombstone that must survive the purge.
    Future<void> seedAuxiliaryRows() async {
      final db = await getDb();
      await captureHead(_resourceId);
      await tree.updatePart(
        id: _partA1,
        expectedUpdatedAt: await tokenOf(_partA1),
        content: '第二版正文',
      );
      await captureHead(_resourceId);

      final token = await tokenOf(_partA1);
      await db.transaction((txn) => txn.insert('resource_autosaves', {
            'checkpoint_id': 'ckpt_r03',
            'resource_id': _resourceId.value,
            'node_id': _partA1.value,
            'node_kind': 'part',
            'content': '未保存的草稿',
            'base_updated_at': token,
            'created_at': '2026-09-19T00:00:00.000',
            'updated_at': '2026-09-19T00:00:00.000',
          }));

      await compressionJobs.insertJob(CompressionJob(
        jobId: 'job_r03',
        resourceId: _resourceId,
        scope: CompressionScope.part,
        targetNodeId: _partA1.value,
        parentNodeId: _sectionA.value,
        sourceToken: token,
        status: CompressionJobStatus.succeeded,
        attempts: 1,
        maxAttempts: 2,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ));

      await db.insert('resource_blueprints', {
        'blueprint_id': 'bp_r03',
        'session_id': 'cs_r03',
        'resource_type': 'worldview',
        'resource_id': _resourceId.value,
        'created_at': '2026-09-19T00:00:00.000',
        'updated_at': '2026-09-19T00:00:00.000',
      });
      await db.insert('resource_generation_tasks', {
        'task_id': 'task_r03',
        'blueprint_id': 'bp_r03',
        'resource_id': _resourceId.value,
        'section_id': _sectionA.value,
        'part_id': _partA1.value,
        'created_at': '2026-09-19T00:00:00.000',
        'updated_at': '2026-09-19T00:00:00.000',
      });
      await db.insert('resource_generation_attempts', {
        'attempt_id': 'att_r03',
        'task_id': 'task_r03',
        'generation_id': 'gen_r03',
        'part_id': _partA1.value,
        'created_at': '2026-09-19T00:00:00.000',
        'updated_at': '2026-09-19T00:00:00.000',
      });
      await db.insert('resource_generation_sessions', {
        'session_id': 'gs_r03',
        'resource_id': _resourceId.value,
        'blueprint_id': 'bp_r03',
        'status': 'completed',
        'created_at': '2026-09-19T00:00:00.000',
        'updated_at': '2026-09-19T00:00:00.000',
      });
      await db.insert('resource_assembly_readiness', {
        'resource_id': _resourceId.value,
        'updated_at': '2026-09-19T00:00:00.000',
      });
      await db.insert('resource_assembly_entries', {
        'entry_id': 'entry_r03',
        'resource_id': _resourceId.value,
        'revision_id': 'rev_missing_after_purge',
        'revision_content_hash': 'h',
        'content': '{}',
        'created_at': '2026-09-19T00:00:00.000',
      });
      // The tombstone: consumed idempotency keys must keep blocking reuse
      // even after the resource is gone.
      await db.insert('resource_creation_sessions', {
        'session_id': 'cs_r03',
        'idempotency_key': 'idem_r03',
        'resource_type': 'worldview',
        'method': 'manual',
        'resource_id': _resourceId.value,
        'created_at': '2026-09-19T00:00:00.000',
        'updated_at': '2026-09-19T00:00:00.000',
      });
    }

    test(
        'a resource purge discharges every owned auxiliary row in one '
        'transaction and keeps the tombstone', () async {
      await seedTrees();
      await seedAuxiliaryRows();
      final deleted = await deleteNode(_resourceId);

      final result = await trash.permanentDelete(deleted.entry.trashId);

      expect(result.alreadyGone, isFalse);
      expect(await countOf('resource_revisions'), 0);
      expect(await countOf('resource_autosaves'), 0);
      expect(await countOf('resource_compression_jobs'), 0);
      expect(await countOf('resource_compression_candidates'), 0);
      expect(await countOf('resource_generation_tasks'), 0);
      expect(await countOf('resource_generation_attempts'), 0);
      expect(await countOf('resource_generation_sessions'), 0);
      expect(await countOf('resource_blueprints'), 0);
      expect(await countOf('resource_assembly_readiness'), 0);
      expect(await countOf('resource_assembly_entries'), 0);
      expect(
        await countOf('resource_creation_sessions'),
        1,
        reason: 'the consumed idempotency key is a deliberate tombstone',
      );
      // The other resource is untouched.
      expect(
        await tree.readParts(_otherSectionId),
        hasLength(1),
      );
    });

    test('purging a single part only removes node-scoped auxiliary rows',
        () async {
      await seedTrees();
      final db = await getDb();
      await captureHead(_resourceId);
      final token = await tokenOf(_partA1);
      await db.transaction((txn) => txn.insert('resource_autosaves', {
            'checkpoint_id': 'ckpt_part',
            'resource_id': _resourceId.value,
            'node_id': _partA1.value,
            'node_kind': 'part',
            'content': '草稿',
            'base_updated_at': token,
            'created_at': '2026-09-19T00:00:00.000',
            'updated_at': '2026-09-19T00:00:00.000',
          }));
      await compressionJobs.insertJob(CompressionJob(
        jobId: 'job_part',
        resourceId: _resourceId,
        scope: CompressionScope.part,
        targetNodeId: _partA1.value,
        parentNodeId: _sectionA.value,
        sourceToken: token,
        status: CompressionJobStatus.succeeded,
        attempts: 1,
        maxAttempts: 2,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ));

      final deleted = await deleteNode(_partA1);
      await trash.permanentDelete(deleted.entry.trashId);

      expect(await countOf('resource_autosaves'), 0);
      expect(await countOf('resource_compression_jobs'), 0);
      expect(
        await countOf('resource_revisions', resourceId: _resourceId.value),
        greaterThanOrEqualTo(1),
        reason: 'the resource is still live; its history stays',
      );
      expect(await tree.readParts(_sectionA), hasLength(1));
    });

    test(
        'purging a section removes descendant part drafts and generation '
        'tasks without touching siblings', () async {
      await seedTrees();
      final db = await getDb();
      final partIds = <PartId>[_partA1, _partA2, _partB1, _otherPartId];
      for (final partId in partIds) {
        await db.insert('resource_autosaves', {
          'checkpoint_id': 'ckpt_${partId.value}',
          'resource_id': partId == _otherPartId
              ? _otherResourceId.value
              : _resourceId.value,
          'node_id': partId.value,
          'node_kind': 'part',
          'content': 'draft ${partId.value}',
          'base_updated_at': await tokenOf(partId),
          'created_at': '2026-09-19T00:00:00.000',
          'updated_at': '2026-09-19T00:00:00.000',
        });
      }
      await db.insert('resource_blueprints', {
        'blueprint_id': 'bp_section_purge',
        'session_id': 'cs_section_purge',
        'resource_type': 'worldview',
        'resource_id': _resourceId.value,
        'created_at': '2026-09-19T00:00:00.000',
        'updated_at': '2026-09-19T00:00:00.000',
      });
      await db.insert('resource_blueprints', {
        'blueprint_id': 'bp_other_section_purge',
        'session_id': 'cs_other_section_purge',
        'resource_type': 'character',
        'resource_id': _otherResourceId.value,
        'created_at': '2026-09-19T00:00:00.000',
        'updated_at': '2026-09-19T00:00:00.000',
      });
      for (final partId in partIds) {
        final isOther = partId == _otherPartId;
        final sectionId = switch (partId) {
          _partA1 || _partA2 => _sectionA.value,
          _partB1 => _sectionB.value,
          _ => _otherSectionId.value,
        };
        await db.insert('resource_generation_tasks', {
          'task_id': 'task_${partId.value}',
          'blueprint_id':
              isOther ? 'bp_other_section_purge' : 'bp_section_purge',
          'resource_id': isOther ? _otherResourceId.value : _resourceId.value,
          'section_id': sectionId,
          'part_id': partId.value,
          'created_at': '2026-09-19T00:00:00.000',
          'updated_at': '2026-09-19T00:00:00.000',
        });
      }

      final deleted = await deleteNode(_sectionA);
      final first = await trash.permanentDelete(deleted.entry.trashId);
      final second = await trash.permanentDelete(deleted.entry.trashId);

      expect(first.alreadyGone, isFalse);
      expect(second.alreadyGone, isTrue);
      final remainingDrafts = await db.query(
        'resource_autosaves',
        columns: const ['node_id'],
        orderBy: 'node_id',
      );
      final remainingTasks = await db.query(
        'resource_generation_tasks',
        columns: const ['part_id'],
        orderBy: 'part_id',
      );
      expect(
        remainingDrafts.map((row) => row['node_id']),
        [_otherPartId.value, _partB1.value],
      );
      expect(
        remainingTasks.map((row) => row['part_id']),
        [_otherPartId.value, _partB1.value],
      );
      expect(await tree.readParts(_sectionB), hasLength(1));
      expect(await tree.readParts(_otherSectionId), hasLength(1));
    });

    test('a purge failure rolls the whole transaction back', () async {
      await seedTrees();
      await seedAuxiliaryRows();
      final deleted = await deleteNode(_resourceId);
      final failingTrash = ResourceTrashService(
        repository: trashRepository,
        treeBoundary: tree,
        captureEngine: engine,
        getDb: getDb,
        ownedStatePort: const _ExplodingOwnedStatePort(),
      );

      await expectLater(
        failingTrash.permanentDelete(deleted.entry.trashId),
        throwsA(isA<ResourceTrashException>()),
      );

      // Nothing was discharged: the bin entry, the soft deleted rows and all
      // auxiliary state are exactly as they were before the purge attempt.
      expect(
        (await trashRepository.listEntries())
            .where((e) => e.trashId == deleted.entry.trashId)
            .single
            .isRestored,
        isFalse,
      );
      final db = await getDb();
      final row = await db.query(
        'resources',
        where: 'id = ?',
        whereArgs: [_resourceId.value],
      );
      expect(row.single['deleted_at'], isNotNull);
      expect(await countOf('resource_revisions'), greaterThanOrEqualTo(1));
      expect(await countOf('resource_autosaves'), 1);
    });

    test('retention purge is idempotent and discharges the same ownership',
        () async {
      await seedTrees();
      await seedAuxiliaryRows();
      final deleted = await deleteNode(_resourceId);
      // Force the retention window to be over.
      final db = await getDb();
      await db.update(
        'resource_trash',
        {'expires_at': '2026-01-01T00:00:00.000'},
        where: 'trash_id = ?',
        whereArgs: [deleted.entry.trashId],
      );

      expect(await trash.purgeExpired(), 1);
      expect(await countOf('resource_revisions'), 0);
      expect(await countOf('resource_autosaves'), 0);

      // A second pass finds nothing left to do.
      expect(await trash.purgeExpired(), 0);
    });
  });

  group('TG10 identity', () {
    Future<void> insertLegacyWorldview(String id, String name) async {
      final db = await getDb();
      await db.insert('worldview_presets', {
        'id': id,
        'name': name,
        'description': '$name 的描述',
        'entries_json': '[]',
        'detail_json':
            '{"format_version":2,"mode":"simple","modules":{"overview":'
                '{"summary":"$name 的描述","status":"confirmed"}}}',
        'created_at': '2026-09-15T00:00:00.000',
        'updated_at': '2026-09-15T00:00:00.000',
      });
    }

    test(
        're-running the migration is idempotent: one mapped pair, no '
        'duplicate tree', () async {
      await insertLegacyWorldview('preset_1', '第一个预设');

      final first = await migrationService.run();
      expect(first.migrated, 1);

      final second = await migrationService.run();
      expect(second.migrated, 0);
      expect(second.skipped, 1);

      final expectedId =
          LegacyResourceMapper.resourceIdFor('worldview_presets', 'preset_1');
      expect(await tree.readNodeState(expectedId), isNotNull);
      expect(await countOf('resource_migration_records'), 1);
    });

    test(
        'a permanently deleted resource does not resurrect through a later '
        'migration run', () async {
      await insertLegacyWorldview('preset_2', '要被删除的预设');
      await migrationService.run();
      final treeId =
          LegacyResourceMapper.resourceIdFor('worldview_presets', 'preset_2');

      // Delete through the production trash path and purge permanently.
      final deleted = await deleteNode(treeId);
      await trash.permanentDelete(deleted.entry.trashId);
      expect(await tree.readNodeState(treeId), isNull);

      final stats = await migrationService.run();

      expect(stats.migrated, 0,
          reason: 'the succeeded record must not re-create the tree');
      expect(await tree.readNodeState(treeId), isNull,
          reason: 'the legacy row and its tree copy are both gone; the '
              'migration record alone must not resurrect anything');
    });
  });
}

/// An [IResourceOwnedStatePort] that always throws — the transactional
/// rollback probe for the permanent delete.
final class _ExplodingOwnedStatePort implements IResourceOwnedStatePort {
  const _ExplodingOwnedStatePort();

  @override
  Future<void> purgeOwnedStateInTransaction(
    DatabaseExecutor txn, {
    required String resourceId,
    String? nodeId,
  }) async {
    throw const ResourceTrashException('注入的附属状态清理失败');
  }
}
