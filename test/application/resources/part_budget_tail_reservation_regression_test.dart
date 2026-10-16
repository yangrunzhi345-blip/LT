import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/blueprint_budget_normalizer.dart';
import 'package:lt_dialogue/application/resources/part_generation_coordinator.dart';
import 'package:lt_dialogue/application/resources/part_generation_validator.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_capacity_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_service.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_protocol.dart';
import 'package:lt_dialogue/models/llm_task.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import '../../helpers/phase10_fixture.dart';
import '../../helpers/r01_streaming_fixture.dart';

typedef TailRun = ({
  ResourceId id,
  ResourceBlueprint blueprint,
  PartGenerationTaskRepositoryImpl tasks,
});

/// Regression for the tail-squeeze that made worldview / character / NPC Part
/// generation fail intermittently while the resource still had budget left.
///
/// Root cause (see the allocation unit tests): the run's future reserve held
/// only each later required Part's *minimum* — a ten-unit legacy floor when no
/// content contract was confirmed — so earlier Parts could consume the shared
/// ceiling right up to the transport cap. The tail Part was then dispatched
/// with a `dispatchableMaximum` *below its own planned length*, so a body
/// written to plan (or the model refusing to emit a degenerate stub) was
/// rejected, and every retry recomputed the same squeezed limit.
///
/// The whole chain is exercised on real SQLite through the real coordinator,
/// prompt builder and validator; only the model network output is replaced.
void main() {
  final fixture = Phase10Fixture();
  setUp(() => fixture.setUp(prefix: 'lt_tail_reserve_'));
  tearDown(fixture.tearDown);

  const target = 20000; // C = min(floor(20000*1.2), A) = 24000 for every type.
  const partCount = 10;
  const planPerPart = target ~/ partCount; // 2000
  const ceiling = 24000;

  Future<TailRun> createRun(ResourceType type) async {
    final pipeline = ResourceCreationPipeline(
        getDb: () async => fixture.db,
        treeRepository: fixture.treeRepository,
        hasAiCredentials: () => true);
    final session = await pipeline.create(ResourceCreationRequest(
        resourceType: type,
        method: CreationMethod.aiReference,
        name: '尾段预算资源',
        referenceSource: ReferenceSource.text('尾段预算参考'),
        targetCharacters: target,
        idempotencyKey: 'tail_${type.storageValue}'));
    final blueprint = BlueprintBudgetNormalizer.normalizeToGenerationTarget(
        ResourceBlueprint(
            blueprintId: 'tail_plan_${type.storageValue}',
            sessionId: session.sessionId!,
            resourceType: type,
            suggestedName: '尾段预算资源',
            summary: '',
            targetCapacity: target,
            sections: [
              BlueprintSection(id: 's', title: '背景', parts: [
                for (var i = 0; i < partCount; i++)
                  BlueprintPart(
                      id: 'p$i',
                      sectionId: 's',
                      title: '背景$i',
                      generationGoal: '内容$i',
                      estimatedLength: planPerPart),
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
          PartGenerationTaskRepositoryImpl tasks, PartRawCompleter completer) =>
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
          maxConcurrency: 1);

  int targetOf(String instruction) =>
      int.parse(RegExp(r'目标字数：约 (\d+) 字').firstMatch(instruction)!.group(1)!);

  int acceptedMaxOf(String instruction) =>
      int.parse(RegExp(r'正文接受上限：(\d+) 个').firstMatch(instruction)!.group(1)!);

  /// A model that writes a natural body (~40% above the plan) but never below a
  /// short floor: a real model asked for a two-character stub still writes a
  /// sentence. Under the old allocation the tail's accepted maximum dropped to
  /// a stub-sized value, so this floor pushed the body past the limit and the
  /// whole run failed — the reported intermittent fault.
  PartRawCompleter naturalModel({
    required void Function(String partId, int target, int acceptedMax) onCall,
  }) {
    final natural = (planPerPart * 1.4).round();
    final floor = math.min(300, planPerPart);
    return ({
      required String systemPrompt,
      required String instruction,
      required LlmTask task,
      GenerationTaskHandle? taskHandle,
    }) async {
      final partId =
          RegExp(r'"part_id": "(.*?)"').firstMatch(systemPrompt)!.group(1)!;
      final acceptedMax = acceptedMaxOf(instruction);
      onCall(partId, targetOf(instruction), acceptedMax);
      var length = math.min(natural, acceptedMax);
      if (length < floor) length = floor;
      return r01Completion(systemPrompt, '文' * length);
    };
  }

  for (final type in ResourceType.values) {
    test(
        '${type.storageValue}: a naturally expanding model completes the run and every Part reaches its plan',
        () async {
      final stack = await createRun(type);
      final calls = <({String partId, int target, int acceptedMax})>[];
      final generator = coordinator(
          stack.tasks,
          naturalModel(
              onCall: (partId, t, m) =>
                  calls.add((partId: partId, target: t, acceptedMax: m))));

      final ok = await generator.generateAllParts(
          blueprintId: stack.blueprint.blueprintId, maxRetriesPerPart: 1);

      // The whole run must finish: this failed before the reservation drew on
      // each later Part's planned body instead of its vacuous minimum.
      expect(ok, isTrue, reason: 'run must not die in the tail');

      final contents = await stack.tasks
          .getPartsContent(calls.map((c) => c.partId).toSet().toList());
      // No Part may be dispatched with a bound below its own planned length.
      for (final call in calls) {
        expect(call.acceptedMax, greaterThanOrEqualTo(planPerPart),
            reason: '${call.partId} was squeezed below its plan');
        expect(call.target, greaterThanOrEqualTo(planPerPart),
            reason: '${call.partId} was asked for less than its plan');
      }
      // Every committed Part reached its planned size and the cumulative total
      // never crossed the elastic ceiling.
      for (final entry in contents.entries) {
        expect(entry.value.content.length, greaterThanOrEqualTo(planPerPart),
            reason: '${entry.key} committed a sub-plan body');
      }
      final actual =
          await ResourceCapacityRepositoryImpl(getDb: () async => fixture.db)
              .measureResource(stack.id);
      expect(actual.activeCharacters, greaterThanOrEqualTo(target));
      expect(actual.activeCharacters, lessThanOrEqualTo(ceiling));

      final tasks = await stack.tasks.findTasksForResource(stack.id.value);
      expect(tasks.where((t) => t.status == 'completed'), hasLength(partCount));
      expect(tasks.where((t) => t.status == 'failed'), isEmpty);
    });
  }

  test(
      'a body written exactly to plan is never rejected while the plan fits the ceiling',
      () async {
    final stack = await createRun(ResourceType.character);
    final generator = coordinator(
        stack.tasks, r01Completer('文' * planPerPart, onCall: () {}));
    expect(
        await generator.generateAllParts(
            blueprintId: stack.blueprint.blueprintId, maxRetriesPerPart: 1),
        isTrue);
    final contents = await stack.tasks.getPartsContent(
        (await stack.tasks.findTasksForResource(stack.id.value))
            .map((t) => t.partId)
            .toList());
    for (final entry in contents.entries) {
      expect(entry.value.content.length, planPerPart);
    }
    debugPrint(
        'PLAN_EXACT total=${contents.values.fold<int>(0, (s, v) => s + v.content.length)}');
  });

  /// Fills every Part except [tail] with a `completed` body so their combined
  /// length is exactly [totalCharacters]; the tail then has exactly
  /// `C - totalCharacters` headroom and no other unfinished required Part, so
  /// its future reserve is 0.
  Future<void> prefillSiblings(
    List<ResourceGenerationTask> tasks,
    ResourceGenerationTask tail,
    int totalCharacters,
  ) async {
    final siblings = tasks.where((t) => t.taskId != tail.taskId).toList();
    expect(siblings, isNotEmpty);
    final base = totalCharacters ~/ siblings.length;
    final extra = totalCharacters - base * siblings.length;
    for (var i = 0; i < siblings.length; i++) {
      final length = i == siblings.length - 1 ? base + extra : base;
      await fixture.db.update('resource_parts', {'content': '原' * length},
          where: 'id = ?', whereArgs: [siblings[i].partId]);
      await fixture.db.update(
          'resource_generation_tasks', {'status': 'completed'},
          where: 'task_id = ?', whereArgs: [siblings[i].taskId]);
    }
  }

  /// Starts a lease on [tail] and tries to commit [bodyLength] characters;
  /// returns the thrown error, or null when the commit was accepted.
  Future<Object?> attemptCommit(
    TailRun stack,
    ResourceGenerationTask tail,
    int bodyLength,
  ) async {
    final attempt =
        await stack.tasks.startAttempt(taskId: tail.taskId, generationId: 'g');
    try {
      await stack.tasks.commitPartContent(
          response: PartGenerationResponse(
              protocolVersion: 1,
              generationId: 'g',
              resourceId: stack.id,
              sectionId: SectionId(tail.sectionId),
              partId: PartId(tail.partId),
              attemptId: attempt.attemptId,
              content: '文' * bodyLength),
          taskId: tail.taskId,
          attemptId: attempt.attemptId,
          expectedSourceToken: attempt.sourceToken);
      return null;
    } catch (error) {
      return error;
    }
  }

  Future<int> savedTotal() async {
    final parts = await fixture.db.query('resource_parts',
        columns: ['content'], where: 'deleted_at IS NULL');
    return parts.fold<int>(
        0, (sum, row) => sum + (row['content']?.toString().length ?? 0));
  }

  test(
      'a candidate one unit over the elastic ceiling is refused by the commit transaction',
      () async {
    // Construct the exact C - 1 state: savedTotal = 23999, remaining = 1,
    // futureReserve = 0 (every other Part is completed).
    final stack = await createRun(ResourceType.npc);
    final tasks = await stack.tasks.findReadyTasks(stack.id.value);
    final tail = tasks.last;
    await prefillSiblings(tasks, tail, ceiling - 1);
    expect(await savedTotal(), ceiling - 1);

    final allocation = await stack.tasks.budgetAllocation(
        resourceId: stack.id.value,
        blueprintId: stack.blueprint.blueprintId,
        partId: tail.partId);
    expect(allocation!.remaining, 1);
    expect(allocation.futureReserve, 0);
    expect(allocation.dispatchableMaximum, 1);

    final error = await attemptCommit(stack, tail, planPerPart);

    // The refusal must come from the cumulative budget guard, not from the
    // Part's own length contract or the single-Part transport cap. This plan
    // carries no content contract and the body is under K, so the only possible
    // rejection is `generation_budget`.
    expect(error, isA<PartGenerationValidationException>());
    final validation = error! as PartGenerationValidationException;
    expect(validation.field, 'generation_budget');
    expect(validation.actual, '${ceiling - 1 + planPerPart}');
    expect(validation.expected, contains('$ceiling'));

    // Nothing was written and the task did not advance past its lease.
    expect(await savedTotal(), ceiling - 1);
    expect(
        (await stack.tasks.getPartsContent([tail.partId]))[tail.partId]!
            .content,
        isEmpty);
    expect(
        (await stack.tasks.findTask(tail.taskId))!.status, isNot('completed'));
    expect(
        await fixture.revisionRepository
            .readHead(stack.id, ResourceRevisionKind.latestHead),
        isNull);
  });

  test(
      'a candidate beyond a fully spent ceiling is refused and prior text is preserved',
      () async {
    // savedTotal = C exactly → remaining = 0, futureReserve = 0.
    final stack = await createRun(ResourceType.npc);
    final tasks = await stack.tasks.findReadyTasks(stack.id.value);
    final tail = tasks.last;
    await prefillSiblings(tasks, tail, ceiling);
    expect(await savedTotal(), ceiling);

    final allocation = await stack.tasks.budgetAllocation(
        resourceId: stack.id.value,
        blueprintId: stack.blueprint.blueprintId,
        partId: tail.partId);
    expect(allocation!.remaining, 0);
    expect(allocation.futureReserve, 0);

    final before =
        await stack.tasks.getPartsContent(tasks.map((t) => t.partId).toList());

    final error = await attemptCommit(stack, tail, planPerPart);
    expect(error, isA<PartGenerationValidationException>());
    expect((error! as PartGenerationValidationException).field,
        'generation_budget');

    // Every already-saved body is untouched.
    final after =
        await stack.tasks.getPartsContent(tasks.map((t) => t.partId).toList());
    for (final id in before.keys) {
      expect(after[id]!.content, before[id]!.content);
    }
    expect(await savedTotal(), ceiling);
    expect(
        (await stack.tasks.findTask(tail.taskId))!.status, isNot('completed'));
    expect(
        await fixture.revisionRepository
            .readHead(stack.id, ResourceRevisionKind.latestHead),
        isNull);
  });
}
