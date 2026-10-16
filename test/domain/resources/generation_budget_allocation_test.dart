import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/generation_budget_allocation.dart';
import 'package:lt_dialogue/domain/resources/resource_limits.dart';

PartBudgetRequirement req(
  String id, {
  bool required = true,
  bool completed = false,
  int minimum = 300,
  int planned = 300,
  int saved = 0,
}) =>
    PartBudgetRequirement(
      partId: id,
      required: required,
      completed: completed,
      minimumCharacters: minimum,
      plannedLength: planned,
      savedLength: saved,
    );

PartGenerationBudgetAllocation compute({
  required PartBudgetRequirement current,
  required int savedOther,
  List<PartBudgetRequirement> unfinished = const [],
  int? ceiling = 1200,
}) =>
    PartGenerationBudgetAllocation.compute(
      current: current,
      savedOther: savedOther,
      unfinishedParts: [current, ...unfinished],
      ceiling: ceiling,
    );

void main() {
  group('PartGenerationBudgetAllocation.compute', () {
    test('budgetless legacy blueprint keeps the transport-only bound', () {
      final allocation = compute(
        current: req('p0', minimum: 10, planned: 500, saved: 0),
        savedOther: 0,
        ceiling: null,
      );
      expect(allocation.isBudgetless, isTrue);
      expect(allocation.isInfeasible, isFalse);
      expect(allocation.dispatchableMaximum, ResourceLimits.maxPartCharacters);
      expect(allocation.recommendedTarget, 500);
    });

    test('feasible when the reserve leaves room for the current minimum', () {
      final allocation = compute(
        current: req('p0'),
        savedOther: 0,
        unfinished: [req('p1'), req('p2')],
      );
      expect(allocation.isFeasible, isTrue);
      // 1200 - 0 saved, minus 600 reserved for p1/p2.
      expect(allocation.futureReserve, 600);
      expect(allocation.dispatchableMaximum, 600);
      expect(allocation.recommendedTarget, 300);
      expect(allocation.unfinishedRequiredCount, 3);
    });

    test('belowMinimum when the reserve starves the current Part', () {
      // The current Part already saved its minimum, but only 100 units remain,
      // fewer than the 300 a full replacement would need.
      final allocation = compute(
        current: req('p3', saved: 300),
        savedOther: 1100,
        unfinished: const [],
      );
      expect(allocation.infeasibility, BudgetInfeasibility.belowMinimum);
      expect(allocation.isInfeasible, isTrue);
      expect(allocation.dispatchableMaximum, 100);
      expect(allocation.infeasibilityMessage, contains('最低'));
    });

    test('ceilingExhausted when other Parts already spend the ceiling', () {
      final allocation = compute(
        current: req('p3'),
        savedOther: 1200,
        unfinished: const [],
      );
      expect(allocation.infeasibility, BudgetInfeasibility.ceilingExhausted);
      expect(allocation.remaining, 0);
    });

    test('minimumTotalExceedsCeiling when the minimums cannot all fit', () {
      final allocation = compute(
        current: req('p0', planned: 400),
        savedOther: 500,
        unfinished: [req('p1', minimum: 500, planned: 500)],
      );
      expect(
        allocation.infeasibility,
        BudgetInfeasibility.minimumTotalExceedsCeiling,
      );
    });

    test('planOutOfBounds when the plan is beyond the transport cap', () {
      final allocation = compute(
        current: req('p0', planned: 4000),
        savedOther: 0,
        ceiling: 60000,
      );
      expect(allocation.infeasibility, BudgetInfeasibility.planOutOfBounds);
    });

    test('optional Parts reserve nothing', () {
      final allocation = compute(
        current: req('p0'),
        savedOther: 0,
        unfinished: [req('p1', required: false, minimum: 500)],
      );
      expect(allocation.futureReserve, 0);
      expect(allocation.dispatchableMaximum, 1200);
      expect(allocation.unfinishedRequiredCount, 1);
    });

    test('a Part already meeting its minimum reserves nothing more', () {
      final allocation = compute(
        current: req('p0'),
        savedOther: 300,
        unfinished: [req('p1', saved: 300)],
      );
      expect(allocation.futureReserve, 0);
      expect(allocation.dispatchableMaximum, 900);
    });

    test('a Part below its plan reserves only the missing units', () {
      final allocation = compute(
        current: req('p0'),
        savedOther: 200,
        unfinished: [req('p1', saved: 200)],
      );
      expect(allocation.futureReserve, 100);
    });

    test('a later required Part reserves its planned body, not its minimum',
        () {
      // p1 carries a legacy floor of 10 but is planned at 1000: the reservation
      // must hold its planned size so the current Part cannot swallow it.
      final allocation = compute(
        current: req('p0', minimum: 10, planned: 1000),
        savedOther: 0,
        unfinished: [req('p1', minimum: 10, planned: 1000)],
        ceiling: 2500,
      );
      expect(allocation.futureReserve, 1000);
      expect(allocation.dispatchableMaximum, 1500);
      expect(allocation.recommendedTarget, 1000);
    });

    test('a later Part reserves only the planned body it has not saved yet',
        () {
      final allocation = compute(
        current: req('p0', minimum: 10, planned: 1000),
        savedOther: 400,
        unfinished: [req('p1', minimum: 10, planned: 1000, saved: 400)],
        ceiling: 2500,
      );
      expect(allocation.futureReserve, 600);
    });

    test('dispatchableMaximum never falls below the current plan when it fits',
        () {
      // Ten equal Parts planned at 2000 in a 20% elastic run (ceiling 24000).
      final parts = [
        for (var i = 0; i < 10; i++) req('p$i', minimum: 10, planned: 2000)
      ];
      for (final current in parts) {
        final allocation = PartGenerationBudgetAllocation.compute(
          current: current,
          savedOther: 0,
          unfinishedParts: parts,
          ceiling: 24000,
        );
        expect(allocation.dispatchableMaximum, greaterThanOrEqualTo(2000),
            reason: '${current.partId} must be able to reach its plan');
      }
    });

    test('the tail keeps its plan even after earlier Parts expand to the cap',
        () {
      // Mirrors the production failure: earlier Parts consume up to the
      // transport cap and are then `completed` (so they leave the unfinished
      // set), yet every remaining Part must still reach its planned size and
      // the cumulative total must never pass the ceiling.
      const cap = ResourceLimits.maxPartCharacters;
      final remaining = [
        for (var i = 0; i < 10; i++) req('p$i', minimum: 10, planned: 2000)
      ];
      var savedOther = 0;
      while (remaining.isNotEmpty) {
        final current = remaining.removeAt(0);
        final allocation = PartGenerationBudgetAllocation.compute(
          current: current,
          savedOther: savedOther,
          unfinishedParts: [current, ...remaining],
          ceiling: 24000,
        );
        expect(allocation.dispatchableMaximum,
            greaterThanOrEqualTo(current.plannedLength),
            reason: '${current.partId} must still reach its plan');
        savedOther += allocation.dispatchableMaximum > cap
            ? cap
            : allocation.dispatchableMaximum;
      }
      expect(savedOther, lessThanOrEqualTo(24000));
    });

    test('recommendedTarget never exceeds the plan nor the dispatchable max',
        () {
      final allocation = compute(
        current: req('p0', planned: 900),
        savedOther: 0,
        unfinished: [req('p1')],
      );
      expect(allocation.futureReserve, 300);
      expect(allocation.dispatchableMaximum, 900);
      expect(allocation.recommendedTarget, 900);
    });

    test('negative savedOther and non-positive cap fail closed', () {
      expect(
        () => compute(current: req('p0'), savedOther: -1),
        throwsArgumentError,
      );
      expect(
        () => PartGenerationBudgetAllocation.compute(
          current: req('p0'),
          savedOther: 0,
          unfinishedParts: [req('p0')],
          ceiling: 1200,
          transportCap: 0,
        ),
        throwsArgumentError,
      );
    });

    test('constraintFingerprint changes with the reserve or the saved total',
        () {
      final first = compute(
        current: req('p0'),
        savedOther: 0,
        unfinished: [req('p1')],
      );
      final second = compute(
        current: req('p0'),
        savedOther: 0,
        unfinished: [req('p1', saved: 100)],
      );
      expect(first.constraintFingerprint, isNot(second.constraintFingerprint));
    });
  });
}
