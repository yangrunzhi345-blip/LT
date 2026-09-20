import 'dart:async';
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
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_protocol.dart';
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

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_runtime_test_');
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
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  PartRawCompleter createMockCompleter({
    Map<String, String>? customResponses,
    bool Function(String partId)? shouldFail,
    bool Function(String partId)? shouldReturnTooLong,
    bool Function(String partId)? shouldReturnMalformed,
  }) {
    return ({
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
      final partMatch = RegExp(r'"part_id": "(.*?)"').firstMatch(systemPrompt);
      final attMatch =
          RegExp(r'"attempt_id": "(.*?)"').firstMatch(systemPrompt);

      final generationId = genMatch?.group(1) ?? 'gen_mock';
      final resourceId = resMatch?.group(1) ?? 'res_mock';
      final sectionId = secMatch?.group(1) ?? 'sec_mock';
      final partId = partMatch?.group(1) ?? 'part_mock';
      final attemptId = attMatch?.group(1) ?? 'att_mock';

      if (shouldFail != null && shouldFail(partId)) {
        throw StateError('Simulated LLM network error for $partId');
      }

      if (shouldReturnMalformed != null && shouldReturnMalformed(partId)) {
        return 'This is not valid JSON at all!';
      }

      var content = customResponses?[partId] ??
          '这是为部件 $partId 生成的标准高质量正文内容。故事在此处展开，细节生动详实。';

      if (shouldReturnTooLong != null && shouldReturnTooLong(partId)) {
        // Exceeds 3000 chars
        content = '超长文本' * 800;
      }

      final common = {
        'protocol_version': 1,
        'generation_id': generationId,
        'resource_id': resourceId,
        'section_id': sectionId,
        'part_id': partId,
        'attempt_id': attemptId,
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
          'summary': '$partId 的摘要',
        },
      ].map(jsonEncode).join('\n');
    };
  }

  Future<({String resourceId, String blueprintId, String sessionId})>
      setupResourceAndBlueprint({
    bool autoConfirm = true,
    bool secondPartDependsOnFirst = true,
    bool includeThirdPart = false,
  }) async {
    final creationResult = await pipeline.create(ResourceCreationRequest(
      resourceType: ResourceType.worldview,
      method: CreationMethod.aiReference,
      name: '神代天穹',
      idempotencyKey: 'idemp_${DateTime.now().microsecondsSinceEpoch}',
      referenceSource: ReferenceSource.text('神代天穹的原始传说参考资料...'),
    ));

    final bp = ResourceBlueprint(
      blueprintId: 'bp_${DateTime.now().microsecondsSinceEpoch}',
      sessionId: creationResult.sessionId!,
      resourceType: ResourceType.worldview,
      suggestedName: '神代天穹',
      summary: '神代天穹的宏大世界观',
      sections: [
        BlueprintSection(
          id: 'sec_1',
          title: '起源之章',
          parts: [
            const BlueprintPart(
              id: 'part_1',
              sectionId: 'sec_1',
              title: '天地开辟',
              generationGoal: '描写世界创生',
              estimatedLength: 800,
              dependencies: [],
            ),
            BlueprintPart(
              id: 'part_2',
              sectionId: 'sec_1',
              title: '诸神黄昏',
              generationGoal: '描写诸神之战',
              estimatedLength: 800,
              dependencies: secondPartDependsOnFirst ? ['part_1'] : [],
            ),
            if (includeThirdPart)
              const BlueprintPart(
                id: 'part_3',
                sectionId: 'sec_1',
                title: '终章',
                generationGoal: '描写世界的新纪元',
                estimatedLength: 800,
                dependencies: ['part_2'],
              ),
          ],
        ),
      ],
    );

    await blueprintRepo.saveBlueprint(bp);

    String resourceId;
    if (autoConfirm) {
      final confirmRes =
          await blueprintRepo.confirmBlueprint(blueprintId: bp.blueprintId);
      resourceId = confirmRes.resourceId.value;
    } else {
      resourceId = 'res_${creationResult.sessionId}';
    }

    return (
      resourceId: resourceId,
      blueprintId: bp.blueprintId,
      sessionId: creationResult.sessionId!,
    );
  }

  group('StreamingResourceGenerationService - Normal Flow', () {
    test('serializes independent parts for a single-active-part session',
        () async {
      final setup = await setupResourceAndBlueprint(
        autoConfirm: true,
        secondPartDependsOnFirst: false,
      );
      var inFlight = 0;
      var maxInFlight = 0;
      final successfulCompleter = createMockCompleter();
      final coordinator = PartGenerationCoordinator(
        taskRepository: taskRepo,
        blueprintRepository: blueprintRepo,
        pipeline: pipeline,
        maxConcurrency: 2,
        completer: ({
          required String systemPrompt,
          required String instruction,
          required LlmTask task,
          GenerationTaskHandle? taskHandle,
        }) async {
          inFlight++;
          maxInFlight = maxInFlight < inFlight ? inFlight : maxInFlight;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          inFlight--;
          return successfulCompleter(
            systemPrompt: systemPrompt,
            instruction: instruction,
            task: task,
            taskHandle: taskHandle,
          );
        },
      );
      final service = StreamingResourceGenerationService(
        sessionRepository: sessionRepo,
        taskRepository: taskRepo,
        blueprintRepository: blueprintRepo,
        pipeline: pipeline,
        coordinator: coordinator,
      );
      final session = await service.createSession(
        resourceId: setup.resourceId,
        blueprintId: setup.blueprintId,
        creationSessionId: setup.sessionId,
      );

      expect(
          await service.startGeneration(sessionId: session.sessionId), isTrue);
      expect(maxInFlight, 1);
      final persisted = await sessionRepo.findSession(session.sessionId);
      expect(persisted?.completedPartsCount, 2);

      service.dispose();
    });

    test('rejects a session whose resource does not match its Blueprint',
        () async {
      final setup = await setupResourceAndBlueprint(autoConfirm: true);
      final coordinator = PartGenerationCoordinator(
        taskRepository: taskRepo,
        blueprintRepository: blueprintRepo,
        pipeline: pipeline,
        completer: createMockCompleter(),
      );
      final service = StreamingResourceGenerationService(
        sessionRepository: sessionRepo,
        taskRepository: taskRepo,
        blueprintRepository: blueprintRepo,
        pipeline: pipeline,
        coordinator: coordinator,
      );

      await expectLater(
        service.createSession(
          resourceId: '${setup.resourceId}_incorrect',
          blueprintId: setup.blueprintId,
          creationSessionId: setup.sessionId,
        ),
        throwsStateError,
      );

      service.dispose();
    });

    test(
        'Full lifecycle: created -> generating_part -> receiving_patch -> validating -> committing -> completed',
        () async {
      final setup = await setupResourceAndBlueprint(autoConfirm: true);
      final completer = createMockCompleter();

      final coordinator = PartGenerationCoordinator(
        taskRepository: taskRepo,
        blueprintRepository: blueprintRepo,
        pipeline: pipeline,
        completer: completer,
        maxConcurrency: 1,
      );

      final service = StreamingResourceGenerationService(
        sessionRepository: sessionRepo,
        taskRepository: taskRepo,
        blueprintRepository: blueprintRepo,
        pipeline: pipeline,
        coordinator: coordinator,
      );

      final events = <GenerationRuntimeEvent>[];
      final sub = service.eventStream.listen(events.add);

      // 1. Create generation session
      final session = await service.createSession(
        resourceId: setup.resourceId,
        blueprintId: setup.blueprintId,
        creationSessionId: setup.sessionId,
      );

      expect(session.status, StreamingLifecycleStatus.created);
      expect(session.completedPartsCount, 0);
      expect(session.totalPartsCount, 2);

      // 2. Start generation
      final success =
          await service.startGeneration(sessionId: session.sessionId);
      expect(success, isTrue);

      // Verify final session state in DB
      final finalSession = await sessionRepo.findSession(session.sessionId);
      expect(finalSession, isNotNull);
      expect(finalSession!.status, StreamingLifecycleStatus.completed);
      expect(finalSession.completedPartsCount, 2);
      expect(finalSession.totalPartsCount, 2);

      // Verify content committed to resource_parts
      final partsMap = await taskRepo.getPartsContent([
        '${setup.resourceId}_part_1',
        '${setup.resourceId}_part_2',
      ]);
      expect(partsMap['${setup.resourceId}_part_1']?.content, isNotEmpty);
      expect(partsMap['${setup.resourceId}_part_2']?.content, isNotEmpty);

      // 3. Verify event stream coverage
      expect(events.whereType<GenerationStarted>().length, 1);
      expect(events.whereType<PartStarted>().length, 2);
      expect(events.whereType<PatchReceived>().length, greaterThanOrEqualTo(2));
      expect(events.whereType<ValidationStarted>().length, 2);
      expect(events.whereType<ValidationPassed>().length, 2);
      expect(events.whereType<PartCompleted>().length, 2);
      expect(events.whereType<GenerationCompleted>().length, 1);
      expect(events.whereType<GenerationFailed>().length, 0);

      await sub.cancel();
      service.dispose();
    });

    test(
        'Planning integration: confirms draft blueprint during startGeneration',
        () async {
      // Leave blueprint unconfirmed in setup
      final setup = await setupResourceAndBlueprint(autoConfirm: false);
      final completer = createMockCompleter();

      final coordinator = PartGenerationCoordinator(
        taskRepository: taskRepo,
        blueprintRepository: blueprintRepo,
        pipeline: pipeline,
        completer: completer,
      );

      final service = StreamingResourceGenerationService(
        sessionRepository: sessionRepo,
        taskRepository: taskRepo,
        blueprintRepository: blueprintRepo,
        pipeline: pipeline,
        coordinator: coordinator,
      );

      final session = await service.createSession(
        resourceId: setup.resourceId,
        blueprintId: setup.blueprintId,
        creationSessionId: setup.sessionId,
      );

      final success =
          await service.startGeneration(sessionId: session.sessionId);
      expect(success, isTrue);

      final confirmedBp = await blueprintRepo.findBlueprint(setup.blueprintId);
      expect(confirmedBp?.status, BlueprintStatus.confirmed);

      final finalSession = await sessionRepo.findSession(session.sessionId);
      expect(finalSession?.status, StreamingLifecycleStatus.completed);
      expect(finalSession?.completedPartsCount, 2);

      service.dispose();
    });
  });

  group(
      'StreamingResourceGenerationService - Failure, Retry and Data Consistency',
      () {
    test(
        'Validation failure: rejects Part exceeding character limits, never commits invalid part',
        () async {
      final setup = await setupResourceAndBlueprint(autoConfirm: true);
      // part_1 returns > 3000 chars
      final completer = createMockCompleter(
        shouldReturnTooLong: (partId) => partId.endsWith('part_1'),
      );

      final coordinator = PartGenerationCoordinator(
        taskRepository: taskRepo,
        blueprintRepository: blueprintRepo,
        pipeline: pipeline,
        completer: completer,
      );

      final service = StreamingResourceGenerationService(
        sessionRepository: sessionRepo,
        taskRepository: taskRepo,
        blueprintRepository: blueprintRepo,
        pipeline: pipeline,
        coordinator: coordinator,
      );

      final events = <GenerationRuntimeEvent>[];
      final sub = service.eventStream.listen(events.add);

      final session = await service.createSession(
        resourceId: setup.resourceId,
        blueprintId: setup.blueprintId,
        creationSessionId: setup.sessionId,
      );

      final success = await service.startGeneration(
        sessionId: session.sessionId,
        maxRetriesPerPart: 0,
      );
      expect(success, isFalse);

      final finalSession = await sessionRepo.findSession(session.sessionId);
      expect(finalSession?.status, StreamingLifecycleStatus.failed);

      // Data consistency: part_1 must NOT be committed
      final partsMap =
          await taskRepo.getPartsContent(['${setup.resourceId}_part_1']);
      expect(partsMap['${setup.resourceId}_part_1']?.content, isEmpty);

      // Events: ValidationFailed was emitted
      expect(
          events.whereType<ValidationFailed>().length, greaterThanOrEqualTo(1));
      expect(events.whereType<GenerationFailed>().length, 1);

      await sub.cancel();
      service.dispose();
    });

    test(
        'Malformed patch/payload: fails and leaves database consistent without commit',
        () async {
      final setup = await setupResourceAndBlueprint(autoConfirm: true);
      final completer = createMockCompleter(
        shouldReturnMalformed: (partId) => partId.endsWith('part_1'),
      );

      final coordinator = PartGenerationCoordinator(
        taskRepository: taskRepo,
        blueprintRepository: blueprintRepo,
        pipeline: pipeline,
        completer: completer,
      );

      final service = StreamingResourceGenerationService(
        sessionRepository: sessionRepo,
        taskRepository: taskRepo,
        blueprintRepository: blueprintRepo,
        pipeline: pipeline,
        coordinator: coordinator,
      );

      final session = await service.createSession(
        resourceId: setup.resourceId,
        blueprintId: setup.blueprintId,
        creationSessionId: setup.sessionId,
      );

      final success = await service.startGeneration(
        sessionId: session.sessionId,
        maxRetriesPerPart: 0,
      );
      expect(success, isFalse);

      final partsMap =
          await taskRepo.getPartsContent(['${setup.resourceId}_part_1']);
      expect(partsMap['${setup.resourceId}_part_1']?.content, isEmpty);

      service.dispose();
    });

    test(
        'Retry: retrying a failed part succeeds and updates overall session progress',
        () async {
      final setup = await setupResourceAndBlueprint(autoConfirm: true);
      var failPart2 = true;

      final completer = createMockCompleter(
        shouldFail: (partId) => partId.endsWith('part_2') && failPart2,
      );

      final coordinator = PartGenerationCoordinator(
        taskRepository: taskRepo,
        blueprintRepository: blueprintRepo,
        pipeline: pipeline,
        completer: completer,
      );

      final service = StreamingResourceGenerationService(
        sessionRepository: sessionRepo,
        taskRepository: taskRepo,
        blueprintRepository: blueprintRepo,
        pipeline: pipeline,
        coordinator: coordinator,
      );

      final session = await service.createSession(
        resourceId: setup.resourceId,
        blueprintId: setup.blueprintId,
        creationSessionId: setup.sessionId,
      );

      // Initial run: part 1 succeeds, part 2 fails
      final initialSuccess = await service.startGeneration(
        sessionId: session.sessionId,
        maxRetriesPerPart: 0,
      );
      expect(initialSuccess, isFalse);

      var sessionState = await sessionRepo.findSession(session.sessionId);
      expect(sessionState?.completedPartsCount, 1);
      expect(sessionState?.totalPartsCount, 2);

      // Now resolve the failure and retry part_2
      failPart2 = false;
      final retrySuccess = await service.retryPart(
        session.sessionId,
        '${setup.resourceId}_part_2',
      );
      expect(retrySuccess, isTrue);

      sessionState = await sessionRepo.findSession(session.sessionId);
      expect(sessionState?.completedPartsCount, 2);
      expect(sessionState?.status, StreamingLifecycleStatus.completed);

      service.dispose();
    });

    test(
        'Retry generation: resumes a failed DAG without rerunning committed parts',
        () async {
      final setup = await setupResourceAndBlueprint(
        autoConfirm: true,
        includeThirdPart: true,
      );
      var failPart3 = true;
      final callsByPart = <String, int>{};
      final successfulCompleter = createMockCompleter();
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
          final partId = RegExp(r'"part_id": "(.*?)"')
                  .firstMatch(systemPrompt)
                  ?.group(1) ??
              '';
          callsByPart.update(partId, (count) => count + 1, ifAbsent: () => 1);
          if (partId.endsWith('part_3') && failPart3) {
            throw StateError('Simulated final Part failure');
          }
          return successfulCompleter(
            systemPrompt: systemPrompt,
            instruction: instruction,
            task: task,
            taskHandle: taskHandle,
          );
        },
      );
      final service = StreamingResourceGenerationService(
        sessionRepository: sessionRepo,
        taskRepository: taskRepo,
        blueprintRepository: blueprintRepo,
        pipeline: pipeline,
        coordinator: coordinator,
      );
      final events = <GenerationRuntimeEvent>[];
      final subscription = service.eventStream.listen(events.add);
      final session = await service.createSession(
        resourceId: setup.resourceId,
        blueprintId: setup.blueprintId,
        creationSessionId: setup.sessionId,
      );

      expect(
        await service.startGeneration(
          sessionId: session.sessionId,
          maxRetriesPerPart: 0,
        ),
        isFalse,
      );
      final part1 = '${setup.resourceId}_part_1';
      final part2 = '${setup.resourceId}_part_2';
      final part3 = '${setup.resourceId}_part_3';
      final committedBefore = await taskRepo.getPartsContent([part1, part2]);
      final db = await DatabaseService.database;
      Future<int> attemptCount(String partId) async {
        final rows = await db.rawQuery(
          'SELECT COUNT(*) AS count FROM resource_generation_attempts a '
          'JOIN resource_generation_tasks t ON t.task_id = a.task_id '
          'WHERE t.part_id = ?',
          [partId],
        );
        return rows.first.values.first as int? ?? 0;
      }

      final part1AttemptsBefore = await attemptCount(part1);
      final part2AttemptsBefore = await attemptCount(part2);
      final revisionsBefore = (await db.rawQuery(
            'SELECT COUNT(*) FROM resource_revisions WHERE resource_id = ?',
            [setup.resourceId],
          ))
              .first
              .values
              .first as int? ??
          0;
      await sessionRepo.updateStatus(
        session.sessionId,
        StreamingLifecycleStatus.failed,
        currentPartId: part2,
        currentTaskId: 'stale_completed_task',
        currentAttemptId: 'stale_completed_attempt',
      );

      failPart3 = false;
      expect(await service.resumeGeneration(session.sessionId), isTrue);

      final persisted = await sessionRepo.findSession(session.sessionId);
      expect(persisted?.status, StreamingLifecycleStatus.completed);
      expect(persisted?.completedPartsCount, 3);
      expect(persisted?.currentPartId, isNull);
      expect(persisted?.currentTaskId, isNull);
      expect(persisted?.currentAttemptId, isNull);
      final committedAfter = await taskRepo.getPartsContent([part1, part2]);
      expect(committedAfter[part1]?.content, committedBefore[part1]?.content);
      expect(committedAfter[part2]?.content, committedBefore[part2]?.content);
      expect(await attemptCount(part1), part1AttemptsBefore);
      expect(await attemptCount(part2), part2AttemptsBefore);
      expect(callsByPart[part1], 1);
      expect(callsByPart[part2], 1);
      expect(callsByPart[part3], 2);
      expect(events.whereType<PartCompleted>(), hasLength(3));
      expect(
        (await db.rawQuery(
              'SELECT COUNT(*) FROM resource_revisions '
              'WHERE resource_id = ?',
              [setup.resourceId],
            ))
                .first
                .values
                .first as int? ??
            0,
        revisionsBefore,
      );

      await subscription.cancel();
      service.dispose();
    });

    test(
        'Cancellation: cancelling generation immediately stops execution and sets cancelled status',
        () async {
      final setup = await setupResourceAndBlueprint(autoConfirm: true);
      final handle = GenerationTaskHandle();

      final completer = createMockCompleter();
      final coordinator = PartGenerationCoordinator(
        taskRepository: taskRepo,
        blueprintRepository: blueprintRepo,
        pipeline: pipeline,
        completer: completer,
      );

      final service = StreamingResourceGenerationService(
        sessionRepository: sessionRepo,
        taskRepository: taskRepo,
        blueprintRepository: blueprintRepo,
        pipeline: pipeline,
        coordinator: coordinator,
      );

      final session = await service.createSession(
        resourceId: setup.resourceId,
        blueprintId: setup.blueprintId,
        creationSessionId: setup.sessionId,
      );

      // Pre-cancel handle
      handle.cancel();

      final result = await service.startGeneration(
        sessionId: session.sessionId,
        taskHandle: handle,
      );
      expect(result, isFalse);

      final sessionState = await sessionRepo.findSession(session.sessionId);
      expect(sessionState?.status, StreamingLifecycleStatus.cancelled);

      service.dispose();
    });

    test('Cancellation: stops an already running generation before commit',
        () async {
      final setup = await setupResourceAndBlueprint(autoConfirm: true);
      final started = Completer<void>();
      final release = Completer<void>();
      final successfulCompleter = createMockCompleter();
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
          if (!started.isCompleted) started.complete();
          await release.future;
          return successfulCompleter(
            systemPrompt: systemPrompt,
            instruction: instruction,
            task: task,
            taskHandle: taskHandle,
          );
        },
      );
      final service = StreamingResourceGenerationService(
        sessionRepository: sessionRepo,
        taskRepository: taskRepo,
        blueprintRepository: blueprintRepo,
        pipeline: pipeline,
        coordinator: coordinator,
      );
      final events = <GenerationRuntimeEvent>[];
      final subscription = service.eventStream.listen(events.add);
      final session = await service.createSession(
        resourceId: setup.resourceId,
        blueprintId: setup.blueprintId,
        creationSessionId: setup.sessionId,
      );

      final run = service.startGeneration(sessionId: session.sessionId);
      await started.future;
      final cancellation = service.cancelGeneration(session.sessionId);
      release.complete();

      expect(await run, isFalse);
      await cancellation;
      final persisted = await sessionRepo.findSession(session.sessionId);
      expect(persisted?.status, StreamingLifecycleStatus.cancelled);
      final parts =
          await taskRepo.getPartsContent(['${setup.resourceId}_part_1']);
      expect(parts['${setup.resourceId}_part_1']?.content, isEmpty);
      expect(events.whereType<PartCompleted>(), isEmpty);

      await subscription.cancel();
      service.dispose();
    });

    test(
        'Pause and Resume: pausing sets paused status, and resume finishes remaining tasks',
        () async {
      final setup = await setupResourceAndBlueprint(autoConfirm: true);
      final handle = GenerationTaskHandle();

      final completer = createMockCompleter();
      final coordinator = PartGenerationCoordinator(
        taskRepository: taskRepo,
        blueprintRepository: blueprintRepo,
        pipeline: pipeline,
        completer: completer,
      );

      final service = StreamingResourceGenerationService(
        sessionRepository: sessionRepo,
        taskRepository: taskRepo,
        blueprintRepository: blueprintRepo,
        pipeline: pipeline,
        coordinator: coordinator,
      );

      final session = await service.createSession(
        resourceId: setup.resourceId,
        blueprintId: setup.blueprintId,
        creationSessionId: setup.sessionId,
      );

      // Simulate pause
      await service.pauseGeneration(session.sessionId, taskHandle: handle);
      var sessionState = await sessionRepo.findSession(session.sessionId);
      expect(sessionState?.status, StreamingLifecycleStatus.paused);

      // Resume
      final resumeSuccess = await service.resumeGeneration(session.sessionId);
      expect(resumeSuccess, isTrue);

      sessionState = await sessionRepo.findSession(session.sessionId);
      expect(sessionState?.status, StreamingLifecycleStatus.completed);
      expect(sessionState?.completedPartsCount, 2);

      service.dispose();
    });

    test('Pause and Resume: pauses a running generation without committing it',
        () async {
      final setup = await setupResourceAndBlueprint(autoConfirm: true);
      final started = Completer<void>();
      final release = Completer<void>();
      final successfulCompleter = createMockCompleter();
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
          if (!started.isCompleted) started.complete();
          await release.future;
          return successfulCompleter(
            systemPrompt: systemPrompt,
            instruction: instruction,
            task: task,
            taskHandle: taskHandle,
          );
        },
      );
      final service = StreamingResourceGenerationService(
        sessionRepository: sessionRepo,
        taskRepository: taskRepo,
        blueprintRepository: blueprintRepo,
        pipeline: pipeline,
        coordinator: coordinator,
      );
      final session = await service.createSession(
        resourceId: setup.resourceId,
        blueprintId: setup.blueprintId,
        creationSessionId: setup.sessionId,
      );

      final run = service.startGeneration(sessionId: session.sessionId);
      await started.future;
      final pause = service.pauseGeneration(session.sessionId);
      release.complete();

      expect(await run, isFalse);
      await pause;
      var persisted = await sessionRepo.findSession(session.sessionId);
      expect(persisted?.status, StreamingLifecycleStatus.paused);
      final parts =
          await taskRepo.getPartsContent(['${setup.resourceId}_part_1']);
      expect(parts['${setup.resourceId}_part_1']?.content, isEmpty);

      expect(await service.resumeGeneration(session.sessionId), isTrue);
      persisted = await sessionRepo.findSession(session.sessionId);
      expect(persisted?.status, StreamingLifecycleStatus.completed);

      service.dispose();
    });

    test(
        'Pause and Resume: preserves a committed part and resumes only remaining work',
        () async {
      final setup = await setupResourceAndBlueprint(autoConfirm: true);
      final commitFinished = Completer<void>();
      final releaseCommitReturn = Completer<void>();
      final commitBlockingRepository = _AfterCommitBlockingTaskRepository(
        getDb: () => DatabaseService.database,
        commitFinished: commitFinished,
        releaseCommitReturn: releaseCommitReturn,
      );
      final callsByPart = <String, int>{};
      final successfulCompleter = createMockCompleter();
      final coordinator = PartGenerationCoordinator(
        taskRepository: commitBlockingRepository,
        blueprintRepository: blueprintRepo,
        pipeline: pipeline,
        completer: ({
          required String systemPrompt,
          required String instruction,
          required LlmTask task,
          GenerationTaskHandle? taskHandle,
        }) {
          final partId = RegExp(r'"part_id": "(.*?)"')
                  .firstMatch(systemPrompt)
                  ?.group(1) ??
              '';
          callsByPart.update(partId, (count) => count + 1, ifAbsent: () => 1);
          return successfulCompleter(
            systemPrompt: systemPrompt,
            instruction: instruction,
            task: task,
            taskHandle: taskHandle,
          );
        },
        maxConcurrency: 1,
      );
      final service = StreamingResourceGenerationService(
        sessionRepository: sessionRepo,
        taskRepository: commitBlockingRepository,
        blueprintRepository: blueprintRepo,
        pipeline: pipeline,
        coordinator: coordinator,
      );
      final events = <GenerationRuntimeEvent>[];
      final subscription = service.eventStream.listen(events.add);
      final session = await service.createSession(
        resourceId: setup.resourceId,
        blueprintId: setup.blueprintId,
        creationSessionId: setup.sessionId,
      );

      final run = service.startGeneration(sessionId: session.sessionId);
      await commitFinished.future;
      final pause = service.pauseGeneration(session.sessionId);
      releaseCommitReturn.complete();

      expect(await run, isFalse);
      await pause;
      var persisted = await sessionRepo.findSession(session.sessionId);
      expect(persisted?.status, StreamingLifecycleStatus.paused);
      expect(persisted?.completedPartsCount, 1);
      expect(events.whereType<PartCompleted>(), hasLength(1));
      final tasks = await commitBlockingRepository.findTasksForResource(
        setup.resourceId,
      );
      expect(
        tasks.where(
            (task) => task.status == PartTaskStatus.completed.storageValue),
        hasLength(1),
      );
      expect(
        tasks.where((task) =>
            task.status == PartTaskStatus.generating.storageValue ||
            task.status == PartTaskStatus.validating.storageValue),
        isEmpty,
      );

      expect(await service.resumeGeneration(session.sessionId), isTrue);
      persisted = await sessionRepo.findSession(session.sessionId);
      expect(persisted?.status, StreamingLifecycleStatus.completed);
      expect(persisted?.completedPartsCount, 2);
      expect(callsByPart['${setup.resourceId}_part_1'], 1);
      expect(callsByPart['${setup.resourceId}_part_2'], 1);
      expect(events.whereType<PartCompleted>(), hasLength(2));

      await subscription.cancel();
      service.dispose();
    });

    test(
        'Interrupted Generation Recovery: recovers orphaned in-flight tasks after app restart',
        () async {
      final setup = await setupResourceAndBlueprint(autoConfirm: true);

      // Simulate a crashed/interrupted session in SQLite
      final crashedSession = StreamingGenerationSession(
        sessionId: 'gen_crashed_1',
        resourceId: ResourceId(setup.resourceId),
        blueprintId: setup.blueprintId,
        status: StreamingLifecycleStatus.generatingPart,
        currentPartId: PartId('${setup.resourceId}_part_1'),
        currentTaskId: 'task_crashed_1',
        totalPartsCount: 2,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await sessionRepo.createSession(crashedSession);

      // Mark the task as generating in SQLite to simulate crash mid-generation
      final db = await DatabaseService.database;
      await db.update(
        'resource_generation_tasks',
        {'status': 'generating'},
        where: 'part_id = ?',
        whereArgs: ['${setup.resourceId}_part_1'],
      );

      final completer = createMockCompleter();
      final coordinator = PartGenerationCoordinator(
        taskRepository: taskRepo,
        blueprintRepository: blueprintRepo,
        pipeline: pipeline,
        completer: completer,
      );

      final service = StreamingResourceGenerationService(
        sessionRepository: sessionRepo,
        taskRepository: taskRepo,
        blueprintRepository: blueprintRepo,
        pipeline: pipeline,
        coordinator: coordinator,
      );

      // Run recovery with autoResume = true
      final recovered = await service.recoverInterruptedGeneration(
        'gen_crashed_1',
        autoResume: true,
      );
      expect(recovered, isTrue);

      final finalSession = await sessionRepo.findSession('gen_crashed_1');
      expect(finalSession?.status, StreamingLifecycleStatus.completed);
      expect(finalSession?.completedPartsCount, 2);

      service.dispose();
    });
  });
}

final class _AfterCommitBlockingTaskRepository
    extends PartGenerationTaskRepositoryImpl {
  _AfterCommitBlockingTaskRepository({
    required super.getDb,
    required this.commitFinished,
    required this.releaseCommitReturn,
  });

  final Completer<void> commitFinished;
  final Completer<void> releaseCommitReturn;
  var _hasBlocked = false;

  @override
  Future<void> commitPartContent({
    required PartGenerationResponse response,
    required String taskId,
    required String attemptId,
    required String expectedSourceToken,
  }) async {
    await super.commitPartContent(
      response: response,
      taskId: taskId,
      attemptId: attemptId,
      expectedSourceToken: expectedSourceToken,
    );
    if (!_hasBlocked) {
      _hasBlocked = true;
      commitFinished.complete();
      await releaseCommitReturn.future;
    }
  }
}
