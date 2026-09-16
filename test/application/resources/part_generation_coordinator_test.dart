import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/part_generation_coordinator.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
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

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_coord_test_');
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
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  PartRawCompleter createMockCompleter({
    int artificialDelayMs = 0,
    Map<String, String>? customResponses,
    bool Function(String partId)? shouldFail,
  }) {
    return ({
      required String systemPrompt,
      required String instruction,
      required LlmTask task,
      GenerationTaskHandle? taskHandle,
    }) async {
      if (artificialDelayMs > 0) {
        await Future.delayed(Duration(milliseconds: artificialDelayMs));
      }

      // Extract requested IDs from system prompt
      final genMatch =
          RegExp(r'"generation_id": "(.*?)"').firstMatch(systemPrompt);
      final resMatch =
          RegExp(r'"resource_id": "(.*?)"').firstMatch(systemPrompt);
      final secMatch =
          RegExp(r'"section_id": "(.*?)"').firstMatch(systemPrompt);
      final partMatch = RegExp(r'"part_id": "(.*?)"').firstMatch(systemPrompt);
      final attMatch =
          RegExp(r'"attempt_id": "(.*?)"').firstMatch(systemPrompt);

      final generationId = genMatch?.group(1) ?? 'gen_mock';
      final resourceId = resMatch?.group(1) ?? 'res_mock';
      final sectionId = secMatch?.group(1) ?? 'sec_mock';
      final partId = partMatch?.group(1) ?? 'part_mock';
      final attemptId = attMatch?.group(1) ?? 'att_mock';

      if (shouldFail != null && shouldFail(partId)) {
        throw StateError('Simulated LLM network failure for $partId');
      }

      final content =
          customResponses?[partId] ?? '这是为部件 $partId 生成的标准正文段落，描绘了生动的情节与设定。';

      final payload = {
        'protocol_version': 1,
        'generation_id': generationId,
        'resource_id': resourceId,
        'section_id': sectionId,
        'part_id': partId,
        'attempt_id': attemptId,
        'content': content,
        'summary': '$partId 的正文摘要',
        'status': 'completed',
      };

      return jsonEncode(payload);
    };
  }

  group('PartGenerationCoordinator', () {
    test(
        'Happy path: executes multi-branch DAG generation for Worldview resource',
        () async {
      final sessionResult = await pipeline.create(ResourceCreationRequest(
        resourceType: ResourceType.worldview,
        method: CreationMethod.aiReference,
        name: '星辰神话',
        idempotencyKey: 'idemp_wv_${DateTime.now().microsecondsSinceEpoch}',
        referenceSource: ReferenceSource.text('星辰神话的宏大设定...'),
      ));

      // DAG structure:
      // sec_1: part_1 (root), part_2 (deps: [part_1])
      // sec_2: part_3 (deps: [part_1]), part_4 (deps: [part_2, part_3])
      final bp = ResourceBlueprint(
        blueprintId: 'bp_worldview_dag',
        sessionId: sessionResult.sessionId!,
        resourceType: ResourceType.worldview,
        suggestedName: '星辰神话',
        summary: '宏大的星辰世界',
        sections: [
          BlueprintSection(
            id: 'sec_1',
            title: '宇宙创生',
            parts: const [
              BlueprintPart(
                id: 'part_1',
                sectionId: 'sec_1',
                title: '原初星云',
                generationGoal: '描述星云诞生',
                estimatedLength: 1000,
                dependencies: [],
              ),
              BlueprintPart(
                id: 'part_2',
                sectionId: 'sec_1',
                title: '光暗分化',
                generationGoal: '描述光的诞生',
                estimatedLength: 1000,
                dependencies: ['part_1'],
              ),
            ],
          ),
          BlueprintSection(
            id: 'sec_2',
            title: '主神时代',
            parts: const [
              BlueprintPart(
                id: 'part_3',
                sectionId: 'sec_2',
                title: '第一纪诸神',
                generationGoal: '描述诸神现世',
                estimatedLength: 1200,
                dependencies: ['part_1'],
              ),
              BlueprintPart(
                id: 'part_4',
                sectionId: 'sec_2',
                title: '创世之战',
                generationGoal: '描述诸神争霸',
                estimatedLength: 1500,
                dependencies: ['part_2', 'part_3'],
              ),
            ],
          ),
        ],
      );

      await blueprintRepo.saveBlueprint(bp);
      final confirmed = await blueprintRepo.confirmBlueprint(
        blueprintId: bp.blueprintId,
      );

      final progressSnapshots = <PartGenerationProgress>[];
      final coordinator = PartGenerationCoordinator(
        taskRepository: taskRepo,
        blueprintRepository: blueprintRepo,
        pipeline: pipeline,
        completer: createMockCompleter(),
        maxConcurrency: 2,
      );

      final success = await coordinator.generateAllParts(
        blueprintId: bp.blueprintId,
        onProgress: (p) => progressSnapshots.add(p),
      );

      expect(success, isTrue);
      expect(progressSnapshots, isNotEmpty);
      expect(progressSnapshots.last.completedTasks, 4);
      expect(progressSnapshots.last.isDone, isTrue);

      // Verify all 4 parts in database now contain content!
      final resId = confirmed.resourceId.value;
      final partsContent = await taskRepo.getPartsContent([
        '${resId}_part_1',
        '${resId}_part_2',
        '${resId}_part_3',
        '${resId}_part_4',
      ]);

      expect(partsContent.length, 4);
      for (final p in partsContent.values) {
        expect(p.content, contains('标准正文段落'));
      }
    });

    test('Generates Character card parts and NPC parts', () async {
      final sessionResult = await pipeline.create(ResourceCreationRequest(
        resourceType: ResourceType.character,
        method: CreationMethod.aiReference,
        name: '维克多',
        idempotencyKey: 'idemp_char_${DateTime.now().microsecondsSinceEpoch}',
        referenceSource: ReferenceSource.text('维克多，王国首席皇家炼金术士...'),
      ));

      final bp = ResourceBlueprint(
        blueprintId: 'bp_char_test',
        sessionId: sessionResult.sessionId!,
        resourceType: ResourceType.character,
        suggestedName: '维克多',
        summary: '首席炼金术士',
        sections: [
          BlueprintSection(
            id: 'sec_bio',
            title: '人物生平',
            parts: const [
              BlueprintPart(
                id: 'part_bg',
                sectionId: 'sec_bio',
                title: '出身早年',
                generationGoal: '描写炼金学徒时期',
                estimatedLength: 800,
                dependencies: [],
              ),
              BlueprintPart(
                id: 'part_feat',
                sectionId: 'sec_bio',
                title: '成名之役',
                generationGoal: '发明贤者之石试剂',
                estimatedLength: 1000,
                dependencies: ['part_bg'],
              ),
            ],
          ),
        ],
      );

      await blueprintRepo.saveBlueprint(bp);
      await blueprintRepo.confirmBlueprint(blueprintId: bp.blueprintId);

      final coordinator = PartGenerationCoordinator(
        taskRepository: taskRepo,
        blueprintRepository: blueprintRepo,
        pipeline: pipeline,
        completer: createMockCompleter(),
      );

      final success = await coordinator.generateAllParts(
        blueprintId: bp.blueprintId,
      );
      expect(success, isTrue);

      final isAllDone =
          await taskRepo.areAllTasksCompleted('res_${sessionResult.sessionId}');
      expect(isAllDone, isTrue);
    });

    test(
        'Bounded concurrency: never runs more than maxConcurrency tasks simultaneously',
        () async {
      final sessionResult = await pipeline.create(ResourceCreationRequest(
        resourceType: ResourceType.worldview,
        method: CreationMethod.aiReference,
        name: '并行测试',
        idempotencyKey: 'idemp_conc_${DateTime.now().microsecondsSinceEpoch}',
      ));

      // 4 independent parts
      final bp = ResourceBlueprint(
        blueprintId: 'bp_conc_test',
        sessionId: sessionResult.sessionId!,
        resourceType: ResourceType.worldview,
        suggestedName: '并行测试',
        summary: '测试并发限制',
        sections: [
          BlueprintSection(
            id: 'sec_1',
            title: '四个独立部件',
            parts: const [
              BlueprintPart(
                  id: 'part_1',
                  sectionId: 'sec_1',
                  title: 'P1',
                  generationGoal: 'G1',
                  estimatedLength: 500),
              BlueprintPart(
                  id: 'part_2',
                  sectionId: 'sec_1',
                  title: 'P2',
                  generationGoal: 'G2',
                  estimatedLength: 500),
              BlueprintPart(
                  id: 'part_3',
                  sectionId: 'sec_1',
                  title: 'P3',
                  generationGoal: 'G3',
                  estimatedLength: 500),
              BlueprintPart(
                  id: 'part_4',
                  sectionId: 'sec_1',
                  title: 'P4',
                  generationGoal: 'G4',
                  estimatedLength: 500),
            ],
          ),
        ],
      );

      await blueprintRepo.saveBlueprint(bp);
      await blueprintRepo.confirmBlueprint(blueprintId: bp.blueprintId);

      var maxObservedInFlight = 0;
      var activeCount = 0;

      final coordinator = PartGenerationCoordinator(
        taskRepository: taskRepo,
        blueprintRepository: blueprintRepo,
        pipeline: pipeline,
        maxConcurrency: 2, // Strict concurrency cap of 2
        completer: ({
          required String systemPrompt,
          required String instruction,
          required LlmTask task,
          GenerationTaskHandle? taskHandle,
        }) async {
          activeCount++;
          if (activeCount > maxObservedInFlight) {
            maxObservedInFlight = activeCount;
          }
          await Future.delayed(const Duration(milliseconds: 30));
          activeCount--;

          final partMatch =
              RegExp(r'"part_id": "(.*?)"').firstMatch(systemPrompt);
          final resMatch =
              RegExp(r'"resource_id": "(.*?)"').firstMatch(systemPrompt);
          final secMatch =
              RegExp(r'"section_id": "(.*?)"').firstMatch(systemPrompt);
          final genMatch =
              RegExp(r'"generation_id": "(.*?)"').firstMatch(systemPrompt);
          final attMatch =
              RegExp(r'"attempt_id": "(.*?)"').firstMatch(systemPrompt);

          return jsonEncode({
            'protocol_version': 1,
            'generation_id': genMatch?.group(1) ?? '',
            'resource_id': resMatch?.group(1) ?? '',
            'section_id': secMatch?.group(1) ?? '',
            'part_id': partMatch?.group(1) ?? '',
            'attempt_id': attMatch?.group(1) ?? '',
            'content': '正文',
            'status': 'completed',
          });
        },
      );

      final success =
          await coordinator.generateAllParts(blueprintId: bp.blueprintId);
      expect(success, isTrue);
      expect(maxObservedInFlight, lessThanOrEqualTo(2));
      expect(maxObservedInFlight, greaterThan(0));
    });

    test('Cancellation: stops generation and marks active tasks cancelled',
        () async {
      final sessionResult = await pipeline.create(ResourceCreationRequest(
        resourceType: ResourceType.worldview,
        method: CreationMethod.aiReference,
        name: '取消测试',
        idempotencyKey: 'idemp_cancel_${DateTime.now().microsecondsSinceEpoch}',
      ));

      final bp = ResourceBlueprint(
        blueprintId: 'bp_cancel_test',
        sessionId: sessionResult.sessionId!,
        resourceType: ResourceType.worldview,
        suggestedName: '取消测试',
        summary: '测试取消',
        sections: [
          BlueprintSection(
            id: 'sec_1',
            title: '章节',
            parts: const [
              BlueprintPart(
                  id: 'part_1',
                  sectionId: 'sec_1',
                  title: 'P1',
                  generationGoal: 'G1',
                  estimatedLength: 500),
              BlueprintPart(
                  id: 'part_2',
                  sectionId: 'sec_1',
                  title: 'P2',
                  generationGoal: 'G2',
                  estimatedLength: 500,
                  dependencies: ['part_1']),
            ],
          ),
        ],
      );

      await blueprintRepo.saveBlueprint(bp);
      final confirmed =
          await blueprintRepo.confirmBlueprint(blueprintId: bp.blueprintId);

      final handle = GenerationTaskHandle();

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
          // Cancel while completer is in-flight
          handle.cancel();
          await Future.delayed(const Duration(milliseconds: 20));

          final partMatch =
              RegExp(r'"part_id": "(.*?)"').firstMatch(systemPrompt);
          final resMatch =
              RegExp(r'"resource_id": "(.*?)"').firstMatch(systemPrompt);
          final secMatch =
              RegExp(r'"section_id": "(.*?)"').firstMatch(systemPrompt);
          final genMatch =
              RegExp(r'"generation_id": "(.*?)"').firstMatch(systemPrompt);
          final attMatch =
              RegExp(r'"attempt_id": "(.*?)"').firstMatch(systemPrompt);

          return jsonEncode({
            'protocol_version': 1,
            'generation_id': genMatch?.group(1) ?? '',
            'resource_id': resMatch?.group(1) ?? '',
            'section_id': secMatch?.group(1) ?? '',
            'part_id': partMatch?.group(1) ?? '',
            'attempt_id': attMatch?.group(1) ?? '',
            'content': '晚到的内容',
            'status': 'completed',
          });
        },
      );

      final success = await coordinator.generateAllParts(
        blueprintId: bp.blueprintId,
        taskHandle: handle,
      );

      expect(success, isFalse);

      final tasks =
          await taskRepo.findTasksForResource(confirmed.resourceId.value);
      // At least one task was cancelled
      expect(tasks.any((t) => t.status == 'cancelled'), isTrue);
    });

    test(
        'Retry single part: regenerates a specific failed part without touching others',
        () async {
      final sessionResult = await pipeline.create(ResourceCreationRequest(
        resourceType: ResourceType.worldview,
        method: CreationMethod.aiReference,
        name: '重试测试',
        idempotencyKey: 'idemp_retry_${DateTime.now().microsecondsSinceEpoch}',
      ));

      final bp = ResourceBlueprint(
        blueprintId: 'bp_single_retry',
        sessionId: sessionResult.sessionId!,
        resourceType: ResourceType.worldview,
        suggestedName: '重试测试',
        summary: '测试单部件重试',
        sections: [
          BlueprintSection(
            id: 'sec_1',
            title: '章节',
            parts: const [
              BlueprintPart(
                  id: 'part_1',
                  sectionId: 'sec_1',
                  title: 'P1',
                  generationGoal: 'G1',
                  estimatedLength: 500),
            ],
          ),
        ],
      );

      await blueprintRepo.saveBlueprint(bp);
      final confirmed =
          await blueprintRepo.confirmBlueprint(blueprintId: bp.blueprintId);
      final resId = confirmed.resourceId.value;

      var failFirstTime = true;
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
          if (failFirstTime) {
            failFirstTime = false;
            throw StateError('Initial network timeout');
          }
          final partMatch =
              RegExp(r'"part_id": "(.*?)"').firstMatch(systemPrompt);
          final resMatch =
              RegExp(r'"resource_id": "(.*?)"').firstMatch(systemPrompt);
          final secMatch =
              RegExp(r'"section_id": "(.*?)"').firstMatch(systemPrompt);
          final genMatch =
              RegExp(r'"generation_id": "(.*?)"').firstMatch(systemPrompt);
          final attMatch =
              RegExp(r'"attempt_id": "(.*?)"').firstMatch(systemPrompt);

          return jsonEncode({
            'protocol_version': 1,
            'generation_id': genMatch?.group(1) ?? '',
            'resource_id': resMatch?.group(1) ?? '',
            'section_id': secMatch?.group(1) ?? '',
            'part_id': partMatch?.group(1) ?? '',
            'attempt_id': attMatch?.group(1) ?? '',
            'content': '重试成功后的正文',
            'status': 'completed',
          });
        },
      );

      // Try generating with 0 retries
      final initialResult = await coordinator.generateAllParts(
        blueprintId: bp.blueprintId,
        maxRetriesPerPart: 0,
      );
      expect(initialResult, isFalse);

      final failedTask = await taskRepo.findTaskByPartId('${resId}_part_1');
      expect(failedTask?.status, 'failed');

      // Now invoke retrySinglePart
      final retrySuccess = await coordinator.retrySinglePart(
        blueprintId: bp.blueprintId,
        partId: '${resId}_part_1',
      );
      expect(retrySuccess, isTrue);

      final completedTask = await taskRepo.findTaskByPartId('${resId}_part_1');
      expect(completedTask?.status, 'completed');

      final content = await taskRepo.getPartsContent(['${resId}_part_1']);
      expect(content['${resId}_part_1']?.content, '重试成功后的正文');
    });
  });
}
