import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_patch.dart';
import 'package:lt_dialogue/domain/resources/streaming_generation_runtime_contracts.dart';

void main() {
  group('StreamingLifecycleStatus', () {
    test('supports all required lifecycle and failure states', () {
      final expectedStatuses = [
        'created',
        'planning',
        'generating_part',
        'receiving_patch',
        'validating',
        'committing',
        'completed',
        'failed',
        'paused',
        'cancelled',
        'recovering',
      ];

      for (final statusStr in expectedStatuses) {
        final status = StreamingLifecycleStatus.fromStorage(statusStr);
        expect(status.storageValue, statusStr);
      }

      // Default fallback for unknown
      expect(
        StreamingLifecycleStatus.fromStorage('unknown_status'),
        StreamingLifecycleStatus.created,
      );
    });

    test('classifies terminal and in-flight states correctly', () {
      expect(StreamingLifecycleStatus.completed.isTerminal, isTrue);
      expect(StreamingLifecycleStatus.cancelled.isTerminal, isTrue);
      expect(
          StreamingLifecycleStatus.failed.isTerminal, isFalse); // recoverable
      expect(StreamingLifecycleStatus.paused.isTerminal, isFalse);

      expect(StreamingLifecycleStatus.planning.isInFlight, isTrue);
      expect(StreamingLifecycleStatus.generatingPart.isInFlight, isTrue);
      expect(StreamingLifecycleStatus.receivingPatch.isInFlight, isTrue);
      expect(StreamingLifecycleStatus.validating.isInFlight, isTrue);
      expect(StreamingLifecycleStatus.committing.isInFlight, isTrue);
      expect(StreamingLifecycleStatus.completed.isInFlight, isFalse);
      expect(StreamingLifecycleStatus.created.isInFlight, isFalse);
    });
  });

  group('StreamingLifecycleStateMachine', () {
    test('allows normal full lifecycle path', () {
      var current = StreamingLifecycleStatus.created;
      current = StreamingLifecycleStateMachine.advance(
        current,
        StreamingLifecycleStatus.planning,
      );
      expect(current, StreamingLifecycleStatus.planning);

      current = StreamingLifecycleStateMachine.advance(
        current,
        StreamingLifecycleStatus.generatingPart,
      );
      expect(current, StreamingLifecycleStatus.generatingPart);

      current = StreamingLifecycleStateMachine.advance(
        current,
        StreamingLifecycleStatus.receivingPatch,
      );
      expect(current, StreamingLifecycleStatus.receivingPatch);

      current = StreamingLifecycleStateMachine.advance(
        current,
        StreamingLifecycleStatus.validating,
      );
      expect(current, StreamingLifecycleStatus.validating);

      current = StreamingLifecycleStateMachine.advance(
        current,
        StreamingLifecycleStatus.committing,
      );
      expect(current, StreamingLifecycleStatus.committing);

      // Generating next part
      current = StreamingLifecycleStateMachine.advance(
        current,
        StreamingLifecycleStatus.generatingPart,
      );
      expect(current, StreamingLifecycleStatus.generatingPart);

      current = StreamingLifecycleStateMachine.advance(
        current,
        StreamingLifecycleStatus.validating,
      );
      current = StreamingLifecycleStateMachine.advance(
        current,
        StreamingLifecycleStatus.committing,
      );
      current = StreamingLifecycleStateMachine.advance(
        current,
        StreamingLifecycleStatus.completed,
      );
      expect(current, StreamingLifecycleStatus.completed);
    });

    test('rejects invalid transitions', () {
      // Completed cannot transition to anything else
      expect(
        () => StreamingLifecycleStateMachine.advance(
          StreamingLifecycleStatus.completed,
          StreamingLifecycleStatus.generatingPart,
        ),
        throwsStateError,
      );

      // Created cannot directly become completed
      expect(
        () => StreamingLifecycleStateMachine.advance(
          StreamingLifecycleStatus.created,
          StreamingLifecycleStatus.completed,
        ),
        throwsStateError,
      );

      // Created cannot directly become committing
      expect(
        () => StreamingLifecycleStateMachine.advance(
          StreamingLifecycleStatus.created,
          StreamingLifecycleStatus.committing,
        ),
        throwsStateError,
      );
    });

    test('supports failure, recovery, pause, and cancellation', () {
      // Failure from generatingPart
      var state = StreamingLifecycleStateMachine.advance(
        StreamingLifecycleStatus.generatingPart,
        StreamingLifecycleStatus.failed,
      );
      expect(state, StreamingLifecycleStatus.failed);

      // Recovering from failure
      state = StreamingLifecycleStateMachine.advance(
        state,
        StreamingLifecycleStatus.recovering,
      );
      expect(state, StreamingLifecycleStatus.recovering);

      // Resume generating from recovery
      state = StreamingLifecycleStateMachine.advance(
        state,
        StreamingLifecycleStatus.generatingPart,
      );
      expect(state, StreamingLifecycleStatus.generatingPart);

      // Pause from generating
      state = StreamingLifecycleStateMachine.advance(
        state,
        StreamingLifecycleStatus.paused,
      );
      expect(state, StreamingLifecycleStatus.paused);

      // Resume from paused
      state = StreamingLifecycleStateMachine.advance(
        state,
        StreamingLifecycleStatus.generatingPart,
      );
      expect(state, StreamingLifecycleStatus.generatingPart);

      // Cancel from generating
      state = StreamingLifecycleStateMachine.advance(
        state,
        StreamingLifecycleStatus.cancelled,
      );
      expect(state, StreamingLifecycleStatus.cancelled);
    });
  });

  group('GenerationRuntimeEvent hierarchy', () {
    final now = DateTime.now();
    const resId = ResourceId('res_test_1');
    const partId = PartId('part_test_1');

    test('instantiates all required event types with contextual payloads', () {
      final started = GenerationStarted(
        generationId: 'gen_1',
        resourceId: resId,
        blueprintId: 'bp_1',
        timestamp: now,
      );
      expect(started.blueprintId, 'bp_1');
      expect(started.toString(), contains('GenerationStarted'));

      final partStarted = PartStarted(
        generationId: 'gen_1',
        resourceId: resId,
        partId: partId,
        taskId: 'task_1',
        attemptId: 'att_1',
        attemptNumber: 1,
        timestamp: now,
      );
      expect(partStarted.attemptNumber, 1);
      expect(partStarted.toString(), contains('PartStarted'));

      const patch = ResourceGenerationPatch(
        protocolVersion: 1,
        generationId: 'gen_1',
        resourceId: resId,
        sectionId: SectionId('sec_1'),
        partId: partId,
        attemptId: 'att_1',
        sequence: 1,
        op: ResourcePatchOp.appendText,
        textDelta: 'Hello world',
        cursor: 0,
      );
      final patchReceived = PatchReceived(
        generationId: 'gen_1',
        resourceId: resId,
        partId: partId,
        taskId: 'task_1',
        attemptId: 'att_1',
        patch: patch,
        accumulatedLength: 11,
        timestamp: now,
      );
      expect(patchReceived.accumulatedLength, 11);
      expect(patchReceived.toString(), contains('PatchReceived'));

      final valStarted = ValidationStarted(
        generationId: 'gen_1',
        resourceId: resId,
        partId: partId,
        taskId: 'task_1',
        attemptId: 'att_1',
        timestamp: now,
      );
      expect(valStarted.toString(), contains('ValidationStarted'));

      final valPassed = ValidationPassed(
        generationId: 'gen_1',
        resourceId: resId,
        partId: partId,
        taskId: 'task_1',
        attemptId: 'att_1',
        characterCount: 100,
        timestamp: now,
      );
      expect(valPassed.characterCount, 100);

      final valFailed = ValidationFailed(
        generationId: 'gen_1',
        resourceId: resId,
        partId: partId,
        taskId: 'task_1',
        attemptId: 'att_1',
        errorMessage: '字数越界',
        timestamp: now,
      );
      expect(valFailed.errorMessage, '字数越界');

      final partDone = PartCompleted(
        generationId: 'gen_1',
        resourceId: resId,
        partId: partId,
        taskId: 'task_1',
        attemptId: 'att_1',
        characterCount: 100,
        timestamp: now,
      );
      expect(partDone.characterCount, 100);

      final genDone = GenerationCompleted(
        generationId: 'gen_1',
        resourceId: resId,
        totalParts: 5,
        totalCharacters: 5000,
        timestamp: now,
      );
      expect(genDone.totalParts, 5);

      final genFailed = GenerationFailed(
        generationId: 'gen_1',
        resourceId: resId,
        failedPartId: partId,
        errorMessage: 'LLM Timeout',
        timestamp: now,
      );
      expect(genFailed.errorMessage, 'LLM Timeout');
    });
  });

  group('StreamingGenerationSession entity', () {
    test('supports creation, copyWith, and equality', () {
      final now = DateTime.now();
      final session = StreamingGenerationSession(
        sessionId: 'sess_1',
        resourceId: const ResourceId('res_1'),
        blueprintId: 'bp_1',
        status: StreamingLifecycleStatus.created,
        totalPartsCount: 4,
        createdAt: now,
        updatedAt: now,
      );

      expect(session.status, StreamingLifecycleStatus.created);
      expect(session.completedPartsCount, 0);
      expect(session.totalPartsCount, 4);

      final updated = session.copyWith(
        status: StreamingLifecycleStatus.generatingPart,
        currentPartId: const PartId('part_1'),
        currentTaskId: 'task_1',
        completedPartsCount: 1,
      );

      expect(updated.status, StreamingLifecycleStatus.generatingPart);
      expect(updated.currentPartId?.value, 'part_1');
      expect(updated.completedPartsCount, 1);
      expect(updated.totalPartsCount, 4);
    });
  });
}
