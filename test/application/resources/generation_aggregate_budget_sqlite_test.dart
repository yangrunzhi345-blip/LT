import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/models/llm_task.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/application/resources/part_generation_coordinator.dart';
import '../../helpers/r01_streaming_fixture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/blueprint_budget_normalizer.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_service.dart';
import 'package:lt_dialogue/application/resources/resource_capacity_repository.dart';
import 'package:lt_dialogue/application/resources/part_generation_validator.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_protocol.dart';
import 'package:lt_dialogue/domain/resources/resource_revision.dart';
import '../../helpers/phase10_fixture.dart';

void main() {
  final fixture = Phase10Fixture();
  setUp(() => fixture.setUp(prefix: 'lt_budget_'));
  tearDown(fixture.tearDown);

  Future<
      ({
        ResourceId id,
        ResourceBlueprint blueprint,
        PartGenerationTaskRepositoryImpl tasks
      })> create(int target) async {
    final pipeline = ResourceCreationPipeline(
        getDb: () async => fixture.db,
        treeRepository: fixture.treeRepository,
        hasAiCredentials: () => true);
    final session = await pipeline.create(ResourceCreationRequest(
        resourceType: ResourceType.character,
        method: CreationMethod.aiReference,
        name: '预算角色',
        referenceSource: ReferenceSource.text('测试参考'),
        targetCharacters: target,
        idempotencyKey: 'budget_$target'));
    final blueprint = BlueprintBudgetNormalizer.normalizeToGenerationTarget(
        ResourceBlueprint(
            blueprintId: 'budget_plan_$target',
            sessionId: session.sessionId!,
            resourceType: ResourceType.character,
            suggestedName: '预算角色',
            summary: '',
            targetCapacity: target,
            sections: [
              BlueprintSection(id: 's', title: '背景', parts: [
                for (var i = 0; i < target ~/ 2000; i++)
                  BlueprintPart(
                      id: 'p$i',
                      sectionId: 's',
                      title: '背景$i',
                      generationGoal: '角色背景',
                      estimatedLength: 2000),
              ])
            ]),
        targetCharacters: target);
    final repo = ResourceBlueprintRepositoryImpl(
        getDb: () async => fixture.db, treeRepository: fixture.treeRepository);
    await repo.saveBlueprint(blueprint);
    final result =
        await repo.confirmBlueprint(blueprintId: blueprint.blueprintId);
    final tasks = PartGenerationTaskRepositoryImpl(
        getDb: () async => fixture.db,
        revisionBoundary: RevisionCaptureEngine(
            revisionRepository: fixture.revisionRepository,
            treeBoundary: fixture.treeRepository));
    return (id: result.resourceId, blueprint: blueprint, tasks: tasks);
  }

  PartGenerationCoordinator coordinator(
          PartGenerationTaskRepositoryImpl tasks, PartRawCompleter completer,
          {int concurrency = 1}) =>
      PartGenerationCoordinator(
          taskRepository: tasks,
          blueprintRepository: ResourceBlueprintRepositoryImpl(
              getDb: () async => fixture.db,
              treeRepository: fixture.treeRepository),
          pipeline: ResourceCreationPipeline(
              getDb: () async => fixture.db,
              treeRepository: fixture.treeRepository,
              hasAiCredentials: () => true),
          completer: completer,
          maxConcurrency: concurrency);

  for (final target in [8000, 12000, 16000, 20000]) {
    test(
        'generation target $target: actual commits stay within budget and immutable assembly readies',
        () async {
      final stack = await create(target);
      final tasks = await stack.tasks.findReadyTasks(stack.id.value);
      expect(stack.blueprint.totalEstimatedLength, target);
      expect(
          await coordinator(stack.tasks, r01Completer('文' * 2000))
              .generateAllParts(blueprintId: stack.blueprint.blueprintId),
          isTrue);
      final actual =
          await ResourceCapacityRepositoryImpl(getDb: () async => fixture.db)
              .measureResource(stack.id);
      final head = (await fixture.revisionRepository
          .readHead(stack.id, ResourceRevisionKind.latestHead))!;
      final state = await fixture.revisionRepository.readState(head.revisionId);
      expect(actual.activeCharacters, target);
      expect(
          state.nodes.values
              .where((node) => node.kind == RevisionNodeKind.part)
              .fold<int>(0, (sum, node) => sum + node.content.length),
          target);
      expect((await fixture.coordinator.prepare(stack.id)).record.state,
          ReadinessState.ready);
      final sessions = await fixture.db
          .query('resource_creation_sessions', columns: ['target_characters']);
      expect(sessions.single['target_characters'], target);
      debugPrint(
          'SQLITE_BUDGET sessionTarget=$target blueprintTarget=${stack.blueprint.targetCapacity} '
          'planned=${stack.blueprint.totalEstimatedLength} parts=${tasks.length} actual=${actual.activeCharacters} revision=$target ready=true');
    });
  }

  for (final length in [1199, 1200, 1201, 1260, 1300, 1320]) {
    for (final hasRemaining in [true, false]) {
      test('production Part target 1200, output $length, spare=$hasRemaining',
          () async {
        final stack = await create(8000);
        final tasks = await stack.tasks.findReadyTasks(stack.id.value);
        final task = tasks.last;
        await fixture.db.update(
            'resource_generation_tasks', {'estimated_length': 1200},
            where: 'task_id = ?', whereArgs: [task.taskId]);
        // With no spare, 6800 saved units leave exactly 1200 for this Part.
        if (!hasRemaining) {
          for (var i = 0; i < 3; i++) {
            await fixture.db.update(
                'resource_parts', {'content': '原' * (i == 2 ? 800 : 3000)},
                where: 'id = ?', whereArgs: [tasks[i].partId]);
          }
        }
        final before = await stack.tasks
            .getPartsContent(tasks.take(3).map((t) => t.partId).toList());
        var calls = 0;
        final generator = coordinator(
            stack.tasks, r01Completer('文' * length, onCall: () => calls++));
        if (hasRemaining || length <= 1200) {
          expect(
              await generator.retrySinglePart(
                  blueprintId: stack.blueprint.blueprintId,
                  partId: task.partId),
              isTrue);
          expect(
              (await stack.tasks.getPartsContent([task.partId]))[task.partId]!
                  .content,
              '文' * length);
        } else {
          await expectLater(
              generator.retrySinglePart(
                  blueprintId: stack.blueprint.blueprintId,
                  partId: task.partId),
              throwsA(isA<PartGenerationValidationException>()));
          expect((await stack.tasks.findTask(task.taskId))!.status, 'failed');
          expect(
              (await stack.tasks.getPartsContent([task.partId]))[task.partId]!
                  .content,
              isEmpty);
        }
        expect(calls, 1);
        final after = await stack.tasks.getPartsContent(before.keys.toList());
        for (final id in before.keys) {
          expect(after[id]!.content, before[id]!.content);
        }
      });
    }
  }

  test('failed Part retries independently, saves once and reloads from disk',
      () async {
    final stack = await create(8000);
    var fail = true;
    final calls = <String, int>{};
    final instructions = <String>[];
    final generator = coordinator(stack.tasks, ({
      required String systemPrompt,
      required String instruction,
      required LlmTask task,
      GenerationTaskHandle? taskHandle,
    }) async {
      final id =
          RegExp(r'"part_id": "(.*?)"').firstMatch(systemPrompt)!.group(1)!;
      calls[id] = (calls[id] ?? 0) + 1;
      instructions.add(instruction);
      if (fail && id.endsWith('_p1')) return '{malformed-json';
      return r01Completion(systemPrompt, '文' * 2000);
    });
    expect(
        await generator.generateAllParts(
            blueprintId: stack.blueprint.blueprintId, maxRetriesPerPart: 1),
        isFalse);
    final tasks = await stack.tasks.findTasksForResource(stack.id.value);
    final failed = tasks.singleWhere((t) => t.status == 'failed');
    expect(calls[failed.partId], 2);
    final before = await fixture.db.query('resource_parts', orderBy: 'id');
    expect(tasks.where((t) => t.status == 'completed'), hasLength(3));
    fail = false;
    expect(
        await generator.retrySinglePart(
            blueprintId: stack.blueprint.blueprintId, partId: failed.partId),
        isTrue);
    expect(instructions.last, contains('整份资源实际剩余预算：2000'));
    expect(instructions.last, contains('正文接受上限：2000'));
    final after = await fixture.db.query('resource_parts', orderBy: 'id');
    for (var i = 0; i < before.length; i++) {
      if (before[i]['id'] != failed.partId) {
        expect(after[i], before[i],
            reason: 'successful siblings remain unchanged');
        expect(calls[before[i]['id']], 1);
      }
    }
    await expectLater(
        generator.retrySinglePart(
            blueprintId: stack.blueprint.blueprintId, partId: failed.partId),
        throwsStateError);
    expect(calls[failed.partId], 3);
    await DatabaseService.resetDatabase();
    fixture.db = await DatabaseService.database;
    final tree = (await fixture.treeRepository.readTree(stack.id))!;
    expect(tree.parts.fold<int>(0, (sum, p) => sum + p.content.length), 8000);
    expect((await fixture.coordinator.prepare(stack.id)).record.state,
        ReadinessState.ready);
  });

  test('decoded multilingual JSON body counts actual UTF-16, not wire escapes',
      () async {
    final stack = await create(8000);
    final task = (await stack.tasks.findReadyTasks(stack.id.value)).first;
    final body = jsonEncode({
      '身份': '游侠😀',
      '关系': 'friend\n友人',
      'Markdown': '**한국어 日本語 English**',
      'literal': r'\u4e2d'
    });
    final generator = coordinator(stack.tasks, r01Completer(body));
    expect(
        await generator.retrySinglePart(
            blueprintId: stack.blueprint.blueprintId, partId: task.partId),
        isTrue);
    final saved =
        (await stack.tasks.getPartsContent([task.partId]))[task.partId]!
            .content;
    expect(jsonDecode(saved), jsonDecode(body));
    expect(saved, body);
    expect(
        await stack.tasks.remainingBudget(
            resourceId: stack.id.value,
            blueprintId: task.blueprintId,
            partId: 'not-a-replacement'),
        8000 - body.length);
  });

  test('aggregate exhausted before request terminates finitely, preserves text',
      () async {
    final stack = await create(8000);
    final tasks = await stack.tasks.findReadyTasks(stack.id.value);
    for (var i = 0; i < 3; i++) {
      await fixture.db.update(
          'resource_parts', {'content': '原' * (i == 2 ? 2000 : 3000)},
          where: 'id = ?', whereArgs: [tasks[i].partId]);
      await fixture.db.update(
          'resource_generation_tasks', {'status': 'completed'},
          where: 'task_id = ?', whereArgs: [tasks[i].taskId]);
    }
    var calls = 0;
    final generator =
        coordinator(stack.tasks, r01Completer('文', onCall: () => calls++));
    expect(
        await generator.generateAllParts(
            blueprintId: stack.blueprint.blueprintId, maxRetriesPerPart: 1),
        isFalse);
    expect(calls, 0);
    expect((await stack.tasks.findTask(tasks.last.taskId))!.status, 'failed');
    final attempts = await fixture.db.query('resource_generation_attempts',
        where: 'task_id = ?', whereArgs: [tasks.last.taskId]);
    expect(attempts, hasLength(2));
    expect(attempts.every((a) => a['status'] == 'failed'), isTrue);
    expect(
        (await ResourceCapacityRepositoryImpl(getDb: () async => fixture.db)
                .measureResource(stack.id))
            .activeCharacters,
        8000);
  });

  test('concurrent overshoot cannot spend shared remaining budget twice',
      () async {
    final stack = await create(8000);
    final generator =
        coordinator(stack.tasks, r01Completer('文' * 2100), concurrency: 4);
    expect(
        await generator.generateAllParts(
            blueprintId: stack.blueprint.blueprintId, maxRetriesPerPart: 1),
        isFalse);
    final tasks = await stack.tasks.findTasksForResource(stack.id.value);
    expect(tasks.where((t) => t.status == 'completed'), hasLength(3));
    expect(tasks.where((t) => t.status == 'failed'), hasLength(1));
    final actual =
        await ResourceCapacityRepositoryImpl(getDb: () async => fixture.db)
            .measureResource(stack.id);
    expect(actual.activeCharacters, 6300);
    expect(
        tasks
            .every((t) => t.status != 'generating' && t.status != 'validating'),
        isTrue);
  });

  test(
      'aggregate guard rejects concurrent budget overspend and preserves prior content',
      () async {
    final stack = await create(8000);
    final tasks = await stack.tasks.findReadyTasks(stack.id.value);
    // Three historical / edited Parts already occupy 7,500 characters.
    for (final task in tasks.take(3)) {
      await fixture.db.update('resource_parts', {'content': '文' * 2500},
          where: 'id = ?', whereArgs: [task.partId]);
    }
    final task = tasks.last;
    expect(
        await stack.tasks.remainingBudget(
            resourceId: stack.id.value,
            blueprintId: task.blueprintId,
            partId: task.partId),
        500);
    final attempt =
        await stack.tasks.startAttempt(taskId: task.taskId, generationId: 'g');
    final response = PartGenerationResponse(
        protocolVersion: 1,
        generationId: 'g',
        resourceId: stack.id,
        sectionId: SectionId(task.sectionId),
        partId: PartId(task.partId),
        attemptId: attempt.attemptId,
        content: '文' * 501);
    await expectLater(
        stack.tasks.commitPartContent(
            response: response,
            taskId: task.taskId,
            attemptId: attempt.attemptId,
            expectedSourceToken: attempt.sourceToken),
        throwsA(isA<PartGenerationValidationException>()));
    final contents = await stack.tasks
        .getPartsContent(tasks.map((task) => task.partId).toList());
    expect(contents[task.partId]!.content, isEmpty);
    expect(contents[tasks.first.partId]!.content.length, 2500);
    expect(
        await fixture.revisionRepository
            .readHead(stack.id, ResourceRevisionKind.latestHead),
        isNull);
  });
}
