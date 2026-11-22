import 'resource_contracts.dart';

/// The single source of truth for resource content capacity.
///
/// Frozen in Phase 0 and consumed by every later phase: pages, prompts,
/// coordinators and business classes must read these values instead of
/// repeating the numbers, so there is exactly one place to change a budget.
///
/// Semantics (ADR-0001):
/// - `nominal` is the normal operating budget.
/// - Between `nominal` and `absolute` the resource is [CapacityStatus.elastic].
/// - Above `absolute` it is [CapacityStatus.overflow].
/// - Overflow content is never truncated: an ordinary write above `absolute`
///   is rejected before persistence instead of losing text.
///
/// The character-card two-level budget is also the default boundary used by
/// card validation: `nominal` is the maximum any UI control or generation
/// target may offer, while `absolute` is the hard acceptance ceiling for
/// ordinary writes. A body above `absolute` is rejected before persistence
/// (fail-closed) rather than being truncated — see `ResourceIntegrityValidator`.
///
/// An authorized AI generation run may freeze a cumulative ceiling C above
/// `absolute`; validation of such a resource uses the widened effective
/// boundary `max(absolute, C)` (see [ResourceCapacityPolicy.effectiveCharacters])
/// so a legitimately generated body is accepted, while imports and manual
/// writes without an authorized run keep the `absolute` ceiling.
abstract final class ResourceLimits {
  static const int worldviewNominalCharacters = 50000;
  static const int worldviewAbsoluteCharacters = 60000;

  /// Character-card normal budget: the largest target the editor, the AI
  /// creation control and every import path may offer.
  static const int characterNominalCharacters = 20000;

  /// Character-card hard ceiling: existing data, generation buffers and import
  /// results up to this size are still saved unchanged, and anything above it
  /// fails closed instead of being silently truncated.
  static const int characterAbsoluteCharacters = 24000;

  /// NPC cards share the character-card budget.
  static const int npcNominalCharacters = characterNominalCharacters;
  static const int npcAbsoluteCharacters = characterAbsoluteCharacters;

  /// Smallest total prose target exposed by AI resource creation.
  ///
  /// The upper bound remains type-specific [nominalCharacters]. Keeping the
  /// lower bound here makes the page and creation validator share one policy.
  static const int minimumGenerationTargetCharacters = 1000;

  /// Discrete target-size increment used by the AI creation control.
  static const int generationTargetStepCharacters = 500;

  static const ResourceCapacityPolicy worldview = ResourceCapacityPolicy(
    nominalCharacters: worldviewNominalCharacters,
    absoluteCharacters: worldviewAbsoluteCharacters,
  );

  static const ResourceCapacityPolicy character = ResourceCapacityPolicy(
    nominalCharacters: characterNominalCharacters,
    absoluteCharacters: characterAbsoluteCharacters,
  );

  static const ResourceCapacityPolicy npc = ResourceCapacityPolicy(
    nominalCharacters: npcNominalCharacters,
    absoluteCharacters: npcAbsoluteCharacters,
  );

  /// The policy for [type]. Every capacity decision must go through here.
  static ResourceCapacityPolicy policyFor(ResourceType type) => switch (type) {
        ResourceType.worldview => worldview,
        ResourceType.character => character,
        ResourceType.npc => npc,
      };
}

/// The single authority for the AI generation elastic budget.
///
/// Three distinct quantities must never be conflated:
/// - `target` (T): the user-selected soft generation goal. The model is asked
///   to aim for it; quality outranks mechanically filling it.
/// - `cumulativeCeiling` (C): the hard cumulative acceptance boundary of one
///   generation run, `floor(T*(100+E)/100)` where E is the task-frozen
///   effective elastic percent. It only bounds what the *run* may commit; it
///   does not re-classify capacity.
/// - `absolute` (A): the resource type's frozen capacity ceiling for ordinary
///   content. Capacity status (normal / elastic / overflow) is computed from
///   the *effective* ceiling via
///   [ResourceCapacityPolicy.statusForEffective], which is `A` for ordinary
///   resources and `max(A, C)` for a resource produced by an authorized AI
///   generation run.
///
/// A body that lands in `target < length <= C` is a normal, accepted
/// generation whose *deviation from the goal* is presented in the UI.
///
/// ## An authorized run may exceed A
///
/// An explicit, user-authorized AI generation task freezes its own budget and
/// may legitimately commit up to C even when C > A; `A` is never re-applied to
/// clip that authorized run. This is exactly what makes "T = 50000 worldview at
/// 50% elasticity → C = 75000" reachable. The widening is scoped to the run:
/// ordinary resources, imports and manual writes keep the A ceiling, and a
/// genuine over-budget generation above C is still rejected at commit.
///
/// ## Budget policy versions
///
/// Because the ceiling formula changed, a run's budget must record *which*
/// formula produced it. A row without a policy version predates elastic
/// breakout and keeps the historical `min(..., A)` semantics, so upgrading the
/// app never retroactively grants an already-frozen run more budget.
/// [legacyBudgetPolicyVersion] is the historical formula; [currentBudgetPolicyVersion]
/// is the breakout formula (`floor(T*(100+E)/100)`).
abstract final class GenerationBudgetPolicy {
  /// Default expansion of the cumulative generated body above the user's
  /// target, expressed in integer percent: `C = floor(T*(100+E)/100)`.
  ///
  /// 20 is the frozen PR #5 behaviour and also the value resolved for legacy
  /// rows whose stored snapshot predates configurable elasticity (NULL
  /// `resource_blueprints.elastic_percent`), so historical runs keep their
  /// original budget no matter what the global setting becomes later.
  static const int defaultElasticPercent = 20;

  /// Lowest configurable elasticity. 0% means "never exceed the target": the
  /// ceiling collapses onto T and over-expansion is rejected at commit.
  static const int minimumElasticPercent = 0;

  /// Highest configurable elasticity. 50% widens the acceptance ceiling
  /// (including above A) for an authorized AI generation run.
  static const int maximumElasticPercent = 50;

  /// Historical (pre-breakout) budget policy: `min(floor(T*(100+E)/100), A)`.
  ///
  /// Rows frozen under this version keep their original ceiling forever, so
  /// changing the formula never widens an already-started run's budget.
  static const int legacyBudgetPolicyVersion = 1;

  /// Current budget policy: `floor(T*(100+E)/100)`, with no absolute clip.
  ///
  /// New generation runs are frozen under this version.
  static const int currentBudgetPolicyVersion = 2;

  /// Clamps and normalizes a user-provided percent into the legal domain.
  ///
  /// Input boundaries (sliders, text fields, restored settings) all funnel
  /// through here so no caller can smuggle an out-of-range value into a
  /// budget computation.
  static int normalizeElasticPercent(int raw) =>
      raw.clamp(minimumElasticPercent, maximumElasticPercent);

  static void _checkElasticPercent(int elasticPercent) {
    if (elasticPercent < minimumElasticPercent ||
        elasticPercent > maximumElasticPercent) {
      throw ArgumentError.value(
        elasticPercent,
        'elasticPercent',
        'must be between $minimumElasticPercent and $maximumElasticPercent',
      );
    }
  }

  static void _checkNonNegative(int value, String name) {
    if (value < 0) {
      throw ArgumentError.value(value, name, 'must not be negative');
    }
  }

  /// The cumulative acceptance ceiling for one generation run under the
  /// current (breakout) policy: `C = floor(T*(100+E)/100)`.
  ///
  /// A non-positive target means "no generation budget": the ceiling is 0 and
  /// callers treat the run as budgetless exactly as they treated
  /// `target_capacity <= 0` before elasticity existed.
  ///
  /// [elasticPercent] is the task-frozen effective percent E. The arithmetic
  /// is pure integer (`T*(100+E) ~/ 100`), so the boundary between an accepted
  /// `C` and a rejected `C+1` never depends on floating-point rounding. The
  /// absolute capacity is deliberately NOT accepted here: an authorized run
  /// must not have its ceiling clipped by it.
  static int cumulativeCeiling({
    required int target,
    int elasticPercent = defaultElasticPercent,
  }) {
    _checkNonNegative(target, 'target');
    _checkElasticPercent(elasticPercent);
    if (target == 0) return 0;
    return (target * (100 + elasticPercent)) ~/ 100;
  }

  /// The historical acceptance ceiling: `min(floor(T*(100+E)/100), A)`.
  ///
  /// Used only for runs frozen under [legacyBudgetPolicyVersion], so their
  /// budget never drifts when the formula changes.
  static int legacyCumulativeCeiling({
    required int target,
    required int absolute,
    int elasticPercent = defaultElasticPercent,
  }) {
    _checkNonNegative(target, 'target');
    _checkNonNegative(absolute, 'absolute');
    _checkElasticPercent(elasticPercent);
    if (target == 0) return 0;
    final elastic = (target * (100 + elasticPercent)) ~/ 100;
    return elastic > absolute ? absolute : elastic;
  }

  /// Version-dispatched ceiling used by persistence-backed consumers.
  ///
  /// A row whose frozen [policyVersion] is at or above
  /// [currentBudgetPolicyVersion] uses the breakout formula; anything lower
  /// (including an unversioned legacy row) keeps the historical clip. The
  /// `absolute` argument is therefore only consulted for legacy rows.
  static int ceilingFor({
    required int target,
    required int absolute,
    required int elasticPercent,
    int policyVersion = currentBudgetPolicyVersion,
  }) {
    if (policyVersion >= currentBudgetPolicyVersion) {
      return cumulativeCeiling(target: target, elasticPercent: elasticPercent);
    }
    return legacyCumulativeCeiling(
      target: target,
      absolute: absolute,
      elasticPercent: elasticPercent,
    );
  }

  /// Deviation of [actual] from [target] in percent, rounded to one decimal.
  ///
  /// Presentation-only: this describes the generation-goal dimension and must
  /// never be used for capacity classification.
  static double deviationPercent({
    required int actual,
    required int target,
  }) {
    if (target <= 0) return 0;
    return ((actual - target) / target * 100 * 10).roundToDouble() / 10;
  }
}

/// Nominal/absolute character budgets for one resource type.
final class ResourceCapacityPolicy {
  const ResourceCapacityPolicy({
    required this.nominalCharacters,
    required this.absoluteCharacters,
  }) : assert(
          nominalCharacters <= absoluteCharacters,
          'nominal budget must not exceed the absolute budget',
        );

  final int nominalCharacters;
  final int absoluteCharacters;

  /// The actual overflow boundary for a resource, widened by an authorized AI
  /// generation budget.
  ///
  /// Ordinary resources (no authorized run) report [absoluteCharacters], which
  /// preserves every pre-existing behavior. A resource produced by an
  /// authorized AI run may carry a frozen ceiling C above A; the effective
  /// boundary is then `max(A, C)` so the run's legitimately generated body is
  /// not re-classified as overflow. The widening direction is one-way: this
  /// can never narrow below A, so a smaller C (for example T below nominal)
  /// still leaves ordinary elastic capacity intact.
  int effectiveCharacters(int authorizedCharacters) {
    if (authorizedCharacters < 0) {
      throw ArgumentError.value(
        authorizedCharacters,
        'authorizedCharacters',
        'must not be negative',
      );
    }
    return authorizedCharacters > absoluteCharacters
        ? authorizedCharacters
        : absoluteCharacters;
  }

  /// Classifies an already measured character count against the type's frozen
  /// [absoluteCharacters] boundary.
  ///
  /// Boundaries are inclusive on the lower band: exactly `nominal` is still
  /// [CapacityStatus.normal] and exactly `absolute` is still
  /// [CapacityStatus.elastic].
  CapacityStatus statusFor(int characterCount) =>
      statusForEffective(characterCount, absoluteCharacters);

  /// Classifies an already measured character count against an explicit
  /// [effectiveAbsoluteCharacters] boundary (see [effectiveCharacters]).
  ///
  /// The normal/elastic split still uses [nominalCharacters]; only the
  /// elastic/overflow split moves. [effectiveAbsoluteCharacters] must not be
  /// below [absoluteCharacters] — a narrower boundary would be a policy bug,
  /// since elastic breakout may only ever widen capacity.
  CapacityStatus statusForEffective(
    int characterCount,
    int effectiveAbsoluteCharacters,
  ) {
    if (characterCount < 0) {
      throw ArgumentError.value(
        characterCount,
        'characterCount',
        'character count must not be negative',
      );
    }
    if (effectiveAbsoluteCharacters < absoluteCharacters) {
      throw ArgumentError.value(
        effectiveAbsoluteCharacters,
        'effectiveAbsoluteCharacters',
        'must not be narrower than the absolute budget',
      );
    }
    if (characterCount <= nominalCharacters) return CapacityStatus.normal;
    if (characterCount <= effectiveAbsoluteCharacters) {
      return CapacityStatus.elastic;
    }
    return CapacityStatus.overflow;
  }
}
