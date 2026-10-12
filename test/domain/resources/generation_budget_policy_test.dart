import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_limits.dart';

void main() {
  group('GenerationBudgetPolicy.cumulativeCeiling', () {
    // Acceptance matrix from the elastic-budget spec: C = min(floor(T*1.20), A).
    // A body at exactly C is accepted; one code unit above C is rejected.
    for (final (target, ceiling) in const [
      (1000, 1200),
      (4000, 4800),
      (8000, 9600),
      (12000, 14400),
      (16000, 19200),
      (20000, 24000),
    ]) {
      test('target $target → ceiling $ceiling', () {
        expect(
          GenerationBudgetPolicy.cumulativeCeiling(
            target: target,
            absolute: ResourceLimits.characterAbsoluteCharacters,
          ),
          ceiling,
        );
        expect(
          GenerationBudgetPolicy.cumulativeCeiling(
            target: target,
            absolute: ceiling - 1,
          ),
          ceiling - 1,
          reason: 'the absolute capacity always caps the ceiling',
        );
      });
    }

    test('zero target stays budgetless', () {
      expect(
        GenerationBudgetPolicy.cumulativeCeiling(
          target: 0,
          absolute: ResourceLimits.characterAbsoluteCharacters,
        ),
        0,
      );
    });

    test('negative inputs are rejected', () {
      expect(
        () =>
            GenerationBudgetPolicy.cumulativeCeiling(target: -1, absolute: 100),
        throwsArgumentError,
      );
      expect(
        () =>
            GenerationBudgetPolicy.cumulativeCeiling(target: 100, absolute: -1),
        throwsArgumentError,
      );
    });

    test('never widens another type independent budget', () {
      // NPC shares the character absolute; worldview keeps its own pair. The
      // ceiling is derived from the caller-supplied absolute only.
      expect(
        GenerationBudgetPolicy.cumulativeCeiling(
          target: 20000,
          absolute: ResourceLimits.npcAbsoluteCharacters,
        ),
        24000,
      );
      expect(
        GenerationBudgetPolicy.cumulativeCeiling(
          target: 50000,
          absolute: ResourceLimits.worldviewAbsoluteCharacters,
        ),
        60000,
      );
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
    test('a body at C stays inside the elastic band, never overflow', () {
      for (final (target, ceiling) in const [
        (1000, 1200),
        (8000, 9600),
        (20000, 24000),
      ]) {
        final status = ResourceLimits.character.statusFor(ceiling);
        expect(status, isNot(CapacityStatus.overflow),
            reason: 'target=$target');
      }
      // Exactly absolute is still elastic per the frozen boundary.
      expect(
        ResourceLimits.character.statusFor(
          ResourceLimits.characterAbsoluteCharacters,
        ),
        CapacityStatus.elastic,
      );
      // The end-to-end matrix bands: 20,000 normal, 21,000 elastic.
      expect(
        ResourceLimits.character
            .statusFor(ResourceLimits.characterNominalCharacters),
        CapacityStatus.normal,
      );
      expect(ResourceLimits.character.statusFor(21000), CapacityStatus.elastic);
    });
  });

  group('configurable elastic percent (ADR-0003)', () {
    // Integer arithmetic: C = min((T*(100+E)) ~/ 100, A). The boundary between
    // an accepted C and a rejected C+1 must never depend on float rounding.
    for (final e in const [0, 5, 20, 35, 50]) {
      test('E=$e: target 8000 with unbounded absolute', () {
        final ceiling = GenerationBudgetPolicy.cumulativeCeiling(
          target: 8000,
          absolute: 1 << 31,
          elasticPercent: e,
        );
        expect(ceiling, (8000 * (100 + e)) ~/ 100);
        // Exactly C is a valid body; the policy itself never truncates.
        expect(ceiling, greaterThanOrEqualTo(8000));
      });
    }

    test('E=0 collapses the ceiling onto the target', () {
      expect(
        GenerationBudgetPolicy.cumulativeCeiling(
            target: 8000, absolute: 24000, elasticPercent: 0),
        8000,
      );
      expect(
        GenerationBudgetPolicy.cumulativeCeiling(
            target: 1, absolute: 24000, elasticPercent: 0),
        1,
      );
    });

    test('E=50 never crosses the absolute capacity', () {
      expect(
        GenerationBudgetPolicy.cumulativeCeiling(
            target: 24000, absolute: 24000, elasticPercent: 50),
        24000,
      );
    });

    test('defaults preserve the frozen PR #5 20% behaviour', () {
      expect(GenerationBudgetPolicy.defaultElasticPercent, 20);
      expect(
        GenerationBudgetPolicy.cumulativeCeiling(target: 8000, absolute: 24000),
        9600,
      );
    });

    test('out-of-range percents fail closed', () {
      for (final bad in const [-1, 51, 100]) {
        expect(
          () => GenerationBudgetPolicy.cumulativeCeiling(
              target: 1000, absolute: 24000, elasticPercent: bad),
          throwsArgumentError,
          reason: 'E=$bad',
        );
      }
    });

    test('normalizeElasticPercent clamps user input', () {
      expect(GenerationBudgetPolicy.normalizeElasticPercent(-7), 0);
      expect(GenerationBudgetPolicy.normalizeElasticPercent(0), 0);
      expect(GenerationBudgetPolicy.normalizeElasticPercent(35), 35);
      expect(GenerationBudgetPolicy.normalizeElasticPercent(99), 50);
    });
  });
}
