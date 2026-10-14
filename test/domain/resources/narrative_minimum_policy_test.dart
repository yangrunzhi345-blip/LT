import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/narrative_minimum_policy.dart';
import 'package:lt_dialogue/domain/resources/resource_limits.dart';

/// U6-A: the approved client-authoritative narrative dynamic minimum is a pure
/// integer function. These tests pin the approved parameter table, the segment
/// boundaries, monotonicity, determinism and fail-closed invalid input. They do
/// not touch the planner, validator, SQLite or UI (that wiring is U6-B).
void main() {
  group('NarrativeMinimumPolicy approved parameter table (U6 v0.1)', () {
    const approved = <int, int>{
      100: 50,
      200: 100,
      450: 200,
      800: 340,
      1000: 400,
      1500: 550,
      3000: 1000,
    };

    approved.forEach((planned, minimum) {
      test('p=$planned → m=$minimum', () {
        expect(NarrativeMinimumPolicy.minimumCharactersFor(planned), minimum);
      });
    });

    test('published constants match the approved decision', () {
      expect(NarrativeMinimumPolicy.firstBreakpoint, 200);
      expect(NarrativeMinimumPolicy.secondBreakpoint, 800);
      expect(NarrativeMinimumPolicy.firstSegmentPercent, 50);
      expect(NarrativeMinimumPolicy.secondSegmentPercent, 40);
      expect(NarrativeMinimumPolicy.thirdSegmentPercent, 30);
      expect(NarrativeMinimumPolicy.minimumPlannedLength, 80);
      expect(NarrativeMinimumPolicy.maximumPlannedLength,
          ResourceLimits.maxPartCharacters);
      expect(NarrativeMinimumPolicy.maximumPlannedLength, 3000);
    });
  });

  group('segment boundaries are exact integer breakpoints', () {
    test('first segment is 50% and clamps at 200', () {
      expect(NarrativeMinimumPolicy.minimumCharactersFor(80), 40);
      expect(NarrativeMinimumPolicy.minimumCharactersFor(81), 41);
      expect(NarrativeMinimumPolicy.minimumCharactersFor(199), 100);
      expect(NarrativeMinimumPolicy.minimumCharactersFor(200), 100);
      // 201 charges the +1 increment at 40%: 100 + ceil(1*0.4).
      expect(NarrativeMinimumPolicy.minimumCharactersFor(201), 101);
    });

    test('second segment stays at 40% between 200 and 800', () {
      expect(NarrativeMinimumPolicy.minimumCharactersFor(799), 340);
      expect(NarrativeMinimumPolicy.minimumCharactersFor(800), 340);
      // 801 charges the +1 increment at 30%: 340 + ceil(1*0.3).
      expect(NarrativeMinimumPolicy.minimumCharactersFor(801), 341);
    });

    test('third segment is 30% above 800', () {
      expect(NarrativeMinimumPolicy.minimumCharactersFor(801), 341);
      expect(NarrativeMinimumPolicy.minimumCharactersFor(2999), 1000);
      expect(NarrativeMinimumPolicy.minimumCharactersFor(3000), 1000);
    });
  });

  group('monotonicity, range and determinism', () {
    test('m is non-decreasing across the whole approved domain', () {
      var previous = NarrativeMinimumPolicy.minimumCharactersFor(
          NarrativeMinimumPolicy.minimumPlannedLength);
      for (var p = NarrativeMinimumPolicy.minimumPlannedLength + 1;
          p <= NarrativeMinimumPolicy.maximumPlannedLength;
          p++) {
        final current = NarrativeMinimumPolicy.minimumCharactersFor(p);
        expect(current, greaterThanOrEqualTo(previous),
            reason: 'm must not decrease at p=$p');
        previous = current;
      }
    });

    test('m stays within 1..p and never implies an absolute floor', () {
      for (var p = NarrativeMinimumPolicy.minimumPlannedLength;
          p <= NarrativeMinimumPolicy.maximumPlannedLength;
          p++) {
        final m = NarrativeMinimumPolicy.minimumCharactersFor(p);
        expect(m, greaterThanOrEqualTo(1), reason: 'p=$p');
        expect(m, lessThanOrEqualTo(p),
            reason: 'minimum must not exceed the plan at p=$p');
      }
    });

    test('the same input always yields the same contract minimum', () {
      const p = 1234;
      final first = NarrativeMinimumPolicy.minimumCharactersFor(p);
      for (var i = 0; i < 100; i++) {
        expect(NarrativeMinimumPolicy.minimumCharactersFor(p), first);
      }
    });
  });

  group('fail-closed on invalid planned lengths', () {
    for (final invalid in <int>[79, 1, 0, -1, 3001, 4000]) {
      test('p=$invalid throws ArgumentError', () {
        expect(
          () => NarrativeMinimumPolicy.minimumCharactersFor(invalid),
          throwsA(isA<ArgumentError>()),
        );
      });
    }

    test('isPlannable accepts only the approved domain', () {
      expect(NarrativeMinimumPolicy.isPlannable(80), isTrue);
      expect(NarrativeMinimumPolicy.isPlannable(3000), isTrue);
      expect(NarrativeMinimumPolicy.isPlannable(79), isFalse);
      expect(NarrativeMinimumPolicy.isPlannable(3001), isFalse);
      expect(NarrativeMinimumPolicy.isPlannable(0), isFalse);
      expect(NarrativeMinimumPolicy.isPlannable(-5), isFalse);
    });

    test('the plannable predicate and the minimum function agree', () {
      for (var p = -2; p <= 3002; p++) {
        final plannable = NarrativeMinimumPolicy.isPlannable(p);
        Object? thrown;
        try {
          NarrativeMinimumPolicy.minimumCharactersFor(p);
        } catch (error) {
          thrown = error;
        }
        expect(plannable, thrown == null, reason: 'disagreement at p=$p');
      }
    });
  });
}
