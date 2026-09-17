import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/section_regeneration.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_edit_command.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_patch.dart';
import 'package:lt_dialogue/domain/resources/streaming_generation_runtime_contracts.dart';
import 'package:lt_dialogue/features/resource_studio/application/use_cases/streaming_section_regeneration_executor.dart';

const _resourceId = ResourceId('res_exec');
const _sectionId = SectionId('res_exec_sec_1');
const _partId = PartId('res_exec_sec_1_part_1');
const _otherPartId = PartId('res_exec_sec_1_part_2');
const _generationId = 'gen_exec_1';

void main() {
  late _FakeRuntimePort port;
  late StreamingSectionRegenerationExecutor executor;

  setUp(() {
    port = _FakeRuntimePort();
    executor = StreamingSectionRegenerationExecutor(runtime: port);
  });

  tearDown(() => port.dispose());

  SectionRegenerationRequest request({PartId partId = _partId}) =>
      SectionRegenerationRequest(
        resourceId: _resourceId,
        sectionId: _sectionId,
        partId: partId,
        taskId: 'task_exec_1',
        blueprintId: 'bp_exec_1',
        mode: AiRewriteMode.regenerate,
      );

  group('StreamingSectionRegenerationExecutor', () {
    test('accepts a correctly bound patch stream and reports completion',
        () async {
      port.replayOnRetry = () => [
            _partStarted(),
            _patchReceived(),
            PartCompleted(
              generationId: _generationId,
              resourceId: _resourceId,
              partId: _partId,
              taskId: 'task_exec_1',
              attemptId: 'att_1',
              characterCount: 17,
              timestamp: DateTime(2026),
            ),
          ];
      port.retryResult = true;

      final outcome = await executor.regenerate(request());

      expect(outcome.success, isTrue);
      expect(outcome.errorMessage, isEmpty);
      expect(outcome.characterCount, 17);
      expect(outcome.generationId, _generationId);
      expect(outcome.sectionId, _sectionId);
      expect(outcome.partId, _partId);
      expect(port.retryCalls.single.partId, _partId.value);
    });

    test('rejects a patch whose sectionId differs', () async {
      port.replayOnRetry = () => [
            _partStarted(),
            _patchReceived(sectionId: const SectionId('res_exec_sec_other')),
          ];

      final outcome = await executor.regenerate(request());

      expect(outcome.success, isFalse);
      expect(outcome.errorMessage, contains('sectionId'));
      expect(outcome.errorMessage, contains(_sectionId.value));
      expect(
        outcome.errorMessage,
        contains('res_exec_sec_other'),
        reason: '错误必须点名实际的 sectionId',
      );
    });

    test('rejects a patch whose resourceId differs', () async {
      port.replayOnRetry = () => [
            _partStarted(),
            _patchReceived(resourceId: const ResourceId('res_other')),
          ];

      final outcome = await executor.regenerate(request());

      expect(outcome.success, isFalse);
      expect(outcome.errorMessage, contains('resourceId'));
    });

    test('rejects a patch whose generationId differs', () async {
      port.replayOnRetry = () => [
            _partStarted(),
            _patchReceived(generationId: 'gen_stale'),
          ];

      final outcome = await executor.regenerate(request());

      expect(outcome.success, isFalse);
      expect(outcome.errorMessage, contains('generationId'));
    });

    test('rejects a patch bound to a sibling Part', () async {
      port.replayOnRetry = () => [
            _partStarted(),
            _patchReceived(partId: _otherPartId),
          ];

      final outcome = await executor.regenerate(request());

      expect(outcome.success, isFalse);
      expect(outcome.errorMessage, contains('partId'));
    });

    test('ignores events that belong to another Part or resource', () async {
      port.replayOnRetry = () => [
            // Another part's event is routed elsewhere and must not fail us.
            _patchReceived(eventPartId: _otherPartId),
            // Another resource's events are filtered out entirely.
            _patchReceived(eventResourceId: const ResourceId('res_other')),
            _partStarted(),
            _patchReceived(),
          ];

      final outcome = await executor.regenerate(request());

      expect(outcome.success, isTrue);
      expect(outcome.errorMessage, isEmpty);
    });

    test('reports a failed run when the runtime cannot commit', () async {
      port.replayOnRetry = () => [
            _partStarted(),
            ValidationStarted(
              generationId: _generationId,
              resourceId: _resourceId,
              partId: _partId,
              taskId: 'task_exec_1',
              attemptId: 'att_1',
              timestamp: DateTime(2026),
            ),
            ValidationFailed(
              generationId: _generationId,
              resourceId: _resourceId,
              partId: _partId,
              taskId: 'task_exec_1',
              attemptId: 'att_1',
              errorMessage: '校验未通过',
              timestamp: DateTime(2026),
            ),
          ];
      port.retryResult = false;

      final outcome = await executor.regenerate(request());

      expect(outcome.success, isFalse);
      expect(outcome.characterCount, 0);
      expect(outcome.errorMessage, 'Part 生成未完成');
      expect(outcome.generationId, _generationId);
    });

    test('propagates a thrown runtime error as a failed outcome', () async {
      port.retryError = StateError('Patch 标识与当前任务不匹配');

      final outcome = await executor.regenerate(request());

      expect(outcome.success, isFalse);
      expect(outcome.errorMessage, contains('Patch 标识与当前任务不匹配'));
      expect(port.retryCalls, hasLength(1));
    });

    test('fails without calling the runtime when no session exists', () async {
      port.sessionId = null;

      final outcome = await executor.regenerate(request());

      expect(outcome.success, isFalse);
      expect(outcome.errorMessage, contains('未找到资源'));
      expect(port.retryCalls, isEmpty);
    });
  });
}

PartStarted _partStarted() => PartStarted(
      generationId: _generationId,
      resourceId: _resourceId,
      partId: _partId,
      taskId: 'task_exec_1',
      attemptId: 'att_1',
      attemptNumber: 1,
      timestamp: DateTime(2026),
    );

/// Builds a [PatchReceived] event whose routing identity (which part/resource
/// the event belongs to) is decoupled from the identity carried inside the
/// patch. That decoupling is what lets a test model a patch that arrived for
/// the right Part but claims to be for another section, resource or part.
PatchReceived _patchReceived({
  // Event routing identity (what the runtime says this event is for).
  String eventGenerationId = _generationId,
  ResourceId eventResourceId = _resourceId,
  PartId eventPartId = _partId,
  // Patch identity (what the payload claims).
  String generationId = _generationId,
  ResourceId resourceId = _resourceId,
  SectionId sectionId = _sectionId,
  PartId partId = _partId,
}) =>
    PatchReceived(
      generationId: eventGenerationId,
      resourceId: eventResourceId,
      partId: eventPartId,
      taskId: 'task_exec_1',
      attemptId: 'att_1',
      patch: ResourceGenerationPatch(
        protocolVersion: 1,
        generationId: generationId,
        resourceId: resourceId,
        sectionId: sectionId,
        partId: partId,
        attemptId: 'att_1',
        sequence: 1,
        op: ResourcePatchOp.appendText,
        textDelta: '增量正文',
        cursor: 0,
      ),
      accumulatedLength: 4,
      timestamp: DateTime(2026),
    );

/// Fake runtime port.
///
/// The event controller is synchronous on purpose: `retryPart` delivers its
/// scripted events before returning, exactly like the real runtime emits them
/// while the Part is in flight, and the executor can therefore be asserted
/// deterministically without sleeping.
final class _FakeRuntimePort implements SectionRegenerationRuntimePort {
  String? sessionId = 'session_exec_1';
  bool retryResult = true;
  Object? retryError;
  List<GenerationRuntimeEvent> Function()? replayOnRetry;

  final List<({String sessionId, String partId})> retryCalls = [];
  final StreamController<GenerationRuntimeEvent> _events =
      StreamController<GenerationRuntimeEvent>.broadcast(sync: true);
  bool _disposed = false;

  @override
  Stream<GenerationRuntimeEvent> get events => _events.stream;

  @override
  Future<String?> latestSessionIdForResource(String resourceId) async =>
      sessionId;

  @override
  Future<bool> retryPart({
    required String sessionId,
    required String partId,
  }) async {
    retryCalls.add((sessionId: sessionId, partId: partId));
    final scripted = replayOnRetry?.call() ?? const <GenerationRuntimeEvent>[];
    for (final event in scripted) {
      if (!_disposed) _events.add(event);
    }
    final error = retryError;
    if (error != null) throw error;
    return retryResult;
  }

  void dispose() {
    _disposed = true;
    unawaited(_events.close());
  }
}
