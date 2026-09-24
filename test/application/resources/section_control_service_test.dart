import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/section_control_event_bus.dart';
import 'package:lt_dialogue/application/resources/section_control_service.dart';
import 'package:lt_dialogue/application/resources/section_regeneration.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/errors/app_error.dart';
import 'package:lt_dialogue/domain/resources/resource_edit_command.dart';
import 'package:lt_dialogue/domain/resources/section_control.dart';
import 'package:lt_dialogue/domain/resources/section_control_events.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/section_control_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _resourceId = ResourceId('res_sc_service');
const _sectionId = SectionId('res_sc_service_sec_1');
const _partId = PartId('res_sc_service_sec_1_part_1');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late ResourceTreeRepositoryImpl treeRepository;
  late SectionControlService service;
  late _FakeRegenerationExecutor executor;

  Future<Database> getDb() => DatabaseService.database;

  Future<void> seedResource() async {
    await treeRepository.createResourceTree(
      const ResourceTreeDraft(
        id: _resourceId,
        type: ResourceType.worldview,
        name: 'Section Control 资源',
        sections: [
          ResourceTreeSectionDraft(
            id: _sectionId,
            title: '第一章',
            parts: [
              ResourceTreePartDraft(
                id: _partId,
                title: '开场',
                content: '已经生成好的正文。',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> seedTask() async {
    final db = await getDb();
    await db.insert('resource_generation_tasks', {
      'task_id': 'task_sc_1',
      'blueprint_id': 'bp_sc_1',
      'resource_id': _resourceId.value,
      'section_id': _sectionId.value,
      'part_id': _partId.value,
      'prompt_goal': '写开场',
      'estimated_length': 800,
      'dependencies_json': '[]',
      'status': 'failed',
      'sort_order': 0,
      'created_at': '2026-09-17T00:00:00.000',
      'updated_at': '2026-09-17T00:00:00.000',
    });
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_sc_service_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();

    treeRepository = ResourceTreeRepositoryImpl(getDb: getDb);
    executor = _FakeRegenerationExecutor();
    service = SectionControlService(
      repository: SectionControlRepositoryImpl(getDb: getDb),
      treeRepository: treeRepository,
      regenerationExecutor: executor,
    );
    addTearDown(service.dispose);
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('SectionControlService queries', () {
    test('pages sections and reports the total without loading everything',
        () async {
      await seedResource();
      await service.createSection(
        const CreateSectionCommand(resourceId: _resourceId, title: '第二章'),
      );
      await service.createSection(
        const CreateSectionCommand(resourceId: _resourceId, title: '第三章'),
      );

      final page = await service.listSections(
        resourceId: _resourceId,
        limit: 2,
      );
      expect(page.totalCount, 3);
      expect(page.entries, hasLength(2));
      expect(page.hasMore, isTrue);
      expect(page.entries.first.orderIndex, 0);
      expect(
        page.entries.first.generationState,
        SectionGenerationState.generated,
        reason: '无生成任务但已有正文',
      );

      final rest = await service.listSections(
        resourceId: _resourceId,
        limit: 2,
        offset: 2,
      );
      expect(rest.entries, hasLength(1));
      expect(rest.hasMore, isFalse);
    });

    test('caps an oversized page request', () async {
      await seedResource();
      final page =
          await service.listSections(resourceId: _resourceId, limit: 10000);
      expect(page.entries, hasLength(1));
    });

    test('throws for an unknown section', () async {
      await seedResource();
      expect(
        () => service.readSection(const SectionId('missing')),
        throwsA(isA<SectionControlException>()),
      );
    });
  });

  group('SectionControlService edit commands', () {
    test('creates a section and emits SectionCreated', () async {
      await seedResource();
      final entry = await service.createSection(
        const CreateSectionCommand(resourceId: _resourceId, title: '第二章'),
      );

      expect(entry.title, '第二章');
      expect(entry.orderIndex, 1);
      expect(entry.generationState, SectionGenerationState.pending);
      expect(service.eventHistory.last.event, isA<SectionCreatedEvent>());
    });

    test('renames a section under its optimistic token', () async {
      await seedResource();
      final before = await service.readSection(_sectionId);

      final renamed = await service.updateSection(
        RenameSectionCommand(
          sectionId: _sectionId,
          title: '  改名后的章节  ',
          expectedUpdatedAt: before.updatedAtToken,
        ),
      );
      expect(renamed.title, '改名后的章节');
      expect(service.eventHistory.last.event, isA<SectionUpdatedEvent>());
    });

    test('rejects a stale rename token', () async {
      await seedResource();
      expect(
        () => service.updateSection(
          const RenameSectionCommand(
            sectionId: _sectionId,
            title: '并发改名',
            expectedUpdatedAt: '2026-01-01T00:00:00.000',
          ),
        ),
        throwsA(isA<ResourceTreeConflictException>()),
      );
    });

    test('updates only the summary', () async {
      await seedResource();
      final before = await service.readSection(_sectionId);
      final updated = await service.updateSection(
        UpdateSectionCommand(
          sectionId: _sectionId,
          summary: '新的章节作用',
          expectedUpdatedAt: before.updatedAtToken,
        ),
      );
      expect(updated.summary, '新的章节作用');
      expect(updated.title, '第一章');
    });

    test('moves a section and emits SectionMoved only when order changes',
        () async {
      await seedResource();
      final second = await service.createSection(
        const CreateSectionCommand(resourceId: _resourceId, title: '第二章'),
      );

      await service.moveSection(
        MoveSectionCommand(
          resourceId: _resourceId,
          sectionId: second.id,
          targetIndex: 0,
          expectedUpdatedAt: second.updatedAtToken,
        ),
      );

      final sections = await treeRepository.readSections(_resourceId);
      expect(sections.map((section) => section.id), [second.id, _sectionId]);
      expect(service.eventHistory.last.event, isA<SectionMovedEvent>());

      final historyLength = service.eventHistory.length;
      final first = await service.readSection(second.id);
      await service.moveSection(
        MoveSectionCommand(
          resourceId: _resourceId,
          sectionId: second.id,
          targetIndex: 0,
          expectedUpdatedAt: first.updatedAtToken,
        ),
      );
      expect(
        service.eventHistory.length,
        historyLength,
        reason: '位置未变化时不得产生事件',
      );
    });

    test('rejects moving a section that belongs to another resource', () async {
      await seedResource();
      final entry = await service.readSection(_sectionId);
      expect(
        () => service.moveSection(
          MoveSectionCommand(
            resourceId: const ResourceId('other_res'),
            sectionId: _sectionId,
            targetIndex: 0,
            expectedUpdatedAt: entry.updatedAtToken,
          ),
        ),
        throwsA(isA<SectionControlException>()),
      );
    });

    test('soft deletes a section and hides it from reads', () async {
      await seedResource();
      final entry = await service.readSection(_sectionId);

      await service.deleteSection(
        DeleteSectionCommand(
          sectionId: _sectionId,
          expectedUpdatedAt: entry.updatedAtToken,
        ),
      );

      final page = await service.listSections(resourceId: _resourceId);
      expect(page.entries, isEmpty);
      expect(await treeRepository.readSections(_resourceId), isEmpty);
      expect(service.eventHistory.last.event, isA<SectionDeletedEvent>());
    });

    test('invalidates a section verdict when its Part content changes',
        () async {
      await seedResource();
      await service.validateSection(_sectionId);
      final validated = await service.readSection(_sectionId);
      expect(validated.validationState, SectionValidationState.valid);
      final part = (await treeRepository.readParts(_sectionId)).single;

      final updated = await service.updatePart(
        UpdatePartCommand(
          sectionId: _sectionId,
          partId: part.id,
          content: '改写后的正文',
          expectedUpdatedAt: await _partToken(),
        ),
      );

      expect(
        updated.validationState,
        SectionValidationState.stale,
        reason: '内容已变更，旧结论必须降级为 stale 而不是保留 valid',
      );
      expect(
        service.eventHistory
            .map((record) => record.event)
            .whereType<SectionValidationResetEvent>(),
        isNotEmpty,
      );
    });

    test('does not invent a verdict for a never-validated section', () async {
      await seedResource();
      final part = (await treeRepository.readParts(_sectionId)).single;

      final updated = await service.updatePart(
        UpdatePartCommand(
          sectionId: _sectionId,
          partId: part.id,
          content: '首次手写正文',
          expectedUpdatedAt: await _partToken(),
        ),
      );

      expect(updated.validationState, SectionValidationState.unvalidated);
    });
  });

  group('SectionControlService validation', () {
    test('validates a complete section and persists the verdict', () async {
      await seedResource();
      final result = await service.validateSection(_sectionId);

      expect(result.state, SectionValidationState.valid);
      expect(result.characterCount, '已经生成好的正文。'.length);

      final stored = await service.readSection(_sectionId);
      expect(stored.validationState, SectionValidationState.valid);
      expect(stored.validatedAt, isNotNull);

      final events = service.eventHistory
          .map((record) => record.event)
          .whereType<SectionValidationPassedEvent>();
      expect(events, hasLength(1));
    });

    test('reports an empty Part as invalid and records the message', () async {
      await seedResource();
      final part = (await treeRepository.readParts(_sectionId)).single;
      await service.updatePart(
        UpdatePartCommand(
          sectionId: _sectionId,
          partId: part.id,
          content: ' ',
          expectedUpdatedAt: await _partToken(),
        ),
      );

      final result = await service.validateSection(_sectionId);
      expect(result.state, SectionValidationState.invalid);
      expect(result.issues, hasLength(1));

      final stored = await service.readSection(_sectionId);
      expect(stored.validationState, SectionValidationState.invalid);
      expect(stored.validationMessage, isNotEmpty);
      expect(
        service.eventHistory
            .map((record) => record.event)
            .whereType<SectionValidationFailedEvent>(),
        hasLength(1),
      );
    });
  });

  group('SectionControlService regeneration', () {
    Future<String> sectionToken() async =>
        (await service.readSection(_sectionId)).updatedAtToken;

    test('rejects regeneration for a section without generation tasks',
        () async {
      await seedResource();
      await expectLater(
        service.regenerateSection(
          RegenerateSectionCommand(
            sectionId: _sectionId,
            expectedUpdatedAt: await sectionToken(),
          ),
        ),
        throwsA(
          isA<SectionControlException>().having(
            (error) => error.message,
            'message',
            contains('没有可重新生成的生成任务'),
          ),
        ),
      );
    });

    test('rejects a stale section token before touching any Part', () async {
      await seedResource();
      await seedTask();

      await expectLater(
        service.regenerateSection(
          const RegenerateSectionCommand(
            sectionId: _sectionId,
            expectedUpdatedAt: '2026-01-01T00:00:00.000',
          ),
        ),
        throwsA(
          isA<SectionControlException>().having(
            (error) => error.message,
            'message',
            contains('并发修改'),
          ),
        ),
      );

      expect(
        executor.requests,
        isEmpty,
        reason: '令牌不匹配时不得启动任何 Part 生成',
      );
      expect(
        service.eventHistory.map((record) => record.event.eventName),
        isNot(contains('SectionGenerationStarted')),
      );
    });

    test('accepts a current section token and regenerates', () async {
      await seedResource();
      await seedTask();
      executor.characterCount = 42;

      final outcome = await service.regenerateSection(
        RegenerateSectionCommand(
          sectionId: _sectionId,
          expectedUpdatedAt: await sectionToken(),
        ),
      );

      expect(outcome.success, isTrue);
      expect(outcome.partCount, 1);
      expect(outcome.completedPartCount, 1);
      expect(outcome.characterCount, 42);
      expect(executor.requests, hasLength(1));
      expect(executor.requests.single.partId, _partId);
      expect(executor.requests.single.taskId, 'task_sc_1');

      final names =
          service.eventHistory.map((record) => record.event.eventName).toList();
      expect(names, contains('SectionGenerationStarted'));
      expect(names, contains('SectionGenerationCompleted'));
    });

    test('rejects a token that went stale because a Part was edited', () async {
      await seedResource();
      await seedTask();
      final staleToken = await sectionToken();

      final part = (await treeRepository.readParts(_sectionId)).single;
      await service.updatePart(
        UpdatePartCommand(
          sectionId: _sectionId,
          partId: part.id,
          content: '并发写入的新正文',
          expectedUpdatedAt: await _partToken(),
        ),
      );

      await expectLater(
        service.regenerateSection(
          RegenerateSectionCommand(
            sectionId: _sectionId,
            expectedUpdatedAt: staleToken,
          ),
        ),
        throwsA(isA<SectionControlException>()),
      );
      expect(executor.requests, isEmpty);
    });

    test('forwards the rewrite directive with the user instruction', () async {
      await seedResource();
      await seedTask();

      await service.regenerateSection(
        RegenerateSectionCommand(
          sectionId: _sectionId,
          expectedUpdatedAt: await sectionToken(),
          mode: AiRewriteMode.condense,
          instruction: '更简洁',
        ),
      );

      final instruction = executor.requests.single.instruction;
      expect(instruction, contains(AiRewriteMode.condense.directive));
      expect(instruction, contains('更简洁'));
    });

    test('rejects an executor outcome bound to another section', () async {
      await seedResource();
      await seedTask();
      executor.reportSectionIdOverride = const SectionId('sec_other');

      final outcome = await service.regenerateSection(
        RegenerateSectionCommand(
          sectionId: _sectionId,
          expectedUpdatedAt: await sectionToken(),
        ),
      );

      expect(outcome.success, isFalse);
      expect(outcome.completedPartCount, 0);
      expect(outcome.error?.code, AppErrorCode.resourceConflict);
      expect(outcome.error?.parameters['field'], 'sectionId');
      expect(
        service.eventHistory
            .map((record) => record.event)
            .whereType<SectionGenerationFailedEvent>(),
        hasLength(1),
      );
      final event = service.eventHistory
          .map((record) => record.event)
          .whereType<SectionGenerationFailedEvent>()
          .single;
      expect(event.error.code, AppErrorCode.resourceConflict);
      expect(event.errorMessage, isEmpty);
    });

    test('stops the run when the executor reports failure', () async {
      await seedResource();
      await seedTask();
      executor.success = false;
      executor.errorMessage = '模型超时';

      final outcome = await service.regenerateSection(
        RegenerateSectionCommand(
          sectionId: _sectionId,
          expectedUpdatedAt: await sectionToken(),
        ),
      );

      expect(outcome.success, isFalse);
      expect(outcome.error?.code, AppErrorCode.resourceGenerationFailed);
    });

    test('maps runtime exceptions to a typed failure without raw text',
        () async {
      await seedResource();
      await seedTask();
      executor.throwError = StateError('private runtime detail');

      final outcome = await service.regenerateSection(
        RegenerateSectionCommand(
          sectionId: _sectionId,
          expectedUpdatedAt: await sectionToken(),
        ),
      );

      expect(outcome.error?.code, AppErrorCode.unknown);
      expect(outcome.errorMessage, isEmpty);
      final event = service.eventHistory
          .map((record) => record.event)
          .whereType<SectionGenerationFailedEvent>()
          .single;
      expect(event.error.code, AppErrorCode.unknown);
      expect(event.errorMessage, isEmpty);
    });
  });

  group('SectionControlEventBus', () {
    test('assigns monotonic sequences and bounds its history', () {
      final bus = SectionControlEventBus(historyLimit: 2);
      addTearDown(bus.dispose);

      for (var i = 0; i < 3; i++) {
        bus.publish(
          SectionDeletedEvent(
            resourceId: _resourceId,
            sectionId: SectionId('sec_$i'),
            timestamp: DateTime(2026),
          ),
        );
      }

      expect(bus.lastSequence, 3);
      expect(bus.history, hasLength(2));
      expect(bus.history.first.sequence, 2);
      expect(bus.history.last.sequence, 3);
    });
  });
}

/// Reads the current optimistic token of the seeded Part node.
Future<String> _partToken() async {
  final repository = ResourceTreeRepositoryImpl(
    getDb: () => DatabaseService.database,
  );
  final state = await repository.readNodeState(_partId);
  return state?.updatedAt ?? '';
}

final class _FakeRegenerationExecutor implements SectionRegenerationExecutor {
  final List<SectionRegenerationRequest> requests =
      <SectionRegenerationRequest>[];

  SectionId? reportSectionIdOverride;
  bool success = true;
  int characterCount = 0;
  String errorMessage = '';
  Object? throwError;

  @override
  Future<SectionRegenerationOutcome> regenerate(
    SectionRegenerationRequest request,
  ) async {
    requests.add(request);
    if (throwError != null) throw throwError!;
    return SectionRegenerationOutcome(
      resourceId: request.resourceId,
      sectionId: reportSectionIdOverride ?? request.sectionId,
      partId: request.partId,
      generationId: 'protocol_gen_${requests.length}',
      success: success,
      characterCount: characterCount,
      errorMessage: errorMessage,
      error: success
          ? null
          : const AppDomainError(code: AppErrorCode.resourceGenerationFailed),
    );
  }
}
