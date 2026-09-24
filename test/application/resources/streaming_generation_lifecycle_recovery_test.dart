import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/part_generation_coordinator.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/application/resources/streaming_generation_session_repository.dart';
import 'package:lt_dialogue/application/resources/streaming_resource_generation_service.dart';
import 'package:lt_dialogue/domain/errors/app_error.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_protocol.dart';
import 'package:lt_dialogue/domain/resources/resource_revision.dart';
import 'package:lt_dialogue/domain/resources/streaming_generation_runtime_contracts.dart';
import 'package:lt_dialogue/models/llm_task.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/r01_streaming_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late R01StreamingFixture fixture;
  final services = <StreamingResourceGenerationService>[];

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_r01_lifecycle_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    fixture = R01StreamingFixture();
  });

  tearDown(() async {
    for (final service in services) {
      service.dispose();
    }
    services.clear();
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  StreamingResourceGenerationService serviceWith(PartRawCompleter completer) {
    final service = fixture.buildService(completer);
    services.add(service);
    return service;
  }

  group('R01 streaming lifecycle recovery', () {
    test(
        'should finish the final atomic commit when pause arrives during commit',
        () async {
      final setup = await fixture.createOnePartResource(
        suffix: 'pause_final_commit',
      );
      final commitStarted = Completer<void>();
      final releaseCommit = Completer<void>();
      final blockingTaskRepository = _BlockingCommitTaskRepository(
        getDb: fixture.getDb,
        commitStarted: commitStarted,
        releaseCommit: releaseCommit,
      );
      final service = StreamingResourceGenerationService(
        sessionRepository: fixture.sessionRepository,
        taskRepository: blockingTaskRepository,
        blueprintRepository: fixture.blueprintRepository,
        coordinator: PartGenerationCoordinator(
          taskRepository: blockingTaskRepository,
          blueprintRepository: fixture.blueprintRepository,
          pipeline: fixture.pipeline,
          completer: r01Completer('最后一个 Part 的正文'),
          maxConcurrency: 1,
        ),
      );
      services.add(service);
      final session = await service.createSession(
        resourceId: setup.resourceId.value,
        blueprintId: setup.blueprintId,
        creationSessionId: setup.creationSessionId,
      );

      final run = service.startGeneration(sessionId: session.sessionId);
      await commitStarted.future;
      final pause = service.pauseGeneration(session.sessionId);
      releaseCommit.complete();

      await expectLater(run, completion(isTrue));
      await expectLater(pause, completes);
      final persisted =
          await fixture.sessionRepository.findSession(session.sessionId);
      expect(persisted?.status, StreamingLifecycleStatus.completed);
      expect(persisted?.completedPartsCount, 1);
      expect(
        (await blockingTaskRepository.findTask(setup.taskId))?.status,
        PartTaskStatus.completed.storageValue,
      );
    });

    test('should pause safely during validation and resume the same task',
        () async {
      final setup = await fixture.createOnePartResource(
        suffix: 'pause_validation',
      );
      final validationPersisted = Completer<void>();
      final releaseValidation = Completer<void>();
      final blockingSessionRepository = _AfterStatusBlockingSessionRepository(
        getDb: fixture.getDb,
        blockedStatus: StreamingLifecycleStatus.validating,
        statusPersisted: validationPersisted,
        releaseStatusUpdate: releaseValidation,
      );
      var completionCalls = 0;
      final service = StreamingResourceGenerationService(
        sessionRepository: blockingSessionRepository,
        taskRepository: fixture.taskRepository,
        blueprintRepository: fixture.blueprintRepository,
        coordinator: PartGenerationCoordinator(
          taskRepository: fixture.taskRepository,
          blueprintRepository: fixture.blueprintRepository,
          pipeline: fixture.pipeline,
          completer: r01Completer(
            'validation pause 正文',
            onCall: () => completionCalls++,
          ),
          maxConcurrency: 1,
        ),
      );
      services.add(service);
      final session = await service.createSession(
        resourceId: setup.resourceId.value,
        blueprintId: setup.blueprintId,
        creationSessionId: setup.creationSessionId,
      );

      final run = service.startGeneration(sessionId: session.sessionId);
      await validationPersisted.future;
      final pause = service.pauseGeneration(session.sessionId);
      releaseValidation.complete();

      expect(await run, isFalse);
      await pause;
      var persisted =
          await fixture.sessionRepository.findSession(session.sessionId);
      expect(persisted?.status, StreamingLifecycleStatus.paused);
      expect(persisted?.completedPartsCount, 0);
      expect(
        (await fixture.taskRepository.findTask(setup.taskId))?.status,
        PartTaskStatus.ready.storageValue,
      );

      expect(await service.resumeGeneration(session.sessionId), isTrue);
      persisted =
          await fixture.sessionRepository.findSession(session.sessionId);
      expect(persisted?.status, StreamingLifecycleStatus.completed);
      expect(persisted?.completedPartsCount, 1);
      expect(completionCalls, 2);
    });

    test('should reconcile an interrupted committing session before pausing',
        () async {
      final setup = await fixture.createOnePartResource(
        suffix: 'pause_restarted_commit',
      );
      final service = serviceWith(r01Completer('重启恢复后的正文'));
      final session = await service.createSession(
        resourceId: setup.resourceId.value,
        blueprintId: setup.blueprintId,
        creationSessionId: setup.creationSessionId,
      );
      await fixture.sessionRepository.updateStatus(
        session.sessionId,
        StreamingLifecycleStatus.planning,
      );
      await fixture.sessionRepository.updateStatus(
        session.sessionId,
        StreamingLifecycleStatus.generatingPart,
      );
      await fixture.sessionRepository.updateStatus(
        session.sessionId,
        StreamingLifecycleStatus.validating,
      );
      await fixture.sessionRepository.updateStatus(
        session.sessionId,
        StreamingLifecycleStatus.committing,
      );
      final ready =
          (await fixture.taskRepository.findReadyTasks(setup.resourceId.value))
              .single;
      await fixture.taskRepository.startAttempt(
        taskId: ready.taskId,
        generationId: session.sessionId,
        attemptNumber: 1,
      );

      await service.pauseGeneration(session.sessionId);

      var persisted =
          await fixture.sessionRepository.findSession(session.sessionId);
      expect(persisted?.status, StreamingLifecycleStatus.paused);
      expect(
        (await fixture.taskRepository.findTask(setup.taskId))?.status,
        PartTaskStatus.ready.storageValue,
      );
      expect(await service.resumeGeneration(session.sessionId), isTrue);
      persisted =
          await fixture.sessionRepository.findSession(session.sessionId);
      expect(persisted?.status, StreamingLifecycleStatus.completed);
      expect(persisted?.completedPartsCount, 1);
    });

    test('should serialize rapid pause and resume', () async {
      final setup =
          await fixture.createOnePartResource(suffix: 'rapid_pause_resume');
      final generationStarted = Completer<void>();
      final releaseGeneration = Completer<void>();
      final service = serviceWith(({
        required String systemPrompt,
        required String instruction,
        required LlmTask task,
        GenerationTaskHandle? taskHandle,
      }) async {
        if (!generationStarted.isCompleted) generationStarted.complete();
        await releaseGeneration.future;
        return r01Completion(systemPrompt, '快速暂停恢复正文');
      });
      final session = await service.createSession(
        resourceId: setup.resourceId.value,
        blueprintId: setup.blueprintId,
        creationSessionId: setup.creationSessionId,
      );

      final run = service.startGeneration(sessionId: session.sessionId);
      await generationStarted.future;
      final pause = service.pauseGeneration(session.sessionId);
      final resume = service.resumeGeneration(session.sessionId);
      releaseGeneration.complete();

      expect(await run, isFalse);
      await pause;
      expect(await resume, isTrue);
      final persisted =
          await fixture.sessionRepository.findSession(session.sessionId);
      expect(persisted?.status, StreamingLifecycleStatus.completed);
      expect(persisted?.completedPartsCount, 1);
    });

    test('should treat concurrent pause requests as idempotent', () async {
      final setup = await fixture.createOnePartResource(suffix: 'double_pause');
      final generationStarted = Completer<void>();
      final releaseGeneration = Completer<void>();
      final service = serviceWith(({
        required String systemPrompt,
        required String instruction,
        required LlmTask task,
        GenerationTaskHandle? taskHandle,
      }) async {
        generationStarted.complete();
        await releaseGeneration.future;
        return r01Completion(systemPrompt, '双暂停正文');
      });
      final session = await service.createSession(
        resourceId: setup.resourceId.value,
        blueprintId: setup.blueprintId,
        creationSessionId: setup.creationSessionId,
      );

      final run = service.startGeneration(sessionId: session.sessionId);
      await generationStarted.future;
      final firstPause = service.pauseGeneration(session.sessionId);
      final secondPause = service.pauseGeneration(session.sessionId);
      releaseGeneration.complete();

      expect(await run, isFalse);
      await Future.wait([firstPause, secondPause]);
      final persisted =
          await fixture.sessionRepository.findSession(session.sessionId);
      expect(persisted?.status, StreamingLifecycleStatus.paused);
      expect(
        (await fixture.taskRepository.findTask(setup.taskId))?.status,
        PartTaskStatus.ready.storageValue,
      );
    });

    test('should give cancellation priority when pause races cancel', () async {
      final setup =
          await fixture.createOnePartResource(suffix: 'pause_cancel_race');
      final generationStarted = Completer<void>();
      final releaseGeneration = Completer<void>();
      final service = serviceWith(({
        required String systemPrompt,
        required String instruction,
        required LlmTask task,
        GenerationTaskHandle? taskHandle,
      }) async {
        generationStarted.complete();
        await releaseGeneration.future;
        return r01Completion(systemPrompt, '暂停取消竞态正文');
      });
      final session = await service.createSession(
        resourceId: setup.resourceId.value,
        blueprintId: setup.blueprintId,
        creationSessionId: setup.creationSessionId,
      );

      final run = service.startGeneration(sessionId: session.sessionId);
      await generationStarted.future;
      final pause = service.pauseGeneration(session.sessionId);
      final cancel = service.cancelGeneration(session.sessionId);
      releaseGeneration.complete();

      expect(await run, isFalse);
      await Future.wait([pause, cancel]);
      final persisted =
          await fixture.sessionRepository.findSession(session.sessionId);
      expect(persisted?.status, StreamingLifecycleStatus.cancelled);
      expect(
        (await fixture.taskRepository.findTask(setup.taskId))?.status,
        PartTaskStatus.cancelled.storageValue,
      );
    });

    test('should pause during patch reception and resume without stale state',
        () async {
      final setup =
          await fixture.createOnePartResource(suffix: 'pause_receiving_patch');
      final receivingPersisted = Completer<void>();
      final releaseReceiving = Completer<void>();
      final blockingSessionRepository = _AfterStatusBlockingSessionRepository(
        getDb: fixture.getDb,
        blockedStatus: StreamingLifecycleStatus.receivingPatch,
        statusPersisted: receivingPersisted,
        releaseStatusUpdate: releaseReceiving,
      );
      var completionCalls = 0;
      final service = StreamingResourceGenerationService(
        sessionRepository: blockingSessionRepository,
        taskRepository: fixture.taskRepository,
        blueprintRepository: fixture.blueprintRepository,
        coordinator: PartGenerationCoordinator(
          taskRepository: fixture.taskRepository,
          blueprintRepository: fixture.blueprintRepository,
          pipeline: fixture.pipeline,
          completer: r01Completer(
            'patch reception pause 正文',
            onCall: () => completionCalls++,
          ),
          maxConcurrency: 1,
        ),
      );
      services.add(service);
      final session = await service.createSession(
        resourceId: setup.resourceId.value,
        blueprintId: setup.blueprintId,
        creationSessionId: setup.creationSessionId,
      );

      final run = service.startGeneration(sessionId: session.sessionId);
      await receivingPersisted.future;
      final pause = service.pauseGeneration(session.sessionId);
      releaseReceiving.complete();

      expect(await run, isFalse);
      await pause;
      expect(
        (await fixture.sessionRepository.findSession(session.sessionId))
            ?.status,
        StreamingLifecycleStatus.paused,
      );
      expect(
        (await fixture.taskRepository.findTask(setup.taskId))?.status,
        PartTaskStatus.ready.storageValue,
      );
      expect(await service.resumeGeneration(session.sessionId), isTrue);
      expect(completionCalls, 2);
    });

    test('should keep a completed session completed when pause is requested',
        () async {
      final setup =
          await fixture.createOnePartResource(suffix: 'pause_completed');
      final service = serviceWith(r01Completer('已完成正文'));
      final session = await service.createSession(
        resourceId: setup.resourceId.value,
        blueprintId: setup.blueprintId,
        creationSessionId: setup.creationSessionId,
      );
      expect(
          await service.startGeneration(sessionId: session.sessionId), isTrue);

      await service.pauseGeneration(session.sessionId);

      expect(
        (await fixture.sessionRepository.findSession(session.sessionId))
            ?.status,
        StreamingLifecycleStatus.completed,
      );
    });

    test('should keep repeated inactive pause idempotent', () async {
      final setup =
          await fixture.createOnePartResource(suffix: 'inactive_double_pause');
      final service = serviceWith(r01Completer('未启动暂停正文'));
      final session = await service.createSession(
        resourceId: setup.resourceId.value,
        blueprintId: setup.blueprintId,
        creationSessionId: setup.creationSessionId,
      );

      await service.pauseGeneration(session.sessionId);
      await service.pauseGeneration(session.sessionId);

      expect(
        (await fixture.sessionRepository.findSession(session.sessionId))
            ?.status,
        StreamingLifecycleStatus.paused,
      );
    });

    test('should not downgrade an inactive cancelled session to paused',
        () async {
      final setup =
          await fixture.createOnePartResource(suffix: 'cancel_then_pause');
      final service = serviceWith(r01Completer('取消后暂停正文'));
      final session = await service.createSession(
        resourceId: setup.resourceId.value,
        blueprintId: setup.blueprintId,
        creationSessionId: setup.creationSessionId,
      );

      await service.cancelGeneration(session.sessionId);
      await service.pauseGeneration(session.sessionId);

      expect(
        (await fixture.sessionRepository.findSession(session.sessionId))
            ?.status,
        StreamingLifecycleStatus.cancelled,
      );
    });

    test('should pause before generation starts and resume all work', () async {
      final setup =
          await fixture.createOnePartResource(suffix: 'pause_before_start');
      var completionCalls = 0;
      final service = serviceWith(r01Completer(
        '启动前暂停正文',
        onCall: () => completionCalls++,
      ));
      final session = await service.createSession(
        resourceId: setup.resourceId.value,
        blueprintId: setup.blueprintId,
        creationSessionId: setup.creationSessionId,
      );

      await service.pauseGeneration(session.sessionId);
      expect(completionCalls, 0);
      expect(await service.resumeGeneration(session.sessionId), isTrue);

      final persisted =
          await fixture.sessionRepository.findSession(session.sessionId);
      expect(persisted?.status, StreamingLifecycleStatus.completed);
      expect(persisted?.completedPartsCount, 1);
      expect(completionCalls, 1);
    });

    test('R01-03 retryPart converges thrown failures and emits the error',
        () async {
      final setup =
          await fixture.createOnePartResource(suffix: 'retry_failure');
      var shouldThrow = false;
      final service = serviceWith(({
        required String systemPrompt,
        required String instruction,
        required LlmTask task,
        GenerationTaskHandle? taskHandle,
      }) async {
        if (shouldThrow) {
          throw StateError('R01 retry failure');
        }
        return r01Completion(systemPrompt, '首次生成正文');
      });
      final session = await service.createSession(
        resourceId: setup.resourceId.value,
        blueprintId: setup.blueprintId,
        creationSessionId: setup.creationSessionId,
      );
      expect(
          await service.startGeneration(sessionId: session.sessionId), isTrue);
      await fixture.revisionService.beginLossyOperation(
        setup.resourceId,
        cause: RevisionCause.regeneration,
        partIds: [setup.partId.value],
      );

      final events = <GenerationRuntimeEvent>[];
      final subscription = service.eventStream.listen(events.add);
      shouldThrow = true;
      final result = await service.retryPart(
        session.sessionId,
        setup.partId.value,
      );

      expect(result, isFalse);
      final persisted =
          await fixture.sessionRepository.findSession(session.sessionId);
      expect(persisted?.status, StreamingLifecycleStatus.failed);
      expect(persisted?.errorMessage, 'resourceGenerationFailed');
      final failure = events.whereType<GenerationFailed>().single;
      expect(failure.errorMessage, 'resourceGenerationFailed');
      expect(failure.error?.code, AppErrorCode.resourceGenerationFailed);
      expect(failure.failedPartId, setup.partId);
      await subscription.cancel();
    });

    test('R01-05 pause without an active run does not poison the next run',
        () async {
      final setup =
          await fixture.createOnePartResource(suffix: 'pause_cleanup');
      final service = serviceWith(r01Completer('暂停后重新启动的正文'));
      final session = await service.createSession(
        resourceId: setup.resourceId.value,
        blueprintId: setup.blueprintId,
        creationSessionId: setup.creationSessionId,
      );

      await service.pauseGeneration(session.sessionId);
      expect(
          await service.startGeneration(sessionId: session.sessionId), isTrue);
      expect(
        (await fixture.sessionRepository.findSession(session.sessionId))
            ?.status,
        StreamingLifecycleStatus.completed,
      );
    });

    test('R01-05 cancel without an active run does not poison a restarted run',
        () async {
      final setup =
          await fixture.createOnePartResource(suffix: 'cancel_cleanup');
      final service = serviceWith(r01Completer('取消后重新启动的正文'));
      final session = await service.createSession(
        resourceId: setup.resourceId.value,
        blueprintId: setup.blueprintId,
        creationSessionId: setup.creationSessionId,
      );

      await service.cancelGeneration(session.sessionId);
      await fixture.taskRepository.markTaskReady(setup.taskId);
      expect(
          await service.startGeneration(sessionId: session.sessionId), isTrue);
      expect(
        (await fixture.sessionRepository.findSession(session.sessionId))
            ?.status,
        StreamingLifecycleStatus.completed,
      );
    });

    test('R01-06 a superseded attempt cannot commit a late response', () async {
      final setup = await fixture.createOnePartResource(suffix: 'late_attempt');
      final ready =
          (await fixture.taskRepository.findReadyTasks(setup.resourceId.value))
              .single;
      final attempt1 = await fixture.taskRepository.startAttempt(
        taskId: ready.taskId,
        generationId: 'generation_1',
        attemptNumber: 1,
      );
      await fixture.taskRepository.recordFailedAttempt(
        taskId: ready.taskId,
        attemptId: attempt1.attemptId,
        errorMessage: 'superseded',
      );
      await fixture.taskRepository.markTaskReady(ready.taskId);
      final attempt2 = await fixture.taskRepository.startAttempt(
        taskId: ready.taskId,
        generationId: 'generation_2',
        attemptNumber: 2,
      );

      final lateResponse = PartGenerationResponse(
        protocolVersion: 1,
        generationId: 'generation_1',
        resourceId: setup.resourceId,
        sectionId: setup.sectionId,
        partId: setup.partId,
        attemptId: attempt1.attemptId,
        content: '旧 attempt 的迟到正文',
      );
      await expectLater(
        fixture.taskRepository.commitPartContent(
          response: lateResponse,
          taskId: ready.taskId,
          attemptId: attempt1.attemptId,
          expectedSourceToken: attempt1.sourceToken,
        ),
        throwsStateError,
      );
      expect(attempt2.attemptId, isNot(attempt1.attemptId));
      expect(
        (await fixture.taskRepository
                .getPartsContent([setup.partId.value]))[setup.partId.value]
            ?.content,
        isEmpty,
      );
    });

    test('R01-07 recovery waits for explicit resume before generating',
        () async {
      final setup = await fixture.createOnePartResource(suffix: 'resume');
      var completionCalls = 0;
      final service = serviceWith(r01Completer(
        '恢复后由用户继续生成的正文',
        onCall: () => completionCalls++,
      ));
      final session = await service.createSession(
        resourceId: setup.resourceId.value,
        blueprintId: setup.blueprintId,
        creationSessionId: setup.creationSessionId,
      );
      await fixture.sessionRepository.updateStatus(
        session.sessionId,
        StreamingLifecycleStatus.planning,
      );
      await fixture.sessionRepository.updateStatus(
        session.sessionId,
        StreamingLifecycleStatus.generatingPart,
      );
      final ready =
          (await fixture.taskRepository.findReadyTasks(setup.resourceId.value))
              .single;
      await fixture.taskRepository.startAttempt(
        taskId: ready.taskId,
        generationId: session.sessionId,
        attemptNumber: 1,
      );

      expect(
        await service.recoverInterruptedGeneration(
          session.sessionId,
          autoResume: false,
        ),
        isTrue,
      );
      expect(completionCalls, 0);
      expect(
        (await fixture.sessionRepository.findSession(session.sessionId))
            ?.status,
        StreamingLifecycleStatus.recovering,
      );
      expect(
        (await fixture.taskRepository.findTask(ready.taskId))?.status,
        PartTaskStatus.ready.storageValue,
      );

      expect(await service.resumeGeneration(session.sessionId), isTrue);
      expect(completionCalls, 1);
      expect(
        (await fixture.sessionRepository.findSession(session.sessionId))
            ?.status,
        StreamingLifecycleStatus.completed,
      );
    });
  });
}

final class _BlockingCommitTaskRepository
    extends PartGenerationTaskRepositoryImpl {
  _BlockingCommitTaskRepository({
    required super.getDb,
    required this.commitStarted,
    required this.releaseCommit,
  });

  final Completer<void> commitStarted;
  final Completer<void> releaseCommit;

  @override
  Future<void> commitPartContent({
    required PartGenerationResponse response,
    required String taskId,
    required String attemptId,
    required String expectedSourceToken,
  }) async {
    commitStarted.complete();
    await releaseCommit.future;
    await super.commitPartContent(
      response: response,
      taskId: taskId,
      attemptId: attemptId,
      expectedSourceToken: expectedSourceToken,
    );
  }
}

final class _AfterStatusBlockingSessionRepository
    extends StreamingGenerationSessionRepositoryImpl {
  _AfterStatusBlockingSessionRepository({
    required super.getDb,
    required this.blockedStatus,
    required this.statusPersisted,
    required this.releaseStatusUpdate,
  });

  final StreamingLifecycleStatus blockedStatus;
  final Completer<void> statusPersisted;
  final Completer<void> releaseStatusUpdate;
  var _hasBlocked = false;

  @override
  Future<void> updateStatus(
    String sessionId,
    StreamingLifecycleStatus status, {
    String? currentPartId,
    String? currentTaskId,
    String? currentAttemptId,
    String? errorMessage,
    bool clearActiveTask = false,
  }) async {
    await super.updateStatus(
      sessionId,
      status,
      currentPartId: currentPartId,
      currentTaskId: currentTaskId,
      currentAttemptId: currentAttemptId,
      errorMessage: errorMessage,
      clearActiveTask: clearActiveTask,
    );
    if (!_hasBlocked && status == blockedStatus) {
      _hasBlocked = true;
      statusPersisted.complete();
      await releaseStatusUpdate.future;
    }
  }
}
