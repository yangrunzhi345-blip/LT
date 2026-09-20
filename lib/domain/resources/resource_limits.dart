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
abstract final class ResourceLimits {
  static const int worldviewNominalCharacters = 50000;
  static const int worldviewAbsoluteCharacters = 60000;

  static const int characterNominalCharacters = 5000;
  static const int characterAbsoluteCharacters = 6000;

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
  static const int resourceContextTokenBudget = 6000;

  /// Context token threshold above which automatic compression is scheduled.
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
