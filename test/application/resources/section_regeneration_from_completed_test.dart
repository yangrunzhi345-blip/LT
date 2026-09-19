import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/section_control_service.dart';
import 'package:lt_dialogue/controllers/streaming_resource_generation_controller.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_edit_command.dart';
import 'package:lt_dialogue/domain/resources/streaming_generation_runtime_contracts.dart';
import 'package:lt_dialogue/features/resource_studio/application/use_cases/streaming_section_regeneration_executor.dart';
import 'package:lt_dialogue/models/llm_task.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/section_control_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/r01_streaming_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late R01StreamingFixture fixture;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_r01_regeneration_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    fixture = R01StreamingFixture();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('R01 regeneration from completed', () {
    test('R01-01 completed section regenerates and preserves old revision',
        () async {
      final setup = await fixture.createOnePartResource(suffix: 'completed');
      var generatedContent = '重新生成前的已提交正文';
      final service = fixture.buildService(({
        required String systemPrompt,
        required String instruction,
        required LlmTask task,
        GenerationTaskHandle? taskHandle,
      }) async =>
          r01Completion(systemPrompt, generatedContent));
      final controller = StreamingResourceGenerationController(
        service: service,
        sessionRepository: fixture.sessionRepository,
      );
      final sectionService = _sectionService(fixture, controller);
      addTearDown(sectionService.dispose);
      addTearDown(controller.dispose);

      final session = await service.createSession(
        resourceId: setup.resourceId.value,
        blueprintId: setup.blueprintId,
        creationSessionId: setup.creationSessionId,
      );
      expect(
          await service.startGeneration(sessionId: session.sessionId), isTrue);
      final oldHead = await fixture.revisionRepository.readHead(
        setup.resourceId,
        ResourceRevisionKind.latestHead,
      );
      expect(oldHead, isNotNull);
      final row = await SectionControlRepositoryImpl(
        getDb: () => DatabaseService.database,
      ).findSectionControlRow(setup.sectionId);
      generatedContent = 'completed 会话重新生成后的正文';

      final outcome = await sectionService.regenerateSection(
        RegenerateSectionCommand(
          sectionId: setup.sectionId,
          expectedUpdatedAt: row!.updatedAt,
        ),
      );

      expect(outcome.success, isTrue, reason: outcome.errorMessage);
      expect(
        (await fixture.sessionRepository.findSession(session.sessionId))
            ?.status,
        StreamingLifecycleStatus.completed,
      );
      expect(
        (await fixture.taskRepository
                .getPartsContent([setup.partId.value]))[setup.partId.value]
            ?.content,
        generatedContent,
      );
      final oldState = await fixture.revisionService.readState(
        oldHead!.revisionId,
      );
      expect(
        oldState.nodes.values
            .firstWhere((node) => node.nodeId == setup.partId.value)
            .content,
        '重新生成前的已提交正文',
      );
    });

    test('R01-02 failed regeneration converges without a completed/ready split',
        () async {
      final setup = await fixture.createOnePartResource(suffix: 'failure');
      var shouldFail = false;
      final service = fixture.buildService(({
        required String systemPrompt,
        required String instruction,
        required LlmTask task,
        GenerationTaskHandle? taskHandle,
      }) async {
        if (shouldFail) throw StateError('R01 coordinator failure');
        return r01Completion(systemPrompt, '失败前的已提交正文');
      });
      final controller = StreamingResourceGenerationController(
        service: service,
        sessionRepository: fixture.sessionRepository,
      );
      final sectionService = _sectionService(fixture, controller);
      addTearDown(sectionService.dispose);
      addTearDown(controller.dispose);

      final session = await service.createSession(
        resourceId: setup.resourceId.value,
        blueprintId: setup.blueprintId,
        creationSessionId: setup.creationSessionId,
      );
      expect(
          await service.startGeneration(sessionId: session.sessionId), isTrue);
      final oldHead = await fixture.revisionRepository.readHead(
        setup.resourceId,
        ResourceRevisionKind.latestHead,
      );
      final row = await SectionControlRepositoryImpl(
        getDb: () => DatabaseService.database,
      ).findSectionControlRow(setup.sectionId);
      shouldFail = true;

      final outcome = await sectionService.regenerateSection(
        RegenerateSectionCommand(
          sectionId: setup.sectionId,
          expectedUpdatedAt: row!.updatedAt,
        ),
      );

      expect(outcome.success, isFalse);
      final persisted =
          await fixture.sessionRepository.findSession(session.sessionId);
      expect(persisted?.status, StreamingLifecycleStatus.failed);
      expect(persisted?.status, isNot(StreamingLifecycleStatus.generatingPart));
      final task = await fixture.taskRepository.findTask(setup.taskId);
      expect(
        persisted?.status == StreamingLifecycleStatus.completed &&
            task?.status == 'ready',
        isFalse,
      );
      final oldState = await fixture.revisionService.readState(
        oldHead!.revisionId,
      );
      expect(
        oldState.nodes.values
            .firstWhere((node) => node.nodeId == setup.partId.value)
            .content,
        '失败前的已提交正文',
      );
    });
  });
}

SectionControlService _sectionService(
  R01StreamingFixture fixture,
  StreamingResourceGenerationController controller,
) {
  return SectionControlService(
    repository: SectionControlRepositoryImpl(
      getDb: () => DatabaseService.database,
    ),
    treeRepository: fixture.treeRepository,
    regenerationExecutor: StreamingSectionRegenerationExecutor(
      runtime: StreamingRegenerationRuntimeAdapter(
        controller: controller,
        sessionRepository: fixture.sessionRepository,
      ),
    ),
    revisionService: fixture.revisionService,
  );
}
