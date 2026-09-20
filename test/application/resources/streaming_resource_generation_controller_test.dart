import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/part_generation_coordinator.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/application/resources/streaming_generation_session_repository.dart';
import 'package:lt_dialogue/application/resources/streaming_resource_generation_service.dart';
import 'package:lt_dialogue/controllers/streaming_resource_generation_controller.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/streaming_generation_runtime_contracts.dart';
import 'package:lt_dialogue/models/llm_task.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late ResourceTreeRepositoryImpl treeRepo;
  late ResourceCreationPipeline pipeline;
  late ResourceBlueprintRepositoryImpl blueprintRepo;
  late PartGenerationTaskRepositoryImpl taskRepo;
  late StreamingGenerationSessionRepositoryImpl sessionRepo;
  late StreamingResourceGenerationService service;
  late StreamingResourceGenerationController controller;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_ctrl_test_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();

    treeRepo =
        ResourceTreeRepositoryImpl(getDb: () => DatabaseService.database);
    pipeline = ResourceCreationPipeline(
      getDb: () => DatabaseService.database,
      hasAiCredentials: () => true,
      treeRepository: treeRepo,
    );
    blueprintRepo = ResourceBlueprintRepositoryImpl(
      getDb: () => DatabaseService.database,
      treeRepository: treeRepo,
    );
    taskRepo = PartGenerationTaskRepositoryImpl(
      getDb: () => DatabaseService.database,
    );
    sessionRepo = StreamingGenerationSessionRepositoryImpl(
      getDb: () => DatabaseService.database,
    );

    final coordinator = PartGenerationCoordinator(
      taskRepository: taskRepo,
      blueprintRepository: blueprintRepo,
      pipeline: pipeline,
      completer: ({
        required String systemPrompt,
        required String instruction,
        required LlmTask task,
        GenerationTaskHandle? taskHandle,
      }) async {
        final genMatch =
            RegExp(r'"generation_id": "(.*?)"').firstMatch(systemPrompt);
        final resMatch =
            RegExp(r'"resource_id": "(.*?)"').firstMatch(systemPrompt);
        final secMatch =
            RegExp(r'"section_id": "(.*?)"').firstMatch(systemPrompt);
        final partMatch =
            RegExp(r'"part_id": "(.*?)"').firstMatch(systemPrompt);
        final attMatch =
            RegExp(r'"attempt_id": "(.*?)"').firstMatch(systemPrompt);

        const content = '标准控制器测试正文内容，详实而生动。';
        final common = {
          'protocol_version': 1,
          'generation_id': genMatch?.group(1) ?? 'gen_mock',
          'resource_id': resMatch?.group(1) ?? 'res_mock',
          'section_id': secMatch?.group(1) ?? 'sec_mock',
          'part_id': partMatch?.group(1) ?? 'part_mock',
          'attempt_id': attMatch?.group(1) ?? 'att_mock',
        };
        return [
          {...common, 'sequence': 0, 'op': 'start_part', 'cursor': 0},
          {
            ...common,
            'sequence': 1,
            'op': 'append_text',
            'text_delta': content,
            'cursor': 0,
          },
          {
            ...common,
            'sequence': 2,
            'op': 'complete_part',
            'cursor': content.length,
            'summary': '控制器测试摘要',
          },
        ].map(jsonEncode).join('\n');
      },
    );

    service = StreamingResourceGenerationService(
      sessionRepository: sessionRepo,
      taskRepository: taskRepo,
      blueprintRepository: blueprintRepo,
      pipeline: pipeline,
      coordinator: coordinator,
    );

    controller = StreamingResourceGenerationController(
      service: service,
      sessionRepository: sessionRepo,
    );
  });

  tearDown(() async {
    controller.dispose();
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<({String resourceId, String blueprintId, String sessionId})>
      setupResourceAndBlueprint() async {
    final creationResult = await pipeline.create(ResourceCreationRequest(
      resourceType: ResourceType.worldview,
      method: CreationMethod.aiReference,
      name: '神代天穹',
      idempotencyKey: 'idemp_${DateTime.now().microsecondsSinceEpoch}',
      referenceSource: ReferenceSource.text('参考文本'),
    ));

    final bp = ResourceBlueprint(
      blueprintId: 'bp_${DateTime.now().microsecondsSinceEpoch}',
      sessionId: creationResult.sessionId!,
      resourceType: ResourceType.worldview,
      suggestedName: '神代天穹',
      summary: '神代天穹设定',
      sections: [
        BlueprintSection(
          id: 'sec_1',
          title: '创世纪',
          parts: const [
            BlueprintPart(
              id: 'part_1',
              sectionId: 'sec_1',
              title: '起源之火',
              generationGoal: '世界诞生',
              estimatedLength: 800,
              dependencies: [],
            ),
          ],
        ),
      ],
    );

    await blueprintRepo.saveBlueprint(bp);
    final confirmResult =
        await blueprintRepo.confirmBlueprint(blueprintId: bp.blueprintId);

    return (
      resourceId: confirmResult.resourceId.value,
      blueprintId: bp.blueprintId,
      sessionId: creationResult.sessionId!,
    );
  }

  test(
      'StreamingResourceGenerationController creates session and drives generation to completion',
      () async {
    final setup = await setupResourceAndBlueprint();
    final events = <GenerationRuntimeEvent>[];
    final sub = controller.events.listen(events.add);

    final session = await controller.createSession(
      resourceId: setup.resourceId,
      blueprintId: setup.blueprintId,
      creationSessionId: setup.sessionId,
    );
    expect(session.status, StreamingLifecycleStatus.created);

    final started = await controller.start(sessionId: session.sessionId);
    expect(started, isTrue);

    final finalSession = await controller.getSession(session.sessionId);
    expect(finalSession?.status, StreamingLifecycleStatus.completed);

    final latestSession =
        await controller.getLatestSessionForResource(setup.resourceId);
    expect(latestSession?.sessionId, session.sessionId);

    expect(events.whereType<GenerationStarted>().length, 1);
    expect(events.whereType<GenerationCompleted>().length, 1);

    await sub.cancel();
  });

  test(
      'StreamingResourceGenerationController pause, resume and cancel lifecycles',
      () async {
    final setup = await setupResourceAndBlueprint();
    final session = await controller.createSession(
      resourceId: setup.resourceId,
      blueprintId: setup.blueprintId,
      creationSessionId: setup.sessionId,
    );

    await controller.pause(sessionId: session.sessionId);
    var fetched = await controller.getSession(session.sessionId);
    expect(fetched?.status, StreamingLifecycleStatus.paused);

    await controller.cancel(sessionId: session.sessionId);
    fetched = await controller.getSession(session.sessionId);
    expect(fetched?.status, StreamingLifecycleStatus.cancelled);
  });
}
