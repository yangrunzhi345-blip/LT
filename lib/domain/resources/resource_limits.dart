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
/// - Overflow content is still persisted in full. No capacity state authorizes
///   truncating user content; overflow only decides whether compression and a
///   new assembly revision are required.
///
/// The character-card two-level budget is also the boundary used by card
/// validation: `nominal` is the maximum any UI control or generation target may
/// offer, while `absolute` is the hard acceptance ceiling. A card body above
/// `absolute` is rejected before persistence (fail-closed) rather than being
/// truncated — see `ResourceIntegrityValidator`.
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

  /// Maximum permitted characters for a single Part prose generation.
  /// Bound to 3000 characters so that the completion is provably guaranteed to fit
  /// within LLM 4096 maxTokens (average 1 token per CJK character).
  static const int maxPartCharacters = 3000;

  /// Smallest total prose target exposed by AI resource creation.
  ///
  /// The upper bound remains type-specific [nominalCharacters]. Keeping the
  /// lower bound here makes the page and creation validator share one policy.
  static const int minimumGenerationTargetCharacters = 1000;

  /// Discrete target-size increment used by the AI creation control.
  static const int generationTargetStepCharacters = 500;

  /// Scene-batch import target range.
  ///
  /// Character cards follow the character nominal cap. NPCs keep their own
  /// smaller scene-batch budget: expanding the character boundary must not
  /// widen the independent NPC/scene limits.
  static const int sceneBatchCharacterMinimumCharacters = 3000;
  static const int sceneBatchCharacterMaximumCharacters =
      characterNominalCharacters;
  static const int sceneBatchNpcMinimumCharacters = 1500;
  static const int sceneBatchNpcMaximumCharacters = 3000;

  // -------------------------------------------------------------------------
  // Phase 8 — capacity and semantic compression budgets.
  //
  // These live here (and only here) so a compression decision never invents a
  // second number. They are capacities, not truncation limits: exceeding them
  // schedules compression candidates, it never authorizes dropping content.
  // -------------------------------------------------------------------------

  /// Conservative tokens-per-character weight for aggregated capacity counts.
  ///
  /// Aggregated capacity only knows a character total, so it uses the heaviest
  /// per-character weight of `TokenEstimator` (CJK, 0.7). That way an aggregate
  /// never claims fewer tokens than the real text would produce.
  static const double capacityTokenWeightPerCharacter = 0.7;

  /// A node smaller than this is never a compression target: compressing it
  /// would cost a request and lose more nuance than it saves.
  static const int minCompressibleNodeCharacters = 600;

  /// Maximum characters of source text handed to one compression request.
  ///
  /// Bounds one request to a finite node window (one Part or a bounded group of
  /// adjacent Parts) so a compression prompt can never carry a whole resource.
  static const int maxCompressionInputCharacters = 12000;

  /// Maximum characters accepted from one compression response.
  ///
  /// A response larger than this is rejected as "not compressed" instead of
  /// being stored, so a compression job can never grow the stored content.
  static const int maxCompressionOutputCharacters = 8000;

  /// Bounded attempt budget for one compression job. A job that keeps failing
  /// stops at this count and waits for an explicit retry — no infinite loop.
  static const int maxCompressionAttempts = 2;

  /// How long one worker may hold a compression job before its lease is
  /// considered stale.
  ///
  /// The lease is what lets a restarted process tell "an orphaned job" apart
  /// from "a job another live worker is running": recovery only reclaims a
  /// `running` row whose lease has expired (or that has no lease at all, which
  /// cannot prove ownership). It must comfortably exceed one bounded
  /// compression request, and be short enough that a crash is reclaimed within
  /// a normal session.
  static const Duration compressionLeaseDuration = Duration(minutes: 5);

  /// Token budget for the priority-packed resource context.
  ///
  /// Audit note (2026-10): this constant currently has no production consumer.
  /// The runtime narrative context budget is derived from the active model's
  /// context window (`ContextBudget.resolve`) plus per-source caps inside
  /// `WeightedContextPlanner`. It is retained as planning metadata for a future
  /// context-driven compression trigger; do not wire it into a decision path
  /// without reconciling it with that runtime budget first.
  static const int resourceContextTokenBudget = 6000;

  /// Context token threshold above which automatic compression is scheduled.
  ///
  /// Audit note (2026-10): only consumed via `CompressionThresholds` defaults
  /// and `CompressionTriggers.evaluateContext`, which has no production caller.
  /// The production compression trigger is the capacity classification
  /// (`CompressionTriggers.evaluateResource`: overflow is mandatory, elastic is
  /// opportunistic background work that never blocks assembly). Retained for
  /// the same reason as [resourceContextTokenBudget].
  static const int compressionTriggerContextTokens = 8000;

  /// Fraction of a resource's **nominal** budget above which the elastic
  /// compression trigger fires. 1.0 means "only above the nominal budget",
  /// which matches the frozen capacity semantics where exactly `nominal` is
  /// still normal.
  static const double compressionTriggerFillRatio = 1.0;

  /// Fraction of a node's original characters a compression candidate may
  /// occupy. 0.6 keeps recognizable detail while removing real redundancy; it
  /// is a target, never a truncation point — a result that fails to reach it is
  /// still stored as a candidate with its measured size.
  static const double compressionTargetRatio = 0.6;

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
///   generation run, `min(floor(T*(100+E)/100), absolute)` where E is the
///   task-frozen effective elastic percent. It only
///   bounds what the *run* may commit; it does not re-classify capacity.
/// - `absolute` (A): the resource type's frozen capacity ceiling. Capacity
///   status (normal / elastic / overflow) is and remains a function of A via
///   [ResourceCapacityPolicy.statusFor].
///
/// A body that lands in `target < length <= C` is a normal, accepted
/// generation whose *deviation from the goal* is presented in the UI; the
/// resource itself is still classified by the nominal/absolute policy. C can
/// never exceed A, so AI generation alone can never push a resource into the
/// overflow band that requires compression before assembly.
abstract final class GenerationBudgetPolicy {
  /// Default expansion of the cumulative generated body above the user's
  /// target, expressed in integer percent: `C = min(floor(T*(100+E)/100), A)`.
  ///
  /// 20 is the frozen PR #5 behaviour and also the value resolved for legacy
  /// rows whose stored snapshot predates configurable elasticity (NULL
  /// `resource_blueprints.elastic_percent`), so historical runs keep their
  /// original budget no matter what the global setting becomes later.
  static const int defaultElasticPercent = 20;

  /// Lowest configurable elasticity. 0% means "never exceed the target": the
  /// ceiling collapses onto T and over-expansion is rejected at commit.
  static const int minimumElasticPercent = 0;

  /// Highest configurable elasticity. 50% widens the acceptance ceiling but
  /// never lifts the absolute capacity A: `min(..., A)` still applies.
  static const int maximumElasticPercent = 50;

  /// Clamps and normalizes a user-provided percent into the legal domain.
  ///
  /// Input boundaries (sliders, text fields, restored settings) all funnel
  /// through here so no caller can smuggle an out-of-range value into a
  /// budget computation.
  static int normalizeElasticPercent(int raw) =>
      raw.clamp(minimumElasticPercent, maximumElasticPercent);

  /// The cumulative acceptance ceiling for one generation run.
  ///
  /// A non-positive target means "no generation budget": the ceiling is 0 and
  /// callers treat the run as budgetless exactly as they treated
  /// `target_capacity <= 0` before elasticity existed.
  ///
  /// [elasticPercent] is the task-frozen effective percent E. The arithmetic
  /// is pure integer (`T*(100+E) ~/ 100`), so the boundary between an accepted
  /// `C` and a rejected `C+1` never depends on floating-point rounding.
  static int cumulativeCeiling({
    required int target,
    required int absolute,
    int elasticPercent = defaultElasticPercent,
  }) {
    if (target < 0) {
      throw ArgumentError.value(target, 'target', 'must not be negative');
    }
    if (absolute < 0) {
      throw ArgumentError.value(absolute, 'absolute', 'must not be negative');
    }
    if (elasticPercent < minimumElasticPercent ||
        elasticPercent > maximumElasticPercent) {
      throw ArgumentError.value(
        elasticPercent,
        'elasticPercent',
        'must be between $minimumElasticPercent and $maximumElasticPercent',
      );
    }
    if (target == 0) return 0;
    final elastic = (target * (100 + elasticPercent)) ~/ 100;
    return elastic > absolute ? absolute : elastic;
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

  /// Classifies an already measured character count.
  ///
  /// Boundaries are inclusive on the lower band: exactly `nominal` is still
  /// [CapacityStatus.normal] and exactly `absolute` is still
  /// [CapacityStatus.elastic].
  CapacityStatus statusFor(int characterCount) {
    if (characterCount < 0) {
      throw ArgumentError.value(
        characterCount,
        'characterCount',
        'character count must not be negative',
      );
    }
    if (characterCount <= nominalCharacters) return CapacityStatus.normal;
    if (characterCount <= absoluteCharacters) return CapacityStatus.elastic;
    return CapacityStatus.overflow;
  }
}
