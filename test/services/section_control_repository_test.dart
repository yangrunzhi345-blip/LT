import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/section_control.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/section_control_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _resourceId = ResourceId('res_section_control');
const _sectionA = SectionId('res_section_control_sec_a');
const _sectionB = SectionId('res_section_control_sec_b');
const _partA1 = PartId('res_section_control_sec_a_part_1');
const _partA2 = PartId('res_section_control_sec_a_part_2');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late ResourceTreeRepositoryImpl treeRepository;
  late SectionControlRepositoryImpl repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_section_control_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();

    Future<Database> getDb() => DatabaseService.database;
    treeRepository = ResourceTreeRepositoryImpl(getDb: getDb);
    repository = SectionControlRepositoryImpl(getDb: getDb);

    await treeRepository.createResourceTree(
      const ResourceTreeDraft(
        id: _resourceId,
        type: ResourceType.worldview,
        name: '节流测试资源',
        sections: [
          ResourceTreeSectionDraft(
            id: _sectionA,
            title: '第一章',
            parts: [
              ResourceTreePartDraft(
                id: _partA1,
                title: '开头',
                content: '第一章开头正文',
              ),
              ResourceTreePartDraft(
                id: _partA2,
                title: '结尾',
                content: '第一章结尾正文',
              ),
            ],
          ),
          ResourceTreeSectionDraft(
            id: _sectionB,
            title: '第二章',
            parts: [
              ResourceTreePartDraft(title: '待生成', content: ''),
            ],
          ),
        ],
      ),
    );

    final db = await getDb();
    await db.insert('resource_generation_tasks', {
      'task_id': 'task_a1',
      'blueprint_id': 'bp_1',
      'resource_id': _resourceId.value,
      'section_id': _sectionA.value,
      'part_id': _partA1.value,
      'prompt_goal': '写开头',
      'estimated_length': 800,
      'dependencies_json': '[]',
      'status': 'failed',
      'sort_order': 0,
      'created_at': '2026-09-17T00:00:00.000',
      'updated_at': '2026-09-17T00:00:00.000',
    });
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('SectionControlRepositoryImpl.readSectionPage', () {
    test('pages sections in canonical order without loading the whole tree',
        () async {
      final firstPage = await repository.readSectionPage(
        resourceId: _resourceId,
        limit: 1,
        offset: 0,
      );
      expect(firstPage.totalCount, 2);
      expect(firstPage.offset, 0);
      expect(firstPage.rows, hasLength(1));
      expect(firstPage.rows.single.id, _sectionA);
      expect(firstPage.rows.single.orderIndex, 0);
      expect(firstPage.rows.single.title, '第一章');

      final secondPage = await repository.readSectionPage(
        resourceId: _resourceId,
        limit: 1,
        offset: 1,
      );
      expect(secondPage.rows.single.id, _sectionB);
      expect(secondPage.rows.single.orderIndex, 1);
    });

    test('rejects a non-positive limit and a negative offset', () async {
      expect(
        () => repository.readSectionPage(
          resourceId: _resourceId,
          limit: 0,
          offset: 0,
        ),
        throwsA(isA<ResourceTreeConflictException>()),
      );
      expect(
        () => repository.readSectionPage(
          resourceId: _resourceId,
          limit: 10,
          offset: -1,
        ),
        throwsA(isA<ResourceTreeConflictException>()),
      );
    });
  });

  group('SectionControlRepositoryImpl reads', () {
    test('reads one section row with its default validation state', () async {
      final row = await repository.findSectionControlRow(_sectionA);
      expect(row, isNotNull);
      expect(row!.validationState, SectionValidationState.unvalidated);
      expect(row.validationMessage, isEmpty);
      expect(row.validatedAt, isNull);
      expect(row.updatedAt, isNotEmpty);
    });

    test('returns null for an unknown section', () async {
      expect(
        await repository.findSectionControlRow(const SectionId('missing')),
        isNull,
      );
    });

    test('aggregates Part counts, characters and a bounded preview', () async {
      final summaries = await repository.readPartSummaries(
        const [_sectionA, _sectionB, SectionId('missing')],
      );

      final sectionA = summaries[_sectionA.value]!;
      expect(sectionA.partCount, 2);
      expect(sectionA.characterCount, '第一章开头正文'.length + '第一章结尾正文'.length);
      expect(sectionA.preview, contains('第一章开头正文'));
      expect(sectionA.hasContent, isTrue);

      final sectionB = summaries[_sectionB.value]!;
      expect(sectionB.partCount, 1);
      expect(sectionB.characterCount, 0);
      expect(sectionB.hasContent, isFalse);

      expect(summaries[const SectionId('missing').value]!.partCount, 0);
    });

    test('truncates the preview to the configured bound', () async {
      final bounded = SectionControlRepositoryImpl(
        getDb: () => DatabaseService.database,
        previewCharacters: 3,
      );
      final summaries = await bounded.readPartSummaries(const [_sectionA]);
      expect(summaries[_sectionA.value]!.preview, '第一章');
      expect(
        summaries[_sectionA.value]!.characterCount,
        '第一章开头正文'.length + '第一章结尾正文'.length,
      );
    });

    test('reads only the generation tasks bound to the requested section',
        () async {
      final tasks = await repository.readSectionTasks(
        const [_sectionA, _sectionB],
      );
      expect(tasks, hasLength(1));
      expect(tasks.single.taskId, 'task_a1');
      expect(tasks.single.partId, _partA1);
      expect(tasks.single.status, 'failed');

      expect(await repository.readSectionTasks(const []), isEmpty);
    });

    test('reads full Part rows for exactly one section', () async {
      final parts = await repository.readSectionParts(_sectionA);
      expect(parts, hasLength(2));
      expect(parts.first.id, _partA1);
      expect(parts.first.content, '第一章开头正文');
      expect(parts.first.orderIndex, 0);

      expect(await repository.readSectionParts(const SectionId('missing')),
          isEmpty);
    });
  });

  group('SectionControlRepositoryImpl.updateSectionValidation', () {
    test('persists the verdict without touching the edit token', () async {
      final before = await repository.findSectionControlRow(_sectionA);
      final validatedAt = DateTime(2026, 9, 17, 12);

      await repository.updateSectionValidation(
        id: _sectionA,
        expectedUpdatedAt: before!.updatedAt,
        state: SectionValidationState.invalid,
        message: '缺少正文',
        validatedAt: validatedAt,
      );

      final after = await repository.findSectionControlRow(_sectionA);
      expect(after!.validationState, SectionValidationState.invalid);
      expect(after.validationMessage, '缺少正文');
      expect(after.validatedAt, validatedAt.toIso8601String());
      expect(
        after.updatedAt,
        before.updatedAt,
        reason: '校验是历史记录，不是内容编辑，不得改变乐观锁令牌',
      );
    });

    test('rejects a stale token instead of overwriting', () async {
      expect(
        () => repository.updateSectionValidation(
          id: _sectionA,
          expectedUpdatedAt: '2026-01-01T00:00:00.000',
          state: SectionValidationState.valid,
          message: '',
        ),
        throwsA(isA<ResourceTreeConflictException>()),
      );
    });
  });
}
