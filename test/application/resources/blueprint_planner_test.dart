import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/blueprint_parser.dart';
import 'package:lt_dialogue/application/resources/blueprint_planner.dart';
import 'package:lt_dialogue/application/resources/blueprint_validator.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_limits.dart';
import 'package:lt_dialogue/models/llm_task.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

int _count(List<Map<String, Object?>> rows) =>
    (rows.first.values.first as num).toInt();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late ResourceTreeRepositoryImpl treeRepo;
  late ResourceCreationPipeline pipeline;
  late ResourceBlueprintRepositoryImpl blueprintRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_blueprint_planner_');
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
    ResourceType type = ResourceType.worldview,
    String name = '星际方舟',
    String reference = '关于末日方舟迁徙的设定',
    int? targetCharacters,
  }) async {
    final res = await pipeline.create(ResourceCreationRequest(
      resourceType: type,
      method: CreationMethod.aiReference,
      name: name,
      idempotencyKey: 'idemp_${DateTime.now().microsecondsSinceEpoch}',
      referenceSource: ReferenceSource.text(reference),
      targetCharacters: targetCharacters,
    ));
    return (await pipeline.findSession(res.sessionId!))!;
  }

  String buildMockJson({
    String name = '星际方舟世界观',
    String summary = '末日方舟逃亡的世界大纲',
    int length1 = 1200,
    int length2 = 1500,
    List<String> deps2 = const ['part_1'],
    String sec1Id = 'sec_1',
    String sec1Title = '方舟物理结构',
    String part1Id = 'part_1',
    String part1Goal = '描写生态圈三层环形结构',
    String part2Id = 'part_2',
    String part2Goal = '描写曲率引擎核心与能量流动',
  }) {
    return '''
```json
{
  "suggestedName": "$name",
  "summary": "$summary",
  "sections": [
    {
      "id": "$sec1Id",
      "title": "$sec1Title",
      "summary": "结构介绍",
      "sortOrder": 0,
      "parts": [
        {
          "id": "$part1Id",
          "sectionId": "$sec1Id",
          "title": "生态穹顶",
          "generationGoal": "$part1Goal",
          "estimatedLength": $length1,
          "dependencies": [],
          "sortOrder": 0
        },
        {
          "id": "$part2Id",
          "sectionId": "$sec1Id",
          "title": "能源动力室",
          "generationGoal": "$part2Goal",
          "estimatedLength": $length2,
          "dependencies": ${deps2.map((d) => '"$d"').toList()},
          "sortOrder": 1
        }
      ]
    }
  ]
}
```
''';
  }

  group('BlueprintPlanner Phase 4 Specifications', () {
    test(
        '1. Worldview Blueprint planning produces dynamic sections & parts without prose',
        () async {
      final session = await setupSession(type: ResourceType.worldview);
      var capturedPrompt = '';

      final planner = BlueprintPlanner(
        pipeline: pipeline,
        blueprintRepository: blueprintRepo,
        completer: (
            {required systemPrompt,
            required instruction,
            required task,
            taskHandle}) async {
          capturedPrompt = instruction;
          expect(task, LlmTask.resourceBlueprintPlanning);
          return buildMockJson(name: '流浪星舟', sec1Title: '超大型穹顶');
        },
      );

      final bp = await planner.plan(sessionId: session.sessionId);

      expect(bp.resourceType, ResourceType.worldview);
      expect(bp.suggestedName, '流浪星舟');
      expect(bp.revision, 1);
      expect(bp.status, BlueprintStatus.draft);
      expect(bp.sections.length, 1);
      expect(bp.sections.first.title, '超大型穹顶');
      expect(bp.allParts.length, 2);
      expect(bp.allParts[0].generationGoal, '描写生态圈三层环形结构');
      expect(capturedPrompt, contains('关于末日方舟迁徙的设定'));

      // Blueprint must NOT contain body prose
      for (final part in bp.allParts) {
        expect(part.generationGoal.length, lessThan(300));
        expect(part.title.length, lessThan(50));
      }
    });

    test('custom target enters the prompt, blueprint, and budget validator',
        () async {
      final session = await setupSession(targetCharacters: 3000);
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
          return buildMockJson(length1: 1200, length2: 1500);
        },
      );

      final blueprint = await planner.plan(sessionId: session.sessionId);

      expect(capturedSystemPrompt, contains('约 3000 字'));
      expect(capturedSystemPrompt, contains('不能超过 3000 字'));
      expect(blueprint.targetCapacity, 3000);

      final secondSession = await setupSession(targetCharacters: 3000);
      final overBudgetPlanner = BlueprintPlanner(
        pipeline: pipeline,
        blueprintRepository: blueprintRepo,
        completer: (
            {required systemPrompt,
            required instruction,
            required task,
            taskHandle}) async {
          return buildMockJson(length1: 1800, length2: 1500);
        },
      );
      final normalized = await overBudgetPlanner.plan(
        sessionId: secondSession.sessionId,
      );
      expect(normalized.totalEstimatedLength, 3000);
    });

    test('2. Character Blueprint planning produces character specific outline',
        () async {
      final session = await setupSession(
        type: ResourceType.character,
        name: '夜行刺客',
        reference: '冷酷且有原则的暗杀者',
      );

      final planner = BlueprintPlanner(
        pipeline: pipeline,
        blueprintRepository: blueprintRepo,
        completer: (
            {required systemPrompt,
            required instruction,
            required task,
            taskHandle}) async {
          expect(systemPrompt, contains('核心主角/主要角色卡'));
          return buildMockJson(
            name: '夜行刺客·影锋',
            summary: '暗杀者角色大纲',
            sec1Title: '战斗与技艺',
            part1Goal: '描写影匿步伐与短匕刺杀技巧',
            part2Goal: '描写其坚守的绝不伤及无辜原则',
          );
        },
      );

      final bp = await planner.plan(sessionId: session.sessionId);
      expect(bp.resourceType, ResourceType.character);
      expect(bp.suggestedName, '夜行刺客·影锋');
      expect(bp.sections.first.title, '战斗与技艺');
    });

    test('3. NPC Blueprint planning produces NPC outline within NPC budget',
        () async {
      final session = await setupSession(
        type: ResourceType.npc,
        name: '酒馆老板老杰克',
        reference: '经营边境酒馆的情报贩子',
      );

      final planner = BlueprintPlanner(
        pipeline: pipeline,
        blueprintRepository: blueprintRepo,
        completer: (
            {required systemPrompt,
            required instruction,
            required task,
            taskHandle}) async {
          expect(systemPrompt, contains('配角/NPC卡'));
          return buildMockJson(
            name: '老杰克',
            summary: '情报贩子NPC',
            sec1Title: '人物背景',
            length1: 400,
            length2: 500,
          );
        },
      );

      final bp = await planner.plan(sessionId: session.sessionId);
      expect(bp.resourceType, ResourceType.npc);
      expect(bp.suggestedName, '老杰克');
      expect(bp.totalEstimatedLength, 900);
      expect(
          bp.totalEstimatedLength,
          lessThan(
              ResourceLimits.policyFor(ResourceType.npc).nominalCharacters));
    });

    test('4. Dynamic Sections & 5. Dynamic Parts (not fixed templates)',
        () async {
      final session = await setupSession(type: ResourceType.worldview);

      final planner = BlueprintPlanner(
        pipeline: pipeline,
        blueprintRepository: blueprintRepo,
        completer: (
            {required systemPrompt,
            required instruction,
            required task,
            taskHandle}) async {
          return '''
```json
{
  "suggestedName": "修仙门派大典",
  "summary": "仙侠门派体系大纲",
  "sections": [
    {
      "id": "sec_1",
      "title": "灵气流转与九霄天脉",
      "summary": "天地灵气根源",
      "sortOrder": 0,
      "parts": [
        {
          "id": "part_1",
          "sectionId": "sec_1",
          "title": "天脉源起",
          "generationGoal": "阐述灵气喷涌之祖脉",
          "estimatedLength": 800,
          "dependencies": [],
          "sortOrder": 0
        }
      ]
    },
    {
      "id": "sec_2",
      "title": "青云宗门规与丹道",
      "summary": "宗门教义",
      "sortOrder": 1,
      "parts": [
        {
          "id": "part_2",
          "sectionId": "sec_2",
          "title": "宗规戒律",
          "generationGoal": "说明不可叛宗害命之铁律",
          "estimatedLength": 600,
          "dependencies": ["part_1"],
          "sortOrder": 0
        }
      ]
    }
  ]
}
```
''';
        },
      );

      final bp = await planner.plan(sessionId: session.sessionId);
      expect(bp.sections.length, 2);
      expect(bp.sections[0].title, '灵气流转与九霄天脉');
      expect(bp.sections[1].title, '青云宗门规与丹道');
      expect(bp.allParts[1].dependencies, ['part_1']);
    });

    test('6. ReferenceSource enters planning with bounded context guard',
        () async {
      final largeRef = '长参考资料' * 3000; // ~15000 chars
      final session = await setupSession(reference: largeRef);
      var capturedUserInstruction = '';

      final planner = BlueprintPlanner(
        pipeline: pipeline,
        blueprintRepository: blueprintRepo,
        completer: (
            {required systemPrompt,
            required instruction,
            required task,
            taskHandle}) async {
          capturedUserInstruction = instruction;
          return buildMockJson();
        },
      );

      await planner.plan(sessionId: session.sessionId);
      expect(capturedUserInstruction, contains('已截取前 8000 字符'));
      expect(capturedUserInstruction.length, lessThan(12000));
    });

    test('8. Unauthorized ID rejected', () async {
      final session = await setupSession();

      final planner = BlueprintPlanner(
        pipeline: pipeline,
        blueprintRepository: blueprintRepo,
        completer: (
            {required systemPrompt,
            required instruction,
            required task,
            taskHandle}) async {
          return buildMockJson(sec1Id: 'sec_unauthorized_x');
        },
      );

      expect(
        () => planner.plan(sessionId: session.sessionId),
        throwsA(isA<BlueprintIdException>()),
      );
    });

    test('9. Duplicate ID rejected', () async {
      final session = await setupSession();

      final planner = BlueprintPlanner(
        pipeline: pipeline,
        blueprintRepository: blueprintRepo,
        completer: (
            {required systemPrompt,
            required instruction,
            required task,
            taskHandle}) async {
          return buildMockJson(part1Id: 'part_1', part2Id: 'part_1');
        },
      );

      expect(
        () => planner.plan(sessionId: session.sessionId),
        throwsA(isA<BlueprintIdException>()),
      );
    });

    test('10. Dependency referencing non-existent ID rejected', () async {
      final session = await setupSession();

      final planner = BlueprintPlanner(
        pipeline: pipeline,
        blueprintRepository: blueprintRepo,
        completer: (
            {required systemPrompt,
            required instruction,
            required task,
            taskHandle}) async {
          return buildMockJson(deps2: ['part_non_existent']);
        },
      );

      expect(
        () => planner.plan(sessionId: session.sessionId),
        throwsA(isA<BlueprintIdException>()),
      );
    });

    test('11. Self-cycle dependency rejected', () async {
      final session = await setupSession();

      final planner = BlueprintPlanner(
        pipeline: pipeline,
        blueprintRepository: blueprintRepo,
        completer: (
            {required systemPrompt,
            required instruction,
            required task,
            taskHandle}) async {
          return buildMockJson(part2Id: 'part_2', deps2: ['part_2']);
        },
      );

      expect(
        () => planner.plan(sessionId: session.sessionId),
        throwsA(isA<BlueprintDagCycleException>()),
      );
    });

    test('12. Multi-node cycle dependency rejected', () async {
      final session = await setupSession();

      final planner = BlueprintPlanner(
        pipeline: pipeline,
        blueprintRepository: blueprintRepo,
        completer: (
            {required systemPrompt,
            required instruction,
            required task,
            taskHandle}) async {
          return '''
```json
{
  "suggestedName": "循环大纲",
  "summary": "循环依赖测试",
  "sections": [
    {
      "id": "sec_1",
      "title": "第一章",
      "summary": "",
      "sortOrder": 0,
      "parts": [
        {
          "id": "part_1",
          "sectionId": "sec_1",
          "title": "节1",
          "generationGoal": "目标1",
          "estimatedLength": 500,
          "dependencies": ["part_2"],
          "sortOrder": 0
        },
        {
          "id": "part_2",
          "sectionId": "sec_1",
          "title": "节2",
          "generationGoal": "目标2",
          "estimatedLength": 500,
          "dependencies": ["part_1"],
          "sortOrder": 1
        }
      ]
    }
  ]
}
```
''';
        },
      );

      expect(
        () => planner.plan(sessionId: session.sessionId),
        throwsA(isA<BlueprintDagCycleException>()),
      );
    });

    test('13. Over-budget Blueprint is normalized at planning time', () async {
      final session = await setupSession(
          type: ResourceType.character); // nominal limit 5,000

      final planner = BlueprintPlanner(
        pipeline: pipeline,
        blueprintRepository: blueprintRepo,
        completer: (
            {required systemPrompt,
            required instruction,
            required task,
            taskHandle}) async {
          return buildMockJson(
            length1: 3000,
            length2: 3000, // total 6000 > 5000 nominal
          );
        },
      );

      final blueprint = await planner.plan(sessionId: session.sessionId);
      expect(blueprint.totalEstimatedLength, 5000);
    });

    test(
        '14. Replan preserves old Blueprint & does NOT pollute formal Resource Tree',
        () async {
      final session = await setupSession();
      var promptIndex = 0;

      final planner = BlueprintPlanner(
        pipeline: pipeline,
        blueprintRepository: blueprintRepo,
        completer: (
            {required systemPrompt,
            required instruction,
            required task,
            taskHandle}) async {
          promptIndex++;
          if (promptIndex == 1) {
            return buildMockJson(name: '初始版本');
          } else {
            expect(instruction, contains('请强化探索元素'));
            return buildMockJson(name: '探索强化版');
          }
        },
      );

      final bp1 = await planner.plan(sessionId: session.sessionId);
      expect(bp1.revision, 1);
      expect(bp1.suggestedName, '初始版本');

      final bp2 = await planner.replan(
        sessionId: session.sessionId,
        userFeedback: '请强化探索元素',
      );
      expect(bp2.revision, 2);
      expect(bp2.suggestedName, '探索强化版');

      // History has both
      final history = await planner.getBlueprintHistory(session.sessionId);
      expect(history.length, 2);
      expect(history[0].status, BlueprintStatus.superseded);
      expect(history[1].status, BlueprintStatus.draft);

      // Verify zero formal resource tree nodes exist
      final db = await DatabaseService.database;
      expect(_count(await db.rawQuery('SELECT COUNT(*) FROM resources')), 0);
      expect(
          _count(await db.rawQuery('SELECT COUNT(*) FROM resource_sections')),
          0);
      expect(
          _count(await db.rawQuery('SELECT COUNT(*) FROM resource_parts')), 0);
    });

    test(
        '16. Confirm boundary: no prose before confirm, placeholders & tasks created after confirm',
        () async {
      final session = await setupSession();

      final planner = BlueprintPlanner(
        pipeline: pipeline,
        blueprintRepository: blueprintRepo,
        completer: (
            {required systemPrompt,
            required instruction,
            required task,
            taskHandle}) async {
          return buildMockJson(name: '待确认世界观');
        },
      );

      final bp = await planner.plan(sessionId: session.sessionId);

      // Before confirm: no resource rows
      final db = await DatabaseService.database;
      expect(_count(await db.rawQuery('SELECT COUNT(*) FROM resources')), 0);

      // Confirm
      final confirmRes = await planner.confirm(blueprintId: bp.blueprintId);
      expect(confirmRes.resourceId.value, 'res_${session.sessionId}');
      expect(confirmRes.blueprint.status, BlueprintStatus.confirmed);

      // After confirm: placeholders created with empty content
      final parts = await treeRepo.readParts(
          (await treeRepo.readSections(confirmRes.resourceId)).first.id);
      expect(parts.length, 2);
      expect(parts[0].content, '');
      expect(parts[1].content, '');

      // Generation tasks created
      final tasks = await blueprintRepo.findGenerationTasks(bp.blueprintId);
      expect(tasks.length, 2);
      expect(tasks[0].status, 'pending');

      // 19. Duplicate confirm is idempotent
      final duplicateConfirm =
          await planner.confirm(blueprintId: bp.blueprintId);
      expect(duplicateConfirm.reusedExisting, isTrue);
      expect(_count(await db.rawQuery('SELECT COUNT(*) FROM resources')), 1);
    });

    test('20. Cancellation interrupts planning immediately', () async {
      final session = await setupSession();
      final taskHandle = GenerationTaskHandle();

      final planner = BlueprintPlanner(
        pipeline: pipeline,
        blueprintRepository: blueprintRepo,
        completer: (
            {required systemPrompt,
            required instruction,
            required task,
            taskHandle}) async {
          taskHandle?.cancel();
          await Future.delayed(const Duration(milliseconds: 50));
          return buildMockJson();
        },
      );

      expect(
        () =>
            planner.plan(sessionId: session.sessionId, taskHandle: taskHandle),
        throwsA(isA<GenerationCancelledException>()),
      );
    });

    test('21. Timeout is caught and throws TimeoutException', () async {
      final session = await setupSession();

      final planner = BlueprintPlanner(
        pipeline: pipeline,
        blueprintRepository: blueprintRepo,
        completer: (
            {required systemPrompt,
            required instruction,
            required task,
            taskHandle}) async {
          await Future.delayed(const Duration(milliseconds: 100));
          return buildMockJson();
        },
      );

      expect(
        () => planner.plan(
          sessionId: session.sessionId,
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('22. Malformed LLM response throws BlueprintParseException', () async {
      final session = await setupSession();

      final planner = BlueprintPlanner(
        pipeline: pipeline,
        blueprintRepository: blueprintRepo,
        completer: (
            {required systemPrompt,
            required instruction,
            required task,
            taskHandle}) async {
          return '这不是JSON，是一篇普通回答';
        },
      );

      expect(
        () => planner.plan(sessionId: session.sessionId),
        throwsA(isA<BlueprintParseException>()),
      );
    });

    test(
        '23. LLM returning forbidden content (smuggled prose in goal) is rejected',
        () async {
      final session = await setupSession();

      final planner = BlueprintPlanner(
        pipeline: pipeline,
        blueprintRepository: blueprintRepo,
        completer: (
            {required systemPrompt,
            required instruction,
            required task,
            taskHandle}) async {
          return buildMockJson(part1Goal: '这是一万字的小说正文细节。' * 80);
        },
      );

      expect(
        () => planner.plan(sessionId: session.sessionId),
        throwsA(isA<BlueprintContentBoundaryException>()),
      );
    });

    test(
        '24. Full Phase 3 CreationSession -> Phase 4 Blueprint -> Confirm end-to-end path',
        () async {
      // Step A: Phase 3 pipeline creates AI session
      final creationResult = await pipeline.create(ResourceCreationRequest(
        resourceType: ResourceType.worldview,
        method: CreationMethod.aiReference,
        name: '赛博新纪元',
        idempotencyKey: 'idemp_e2e_phase3_to_phase4',
        referenceSource: ReferenceSource.text('高科技、低生活与义体改造的赛博都市。'),
      ));

      expect(creationResult.status, CreationSessionStatus.planning);
      final sessionId = creationResult.sessionId!;

      // Step B: Phase 4 planner picks up the session
      final planner = BlueprintPlanner(
        pipeline: pipeline,
        blueprintRepository: blueprintRepo,
        completer: (
            {required systemPrompt,
            required instruction,
            required task,
            taskHandle}) async {
          return buildMockJson(
            name: '赛博新纪元：夜之枢纽',
            summary: '赛博庞克世界观结构规划',
            sec1Title: '都市架构与社会阶层',
            part1Goal: '描写上层轨道天梯与底层废墟的分野',
            part2Goal: '描写黑市义体诊所与神经毒品流通',
          );
        },
      );

      final bp = await planner.plan(sessionId: sessionId);
      expect(bp.suggestedName, '赛博新纪元：夜之枢纽');
      expect(bp.sections.first.title, '都市架构与社会阶层');

      // Step C: Confirm blueprint into formal unified tree
      final confirmRes = await planner.confirm(blueprintId: bp.blueprintId);
      expect(confirmRes.resourceId.value, 'res_$sessionId');

      // Verify formal tree in SQLite
      final tree = await treeRepo.findResource(confirmRes.resourceId);
      expect(tree, isNotNull);
      expect(tree!.name, '赛博新纪元：夜之枢纽');

      final sections = await treeRepo.readSections(confirmRes.resourceId);
      expect(sections.length, 1);
      expect(sections.first.title, '都市架构与社会阶层');

      final parts = await treeRepo.readParts(sections.first.id);
      expect(parts.length, 2);
      expect(parts[0].content, '', reason: 'Placeholders must be empty');
      expect(parts[1].content, '', reason: 'Placeholders must be empty');

      // Verify generation tasks in SQLite
      final tasks = await blueprintRepo.findGenerationTasks(bp.blueprintId);
      expect(tasks.length, 2);
      expect(tasks[0].promptGoal, '描写上层轨道天梯与底层废墟的分野');
      expect(tasks[1].promptGoal, '描写黑市义体诊所与神经毒品流通');

      // Verify CreationSession status is completed
      final session = await pipeline.findSession(sessionId);
      expect(session!.status, CreationSessionStatus.completed);
    });
  });
}
