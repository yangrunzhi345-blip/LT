import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/blueprint_planner.dart';
import 'package:lt_dialogue/application/resources/blueprint_validator.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_limits.dart';

import '../../helpers/phase10_fixture.dart';
import '../../helpers/r01_streaming_fixture.dart';

void main() {
  group('Blueprint Part budget production SQLite paths', () {
    final fixture = Phase10Fixture();
    late R01StreamingFixture stack;
    setUp(() async {
      await fixture.setUp(prefix: 'lt_part_plan_budget_');
      stack = R01StreamingFixture();
    });
    tearDown(fixture.tearDown);

    const protectedTables = [
      'resources',
      'resource_sections',
      'resource_parts',
      'resource_creation_sessions',
      'resource_blueprints',
      'resource_generation_tasks',
      'resource_generation_attempts',
      'resource_revisions'
    ];
    Future<Map<String, Object?>> snapshot() async => {
          for (final table in protectedTables)
            table: await fixture.db.query(table),
        };
    Future<String> createSession(
        String key, ResourceType type, int target) async {
      final creation = await stack.pipeline.create(ResourceCreationRequest(
          resourceType: type,
          method: CreationMethod.aiReference,
          name: '规划预算资源',
          referenceSource: ReferenceSource.text('规划预算测试'),
          targetCharacters: target,
          idempotencyKey: key));
      return creation.sessionId!;
    }

    ResourceBlueprint plan(
            String sessionId, ResourceType type, List<int> lengths) =>
        ResourceBlueprint(
          blueprintId: 'bp_${sessionId}_manual',
          sessionId: sessionId,
          resourceType: type,
          suggestedName: '规划预算资源',
          summary: '',
          targetCapacity: lengths.fold<int>(0, (a, b) => a + b),
          sections: [
            BlueprintSection(id: 'sec_1', title: '人物', parts: [
              for (var index = 0; index < lengths.length; index++)
                BlueprintPart(
                    id: 'part_${index + 1}',
                    sectionId: 'sec_1',
                    title: '部分${index + 1}',
                    generationGoal: '有效生成目标',
                    estimatedLength: lengths[index],
                    sortOrder: index,
                    dependencies: index == 0 ? [] : ['part_$index']),
            ])
          ],
        );
    BlueprintPlanner planner(List<int> lengths) => BlueprintPlanner(
          pipeline: stack.pipeline,
          blueprintRepository: stack.blueprintRepository,
          completer: (
              {required systemPrompt,
              required instruction,
              required task,
              taskHandle}) async {
            final blueprint =
                plan('wire_only', ResourceType.character, lengths);
            return jsonEncode({
              'suggestedName': blueprint.suggestedName,
              'summary': '',
              'sections': [
                for (final section in blueprint.sections)
                  {
                    'id': section.id,
                    'title': section.title,
                    'parts': [
                      for (final part in section.parts)
                        {
                          'id': part.id,
                          'sectionId': part.sectionId,
                          'title': part.title,
                          'generationGoal': part.generationGoal,
                          'estimatedLength': part.estimatedLength,
                          'dependencies': part.dependencies,
                        }
                    ],
                  }
              ],
            });
          },
        );

    for (final type in [ResourceType.character, ResourceType.worldview]) {
      test(
          'should reject an under-target oversized model Part before saving a $type plan',
          () async {
        final sessionId = await createSession('initial', type, 12000);
        final before = await snapshot();
        await expectLater(planner([10000]).plan(sessionId: sessionId),
            throwsA(isA<BlueprintValidationException>()));
        expect(await snapshot(), before);
      });
      test(
          'should preserve previous draft, IDs and revisions after invalid $type replan',
          () async {
        final sessionId = await createSession('replan', type, 12000);
        final previous = await planner([500, 500]).plan(sessionId: sessionId);
        final before = await snapshot();
        await expectLater(
            planner([10000]).replan(sessionId: sessionId, userFeedback: '重新规划'),
            throwsA(isA<BlueprintValidationException>()));
        expect(await snapshot(), before);
        expect(await stack.blueprintRepository.findLatestBlueprint(sessionId),
            previous);
      });
      test(
          'should reject direct confirmation of an exactly-on-target oversized $type draft atomically',
          () async {
        final sessionId = await createSession('direct', type, 10000);
        final draft = plan(sessionId, type, [10000]);
        await stack.blueprintRepository.saveBlueprint(draft);
        final before = await snapshot();
        await expectLater(
            stack.blueprintRepository
                .confirmBlueprint(blueprintId: draft.blueprintId),
            throwsA(isA<BlueprintValidationException>()));
        expect(await snapshot(), before);
        expect(
            (await stack.blueprintRepository.findBlueprint(draft.blueprintId))!
                .status,
            BlueprintStatus.draft);
      });
      test(
          'should confirm legally normalized $type plans with the original authorized DAG',
          () async {
        final sessionId = await createSession('normalize', type, 5000);
        final normalized =
            await planner([10000, 2000]).plan(sessionId: sessionId);
        expect(normalized.totalEstimatedLength, 5000);
        expect(normalized.allParts.map((part) => part.estimatedLength),
            everyElement(lessThanOrEqualTo(ResourceLimits.maxPartCharacters)));
        final result = await stack.blueprintRepository
            .confirmBlueprint(blueprintId: normalized.blueprintId);
        final tasks = await stack.blueprintRepository
            .findGenerationTasks(normalized.blueprintId);
        expect(tasks.map((task) => task.partId), [
          '${result.resourceId.value}_part_1',
          '${result.resourceId.value}_part_2'
        ]);
        expect(tasks.last.dependencies, [tasks.first.partId]);
        expect(tasks.map((task) => task.estimatedLength),
            normalized.allParts.map((part) => part.estimatedLength));
      });
    }
  });
}
