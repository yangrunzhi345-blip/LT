import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/llm/llm_gateway.dart';
import 'package:lt_dialogue/application/resources/generation_patch_parser.dart';
import 'package:lt_dialogue/application/resources/part_generation_coordinator.dart';
import 'package:lt_dialogue/domain/errors/app_error.dart';
import 'package:lt_dialogue/models/llm_task.dart';
import 'package:lt_dialogue/services/llm_service.dart';

import '../../helpers/phase10_fixture.dart';
import '../../helpers/r01_streaming_fixture.dart';

void main() {
  group('Patch sequence integrity production SQLite path', () {
    final fixture = Phase10Fixture();
    late R01StreamingFixture stack;
    setUp(() async {
      await fixture.setUp(prefix: 'lt_patch_conflict_');
      stack = R01StreamingFixture();
    });
    tearDown(fixture.tearDown);

    test(
        'should preserve valid saved content and revision history when regeneration conflicts',
        () async {
      final setup = await stack.createOnePartResource(suffix: 'saved_sequence');
      const saved = '已保存并确认的原文🙂。';
      final initial = PartGenerationCoordinator(
          taskRepository: stack.taskRepository,
          blueprintRepository: stack.blueprintRepository,
          pipeline: stack.pipeline,
          completer: r01Completer(saved),
          maxConcurrency: 1);
      expect(await initial.generateAllParts(blueprintId: setup.blueprintId),
          isTrue);
      await fixture.db.transaction((txn) => stack.taskRepository
          .reopenCompletedTasksInTransaction(txn,
              partIds: [setup.partId.value],
              now: DateTime.now().toUtc().toIso8601String()));
      const preservedTables = [
        'resource_parts',
        'resource_sections',
        'resources',
        'resource_revisions'
      ];
      final before = {
        for (final table in preservedTables)
          table: await fixture.db.query(table)
      };
      final oldAttempt =
          (await fixture.db.query('resource_generation_attempts')).single;
      final gateway = _PatchGateway(true);
      final regeneration = PartGenerationCoordinator(
          taskRepository: stack.taskRepository,
          blueprintRepository: stack.blueprintRepository,
          pipeline: stack.pipeline,
          gateway: gateway,
          maxConcurrency: 1);
      await expectLater(
          regeneration.retrySinglePart(
              blueprintId: setup.blueprintId, partId: setup.partId.value),
          throwsA(isA<PatchSequenceConflictException>()));
      for (final table in preservedTables) {
        expect(await fixture.db.query(table), before[table],
            reason: '$table must be unchanged');
      }
      final attempts = await fixture.db.query('resource_generation_attempts');
      expect(attempts, hasLength(2));
      expect(
          attempts.firstWhere(
              (row) => row['attempt_id'] == oldAttempt['attempt_id']),
          oldAttempt);
      expect(attempts.where((row) => row['status'] == 'failed'), hasLength(1));
      expect(
          (await stack.taskRepository
                  .getPartsContent([setup.partId.value]))[setup.partId.value]!
              .content,
          saved);
      expect(gateway.calls, 1);
    });

    for (final streaming in [true, false]) {
      for (final conflict in [true, false]) {
        test(
            'should ${conflict ? 'reject conflicting' : 'accept identical'} replay with streaming=$streaming',
            () async {
          final setup = await stack.createOnePartResource(suffix: 'sequence');
          await stack.taskRepository.findReadyTasks(setup.resourceId.value);
          final before = await fixture.db.query('resource_revisions');
          final gateway = _PatchGateway(conflict);
          var validationFailed = 0;
          final displayedDeltas = StringBuffer();
          var patchCallbacks = 0;
          final coordinator = PartGenerationCoordinator(
            taskRepository: stack.taskRepository,
            blueprintRepository: stack.blueprintRepository,
            pipeline: stack.pipeline,
            gateway: streaming ? gateway : null,
            completer: streaming ? null : gateway.rawCompletion,
            maxConcurrency: 1,
          );
          final operation = coordinator.retrySinglePart(
            blueprintId: setup.blueprintId,
            partId: setup.partId.value,
            callbacks: PartGenerationLifecycleCallbacks(onPatchReceived: ({
              required generationId,
              required resourceId,
              required partId,
              required taskId,
              required attemptId,
              required patch,
              required accumulatedLength,
            }) {
              patchCallbacks++;
              displayedDeltas.write(patch.textDelta);
            }, onValidationFailed: ({
              required generationId,
              required resourceId,
              required partId,
              required taskId,
              required attemptId,
              required errorMessage,
            }) {
              validationFailed++;
              expect(errorMessage, AppErrorCode.resourceParseFailed.name);
            }),
          );
          if (conflict) {
            await expectLater(
                operation, throwsA(isA<PatchSequenceConflictException>()));
            expect(validationFailed, 1);
            expect(await fixture.db.query('resource_revisions'), before);
            expect((await stack.taskRepository.findTask(setup.taskId))!.status,
                'failed');
            final rows = await fixture.db.query('resource_generation_attempts');
            expect(rows.single['status'], 'failed');
            expect(rows.single['error_message'],
                AppErrorCode.resourceParseFailed.name);
          } else {
            expect(await operation, isTrue);
            expect(validationFailed, 0);
            expect(displayedDeltas.toString(), _PatchGateway.body);
            expect(patchCallbacks, 3);
            expect((await stack.taskRepository.findTask(setup.taskId))!.status,
                'completed');
          }
          final content =
              await stack.taskRepository.getPartsContent([setup.partId.value]);
          expect(content[setup.partId.value]!.content,
              conflict ? '' : _PatchGateway.body);
          expect(gateway.calls, 1);
        });
      }
    }
  });
}

final class _PatchGateway
    implements LlmGateway, PartGenerationStreamingGateway {
  _PatchGateway(this.conflict);
  final bool conflict;
  int calls = 0;
  static const body = '完整正文🙂，引号"、反斜线\\与换行\n均应完整保存。';
  String get payload => [
        {'sequence': 0, 'op': 'start_part'},
        {'sequence': 1, 'op': 'append_text', 'text_delta': body},
        {
          'sequence': 1,
          'op': 'append_text',
          'text_delta': conflict ? '冲突正文' * 100 : body,
          'cursor': 0
        },
        {'sequence': 2, 'op': 'complete_part', 'summary': '摘要'},
        if (!conflict)
          {
            'sequence': 2,
            'op': 'complete_part',
            'summary': '摘要',
            'cursor': body.length
          },
      ].map(jsonEncode).join('\n');

  @override
  bool get isConfigured => true;
  @override
  Future<String> rawCompletion(
      {required String systemPrompt,
      required String instruction,
      int maximumOutputTokens = 4096,
      double temperature = .7,
      LlmTask task = LlmTask.structuredExtraction,
      GenerationTaskHandle? taskHandle}) async {
    calls++;
    return payload;
  }

  @override
  Future<void> streamPartGeneration(
      {required String systemPrompt,
      required String instruction,
      required LlmTask task,
      required void Function(String chunk) onChunk,
      GenerationTaskHandle? taskHandle}) async {
    calls++;
    final wire = payload;
    // Split protocol/escaped Unicode text across chunks, without final newline.
    for (var index = 0; index < wire.length; index += 7) {
      onChunk(wire.substring(index, (index + 7).clamp(0, wire.length)));
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(invocation.memberName.toString());
}
