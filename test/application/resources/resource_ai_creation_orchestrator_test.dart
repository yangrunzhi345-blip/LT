import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/llm/llm_gateway.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/controllers/streaming_resource_generation_controller.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/streaming_generation_runtime_contracts.dart';
import 'package:lt_dialogue/features/resource_studio/application/use_cases/resource_ai_creation_orchestrator.dart';
import 'package:lt_dialogue/models/llm_task.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/r01_streaming_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory directory;
  late R01StreamingFixture fixture;
  late Completer<void> allowGeneration;
  late Completer<void> generationStarted;
  late StreamingResourceGenerationController controller;
  late ResourceAiCreationOrchestrator orchestrator;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lt_ai_orchestrator_');
    DatabaseService.customDbDir = directory.path;
    await DatabaseService.resetDatabase();
    await DatabaseService.database;
    fixture = R01StreamingFixture();
    allowGeneration = Completer<void>();
    generationStarted = Completer<void>();
    final service = fixture.buildService(({
      required String systemPrompt,
      required String instruction,
      required LlmTask task,
      GenerationTaskHandle? taskHandle,
    }) async {
      if (!generationStarted.isCompleted) generationStarted.complete();
      await allowGeneration.future;
      return r01Completion(systemPrompt, '统一 Authority 生成的正文。');
    });
    controller = StreamingResourceGenerationController(
      service: service,
      sessionRepository: fixture.sessionRepository,
    );
    orchestrator = ResourceAiCreationOrchestrator(
      controller: controller,
      sessionRepository: fixture.sessionRepository,
      treeRepository: fixture.treeRepository,
      blueprintRepository: fixture.blueprintRepository,
      pipeline: fixture.pipeline,
      gateway: const _PlanningGateway(),
    );
  });

  tearDown(() async {
    if (!allowGeneration.isCompleted) allowGeneration.complete();
    controller.dispose();
    await DatabaseService.resetDatabase();
    DatabaseService.customDbDir = null;
    await directory.delete(recursive: true);
  });

  test('returns stable identities before terminal generation and reuses them',
      () async {
    const draft = ResourceAiCreationDraft(
      resourceType: ResourceType.worldview,
      name: '统一创建入口',
      referenceSource: ReferenceSource(
        kind: ReferenceSourceKind.text,
        body: '山海之间的城市。',
        characterCount: 8,
      ),
      targetCharacters: 5000,
      idempotencyKey: 'stable-submit-key',
      origin: 'orchestrator-test',
      libraryMode: 'adventure',
    );

    final first = await orchestrator.createAndStart(draft);
    await generationStarted.future.timeout(const Duration(seconds: 2));
    final running =
        await fixture.sessionRepository.findSession(first.generationSessionId);
    expect(running, isNotNull);
    expect(running!.status, isNot(StreamingLifecycleStatus.completed));

    final repeatedSubmit = await orchestrator.createAndStart(draft);
    final continued =
        await orchestrator.continueAndStart(first.creationSessionId);
    expect(repeatedSubmit.creationSessionId, first.creationSessionId);
    expect(repeatedSubmit.resourceId, first.resourceId);
    expect(repeatedSubmit.generationSessionId, first.generationSessionId);
    expect(continued.creationSessionId, first.creationSessionId);
    expect(continued.resourceId, first.resourceId);
    expect(continued.generationSessionId, first.generationSessionId);

    final db = await DatabaseService.database;
    expect(await db.query('resource_creation_sessions'), hasLength(1));
    expect(await db.query('resource_blueprints'), hasLength(1));
    expect(await db.query('resources'), hasLength(1));
    expect(await db.query('resource_generation_tasks'), hasLength(1));
    expect(await db.query('resource_generation_sessions'), hasLength(1));

    allowGeneration.complete();
    await _waitForStatus(
      fixture,
      first.generationSessionId,
      StreamingLifecycleStatus.completed,
    );
  });

  test('appends the full origin worldview and persists its compatibility id',
      () async {
    await fixture.pipeline.create(
      const ResourceCreationRequest(
        resourceType: ResourceType.worldview,
        method: CreationMethod.manual,
        name: '霜火世界',
        idempotencyKey: 'origin-worldview',
        summary: '北境与古龙的世界',
        resourceId: 'origin-worldview',
        initialSections: [
          ResourceTreeSectionDraft(
            title: '历史',
            summary: '旧王朝的兴衰',
            parts: [
              ResourceTreePartDraft(
                title: '远古战争',
                content: '古龙曾在霜火之地交战。',
              ),
            ],
          ),
        ],
      ),
    );

    const draft = ResourceAiCreationDraft(
      resourceType: ResourceType.character,
      name: '霜火旅者',
      referenceSource: ReferenceSource(
        kind: ReferenceSourceKind.text,
        body: '角色主要参考资料。',
        characterCount: 9,
      ),
      targetCharacters: 3000,
      idempotencyKey: 'origin-character',
      origin: 'orchestrator-origin-test',
      libraryMode: 'adventure',
      originWorldviewId: 'origin-worldview',
    );
    final plan = await orchestrator.createAndPlan(draft);
    final plannedSession =
        await fixture.pipeline.findSession(plan.creationSessionId);
    expect(plannedSession!.referenceSource.body, contains('角色主要参考资料。'));
    expect(plannedSession.referenceSource.body, contains('霜火世界'));
    expect(plannedSession.referenceSource.body, contains('古龙曾在霜火之地交战。'));

    final identity = await orchestrator.confirmAndStart(plan.creationSessionId);
    final tree = await fixture.treeRepository.readTree(identity.resourceId);
    expect(
        tree!.resource.metadata['matching_worldview_id'], 'origin-worldview');

    final sameWorldviewReference = await orchestrator.createAndPlan(
      const ResourceAiCreationDraft(
        resourceType: ResourceType.npc,
        name: '霜火守卫',
        referenceSource: ReferenceSource(
          kind: ReferenceSourceKind.existingResource,
          label: '霜火世界',
          existingResourceId: 'origin-worldview',
        ),
        targetCharacters: 3000,
        idempotencyKey: 'origin-npc',
        origin: 'orchestrator-origin-test',
        libraryMode: 'adventure',
        originWorldviewId: 'origin-worldview',
      ),
    );
    final sameSession = await fixture.pipeline
        .findSession(sameWorldviewReference.creationSessionId);
    final body = sameSession!.referenceSource.body;
    expect(body.split('霜火世界').length - 1, 1);
    final npcIdentity = await orchestrator.confirmAndStart(
      sameWorldviewReference.creationSessionId,
    );
    final npcTree =
        await fixture.treeRepository.readTree(npcIdentity.resourceId);
    expect(
      npcTree!.resource.metadata['matching_worldview_id'],
      'origin-worldview',
    );
    allowGeneration.complete();
    await _waitForStatus(
      fixture,
      identity.generationSessionId,
      StreamingLifecycleStatus.completed,
    );
    await _waitForStatus(
      fixture,
      npcIdentity.generationSessionId,
      StreamingLifecycleStatus.completed,
    );
  });

  test('confirms one candidate selection atomically and cannot be overwritten',
      () async {
    orchestrator = ResourceAiCreationOrchestrator(
      controller: controller,
      sessionRepository: fixture.sessionRepository,
      treeRepository: fixture.treeRepository,
      blueprintRepository: fixture.blueprintRepository,
      pipeline: fixture.pipeline,
      gateway: const _PlanningGateway(twoParts: true),
    );
    const draft = ResourceAiCreationDraft(
      resourceType: ResourceType.character,
      name: '场景候选',
      referenceSource: ReferenceSource(
        kind: ReferenceSourceKind.text,
        body: '甲与乙出现在场景中。',
        characterCount: 10,
      ),
      targetCharacters: 3000,
      idempotencyKey: 'scene-selection-key',
      origin: 'scene-batch-import',
      libraryMode: 'adventure',
    );

    final plan = await orchestrator.createAndPlan(draft);
    final partIds = plan.blueprint.allParts.map((part) => part.id).toList();
    expect(partIds, hasLength(2));
    expect(
      (await fixture.pipeline.pendingPlanningSessions())
          .map((session) => session.sessionId),
      [plan.creationSessionId],
    );
    final db = await DatabaseService.database;
    expect(await db.query('resources'), isEmpty);
    expect(await db.query('resource_generation_tasks'), isEmpty);
    expect(await db.query('resource_generation_sessions'), isEmpty);

    final first = await orchestrator.confirmAndStart(
      plan.creationSessionId,
      selectedPartIds: {partIds.first},
    );
    await generationStarted.future.timeout(const Duration(seconds: 2));
    final repeated = await orchestrator.confirmAndStart(
      plan.creationSessionId,
      selectedPartIds: {partIds.last},
    );
    expect(repeated.resourceId, first.resourceId);
    expect(repeated.generationSessionId, first.generationSessionId);
    expect(await fixture.pipeline.pendingPlanningSessions(), isEmpty);

    final persisted = await fixture.blueprintRepository
        .findLatestBlueprint(plan.creationSessionId);
    expect(persisted!.allParts.map((part) => part.id), [partIds.first]);
    final tasks = await fixture.blueprintRepository
        .findGenerationTasks(persisted.blueprintId);
    expect(tasks.map((task) => task.partId), [
      '${first.resourceId.value}_${partIds.first}',
    ]);
  });

  test('existing character regeneration rejects a manual edit after planning',
      () async {
    const resourceId = ResourceId('character_existing');
    const partId = PartId('character_existing_profile');
    await fixture.pipeline.create(
      const ResourceCreationRequest(
        resourceType: ResourceType.character,
        method: CreationMethod.manual,
        name: '手工角色',
        idempotencyKey: 'manual-character',
        resourceId: 'character_existing',
        initialSections: [
          ResourceTreeSectionDraft(
            id: SectionId('character_existing_core'),
            title: '核心资料',
            parts: [
              ResourceTreePartDraft(
                id: partId,
                title: '角色资料',
                content: '规划前内容',
              ),
            ],
          ),
        ],
      ),
    );
    orchestrator = ResourceAiCreationOrchestrator(
      controller: controller,
      sessionRepository: fixture.sessionRepository,
      treeRepository: fixture.treeRepository,
      blueprintRepository: fixture.blueprintRepository,
      pipeline: fixture.pipeline,
      gateway: const _PlanningGateway(estimatedLength: 3000),
    );
    const draft = ResourceAiCreationDraft(
      resourceType: ResourceType.character,
      name: '手工角色',
      referenceSource: ReferenceSource(
        kind: ReferenceSourceKind.text,
        body: '以当前角色资料为参考重新生成。',
        characterCount: 14,
      ),
      targetCharacters: 3000,
      idempotencyKey: 'character-regeneration',
      origin: 'character-editor-regeneration',
      libraryMode: 'adventure',
      targetResourceId: resourceId,
    );

    final plan = await orchestrator.createAndPlan(draft);
    final token = (await fixture.treeRepository.readNodeState(partId))!;
    await fixture.treeRepository.updatePart(
      id: partId,
      expectedUpdatedAt: token.updatedAt,
      content: '规划后用户手工修改，必须保留',
    );

    await expectLater(
      orchestrator.confirmAndStart(plan.creationSessionId),
      throwsA(isA<ResourceTreeConflictException>()),
    );
    final tree = await fixture.treeRepository.readTree(resourceId);
    expect(tree!.parts.single.content, '规划后用户手工修改，必须保留');
    expect(
        await fixture.sessionRepository
            .findSessionsForResource(resourceId.value),
        isEmpty);
  });
}

Future<void> _waitForStatus(
  R01StreamingFixture fixture,
  String sessionId,
  StreamingLifecycleStatus expected,
) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    final session = await fixture.sessionRepository.findSession(sessionId);
    if (session?.status == expected) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  final session = await fixture.sessionRepository.findSession(sessionId);
  fail('会话未进入 ${expected.storageValue}，当前为 ${session?.status}');
}

final class _PlanningGateway implements LlmGateway {
  const _PlanningGateway({this.twoParts = false, this.estimatedLength = 5000});

  final bool twoParts;
  final int estimatedLength;

  @override
  bool get isConfigured => true;

  @override
  Future<String> rawCompletion({
    required String systemPrompt,
    required String instruction,
    int maximumOutputTokens = 4096,
    double temperature = .7,
    LlmTask task = LlmTask.structuredExtraction,
    GenerationTaskHandle? taskHandle,
  }) async {
    final sectionId =
        RegExp(r'允许的 Section ID：([^,\n]+)').firstMatch(systemPrompt)!.group(1)!;
    final partId =
        RegExp(r'允许的 Part ID：([^,\n]+)').firstMatch(systemPrompt)!.group(1)!;
    final allowedPartIds = RegExp(r'允许的 Part ID：([^\n]+)')
        .firstMatch(systemPrompt)!
        .group(1)!
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    return jsonEncode({
      'suggestedName': '统一创建入口',
      'summary': '测试统一创建编排',
      'sections': [
        {
          'id': sectionId,
          'title': '概览',
          'summary': '世界概览',
          'sortOrder': 0,
          'parts': [
            {
              'id': partId,
              'sectionId': sectionId,
              'title': '正文',
              'generationGoal': '生成世界观正文',
              'estimatedLength': twoParts ? 1500 : estimatedLength,
              'dependencies': <String>[],
              'sortOrder': 0,
            },
            if (twoParts)
              {
                'id': allowedPartIds[1],
                'sectionId': sectionId,
                'title': '乙',
                'generationGoal': '生成乙的角色资料',
                'estimatedLength': 1500,
                'dependencies': <String>[],
                'sortOrder': 1,
              },
          ],
        },
      ],
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(invocation.memberName.toString());
}
