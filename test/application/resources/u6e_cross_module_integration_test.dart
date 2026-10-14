import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/part_generation_coordinator.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_service.dart';
import 'package:lt_dialogue/domain/resources/content_requirements.dart';
import 'package:lt_dialogue/domain/resources/narrative_minimum_policy.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import '../../helpers/phase10_fixture.dart';
import '../../helpers/r01_streaming_fixture.dart';

/// U6-E: the confirmed content contract must not break LT's resource,
/// assembly or adventure-readiness behaviour across resource types. Real
/// SQLite + real coordinator/pipeline; only the model body is a deterministic
/// fake.
void main() {
  final fixture = Phase10Fixture();
  setUp(() => fixture.setUp(prefix: 'lt_u6e_'));
  tearDown(fixture.tearDown);

  ContentRequirements narrative(int minimum) => ContentRequirements(
      kind: PartContentKind.narrative,
      minimumCharacters: minimum,
      validationProfile: PartValidationProfile.narrativeSectionsV1);

  ContentRequirements scalar() => ContentRequirements(
      kind: PartContentKind.scalar,
      minimumCharacters: 1,
      validationProfile: PartValidationProfile.scalarTextV1);

  Future<
      ({
        ResourceId id,
        ResourceBlueprint blueprint,
        PartGenerationTaskRepositoryImpl tasks
      })> create({
    required ResourceType type,
    required int target,
    required List<({String id, int estimated, ContentRequirements? contract})>
        parts,
    required String suffix,
    String? origin,
  }) async {
    final pipeline = ResourceCreationPipeline(
        getDb: () async => fixture.db,
        treeRepository: fixture.treeRepository,
        hasAiCredentials: () => true);
    final session = await pipeline.create(ResourceCreationRequest(
        resourceType: type,
        method: CreationMethod.aiReference,
        name: 'U6E $suffix',
        referenceSource: ReferenceSource.text('参考'),
        targetCharacters: target,
        idempotencyKey: 'u6e_$suffix',
        origin: origin ?? ''));
    final blueprint = ResourceBlueprint(
        blueprintId: 'u6e_$suffix',
        sessionId: session.sessionId!,
        resourceType: type,
        suggestedName: 'U6E $suffix',
        summary: '',
        targetCapacity: target,
        sections: [
          BlueprintSection(id: 's', title: '内容', parts: [
            for (final p in parts)
              BlueprintPart(
                  id: p.id,
                  sectionId: 's',
                  title: p.id,
                  generationGoal: 'g',
                  estimatedLength: p.estimated,
                  contentRequirements: p.contract),
          ])
        ]);
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

  /// Returns a completer that yields [bodyFor] sized by the part's planned
  /// length parsed from the prompt target, so every Part meets its contract.
  PartRawCompleter sizedCompleter(int unit) => r01Completer('文' * unit);

  test('character T=10000 (E20) with dynamic-min contracts completes within C',
      () async {
    final minimum = NarrativeMinimumPolicy.minimumCharactersFor(1000);
    final stack = await create(
        type: ResourceType.character,
        target: 10000,
        parts: [
          for (var i = 0; i < 10; i++)
            (id: 'p$i', estimated: 1000, contract: narrative(minimum)),
        ],
        suffix: 'char_t10000');
    final generator = coordinator(stack.tasks, sizedCompleter(1000));
    expect(
        await generator.generateAllParts(
            blueprintId: stack.blueprint.blueprintId, maxRetriesPerPart: 0),
        isTrue);
    final tasks = await stack.tasks.findTasksForResource(stack.id.value);
    expect(tasks.every((t) => t.status == 'completed'), isTrue);
    final total =
        (await stack.tasks.getPartsContent(tasks.map((t) => t.partId).toList()))
            .values
            .fold<int>(0, (sum, v) => sum + v.content.length);
    expect(total, 10000);
    expect(total, lessThanOrEqualTo(12000), reason: '不得超出冻结 C=E20 上限');
  });

  test('E50 widens C without drift and still completes', () async {
    final minimum = NarrativeMinimumPolicy.minimumCharactersFor(1000);
    final stack = await create(
        type: ResourceType.character,
        target: 10000,
        parts: [
          for (var i = 0; i < 10; i++)
            (id: 'p$i', estimated: 1000, contract: narrative(minimum)),
        ],
        suffix: 'char_e50',
        // A run-scoped choice of 50% is frozen into the blueprint at confirm.
        origin: const ResourceCreationOriginEnvelope(
                origin: 'test', libraryMode: 'adventure', elasticPercent: 50)
            .encode());
    final generator = coordinator(stack.tasks, sizedCompleter(1000));
    expect(
        await generator.generateAllParts(
            blueprintId: stack.blueprint.blueprintId, maxRetriesPerPart: 0),
        isTrue);
    final tasks = await stack.tasks.findTasksForResource(stack.id.value);
    final total =
        (await stack.tasks.getPartsContent(tasks.map((t) => t.partId).toList()))
            .values
            .fold<int>(0, (sum, v) => sum + v.content.length);
    expect(total, 10000);
    expect(total, lessThanOrEqualTo(15000));
  });

  test(
      'worldview: long Unicode/Markdown/no-trailing-newline body saves verbatim',
      () async {
    final minimum = NarrativeMinimumPolicy.minimumCharactersFor(3000);
    final stack = await create(
        type: ResourceType.worldview,
        target: 20000,
        parts: [(id: 'p0', estimated: 3000, contract: narrative(minimum))],
        suffix: 'world_t20000');
    final body = '# 标题\n角色😀 **markdown** 한국어 日本語 English'
        '${'\n行尾不可丢失' * 200}';
    // Trimmed length must reach the dynamic minimum (verified by the coordinator).
    final generator = coordinator(stack.tasks, r01Completer(body));
    expect(
        await generator.generateAllParts(
            blueprintId: stack.blueprint.blueprintId, maxRetriesPerPart: 0),
        isTrue);
    final task =
        (await stack.tasks.findTasksForResource(stack.id.value)).single;
    final saved =
        (await stack.tasks.getPartsContent([task.partId]))[task.partId]!
            .content;
    expect(saved, body, reason: '长正文/Unicode/Markdown/无末尾换行必须逐字保存');
    expect(saved.length, body.length);
  });

  test('NPC: a legal short scalar coexists with a narrative part', () async {
    final stack = await create(
        type: ResourceType.npc,
        target: 1000,
        parts: [
          (id: 'label', estimated: 10, contract: scalar()),
          (id: 'bio', estimated: 300, contract: narrative(200)),
        ],
        suffix: 'npc_mixed');
    final generator = coordinator(stack.tasks, r01Completer('导师'));
    expect(
        await generator.generateAllParts(
            blueprintId: stack.blueprint.blueprintId, maxRetriesPerPart: 0),
        isFalse,
        reason: 'narrative 段仍受动态最低约束，短正文不应让整个 run 静默通过');
    final tasks = await stack.tasks.findTasksForResource(stack.id.value);
    final byPart = {for (final t in tasks) t.partId.split('_').last: t.status};
    expect(byPart['label'], 'completed', reason: '合法短 Scalar 段必须完成');
    expect(byPart['bio'], 'failed', reason: 'narrative 段收到过短正文必须失败');
    final contents =
        await stack.tasks.getPartsContent(tasks.map((t) => t.partId).toList());
    final labelId = tasks.firstWhere((t) => t.partId.endsWith('_label')).partId;
    expect(contents[labelId]!.content, '导师');
  });

  test('legacy contract-less resource is unaffected and still opens', () async {
    final stack = await create(
        type: ResourceType.character,
        target: 5000,
        parts: [(id: 'p0', estimated: 500, contract: null)],
        suffix: 'legacy_open');
    // Contract stays null; the tree is readable; assembly preparation runs.
    final reopened = await ResourceBlueprintRepositoryImpl(
            getDb: () async => fixture.db,
            treeRepository: fixture.treeRepository)
        .findBlueprint(stack.blueprint.blueprintId);
    expect(reopened!.allParts.single.contentRequirements, isNull);
    final tree = await fixture.treeRepository.readTree(stack.id);
    expect(tree, isNotNull);
    final readiness = await fixture.coordinator.prepare(stack.id);
    expect(readiness.record.state, isNotNull);
  });
}
