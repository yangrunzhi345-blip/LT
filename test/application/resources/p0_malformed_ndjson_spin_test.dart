import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/llm/llm_gateway.dart';
import 'package:lt_dialogue/application/resources/part_generation_coordinator.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/application/resources/streaming_generation_session_repository.dart';
import 'package:lt_dialogue/application/resources/streaming_resource_generation_service.dart';
import 'package:lt_dialogue/core/debug/generation_diagnostics.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_protocol.dart';
import 'package:lt_dialogue/domain/resources/streaming_generation_runtime_contracts.dart';
import 'package:lt_dialogue/models/generation_mode.dart';
import 'package:lt_dialogue/models/llm_task.dart';
import 'package:lt_dialogue/models/scene_batch_candidate.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// P0 regression suite for the malformed-NDJSON infinite-spin freeze.
///
/// Real device evidence: the model emitted an NDJSON line with a stray `"`
/// after the JSON string, which raised `GenerationPatchParseException`. The
/// automatic retry then spun: `ATTEMPT_STARTED` followed by
/// `FUTURE_SETTLED` within milliseconds, no `HTTP_REQUEST_START`, attempt
/// numbers climbing to 10+, and the application died with
/// `Lost connection to device`.
///
/// Each test below locks one link of that chain.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  setUpAll(() {
    GenerationDiagnostics.printingEnabled = false;
  });

  tearDownAll(() {
    GenerationDiagnostics.printingEnabled = true;
  });

  late Directory tempDir;
  late _Rig rig;

  setUp(() async {
    GenerationDiagnostics.instance.resetForTesting();
    tempDir = await Directory.systemTemp.createTemp('lt_spin_test_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    rig = _Rig(DatabaseService.database);
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  // ─── 1 ────────────────────────────────────────────────────────────────

  test(
      '1. malformed NDJSON on the first attempt, valid on the second: '
      'automatic retry completes the Part without freezing', () async {
    final setup = await rig.createResource(
      parts: const [
        _PartSpec(id: 'part_1', deps: []),
      ],
    );

    var calls = 0;
    final coordinator = PartGenerationCoordinator(
      taskRepository: rig.taskRepo,
      blueprintRepository: rig.blueprintRepo,
      pipeline: rig.pipeline,
      completer: ({
        required String systemPrompt,
        required String instruction,
        required LlmTask task,
        GenerationTaskHandle? taskHandle,
      }) async {
        calls++;
        if (calls == 1) return _malformedNdjson(systemPrompt);
        return _validNdjson(systemPrompt, '重试后的正文');
      },
      maxConcurrency: 1,
    );

    final start = DateTime.now();
    final success = await coordinator.generateAllParts(
      blueprintId: setup.blueprintId,
      maxRetriesPerPart: 2,
    );
    final elapsed = DateTime.now().difference(start);

    expect(success, isTrue);
    expect(calls, 2, reason: 'exactly one automatic retry');

    final task = await rig.taskRepo
        .findTaskByPartId(_storedPartId(setup.resId, 'part_1'));
    expect(task?.status, PartTaskStatus.completed.storageValue);
    final content = await rig.taskRepo
        .getPartsContent([_storedPartId(setup.resId, 'part_1')]);
    expect(content[_storedPartId(setup.resId, 'part_1')]?.content, '重试后的正文');

    // Anti-freeze bound: a correct run is bounded by the budget, not by the
    // clock. The old bug looped hundreds of times within milliseconds.
    expect(elapsed, lessThan(const Duration(seconds: 30)));
    expect(coordinator.dispatchCountSnapshot().values.single, 2);
  });

  // ─── 2 ────────────────────────────────────────────────────────────────

  test(
      '2. malformed NDJSON every time: a finite number of attempts, no '
      'attempt-number explosion, Part failed', () async {
    final setup = await rig.createResource(
      parts: const [
        _PartSpec(id: 'part_1', deps: []),
      ],
    );

    var calls = 0;
    final coordinator = PartGenerationCoordinator(
      taskRepository: rig.taskRepo,
      blueprintRepository: rig.blueprintRepo,
      pipeline: rig.pipeline,
      completer: ({
        required String systemPrompt,
        required String instruction,
        required LlmTask task,
        GenerationTaskHandle? taskHandle,
      }) async {
        calls++;
        return _malformedNdjson(systemPrompt);
      },
      maxConcurrency: 1,
    );

    final success = await coordinator.generateAllParts(
      blueprintId: setup.blueprintId,
      maxRetriesPerPart: 2,
    );

    expect(success, isFalse);
    // maxRetriesPerPart=2 means the original attempt plus 2 retries.
    expect(calls, 3, reason: 'the attempt count must never exceed the budget');

    final task = await rig.taskRepo
        .findTaskByPartId(_storedPartId(setup.resId, 'part_1'));
    expect(task?.status, PartTaskStatus.failed.storageValue);
    expect(task?.errorMessage, isNotEmpty);
  });

  // ─── 3 ────────────────────────────────────────────────────────────────

  test(
      '3. the runtime service can legally re-enter generating_part from '
      'validating after a validation failure (automatic retry)', () async {
    // The domain edge this test locks: without it, onPartStarted throws and
    // the attempt aborts before any HTTP request.
    expect(
      StreamingLifecycleStateMachine.canTransition(
        StreamingLifecycleStatus.validating,
        StreamingLifecycleStatus.generatingPart,
      ),
      isTrue,
    );

    final setup = await rig.createResourceWithSession(
      parts: const [
        _PartSpec(id: 'part_1', deps: []),
      ],
    );

    var calls = 0;
    final gateway = _ScriptedGateway((systemPrompt) {
      calls++;
      if (calls == 1) return _malformedNdjson(systemPrompt);
      return _validNdjson(systemPrompt, '恢复后的正文');
    });

    final coordinator = PartGenerationCoordinator(
      taskRepository: rig.taskRepo,
      blueprintRepository: rig.blueprintRepo,
      pipeline: rig.pipeline,
      gateway: gateway,
      maxConcurrency: 1,
    );
    final service = StreamingResourceGenerationService(
      sessionRepository: rig.sessionRepo,
      taskRepository: rig.taskRepo,
      blueprintRepository: rig.blueprintRepo,
      pipeline: rig.pipeline,
      coordinator: coordinator,
    );

    final statuses = <StreamingLifecycleStatus>[];
    final sub = service.eventStream.listen((event) {
      if (event is PartStarted) {
        statuses.add(StreamingLifecycleStatus.generatingPart);
      }
      if (event is ValidationStarted) {
        statuses.add(StreamingLifecycleStatus.validating);
      }
    });

    final success = await service.startGeneration(
      sessionId: setup.sessionId,
      maxRetriesPerPart: 2,
    );
    await sub.cancel();

    expect(success, isTrue, reason: 'the retry must be able to succeed');
    final session = await rig.sessionRepo.findSession(setup.sessionId);
    expect(session?.status, StreamingLifecycleStatus.completed);
    // validating happened, then the retry re-entered generatingPart.
    expect(statuses, contains(StreamingLifecycleStatus.validating));
    expect(
      statuses.indexOf(StreamingLifecycleStatus.validating),
      lessThan(statuses.lastIndexOf(StreamingLifecycleStatus.generatingPart)),
    );
    service.dispose();
  });

  // ─── 4 ────────────────────────────────────────────────────────────────

  test(
      '4. a throwing onPartStarted callback leaves no started attempt and no '
      'generating task, and consumes retry budget', () async {
    final setup = await rig.createResource(
      parts: const [
        _PartSpec(id: 'part_1', deps: []),
      ],
    );

    var callbackCalls = 0;
    final coordinator = PartGenerationCoordinator(
      taskRepository: rig.taskRepo,
      blueprintRepository: rig.blueprintRepo,
      pipeline: rig.pipeline,
      completer: ({
        required String systemPrompt,
        required String instruction,
        required LlmTask task,
        GenerationTaskHandle? taskHandle,
      }) async =>
          _validNdjson(systemPrompt, '不应到达'),
      maxConcurrency: 1,
    );

    final success = await coordinator.generateAllParts(
      blueprintId: setup.blueprintId,
      maxRetriesPerPart: 1,
      callbacks: PartGenerationLifecycleCallbacks(
        onPartStarted: ({
          required generationId,
          required resourceId,
          required partId,
          required taskId,
          required attemptId,
          required attemptNumber,
        }) {
          callbackCalls++;
          throw StateError('onPartStarted 人为失败');
        },
      ),
    );

    expect(success, isFalse);
    // 1 original + 1 retry.
    expect(callbackCalls, 2);

    final task = await rig.taskRepo
        .findTaskByPartId(_storedPartId(setup.resId, 'part_1'));
    expect(task?.status, PartTaskStatus.failed.storageValue,
        reason: 'the task must not be left generating');
    expect(task?.currentAttemptId, isNotEmpty);
    final attempt = await rig.taskRepo.findAttempt(task!.currentAttemptId);
    expect(attempt?.status, isNot('started'),
        reason: 'no attempt may be left started');
  });

  // ─── 5 ────────────────────────────────────────────────────────────────

  test(
      '5. a failure after startAttempt but before HTTP_REQUEST_START is '
      'bounded and never spins', () async {
    final setup = await rig.createResource(
      parts: const [
        _PartSpec(id: 'part_1', deps: []),
      ],
    );

    // The streaming gateway throws before emitting anything, so the attempt
    // is registered but no HTTP request is ever observed.
    final gateway = _ScriptedGateway(
      (systemPrompt) => throw const _FakeTransportBreach(),
      throwBeforeStreaming: true,
    );
    final coordinator = PartGenerationCoordinator(
      taskRepository: rig.taskRepo,
      blueprintRepository: rig.blueprintRepo,
      pipeline: rig.pipeline,
      gateway: gateway,
      maxConcurrency: 1,
    );

    final success = await coordinator.generateAllParts(
      blueprintId: setup.blueprintId,
      maxRetriesPerPart: 2,
    );

    expect(success, isFalse);
    expect(gateway.calls, 3, reason: '1 original + 2 retries, then stop');
    expect(coordinator.dispatchCountSnapshot().values.single, 3);

    final task = await rig.taskRepo
        .findTaskByPartId(_storedPartId(setup.resId, 'part_1'));
    expect(task?.status, PartTaskStatus.failed.storageValue);
    // The terminal message reports the exhausted budget; the transport
    // failure itself is recorded on the attempt that hit it.
    expect(task?.errorMessage, contains('自动重试次数已用尽'));
    final attempt = await rig.taskRepo.findAttempt(task!.currentAttemptId);
    expect(attempt?.status, 'failed',
        reason: 'the attempt must be terminal, not left started');
  });

  // ─── 6 ────────────────────────────────────────────────────────────────

  test(
      '6. after the retry budget is exhausted, a recovered ready row is '
      'never dispatched again', () async {
    final setup = await rig.createResource(
      parts: const [
        _PartSpec(id: 'part_1', deps: []),
      ],
    );

    var dispatches = 0;
    final coordinator = PartGenerationCoordinator(
      taskRepository: rig.taskRepo,
      blueprintRepository: rig.blueprintRepo,
      pipeline: rig.pipeline,
      completer: ({
        required String systemPrompt,
        required String instruction,
        required LlmTask task,
        GenerationTaskHandle? taskHandle,
      }) async {
        dispatches++;
        return _malformedNdjson(systemPrompt);
      },
      maxConcurrency: 1,
    );

    final success = await coordinator.generateAllParts(
      blueprintId: setup.blueprintId,
      maxRetriesPerPart: 1,
    );
    expect(success, isFalse);
    expect(dispatches, 2);

    // Simulate the recovery path that used to bypass the retry gate: force
    // the row back to ready. `markTaskReady` takes the task id, not the part.
    final failedTask = await rig.taskRepo
        .findTaskByPartId(_storedPartId(setup.resId, 'part_1'));
    await rig.taskRepo.markTaskReady(failedTask!.taskId);

    var secondPassDispatches = 0;
    final secondCoordinator = PartGenerationCoordinator(
      taskRepository: rig.taskRepo,
      blueprintRepository: rig.blueprintRepo,
      pipeline: rig.pipeline,
      completer: ({
        required String systemPrompt,
        required String instruction,
        required LlmTask task,
        GenerationTaskHandle? taskHandle,
      }) async {
        secondPassDispatches++;
        return _malformedNdjson(systemPrompt);
      },
      maxConcurrency: 1,
    );

    final secondSuccess = await secondCoordinator.generateAllParts(
      blueprintId: setup.blueprintId,
      maxRetriesPerPart: 1,
    );

    expect(secondSuccess, isFalse);
    expect(secondPassDispatches, 2,
        reason: 'a new pass gets a new budget, but it is still bounded');
    // Exhausted rows must be terminal, not left dispatchable.
    final task = await rig.taskRepo
        .findTaskByPartId(_storedPartId(setup.resId, 'part_1'));
    expect(task?.status, PartTaskStatus.failed.storageValue);
  });

  // ─── 7 ────────────────────────────────────────────────────────────────

  test(
      '7. DAG: a permanently malformed branch fails while an independent '
      'branch completes; the session ends failed, never completed', () async {
    // A -> A2   (A permanently malformed)
    // B -> B2   (independent, healthy)
    final setup = await rig.createResourceWithSession(
      sections: const [
        _SectionSpec(id: 'sec_1', partIds: ['part_a', 'part_a2']),
        _SectionSpec(id: 'sec_2', partIds: ['part_b', 'part_b2']),
      ],
      parts: const [
        _PartSpec(id: 'part_a', deps: []),
        _PartSpec(id: 'part_a2', deps: ['part_a']),
        _PartSpec(id: 'part_b', deps: []),
        _PartSpec(id: 'part_b2', deps: ['part_b']),
      ],
    );

    final gateway = _ScriptedGateway((systemPrompt) {
      final partId = _partId(systemPrompt);
      if (partId.endsWith('part_a')) return _malformedNdjson(systemPrompt);
      return _validNdjson(systemPrompt, 'B 分支正文 $partId');
    });

    final coordinator = PartGenerationCoordinator(
      taskRepository: rig.taskRepo,
      blueprintRepository: rig.blueprintRepo,
      pipeline: rig.pipeline,
      gateway: gateway,
      maxConcurrency: 2,
    );
    final service = StreamingResourceGenerationService(
      sessionRepository: rig.sessionRepo,
      taskRepository: rig.taskRepo,
      blueprintRepository: rig.blueprintRepo,
      pipeline: rig.pipeline,
      coordinator: coordinator,
    );

    final success = await service.startGeneration(
      sessionId: setup.sessionId,
      maxRetriesPerPart: 1,
    );

    expect(success, isFalse);

    Future<String?> statusOf(String partId) async => (await rig.taskRepo
            .findTaskByPartId(_storedPartId(setup.resId, partId)))
        ?.status;

    expect(await statusOf('part_a'), PartTaskStatus.failed.storageValue);
    expect(
        await statusOf('part_a2'), isNot(PartTaskStatus.completed.storageValue),
        reason: 'a dependent of a failed Part must not complete');
    expect(await statusOf('part_b'), PartTaskStatus.completed.storageValue,
        reason: 'an independent branch must still finish');
    expect(await statusOf('part_b2'), PartTaskStatus.completed.storageValue);

    final session = await rig.sessionRepo.findSession(setup.sessionId);
    expect(session?.status, StreamingLifecycleStatus.failed);
    expect(session?.status, isNot(StreamingLifecycleStatus.completed));

    // The completed branch's content is preserved.
    final content = await rig.taskRepo
        .getPartsContent([_storedPartId(setup.resId, 'part_b')]);
    expect(content[_storedPartId(setup.resId, 'part_b')]?.content, isNotEmpty);
    service.dispose();
  });

  // ─── 8 ────────────────────────────────────────────────────────────────

  test(
      '8. the event loop keeps turning during a continuous fast-fail retry '
      'storm', () async {
    final setup = await rig.createResource(
      parts: const [
        _PartSpec(id: 'part_1', deps: []),
      ],
    );

    var uiTicks = 0;
    final heartbeat = Timer.periodic(const Duration(milliseconds: 10), (_) {
      uiTicks++;
    });

    final coordinator = PartGenerationCoordinator(
      taskRepository: rig.taskRepo,
      blueprintRepository: rig.blueprintRepo,
      pipeline: rig.pipeline,
      completer: ({
        required String systemPrompt,
        required String instruction,
        required LlmTask task,
        GenerationTaskHandle? taskHandle,
      }) async =>
          _malformedNdjson(systemPrompt),
      maxConcurrency: 1,
    );

    await coordinator.generateAllParts(
      blueprintId: setup.blueprintId,
      maxRetriesPerPart: 3,
    );
    heartbeat.cancel();

    // Without the fairness yield the fast-fail path can run to completion
    // inside one event-loop turn and the timer never fires.
    expect(uiTicks, greaterThan(0),
        reason: 'the fast-fail path must not starve timers/UI events');
  });

  // ─── 9 ────────────────────────────────────────────────────────────────

  test('9. cancellation is honoured between fast-fail attempts', () async {
    final setup = await rig.createResource(
      parts: const [
        _PartSpec(id: 'part_1', deps: []),
        _PartSpec(id: 'part_2', deps: []),
      ],
    );

    final handle = GenerationTaskHandle(taskId: 'spin_cancel');
    final coordinator = PartGenerationCoordinator(
      taskRepository: rig.taskRepo,
      blueprintRepository: rig.blueprintRepo,
      pipeline: rig.pipeline,
      completer: ({
        required String systemPrompt,
        required String instruction,
        required LlmTask task,
        GenerationTaskHandle? taskHandle,
      }) async =>
          _malformedNdjson(systemPrompt),
      maxConcurrency: 1,
    );

    final run = coordinator.generateAllParts(
      blueprintId: setup.blueprintId,
      maxRetriesPerPart: 5,
      taskHandle: handle,
    );
    // Let a couple of fast-fail cycles happen, then cancel from "outside".
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await handle.cancel();

    final success = await run;
    expect(success, isFalse);
    // Nothing may be left in flight after a cancellation.
    expect(coordinator.inFlightCount(), 0);
  });

  // ─── 10 ───────────────────────────────────────────────────────────────

  test('10. the stall watchdog still fires when every iteration re-arms it',
      () async {
    final setup = await rig.createResource(
      parts: const [
        _PartSpec(id: 'part_1', deps: []),
      ],
    );

    final coordinator = PartGenerationCoordinator(
      taskRepository: rig.taskRepo,
      blueprintRepository: rig.blueprintRepo,
      pipeline: rig.pipeline,
      completer: ({
        required String systemPrompt,
        required String instruction,
        required LlmTask task,
        GenerationTaskHandle? taskHandle,
      }) async {
        // Hang far longer than the watchdog threshold.
        await Future<void>.delayed(const Duration(seconds: 2));
        return _validNdjson(systemPrompt, '慢正文');
      },
      maxConcurrency: 1,
      stallWatchdogThreshold: const Duration(milliseconds: 120),
    );

    final run = coordinator.generateAllParts(
      blueprintId: setup.blueprintId,
      maxRetriesPerPart: 0,
    );

    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (GenerationDiagnostics.instance.dumpReasons.isEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        fail('the stall watchdog must still fire while a Part is in flight');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(
      GenerationDiagnostics.instance.dumpReasons.last,
      contains('PART_TRANSITION_STALL'),
    );

    await run;
  });

  // ─── 11 (invariant) ───────────────────────────────────────────────────

  test(
      '11. INVARIANT: dispatchCount never exceeds the attempt budget for any '
      'task, and exhausted tasks are reported', () async {
    final setup = await rig.createResource(
      sections: const [
        _SectionSpec(id: 'sec_1', partIds: ['part_1', 'part_2', 'part_3']),
      ],
      parts: const [
        _PartSpec(id: 'part_1', deps: []),
        _PartSpec(id: 'part_2', deps: []),
        _PartSpec(id: 'part_3', deps: []),
      ],
    );

    const budget = 2;
    final coordinator = PartGenerationCoordinator(
      taskRepository: rig.taskRepo,
      blueprintRepository: rig.blueprintRepo,
      pipeline: rig.pipeline,
      completer: ({
        required String systemPrompt,
        required String instruction,
        required LlmTask task,
        GenerationTaskHandle? taskHandle,
      }) async =>
          _malformedNdjson(systemPrompt),
      maxConcurrency: 3,
    );

    await coordinator.generateAllParts(
      blueprintId: setup.blueprintId,
      maxRetriesPerPart: budget - 1,
    );

    final counts = coordinator.dispatchCountSnapshot();
    expect(counts, isNotEmpty);
    for (final entry in counts.entries) {
      expect(
        entry.value,
        lessThanOrEqualTo(budget),
        reason: 'task ${entry.key} was dispatched ${entry.value} times '
            'for a budget of $budget',
      );
    }
    expect(
      GenerationDiagnostics.instance.counterValue('retry.budgetExhausted'),
      greaterThan(0),
    );
  });
}

// ─── Fixtures ──────────────────────────────────────────────────────────

final class _PartSpec {
  const _PartSpec({required this.id, required this.deps});
  final String id;
  final List<String> deps;
}

final class _SectionSpec {
  const _SectionSpec({required this.id, required this.partIds});
  final String id;
  final List<String> partIds;
}

final class _FakeTransportBreach implements Exception {
  const _FakeTransportBreach();
  @override
  String toString() => '传输中断（测试注入）';
}

String _idFor(String systemPrompt, String field) =>
    RegExp('"$field": "(.*?)"').firstMatch(systemPrompt)?.group(1) ?? '';

String _partId(String systemPrompt) => _idFor(systemPrompt, 'part_id');

/// Blueprint part ids are stored prefixed with the owning resource id, so
/// every lookup needs the composed form.
String _storedPartId(ResourceId resId, String blueprintPartId) =>
    '${resId.value}_$blueprintPartId';

/// A valid 3-patch NDJSON stream.
String _validNdjson(String systemPrompt, String content,
    {String summary = ''}) {
  final common = <String, dynamic>{
    'protocol_version': 1,
    'generation_id': _idFor(systemPrompt, 'generation_id'),
    'resource_id': _idFor(systemPrompt, 'resource_id'),
    'section_id': _idFor(systemPrompt, 'section_id'),
    'part_id': _idFor(systemPrompt, 'part_id'),
    'attempt_id': _idFor(systemPrompt, 'attempt_id'),
  };
  return [
    {...common, 'sequence': 0, 'op': 'start_part'},
    {...common, 'sequence': 1, 'op': 'append_text', 'text_delta': content},
    {
      ...common,
      'sequence': 2,
      'op': 'complete_part',
      if (summary.isNotEmpty) 'summary': summary,
    },
  ].map(jsonEncode).join('\n');
}

/// Reproduces the real-device corruption: the model closed its JSON string and
/// then emitted one extra `"` before the line ended, so the line is not valid
/// JSON. The parser must keep rejecting this (fail-closed) — the fix is in
/// the scheduler, not the parser.
String _malformedNdjson(String systemPrompt) {
  final common = <String, dynamic>{
    'protocol_version': 1,
    'generation_id': _idFor(systemPrompt, 'generation_id'),
    'resource_id': _idFor(systemPrompt, 'resource_id'),
    'section_id': _idFor(systemPrompt, 'section_id'),
    'part_id': _idFor(systemPrompt, 'part_id'),
    'attempt_id': _idFor(systemPrompt, 'attempt_id'),
  };
  final brokenSecondLine = '${jsonEncode({
        ...common,
        'sequence': 1,
        'op': 'append_text',
        'text_delta': '正文内容。',
      })}"';
  return [
    jsonEncode({...common, 'sequence': 0, 'op': 'start_part'}),
    brokenSecondLine,
    jsonEncode({...common, 'sequence': 2, 'op': 'complete_part'}),
  ].join('\n');
}

/// Streaming gateway driven by a callback; optionally throws before streaming.
///
/// Implements the application gateway interface because [PartGenerationCoordinator]
/// takes the gateway as `LlmGateway` and detects the streaming capability by
/// type; none of the non-streaming members are reachable in these tests.
final class _ScriptedGateway
    implements LlmGateway, PartGenerationStreamingGateway {
  _ScriptedGateway(this.script, {this.throwBeforeStreaming = false});

  final String Function(String systemPrompt) script;
  final bool throwBeforeStreaming;
  int calls = 0;

  @override
  bool get isConfigured => true;

  Never _unused() => throw UnimplementedError('not used');

  @override
  Future<Map<String, String>> generateConversationCharacter(String source) =>
      _unused();
  @override
  Future<Map<String, String>> generateResourceCharacter({
    required String source,
    required String worldview,
    required List<Map<String, String>> associatedCharacters,
    LlmGenerationMode? generationMode,
  }) =>
      _unused();
  @override
  Future<Map<String, dynamic>> generateDetailedResourceCharacter({
    required String source,
    String worldview = '',
    List<Map<String, String>> associatedCharacters = const [],
    int? targetTotalCharacters,
    void Function(int, int, String)? onProgress,
    LlmGenerationMode? generationMode,
  }) =>
      _unused();
  @override
  Future<List<Map<String, String>>> generateResourceNpcs({
    required String source,
    required String worldview,
    required List<Map<String, String>> associatedCharacters,
  }) =>
      _unused();
  @override
  Future<List<String>> identifyCharacterNames(String source) => _unused();
  @override
  Future<Map<String, dynamic>> generateSceneBatchCharacter({
    required String source,
    required String label,
    required String worldview,
    required List<Map<String, dynamic>> relatedCharacters,
    required SceneBatchCandidate candidate,
    required int minimumTotalLength,
    required int maximumTotalLength,
    required String detailInstruction,
  }) =>
      _unused();
  @override
  Future<Map<String, String>> generateWorldview(
    String source, {
    LlmGenerationMode? generationMode,
  }) =>
      _unused();
  @override
  Future<Map<String, dynamic>> generateDetailedWorldview(
    String source, {
    int? targetTotalCharacters,
    void Function(WorldviewGenerationProgress)? onProgress,
    LlmGenerationMode? generationMode,
  }) =>
      _unused();
  @override
  Future<Map<String, String>> imageToWorldview(String base64Image) => _unused();
  @override
  Future<Map<String, String>> imageToCharacterCard(
    String base64Image, {
    String worldview = '',
  }) =>
      _unused();
  @override
  Future<List<Map<String, String>>> textToNpcs({
    required String userPrompt,
    String worldview = '',
    String protagonistName = '',
    String protagonistRole = '',
    String protagonistPersonality = '',
    String protagonistBackground = '',
    String protagonistBodyDescription = '',
    String protagonistAppearance = '',
    List<Map<String, String>> selectedCharacters = const [],
    List<Map<String, String>> associatedCharacters = const [],
    List<Map<String, String>> existingNpcs = const [],
    List<Map<String, String>> characterRelationships = const [],
  }) =>
      _unused();
  @override
  Future<Map<String, String>> textToOpening({
    required String userPrompt,
    String worldview = '',
    String protagonistName = '',
    String protagonistRole = '',
    String protagonistPersonality = '',
    String protagonistBackground = '',
    String protagonistBodyDescription = '',
    String protagonistAppearance = '',
    List<Map<String, String>> selectedCharacters = const [],
    List<Map<String, String>> associatedCharacters = const [],
    List<Map<String, String>> existingNpcs = const [],
    List<Map<String, String>> characterRelationships = const [],
    List<Map<String, String>> npcs = const [],
  }) =>
      _unused();
  @override
  Future<String> rawCompletion({
    required String systemPrompt,
    required String instruction,
    int maximumOutputTokens = 4096,
    double temperature = .7,
    LlmTask task = LlmTask.structuredExtraction,
    GenerationTaskHandle? taskHandle,
  }) =>
      _unused();
  @override
  Future<Map<String, dynamic>> textToCreationWorld(String userPrompt) =>
      _unused();
  @override
  Future<Map<String, dynamic>> textToCreationCharacter(
    String userPrompt, {
    String worldview = '',
    List<Map<String, dynamic>> associatedCharacters = const [],
    GenerationTaskHandle? taskHandle,
    int maximumOutputTokens = 8192,
  }) =>
      _unused();
  @override
  Future<List<Map<String, dynamic>>> textToCreationNpcs(
    String userPrompt, {
    String worldview = '',
    List<Map<String, dynamic>> associatedCharacters = const [],
  }) =>
      _unused();

  @override
  Future<void> streamPartGeneration({
    required String systemPrompt,
    required String instruction,
    required LlmTask task,
    required void Function(String chunk) onChunk,
    GenerationTaskHandle? taskHandle,
  }) async {
    calls++;
    if (throwBeforeStreaming) throw const _FakeTransportBreach();
    onChunk(script(systemPrompt));
  }
}

final class _RigSetup {
  const _RigSetup({
    required this.resId,
    required this.blueprintId,
    required this.sessionId,
  });
  final ResourceId resId;
  final String blueprintId;
  final String sessionId;
}

final class _Rig {
  _Rig(Future<Database> db) {
    _getDb = () => db;
    treeRepo = ResourceTreeRepositoryImpl(getDb: _getDb);
    pipeline = ResourceCreationPipeline(
      getDb: _getDb,
      hasAiCredentials: () => true,
      treeRepository: treeRepo,
    );
    blueprintRepo = ResourceBlueprintRepositoryImpl(
      getDb: _getDb,
      treeRepository: treeRepo,
    );
    taskRepo = PartGenerationTaskRepositoryImpl(getDb: _getDb);
    sessionRepo = StreamingGenerationSessionRepositoryImpl(getDb: _getDb);
  }

  late final Future<Database> Function() _getDb;
  late final ResourceTreeRepositoryImpl treeRepo;
  late final ResourceCreationPipeline pipeline;
  late final ResourceBlueprintRepositoryImpl blueprintRepo;
  late final PartGenerationTaskRepositoryImpl taskRepo;
  late final StreamingGenerationSessionRepositoryImpl sessionRepo;

  Future<_RigSetup> createResource({
    List<_SectionSpec>? sections,
    required List<_PartSpec> parts,
  }) async {
    final specs = sections ??
        [
          _SectionSpec(
            id: 'sec_1',
            partIds: parts.map((p) => p.id).toList(),
          ),
        ];
    final creation = await pipeline.create(ResourceCreationRequest(
      resourceType: ResourceType.worldview,
      method: CreationMethod.aiReference,
      name: '自旋回归资源',
      idempotencyKey: 'spin_${DateTime.now().microsecondsSinceEpoch}',
      referenceSource: ReferenceSource.text('自旋回归参考材料。'),
    ));
    final blueprint = ResourceBlueprint(
      blueprintId: 'bp_spin_${DateTime.now().microsecondsSinceEpoch}',
      sessionId: creation.sessionId!,
      resourceType: ResourceType.worldview,
      suggestedName: '自旋回归资源',
      summary: 'P0 无限自旋回归',
      sections: [
        for (final section in specs)
          BlueprintSection(
            id: section.id,
            title: section.id,
            parts: [
              for (final partId in section.partIds)
                BlueprintPart(
                  id: partId,
                  sectionId: section.id,
                  title: partId,
                  generationGoal: '生成 $partId',
                  estimatedLength: 400,
                  dependencies: parts.firstWhere((p) => p.id == partId).deps,
                ),
            ],
          ),
      ],
    );
    await blueprintRepo.saveBlueprint(blueprint);
    final confirmation = await blueprintRepo.confirmBlueprint(
      blueprintId: blueprint.blueprintId,
    );
    return _RigSetup(
      resId: confirmation.resourceId,
      blueprintId: blueprint.blueprintId,
      sessionId: '',
    );
  }

  /// Same as [createResource] but also creates a runtime generation session,
  /// for the service-level tests.
  Future<_RigSetup> createResourceWithSession({
    List<_SectionSpec>? sections,
    required List<_PartSpec> parts,
  }) async {
    final setup = await createResource(sections: sections, parts: parts);
    final sessions = await sessionRepo.findSessionsForResource(
      setup.resId.value,
    );
    final session = sessions.isEmpty
        ? await sessionRepo.createSession(StreamingGenerationSession(
            sessionId: 'gen_spin_${DateTime.now().microsecondsSinceEpoch}',
            resourceId: setup.resId,
            blueprintId: setup.blueprintId,
            status: StreamingLifecycleStatus.created,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ))
        : sessions.last;
    return _RigSetup(
      resId: setup.resId,
      blueprintId: setup.blueprintId,
      sessionId: session.sessionId,
    );
  }
}
