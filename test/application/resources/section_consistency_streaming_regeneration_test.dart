import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/part_generation_coordinator.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/application/resources/section_regeneration.dart';
import 'package:lt_dialogue/application/resources/streaming_generation_session_repository.dart';
import 'package:lt_dialogue/application/resources/streaming_resource_generation_service.dart';
import 'package:lt_dialogue/controllers/streaming_resource_generation_controller.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_edit_command.dart';
import 'package:lt_dialogue/domain/resources/section_control.dart';
import 'package:lt_dialogue/features/resource_studio/application/use_cases/streaming_section_regeneration_executor.dart';
import 'package:lt_dialogue/models/llm_task.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/section_control_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// End-to-end cover for the Phase 7 B1 invariant through the real production
/// chain: StreamingSectionRegenerationExecutor → StreamingRegenerationRuntime
/// Adapter → StreamingResourceGenerationController → StreamingResource
/// GenerationService → PartGenerationCoordinator → commitPartContent.
///
/// The repository-level cases live in
/// `resource_generation_task_repository_test.dart`; this file exists to prove
/// the invariant also holds when the commit is reached the way the Studio
/// reaches it, not only when the repository is called directly.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late ResourceTreeRepositoryImpl treeRepo;
  late ResourceBlueprintRepositoryImpl blueprintRepo;
  late PartGenerationTaskRepositoryImpl taskRepo;
  late StreamingGenerationSessionRepositoryImpl sessionRepo;
  late SectionControlRepositoryImpl sectionRepo;
  late ResourceCreationPipeline pipeline;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_b1_stream_');
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
    sectionRepo = SectionControlRepositoryImpl(
      getDb: () => DatabaseService.database,
    );
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  /// Echoes the ids the prompt carries, exactly like a compliant model would.
  PartRawCompleter mockCompleter() {
    return ({
      required String systemPrompt,
      required String instruction,
      required LlmTask task,
      GenerationTaskHandle? taskHandle,
    }) async {
      String id(String field) =>
          RegExp('"$field": "(.*?)"').firstMatch(systemPrompt)?.group(1) ?? '';
      return jsonEncode({
        'protocol_version': 1,
        'generation_id': id('generation_id'),
        'resource_id': id('resource_id'),
        'section_id': id('section_id'),
        'part_id': id('part_id'),
        'attempt_id': id('attempt_id'),
        'content': '通过真实流式链路重新生成的正文内容。',
        'summary': 'B1 摘要',
        'status': 'completed',
      });
    };
  }

  test(
      'a real streaming regeneration invalidates the verdict and moves the section token',
      () async {
    // 1. A confirmed blueprint gives one section with one Part and its task.
    final creation = await pipeline.create(ResourceCreationRequest(
      resourceType: ResourceType.worldview,
      method: CreationMethod.aiReference,
      name: 'B1 一致性资源',
      idempotencyKey: 'idemp_b1_${DateTime.now().microsecondsSinceEpoch}',
      referenceSource: ReferenceSource.text('B1 一致性测试的参考材料...'),
    ));
    final blueprint = ResourceBlueprint(
      blueprintId: 'bp_b1_${DateTime.now().microsecondsSinceEpoch}',
      sessionId: creation.sessionId!,
      resourceType: ResourceType.worldview,
      suggestedName: 'B1 一致性资源',
      summary: '用于 B1 一致性回归',
      sections: [
        BlueprintSection(
          id: 'sec_1',
          title: '唯一章节',
          parts: [
            const BlueprintPart(
              id: 'part_1',
              sectionId: 'sec_1',
              title: '唯一部件',
              generationGoal: '写出该部件的正文',
              estimatedLength: 300,
              dependencies: [],
            ),
          ],
        ),
      ],
    );
    await blueprintRepo.saveBlueprint(blueprint);
    final confirmed = await blueprintRepo.confirmBlueprint(
      blueprintId: blueprint.blueprintId,
    );
    final resourceId = confirmed.resourceId;
    final sectionId = SectionId('${resourceId.value}_sec_1');
    final task = (await taskRepo.findTasksForResource(resourceId.value)).single;

    // 2. Real runtime wiring — no fakes below the executor boundary.
    final coordinator = PartGenerationCoordinator(
      taskRepository: taskRepo,
      blueprintRepository: blueprintRepo,
      pipeline: pipeline,
      maxConcurrency: 1,
      completer: mockCompleter(),
    );
    final service = StreamingResourceGenerationService(
      sessionRepository: sessionRepo,
      taskRepository: taskRepo,
      blueprintRepository: blueprintRepo,
      pipeline: pipeline,
      coordinator: coordinator,
    );
    final controller = StreamingResourceGenerationController(
      service: service,
      sessionRepository: sessionRepo,
    );
    // The controller owns the service's disposal.
    addTearDown(controller.dispose);
    final executor = StreamingSectionRegenerationExecutor(
      runtime: StreamingRegenerationRuntimeAdapter(
        controller: controller,
        sessionRepository: sessionRepo,
      ),
    );

    final session = await service.createSession(
      resourceId: resourceId.value,
      blueprintId: blueprint.blueprintId,
      creationSessionId: creation.sessionId!,
    );
    // A paused session is the realistic pre-state for a per-section
    // regeneration: `retryPart` moves the session to `generating_part`, and
    // the lifecycle state machine only allows that from planning / paused /
    // failed / cancelled (not from `created`).
    await service.pauseGeneration(session.sessionId);

    // 3. The section carries a verdict recorded before the regeneration.
    final before = (await sectionRepo.findSectionControlRow(sectionId))!;
    await sectionRepo.updateSectionValidation(
      id: sectionId,
      expectedUpdatedAt: before.updatedAt,
      state: SectionValidationState.valid,
      message: '人工确认无误',
    );
    final validated = (await sectionRepo.findSectionControlRow(sectionId))!;
    expect(validated.validationState, SectionValidationState.valid);

    // 4. Real section regeneration through the executor.
    final outcome = await executor.regenerate(
      SectionRegenerationRequest(
        resourceId: resourceId,
        sectionId: sectionId,
        partId: PartId(task.partId),
        taskId: task.taskId,
        blueprintId: blueprint.blueprintId,
        mode: AiRewriteMode.regenerate,
      ),
    );

    expect(outcome.success, isTrue, reason: outcome.errorMessage);
    expect(
      (await taskRepo.getPartsContent([task.partId]))[task.partId]?.content,
      '通过真实流式链路重新生成的正文内容。',
      reason: '真实链路必须确实把正文写入 resource_parts',
    );

    // 5. The B1 invariant: no stale `valid`, and the section token moved.
    final after = (await sectionRepo.findSectionControlRow(sectionId))!;
    expect(
      after.validationState,
      isNot(SectionValidationState.valid),
      reason: 'AI 改写内容后旧结论不得继续有效',
    );
    expect(after.validationState, SectionValidationState.stale);
    expect(after.validationMessage, isEmpty);
    expect(
      after.updatedAt,
      isNot(validated.updatedAt),
      reason: 'Section 令牌必须随内容变化推进',
    );

    // The token the caller now reads is the fresh one, and it still writes.
    await sectionRepo.updateSectionValidation(
      id: sectionId,
      expectedUpdatedAt: after.updatedAt,
      state: SectionValidationState.valid,
      message: '重新验证通过',
    );
    expect(
      (await sectionRepo.findSectionControlRow(sectionId))!.validationState,
      SectionValidationState.valid,
    );
  });
}
