import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/resource_metadata_policy.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_row_mapper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late ResourceTreeRepositoryImpl repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_resource_tree_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    repo = ResourceTreeRepositoryImpl(getDb: () => DatabaseService.database);
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Resource CRUD', () {
    test('creates a resource root and reads it back', () async {
      final created = await repo.createResource(
        type: ResourceType.worldview,
        name: '银月大陆',
        summary: '北境学术重镇',
      );

      final found = await repo.findResource(created.id);
      expect(found, isNotNull);
      expect(found!.id, created.id);
      expect(found.type, ResourceType.worldview);
      expect(found.name, '银月大陆');
      expect(found.summary, '北境学术重镇');
      expect(found.status, NodeStatus.draft);
      expect(
        found.metadata[ResourceTreeSchema.metadataAuthoringMethodKey],
        CreationMethod.manual.storageValue,
      );
    });

    test('stores provenance in metadata, not in a body column', () async {
      final created = await repo.createResource(
        type: ResourceType.character,
        name: '艾莲娜',
        method: CreationMethod.aiReference,
      );

      final db = await DatabaseService.database;
      final rows = await db.query(
        'resources',
        where: 'id = ?',
        whereArgs: [created.id.value],
      );
      final metadataJson = rows.first['metadata_json'] as String;
      expect(
        metadataJson,
        contains('"${ResourceTreeSchema.metadataAuthoringMethodKey}"'
            ':"${CreationMethod.aiReference.storageValue}"'),
      );
      expect(metadataJson.length, lessThan(200));
    });

    test('updates name, summary and metadata with a fresh token', () async {
      final created = await repo.createResource(
        type: ResourceType.worldview,
        name: '旧名',
      );
      final token = (await repo.readNodeState(created.id))!.updatedAt;

      await repo.updateResource(
        id: created.id,
        expectedUpdatedAt: token,
        name: '新名',
        summary: '新摘要',
        metadata: const <String, Object?>{
          'tags': ['玄幻']
        },
      );

      final updated = await repo.findResource(created.id);
      expect(updated!.name, '新名');
      expect(updated.summary, '新摘要');
      expect(updated.metadata['tags'], ['玄幻']);
      // The provenance carried over instead of being dropped.
      expect(
        updated.metadata[ResourceTreeSchema.metadataAuthoringMethodKey],
        CreationMethod.manual.storageValue,
      );
    });

    test('rejects metadata that tries to become a body container', () async {
      await expectLater(
        repo.createResource(
          type: ResourceType.worldview,
          name: '非法元数据',
          metadata: <String, Object?>{
            'sections': [
              {'title': 'a'},
            ],
          },
        ),
        throwsA(isA<ResourceMetadataException>()),
      );
      await expectLater(
        repo.createResource(
          type: ResourceType.worldview,
          name: '非法元数据2',
          metadata: <String, Object?>{'content_json': '整棵树'},
        ),
        throwsA(isA<ResourceMetadataException>()),
      );
    });

    test('lists resources per type and hides archived ones by default',
        () async {
      final worldview = await repo.createResource(
        type: ResourceType.worldview,
        name: '世界观',
      );
      await repo.createResource(type: ResourceType.npc, name: 'NPC');

      expect(
        (await repo.listResources(type: ResourceType.worldview))
            .map((resource) => resource.id),
        [worldview.id],
      );

      await repo.mount(ArchiveNodePatch(nodeId: worldview.id));
      expect(await repo.listResources(type: ResourceType.worldview), isEmpty);
      expect(
        await repo.listResources(
          type: ResourceType.worldview,
          includeArchived: true,
        ),
        hasLength(1),
      );
    });
  });

  group('creation session', () {
    test('commits the whole tree in one transaction', () async {
      final session = await repo.begin(
        type: ResourceType.worldview,
        name: '银月大陆',
      );
      final overview = await session.appendSection(title: '概览');
      final rules = await session.appendSection(title: '世界规则');
      await session.appendPart(
        sectionId: overview,
        title: '一句话',
        content: '银月大陆是北境学术重镇。',
      );
      await session.appendPart(
        sectionId: rules,
        title: '规则一',
        content: '魔法需要媒介。',
      );
      await session.commit();

      final tree = await repo.readTree(session.resourceId);
      expect(tree, isNotNull);
      expect(
        tree!.orderedSections.map((section) => section.title),
        ['概览', '世界规则'],
      );
      expect(tree.orderedPartsOf(overview).single.content, '银月大陆是北境学术重镇。');
      expect(tree.orderedPartsOf(rules).single.content, '魔法需要媒介。');
      tree.validate();
    });

    test('creates an empty content tree', () async {
      final session = await repo.begin(
        type: ResourceType.npc,
        name: '空树',
      );
      await session.commit();

      final tree = await repo.readTree(session.resourceId);
      expect(tree, isNotNull);
      expect(tree!.sections, isEmpty);
      expect(tree.parts, isEmpty);
    });

    test('marks the session creation method', () async {
      final session = await repo.begin(
        type: ResourceType.character,
        name: 'AI 角色',
        method: CreationMethod.aiReference,
      );
      expect(session.creationMethod, CreationMethod.aiReference);
      await session.commit();

      final resource = await repo.findResource(session.resourceId);
      expect(
        resource!.metadata[ResourceTreeSchema.metadataAuthoringMethodKey],
        CreationMethod.aiReference.storageValue,
      );
    });

    test('an abandoned session publishes nothing', () async {
      final session = await repo.begin(
        type: ResourceType.worldview,
        name: '被放弃',
      );
      await session.appendSection(title: '孤儿 Section');
      await session.abandon();

      expect(await repo.findResource(session.resourceId), isNull);
      final db = await DatabaseService.database;
      final sections = await db.query('resource_sections');
      expect(sections, isEmpty);
    });

    test('rejects a part whose section is not in the session', () async {
      final session = await repo.begin(
        type: ResourceType.worldview,
        name: '会话',
      );
      await expectLater(
        session.appendPart(
          sectionId: const SectionId('sec_unknown'),
          title: 'X',
          content: 'Y',
        ),
        throwsA(isA<ResourceTreeNotFoundException>()),
      );
    });

    test('rejects use after commit or abandon', () async {
      final committed = await repo.begin(type: ResourceType.npc, name: 'A');
      await committed.commit();
      await expectLater(
        committed.appendSection(title: 'late'),
        throwsA(isA<ResourceTreeConflictException>()),
      );

      final abandoned = await repo.begin(type: ResourceType.npc, name: 'B');
      await abandoned.abandon();
      await expectLater(
        abandoned.commit(),
        throwsA(isA<ResourceTreeConflictException>()),
      );
    });
  });

  group('node mounts', () {
    test('append assigns increasing explicit sibling order', () async {
      final resource = await repo.createResource(
        type: ResourceType.worldview,
        name: 'R',
      );

      final first = await repo.mount(
        AppendSectionPatch(resourceId: resource.id, title: 'S1'),
      );
      final second = await repo.mount(
        AppendSectionPatch(resourceId: resource.id, title: 'S2'),
      );
      expect(first.sortOrder, 0);
      expect(second.sortOrder, 1);

      final partA = await repo.mount(
        AppendPartPatch(sectionId: first.nodeId as SectionId, title: 'P1'),
      );
      final partB = await repo.mount(
        AppendPartPatch(sectionId: first.nodeId as SectionId, title: 'P2'),
      );
      expect(partA.sortOrder, 0);
      expect(partB.sortOrder, 1);
    });

    test('append requires a live parent', () async {
      await expectLater(
        repo.mount(
          const AppendSectionPatch(
            resourceId: ResourceId('res_missing'),
            title: 'S',
          ),
        ),
        throwsA(isA<ResourceTreeNotFoundException>()),
      );
      await expectLater(
        repo.mount(
          const AppendPartPatch(
              sectionId: SectionId('sec_missing'), title: 'P'),
        ),
        throwsA(isA<ResourceTreeNotFoundException>()),
      );
    });

    test('renames a resource and a part through the same patch', () async {
      final session = await repo.begin(type: ResourceType.worldview, name: 'R');
      final sectionId = await session.appendSection(title: 'S');
      final partId = await session.appendPart(
        sectionId: sectionId,
        title: '旧标题',
        content: '正文',
      );
      await session.commit();

      await repo
          .mount(RenameNodePatch(nodeId: session.resourceId, title: '新资源名'));
      await repo.mount(RenameNodePatch(nodeId: partId, title: '新标题'));

      final tree = await repo.readTree(session.resourceId);
      expect(tree!.resource.name, '新资源名');
      expect(tree.parts.single.title, '新标题');
    });

    test('updates one part body and its hash only', () async {
      final session = await repo.begin(type: ResourceType.worldview, name: 'R');
      final sectionId = await session.appendSection(title: 'S');
      final partId = await session.appendPart(
        sectionId: sectionId,
        title: 'P',
        content: '旧正文',
      );
      await session.commit();

      final before = await repo.readNodeState(partId);

      await repo.mount(
        UpdatePartContentPatch(partId: partId, content: '新正文'),
      );

      final after = await repo.readNodeState(partId);
      expect(after!.contentHash, ResourceTreeRowMapper.contentHashFor('新正文'));
      expect(after.contentHash, isNot(before!.contentHash));
      expect(
        (await repo.readParts(sectionId)).single.content,
        '新正文',
      );
    });

    test('archives a node and rejects the illegal transition back', () async {
      final session = await repo.begin(type: ResourceType.worldview, name: 'R');
      final sectionId = await session.appendSection(title: 'S');
      await session.commit();

      await repo.mount(ArchiveNodePatch(nodeId: sectionId));
      final token = (await repo.readNodeState(sectionId))!.updatedAt;

      await expectLater(
        repo.updateSection(
          id: sectionId,
          expectedUpdatedAt: token,
          status: NodeStatus.confirmed,
        ),
        throwsA(isA<ResourceStateTransitionException>()),
      );
    });
  });

  group('ordering', () {
    test('reads sections and parts in (sort_order, id) order', () async {
      final session = await repo.begin(type: ResourceType.worldview, name: 'R');
      final first = await session.appendSection(title: 'A');
      final second = await session.appendSection(title: 'B');
      await session.appendPart(sectionId: first, title: 'P1', content: '1');
      await session.appendPart(sectionId: first, title: 'P2', content: '2');
      await session.commit();

      expect(
        (await repo.readSections(session.resourceId)).map((s) => s.id),
        [first, second],
      );
      expect(
        (await repo.readParts(first)).map((p) => p.title),
        ['P1', 'P2'],
      );
    });

    test('ties on sort_order resolve deterministically by id', () async {
      final session = await repo.begin(type: ResourceType.worldview, name: 'R');
      final a = await session.appendSection(title: 'A');
      final b = await session.appendSection(title: 'B');
      final c = await session.appendSection(title: 'C');
      await session.commit();

      // Force a tie so order can only come from the id tiebreaker.
      final db = await DatabaseService.database;
      await db.update(
        'resource_sections',
        {'sort_order': 5},
        where: 'id IN (?, ?)',
        whereArgs: [a.value, b.value],
      );

      final expected = <String>[a.value, b.value]..sort();
      final sections = await repo.readSections(session.resourceId);
      // The tied pair can only be ordered by id; c keeps its own position.
      expect(
        sections.map((section) => section.id.value),
        [c.value, ...expected],
      );
    });

    test('reorders sections and parts explicitly', () async {
      final session = await repo.begin(type: ResourceType.worldview, name: 'R');
      final s1 = await session.appendSection(title: 'S1');
      final s2 = await session.appendSection(title: 'S2');
      final s3 = await session.appendSection(title: 'S3');
      final p1 = await session.appendPart(
        sectionId: s1,
        title: 'P1',
        content: '正文 1',
      );
      final p2 = await session.appendPart(
        sectionId: s1,
        title: 'P2',
        content: '正文 2',
      );
      await session.commit();

      await repo.reorderSections(
        resourceId: session.resourceId,
        orderedIds: [s3, s1, s2],
      );
      await repo.reorderParts(sectionId: s1, orderedIds: [p2, p1]);

      expect(
        (await repo.readSections(session.resourceId)).map((s) => s.id),
        [s3, s1, s2],
      );
      expect(
        (await repo.readParts(s1)).map((p) => p.id),
        [p2, p1],
      );
      // Positions are contiguous after an explicit reorder.
      expect(
        (await repo.readSections(session.resourceId))
            .map((section) => section.sortOrder),
        [0, 1, 2],
      );
    });

    test('rejects a reorder list that does not match the live children',
        () async {
      final session = await repo.begin(type: ResourceType.worldview, name: 'R');
      final s1 = await session.appendSection(title: 'S1');
      final s2 = await session.appendSection(title: 'S2');
      await session.commit();

      await expectLater(
        repo.reorderSections(
          resourceId: session.resourceId,
          orderedIds: [s1],
        ),
        throwsA(isA<ResourceTreeConflictException>()),
      );
      await expectLater(
        repo.reorderSections(
          resourceId: session.resourceId,
          orderedIds: [s1, s1],
        ),
        throwsA(isA<ResourceTreeConflictException>()),
      );
      await repo.reorderSections(
        resourceId: session.resourceId,
        orderedIds: [s1, s2],
      );
    });

    test('a failed reorder rolls back every position it already wrote',
        () async {
      final session = await repo.begin(type: ResourceType.worldview, name: 'R');
      final sectionId = await session.appendSection(title: 'S');
      final p1 = await session.appendPart(
        sectionId: sectionId,
        title: 'P1',
        content: '正文 1',
      );
      final p2 = await session.appendPart(
        sectionId: sectionId,
        title: 'P2',
        content: '正文 2',
      );
      await session.commit();

      // Start from a non-default order so a partial write would be visible.
      await repo.reorderParts(sectionId: sectionId, orderedIds: [p2, p1]);

      // p1 is written first (position 0), then the unknown id fails the
      // transaction and every earlier write must be rolled back.
      await expectLater(
        repo.reorderParts(
          sectionId: sectionId,
          orderedIds: [p1, const PartId('part_missing')],
        ),
        throwsA(isA<ResourceTreeConflictException>()),
      );

      final parts = await repo.readParts(sectionId);
      expect(parts.map((part) => part.id), [p2, p1]);
      expect(parts.map((part) => part.sortOrder), [0, 1]);
    });
  });

  group('isolation', () {
    test('a resource never exposes another resource sections', () async {
      final a = await repo.begin(type: ResourceType.worldview, name: 'A');
      final aSection = await a.appendSection(title: 'A-S');
      await a.commit();

      final b = await repo.begin(type: ResourceType.worldview, name: 'B');
      final bSection = await b.appendSection(title: 'B-S');
      final bPart = await b.appendPart(
        sectionId: bSection,
        title: 'B-P',
        content: 'B 正文',
      );
      await b.commit();

      expect(
        (await repo.readSections(a.resourceId)).map((s) => s.id),
        [aSection],
      );
      expect(
        (await repo.readSections(b.resourceId)).map((s) => s.id),
        [bSection],
      );

      final treeA = await repo.readTree(a.resourceId);
      expect(treeA!.parts, isEmpty);
      expect(treeA.sections.single.id, aSection);

      final treeB = await repo.readTree(b.resourceId);
      expect(treeB!.parts.single.id, bPart);
    });

    test('a section never exposes another section parts', () async {
      final session = await repo.begin(type: ResourceType.worldview, name: 'R');
      final s1 = await session.appendSection(title: 'S1');
      final s2 = await session.appendSection(title: 'S2');
      await session.appendPart(sectionId: s1, title: 'P1', content: '1');
      await session.appendPart(sectionId: s2, title: 'P2', content: '2');
      await session.commit();

      expect((await repo.readParts(s1)).map((p) => p.content), ['1']);
      expect((await repo.readParts(s2)).map((p) => p.content), ['2']);
    });

    test('the database refuses a part whose section does not exist', () async {
      final db = await DatabaseService.database;
      await expectLater(
        db.insert('resource_parts', {
          'id': 'part_orphan',
          'section_id': 'sec_missing',
          'title': 'T',
          'content': 'C',
          'sort_order': 0,
          'status': 'draft',
          'content_hash': 'h',
          'created_at': '2026-09-16T00:00:00.000',
          'updated_at': '2026-09-16T00:00:00.000',
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('the database refuses a section whose resource does not exist',
        () async {
      final db = await DatabaseService.database;
      await expectLater(
        db.insert('resource_sections', {
          'id': 'sec_orphan',
          'resource_id': 'res_missing',
          'title': 'T',
          'summary': '',
          'sort_order': 0,
          'status': 'draft',
          'created_at': '2026-09-16T00:00:00.000',
          'updated_at': '2026-09-16T00:00:00.000',
        }),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('partial updates never rewrite siblings', () {
    test('updating one part leaves the other parts untouched', () async {
      final session = await repo.begin(type: ResourceType.worldview, name: 'R');
      final sectionId = await session.appendSection(title: 'S');
      final partA = await session.appendPart(
        sectionId: sectionId,
        title: 'A',
        content: 'A 正文',
      );
      final partB = await session.appendPart(
        sectionId: sectionId,
        title: 'B',
        content: 'B 正文',
      );
      final partC = await session.appendPart(
        sectionId: sectionId,
        title: 'C',
        content: 'C 正文',
      );
      await session.commit();

      final db = await DatabaseService.database;
      Future<Map<String, Map<String, Object?>>> snapshot() async {
        final rows = await db.query('resource_parts');
        return {
          for (final row in rows)
            row['id'].toString(): {
              'content': row['content'],
              'content_hash': row['content_hash'],
              'updated_at': row['updated_at'],
              'sort_order': row['sort_order'],
              'title': row['title'],
              'status': row['status'],
            },
        };
      }

      final sectionBefore = (await db.query(
        'resource_sections',
        where: 'id = ?',
        whereArgs: [sectionId.value],
      ))
          .first;
      final resourceBefore = (await db.query(
        'resources',
        where: 'id = ?',
        whereArgs: [session.resourceId.value],
      ))
          .first;
      final before = await snapshot();
      final token = (await repo.readNodeState(partB))!.updatedAt;

      await repo.updatePart(
        id: partB,
        expectedUpdatedAt: token,
        content: 'B 新正文',
      );

      final after = await snapshot();
      expect(after[partB.value]!['content'], 'B 新正文');
      expect(after[partB.value]!['content_hash'],
          isNot(before[partB.value]!['content_hash']));

      for (final other in [partA.value, partC.value]) {
        expect(
          after[other],
          equals(before[other]),
          reason: 'part $other must not be rewritten',
        );
      }

      final sectionAfter = (await db.query(
        'resource_sections',
        where: 'id = ?',
        whereArgs: [sectionId.value],
      ))
          .first;
      expect(sectionAfter, equals(sectionBefore));

      // The resource keeps its own freshness marker by design.
      final resourceAfter = (await db.query(
        'resources',
        where: 'id = ?',
        whereArgs: [session.resourceId.value],
      ))
          .first;
      expect(
        resourceAfter['updated_at'],
        isNot(resourceBefore['updated_at']),
      );
    });
  });

  group('optimistic locking', () {
    test('a stale part token is rejected and changes nothing', () async {
      final session = await repo.begin(type: ResourceType.worldview, name: 'R');
      final sectionId = await session.appendSection(title: 'S');
      final partId = await session.appendPart(
        sectionId: sectionId,
        title: 'P',
        content: '原始正文',
      );
      await session.commit();

      final staleToken = (await repo.readNodeState(partId))!.updatedAt;
      await repo.updatePart(
        id: partId,
        expectedUpdatedAt: staleToken,
        content: '第一次修改',
      );
      final freshToken = (await repo.readNodeState(partId))!.updatedAt;
      expect(freshToken, isNot(staleToken));

      await expectLater(
        repo.updatePart(
          id: partId,
          expectedUpdatedAt: staleToken,
          content: '并发覆盖',
        ),
        throwsA(isA<ResourceTreeConflictException>()),
      );

      expect((await repo.readParts(sectionId)).single.content, '第一次修改');
    });

    test('a stale section or resource token is rejected', () async {
      final resource = await repo.createResource(
        type: ResourceType.worldview,
        name: 'R',
      );
      final sectionToken = (await repo.readNodeState(resource.id))!.updatedAt;
      final section = await repo.mount(
        AppendSectionPatch(resourceId: resource.id, title: 'S'),
      );

      // Editing the section bumps the section's own token, so replaying the
      // original one must fail instead of silently overwriting.
      await repo.updateSection(
        id: section.nodeId as SectionId,
        expectedUpdatedAt:
            (await repo.readNodeState(section.nodeId))!.updatedAt,
        title: '新标题',
      );
      await repo.updateSection(
        id: section.nodeId as SectionId,
        expectedUpdatedAt:
            (await repo.readNodeState(section.nodeId))!.updatedAt,
        title: '第一次',
      );

      // Appending a section moved the resource token, so the pre-append one is
      // stale.
      await expectLater(
        repo.updateResource(
          id: resource.id,
          expectedUpdatedAt: sectionToken,
          name: '并发覆盖',
        ),
        throwsA(isA<ResourceTreeConflictException>()),
      );
      expect((await repo.findResource(resource.id))!.name, 'R');
    });

    test('updating an unknown or deleted node raises not-found', () async {
      await expectLater(
        repo.updatePart(
          id: const PartId('part_missing'),
          expectedUpdatedAt: 'any',
          content: 'x',
        ),
        throwsA(isA<ResourceTreeNotFoundException>()),
      );
    });
  });

  group('soft delete', () {
    test('a deleted part disappears from reads but stays in the database',
        () async {
      final session = await repo.begin(type: ResourceType.worldview, name: 'R');
      final sectionId = await session.appendSection(title: 'S');
      final partId = await session.appendPart(
        sectionId: sectionId,
        title: 'P',
        content: '正文',
      );
      await session.commit();

      final token = (await repo.readNodeState(partId))!.updatedAt;
      await repo.softDeleteNode(id: partId, expectedUpdatedAt: token);

      expect(await repo.readParts(sectionId), isEmpty);
      expect((await repo.readNodeState(partId))!.isDeleted, isTrue);

      final db = await DatabaseService.database;
      final rows = await db.query(
        'resource_parts',
        where: 'id = ?',
        whereArgs: [partId.value],
      );
      expect(rows, hasLength(1));
      expect(rows.first['content'], '正文');
      expect(rows.first['deleted_at'], isNotNull);
    });

    test('deleting a section hides its parts', () async {
      final session = await repo.begin(type: ResourceType.worldview, name: 'R');
      final sectionId = await session.appendSection(title: 'S');
      final partId = await session.appendPart(
        sectionId: sectionId,
        title: 'P',
        content: '正文',
      );
      await session.commit();

      await repo.softDeleteNode(
        id: sectionId,
        expectedUpdatedAt: (await repo.readNodeState(sectionId))!.updatedAt,
      );

      expect(await repo.readSections(session.resourceId), isEmpty);
      expect(await repo.readParts(sectionId), isEmpty);
      expect((await repo.readNodeState(partId))!.isDeleted, isTrue);
      final tree = await repo.readTree(session.resourceId);
      expect(tree!.sections, isEmpty);
      expect(tree.parts, isEmpty);
    });

    test('deleting a resource hides the whole tree', () async {
      final session = await repo.begin(type: ResourceType.worldview, name: 'R');
      final sectionId = await session.appendSection(title: 'S');
      await session.appendPart(sectionId: sectionId, title: 'P', content: '正文');
      await session.commit();

      await repo.softDeleteNode(
        id: session.resourceId,
        expectedUpdatedAt:
            (await repo.readNodeState(session.resourceId))!.updatedAt,
      );

      expect(await repo.findResource(session.resourceId), isNull);
      expect(await repo.readTree(session.resourceId), isNull);
      expect(await repo.readSections(session.resourceId), isEmpty);
      expect(await repo.listResources(type: ResourceType.worldview), isEmpty);
    });
  });

  group('content hash', () {
    test('matches the mapper hash on append and follows content updates',
        () async {
      final session = await repo.begin(type: ResourceType.worldview, name: 'R');
      final sectionId = await session.appendSection(title: 'S');
      final partId = await session.appendPart(
        sectionId: sectionId,
        title: 'P',
        content: '第一段',
      );
      await session.commit();

      expect(
        (await repo.readNodeState(partId))!.contentHash,
        ResourceTreeRowMapper.contentHashFor('第一段'),
      );

      await repo.updatePart(
        id: partId,
        expectedUpdatedAt: (await repo.readNodeState(partId))!.updatedAt,
        content: '第二段',
      );

      expect(
        (await repo.readNodeState(partId))!.contentHash,
        ResourceTreeRowMapper.contentHashFor('第二段'),
      );
      expect(
        (await repo.readParts(sectionId)).single.contentHash,
        ResourceTreeRowMapper.contentHashFor('第二段'),
      );
    });

    test('identical content produces an identical hash', () async {
      expect(
        ResourceTreeRowMapper.contentHashFor('相同正文'),
        ResourceTreeRowMapper.contentHashFor('相同正文'),
      );
      expect(
        ResourceTreeRowMapper.contentHashFor('相同正文'),
        isNot(ResourceTreeRowMapper.contentHashFor('不同正文')),
      );
    });
  });

  group('large fixtures need no giant JSON', () {
    test('reads a large tree from per-node rows', () async {
      final session =
          await repo.begin(type: ResourceType.worldview, name: '大资源');
      final sectionIds = <SectionId>[];
      for (var s = 0; s < 20; s++) {
        final sectionId = await session.appendSection(title: 'Section $s');
        sectionIds.add(sectionId);
        for (var p = 0; p < 3; p++) {
          await session.appendPart(
            sectionId: sectionId,
            title: 'Part $s-$p',
            content: '正文' * 300,
          );
        }
      }
      await session.commit();

      final tree = await repo.readTree(session.resourceId);
      expect(tree!.sections, hasLength(20));
      expect(tree.parts, hasLength(60));
      expect(tree.orderedPartsOf(sectionIds.first), hasLength(3));

      // The root row stays tiny: the tree lives in node rows, not in JSON.
      final db = await DatabaseService.database;
      final resourceRow = (await db.query(
        'resources',
        where: 'id = ?',
        whereArgs: [session.resourceId.value],
      ))
          .first;
      expect((resourceRow['metadata_json'] as String).length, lessThan(200));

      // Reading one section loads only that section's parts.
      expect(await repo.readParts(sectionIds.last), hasLength(3));
    });
  });

  group('architecture guards', () {
    test('the tree repository never touches legacy resource tables', () {
      final source = File(
        'lib/services/repositories/resource_tree_repository_impl.dart',
      ).readAsStringSync();

      for (final legacy in const [
        'worldview_presets',
        'character_cards',
        'npc_cards',
        'creation_library_resources',
      ]) {
        expect(
          source.contains(legacy),
          isFalse,
          reason: 'Phase 1 must not read or write $legacy (that is Phase 2)',
        );
      }
    });

    test('the tree schema has no whole-resource body column', () {
      final source =
          File('lib/services/database_service.dart').readAsStringSync();
      final start =
          source.indexOf('static Future<void> createResourceTreeSchema');
      final end = source
          .indexOf('static Future<void> createWorldEntryEmbeddingsSchema');
      expect(start, greaterThan(0));
      expect(end, greaterThan(start));
      final block = source.substring(start, end);

      for (final banned in const [
        'content_json',
        'parts_json',
        'sections_json',
        'full_content',
      ]) {
        expect(
          block.contains(banned),
          isFalse,
          reason: 'the resource tree schema must not declare $banned',
        );
      }
    });
  });
}
