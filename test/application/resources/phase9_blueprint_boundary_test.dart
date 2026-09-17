import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/blueprint_parser.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_revision.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/phase9_recovery_fixtures.dart';

/// P9-I2: confirming a blueprint over an **existing** resource replaces the
/// whole tree (`updateResourceTreeInTransaction` deletes every Section/Part and
/// rewrites them), so that branch is a lossy write and must record a before /
/// after revision in the same transaction.
///
/// The branch is believed unreachable today with confirmed content — the session
/// has to be `planning`/`persisted` and the blueprint `draft` — so this test
/// drives it deliberately and pins the boundary in place before Phase 10 starts
/// re-planning resources.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late Phase9RecoveryFixture phase9;

  const resourceId = ResourceId('res_bp_boundary');
  const sessionId = 'sess_bp_boundary';
  const blueprintId = 'bp_boundary';
  const now = '2026-09-17T00:00:00.000';

  Future<Database> getDb() => DatabaseService.database;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_p9_blueprint_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    phase9 = Phase9RecoveryFixture(getDb: getDb);
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> seedExistingTree({String content = '确认前已有的正文'}) =>
      phase9.tree.createResourceTree(
        ResourceTreeDraft(
          id: resourceId,
          type: ResourceType.worldview,
          name: '已存在的资源',
          sections: <ResourceTreeSectionDraft>[
            ResourceTreeSectionDraft(
              id: const SectionId('res_bp_boundary_sec'),
              title: '已有章节',
              parts: <ResourceTreePartDraft>[
                ResourceTreePartDraft(
                  id: const PartId('res_bp_boundary_part'),
                  title: '已有段落',
                  content: content,
                ),
              ],
            ),
          ],
        ),
      );

  Future<void> seedSession({
    String status = 'planning',
    bool withResourceId = true,
  }) async {
    final db = await getDb();
    await db.insert('resource_creation_sessions', <String, Object?>{
      'session_id': sessionId,
      'idempotency_key': 'idem_bp_boundary',
      'resource_type': ResourceType.worldview.storageValue,
      'method': 'aiReference',
      'name': '会话',
      'summary': '',
      'status': status,
      'resource_id': withResourceId ? resourceId.value : '',
      'reference_kind': 'none',
      'reference_label': '',
      'reference_file_name': '',
      'reference_resource_id': '',
      'reference_body': '',
      'reference_char_count': 0,
      'origin': 'test',
      'request_fingerprint': '',
      'error_message': '',
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> seedBlueprint({String status = 'draft'}) async {
    final blueprint = ResourceBlueprint(
      blueprintId: blueprintId,
      sessionId: sessionId,
      resourceType: ResourceType.worldview,
      suggestedName: '新大纲',
      summary: '新大纲摘要',
      resourceId: resourceId,
      sections: <BlueprintSection>[
        BlueprintSection(
          id: 'sec_new',
          title: '新的章节',
          summary: '',
          parts: <BlueprintPart>[
            const BlueprintPart(
              id: 'part_new',
              sectionId: 'sec_new',
              title: '新的段落',
              generationGoal: '写新的段落',
              estimatedLength: 400,
            ),
          ],
        ),
      ],
    );
    final db = await getDb();
    await db.insert('resource_blueprints', <String, Object?>{
      'blueprint_id': blueprintId,
      'session_id': sessionId,
      'resource_type': ResourceType.worldview.storageValue,
      'suggested_name': blueprint.suggestedName,
      'summary': blueprint.summary,
      'revision': 1,
      'status': status,
      'target_capacity': blueprint.targetCapacity,
      'blueprint_json': jsonEncode(BlueprintParser.toMap(blueprint)),
      'resource_id': resourceId.value,
      'created_at': now,
      'updated_at': now,
    });
  }

  test('confirming over an existing tree records the replaced state', () async {
    await seedExistingTree();
    await seedSession();
    await seedBlueprint();
    // The state that is about to be overwritten must already be the head.
    final before = await phase9.revisionService.captureRevision(
      resourceId,
      cause: RevisionCause.migration,
    );
    expect(before.captured, isTrue);

    final repository = ResourceBlueprintRepositoryImpl(
      getDb: getDb,
      treeRepository: phase9.tree,
      revisionCapture: phase9.captureEngine,
    );
    await repository.confirmBlueprint(blueprintId: blueprintId);

    // The tree really was replaced.
    final tree = await phase9.tree.readTree(resourceId);
    expect(tree, isNotNull);
    expect(tree!.sections.single.title, '新的章节');

    // …and the replaced state is still in history with the planning cause.
    final history = await phase9.revisionService.history(resourceId);
    expect(
      history.any((revision) => revision.cause == RevisionCause.planning),
      isTrue,
      reason: 'a blueprint overwrite must be recorded like any lossy write '
          '(P9-I2)',
    );

    final replaced = await phase9.revisionService.readState(
      ResourceRevisionId(before.revision!.revisionId.value),
    );
    expect(
      replaced.nodes.values
          .firstWhere((node) => node.nodeId == 'res_bp_boundary_part')
          .content,
      '确认前已有的正文',
      reason: 'the body the confirmation replaced must stay recoverable',
    );
  });

  test('the newest head after confirmation describes the new tree', () async {
    await seedExistingTree();
    await seedSession();
    await seedBlueprint();

    final repository = ResourceBlueprintRepositoryImpl(
      getDb: getDb,
      treeRepository: phase9.tree,
      revisionCapture: phase9.captureEngine,
    );
    await repository.confirmBlueprint(blueprintId: blueprintId);

    final head = await phase9.revisionService.latestHead(resourceId);
    expect(head, isNotNull);
    final state = await phase9.revisionService.readState(head!.revisionId);
    // Confirmation namespaces the placeholder ids under the resource id.
    expect(
      state.nodes.values
          .any((node) => node.nodeId == '${resourceId.value}_part_new'),
      isTrue,
    );
  });

  test('a first confirmation on a new tree still creates the tree', () async {
    // Session points at the resource id, but no tree exists yet: create branch.
    await seedSession();
    await seedBlueprint();

    final repository = ResourceBlueprintRepositoryImpl(
      getDb: getDb,
      treeRepository: phase9.tree,
      revisionCapture: phase9.captureEngine,
    );
    final result = await repository.confirmBlueprint(
      blueprintId: blueprintId,
    );

    expect(result.reusedExisting, isFalse);
    expect(await phase9.tree.findResource(resourceId), isNotNull);
  });
}
