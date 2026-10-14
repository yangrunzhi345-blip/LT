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

/// U6-C: the confirmed [ContentRequirements] really control production prose
/// through the full chain (Request → Parser → Validator → Commit → SQLite).
/// Real SQLite + real coordinator; only the model is a deterministic fake.
void main() {
  final fixture = Phase10Fixture();
  setUp(() => fixture.setUp(prefix: 'lt_u6c_'));
  tearDown(fixture.tearDown);

  Future<
      ({
        ResourceId id,
        ResourceBlueprint blueprint,
        PartGenerationTaskRepositoryImpl tasks
      })> create({
    required ContentRequirements? requirements,
    required int estimated,
    required int target,
    required String suffix,
  }) async {
    final pipeline = ResourceCreationPipeline(
        getDb: () async => fixture.db,
        treeRepository: fixture.treeRepository,
        hasAiCredentials: () => true);
    final session = await pipeline.create(ResourceCreationRequest(
        resourceType: ResourceType.character,
        method: CreationMethod.aiReference,
        name: 'U6C $suffix',
        referenceSource: ReferenceSource.text('参考'),
        targetCharacters: target,
        idempotencyKey: 'u6c_$suffix'));
    final blueprint = ResourceBlueprint(
        blueprintId: 'u6c_$suffix',
        sessionId: session.sessionId!,
        resourceType: ResourceType.character,
        suggestedName: 'U6C $suffix',
        summary: '',
        targetCapacity: target,
        sections: [
          BlueprintSection(id: 's', title: '背景', parts: [
            BlueprintPart(
                id: 'p0',
                sectionId: 's',
                title: '背景',
                generationGoal: '角色背景',
                estimatedLength: estimated,
                contentRequirements: requirements),
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

  /// Runs one part to completion attempt; returns (ok, taskStatus, content).
  Future<({bool ok, String status, String content})> run({
    required ContentRequirements? requirements,
    required int estimated,
    required int target,
    required String body,
    required String suffix,
  }) async {
    final stack = await create(
        requirements: requirements,
        estimated: estimated,
        target: target,
        suffix: suffix);
    final generator = coordinator(stack.tasks, r01Completer(body));
    final ok = await generator.generateAllParts(
        blueprintId: stack.blueprint.blueprintId, maxRetriesPerPart: 0);
    final task =
        (await stack.tasks.findTasksForResource(stack.id.value)).single;
    final content =
        (await stack.tasks.getPartsContent([task.partId]))[task.partId]!
            .content;
    return (ok: ok, status: task.status, content: content);
  }

  ContentRequirements narrative(
          {required int minimum, List<String> headings = const []}) =>
      ContentRequirements(
          kind: PartContentKind.narrative,
          minimumCharacters: minimum,
          validationProfile: PartValidationProfile.narrativeSectionsV1,
          requiredHeadings: headings);

  group('§5.1 narrative dynamic minimum (real chain)', () {
    for (final entry
        in const {100: 50, 450: 200, 1000: 400, 3000: 1000}.entries) {
      final planned = entry.key;
      final minimum = entry.value;
      final target = planned < 1000 ? 1000 : planned;

      test('p=$planned (m=$minimum): a 1-char body is rejected', () async {
        final result = await run(
            requirements: narrative(minimum: minimum),
            estimated: planned,
            target: target,
            body: '荒',
            suffix: 'n${planned}_short');
        expect(result.ok, isFalse);
        expect(result.status, 'failed');
        expect(result.content, isEmpty, reason: '无效正文不得写入');
      });

      test('p=$planned (m=$minimum): a minimum-length free narrative completes',
          () async {
        final result = await run(
            requirements: narrative(minimum: minimum),
            estimated: planned,
            target: target,
            body: '文' * minimum,
            suffix: 'n${planned}_ok');
        expect(result.ok, isTrue);
        expect(result.status, 'completed');
        expect(result.content.length, minimum);
      });
    }

    test('free narrative does not require markdown headings', () async {
      final result = await run(
          requirements: narrative(minimum: 200),
          estimated: 450,
          target: 1000,
          body: '这是一段没有任何小标题的连续叙述文本。' * 20,
          suffix: 'free');
      expect(result.ok, isTrue, reason: '自由叙述不应因缺少标题被拒绝');
    });

    test('sectioned narrative requires a real, populated heading', () async {
      final missing = await run(
          requirements: narrative(minimum: 10, headings: ['开端', '发展']),
          estimated: 300,
          target: 1000,
          body: '# 开端\n${'很久以前。' * 30}',
          suffix: 'sec_missing');
      expect(missing.ok, isFalse, reason: '缺少必填小节必须拒绝');

      final present = await run(
          requirements: narrative(minimum: 10, headings: ['开端', '发展']),
          estimated: 300,
          target: 1000,
          body: '# 开端\n${'很久以前。' * 10}\n# 发展\n${'后来。' * 10}',
          suffix: 'sec_present');
      expect(present.ok, isTrue);
    });

    test('a pseudo-heading inside a fenced code block does not count',
        () async {
      final result = await run(
          requirements: narrative(minimum: 10, headings: ['开端']),
          estimated: 300,
          target: 1000,
          body: '```\n# 开端\n```\n${'正文内容。' * 20}',
          suffix: 'fence');
      expect(result.ok, isFalse, reason: '代码块内的伪标题不能满足必填小节');
    });
  });

  group('§5.2 scalar legal short fields (real chain)', () {
    ContentRequirements scalar() => ContentRequirements(
        kind: PartContentKind.scalar,
        minimumCharacters: 1,
        validationProfile: PartValidationProfile.scalarTextV1);

    for (final value in const ['师', '导师']) {
      test('a legal short scalar "$value" completes', () async {
        final result = await run(
            requirements: scalar(),
            estimated: 10,
            target: 1000,
            body: value,
            suffix: 'scalar_${value.codeUnitAt(0)}');
        expect(result.ok, isTrue);
        expect(result.content, value);
      });
    }

    test('a multi-line scalar is rejected', () async {
      final result = await run(
          requirements: scalar(),
          estimated: 10,
          target: 1000,
          body: '导师\n其他',
          suffix: 'scalar_multi');
      expect(result.ok, isFalse);
    });

    test('a whitespace-only scalar is rejected', () async {
      final result = await run(
          requirements: scalar(),
          estimated: 10,
          target: 1000,
          body: '   ',
          suffix: 'scalar_blank');
      expect(result.ok, isFalse);
    });
  });

  group('§5.3 structured top-level fields (real chain)', () {
    ContentRequirements structured(List<String> fields) => ContentRequirements(
        kind: PartContentKind.structured,
        minimumCharacters: 1,
        validationProfile: PartValidationProfile.structuredObjectV1,
        requiredFields: fields);

    test('a valid object completes', () async {
      final result = await run(
          requirements: structured(['name', 'role']),
          estimated: 50,
          target: 1000,
          body: '{"name":"林恩","role":"法师"}',
          suffix: 'st_ok');
      expect(result.ok, isTrue);
    });

    test('illegal JSON is rejected', () async {
      final result = await run(
          requirements: structured(['name']),
          estimated: 50,
          target: 1000,
          body: '{not json',
          suffix: 'st_badjson');
      expect(result.ok, isFalse);
    });

    test('a missing required top-level field is rejected', () async {
      final result = await run(
          requirements: structured(['name', 'role']),
          estimated: 50,
          target: 1000,
          body: '{"name":"林恩"}',
          suffix: 'st_missing');
      expect(result.ok, isFalse);
    });

    test('an empty required string is rejected', () async {
      final result = await run(
          requirements: structured(['name']),
          estimated: 50,
          target: 1000,
          body: '{"name":"   "}',
          suffix: 'st_empty');
      expect(result.ok, isFalse);
    });

    for (final json in const ['{"enabled":false}', '{"count":0}']) {
      test('legal false/0 required values are accepted: $json', () async {
        final field = json.contains('enabled') ? 'enabled' : 'count';
        final result = await run(
            requirements: structured([field]),
            estimated: 50,
            target: 1000,
            body: json,
            suffix: 'st_$field');
        expect(result.ok, isTrue, reason: '合法的 false / 0 不得被当作空值拒绝');
      });
    }
  });

  group('§5.1 the minimum is a floor, not an exact target', () {
    test('a body longer than the minimum (within K) is accepted', () async {
      final minimum = NarrativeMinimumPolicy.minimumCharactersFor(1000);
      final result = await run(
          requirements: narrative(minimum: minimum),
          estimated: 1000,
          target: 3000,
          body: '文' * 2500,
          suffix: 'floor');
      expect(result.ok, isTrue,
          reason: '超出 minimum 但仍在授权上限内应接受，minimum 不是精确目标');
      expect(result.content.length, 2500);
    });
  });
}
