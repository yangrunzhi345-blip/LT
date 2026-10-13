import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/blueprint_budget_normalizer.dart';
import 'package:lt_dialogue/application/resources/blueprint_validator.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/content_requirements.dart';
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
    for (final target in [10000, 12000]) {
      test(
          'should reject an oversized Part even when the total fits target $target',
          () {
        final source = blueprintWithLengths([10000]);
        expect(
            () => BlueprintBudgetNormalizer.normalizeToGenerationTarget(source,
                targetCharacters: target),
            throwsA(isA<BlueprintValidationException>()));
        expect(
            () =>
                BlueprintValidator.validate(source, maxBudgetOverride: target),
            throwsA(isA<BlueprintValidationException>()));
        expect(source.allParts.single.estimatedLength, 10000);
      });
    }
    test(
        'should legally normalize an oversized proposal when the final Part fits',
        () {
      final source = blueprintWithLengths([10000, 2000]);
      final result = BlueprintBudgetNormalizer.normalizeToGenerationTarget(
          source,
          targetCharacters: 5000);
      expect(result.allParts.map((part) => part.estimatedLength),
          everyElement(lessThanOrEqualTo(3000)));
      expect(result.totalEstimatedLength, 5000);
      expect(result.allParts.map((part) => part.id),
          source.allParts.map((part) => part.id));
      expect(
          result.allParts.last.dependencies, source.allParts.last.dependencies);
      expect(() => BlueprintValidator.validate(result, maxBudgetOverride: 5000),
          returnsNormally);
    });
    test(
        'should preserve confirmed per-Part minima when reducing planning metadata',
        () {
      final requirements = ContentRequirements(
          kind: PartContentKind.narrative,
          minimumCharacters: 180,
          validationProfile: PartValidationProfile.narrativeSectionsV1);
      final source = blueprintWithLengths([500, 500]);
      final typed = source.copyWith(sections: [
        source.sections.single.copyWith(
            parts: source.allParts
                .map((part) => part.copyWith(contentRequirements: requirements))
                .toList())
      ]);
      final result = BlueprintBudgetNormalizer.normalizeToGenerationTarget(
          typed,
          targetCharacters: 360);
      expect(result.allParts.map((part) => part.estimatedLength), [180, 180]);
      expect(result.allParts.map((part) => part.contentRequirements),
          everyElement(requirements));
      expect(
          () => BlueprintBudgetNormalizer.normalizeToGenerationTarget(typed,
              targetCharacters: 359),
          throwsA(isA<BlueprintBudgetExceededException>()));
      final unequal = typed.copyWith(sections: [
        typed.sections.single.copyWith(parts: [
          typed.allParts.first.copyWith(estimatedLength: 200),
          typed.allParts.last.copyWith(estimatedLength: 800),
        ])
      ]);
      final bounded = BlueprintBudgetNormalizer.normalizeToGenerationTarget(
          unequal,
          targetCharacters: 400);
      expect(bounded.allParts.first.estimatedLength, greaterThanOrEqualTo(180));
      expect(bounded.totalEstimatedLength, 400);
    });
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
