import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/blueprint_planner.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_limits.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Regression tests for the worldview planning fold.
///
/// The model systematically over-generates. Worldview blueprints are therefore
/// *planned* to `floor(userTarget * 0.8)` so the delivered body still lands
/// inside the elastic ceiling. The fold changes only the plan: the persisted
/// capacity, the elastic ceiling and the capacity checks keep using the user's
/// real target.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late ResourceTreeRepositoryImpl treeRepo;
  late ResourceCreationPipeline pipeline;
  late ResourceBlueprintRepositoryImpl blueprintRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_planning_fold_');
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
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<ResourceCreationSession> setupSession({
    required ResourceType type,
    required int targetCharacters,
  }) async {
    final res = await pipeline.create(ResourceCreationRequest(
      resourceType: type,
      method: CreationMethod.aiReference,
      name: '折叠目标资源',
      idempotencyKey: 'idemp_${DateTime.now().microsecondsSinceEpoch}',
      referenceSource: ReferenceSource.text('折叠目标参考'),
      targetCharacters: targetCharacters,
    ));
    return (await pipeline.findSession(res.sessionId!))!;
  }

  /// A valid multi-Part plan whose Parts sum to `lengths.length * 3000`.
  String buildJson(List<int> lengths) {
    final parts = <String>[];
    for (var i = 0; i < lengths.length; i++) {
      final deps = i == 0 ? '[]' : '["part_$i"]';
      parts.add('{"id":"part_${i + 1}","sectionId":"sec_1","title":"节${i + 1}",'
          '"generationGoal":"本节生成目标${i + 1}","estimatedLength":${lengths[i]},'
          '"dependencies":$deps,"sortOrder":$i}');
    }
    return '```json\n{"suggestedName":"折叠目标资源","summary":"折叠测试",'
        '"sections":[{"id":"sec_1","title":"第一章","summary":"","sortOrder":0,'
        '"parts":[${parts.join(',')}]}]}\n```';
  }

  group('planningTargetFor — pure fold function', () {
    test('A: worldview 50000 folds to 40000', () {
      expect(BlueprintPlanner.planningTargetFor(ResourceType.worldview, 50000),
          40000);
    });

    test('B: worldview 10000 folds to 8000', () {
      expect(BlueprintPlanner.planningTargetFor(ResourceType.worldview, 10000),
          8000);
    });

    test('C: character and NPC targets are not folded', () {
      expect(BlueprintPlanner.planningTargetFor(ResourceType.character, 10000),
          10000);
      expect(
          BlueprintPlanner.planningTargetFor(ResourceType.npc, 10000), 10000);
    });

    test('fold is a floor and is applied exactly once', () {
      // floor(50000 * 0.8) == 40000; a double application would give 32000.
      expect(BlueprintPlanner.planningTargetFor(ResourceType.worldview, 50000),
          isNot(32000));
      expect(BlueprintPlanner.planningTargetFor(ResourceType.worldview, 12345),
          9876); // floor(9876.0)
    });
  });

  group('worldview fold — planning path', () {
    test('A: worldview 50000 plans to 40000 while keeping the 50000 target',
        () async {
      final session = await setupSession(
        type: ResourceType.worldview,
        targetCharacters: 50000,
      );
      var capturedSystemPrompt = '';
      // 14 * 3000 = 42000 > folded 40000, so the normalizer must fold it down.
      final planner = BlueprintPlanner(
        pipeline: pipeline,
        blueprintRepository: blueprintRepo,
        completer: (
            {required systemPrompt,
            required instruction,
            required task,
            taskHandle}) async {
          capturedSystemPrompt = systemPrompt;
          return buildJson(List<int>.filled(14, 3000));
        },
      );

      final bp = await planner.plan(sessionId: session.sessionId);

      // The planning scale handed to the model is the folded target.
      expect(capturedSystemPrompt, contains('约 40000 字'));
      expect(capturedSystemPrompt, contains('不能超过 40000 字'));
      // The user's real target is what the blueprint persists.
      expect(bp.targetCapacity, 50000);
      // The plan itself is folded to the planning target.
      expect(bp.totalEstimatedLength, lessThanOrEqualTo(40000));
      expect(bp.totalEstimatedLength, 40000);
    });

    test('B: worldview 10000 plans to 8000 while keeping the 10000 target',
        () async {
      final session = await setupSession(
        type: ResourceType.worldview,
        targetCharacters: 10000,
      );
      var capturedSystemPrompt = '';
      final planner = BlueprintPlanner(
        pipeline: pipeline,
        blueprintRepository: blueprintRepo,
        completer: (
            {required systemPrompt,
            required instruction,
            required task,
            taskHandle}) async {
          capturedSystemPrompt = systemPrompt;
          return buildJson([3000, 3000, 3000]); // 9000 > 8000
        },
      );

      final bp = await planner.plan(sessionId: session.sessionId);

      expect(capturedSystemPrompt, contains('约 8000 字'));
      expect(bp.targetCapacity, 10000);
      expect(bp.totalEstimatedLength, 8000);
    });

    test('C: character plans at the full target (no fold)', () async {
      final session = await setupSession(
        type: ResourceType.character,
        targetCharacters: 10000,
      );
      var capturedSystemPrompt = '';
      final planner = BlueprintPlanner(
        pipeline: pipeline,
        blueprintRepository: blueprintRepo,
        completer: (
            {required systemPrompt,
            required instruction,
            required task,
            taskHandle}) async {
          capturedSystemPrompt = systemPrompt;
          return buildJson([2000, 2000]);
        },
      );

      final bp = await planner.plan(sessionId: session.sessionId);

      expect(capturedSystemPrompt, contains('约 10000 字'));
      expect(capturedSystemPrompt, contains('不能超过 10000 字'));
      expect(bp.targetCapacity, 10000);
      // No 0.8 reduction: the model plan of 4000 is left untouched.
      expect(bp.totalEstimatedLength, 4000);
    });
  });

  group('D: generation capacity still uses the original target and elasticity',
      () {
    test('the 20% hard ceiling of a 50000 target is 60000', () {
      expect(
        GenerationBudgetPolicy.cumulativeCeiling(
          target: 50000,
          absolute: ResourceLimits.worldviewAbsoluteCharacters,
          elasticPercent: 20,
        ),
        60000,
      );
    });

    test(
        'a folded worldview plan persists the real 50000 target, so its '
        'ceiling is derived from 50000 not 40000', () async {
      final session = await setupSession(
        type: ResourceType.worldview,
        targetCharacters: 50000,
      );
      final planner = BlueprintPlanner(
        pipeline: pipeline,
        blueprintRepository: blueprintRepo,
        completer: (
            {required systemPrompt,
            required instruction,
            required task,
            taskHandle}) async {
          return buildJson(List<int>.filled(14, 3000));
        },
      );

      final planned = await planner.plan(sessionId: session.sessionId);
      final reopened = await blueprintRepo.findBlueprint(planned.blueprintId);

      // Persisted capacity is the user's target, never the folded plan.
      expect(reopened!.targetCapacity, 50000);
      expect(reopened.totalEstimatedLength, 40000);

      final ceiling = GenerationBudgetPolicy.cumulativeCeiling(
        target: reopened.targetCapacity!,
        absolute: ResourceLimits.worldviewAbsoluteCharacters,
        elasticPercent: GenerationBudgetPolicy.defaultElasticPercent,
      );
      expect(ceiling, 60000);
      // The ceiling is not derived from the folded plan (40000 * 1.2 = 48000).
      expect(ceiling, isNot(48000));
      // The folded plan leaves room for the elastic band.
      expect(reopened.totalEstimatedLength, lessThan(ceiling));
    });
  });
}
