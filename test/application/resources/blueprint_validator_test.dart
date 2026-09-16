import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/blueprint_validator.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_limits.dart';

void main() {
  group('BlueprintValidator', () {
    late BlueprintIdPool defaultPool;

    setUp(() {
      defaultPool = BlueprintIdPool.createDefault(maxSections: 5, maxParts: 10);
    });

    ResourceBlueprint createValidBlueprint({
      ResourceType type = ResourceType.worldview,
      int totalLength = 1200,
    }) {
      return ResourceBlueprint(
        blueprintId: 'bp_test_1',
        sessionId: 'cre_test_1',
        resourceType: type,
        suggestedName: '新世界观',
        summary: '这是一个宏大的奇幻世界规划',
        sections: [
          BlueprintSection(
            id: 'sec_1',
            title: '世界地理与环境',
            summary: '介绍地理风貌',
            sortOrder: 0,
            parts: [
              BlueprintPart(
                id: 'part_1',
                sectionId: 'sec_1',
                title: '大陆板块概览',
                generationGoal: '描写大陆主要地形与三大陆块划分',
                estimatedLength: totalLength ~/ 2,
                sortOrder: 0,
              ),
              BlueprintPart(
                id: 'part_2',
                sectionId: 'sec_1',
                title: '气候与生态带',
                generationGoal: '描写极端气候带与灵气流动特征',
                estimatedLength: totalLength ~/ 2,
                dependencies: ['part_1'],
                sortOrder: 1,
              ),
            ],
          ),
        ],
      );
    }

    test('accepts valid blueprint with authorized ID pool', () {
      final bp = createValidBlueprint();
      expect(() => BlueprintValidator.validate(bp, idPool: defaultPool),
          returnsNormally);
    });

    group('ID Security & Pool Validation', () {
      test('rejects unauthorized Section ID', () {
        final bp = ResourceBlueprint(
          blueprintId: 'bp_1',
          sessionId: 'cre_1',
          resourceType: ResourceType.worldview,
          suggestedName: '测试',
          summary: '摘要',
          sections: [
            BlueprintSection(
              id: 'sec_unknown_999',
              title: '未知章节',
              parts: [
                const BlueprintPart(
                  id: 'part_1',
                  sectionId: 'sec_unknown_999',
                  title: '小节1',
                  generationGoal: '目标',
                  estimatedLength: 200,
                ),
              ],
            ),
          ],
        );

        expect(
          () => BlueprintValidator.validate(bp, idPool: defaultPool),
          throwsA(isA<BlueprintIdException>().having(
            (e) => e.message,
            'message',
            contains('未在预分配 ID 许可池中'),
          )),
        );
      });

      test('rejects unauthorized Part ID', () {
        final bp = ResourceBlueprint(
          blueprintId: 'bp_1',
          sessionId: 'cre_1',
          resourceType: ResourceType.worldview,
          suggestedName: '测试',
          summary: '摘要',
          sections: [
            BlueprintSection(
              id: 'sec_1',
              title: '章节1',
              parts: [
                const BlueprintPart(
                  id: 'part_hacked_random_id',
                  sectionId: 'sec_1',
                  title: '小节1',
                  generationGoal: '目标',
                  estimatedLength: 200,
                ),
              ],
            ),
          ],
        );

        expect(
          () => BlueprintValidator.validate(bp, idPool: defaultPool),
          throwsA(isA<BlueprintIdException>().having(
            (e) => e.message,
            'message',
            contains('未在预分配 ID 许可池中'),
          )),
        );
      });

      test('rejects duplicate Section IDs', () {
        final bp = ResourceBlueprint(
          blueprintId: 'bp_1',
          sessionId: 'cre_1',
          resourceType: ResourceType.worldview,
          suggestedName: '测试',
          summary: '摘要',
          sections: [
            BlueprintSection(
              id: 'sec_1',
              title: '章节1',
              parts: [
                const BlueprintPart(
                  id: 'part_1',
                  sectionId: 'sec_1',
                  title: '小节1',
                  generationGoal: '目标',
                  estimatedLength: 200,
                ),
              ],
            ),
            BlueprintSection(
              id: 'sec_1',
              title: '重复的章节1',
              parts: [
                const BlueprintPart(
                  id: 'part_2',
                  sectionId: 'sec_1',
                  title: '小节2',
                  generationGoal: '目标',
                  estimatedLength: 200,
                ),
              ],
            ),
          ],
        );

        expect(
          () => BlueprintValidator.validate(bp),
          throwsA(isA<BlueprintIdException>().having(
            (e) => e.message,
            'message',
            contains('重复的 Section ID'),
          )),
        );
      });

      test('rejects duplicate Part IDs across sections', () {
        final bp = ResourceBlueprint(
          blueprintId: 'bp_1',
          sessionId: 'cre_1',
          resourceType: ResourceType.worldview,
          suggestedName: '测试',
          summary: '摘要',
          sections: [
            BlueprintSection(
              id: 'sec_1',
              title: '章节1',
              parts: [
                const BlueprintPart(
                  id: 'part_1',
                  sectionId: 'sec_1',
                  title: '小节1',
                  generationGoal: '目标',
                  estimatedLength: 200,
                ),
              ],
            ),
            BlueprintSection(
              id: 'sec_2',
              title: '章节2',
              parts: [
                const BlueprintPart(
                  id: 'part_1',
                  sectionId: 'sec_2',
                  title: '重复小节1',
                  generationGoal: '目标',
                  estimatedLength: 200,
                ),
              ],
            ),
          ],
        );

        expect(
          () => BlueprintValidator.validate(bp),
          throwsA(isA<BlueprintIdException>().having(
            (e) => e.message,
            'message',
            contains('重复的 Part ID'),
          )),
        );
      });

      test('rejects part whose sectionId does not match parent section', () {
        final bp = ResourceBlueprint(
          blueprintId: 'bp_1',
          sessionId: 'cre_1',
          resourceType: ResourceType.worldview,
          suggestedName: '测试',
          summary: '摘要',
          sections: [
            BlueprintSection(
              id: 'sec_1',
              title: '章节1',
              parts: [
                const BlueprintPart(
                  id: 'part_1',
                  sectionId: 'sec_different',
                  title: '小节1',
                  generationGoal: '目标',
                  estimatedLength: 200,
                ),
              ],
            ),
          ],
        );

        expect(
          () => BlueprintValidator.validate(bp),
          throwsA(isA<BlueprintIdException>().having(
            (e) => e.message,
            'message',
            contains('不一致'),
          )),
        );
      });

      test('rejects dependency referencing non-existent Part ID', () {
        final bp = ResourceBlueprint(
          blueprintId: 'bp_1',
          sessionId: 'cre_1',
          resourceType: ResourceType.worldview,
          suggestedName: '测试',
          summary: '摘要',
          sections: [
            BlueprintSection(
              id: 'sec_1',
              title: '章节1',
              parts: [
                const BlueprintPart(
                  id: 'part_1',
                  sectionId: 'sec_1',
                  title: '小节1',
                  generationGoal: '目标',
                  estimatedLength: 200,
                  dependencies: ['part_999_not_exist'],
                ),
              ],
            ),
          ],
        );

        expect(
          () => BlueprintValidator.validate(bp),
          throwsA(isA<BlueprintIdException>().having(
            (e) => e.message,
            'message',
            contains('不存在的 Part ID'),
          )),
        );
      });
    });

    group('DAG Validation', () {
      test('rejects self-cycle (A → A)', () {
        final bp = ResourceBlueprint(
          blueprintId: 'bp_1',
          sessionId: 'cre_1',
          resourceType: ResourceType.worldview,
          suggestedName: '测试',
          summary: '摘要',
          sections: [
            BlueprintSection(
              id: 'sec_1',
              title: '章节1',
              parts: [
                const BlueprintPart(
                  id: 'part_1',
                  sectionId: 'sec_1',
                  title: '小节1',
                  generationGoal: '目标',
                  estimatedLength: 200,
                  dependencies: ['part_1'],
                ),
              ],
            ),
          ],
        );

        expect(
          () => BlueprintValidator.validate(bp),
          throwsA(isA<BlueprintDagCycleException>().having(
            (e) => e.message,
            'message',
            contains('自环依赖'),
          )),
        );
      });

      test('rejects 2-node cycle (A → B, B → A)', () {
        final bp = ResourceBlueprint(
          blueprintId: 'bp_1',
          sessionId: 'cre_1',
          resourceType: ResourceType.worldview,
          suggestedName: '测试',
          summary: '摘要',
          sections: [
            BlueprintSection(
              id: 'sec_1',
              title: '章节1',
              parts: [
                const BlueprintPart(
                  id: 'part_1',
                  sectionId: 'sec_1',
                  title: '小节1',
                  generationGoal: '目标',
                  estimatedLength: 200,
                  dependencies: ['part_2'],
                ),
                const BlueprintPart(
                  id: 'part_2',
                  sectionId: 'sec_1',
                  title: '小节2',
                  generationGoal: '目标',
                  estimatedLength: 200,
                  dependencies: ['part_1'],
                ),
              ],
            ),
          ],
        );

        expect(
          () => BlueprintValidator.validate(bp),
          throwsA(isA<BlueprintDagCycleException>().having(
            (e) => e.message,
            'message',
            contains('循环依赖'),
          )),
        );
      });

      test('rejects multi-node cycle (A → B, B → C, C → A)', () {
        final bp = ResourceBlueprint(
          blueprintId: 'bp_1',
          sessionId: 'cre_1',
          resourceType: ResourceType.worldview,
          suggestedName: '测试',
          summary: '摘要',
          sections: [
            BlueprintSection(
              id: 'sec_1',
              title: '章节1',
              parts: [
                const BlueprintPart(
                  id: 'part_1',
                  sectionId: 'sec_1',
                  title: '小节1',
                  generationGoal: '目标',
                  estimatedLength: 200,
                  dependencies: ['part_2'],
                ),
                const BlueprintPart(
                  id: 'part_2',
                  sectionId: 'sec_1',
                  title: '小节2',
                  generationGoal: '目标',
                  estimatedLength: 200,
                  dependencies: ['part_3'],
                ),
                const BlueprintPart(
                  id: 'part_3',
                  sectionId: 'sec_1',
                  title: '小节3',
                  generationGoal: '目标',
                  estimatedLength: 200,
                  dependencies: ['part_1'],
                ),
              ],
            ),
          ],
        );

        expect(
          () => BlueprintValidator.validate(bp),
          throwsA(isA<BlueprintDagCycleException>().having(
            (e) => e.message,
            'message',
            contains('循环依赖'),
          )),
        );
      });
    });

    group('Content Boundary Validation (Prevent Smuggling Prose)', () {
      test('rejects huge text in generationGoal', () {
        final longProse = '这是几千字的正文。' * 100; // ~900 chars
        final bp = ResourceBlueprint(
          blueprintId: 'bp_1',
          sessionId: 'cre_1',
          resourceType: ResourceType.worldview,
          suggestedName: '测试',
          summary: '摘要',
          sections: [
            BlueprintSection(
              id: 'sec_1',
              title: '章节1',
              parts: [
                BlueprintPart(
                  id: 'part_1',
                  sectionId: 'sec_1',
                  title: '小节1',
                  generationGoal: longProse,
                  estimatedLength: 200,
                ),
              ],
            ),
          ],
        );

        expect(
          () => BlueprintValidator.validate(bp),
          throwsA(isA<BlueprintContentBoundaryException>().having(
            (e) => e.field,
            'field',
            equals('parts.generationGoal'),
          )),
        );
      });

      test('rejects huge text in suggestedName', () {
        final bp = ResourceBlueprint(
          blueprintId: 'bp_1',
          sessionId: 'cre_1',
          resourceType: ResourceType.worldview,
          suggestedName: 'A' * 150,
          summary: '摘要',
          sections: [
            BlueprintSection(
              id: 'sec_1',
              title: '章节1',
              parts: [
                const BlueprintPart(
                  id: 'part_1',
                  sectionId: 'sec_1',
                  title: '小节1',
                  generationGoal: '目标',
                  estimatedLength: 200,
                ),
              ],
            ),
          ],
        );

        expect(
          () => BlueprintValidator.validate(bp),
          throwsA(isA<BlueprintContentBoundaryException>().having(
            (e) => e.field,
            'field',
            equals('suggestedName'),
          )),
        );
      });

      test('rejects huge text in summary', () {
        final bp = ResourceBlueprint(
          blueprintId: 'bp_1',
          sessionId: 'cre_1',
          resourceType: ResourceType.worldview,
          suggestedName: '测试',
          summary: 'S' * 1500,
          sections: [
            BlueprintSection(
              id: 'sec_1',
              title: '章节1',
              parts: [
                const BlueprintPart(
                  id: 'part_1',
                  sectionId: 'sec_1',
                  title: '小节1',
                  generationGoal: '目标',
                  estimatedLength: 200,
                ),
              ],
            ),
          ],
        );

        expect(
          () => BlueprintValidator.validate(bp),
          throwsA(isA<BlueprintContentBoundaryException>().having(
            (e) => e.field,
            'field',
            equals('summary'),
          )),
        );
      });
    });

    group('Capacity Budget Validation', () {
      test('rejects worldview blueprint exceeding nominal limit', () {
        final budget =
            ResourceLimits.policyFor(ResourceType.worldview).nominalCharacters;
        final bp = createValidBlueprint(
          type: ResourceType.worldview,
          totalLength: budget + 500,
        );

        expect(
          () => BlueprintValidator.validate(bp),
          throwsA(isA<BlueprintBudgetExceededException>().having(
            (e) => e.plannedLength,
            'plannedLength',
            greaterThan(budget),
          )),
        );
      });

      test('rejects character blueprint exceeding nominal limit', () {
        final budget =
            ResourceLimits.policyFor(ResourceType.character).nominalCharacters;
        final bp = createValidBlueprint(
          type: ResourceType.character,
          totalLength: budget + 200,
        );

        expect(
          () => BlueprintValidator.validate(bp),
          throwsA(isA<BlueprintBudgetExceededException>().having(
            (e) => e.plannedLength,
            'plannedLength',
            greaterThan(budget),
          )),
        );
      });

      test('rejects npc blueprint exceeding nominal limit', () {
        final budget =
            ResourceLimits.policyFor(ResourceType.npc).nominalCharacters;
        final bp = createValidBlueprint(
          type: ResourceType.npc,
          totalLength: budget + 200,
        );

        expect(
          () => BlueprintValidator.validate(bp),
          throwsA(isA<BlueprintBudgetExceededException>().having(
            (e) => e.plannedLength,
            'plannedLength',
            greaterThan(budget),
          )),
        );
      });
    });
  });
}
