import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/domain/resources/content_requirements.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_protocol.dart';

import '../../helpers/phase10_fixture.dart';
import '../../helpers/r01_streaming_fixture.dart';

void main() {
  group('ContentRequirements SQLite compatibility', () {
    final fixture = Phase10Fixture();
    late R01StreamingFixture stack;
    setUp(() async {
      await fixture.setUp(prefix: 'lt_content_contract_');
      stack = R01StreamingFixture();
    });
    tearDown(fixture.tearDown);

    test(
        'should persist the confirmed contract and dependencies across repository recreation',
        () async {
      final creation = await stack.pipeline.create(ResourceCreationRequest(
        resourceType: ResourceType.character,
        method: CreationMethod.aiReference,
        name: '契约角色',
        idempotencyKey: 'contract_roundtrip',
        referenceSource: ReferenceSource.text('测试角色'),
        targetCharacters: 1000,
      ));
      final requirements = ContentRequirements(
        kind: PartContentKind.narrative,
        minimumCharacters: 180,
        validationProfile: PartValidationProfile.narrativeSectionsV1,
        requiredHeadings: ['经历', '动机'],
      );
      final blueprint = ResourceBlueprint(
        blueprintId: 'bp_contract_sqlite',
        sessionId: creation.sessionId!,
        resourceType: ResourceType.character,
        suggestedName: '契约角色',
        summary: '',
        targetCapacity: 1000,
        sections: [
          BlueprintSection(id: 'sec_1', title: '人物', parts: [
            for (var index = 0; index < 2; index++)
              BlueprintPart(
                  id: 'part_$index',
                  sectionId: 'sec_1',
                  title: '人物$index',
                  generationGoal: '人物经历与动机',
                  estimatedLength: 450,
                  dependencies: index == 0 ? [] : ['part_0'],
                  contentRequirements: requirements),
          ])
        ],
      );
      await stack.blueprintRepository.saveBlueprint(blueprint);
      final confirmation = await stack.blueprintRepository
          .confirmBlueprint(blueprintId: blueprint.blueprintId);
      final reconstructed = ResourceBlueprintRepositoryImpl(
          getDb: () async => fixture.db,
          treeRepository: fixture.treeRepository);
      final stored = await reconstructed.findBlueprint(blueprint.blueprintId);
      expect(stored, confirmation.blueprint);
      expect(stored!.allParts.map((part) => part.contentRequirements),
          everyElement(requirements));
      final tasks =
          await reconstructed.findGenerationTasks(blueprint.blueprintId);
      expect(tasks.last.dependencies, [tasks.first.partId]);
      final before = await fixture.db.query('resource_blueprints');
      final duplicate = await reconstructed.confirmBlueprint(
          blueprintId: blueprint.blueprintId);
      expect(duplicate.reusedExisting, isTrue);
      expect(await fixture.db.query('resource_blueprints'), before);
    });

    for (final legacyBody in ['荒', '导师']) {
      test(
          'should preserve completed legacy $legacyBody and its hash, attempts and revisions',
          () async {
        final setup = await stack.createOnePartResource(
            suffix: 'legacy_${legacyBody.length}');
        final task =
            (await stack.taskRepository.findReadyTasks(setup.resourceId.value))
                .single;
        final attempt = await stack.taskRepository
            .startAttempt(taskId: task.taskId, generationId: 'legacy_run');
        await stack.taskRepository.commitPartContent(
          response: PartGenerationResponse(
              protocolVersion: 1,
              generationId: 'legacy_run',
              resourceId: setup.resourceId,
              sectionId: setup.sectionId,
              partId: setup.partId,
              attemptId: attempt.attemptId,
              content: legacyBody),
          taskId: task.taskId,
          attemptId: attempt.attemptId,
          expectedSourceToken: attempt.sourceToken,
        );
        const tables = [
          'resource_parts',
          'resource_sections',
          'resources',
          'resource_generation_tasks',
          'resource_generation_attempts',
          'resource_revisions'
        ];
        final before = {
          for (final table in tables) table: await fixture.db.query(table)
        };
        final reconstructed = ResourceBlueprintRepositoryImpl(
            getDb: () async => fixture.db,
            treeRepository: fixture.treeRepository);
        final stored = await reconstructed.findBlueprint(setup.blueprintId);
        expect(stored!.allParts.single.contentRequirements, isNull);
        expect(
            PartContentRequirementsValidator.validate(
                legacyBody, stored.allParts.single.contentRequirements),
            PartContentReview.needsContentReview);
        expect((await stack.taskRepository.findTask(task.taskId))!.status,
            'completed');
        for (final table in tables) {
          expect(await fixture.db.query(table), before[table],
              reason: '$table must remain unchanged');
        }
      });
    }
  });
}
