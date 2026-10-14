import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/application/llm/llm_gateway.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/controllers/streaming_resource_generation_controller.dart';
import 'package:lt_dialogue/domain/resources/part_contract_status.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/features/resource_studio/application/use_cases/resource_studio_runtime.dart';
import 'package:lt_dialogue/models/llm_task.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import '../../helpers/r01_streaming_fixture.dart';

/// U6-D runtime projection: real SQLite + real repositories + real runtime.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  late Directory directory;
  late R01StreamingFixture fixture;
  late StreamingResourceGenerationController controller;
  late StreamingResourceStudioRuntime runtime;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lt_u6d_');
    DatabaseService.customDbDir = directory.path;
    await DatabaseService.resetDatabase();
    await DatabaseService.database;
    fixture = R01StreamingFixture();
    final service = fixture.buildService(r01Completer('文' * 1200));
    controller = StreamingResourceGenerationController(
      service: service,
      sessionRepository: fixture.sessionRepository,
    );
    runtime = StreamingResourceStudioRuntime(
      controller: controller,
      sessionRepository: fixture.sessionRepository,
      treeRepository: fixture.treeRepository,
      blueprintRepository: fixture.blueprintRepository,
      pipeline: fixture.pipeline,
      gateway: const _PlanGateway(),
    );
  });

  tearDown(() async {
    controller.dispose();
    await DatabaseService.resetDatabase();
    DatabaseService.customDbDir = null;
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  Future<ResourceId> seedLegacyAiResource() async {
    final session = await fixture.pipeline.create(ResourceCreationRequest(
        resourceType: ResourceType.character,
        method: CreationMethod.aiReference,
        name: '历史角色',
        referenceSource: ReferenceSource.text('参考'),
        targetCharacters: 3000,
        idempotencyKey: 'legacy_ai'));
    final blueprint = ResourceBlueprint(
        blueprintId: 'bp_legacy',
        sessionId: session.sessionId!,
        resourceType: ResourceType.character,
        suggestedName: '历史角色',
        summary: '',
        targetCapacity: 3000,
        sections: [
          BlueprintSection(id: 's', title: '背景', parts: [
            const BlueprintPart(
                id: 'p0',
                sectionId: 's',
                title: '背景',
                generationGoal: 'g',
                estimatedLength: 800),
          ])
        ]);
    final repo = ResourceBlueprintRepositoryImpl(
        getDb: () async => DatabaseService.database,
        treeRepository: fixture.treeRepository);
    await repo.saveBlueprint(blueprint);
    final confirmed = await repo.confirmBlueprint(blueprintId: 'bp_legacy');
    return confirmed.resourceId;
  }

  test('an authoritative legacy AI blueprint yields legacyUnknownContract',
      () async {
    final resourceId = await seedLegacyAiResource();
    final statuses = await runtime.blueprintPartContracts(resourceId);
    expect(statuses.values.single, PartContractStatus.legacyUnknownContract);
  });

  test('a new U6 plan yields confirmedContract', () async {
    final session = await fixture.pipeline.create(ResourceCreationRequest(
        resourceType: ResourceType.character,
        method: CreationMethod.aiReference,
        name: '新角色',
        referenceSource: ReferenceSource.text('参考'),
        targetCharacters: 3000,
        idempotencyKey: 'new_ai'));
    final blueprint = await fixture.pipeline.planAiSession(
        sessionId: session.sessionId!, gateway: const _PlanGateway());
    final confirmed = await fixture.pipeline
        .confirmAiBlueprint(blueprintId: blueprint.blueprintId);
    final statuses = await runtime.blueprintPartContracts(confirmed.resourceId);
    expect(statuses.values.single, PartContractStatus.confirmedContract);
  });

  test('a manual resource is notApplicable', () async {
    final created = await fixture.pipeline.create(const ResourceCreationRequest(
        resourceType: ResourceType.character,
        method: CreationMethod.manual,
        name: '手工角色',
        idempotencyKey: 'manual_1',
        resourceId: 'res_manual_u6d',
        initialSections: [
          ResourceTreeSectionDraft(
              id: SectionId('res_manual_u6d_sec'),
              title: '核心',
              parts: [
                ResourceTreePartDraft(
                    id: PartId('res_manual_u6d_sec_p'),
                    title: '资料',
                    content: '两字')
              ]),
        ]));
    final statuses = await runtime.blueprintPartContracts(created.resourceId!);
    expect(statuses.values, everyElement(PartContractStatus.notApplicable));
  });

  test('reading the projection performs no write and preserves legacy rows',
      () async {
    final resourceId = await seedLegacyAiResource();
    // A historical 1-char body on the legacy Part.
    final tree = (await fixture.treeRepository.readTree(resourceId))!;
    final partId = tree.parts.single.id.value;
    await (await DatabaseService.database).update(
        'resource_parts', {'content': '荒', 'content_hash': 'legacy-hash'},
        where: 'id = ?', whereArgs: [partId]);

    await runtime.blueprintPartContracts(resourceId);

    final after = await fixture.treeRepository.readTree(resourceId);
    expect(after!.parts.single.content, '荒');
    expect(after.parts.single.contentHash, 'legacy-hash');
  });

  test('status survives a database restart', () async {
    final resourceId = await seedLegacyAiResource();
    final first = await runtime.blueprintPartContracts(resourceId);
    await DatabaseService.resetDatabase();
    await DatabaseService.database;
    final second = await runtime.blueprintPartContracts(resourceId);
    expect(second, first);
  });
}

/// Minimal LlmGateway returning a valid over-target blueprint plan.
final class _PlanGateway implements LlmGateway {
  const _PlanGateway();

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
    return jsonEncode({
      'suggestedName': '新角色',
      'summary': '摘要',
      'sections': [
        {
          'id': sectionId,
          'title': '背景',
          'summary': '',
          'sortOrder': 0,
          'parts': [
            {
              'id': partId,
              'sectionId': sectionId,
              'title': '背景',
              'generationGoal': 'g',
              'estimatedLength': 800,
              'dependencies': <String>[],
              'sortOrder': 0,
            }
          ],
        }
      ],
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(invocation.memberName.toString());
}
