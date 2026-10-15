import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/blueprint_token_budget.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';

/// DeepSeek Flash's verified physical limits (Chat Completions `max_tokens`
/// range 1..393216; context length 1M). Kept as literals because instance
/// property access is not a constant expression; the registry test pins the
/// registry to these same numbers.
const int _flashMaxOutput = 393216;
const int _flashContext = 1000000;

BlueprintTokenBudget _budgetFor(
  int target, {
  int reference = 0,
  int inputTokens = 4000,
  int modelMax = _flashMaxOutput,
  int context = _flashContext,
  int? plannedSections,
  int? plannedParts,
}) =>
    BlueprintTokenBudgetPolicy.compute(
      resourceType: ResourceType.worldview,
      targetCharacters: target,
      referenceCharacters: reference,
      estimatedInputTokens: inputTokens,
      modelMaximumOutputTokens: modelMax,
      modelContextWindow: context,
      plannedSections: plannedSections,
      plannedParts: plannedParts,
    );

void main() {
  group('BlueprintTokenBudgetPolicy target matrix', () {
    const targets = [8000, 10000, 20000, 25000, 35000, 50000];

    test('every target produces a positive, feasible, monotonic budget', () {
      final budgets = [for (final t in targets) _budgetFor(t)];
      for (var i = 0; i < budgets.length; i++) {
        final budget = budgets[i];
        expect(budget.feasible, isTrue, reason: 'target ${targets[i]}');
        expect(budget.allowedOutputTokens, greaterThan(0));
        expect(budget.allowedOutputTokens, lessThanOrEqualTo(_flashMaxOutput));
        expect(budget.boundReason, 'estimate-bound');
      }
      for (var i = 1; i < budgets.length; i++) {
        expect(
          budgets[i].allowedOutputTokens,
          greaterThan(budgets[i - 1].allowedOutputTokens),
          reason: 'budget must grow from ${targets[i - 1]} to ${targets[i]}',
        );
      }
    });

    test('4096 is not an implicit cap: large targets exceed it substantially',
        () {
      for (final target in [20000, 25000, 35000, 50000]) {
        expect(_budgetFor(target).allowedOutputTokens, greaterThan(4096),
            reason: 'target $target');
      }
    });

    test('16384 is not a new implicit cap: 50000 exceeds it', () {
      final budget = _budgetFor(50000);
      expect(budget.requestedOutputTokens, greaterThan(16384));
      expect(budget.allowedOutputTokens, greaterThan(16384));
    });

    test('the budget is not a single fixed constant across targets', () {
      final distinct = {
        for (final target in targets) _budgetFor(target).allowedOutputTokens,
      };
      expect(distinct.length, targets.length);
    });

    test('larger reference complexity raises the estimate', () {
      final plain = _budgetFor(50000);
      final rich = _budgetFor(50000, reference: 8000);
      expect(rich.estimatedParts, greaterThanOrEqualTo(plain.estimatedParts));
      expect(
          rich.requestedOutputTokens, greaterThan(plain.requestedOutputTokens));
    });

    test('structure estimate stays within the plan ceilings', () {
      final huge = _budgetFor(100000000);
      expect(huge.estimatedParts, BlueprintTokenBudgetPolicy.maxParts);
      expect(huge.estimatedSections, BlueprintTokenBudgetPolicy.maxSections);
      // No integer overflow / absurd grant for an absurd target.
      expect(huge.allowedOutputTokens, lessThanOrEqualTo(_flashMaxOutput));
    });
  });

  group('BlueprintTokenBudgetPolicy model and context bounds', () {
    test('never exceeds verified model capability', () {
      final budget = _budgetFor(50000, modelMax: 8192, context: 1 << 20);
      expect(budget.isModelBound, isTrue);
      expect(budget.allowedOutputTokens, 8192);
      expect(budget.boundReason, 'model-bound');
    });

    test('never exceeds remaining context capacity', () {
      final budget = _budgetFor(50000,
          modelMax: 393216, context: 20000, inputTokens: 8000);
      expect(budget.isContextBound, isTrue);
      expect(budget.remainingContextTokens, 12000);
      expect(budget.allowedOutputTokens, 12000);
      expect(budget.boundReason, 'context-bound');
    });

    test('prompt that exhausts the context window is infeasible', () {
      final budget =
          _budgetFor(50000, modelMax: 4096, context: 4000, inputTokens: 4000);
      expect(budget.remainingContextTokens, 0);
      expect(budget.feasible, isFalse);
      expect(budget.allowedOutputTokens, 0);
      expect(budget.boundReason, 'context-exhausted');
    });

    test('an unknown model (zero maximum output) is infeasible, not large', () {
      final budget = _budgetFor(50000, modelMax: 0, context: 8192);
      expect(budget.feasible, isFalse);
      expect(budget.allowedOutputTokens, 0);
      expect(budget.boundReason, 'model-unknown');
    });

    test('a conservative model can still plan a small target', () {
      final budget =
          _budgetFor(3000, modelMax: 1024, context: 8192, inputTokens: 800);
      expect(budget.feasible, isTrue);
      expect(budget.allowedOutputTokens, 1024);
    });
  });

  group('BlueprintTokenBudgetPolicy robustness', () {
    test('zero and negative targets do not crash or overflow', () {
      for (final target in [0, -1, -100000]) {
        final budget = _budgetFor(target);
        expect(budget.targetCharacters, 0);
        expect(budget.estimatedParts, greaterThanOrEqualTo(1));
        expect(budget.allowedOutputTokens, greaterThan(0));
      }
    });

    test('negative inputs are clamped, never producing negative budgets', () {
      final budget = _budgetFor(-5, reference: -3, inputTokens: -100);
      expect(budget.estimatedInputTokens, 0);
      expect(budget.remainingContextTokens, _flashContext);
      expect(budget.allowedOutputTokens, greaterThan(0));
    });

    test('explicit planned structure overrides the target-derived estimate',
        () {
      final budget = _budgetFor(50000, plannedSections: 2, plannedParts: 3);
      expect(budget.estimatedParts, 3);
      expect(budget.estimatedSections, 2);
    });

    test('explicit structure is clamped to the plan ceilings', () {
      final budget = _budgetFor(50000, plannedSections: 999, plannedParts: 999);
      expect(budget.estimatedParts, BlueprintTokenBudgetPolicy.maxParts);
      expect(budget.estimatedSections, BlueprintTokenBudgetPolicy.maxSections);
      final tiny = _budgetFor(50000, plannedSections: -5, plannedParts: 0);
      expect(tiny.estimatedParts, 1);
      expect(tiny.estimatedSections, 1);
    });
  });

  group('BlueprintTokenBudgetPolicy truncation retry growth', () {
    test('grows the grant but never above the model ceiling', () {
      final budget = _budgetFor(50000, modelMax: 65536, context: 1 << 20);
      final next = BlueprintTokenBudgetPolicy.nextTruncationRetryBudget(
        budget,
        observedCompletionTokens: budget.allowedOutputTokens,
      );
      expect(next, isNotNull);
      expect(next!, greaterThan(budget.allowedOutputTokens));
      expect(next, lessThanOrEqualTo(65536));
    });

    test('refuses to retry a context-bound request', () {
      final budget = _budgetFor(50000,
          modelMax: 393216, context: 20000, inputTokens: 8000);
      expect(budget.isContextBound, isTrue);
      expect(
        BlueprintTokenBudgetPolicy.nextTruncationRetryBudget(budget),
        isNull,
      );
    });

    test('refuses to retry when the model ceiling is already reached', () {
      final budget = _budgetFor(50000, modelMax: 4096, context: 1 << 20);
      expect(budget.allowedOutputTokens, 4096);
      expect(
        BlueprintTokenBudgetPolicy.nextTruncationRetryBudget(budget),
        isNull,
      );
    });
  });

  group('BlueprintTokenBudgetPolicy timeout coordination', () {
    test('small grants keep the 60 s floor', () {
      expect(
        BlueprintTokenBudgetPolicy.recommendedTimeoutForTokens(1024),
        BlueprintTokenBudgetPolicy.minimumPlanningTimeout,
      );
    });

    test('larger grants get a proportionally longer, bounded window', () {
      final small =
          BlueprintTokenBudgetPolicy.recommendedTimeoutForTokens(4000);
      final large =
          BlueprintTokenBudgetPolicy.recommendedTimeoutForTokens(18000);
      expect(large, greaterThan(small));
      expect(large,
          lessThanOrEqualTo(BlueprintTokenBudgetPolicy.maximumPlanningTimeout));
      expect(
        BlueprintTokenBudgetPolicy.recommendedTimeoutForTokens(1 << 30),
        BlueprintTokenBudgetPolicy.maximumPlanningTimeout,
      );
    });
  });
}
