import 'dart:math' as math;

import '../../domain/resources/resource_blueprint.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_limits.dart';

/// Thrown when the active model cannot physically emit a complete Blueprint for
/// the requested generation target.
///
/// This is a *budget* failure, not a protocol failure: the plan is provably
/// impossible under the model's verified limits, so no request is attempted and
/// no partial Blueprint is ever saved.
class BlueprintBudgetInfeasibleException implements Exception {
  const BlueprintBudgetInfeasibleException(this.message);

  final String message;

  @override
  String toString() => 'BlueprintBudgetInfeasibleException: $message';
}

/// Estimated structural shape of a plan (how many Sections and Parts the model
/// is expected to emit for a target).
final class BlueprintStructureEstimate {
  const BlueprintStructureEstimate({
    required this.sections,
    required this.parts,
  });

  final int sections;
  final int parts;
}

/// The dynamic output-token budget for one Blueprint planning request.
///
/// Three distinct quantities are kept apart, exactly as the transport needs
/// them:
/// - [estimatedOutputTokens] / [requestedOutputTokens]: what a complete plan is
///   expected to need (estimate plus a safety reserve).
/// - [modelMaximumOutputTokens] / [modelContextWindow]: hard physical limits.
/// - [allowedOutputTokens]: the value actually sent as `max_tokens`, i.e.
///   `min(requested, modelMaximum, remainingContext)`. It is never a fixed
///   constant.
final class BlueprintTokenBudget {
  const BlueprintTokenBudget({
    required this.resourceType,
    required this.targetCharacters,
    required this.estimatedSections,
    required this.estimatedParts,
    required this.estimatedOutputTokens,
    required this.safetyReserveTokens,
    required this.requestedOutputTokens,
    required this.modelMaximumOutputTokens,
    required this.modelContextWindow,
    required this.estimatedInputTokens,
  });

  final ResourceType resourceType;
  final int targetCharacters;
  final int estimatedSections;
  final int estimatedParts;

  /// Tokens a complete Blueprint JSON is estimated to need.
  final int estimatedOutputTokens;

  /// Head-room added on top of [estimatedOutputTokens] for estimation error.
  final int safetyReserveTokens;

  /// [estimatedOutputTokens] + [safetyReserveTokens], before clamping.
  final int requestedOutputTokens;

  final int modelMaximumOutputTokens;
  final int modelContextWindow;
  final int estimatedInputTokens;

  /// Context capacity left for the response after the prompt.
  int get remainingContextTokens =>
      math.max(0, modelContextWindow - estimatedInputTokens);

  /// The value that must be sent as `max_tokens`.
  ///
  /// `min(requestedOutput, modelMaximumOutput, remainingContextCapacity)`, never
  /// negative and never above any real limit.
  int get allowedOutputTokens {
    var allowed = requestedOutputTokens;
    if (allowed > modelMaximumOutputTokens) allowed = modelMaximumOutputTokens;
    if (allowed > remainingContextTokens) allowed = remainingContextTokens;
    return math.max(0, allowed);
  }

  /// True when the model's own output ceiling is what limits the request.
  bool get isModelBound =>
      requestedOutputTokens > modelMaximumOutputTokens &&
      modelMaximumOutputTokens <= remainingContextTokens;

  /// True when the remaining context window is what limits the request.
  ///
  /// A context-bound request cannot be helped by a retry: growing the output
  /// budget would only push the prompt+response past the context window.
  bool get isContextBound =>
      remainingContextTokens < requestedOutputTokens &&
      remainingContextTokens <= modelMaximumOutputTokens;

  /// True when a complete plan is physically possible under the model limits.
  bool get feasible =>
      modelMaximumOutputTokens > 0 &&
      remainingContextTokens > 0 &&
      allowedOutputTokens >=
          BlueprintTokenBudgetPolicy.minimumFeasibleOutputTokens;

  /// Short, content-free description of why the request is (or is not) clamped,
  /// safe to attach to diagnostics.
  String get boundReason {
    if (modelMaximumOutputTokens <= 0) return 'model-unknown';
    if (remainingContextTokens <= 0) return 'context-exhausted';
    if (isContextBound) return 'context-bound';
    if (isModelBound) return 'model-bound';
    return 'estimate-bound';
  }
}

/// Computes a model-driven output budget for Blueprint planning.
///
/// The previous behaviour sent a fixed `max_tokens: 4096` for every plan, which
/// truncated any plan whose JSON exceeded that budget (`finish_reason=length`).
/// This policy instead derives the budget from the plan the target requires and
/// clamps it to the model's real limits.
///
/// The algorithm is deliberately explainable and testable:
///
/// 1. Estimate the plan shape (Section/Part counts) from the target size, with a
///    bounded reference-complexity bonus.
/// 2. Estimate the JSON size from per-element protocol budgets derived from the
///    validator's content boundaries, so the estimate is an upper bound on the
///    output the validator would accept.
/// 3. Convert characters to tokens with the heaviest per-character weight in
///    [TokenEstimator] (CJK, 0.7) — never a 1:1 character/token assumption.
/// 4. Add a safety reserve for estimation error.
/// 5. Clamp to `min(requested, modelMaximumOutput, remainingContext)`.
///
/// No value in this policy is used as a hidden global ceiling: the only hard
/// ceilings are the model's own limits.
abstract final class BlueprintTokenBudgetPolicy {
  BlueprintTokenBudgetPolicy._();

  /// Structural ceilings, mirroring the ID pool the validator enforces.
  static const int maxSections = BlueprintIdPool.defaultMaxSections;
  static const int maxParts = BlueprintIdPool.defaultMaxParts;

  /// Conservative planned-Part size (characters) used only to estimate how many
  /// Parts the model will emit for a target.
  ///
  /// Kept deliberately below [ResourceLimits.maxPartCharacters] so the estimate
  /// stays on the safe side when the model chooses finer granularity than the
  /// per-Part transport cap.
  static const int plannedPartCharacters = 2000;

  /// Average Parts per Section used to estimate the Section count.
  static const int partsPerSection = 3;

  /// Reference length (characters) at which the complexity bonus saturates.
  /// Matches the prompt builder's reference truncation window.
  static const int referenceComplexitySaturationCharacters = 8000;

  /// Maximum fractional increase of the Part estimate for a rich reference.
  static const double referenceComplexityBonus = 0.25;

  /// Per-element protocol budgets in characters.
  ///
  /// Derived from the validator's accepted maxima (Section title 100 +
  /// summary 500, Part title 100 + goal 500, plus keys, ids, digits and
  /// punctuation), so a plan that would pass validation always fits the
  /// estimate.
  static const int protocolBaseCharacters = 400;
  static const int sectionCharacters = 400;
  static const int partCharacters = 600;

  /// Safety head-room over the estimate.
  static const double safetyReserveRatio = 0.35;
  static const int minimumSafetyReserveTokens = 512;

  /// Smallest output that can carry a minimal protocol object.
  static const int minimumFeasibleOutputTokens = 512;

  /// Per-character token weight for the estimate.
  ///
  /// The heaviest weight used by `TokenEstimator` (CJK, 0.7), applied to the
  /// whole estimated JSON so the token estimate is conservative rather than a
  /// point estimate. Chinese characters are never counted as one token each.
  static const double tokensPerCharacter =
      ResourceLimits.capacityTokenWeightPerCharacter;

  /// Timeout coordination.
  ///
  /// A larger budget legitimately takes longer. The window scales with the
  /// granted output tokens at a conservative throughput, while keeping a lower
  /// bound (small plans keep the historical 60 s) and a hard upper bound so a
  /// request can never wait indefinitely.
  static const Duration minimumPlanningTimeout = Duration(seconds: 60);
  static const Duration maximumPlanningTimeout = Duration(minutes: 8);
  static const Duration timeoutBaseAllowance = Duration(seconds: 30);
  static const int assumedOutputTokensPerSecond = 60;

  /// Estimates the plan shape for a target.
  static BlueprintStructureEstimate estimateStructure({
    required int targetCharacters,
    required int referenceCharacters,
    int? plannedSections,
    int? plannedParts,
  }) {
    final target = math.max(0, targetCharacters);
    final reference = math.max(0, referenceCharacters);
    final complexity = 1.0 +
        referenceComplexityBonus *
            (reference.clamp(0, referenceComplexitySaturationCharacters) /
                referenceComplexitySaturationCharacters);

    final parts = plannedParts ??
        (target <= 0
            ? 1
            : math.max(
                1, (target * complexity / plannedPartCharacters).ceil()));
    final clampedParts = parts.clamp(1, maxParts).toInt();
    final sections = plannedSections == null
        ? math
            .max(1, (clampedParts / partsPerSection).ceil())
            .clamp(1, maxSections)
            .toInt()
        : plannedSections.clamp(1, maxSections).toInt();
    return BlueprintStructureEstimate(sections: sections, parts: clampedParts);
  }

  /// Computes the dynamic output budget for one planning request.
  static BlueprintTokenBudget compute({
    required ResourceType resourceType,
    required int targetCharacters,
    required int referenceCharacters,
    required int estimatedInputTokens,
    required int modelMaximumOutputTokens,
    required int modelContextWindow,
    int? plannedSections,
    int? plannedParts,
  }) {
    final target = math.max(0, targetCharacters);
    final structure = estimateStructure(
      targetCharacters: target,
      referenceCharacters: referenceCharacters,
      plannedSections: plannedSections,
      plannedParts: plannedParts,
    );

    final estimatedCharacters = protocolBaseCharacters +
        sectionCharacters * structure.sections +
        partCharacters * structure.parts;
    final estimatedOutputTokens =
        (estimatedCharacters * tokensPerCharacter).ceil();
    final reserve = math.max(
      minimumSafetyReserveTokens,
      (estimatedOutputTokens * safetyReserveRatio).ceil(),
    );

    return BlueprintTokenBudget(
      resourceType: resourceType,
      targetCharacters: target,
      estimatedSections: structure.sections,
      estimatedParts: structure.parts,
      estimatedOutputTokens: estimatedOutputTokens,
      safetyReserveTokens: reserve,
      requestedOutputTokens: estimatedOutputTokens + reserve,
      modelMaximumOutputTokens: modelMaximumOutputTokens,
      modelContextWindow: modelContextWindow,
      estimatedInputTokens: math.max(0, estimatedInputTokens),
    );
  }

  /// The `max_tokens` to use for a bounded full-replan after a truncated
  /// response, or null when a retry cannot help.
  ///
  /// Returns null when the request is already context-bound (growing the output
  /// cannot create context), when the model ceiling is already reached, or when
  /// the growth would not actually raise the granted budget. The caller decides
  /// how many attempts to allow; this only computes one step.
  static int? nextTruncationRetryBudget(
    BlueprintTokenBudget budget, {
    int? observedCompletionTokens,
  }) {
    if (budget.isContextBound) return null;
    final current = budget.allowedOutputTokens;
    if (current <= 0) return null;
    final observed = observedCompletionTokens ?? 0;
    final doubled = math.max(current + 1, current * 2);
    final observedTarget =
        observed > 0 ? math.max(observed * 2, current + 1) : 0;
    final target = math.max(doubled, observedTarget);
    final bounded = math.min(
      math.min(target, budget.modelMaximumOutputTokens),
      budget.remainingContextTokens,
    );
    return bounded > current ? bounded : null;
  }

  /// Derives a planning timeout from the granted output budget.
  static Duration recommendedTimeout(BlueprintTokenBudget budget) =>
      recommendedTimeoutForTokens(budget.allowedOutputTokens);

  /// Derives a planning timeout directly from an output-token grant.
  static Duration recommendedTimeoutForTokens(int outputTokens) {
    final safeTokens = math.max(0, outputTokens);
    final tokenSeconds = (safeTokens / assumedOutputTokensPerSecond).ceil();
    final seconds = timeoutBaseAllowance.inSeconds + tokenSeconds;
    return Duration(
      seconds: seconds
          .clamp(
            minimumPlanningTimeout.inSeconds,
            maximumPlanningTimeout.inSeconds,
          )
          .toInt(),
    );
  }
}
