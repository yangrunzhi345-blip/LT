import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_limits.dart';

void main() {
  group('GenerationBudgetPolicy.cumulativeCeiling (elastic breakout)', () {
    // C = floor(T*(100+E)/100). The absolute capacity of the resource type is
    // never consulted here: an authorized run may exceed it.
    test('acceptance numbers for every resource type', () {
      // Worldview: T = 50000 at E = 0 / 20 / 50.
      expect(
        GenerationBudgetPolicy.cumulativeCeiling(
            target: 50000, elasticPercent: 0),
        50000,
      );
      expect(
        GenerationBudgetPolicy.cumulativeCeiling(
            target: 50000, elasticPercent: 20),
        60000,
      );
      expect(
        GenerationBudgetPolicy.cumulativeCeiling(
            target: 50000, elasticPercent: 50),
        75000,
        reason: 'worldview 50000 + 50% breaks the old 60000 absolute',
      );

      // Character card and NPC: T = 20000 at E = 0 / 20 / 50.
      for (final target in const [20000, 20000]) {
        expect(
          GenerationBudgetPolicy.cumulativeCeiling(
              target: target, elasticPercent: 0),
          target,
        );
        expect(
          GenerationBudgetPolicy.cumulativeCeiling(
              target: target, elasticPercent: 20),
          24000,
        );
        expect(
          GenerationBudgetPolicy.cumulativeCeiling(
              target: target, elasticPercent: 50),
          30000,
          reason: 'character/NPC 20000 + 50% breaks the old 24000 absolute',
        );
      }
    });

    test('zero target stays budgetless', () {
      expect(
        GenerationBudgetPolicy.cumulativeCeiling(target: 0),
        0,
      );
      expect(
        GenerationBudgetPolicy.cumulativeCeiling(target: 0, elasticPercent: 50),
        0,
      );
    });

    test('negative target is rejected', () {
      expect(
        () => GenerationBudgetPolicy.cumulativeCeiling(target: -1),
        throwsArgumentError,
      );
    });

    test('out-of-range percents fail closed', () {
      for (final bad in const [-1, 51, 100]) {
        expect(
          () => GenerationBudgetPolicy.cumulativeCeiling(
              target: 1000, elasticPercent: bad),
          throwsArgumentError,
          reason: 'E=$bad',
        );
      }
    });

    test('always the default 20% when omitted', () {
      expect(GenerationBudgetPolicy.defaultElasticPercent, 20);
      expect(
        GenerationBudgetPolicy.cumulativeCeiling(target: 8000),
        9600,
      );
    });

    test('pure integer floor never rounds up', () {
      // Non-divisible targets: floor, never round-to-nearest.
      expect(
        GenerationBudgetPolicy.cumulativeCeiling(
            target: 1234, elasticPercent: 35),
        1665, // 1234 * 135 = 166590
      );
      expect(
        GenerationBudgetPolicy.cumulativeCeiling(
            target: 9877, elasticPercent: 15),
        11358, // 9877 * 115 = 1135855
      );
      expect(
        GenerationBudgetPolicy.cumulativeCeiling(
            target: 9999, elasticPercent: 50),
        14998, // 9999 * 150 = 1499850
      );
      expect(
        GenerationBudgetPolicy.cumulativeCeiling(target: 1, elasticPercent: 50),
        1,
      );
    });
  });

  group('GenerationBudgetPolicy.ceilingFor (version dispatch)', () {
    test('the current version ignores the absolute capacity', () {
      expect(
        GenerationBudgetPolicy.ceilingFor(
          target: 50000,
          absolute: ResourceLimits.worldviewAbsoluteCharacters,
          elasticPercent: 50,
          policyVersion: GenerationBudgetPolicy.currentBudgetPolicyVersion,
        ),
        75000,
      );
      expect(
        GenerationBudgetPolicy.ceilingFor(
          target: 20000,
          absolute: ResourceLimits.characterAbsoluteCharacters,
          elasticPercent: 50,
          policyVersion: GenerationBudgetPolicy.currentBudgetPolicyVersion,
        ),
        30000,
      );
    });

    test('the legacy version keeps the historical min(..., A) clip', () {
      expect(
        GenerationBudgetPolicy.ceilingFor(
          target: 50000,
          absolute: ResourceLimits.worldviewAbsoluteCharacters,
          elasticPercent: 50,
          policyVersion: GenerationBudgetPolicy.legacyBudgetPolicyVersion,
        ),
        60000,
        reason: 'a legacy run must not be retroactively widened to 75000',
      );
      expect(
        GenerationBudgetPolicy.ceilingFor(
          target: 20000,
          absolute: ResourceLimits.characterAbsoluteCharacters,
          elasticPercent: 50,
          policyVersion: GenerationBudgetPolicy.legacyBudgetPolicyVersion,
        ),
        24000,
      );
      // Unversioned / unknown versions below current are legacy.
      expect(
        GenerationBudgetPolicy.ceilingFor(
          target: 50000,
          absolute: ResourceLimits.worldviewAbsoluteCharacters,
          elasticPercent: 50,
          policyVersion: 0,
        ),
        60000,
      );
    });

    test('legacy and current agree whenever floor(T*(1+E)) <= A', () {
      for (final e in const [0, 5, 20]) {
        final current = GenerationBudgetPolicy.cumulativeCeiling(
            target: 20000, elasticPercent: e);
        final legacy = GenerationBudgetPolicy.legacyCumulativeCeiling(
          target: 20000,
          absolute: ResourceLimits.characterAbsoluteCharacters,
          elasticPercent: e,
        );
        expect(current, legacy, reason: 'E=$e');
      }
    });
  });

  group('GenerationBudgetPolicy.deviationPercent', () {
    test('reports the goal deviation, positive and negative', () {
      expect(
        GenerationBudgetPolicy.deviationPercent(actual: 9600, target: 8000),
        20.0,
      );
      expect(
        GenerationBudgetPolicy.deviationPercent(actual: 8400, target: 8000),
        5.0,
      );
      expect(
        GenerationBudgetPolicy.deviationPercent(actual: 8750, target: 8000),
        9.4,
      );
      expect(
        GenerationBudgetPolicy.deviationPercent(actual: 7500, target: 8000),
        -6.3,
      );
    });

    test('zero target yields zero instead of dividing by zero', () {
      expect(
        GenerationBudgetPolicy.deviationPercent(actual: 100, target: 0),
        0,
      );
    });
  });

  group('elastic ceiling vs capacity classification', () {
    test('the ordinary absolute boundary is unchanged', () {
      expect(
        ResourceLimits.character.statusFor(
          ResourceLimits.characterAbsoluteCharacters,
        ),
        CapacityStatus.elastic,
      );
      expect(
        ResourceLimits.character
            .statusFor(ResourceLimits.characterNominalCharacters),
        CapacityStatus.normal,
      );
      expect(ResourceLimits.character.statusFor(21000), CapacityStatus.elastic);
    });

    test('an authorized ceiling moves the overflow boundary', () {
      const policy = ResourceLimits.character;
      // C = 30000 for T = 20000 at 50%.
      final effective = policy.effectiveCharacters(30000);
      expect(effective, 30000);
      expect(
        policy.statusForEffective(27000, effective),
        CapacityStatus.elastic,
        reason: 'over the old 24000 absolute but within C, so not overflow',
      );
      expect(
        policy.statusForEffective(30001, effective),
        CapacityStatus.overflow,
      );
      // Without an authorization the boundary stays at the absolute.
      expect(policy.effectiveCharacters(0), 24000);
      expect(policy.statusFor(27000), CapacityStatus.overflow);
    });

    test('a smaller authorized ceiling never narrows the boundary', () {
      const policy = ResourceLimits.worldview;
      // T below nominal gives C < A; the effective boundary must stay at A.
      expect(policy.effectiveCharacters(40000), 60000);
      expect(
          policy.statusForEffective(55000, policy.effectiveCharacters(40000)),
          CapacityStatus.elastic);
    });

    test('a narrower effective boundary is rejected as a policy bug', () {
      expect(
        () => ResourceLimits.character.statusForEffective(1000, 10000),
        throwsArgumentError,
      );
    });
  });
}
