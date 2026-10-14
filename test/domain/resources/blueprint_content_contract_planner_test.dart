import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/blueprint_content_contract_planner.dart';
import 'package:lt_dialogue/domain/resources/content_requirements.dart';
import 'package:lt_dialogue/domain/resources/narrative_minimum_policy.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';

/// U6-B: the client-authoritative content contract planner. Pure, no SQLite.
void main() {
  ResourceBlueprint blueprintWith(List<BlueprintPart> parts) =>
      ResourceBlueprint(
        blueprintId: 'bp',
        sessionId: 's',
        resourceType: ResourceType.worldview,
        suggestedName: '资源',
        summary: '',
        targetCapacity: 10000,
        sections: [BlueprintSection(id: 'sec', title: '章节', parts: parts)],
      );

  BlueprintPart part(String id, int estimated,
          {ContentRequirements? contract}) =>
      BlueprintPart(
        id: id,
        sectionId: 'sec',
        title: '段落 $id',
        generationGoal: '目标',
        estimatedLength: estimated,
        contentRequirements: contract,
      );

  group('narrative dynamic minimum (approved U6-A policy)', () {
    for (final entry
        in const {100: 50, 450: 200, 1000: 400, 3000: 1000}.entries) {
      test('p=${entry.key} → narrative m=${entry.value}', () {
        final result = BlueprintContentContractPlanner.apply(
            blueprintWith([part('p', entry.key)]));
        expect(result.isComplete, isTrue);
        final contract = result.blueprint.allParts.single.contentRequirements!;
        expect(contract.kind, PartContentKind.narrative);
        expect(contract.validationProfile,
            PartValidationProfile.narrativeSectionsV1);
        expect(contract.minimumCharacters, entry.value);
        expect(contract.required, isTrue, reason: '新契约默认必填');
        expect(contract.requiredHeadings, isEmpty, reason: '默认自由叙述');
      });
    }
  });

  group('planning floor', () {
    test('p=79 is a gap and receives no contract', () {
      final result =
          BlueprintContentContractPlanner.apply(blueprintWith([part('p', 79)]));
      expect(result.isComplete, isFalse);
      expect(result.gaps.single.partId, 'p');
      expect(result.gaps.single.reason,
          BlueprintContractGapReason.plannedLengthBelowMinimum);
      expect(result.blueprint.allParts.single.contentRequirements, isNull);
    });

    test('p=80 is feasible (minimum 40)', () {
      final result =
          BlueprintContentContractPlanner.apply(blueprintWith([part('p', 80)]));
      expect(result.isComplete, isTrue);
      expect(
          result
              .blueprint.allParts.single.contentRequirements!.minimumCharacters,
          40);
    });
  });

  group('scalar and structured specs', () {
    test('an explicit scalar spec yields minimum 1', () {
      final result = BlueprintContentContractPlanner.apply(
        blueprintWith([part('p', 500)]),
        specs: {'p': const PartContentSpec(kind: PartContentKind.scalar)},
      );
      final contract = result.blueprint.allParts.single.contentRequirements!;
      expect(contract.kind, PartContentKind.scalar);
      expect(contract.validationProfile, PartValidationProfile.scalarTextV1);
      expect(contract.minimumCharacters, 1);
    });

    test('structured without client fields is a gap', () {
      final result = BlueprintContentContractPlanner.apply(
        blueprintWith([part('p', 500)]),
        specs: {'p': const PartContentSpec(kind: PartContentKind.structured)},
      );
      expect(result.isComplete, isFalse);
      expect(result.gaps.single.reason,
          BlueprintContractGapReason.structuredFieldsUnconfirmed);
      expect(result.blueprint.allParts.single.contentRequirements, isNull);
    });

    test('structured with client fields yields a V1 object contract', () {
      final result = BlueprintContentContractPlanner.apply(
        blueprintWith([part('p', 500)]),
        specs: {
          'p': const PartContentSpec(
              kind: PartContentKind.structured,
              requiredFields: ['name', 'role']),
        },
      );
      final contract = result.blueprint.allParts.single.contentRequirements!;
      expect(contract.kind, PartContentKind.structured);
      expect(
          contract.validationProfile, PartValidationProfile.structuredObjectV1);
      expect(contract.requiredFields, ['name', 'role']);
    });

    test('an explicit spec carries required=false and sectioned headings', () {
      final result = BlueprintContentContractPlanner.apply(
        blueprintWith([part('p', 1000)]),
        specs: {
          'p': const PartContentSpec(
              required: false, requiredHeadings: ['开端', '发展']),
        },
      );
      final contract = result.blueprint.allParts.single.contentRequirements!;
      expect(contract.required, isFalse);
      expect(contract.requiredHeadings, ['开端', '发展']);
    });
  });

  group('the model cannot lower a requirement', () {
    test('a model-supplied narrative minimum=1 is replaced by the policy', () {
      final smuggled = ContentRequirements(
        kind: PartContentKind.narrative,
        minimumCharacters: 1,
        validationProfile: PartValidationProfile.narrativeSectionsV1,
      );
      final result = BlueprintContentContractPlanner.apply(
          blueprintWith([part('p', 3000, contract: smuggled)]));
      final contract = result.blueprint.allParts.single.contentRequirements!;
      expect(contract.minimumCharacters,
          NarrativeMinimumPolicy.minimumCharactersFor(3000));
      expect(contract.minimumCharacters, 1000,
          reason: '模型伪造的 minimum=1 必须被客户端覆盖');
    });

    test(
        'a model-supplied structured contract without client fields is cleared',
        () {
      final smuggled = ContentRequirements(
        kind: PartContentKind.structured,
        minimumCharacters: 1,
        validationProfile: PartValidationProfile.structuredObjectV1,
        requiredFields: const ['invented'],
      );
      // No trusted spec: the part defaults to narrative, so the smuggled
      // structured contract is fully replaced.
      final result = BlueprintContentContractPlanner.apply(
          blueprintWith([part('p', 3000, contract: smuggled)]));
      final contract = result.blueprint.allParts.single.contentRequirements!;
      expect(contract.kind, PartContentKind.narrative);
      expect(contract.minimumCharacters, 1000);
    });
  });

  test('the result blueprint preserves ids, lengths and inner order', () {
    final result = BlueprintContentContractPlanner.apply(blueprintWith([
      part('a', 100),
      part('b', 450),
    ]));
    final parts = result.blueprint.allParts;
    expect(parts.map((p) => p.id), ['a', 'b']);
    expect(parts.map((p) => p.estimatedLength), [100, 450]);
    expect(
        parts.map((p) => p.contentRequirements!.minimumCharacters), [50, 200]);
  });

  test('the result is stamped with the contract-enforcement version', () {
    final result =
        BlueprintContentContractPlanner.apply(blueprintWith([part('a', 100)]));
    expect(result.blueprint.contentContractVersion,
        BlueprintContentContractPlanner.contentContractVersion);
    expect(result.blueprint.contentContractVersion, 1);
  });
}
