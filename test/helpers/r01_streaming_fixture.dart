import 'dart:convert';

import 'package:lt_dialogue/application/resources/part_generation_coordinator.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_service.dart';
import 'package:lt_dialogue/application/resources/streaming_generation_session_repository.dart';
import 'package:lt_dialogue/application/resources/streaming_resource_generation_service.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/models/llm_task.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:sqflite/sqflite.dart';

final class R01StreamingFixture {
  R01StreamingFixture() {
    treeRepository = ResourceTreeRepositoryImpl(getDb: getDb);
    revisionRepository = ResourceRevisionRepositoryImpl(getDb: getDb);
    revisionCapture = RevisionCaptureEngine(
      revisionRepository: revisionRepository,
      treeBoundary: treeRepository,
    );
    taskRepository = PartGenerationTaskRepositoryImpl(
      getDb: getDb,
      revisionBoundary: revisionCapture,
    );
    blueprintRepository = ResourceBlueprintRepositoryImpl(
      getDb: getDb,
      treeRepository: treeRepository,
      revisionCapture: revisionCapture,
    );
    pipeline = ResourceCreationPipeline(
      getDb: getDb,
      hasAiCredentials: () => true,
      treeRepository: treeRepository,
      blueprintRepository: blueprintRepository,
      generationTaskRepository: taskRepository,
      revisionCapture: revisionCapture,
    );
    sessionRepository = StreamingGenerationSessionRepositoryImpl(getDb: getDb);
    revisionService = ResourceRevisionService(
      revisionRepository: revisionRepository,
      captureEngine: revisionCapture,
      treeBoundary: treeRepository,
      getDb: getDb,
      taskReset: taskRepository,
    );
  }

  Future<Database> getDb() => DatabaseService.database;

  late final ResourceTreeRepositoryImpl treeRepository;
  late final ResourceRevisionRepositoryImpl revisionRepository;
  late final RevisionCaptureEngine revisionCapture;
  late final PartGenerationTaskRepositoryImpl taskRepository;
  late final ResourceBlueprintRepositoryImpl blueprintRepository;
  late final ResourceCreationPipeline pipeline;
  late final StreamingGenerationSessionRepositoryImpl sessionRepository;
  late final ResourceRevisionService revisionService;

  Future<R01ResourceSetup> createOnePartResource({
    String suffix = 'default',
  }) async {
    final creation = await pipeline.create(ResourceCreationRequest(
      resourceType: ResourceType.worldview,
      method: CreationMethod.aiReference,
      name: 'R01 流式资源 $suffix',
      idempotencyKey: 'r01_$suffix',
      referenceSource: ReferenceSource.text('R01 恢复与重新生成参考材料'),
    ));
    final blueprint = ResourceBlueprint(
      blueprintId: 'bp_r01_$suffix',
      sessionId: creation.sessionId!,
      resourceType: ResourceType.worldview,
      suggestedName: 'R01 流式资源 $suffix',
      summary: 'R01 生命周期测试',
      sections: [
        BlueprintSection(
          id: 'sec_1',
          title: '第一章',
          parts: [
            const BlueprintPart(
              id: 'part_1',
              sectionId: 'sec_1',
              title: '第一节',
              generationGoal: '生成 R01 正文',
              estimatedLength: 300,
              dependencies: [],
            ),
          ],
        ),
      ],
    );
    await blueprintRepository.saveBlueprint(blueprint);
    final confirmation = await blueprintRepository.confirmBlueprint(
      blueprintId: blueprint.blueprintId,
    );
    final resourceId = confirmation.resourceId;
    final task =
        (await taskRepository.findTasksForResource(resourceId.value)).single;
    return R01ResourceSetup(
      resourceId: resourceId,
      sectionId: SectionId('${resourceId.value}_sec_1'),
      partId: PartId(task.partId),
      taskId: task.taskId,
      blueprintId: blueprint.blueprintId,
      creationSessionId: creation.sessionId!,
    );
  }

  StreamingResourceGenerationService buildService(PartRawCompleter completer) {
    return StreamingResourceGenerationService(
      sessionRepository: sessionRepository,
      taskRepository: taskRepository,
      blueprintRepository: blueprintRepository,
      coordinator: PartGenerationCoordinator(
        taskRepository: taskRepository,
        blueprintRepository: blueprintRepository,
        pipeline: pipeline,
        completer: completer,
        maxConcurrency: 1,
      ),
    );
  }
}

final class R01ResourceSetup {
  const R01ResourceSetup({
    required this.resourceId,
    required this.sectionId,
    required this.partId,
    required this.taskId,
    required this.blueprintId,
    required this.creationSessionId,
  });

  final ResourceId resourceId;
  final SectionId sectionId;
  final PartId partId;
  final String taskId;
  final String blueprintId;
  final String creationSessionId;
}

String r01Completion(String systemPrompt, String content) {
  String id(String field) =>
      RegExp('"$field": "(.*?)"').firstMatch(systemPrompt)?.group(1) ?? '';
  return jsonEncode({
    'protocol_version': 1,
    'generation_id': id('generation_id'),
    'resource_id': id('resource_id'),
    'section_id': id('section_id'),
    'part_id': id('part_id'),
    'attempt_id': id('attempt_id'),
    'content': content,
    'summary': 'R01 摘要',
    'status': 'completed',
  });
}

PartRawCompleter r01Completer(
  String content, {
  void Function()? onCall,
}) {
  return ({
    required String systemPrompt,
    required String instruction,
    required LlmTask task,
    GenerationTaskHandle? taskHandle,
  }) async {
    onCall?.call();
    return r01Completion(systemPrompt, content);
  };
}
