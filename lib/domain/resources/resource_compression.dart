import 'resource_capacity.dart';
import 'resource_contracts.dart';
import 'resource_limits.dart';

/// What one compression job rewrites.
///
/// A job always targets a finite node window: one Part, or the bounded group of
/// adjacent Parts that make up one Section. There is deliberately no
/// whole-resource scope, so a compression request can never carry a full tree.
enum CompressionScope {
  part,
  section;

  String get storageValue => name;

  static CompressionScope fromStorage(String? value) {
    for (final scope in CompressionScope.values) {
      if (scope.storageValue == value) return scope;
    }
    throw ResourceContractException('Unknown compression scope: $value');
  }
}

/// Lifecycle of one compression job.
///
/// `succeeded`, `failed` and `cancelled` are terminal; a failed job only
/// restarts through [CompressionJobStateMachine] when the caller explicitly
/// retries, and only while its attempt budget allows it.
enum CompressionJobStatus {
  queued,
  running,
  succeeded,
  failed,
  cancelled;

  String get storageValue => name;

  bool get isTerminal =>
      this == succeeded || this == failed || this == cancelled;

  bool get isActive => this == queued || this == running;

  static CompressionJobStatus fromStorage(String? value) {
    for (final status in CompressionJobStatus.values) {
      if (status.storageValue == value) return status;
    }
    throw ResourceContractException('Unknown compression job status: $value');
  }
}

/// The single source of truth for legal compression job transitions.
///
/// Self transitions are legal so re-applying the current state is an idempotent
/// write; everything else is rejected before persistence happens.
abstract final class CompressionJobStateMachine {
  static const Map<CompressionJobStatus, Set<CompressionJobStatus>>
      transitions = {
    CompressionJobStatus.queued: {
      CompressionJobStatus.queued,
      CompressionJobStatus.running,
      CompressionJobStatus.cancelled,
    },
    CompressionJobStatus.running: {
      CompressionJobStatus.running,
      CompressionJobStatus.succeeded,
      CompressionJobStatus.failed,
      CompressionJobStatus.cancelled,
      // Interrupted recovery only: the worker that owned this lease is gone
      // (application restart/crash), so the job is released back to the queue.
      // Nothing else may take this edge — a live worker always finishes through
      // succeeded/failed/cancelled.
      CompressionJobStatus.queued,
    },
    // A failed job returns to `queued` only through an explicit retry.
    CompressionJobStatus.failed: {
      CompressionJobStatus.failed,
      CompressionJobStatus.queued,
      CompressionJobStatus.cancelled,
    },
    CompressionJobStatus.cancelled: {
      CompressionJobStatus.cancelled,
      CompressionJobStatus.queued,
    },
    CompressionJobStatus.succeeded: {
      CompressionJobStatus.succeeded,
    },
  };

  /// The one edge reserved for interrupted-job recovery.
  ///
  /// Kept as a named constant so recovery cannot accidentally widen the table:
  /// the persistence layer reuses it, and a test pins that it is the only
  /// addition to the release path.
  static const CompressionJobStatus recoveryTarget =
      CompressionJobStatus.queued;

  static bool canTransition(
    CompressionJobStatus from,
    CompressionJobStatus to,
  ) =>
      transitions[from]!.contains(to);

  /// Returns [to] when the edge is legal, otherwise throws.
  static CompressionJobStatus advance(
    CompressionJobStatus from,
    CompressionJobStatus to,
  ) {
    if (!canTransition(from, to)) {
      throw ResourceStateTransitionException(
        domain: 'compressionJob',
        from: from.storageValue,
        to: to.storageValue,
      );
    }
    return to;
  }
}

/// One queued or finished compression unit.
///
/// A `running` job belongs to exactly one worker, identified by [workerId] and
/// bounded by [leaseExpiresAt]. That lease is what makes recovery safe: a
/// `running` row whose lease is gone belongs to a process that died, while a
/// row with a live lease must not be touched.
final class CompressionJob {
  const CompressionJob({
    required this.jobId,
    required this.resourceId,
    required this.scope,
    required this.targetNodeId,
    required this.sourceToken,
    this.parentNodeId = '',
    this.status = CompressionJobStatus.queued,
    this.attempts = 0,
    this.maxAttempts = ResourceLimits.maxCompressionAttempts,
    this.errorMessage = '',
    this.workerId = '',
    this.claimedAt,
    this.leaseExpiresAt,
    this.createdAt,
    this.updatedAt,
  });

  final String jobId;
  final ResourceId resourceId;
  final CompressionScope scope;

  /// The Section or Part this job compresses.
  final String targetNodeId;

  /// The owning Section when [scope] is [CompressionScope.part].
  ///
  /// Stored so a per-Part job can read exactly one Section's Parts instead of
  /// walking the whole tree, which is what keeps job execution off an O(n²)
  /// path on a large resource.
  final String parentNodeId;

  /// Optimistic token of the target when the job was queued. A job whose
  /// source token no longer matches the live node is superseded by a new job
  /// instead of compressing content the user has since edited.
  final String sourceToken;

  final CompressionJobStatus status;
  final int attempts;
  final int maxAttempts;
  final String errorMessage;

  /// The worker that currently owns the job; empty when nobody owns it.
  final String workerId;

  /// When [workerId] claimed the job.
  final DateTime? claimedAt;

  /// When the claim becomes reclaimable. Null means "no proveable owner", so
  /// the row is treatable as interrupted rather than live.
  final DateTime? leaseExpiresAt;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Stable identity for queue de-duplication: same resource, same target,
  /// same source version is one job.
  String get dedupKey =>
      '${resourceId.value}|${scope.storageValue}|$targetNodeId|$sourceToken';

  bool get canRetry =>
      status == CompressionJobStatus.failed && attempts < maxAttempts;

  bool get isActive => status.isActive;

  /// True while a lease held by some worker has not expired yet.
  ///
  /// A `running` row without a lease cannot prove ownership, so it is never
  /// considered live and stale recovery may reclaim it.
  bool isLeaseLive(DateTime now) {
    if (status != CompressionJobStatus.running) return false;
    final lease = leaseExpiresAt;
    return lease != null && lease.isAfter(now);
  }

  /// True when [worker] owns this job under a still-valid lease.
  bool isOwnedBy(String worker, DateTime now) =>
      workerId == worker && isLeaseLive(now);

  /// Whether stale recovery may reclaim this row: it is `running` but no live
  /// lease proves that a worker is still working on it.
  bool isReclaimable(DateTime now) =>
      status == CompressionJobStatus.running && !isLeaseLive(now);

  CompressionJob copyWith({
    CompressionScope? scope,
    String? targetNodeId,
    String? parentNodeId,
    String? sourceToken,
    CompressionJobStatus? status,
    int? attempts,
    int? maxAttempts,
    String? errorMessage,
    String? workerId,
    DateTime? claimedAt,
    DateTime? leaseExpiresAt,
    bool clearLease = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CompressionJob(
      jobId: jobId,
      resourceId: resourceId,
      scope: scope ?? this.scope,
      targetNodeId: targetNodeId ?? this.targetNodeId,
      parentNodeId: parentNodeId ?? this.parentNodeId,
      sourceToken: sourceToken ?? this.sourceToken,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      maxAttempts: maxAttempts ?? this.maxAttempts,
      errorMessage: errorMessage ?? this.errorMessage,
      workerId: clearLease ? '' : (workerId ?? this.workerId),
      claimedAt: clearLease ? null : (claimedAt ?? this.claimedAt),
      leaseExpiresAt:
          clearLease ? null : (leaseExpiresAt ?? this.leaseExpiresAt),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() => 'CompressionJob($jobId, ${scope.storageValue} '
      '$targetNodeId, ${status.storageValue}, attempts: $attempts'
      '${workerId.isEmpty ? '' : ', worker: $workerId'})';
}

/// Outcome of re-queueing the failed jobs of one resource.
///
/// A conflict is a normal business result, never an exception: a target that
/// already has a queued or running job must not receive a second active row.
final class CompressionRetryOutcome {
  const CompressionRetryOutcome({
    this.requeued = 0,
    this.skippedActiveTarget = 0,
    this.skippedExhausted = 0,
  });

  /// Failed jobs put back on the queue.
  final int requeued;

  /// Failed jobs whose target already has an active job, so re-queueing them
  /// would create a second active row for the same target.
  final int skippedActiveTarget;

  /// Failed jobs that already spent their attempt budget.
  final int skippedExhausted;

  int get skipped => skippedActiveTarget + skippedExhausted;

  @override
  String toString() => 'CompressionRetryOutcome(requeued: $requeued, '
      'skippedActiveTarget: $skippedActiveTarget, '
      'skippedExhausted: $skippedExhausted)';
}

/// Facts a compression result claims to have kept.
///
/// This is the model's own declaration; [CompressionValidator] additionally
/// checks caller-supplied required terms so a result cannot pass purely by
/// declaring an empty retention list.
final class CompressionRetention {
  const CompressionRetention({
    this.entities = const <String>[],
    this.relationships = const <String>[],
    this.timeline = const <String>[],
  });

  static const CompressionRetention empty = CompressionRetention();

  /// Names that must survive: characters, factions, places, items, rules.
  final List<String> entities;

  /// Pairwise relations such as `A→B`; every side must survive.
  final List<String> relationships;

  /// Ordered timeline facts (dates, eras, sequence markers).
  final List<String> timeline;

  bool get isEmpty =>
      entities.isEmpty && relationships.isEmpty && timeline.isEmpty;

  int get totalCount =>
      entities.length + relationships.length + timeline.length;

  @override
  String toString() => 'CompressionRetention(entities: ${entities.length}, '
      'relationships: ${relationships.length}, timeline: ${timeline.length})';
}

/// A produced compression result.
///
/// Phase 8 only produces candidates. Publishing a candidate as the resource
/// head requires the revision boundary owned by Phase 9, so nothing in Phase 8
/// writes [compressedContent] back into `resource_parts`. Phase 9 adds
/// [appliedAt]: until it is set the candidate is a proposal, and once it is set
/// the candidate has been published as a recorded revision.
final class CompressionCandidate {
  const CompressionCandidate({
    required this.candidateId,
    required this.jobId,
    required this.resourceId,
    required this.scope,
    required this.targetNodeId,
    required this.originalCharacters,
    required this.compressedCharacters,
    required this.compressedContent,
    required this.retention,
    required this.isValidated,
    this.validationMessage = '',
    this.createdAt,
    this.appliedAt,
  });

  final String candidateId;
  final String jobId;
  final ResourceId resourceId;
  final CompressionScope scope;
  final String targetNodeId;
  final int originalCharacters;
  final int compressedCharacters;
  final String compressedContent;
  final CompressionRetention retention;
  final bool isValidated;
  final String validationMessage;
  final DateTime? createdAt;

  /// When this candidate was published as the resource head, or null while it
  /// is still only a proposal.
  final DateTime? appliedAt;

  /// True while the candidate has not been published. The Studio publishes
  /// only candidates that are both [isValidated] and still unapplied.
  bool get isCandidateOnly => appliedAt == null;

  /// True when the candidate may be published: validated, unapplied, and scoped
  /// to a single Part so the target of the write is unambiguous.
  bool get isPublishable =>
      isValidated && isCandidateOnly && scope == CompressionScope.part;

  double get compressionRatio =>
      originalCharacters == 0 ? 1 : compressedCharacters / originalCharacters;

  int get savedCharacters => originalCharacters - compressedCharacters;

  /// Same content with a publication timestamp.
  CompressionCandidate withAppliedAt(DateTime appliedAt) =>
      CompressionCandidate(
        candidateId: candidateId,
        jobId: jobId,
        resourceId: resourceId,
        scope: scope,
        targetNodeId: targetNodeId,
        originalCharacters: originalCharacters,
        compressedCharacters: compressedCharacters,
        compressedContent: compressedContent,
        retention: retention,
        isValidated: isValidated,
        validationMessage: validationMessage,
        createdAt: createdAt,
        appliedAt: appliedAt,
      );

  @override
  String toString() => 'CompressionCandidate($candidateId, $originalCharacters'
      '→$compressedCharacters chars, validated: $isValidated, '
      'applied: ${appliedAt != null})';
}

/// Why a compression job is (or is not) needed.
enum CompressionTriggerReason {
  /// Context about to be sent exceeds the context token budget.
  contextBudgetExceeded,

  /// Resource is above its absolute capacity budget.
  capacityOverflow,

  /// Resource is inside the elastic band; compression is opportunistic.
  capacityElastic,

  /// The user asked for compression explicitly.
  manual,

  /// Nothing to do.
  none;

  String get storageValue => name;
}

/// Configurable thresholds that decide when compression is scheduled.
final class CompressionThresholds {
  const CompressionThresholds({
    this.contextTokenLimit = ResourceLimits.compressionTriggerContextTokens,
    this.fillRatio = ResourceLimits.compressionTriggerFillRatio,
    this.minNodeCharacters = ResourceLimits.minCompressibleNodeCharacters,
  }) : assert(
          fillRatio > 0 && fillRatio <= 1,
          'fillRatio must be within (0, 1]',
        );

  static const CompressionThresholds defaults = CompressionThresholds();

  /// Context token count that triggers automatic compression.
  final int contextTokenLimit;

  /// Fraction of the resource's *nominal* budget above which the elastic
  /// trigger fires. The default of 1.0 reproduces the frozen boundary exactly:
  /// a resource at its nominal budget is still normal.
  final double fillRatio;

  /// Smallest node worth compressing.
  final int minNodeCharacters;

  @override
  String toString() => 'CompressionThresholds(context: $contextTokenLimit, '
      'fillRatio: $fillRatio, minNode: $minNodeCharacters)';
}

/// The outcome of evaluating one trigger condition.
final class CompressionTriggerDecision {
  const CompressionTriggerDecision({
    required this.shouldCompress,
    required this.reason,
    this.targetCharacters = 0,
  });

  const CompressionTriggerDecision.skip()
      : shouldCompress = false,
        reason = CompressionTriggerReason.none,
        targetCharacters = 0;

  final bool shouldCompress;
  final CompressionTriggerReason reason;

  /// The budget a produced candidate must fit into, in characters.
  final int targetCharacters;

  @override
  String toString() => 'CompressionTriggerDecision(${reason.storageValue}, '
      'shouldCompress: $shouldCompress, target: $targetCharacters)';
}

/// Decides *whether* compression is needed and *which* nodes to compress.
///
/// Pure and deterministic: it reads measurements, never the database, so it
/// can be unit tested at every boundary without a fixture.
abstract final class CompressionTriggers {
  /// Evaluates a resource-wide measurement.
  ///
  /// Above the absolute budget the resource is in overflow; otherwise the
  /// elastic trigger fires when the resource passes
  /// [CompressionThresholds.fillRatio] of its nominal budget. Both bands come
  /// from the frozen capacity policy, so compression and capacity can never
  /// disagree about where "too big" starts.
  static CompressionTriggerDecision evaluateResource({
    required ResourceCapacitySnapshot capacity,
    CompressionThresholds thresholds = CompressionThresholds.defaults,
  }) {
    final policy = ResourceLimits.policyFor(capacity.type);
    if (capacity.totalCharacters > policy.absoluteCharacters) {
      return CompressionTriggerDecision(
        shouldCompress: true,
        reason: CompressionTriggerReason.capacityOverflow,
        targetCharacters: policy.nominalCharacters,
      );
    }
    final nominal = policy.nominalCharacters;
    final nominalRatio =
        nominal <= 0 ? 0.0 : capacity.totalCharacters / nominal;
    if (nominalRatio > thresholds.fillRatio) {
      return CompressionTriggerDecision(
        shouldCompress: true,
        reason: CompressionTriggerReason.capacityElastic,
        targetCharacters: policy.nominalCharacters,
      );
    }
    return const CompressionTriggerDecision.skip();
  }

  /// Evaluates the context about to be sent to the model.
  static CompressionTriggerDecision evaluateContext({
    required int contextTokens,
    CompressionThresholds thresholds = CompressionThresholds.defaults,
  }) {
    if (contextTokens > thresholds.contextTokenLimit) {
      return CompressionTriggerDecision(
        shouldCompress: true,
        reason: CompressionTriggerReason.contextBudgetExceeded,
        targetCharacters: thresholds.contextTokenLimit,
      );
    }
    return const CompressionTriggerDecision.skip();
  }

  /// Ranks section targets most-redundant first.
  ///
  /// Only complete sections at or above [CompressionThresholds.minNodeCharacters]
  /// qualify; the list is ordered by combined size so the biggest savings are
  /// attempted first, and truncated to [maxTargets] so one sweep never queues
  /// an unbounded number of jobs.
  static List<SectionCapacitySnapshot> selectSectionTargets({
    required List<SectionCapacitySnapshot> sections,
    CompressionThresholds thresholds = CompressionThresholds.defaults,
    int maxTargets = 8,
  }) {
    if (maxTargets <= 0) return const <SectionCapacitySnapshot>[];
    final candidates = sections
        .where((s) => s.isComplete)
        .where((s) => s.characters >= thresholds.minNodeCharacters)
        .toList()
      ..sort((a, b) {
        final bySize = b.characters.compareTo(a.characters);
        if (bySize != 0) return bySize;
        return a.sectionId.value.compareTo(b.sectionId.value);
      });
    if (candidates.length <= maxTargets) return candidates;
    return candidates.sublist(0, maxTargets);
  }
}

/// Budget arithmetic for a single compression target.
///
/// A budget is a *goal*: a candidate that misses it is still a candidate, and
/// nothing in this class ever truncates content.
abstract final class CompressionBudget {
  /// The character budget one node aims for.
  ///
  /// Always strictly smaller than the input for anything worth compressing, and
  /// never below one character, so a budget can never ask for an empty result.
  static int nodeTargetCharacters(int originalCharacters) {
    if (originalCharacters <= 1) return originalCharacters;
    final raw =
        (originalCharacters * ResourceLimits.compressionTargetRatio).round();
    final bounded = raw < 1 ? 1 : raw;
    return bounded >= originalCharacters ? originalCharacters - 1 : bounded;
  }
}

/// Codes for a failed compression validation.
enum CompressionIssueCode {
  emptyResult,
  notCompressed,
  overBudget,
  missingRequiredTerm,
  missingEntity,
  missingRelationship,
  missingTimelineFact,
}

/// One reason a compression result was rejected.
final class CompressionIssue {
  const CompressionIssue(this.code, this.message);

  final CompressionIssueCode code;
  final String message;

  @override
  String toString() => '${code.name}: $message';
}

/// Outcome of validating one compression result.
final class CompressionValidationResult {
  const CompressionValidationResult({required this.issues});

  static const CompressionValidationResult passed =
      CompressionValidationResult(issues: <CompressionIssue>[]);

  final List<CompressionIssue> issues;

  bool get isValid => issues.isEmpty;

  String get message => issues.map((issue) => issue.message).join('；');

  @override
  String toString() => isValid
      ? 'CompressionValidationResult(valid)'
      : 'CompressionValidationResult(${issues.length} issues)';
}

/// Structural and retention validation for a compression result.
///
/// Semantic grading needs a model, so this validator deliberately checks only
/// properties that can be proven without one:
/// - the result is smaller than the original and within its budget, and
/// - every name, relation and timeline fact that the result claims to keep is
///   actually present, and
/// - every caller-supplied required term (resource/section/part titles) still
///   appears.
///
/// A compression that silently drops a name therefore fails instead of being
/// stored, and the original stays untouched.
abstract final class CompressionValidator {
  /// Separators accepted inside a declared relationship such as `A→B`.
  static final RegExp _relationshipSeparators =
      RegExp(r'\s*(?:→|->|—+|:|：|\||=|＝)\s*');

  static final RegExp _digitRun = RegExp(r'\d+');

  static CompressionValidationResult validate({
    required String originalContent,
    required String compressedContent,
    required CompressionRetention retention,
    required int targetCharacters,
    List<String> requiredTerms = const <String>[],
  }) {
    final issues = <CompressionIssue>[];
    final compressed = compressedContent.trim();

    if (compressed.isEmpty) {
      issues.add(const CompressionIssue(
        CompressionIssueCode.emptyResult,
        '压缩结果为空',
      ));
      return CompressionValidationResult(issues: issues);
    }

    if (compressed.length >= originalContent.trim().length) {
      issues.add(CompressionIssue(
        CompressionIssueCode.notCompressed,
        '压缩结果未变短（原文 ${originalContent.trim().length} 字，结果 ${compressed.length} 字）',
      ));
    }

    if (targetCharacters > 0 && compressed.length > targetCharacters) {
      // The requirement is not relaxed: a result that is shorter than the
      // original but above budget is still rejected. What matters is that the
      // rejection is actionable — the message carries every number the caller
      // needs to decide whether to retry with stronger guidance.
      final originalLength = originalContent.trim().length;
      final achievedRatio =
          originalLength <= 0 ? 0.0 : compressed.length / originalLength;
      issues.add(CompressionIssue(
        CompressionIssueCode.overBudget,
        '压缩结果超出预算：原文 $originalLength 字，实际 ${compressed.length} 字，'
        '目标 $targetCharacters 字（达成比 ${achievedRatio.toStringAsFixed(2)}）'
        '，可重试并加强压缩要求',
      ));
    }

    for (final term in requiredTerms) {
      final trimmed = term.trim();
      if (trimmed.isEmpty) continue;
      if (!compressed.contains(trimmed)) {
        issues.add(CompressionIssue(
          CompressionIssueCode.missingRequiredTerm,
          '关键名称丢失：$trimmed',
        ));
      }
    }

    for (final entity in retention.entities) {
      final trimmed = entity.trim();
      if (trimmed.isEmpty) continue;
      if (!compressed.contains(trimmed)) {
        issues.add(CompressionIssue(
          CompressionIssueCode.missingEntity,
          '实体丢失：$trimmed',
        ));
      }
    }

    for (final relationship in retention.relationships) {
      final parts = relationship
          .split(_relationshipSeparators)
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toList();
      if (parts.isEmpty) continue;
      final missing = parts.where((part) => !compressed.contains(part));
      if (missing.isNotEmpty) {
        issues.add(CompressionIssue(
          CompressionIssueCode.missingRelationship,
          '关系丢失：$relationship（缺少 ${missing.join('、')}）',
        ));
      }
    }

    for (final fact in retention.timeline) {
      final trimmed = fact.trim();
      if (trimmed.isEmpty) continue;
      if (compressed.contains(trimmed)) continue;
      // A timeline fact may be rephrased; every numeric marker it carries must
      // still survive, otherwise the timeline itself was changed.
      final digits =
          _digitRun.allMatches(trimmed).map((m) => m.group(0)!).toSet();
      final missingDigits = digits.where((d) => !compressed.contains(d));
      if (digits.isEmpty || missingDigits.isNotEmpty) {
        issues.add(CompressionIssue(
          CompressionIssueCode.missingTimelineFact,
          '时间线丢失：$trimmed',
        ));
      }
    }

    if (issues.isEmpty) return CompressionValidationResult.passed;
    return CompressionValidationResult(issues: issues);
  }
}
