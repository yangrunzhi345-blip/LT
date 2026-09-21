// Independent Phase 4 acceptance evidence.
//
// Authored by the reviewer role (read-only with respect to production code).
// These cases probe the Phase 4 contract adversarially rather than restating
// the executor's fixtures: real SQLite transactions, real failure injection
// mid-transaction, real capacity boundaries, real ID-pool enforcement and a
// probe for whether the planning stack is reachable from production code.
//
// A failure here is a Phase 4 finding, not a test debt item.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/blueprint_planner.dart';
import 'package:lt_dialogue/application/resources/blueprint_validator.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_limits.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
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
    tempDir = await Directory.systemTemp.createTemp('lt_p4_acceptance_');
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

  Future<ResourceCreationSession> newSession({
    ResourceType type = ResourceType.worldview,
    String name = '独立验收资源',
    String reference = '参考资料正文',
  }) async {
    final result = await pipeline.create(ResourceCreationRequest(
      resourceType: type,
      method: CreationMethod.aiReference,
      name: name,
      idempotencyKey: 'p4_${DateTime.now().microsecondsSinceEpoch}',
      referenceSource: ReferenceSource.text(reference),
    ));
    return (await pipeline.findSession(result.sessionId!))!;
  }

  String llmJson({
    String name = '独立验收大纲',
    String summary = '大纲摘要',
    List<List<int>> lengths = const [
      [800, 900]
    ],
    List<List<List<String>>> deps = const [
      [
        [],
        ['part_1']
      ]
    ],
    List<String> sectionIds = const ['sec_1'],
    List<String> partIds = const ['part_1', 'part_2'],
    int? targetCapacity,
  }) {
    final sections = <String>[];
    var partCursor = 0;
    for (var s = 0; s < sectionIds.length; s++) {
      final parts = <String>[];
      for (var p = 0; p < lengths[s].length; p++) {
        final pid = partIds[partCursor];
        final depList = deps[s][p].map((d) => '"$d"').toList();
        parts.add('''
        {
          "id": "$pid",
          "sectionId": "${sectionIds[s]}",
          "title": "小节 $pid",
          "generationGoal": "描述 $pid 的核心设定要点",
          "estimatedLength": ${lengths[s][p]},
          "dependencies": $depList,
          "sortOrder": $p
        }''');
        partCursor++;
      }
      sections.add('''
    {
      "id": "${sectionIds[s]}",
      "title": "章节 ${sectionIds[s]}",
      "summary": "章节概述",
      "sortOrder": $s,
      "parts": [${parts.join(',')}]
    }''');
    }
    final capacity =
        targetCapacity == null ? '' : ',\n  "targetCapacity": $targetCapacity';
    return '''```json
{
  "suggestedName": "$name",
  "summary": "$summary"$capacity,
  "sections": [${sections.join(',')}]
}
```''';
  }

  BlueprintPlanner plannerWith(String response) => BlueprintPlanner(
        pipeline: pipeline,
        blueprintRepository: blueprintRepo,
        completer: (
                {required systemPrompt,
                required instruction,
                required task,
                taskHandle}) async =>
            response,
      );

  Future<void> expectCounts({
    required int resources,
    required int sections,
    required int parts,
    int tasks = -1,
  }) async {
    final db = await DatabaseService.database;
    expect(
        _count(await db.rawQuery('SELECT COUNT(*) FROM resources')), resources,
        reason: 'resources row count');
    expect(_count(await db.rawQuery('SELECT COUNT(*) FROM resource_sections')),
        sections,
        reason: 'resource_sections row count');
    expect(
        _count(await db.rawQuery('SELECT COUNT(*) FROM resource_parts')), parts,
        reason: 'resource_parts row count');
    if (tasks >= 0) {
      expect(
          _count(await db
              .rawQuery('SELECT COUNT(*) FROM resource_generation_tasks')),
          tasks,
          reason: 'resource_generation_tasks row count');
    }
  }

  group('Independent Phase 4 — confirm transaction atomicity', () {
    test(
        'I-1 rollback occurs after the resource row is already written '
        '(section insert fails mid-transaction)', () async {
      final session = await newSession();
      final planner = plannerWith(llmJson());
      final bp = await planner.plan(sessionId: session.sessionId);

      // Occupy the exact Section id that confirm() will derive, so the tree
      // write fails AFTER the resources row has been inserted.
      final conflicting = ResourceTreeDraft(
        id: const ResourceId('res_unrelated'),
        type: ResourceType.worldview,
        name: '无关资源',
        sections: [
          ResourceTreeSectionDraft(
            id: SectionId('res_${session.sessionId}_sec_1'),
            title: '占位',
          ),
        ],
      );
      await treeRepo.createResourceTree(conflicting);

      await expectCounts(resources: 1, sections: 1, parts: 0, tasks: 0);

      expect(
        () => blueprintRepo.confirmBlueprint(blueprintId: bp.blueprintId),
        throwsA(isA<DatabaseException>()),
        reason: 'duplicate primary key must abort the whole confirm',
      );

      // Rollback must remove the resource row written before the failure.
      await expectCounts(resources: 1, sections: 1, parts: 0, tasks: 0);
      expect((await blueprintRepo.findBlueprint(bp.blueprintId))!.status,
          BlueprintStatus.draft,
          reason: 'a half-confirmed blueprint must not exist');
      expect((await pipeline.findSession(session.sessionId))!.status,
          CreationSessionStatus.planning,
          reason:
              'session must not be marked completed after a failed confirm');
    });

    test('I-2 concurrent duplicate confirm never duplicates rows', () async {
      final session = await newSession();
      final bp = await plannerWith(llmJson()).plan(
        sessionId: session.sessionId,
      );

      final results = await Future.wait([
        blueprintRepo.confirmBlueprint(blueprintId: bp.blueprintId),
        blueprintRepo.confirmBlueprint(blueprintId: bp.blueprintId),
      ]);

      expect(results.map((r) => r.resourceId.value).toSet(), hasLength(1),
          reason: 'all confirms must resolve to the same resource identity');
      await expectCounts(resources: 1, sections: 1, parts: 2, tasks: 2);
    });

    test('I-3 confirm result is readable through the unified tree read path',
        () async {
      final session = await newSession();
      final bp = await plannerWith(llmJson()).plan(
        sessionId: session.sessionId,
      );
      final confirmed = await blueprintRepo.confirmBlueprint(
        blueprintId: bp.blueprintId,
      );

      final resource = await treeRepo.findResource(confirmed.resourceId);
      expect(resource, isNotNull, reason: 'confirmed resource must be visible');
      final sections = await treeRepo.readSections(confirmed.resourceId);
      expect(sections, hasLength(1));
      final parts = await treeRepo.readParts(sections.first.id);
      expect(parts, hasLength(2));
      for (final part in parts) {
        expect(part.content, isEmpty,
            reason: 'confirmed placeholders must carry no generated prose');
      }
    });
  });

  group('Independent Phase 4 — capacity policy boundaries', () {
    test('I-4 worldview normalizes planning metadata to its generation target',
        () async {
      final session = await newSession(type: ResourceType.worldview);

      final atLimit = await plannerWith(llmJson(
        lengths: const [
          [50000]
        ],
        deps: const [
          [[]]
        ],
        partIds: const ['part_1'],
      )).plan(sessionId: session.sessionId);
      expect(atLimit.totalEstimatedLength,
          ResourceLimits.worldviewNominalCharacters);
      expect(atLimit.allParts.single.estimatedLength,
          ResourceLimits.worldviewNominalCharacters);
      expect(await blueprintRepo.findBlueprint(atLimit.blueprintId), isNotNull);

      final overTarget = await plannerWith(llmJson(
        lengths: const [
          [50001]
        ],
        deps: const [
          [[]]
        ],
        partIds: const ['part_1'],
      )).plan(sessionId: session.sessionId);
      expect(overTarget.totalEstimatedLength,
          lessThanOrEqualTo(ResourceLimits.worldviewNominalCharacters));
      expect(overTarget.allParts.single.estimatedLength,
          ResourceLimits.maxPartCharacters);
    });

    test('I-5 character/NPC normalize planning metadata above 20000', () async {
      final session = await newSession(type: ResourceType.character);
      final character = await plannerWith(llmJson(
        lengths: const [
          [20001]
        ],
        deps: const [
          [[]]
        ],
        partIds: const ['part_1'],
      )).plan(sessionId: session.sessionId);
      expect(character.totalEstimatedLength,
          lessThanOrEqualTo(ResourceLimits.characterNominalCharacters));

      final npcSession = await newSession(type: ResourceType.npc);
      final npc = await plannerWith(llmJson(
        lengths: const [
          [20001]
        ],
        deps: const [
          [[]]
        ],
        partIds: const ['part_1'],
      )).plan(sessionId: npcSession.sessionId);
      expect(npc.totalEstimatedLength,
          lessThanOrEqualTo(ResourceLimits.npcNominalCharacters));
    });

    test('I-6 the model cannot raise its own budget via targetCapacity',
        () async {
      final session = await newSession(type: ResourceType.character);
      final blueprint = await plannerWith(llmJson(
        lengths: const [
          [9000]
        ],
        deps: const [
          [[]]
        ],
        partIds: const ['part_1'],
        targetCapacity: 999999,
      )).plan(sessionId: session.sessionId);
      expect(
          blueprint.targetCapacity, ResourceLimits.characterNominalCharacters,
          reason: 'server-side generation target must win over model metadata');
      expect(blueprint.totalEstimatedLength,
          lessThanOrEqualTo(ResourceLimits.characterNominalCharacters));
    });
  });

  group('Independent Phase 4 — ID security & DAG', () {
    test('I-7 dependency pointing at another blueprint is rejected', () async {
      final first = await newSession(name: 'A');
      await plannerWith(llmJson()).plan(sessionId: first.sessionId);

      final second = await newSession(name: 'B');
      expect(
        () => plannerWith(llmJson(
          deps: const [
            [
              [],
              // belongs to blueprint A, not to this blueprint
              ['part_1_of_other_blueprint']
            ]
          ],
        )).plan(sessionId: second.sessionId),
        throwsA(isA<BlueprintIdException>()),
      );
    });

    test('I-8 every DAG cycle shape is rejected through the real planner path',
        () async {
      final selfSession = await newSession(name: 'self');
      expect(
        () => plannerWith(llmJson(
          lengths: const [
            [500]
          ],
          deps: const [
            [
              ['part_1']
            ]
          ],
          partIds: const ['part_1'],
        )).plan(sessionId: selfSession.sessionId),
        throwsA(isA<BlueprintDagCycleException>()),
        reason: 'A → A must be rejected',
      );

      final twoSession = await newSession(name: 'two');
      expect(
        () => plannerWith(llmJson(
          lengths: const [
            [400, 400]
          ],
          deps: const [
            [
              ['part_2'],
              ['part_1']
            ]
          ],
        )).plan(sessionId: twoSession.sessionId),
        throwsA(isA<BlueprintDagCycleException>()),
        reason: 'A → B → A must be rejected',
      );

      final threeSession = await newSession(name: 'three');
      expect(
        () => plannerWith(llmJson(
          lengths: const [
            [300, 300, 300]
          ],
          deps: const [
            [
              ['part_3'],
              ['part_1'],
              ['part_2']
            ]
          ],
          partIds: const ['part_1', 'part_2', 'part_3'],
        )).plan(sessionId: threeSession.sessionId),
        throwsA(isA<BlueprintDagCycleException>()),
        reason: 'A → B → C → A must be rejected',
      );
    });

    test('I-9 ID pool caps the outline size the model may invent', () async {
      final session = await newSession();
      final tooManySections = List<String>.generate(14, (i) => 'sec_${i + 1}');
      final partIds = List<String>.generate(28, (i) => 'part_${i + 1}');

      expect(
        () => plannerWith(llmJson(
          sectionIds: tooManySections,
          partIds: partIds,
          lengths: List<List<int>>.generate(14, (_) => <int>[100, 100],
              growable: false),
          deps: List<List<List<String>>>.generate(
              14, (_) => <List<String>>[<String>[], <String>[]],
              growable: false),
        )).plan(sessionId: session.sessionId),
        throwsA(isA<BlueprintIdException>()),
        reason: 'IDs outside the client-allocated pool must be rejected',
      );
    });
  });

  group('Independent Phase 4 — bounded planning context', () {
    test('I-10 huge reference source never reaches the prompt verbatim',
        () async {
      final hugeReference = '秘' * 40000;
      final session = await newSession(reference: hugeReference);

      String capturedInstruction = '';
      final planner = BlueprintPlanner(
        pipeline: pipeline,
        blueprintRepository: blueprintRepo,
        completer: (
            {required systemPrompt,
            required instruction,
            required task,
            taskHandle}) async {
          capturedInstruction = instruction;
          return llmJson();
        },
      );
      await planner.plan(sessionId: session.sessionId);

      final bodySlice =
          capturedInstruction.split('【参考资料】').last.split('请根据上述需求').first;
      final compactBody = bodySlice.replaceAll(' ', '').replaceAll('\n', '');
      expect(compactBody.length, lessThan(9000),
          reason: 'planning context must stay bounded');
      expect(capturedInstruction, isNot(contains('秘' * 9000)),
          reason: 'the full user reference text must not be sent');
      expect(capturedInstruction, contains('已截取前'),
          reason: 'truncation must be disclosed to the model');
    });
  });

  group('Independent Phase 4 — plan / replan tree isolation', () {
    test('I-11 planning never touches the formal tree; confirm is the gate',
        () async {
      final session = await newSession();
      final planner = plannerWith(llmJson());

      await planner.plan(sessionId: session.sessionId);
      await expectCounts(resources: 0, sections: 0, parts: 0, tasks: 0);

      await planner.replan(
        sessionId: session.sessionId,
        userFeedback: '请重新分配章节',
      );
      await expectCounts(resources: 0, sections: 0, parts: 0, tasks: 0);

      final history = await planner.getBlueprintHistory(session.sessionId);
      expect(history.map((b) => b.revision), [1, 2]);
      expect(history.first.status, BlueprintStatus.superseded);
      expect(history.last.status, BlueprintStatus.draft);
    });
  });

  group('Independent Phase 4 — database / migration', () {
    test('I-13 an older database upgrades to v35 and keeps existing rows',
        () async {
      final db = await DatabaseService.database;
      await treeRepo.createResourceTree(const ResourceTreeDraft(
        id: ResourceId('res_preexisting'),
        type: ResourceType.worldview,
        name: '升级前已存在的资源',
      ));

      // Simulate a pre-v35 database: drop the new tables and roll the version
      // back, then reopen through DatabaseService so onUpgrade runs for real.
      await db.execute('DROP TABLE IF EXISTS resource_blueprints');
      await db.execute('DROP TABLE IF EXISTS resource_generation_tasks');
      await db.execute('PRAGMA user_version = 34');
      await DatabaseService.resetDatabase();

      final upgraded = await DatabaseService.database;
      final version = (await upgraded.rawQuery('PRAGMA user_version'))
          .first
          .values
          .first as int;
      expect(version, DatabaseService.schemaVersion);
      expect(await DatabaseService.tableExists(upgraded, 'resource_blueprints'),
          isTrue);
      expect(
          await DatabaseService.tableExists(
              upgraded, 'resource_generation_tasks'),
          isTrue);

      // Replaying the same step must stay safe.
      await DatabaseService.migrateStepByStep(upgraded, 34, 35);
      await DatabaseService.migrateStepByStep(upgraded, 34, 35);

      expect(await treeRepo.findResource(const ResourceId('res_preexisting')),
          isNotNull,
          reason: 'upgrade must preserve existing user resources');
    });
  });

  group('Independent Phase 4 — confirm ownership boundary', () {
    test('I-14 confirm refuses to rewrite an unrelated existing resource',
        () async {
      final session = await newSession();

      // A resource that has nothing to do with this session, with real content.
      await treeRepo.createResourceTree(const ResourceTreeDraft(
        id: ResourceId('res_victim'),
        type: ResourceType.worldview,
        name: '与本次规划无关的资源',
        sections: [
          ResourceTreeSectionDraft(
            title: '别人的章节',
            parts: [
              ResourceTreePartDraft(
                title: '别人的正文',
                content: '这是用户已经写好的正文，不能被规划覆盖',
              ),
            ],
          ),
        ],
      ));

      final bp = await plannerWith(llmJson()).plan(
        sessionId: session.sessionId,
      );

      expect(
        () => blueprintRepo.confirmBlueprint(
          blueprintId: bp.blueprintId,
          explicitResourceId: const ResourceId('res_victim'),
        ),
        throwsA(isA<Exception>()),
        reason: 'confirm must not bind a blueprint to a resource that does not '
            'belong to the planning session',
      );

      // If the API is allowed to proceed, it must not have destroyed content.
      final victim =
          await treeRepo.findResource(const ResourceId('res_victim'));
      expect(victim!.name, '与本次规划无关的资源',
          reason: 'a confirm must not rename an unrelated resource');
      final victimSections =
          await treeRepo.readSections(const ResourceId('res_victim'));
      expect(victimSections, hasLength(1),
          reason: 'a confirm must not drop the sections of an unrelated '
              'resource');
      final victimParts = await treeRepo.readParts(victimSections.first.id);
      expect(victimParts.single.content, '这是用户已经写好的正文，不能被规划覆盖',
          reason: 'existing user content must survive a blueprint confirm');
    });
  });

  group('Independent Phase 4 — production reachability', () {
    test('I-12 the planning stack is reachable from production code', () async {
      // Evidence probe: if nothing outside the Phase 4 files constructs
      // BlueprintPlanner or the blueprint repository, then no user flow can
      // ever obtain a Blueprint, and confirm() cannot be reached at all.
      final consumers = <String>[];
      final libDir = Directory('lib');
      await for (final entity in libDir.list(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('blueprint_planner.dart') ||
            entity.path.endsWith('resource_blueprint_repository.dart')) {
          continue;
        }
        final source = entity.readAsStringSync();
        if (source.contains('BlueprintPlanner(') ||
            source.contains('ResourceBlueprintRepositoryImpl(')) {
          consumers.add(entity.path);
        }
      }

      expect(consumers, isNotEmpty,
          reason: 'Phase 3 pending-planning sessions must be picked up by the '
              'Phase 4 planner; today the whole planning stack is unreachable '
              'from any production call site');
    });
  });
}
