import 'resource_limits.dart';

/// One Part's contribution to a generation run's budget feasibility.
///
/// The allocation only needs planning metadata: how much the run has already
/// saved for this Part, how much the plan expects, and the minimum the Part's
/// confirmed content contract still requires. Nothing here reads or rewrites
/// prose.
final class PartBudgetRequirement {
  const PartBudgetRequirement({
    required this.partId,
    required this.required,
    required this.completed,
    required this.minimumCharacters,
    required this.plannedLength,
    required this.savedLength,
  })  : assert(minimumCharacters >= 0),
        assert(plannedLength >= 0),
        assert(savedLength >= 0);

  /// Part identity inside the blueprint (e.g. `part_3`).
  final String partId;

  /// Whether the confirmed contract marks this Part as required. Parts the
  /// user explicitly made optional reserve no future capacity.
  final bool required;

  /// Whether the Part already reached `completed`.
  final bool completed;

  /// Minimum acceptable body the contract still demands (legacy floor when no
  /// contract was ever confirmed).
  final int minimumCharacters;

  /// The Part's planned target (`estimatedLength`).
  final int plannedLength;

  /// Characters already persisted for this Part.
  final int savedLength;

  /// Minimum still missing for this Part. A Part whose saved body already
  /// meets its minimum reserves nothing more; its saved length already counts
  /// against the shared ceiling.
  int get additionalMinimum {
    final missing = minimumCharacters - savedLength;
    return missing > 0 ? missing : 0;
  }

  /// Planned body a run must still be able to write for this Part: the
  /// outstanding part of [plannedLength] that [savedLength] does not already
  /// cover.
  ///
  /// This — not [additionalMinimum] — is the reservation basis for a later
  /// *required* Part. A Part's minimum is only the floor below which a body is
  /// rejected; reserving just that floor (ten units for a legacy Part, or a
  /// small confirmed contract floor) lets earlier Parts consume the shared
  /// ceiling down to the point where a later Part can no longer be written at
  /// its own planned size — the Part is then dispatched with a soft target and
  /// an acceptance limit below its plan, and a naturally sized body is
  /// rejected. The planned need is what makes the reservation meaningful.
  int get additionalPlanned {
    final missing = plannedLength - savedLength;
    return missing > 0 ? missing : 0;
  }
}

/// Why a run may not be able to dispatch one Part without starving a later
/// required Part. `budgetless` is not a failure: it preserves the historical
/// behaviour for blueprints that carry no ceiling at all.
enum BudgetInfeasibility {
  /// The Part can be dispatched within the frozen budget.
  feasible,

  /// The blueprint has no budget ceiling (`targetCapacity <= 0`); the legacy
  /// "no reserve" behaviour is retained rather than inventing a limit.
  budgetless,

  /// Other Parts already consume the whole cumulative ceiling.
  ceilingExhausted,

  /// The Part's own minimum is larger than the space left after reserving the
  /// planned bodies of every other unfinished required Part.
  belowMinimum,

  /// The plan itself is outside `[minimumCharacters, transportCap]`; this
  /// should have been rejected at planning time.
  planOutOfBounds,

  /// Even reserving only the minimums, the run cannot satisfy every unfinished
  /// required Part within the ceiling.
  minimumTotalExceedsCeiling,
}

/// The single resolved budget view for one Part dispatch or commit.
///
/// All consumers (pre-dispatch feasibility, the LLM request, and the atomic
/// commit) must read the same value so a request can never be granted more
/// capacity than the commit will accept.
final class PartGenerationBudgetAllocation {
  const PartGenerationBudgetAllocation({
    required this.ceiling,
    required this.transportCap,
    required this.savedOther,
    required this.remaining,
    required this.futureReserve,
    required this.dispatchableMaximum,
    required this.recommendedTarget,
    required this.minimumCharacters,
    required this.infeasibility,
    required this.unfinishedRequiredCount,
  });

  /// Frozen cumulative ceiling `C`, or null for a budgetless legacy blueprint.
  final int? ceiling;

  /// Transport cap `K` (3000).
  final int transportCap;

  /// Characters already spent by every other Part (`S_other`).
  final int savedOther;

  /// `C - S_other`, clamped to zero for reporting. Use [isFeasible] before
  /// trusting this as capacity.
  final int remaining;

  /// Capacity reserved for the outstanding planned bodies of every other
  /// unfinished required Part (`F_i`).
  ///
  /// The reservation is each later required Part's *planned* need
  /// ([PartBudgetRequirement.additionalPlanned]), so earlier Parts cannot
  /// consume a later Part's planned capacity. Combined with `savedOther` this
  /// equals `Σ over other unfinished required Parts of max(saved, planned)`.
  ///
  /// This is what keeps [dispatchableMaximum] at or above the current Part's
  /// own plan whenever the precondition documented on [compute] holds — most
  /// importantly for a freshly confirmed plan whose Parts have not spent the
  /// ceiling yet. It is not an unconditional guarantee (see [compute]).
  final int futureReserve;

  /// `D_i = min(K, max(0, remaining - futureReserve))`: the largest body this
  /// Part may accept without starving a later required Part.
  final int dispatchableMaximum;

  /// `q_i`: the soft target handed to the model. Never below the Part's
  /// minimum and never above [dispatchableMaximum].
  final int recommendedTarget;

  /// `m_i`: the Part's own minimum.
  final int minimumCharacters;

  final BudgetInfeasibility infeasibility;

  /// Number of unfinished required Parts, including this one.
  final int unfinishedRequiredCount;

  bool get isBudgetless => infeasibility == BudgetInfeasibility.budgetless;

  bool get isFeasible => infeasibility == BudgetInfeasibility.feasible;

  /// True only when the run must NOT call the model for this Part.
  bool get isInfeasible => !isFeasible && !isBudgetless;

  /// A stable description of the constraints that produced this allocation.
  /// Used for diagnostics and to detect a stale snapshot.
  String get constraintFingerprint => 'C:${ceiling ?? -1}|K:$transportCap|'
      'S:$savedOther|F:$futureReserve|M:$minimumCharacters|'
      'U:$unfinishedRequiredCount';

  /// The safe, human-actionable reason for an infeasible run. Contains only
  /// derived numbers, never prose or credentials.
  String get infeasibilityMessage => switch (infeasibility) {
        BudgetInfeasibility.ceilingExhausted =>
          '资源累计预算已被其他章节用尽（上限 ${ceiling ?? 0}，已用 $savedOther），'
              '无法在不覆盖已保存正文的情况下继续生成',
        BudgetInfeasibility.belowMinimum =>
          '剩余容量不足以满足本段最低内容要求（本段最低 $minimumCharacters，'
              '扣除后续必填预留后仅剩 $dispatchableMaximum），请调整规划或压缩前段后重试',
        BudgetInfeasibility.planOutOfBounds =>
          '本段规划长度不在允许范围内（最低 $minimumCharacters，上限 $transportCap，'
              '当前计划超界）',
        BudgetInfeasibility.minimumTotalExceedsCeiling =>
          '剩余累计预算无法容纳全部未完成必填章节的最低内容要求'
              '（上限 ${ceiling ?? 0}，已用 $savedOther，后续必填规划预留 $futureReserve），'
              '请调整规划或压缩前段后重试',
        BudgetInfeasibility.feasible || BudgetInfeasibility.budgetless => '',
      };

  /// Resolves one Part's budget from the frozen ceiling and the run's parts.
  ///
  /// [savedOther] is the total body length of every other Part in the resource
  /// (including Parts without a generation task). [unfinishedParts] are all
  /// Parts that are not yet `completed`; the current Part is filtered out
  /// internally so callers may pass the whole unfinished set.
  ///
  /// Sufficient condition for `dispatchableMaximum >= plannedLength` (the
  /// property that lets a Part be written at its planned size), with
  /// `minimumCharacters <= plannedLength <= transportCap` on every Part:
  ///
  /// ```text
  /// completed bodies
  ///   + Σ over unfinished required Parts of max(savedLength, plannedLength)
  ///   + other saved bodies (optional unfinished Parts and Parts outside the
  ///     blueprint)
  /// <= ceiling
  /// ```
  ///
  /// Under that condition — which a freshly confirmed, not-yet-consumed plan
  /// satisfies by construction — the reserve holds each unfinished required
  /// Part's planned capacity, so a Part is never asked for, or judged against,
  /// a bound smaller than its own planned size, and the cumulative committed
  /// total stays within the ceiling.
  ///
  /// The condition is a precondition, not an unconditional guarantee:
  ///
  /// - Reopening a `completed` Part whose saved body is shorter than its plan
  ///   turns it back into an unfinished required Part, so its full plan must be
  ///   found again next to the bodies the other Parts already committed. If
  ///   that no longer fits, neither is its original planned length restored.
  /// - A historical run that already spent capacity keeps its spent capacity:
  ///   changing the reservation basis never invents budget back.
  static PartGenerationBudgetAllocation compute({
    required PartBudgetRequirement current,
    required int savedOther,
    required Iterable<PartBudgetRequirement> unfinishedParts,
    required int? ceiling,
    int transportCap = ResourceLimits.maxPartCharacters,
  }) {
    if (savedOther < 0) {
      throw ArgumentError.value(
          savedOther, 'savedOther', 'must not be negative');
    }
    if (transportCap <= 0) {
      throw ArgumentError.value(
          transportCap, 'transportCap', 'must be positive');
    }
    final unfinished = unfinishedParts
        .where((part) => part.partId != current.partId)
        .toList(growable: false);
    // Reserve each later required Part's outstanding *planned* body, not just
    // its minimum. Reserving the minimum (ten units for a legacy Part, or a
    // small contract floor) leaves the reserve effectively empty, so earlier
    // Parts may consume the whole shared ceiling up to the transport cap; the
    // tail Part then receives a dispatchable maximum below its own planned
    // length, so even a body written exactly to plan is rejected and every
    // retry recomputes the same squeezed limit.
    final reserve = unfinished
        .where((part) => part.required)
        .fold<int>(0, (sum, part) => sum + part.additionalPlanned);
    final unfinishedRequiredCount =
        1 + unfinished.where((part) => part.required).length;

    if (ceiling == null) {
      return PartGenerationBudgetAllocation(
        ceiling: null,
        transportCap: transportCap,
        savedOther: savedOther,
        remaining: 0,
        futureReserve: 0,
        dispatchableMaximum: transportCap,
        recommendedTarget: current.plannedLength,
        minimumCharacters: current.minimumCharacters,
        infeasibility: BudgetInfeasibility.budgetless,
        unfinishedRequiredCount: unfinishedRequiredCount,
      );
    }

    final remaining = ceiling - savedOther;
    final roomAfterReserve = remaining - reserve;
    final dispatchableMaximum = roomAfterReserve <= 0
        ? 0
        : (roomAfterReserve > transportCap ? transportCap : roomAfterReserve);

    final BudgetInfeasibility infeasibility;
    if (current.plannedLength < current.minimumCharacters ||
        current.plannedLength > transportCap) {
      infeasibility = BudgetInfeasibility.planOutOfBounds;
    } else if (remaining <= 0) {
      infeasibility = BudgetInfeasibility.ceilingExhausted;
    } else if (savedOther + reserve + current.additionalMinimum > ceiling) {
      infeasibility = BudgetInfeasibility.minimumTotalExceedsCeiling;
    } else if (current.minimumCharacters > dispatchableMaximum) {
      infeasibility = BudgetInfeasibility.belowMinimum;
    } else {
      infeasibility = BudgetInfeasibility.feasible;
    }

    final recommendedTarget = infeasibility == BudgetInfeasibility.feasible
        ? (current.plannedLength < dispatchableMaximum
            ? current.plannedLength
            : dispatchableMaximum)
        : dispatchableMaximum;

    return PartGenerationBudgetAllocation(
      ceiling: ceiling,
      transportCap: transportCap,
      savedOther: savedOther,
      remaining: remaining > 0 ? remaining : 0,
      futureReserve: reserve,
      dispatchableMaximum: dispatchableMaximum,
      recommendedTarget: recommendedTarget,
      minimumCharacters: current.minimumCharacters,
      infeasibility: infeasibility,
      unfinishedRequiredCount: unfinishedRequiredCount,
    );
  }
}

/// Thrown before any model request when the frozen budget cannot satisfy the
/// Part without starving a later required Part. The run must not spend a paid
/// request and must not retry until the constraints change.
final class PartGenerationBudgetInfeasibleException implements Exception {
  const PartGenerationBudgetInfeasibleException(this.allocation);

  final PartGenerationBudgetAllocation allocation;

  @override
  String toString() =>
      'PartGenerationBudgetInfeasibleException: ${allocation.infeasibility.name} '
      '[${allocation.constraintFingerprint}] '
      '${allocation.infeasibilityMessage}';
}
