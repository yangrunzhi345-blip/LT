import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/part_generation_coordinator.dart';
import 'package:lt_dialogue/application/resources/streaming_resource_generation_service.dart';
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
      expect(persisted?.errorMessage, contains('R01 retry failure'));
      final failure = events.whereType<GenerationFailed>().single;
      expect(failure.errorMessage, contains('R01 retry failure'));
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
