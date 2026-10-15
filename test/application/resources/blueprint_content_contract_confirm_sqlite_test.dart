import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/blueprint_planner.dart';
import 'package:lt_dialogue/application/resources/blueprint_validator.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/domain/resources/content_requirements.dart';
import 'package:lt_dialogue/domain/resources/narrative_minimum_policy.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/models/llm_task.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import '../../helpers/phase10_fixture.dart';

/// U6-B production chain: Blueprint → Normalize → ContentRequirements → Review
/// → Confirm → SQLite, on a real temporary database.
void main() {
  final fixture = Phase10Fixture();
  setUp(() => fixture.setUp(prefix: 'lt_u6b_'));
  tearDown(fixture.tearDown);

  late ResourceCreationPipeline pipeline;
  late ResourceBlueprintRepositoryImpl repo;

  setUp(() {
    pipeline = ResourceCreationPipeline(
        getDb: () async => fixture.db,
        treeRepository: fixture.treeRepository,
        hasAiCredentials: () => true);
    repo = ResourceBlueprintRepositoryImpl(
        getDb: () async => fixture.db, treeRepository: fixture.treeRepository);
  });

  String planJson({
    required String sectionId,
    required String partId,
    int estimatedLength = 1000,
    Map<String, Object?>? contentRequirements,
  }) =>
      '{"suggestedName":"契约资源","summary":"摘要","sections":[{'
      '"id":"$sectionId","title":"概览","summary":"","sortOrder":0,'
      '"parts":[{"id":"$partId","sectionId":"$sectionId","title":"正文",'
      '"generationGoal":"生成正文","estimatedLength":$estimatedLength,'
      '"dependencies":[],"sortOrder":0'
      '${contentRequirements == null ? '' : ',"contentRequirements":${jsonEncode(contentRequirements)}'}}]}]}';

  String idFrom(String prompt, String label) =>
      RegExp('$label：([^,\\n]+)').firstMatch(prompt)!.group(1)!.trim();

  Future<ResourceCreationResult> createSession(String key,
      {int target = 5000}) async {
    return pipeline.create(ResourceCreationRequest(
      resourceType: ResourceType.worldview,
      method: CreationMethod.aiReference,
      name: '契约资源',
      referenceSource: ReferenceSource.text('参考'),
      targetCharacters: target,
      idempotencyKey: key,
    ));
  }

  BlueprintPlanner plannerReturning(List<String> plans) {
    var index = 0;
    return BlueprintPlanner(
      pipeline: pipeline,
      blueprintRepository: repo,
      completer: ({
        required String systemPrompt,
        required String instruction,
        required LlmTask task,
        GenerationTaskHandle? taskHandle,
      }) async {
        final plan = plans[index < plans.length ? index : plans.length - 1];
        index++;
        return plan
            .replaceAll('{SEC}', idFrom(systemPrompt, '允许的 Section ID'))
            .replaceAll('{PART}', idFrom(systemPrompt, '允许的 Part ID'));
      },
    );
  }

  test('plan attaches client contracts, confirm persists, reopen keeps them',
      () async {
    final session = await createSession('t1');
    final planner = plannerReturning([
      planJson(sectionId: '{SEC}', partId: '{PART}', estimatedLength: 1000),
    ]);

    final planned = await planner.plan(sessionId: session.sessionId!);
    final part = planned.allParts.single;
    expect(part.contentRequirements, isNotNull);
    expect(part.contentRequirements!.kind, PartContentKind.narrative);
    expect(part.contentRequirements!.minimumCharacters,
        NarrativeMinimumPolicy.minimumCharactersFor(part.estimatedLength));

    final confirmation =
        await repo.confirmBlueprint(blueprintId: planned.blueprintId);
    final reopened = await repo.findBlueprint(planned.blueprintId);
    expect(reopened!.status, BlueprintStatus.confirmed);
    expect(reopened.resourceId, confirmation.resourceId);
    expect(
        reopened.allParts.single.contentRequirements, part.contentRequirements,
        reason: 'confirm 不得改变已冻结的契约');
  });

  test('a model-supplied minimum=1 is overridden by the client policy',
      () async {
    final session = await createSession('t2', target: 3000);
    final planner = plannerReturning([
      planJson(
        sectionId: '{SEC}',
        partId: '{PART}',
        estimatedLength: 3000,
        contentRequirements: {
          'version': 1,
          'kind': 'narrative',
          'required': true,
          'minimumCharacters': 1,
          'validationProfile': 'narrativeSectionsV1',
          'requiredFields': <String>[],
          'requiredHeadings': <String>[],
        },
      ),
    ]);
    final planned = await planner.plan(sessionId: session.sessionId!);
    // Worldview plans are folded to 80% of the target (3000 -> 2400), so the
    // client policy derives the minimum from the folded length (2400 -> 820),
    // never from the model's forged minimum=1.
    expect(planned.allParts.single.contentRequirements!.minimumCharacters, 820,
        reason: '模型伪造的 minimum=1 必须被客户端覆盖');
  });

  test('normalizer shrinking a plan updates the attached minimum', () async {
    final session = await createSession('t3', target: 1000);
    final planner = plannerReturning([
      planJson(sectionId: '{SEC}', partId: '{PART}', estimatedLength: 2000),
    ]);
    final planned = await planner.plan(sessionId: session.sessionId!);
    final part = planned.allParts.single;
    expect(part.estimatedLength, lessThan(2000), reason: '应被归一化到目标以内');
    expect(part.contentRequirements!.minimumCharacters,
        NarrativeMinimumPolicy.minimumCharactersFor(part.estimatedLength));
  });

  test('replan recomputes the contract from the new plan', () async {
    final session = await createSession('t4', target: 5000);
    final planner = plannerReturning([
      planJson(sectionId: '{SEC}', partId: '{PART}', estimatedLength: 1000),
      planJson(sectionId: '{SEC}', partId: '{PART}', estimatedLength: 500),
    ]);
    final first = await planner.plan(sessionId: session.sessionId!);
    expect(first.allParts.single.contentRequirements!.minimumCharacters, 400);

    final second =
        await planner.replan(sessionId: session.sessionId!, userFeedback: '更短');
    expect(second.revision, first.revision + 1);
    expect(second.allParts.single.contentRequirements!.minimumCharacters, 220,
        reason: 'replan 必须按新规划重算，不沿用旧 minimum');
  });

  test('a plan below the narrative floor leaves a gap and confirm is blocked',
      () async {
    final session = await createSession('t5', target: 1000);
    final planner = plannerReturning([
      planJson(sectionId: '{SEC}', partId: '{PART}', estimatedLength: 79),
    ]);
    final planned = await planner.plan(sessionId: session.sessionId!);
    expect(planned.allParts.single.contentRequirements, isNull);

    await expectLater(
      repo.confirmBlueprint(blueprintId: planned.blueprintId),
      throwsA(isA<BlueprintValidationException>()),
    );
    // Nothing half-written.
    expect((await fixture.db.query('resources')), isEmpty);
    expect((await fixture.db.query('resource_generation_tasks')), isEmpty);
  });

  test(
      'a direct repository confirm cannot run a partially-contracted blueprint',
      () async {
    final session = await createSession('t6');
    final requirements = ContentRequirements(
      kind: PartContentKind.narrative,
      minimumCharacters: 100,
      validationProfile: PartValidationProfile.narrativeSectionsV1,
    );
    final blueprint = ResourceBlueprint(
      blueprintId: 'bp_partial',
      sessionId: session.sessionId!,
      resourceType: ResourceType.worldview,
      suggestedName: '契约资源',
      summary: '',
      targetCapacity: 5000,
      sections: [
        BlueprintSection(id: 'sec', title: '概览', parts: [
          BlueprintPart(
              id: 'a',
              sectionId: 'sec',
              title: '甲',
              generationGoal: 'g',
              estimatedLength: 500,
              contentRequirements: requirements),
          const BlueprintPart(
              id: 'b',
              sectionId: 'sec',
              title: '乙',
              generationGoal: 'g',
              estimatedLength: 500),
        ]),
      ],
    );
    await repo.saveBlueprint(blueprint);
    await expectLater(
      repo.confirmBlueprint(blueprintId: 'bp_partial'),
      throwsA(isA<BlueprintValidationException>()),
    );
    expect((await fixture.db.query('resources')), isEmpty);
    expect((await fixture.db.query('resource_generation_tasks')), isEmpty);
  });

  test('a direct repository confirm cannot accept an invalid contract',
      () async {
    final session = await createSession('t7');
    // minimum (900) > estimatedLength (500): structurally invalid.
    final invalid = ContentRequirements(
      kind: PartContentKind.narrative,
      minimumCharacters: 900,
      validationProfile: PartValidationProfile.narrativeSectionsV1,
    );
    final blueprint = ResourceBlueprint(
      blueprintId: 'bp_invalid',
      sessionId: session.sessionId!,
      resourceType: ResourceType.worldview,
      suggestedName: '契约资源',
      summary: '',
      targetCapacity: 5000,
      sections: [
        BlueprintSection(id: 'sec', title: '概览', parts: [
          BlueprintPart(
              id: 'a',
              sectionId: 'sec',
              title: '甲',
              generationGoal: 'g',
              estimatedLength: 500,
              contentRequirements: invalid),
        ]),
      ],
    );
    await repo.saveBlueprint(blueprint);
    await expectLater(
      repo.confirmBlueprint(blueprintId: 'bp_invalid'),
      throwsA(isA<BlueprintValidationException>()),
    );
    expect((await fixture.db.query('resources')), isEmpty);
  });

  test('a legacy contract-less blueprint still confirms (unchanged)', () async {
    final session = await createSession('t8');
    final blueprint = ResourceBlueprint(
      blueprintId: 'bp_legacy',
      sessionId: session.sessionId!,
      resourceType: ResourceType.worldview,
      suggestedName: '契约资源',
      summary: '',
      targetCapacity: 5000,
      sections: [
        BlueprintSection(id: 'sec', title: '概览', parts: [
          const BlueprintPart(
              id: 'a',
              sectionId: 'sec',
              title: '甲',
              generationGoal: 'g',
              estimatedLength: 500),
        ]),
      ],
    );
    await repo.saveBlueprint(blueprint);
    final confirmation = await repo.confirmBlueprint(blueprintId: 'bp_legacy');
    expect(confirmation.resourceId.value, isNotEmpty);
    final reopened = await repo.findBlueprint('bp_legacy');
    expect(reopened!.allParts.single.contentRequirements, isNull,
        reason: 'Legacy 无契约蓝图不得被追溯补造契约');
  });
}
