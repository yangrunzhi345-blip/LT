import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/blueprint_budget_normalizer.dart';
import 'package:lt_dialogue/application/resources/blueprint_validator.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_limits.dart';

void main() {
  ResourceBlueprint blueprintWithLengths(List<int> lengths) =>
      ResourceBlueprint(
        blueprintId: 'bp_budget',
        sessionId: 'session_budget',
        resourceType: ResourceType.worldview,
        suggestedName: '预算测试世界观',
        summary: '验证 Blueprint 元数据预算协调。',
        sections: [
          BlueprintSection(
            id: 'sec_1',
            title: '唯一章节',
            parts: [
              for (var index = 0; index < lengths.length; index++)
                BlueprintPart(
                  id: 'part_${index + 1}',
                  sectionId: 'sec_1',
                  title: 'Part ${index + 1}',
                  generationGoal: '生成第 ${index + 1} 部分的内容',
                  estimatedLength: lengths[index],
                  dependencies: index == 0 ? const [] : ['part_$index'],
                  sortOrder: index,
                ),
            ],
          ),
        ],
      );

  group('BlueprintBudgetNormalizer', () {
    test('should normalize 23900 into the 23000 generation target', () {
      final normalized = BlueprintBudgetNormalizer.normalizeToGenerationTarget(
        blueprintWithLengths(
            const [3000, 3000, 3000, 3000, 3000, 3000, 3000, 2900]),
        targetCharacters: 23000,
      );

      expect(normalized.totalEstimatedLength, 23000);
      for (final part in normalized.allParts) {
        expect(part.estimatedLength,
            greaterThanOrEqualTo(BlueprintValidator.minPartEstimatedLength));
        expect(part.estimatedLength,
            lessThanOrEqualTo(ResourceLimits.maxPartCharacters));
      }
      BlueprintValidator.validate(normalized, maxBudgetOverride: 23000);
    });

    test('should preserve an exactly-on-target blueprint unchanged', () {
      final source = blueprintWithLengths(
          const [3000, 3000, 3000, 3000, 3000, 3000, 3000, 2000]);
      final normalized = BlueprintBudgetNormalizer.normalizeToGenerationTarget(
        source,
        targetCharacters: 23000,
      );

      expect(normalized, same(source));
    });

    test(
        'should deterministically distribute rounding without exceeding target',
        () {
      final source = blueprintWithLengths(
          const [3000, 2999, 2998, 2997, 2996, 2995, 2994, 2993, 2992]);
      final first = BlueprintBudgetNormalizer.normalizeToGenerationTarget(
        source,
        targetCharacters: 23000,
      );
      final second = BlueprintBudgetNormalizer.normalizeToGenerationTarget(
        source,
        targetCharacters: 23000,
      );

      expect(first.totalEstimatedLength, lessThanOrEqualTo(23000));
      expect(first.allParts.map((part) => part.estimatedLength),
          second.allParts.map((part) => part.estimatedLength));
    });

    test(
        'should enforce Part min/max bounds and fail when the target cannot fit minima',
        () {
      final normalized = BlueprintBudgetNormalizer.normalizeToGenerationTarget(
        blueprintWithLengths(const [3000, 10]),
        targetCharacters: 20,
      );
      expect(normalized.allParts.map((part) => part.estimatedLength), [10, 10]);

      expect(
        () => BlueprintBudgetNormalizer.normalizeToGenerationTarget(
          blueprintWithLengths(const [3000, 10]),
          targetCharacters: 19,
        ),
        throwsA(isA<BlueprintBudgetExceededException>()),
      );
    });

    test('should not change worldview nominal or absolute capacity semantics',
        () {
      final policy = ResourceLimits.policyFor(ResourceType.worldview);
      expect(policy.nominalCharacters, 50000);
      expect(policy.absoluteCharacters, 60000);
      expect(policy.statusFor(50000), CapacityStatus.normal);
      expect(policy.statusFor(60000), CapacityStatus.elastic);
    });
  });
}
