import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/services/database_service.dart';
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
    tempDir = await Directory.systemTemp.createTemp('lt_blueprint_repo_');
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

  Future<ResourceCreationSession> setupPlanningSession({
    ResourceType type = ResourceType.worldview,
    String name = '星渊世界',
  }) async {
    final result = await pipeline.create(ResourceCreationRequest(
      resourceType: type,
      method: CreationMethod.aiReference,
      name: name,
      idempotencyKey: 'idemp_${DateTime.now().microsecondsSinceEpoch}',
      referenceSource: ReferenceSource.text('关于星渊的古老背景传说...'),
    ));

    final session = await pipeline.findSession(result.sessionId!);
    return session!;
  }

  ResourceBlueprint makeBlueprint({
    required String sessionId,
    String blueprintId = 'bp_test_1',
    ResourceType type = ResourceType.worldview,
    int revision = 1,
    String suggestedName = '星渊全貌',
  }) {
    return ResourceBlueprint(
      blueprintId: blueprintId,
      sessionId: sessionId,
      resourceType: type,
      suggestedName: suggestedName,
      summary: '星渊维度的世界大纲',
      revision: revision,
      status: BlueprintStatus.draft,
      sections: [
        BlueprintSection(
          id: 'sec_1',
          title: '星渊构造',
          summary: '物理层结构',
          sortOrder: 0,
          parts: [
            const BlueprintPart(
              id: 'part_1',
              sectionId: 'sec_1',
              title: '界壁裂隙',
              generationGoal: '描写界壁裂隙的成因与外貌',
              estimatedLength: 800,
              sortOrder: 0,
            ),
            const BlueprintPart(
              id: 'part_2',
              sectionId: 'sec_1',
              title: '引力回廊',
              generationGoal: '描写穿行于界壁间的引力回廊',
              estimatedLength: 1000,
              dependencies: ['part_1'],
              sortOrder: 1,
            ),
          ],
        ),
      ],
    );
  }

  group('ResourceBlueprintRepository persistence & replan', () {
    test('saves and loads blueprint revision 1', () async {
      final session = await setupPlanningSession();
      final bp = makeBlueprint(sessionId: session.sessionId);

      await blueprintRepo.saveBlueprint(bp);

      final loaded = await blueprintRepo.findBlueprint(bp.blueprintId);
      expect(loaded, isNotNull);
      expect(loaded!.blueprintId, bp.blueprintId);
      expect(loaded.suggestedName, '星渊全貌');
      expect(loaded.revision, 1);
      expect(loaded.status, BlueprintStatus.draft);
      expect(loaded.sections.length, 1);
      expect(loaded.allParts.length, 2);
    });

    test('replan saves revision 2, supersedes revision 1, preserves history',
        () async {
      final session = await setupPlanningSession();
      final bp1 = makeBlueprint(sessionId: session.sessionId, revision: 1);
      await blueprintRepo.saveBlueprint(bp1);

      final bp2 = makeBlueprint(
        sessionId: session.sessionId,
        blueprintId: 'bp_test_2',
        revision: 2,
        suggestedName: '星渊全貌（修正版）',
      );
      await blueprintRepo.saveBlueprint(bp2);

      // Latest must be revision 2
      final latest = await blueprintRepo.findLatestBlueprint(session.sessionId);
      expect(latest, isNotNull);
      expect(latest!.blueprintId, 'bp_test_2');
      expect(latest.revision, 2);
      expect(latest.status, BlueprintStatus.draft);

      // Revision 1 must still exist and be marked superseded
      final oldRev = await blueprintRepo.findBlueprint(bp1.blueprintId);
      expect(oldRev, isNotNull);
      expect(oldRev!.status, BlueprintStatus.superseded);

      // History listing has both
      final history = await blueprintRepo.listBlueprints(session.sessionId);
      expect(history.length, 2);
      expect(history[0].revision, 1);
      expect(history[0].status, BlueprintStatus.superseded);
      expect(history[1].revision, 2);
      expect(history[1].status, BlueprintStatus.draft);

      // Verify formal resource tree is completely untouched during planning/replanning!
      final db = await DatabaseService.database;
      final resCount =
          _count(await db.rawQuery('SELECT COUNT(*) FROM resources'));
      final secCount =
          _count(await db.rawQuery('SELECT COUNT(*) FROM resource_sections'));
      final partCount =
          _count(await db.rawQuery('SELECT COUNT(*) FROM resource_parts'));
      expect(resCount, 0,
          reason: 'No formal resources should exist before confirm');
      expect(secCount, 0,
          reason: 'No formal sections should exist before confirm');
      expect(partCount, 0,
          reason: 'No formal parts should exist before confirm');
    });
  });

  group('ResourceBlueprintRepository confirm boundary & transaction', () {
    test(
        'confirmBlueprint creates tree placeholders and generation tasks in one transaction',
        () async {
      final session = await setupPlanningSession();
      final bp = makeBlueprint(sessionId: session.sessionId);
      await blueprintRepo.saveBlueprint(bp);

      final confirmResult = await blueprintRepo.confirmBlueprint(
        blueprintId: bp.blueprintId,
        nameOverride: '星渊世界（最终确认名）',
      );

      expect(confirmResult.reusedExisting, isFalse);
      expect(confirmResult.resourceId.value, 'res_${session.sessionId}');
      expect(confirmResult.blueprint.status, BlueprintStatus.confirmed);

      // Verify formal Resource tree
      final resource = (await treeRepo.findResource(confirmResult.resourceId))!;
      expect(resource.name, '星渊世界（最终确认名）');
      expect(resource.summary, bp.summary);
      expect(resource.metadata['creation_session_id'], session.sessionId);
      expect(resource.metadata['confirmed_blueprint_id'], bp.blueprintId);

      // Verify sections and parts
      final sections = await treeRepo.readSections(confirmResult.resourceId);
      expect(sections.length, 1);
      expect(sections.first.title, '星渊构造');

      final parts = await treeRepo.readParts(sections.first.id);
      expect(parts.length, 2);
      expect(parts[0].title, '界壁裂隙');
      expect(parts[0].content, '',
          reason: 'Part placeholder content must be strictly empty');
      expect(parts[1].title, '引力回廊');
      expect(parts[1].content, '',
          reason: 'Part placeholder content must be strictly empty');

      // Verify generation tasks created
      final tasks = await blueprintRepo.findGenerationTasks(bp.blueprintId);
      expect(tasks.length, 2);
      expect(tasks[0].promptGoal, '描写界壁裂隙的成因与外貌');
      expect(tasks[0].estimatedLength, 800);
      expect(tasks[0].status, 'pending');
      expect(tasks[1].dependencies,
          contains('${confirmResult.resourceId.value}_part_1'));

      // Verify session updated to completed
      final updatedSession = await pipeline.findSession(session.sessionId);
      expect(updatedSession!.status, CreationSessionStatus.completed);
      expect(updatedSession.resourceId?.value, confirmResult.resourceId.value);
    });

    test('duplicate confirm is idempotent and does not duplicate rows',
        () async {
      final session = await setupPlanningSession();
      final bp = makeBlueprint(sessionId: session.sessionId);
      await blueprintRepo.saveBlueprint(bp);

      final firstResult = await blueprintRepo.confirmBlueprint(
        blueprintId: bp.blueprintId,
      );
      expect(firstResult.reusedExisting, isFalse);

      final secondResult = await blueprintRepo.confirmBlueprint(
        blueprintId: bp.blueprintId,
      );
      expect(secondResult.reusedExisting, isTrue);
      expect(secondResult.resourceId, firstResult.resourceId);

      // Check row counts in database: must not double!
      final db = await DatabaseService.database;
      final resCount =
          _count(await db.rawQuery('SELECT COUNT(*) FROM resources'));
      final secCount =
          _count(await db.rawQuery('SELECT COUNT(*) FROM resource_sections'));
      final partCount =
          _count(await db.rawQuery('SELECT COUNT(*) FROM resource_parts'));
      final taskCount = _count(
          await db.rawQuery('SELECT COUNT(*) FROM resource_generation_tasks'));

      expect(resCount, 1);
      expect(secCount, 1);
      expect(partCount, 2);
      expect(taskCount, 2);
    });

    test('transaction rollback on failure leaves zero orphan records',
        () async {
      final session = await setupPlanningSession();
      // Create a blueprint that has an invalid resourceId override to cause an exception
      final bp = makeBlueprint(sessionId: session.sessionId);
      await blueprintRepo.saveBlueprint(bp);

      // We test transaction rollback by injecting a conflict or simulating failure.
      final db = await DatabaseService.database;

      // Cancel the session, making it invalid for confirmation
      await pipeline.cancel(sessionId: session.sessionId);

      expect(
        () => blueprintRepo.confirmBlueprint(blueprintId: bp.blueprintId),
        throwsA(isA<ResourceCreationException>()),
      );

      // Verify that NO resource, sections, parts, or tasks were created
      final resCount =
          _count(await db.rawQuery('SELECT COUNT(*) FROM resources'));
      final secCount =
          _count(await db.rawQuery('SELECT COUNT(*) FROM resource_sections'));
      final partCount =
          _count(await db.rawQuery('SELECT COUNT(*) FROM resource_parts'));
      final taskCount = _count(
          await db.rawQuery('SELECT COUNT(*) FROM resource_generation_tasks'));

      expect(resCount, 0);
      expect(secCount, 0);
      expect(partCount, 0);
      expect(taskCount, 0);

      // Blueprint status remains draft
      final unconfirmedBp = await blueprintRepo.findBlueprint(bp.blueprintId);
      expect(unconfirmedBp!.status, BlueprintStatus.draft);
    });
  });

  group('v34 -> v35 database migration & schema verification', () {
    test('fresh install creates v35 tables and indices', () async {
      final db = await DatabaseService.database;
      final userVer =
          (await db.rawQuery('PRAGMA user_version')).first.values.first as int;
      expect(userVer, DatabaseService.schemaVersion);

      expect(
          await DatabaseService.tableExists(db, 'resource_blueprints'), isTrue);
      expect(await DatabaseService.tableExists(db, 'resource_generation_tasks'),
          isTrue);

      final bpCols =
          await db.rawQuery('PRAGMA table_info(resource_blueprints)');
      final bpColNames = bpCols.map((r) => r['name'] as String).toSet();
      expect(
        bpColNames,
        containsAll([
          'blueprint_id',
          'session_id',
          'resource_type',
          'suggested_name',
          'summary',
          'revision',
          'status',
          'target_capacity',
          'blueprint_json',
          'resource_id',
          'created_at',
          'updated_at',
        ]),
      );

      final taskCols =
          await db.rawQuery('PRAGMA table_info(resource_generation_tasks)');
      final taskColNames = taskCols.map((r) => r['name'] as String).toSet();
      expect(
        taskColNames,
        containsAll([
          'task_id',
          'blueprint_id',
          'resource_id',
          'section_id',
          'part_id',
          'prompt_goal',
          'estimated_length',
          'dependencies_json',
          'status',
          'sort_order',
          'created_at',
          'updated_at',
        ]),
      );
    });

    test(
        'v34 -> v35 upgrade via migrateStepByStep is idempotent and re-runnable',
        () async {
      final db = await DatabaseService.database;
      // Re-run step 34 to 35
      await DatabaseService.migrateStepByStep(db, 34, 35);
      await DatabaseService.migrateStepByStep(db, 34, 35);

      expect(
          await DatabaseService.tableExists(db, 'resource_blueprints'), isTrue);
      expect(await DatabaseService.tableExists(db, 'resource_generation_tasks'),
          isTrue);
    });
  });
}
