/// Phase 7 section-scoped control model.
///
/// A `Resource` is a container; a `Section` is the smallest content unit that
/// can be independently generated, validated, edited, retried and deleted.
/// This library freezes that view without redefining the Phase 0 tree: the
/// frozen `ResourceSection` entity keeps its editorial `NodeStatus`, and the
/// generation/validation lifecycle is expressed here as enums plus one read
/// model, so no status is ever carried around as a bare string.
///
/// Pure Dart on purpose: no Flutter, no SQLite, no HTTP. Persistence and
/// orchestration live in `application/` and `services/`.
///
/// Ownership split (ADR-0001 stays intact):
/// - `generationState` is a *derived* rollup of the per-Part generation tasks
///   and committed Part content. It is never stored on `resource_sections`,
///   so it cannot diverge from the Phase 5 task table.
/// - `validationState` is *not* derivable (a section can be created manually
///   with no generation task at all), so it is persisted per section.
library;

import 'resource_contracts.dart';
import 'resource_limits.dart';

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

/// Base type for section-control failures that are the caller's fault.
class SectionControlException implements Exception {
  const SectionControlException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when an illegal [SectionGenerationState] edge is requested.
class SectionStateTransitionException extends SectionControlException {
  SectionStateTransitionException({
    required this.from,
    required this.to,
  }) : super(
          'Illegal section generation transition: '
          '${from.storageValue} -> ${to.storageValue}',
        );

  final SectionGenerationState from;
  final SectionGenerationState to;
}

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Lifecycle of one section as an independently generatable unit.
///
/// `generated` means content exists but has not yet been validated;
/// `completed` means the section's Parts finished generation and validation.
enum SectionGenerationState {
  pending('pending'),
  generating('generating'),
  generated('generated'),
  validating('validating'),
  completed('completed'),
  failed('failed'),
  cancelled('cancelled');

  const SectionGenerationState(this.storageValue);

  final String storageValue;

  /// Parses a stored value. Unknown input is rejected instead of defaulted so
  /// a typo cannot silently mark a section as finished.
  static SectionGenerationState fromStorage(String? value) {
    for (final state in SectionGenerationState.values) {
      if (state.storageValue == value) return state;
    }
    throw SectionControlException('Unknown section generation state: $value');
  }

  bool get isTerminal =>
      this == SectionGenerationState.completed ||
      this == SectionGenerationState.failed ||
      this == SectionGenerationState.cancelled;

  /// Whether work is actively occupying the generation runtime.
  bool get isActive =>
      this == SectionGenerationState.generating ||
      this == SectionGenerationState.validating;

  /// Whether the user must look at this section before it can move on.
  bool get needsAttention =>
      this == SectionGenerationState.failed ||
      this == SectionGenerationState.cancelled;
}

/// Outcome of validating one section's committed content.
///
/// Persisted because it cannot be derived: a manually authored section has no
/// generation task and no history to recompute from.
enum SectionValidationState {
  unvalidated('unvalidated'),
  validating('validating'),
  valid('valid'),
  invalid('invalid');

  const SectionValidationState(this.storageValue);

  final String storageValue;

  static SectionValidationState fromStorage(String? value) {
    for (final state in SectionValidationState.values) {
      if (state.storageValue == value) return state;
    }
    // Missing / unknown storage values are treated as "never validated"
    // rather than corrupt, because the column is optional history.
    return SectionValidationState.unvalidated;
  }

  bool get isInFlight => this == SectionValidationState.validating;
}

// ---------------------------------------------------------------------------
// State machine
// ---------------------------------------------------------------------------

/// The single authority for legal [SectionGenerationState] edges.
///
/// Self transitions are legal so re-applying the current state is an idempotent
/// write instead of an error. Anything not listed is rejected before any
/// persistence or event emission happens.
abstract final class SectionGenerationStateMachine {
  static const Map<SectionGenerationState, Set<SectionGenerationState>>
      transitions = {
    SectionGenerationState.pending: {
      SectionGenerationState.pending,
      SectionGenerationState.generating,
      SectionGenerationState.generated,
      SectionGenerationState.cancelled,
    },
    SectionGenerationState.generating: {
      SectionGenerationState.generating,
      SectionGenerationState.generated,
      SectionGenerationState.validating,
      SectionGenerationState.failed,
      SectionGenerationState.cancelled,
    },
    SectionGenerationState.generated: {
      SectionGenerationState.generated,
      SectionGenerationState.generating,
      SectionGenerationState.validating,
      SectionGenerationState.completed,
      SectionGenerationState.failed,
      SectionGenerationState.cancelled,
    },
    SectionGenerationState.validating: {
      SectionGenerationState.validating,
      SectionGenerationState.generated,
      SectionGenerationState.completed,
      SectionGenerationState.failed,
      SectionGenerationState.cancelled,
    },
    // A completed section may be regenerated, which restarts at `generating`.
    SectionGenerationState.completed: {
      SectionGenerationState.completed,
      SectionGenerationState.generating,
      SectionGenerationState.validating,
    },
    SectionGenerationState.failed: {
      SectionGenerationState.failed,
      SectionGenerationState.generating,
      SectionGenerationState.pending,
    },
    SectionGenerationState.cancelled: {
      SectionGenerationState.cancelled,
      SectionGenerationState.generating,
      SectionGenerationState.pending,
    },
  };

  static bool canTransition(
    SectionGenerationState from,
    SectionGenerationState to,
  ) =>
      transitions[from]!.contains(to);

  /// Returns [to] when the edge is legal, otherwise throws.
  static SectionGenerationState advance(
    SectionGenerationState from,
    SectionGenerationState to,
  ) {
    if (!canTransition(from, to)) {
      throw SectionStateTransitionException(from: from, to: to);
    }
    return to;
  }
}

// ---------------------------------------------------------------------------
// Read model
// ---------------------------------------------------------------------------

/// One independently controllable section.
///
/// `content` is a *derived aggregate* of the section's Parts, exposed so the UI
/// can render a preview/validation without loading the whole resource. It is
/// never persisted on `resource_sections`: long body text only lives in
/// `resource_parts.content` (frozen Phase 0 rule).
final class SectionControlEntry {
  const SectionControlEntry({
    required this.id,
    required this.resourceId,
    required this.title,
    required this.orderIndex,
    this.summary = '',
    this.status = NodeStatus.draft,
    this.generationState = SectionGenerationState.pending,
    this.validationState = SectionValidationState.unvalidated,
    this.validationMessage = '',
    this.content = '',
    this.partCount = 0,
    this.createdAt,
    this.updatedAt,
    this.updatedAtToken = '',
    this.validatedAt,
  })  : assert(orderIndex >= 0, 'orderIndex must not be negative'),
        assert(partCount >= 0, 'partCount must not be negative');

  final SectionId id;
  final ResourceId resourceId;
  final String title;
  final String summary;

  /// Explicit sibling position inside the parent resource.
  final int orderIndex;

  /// Editorial state from the frozen tree model.
  final NodeStatus status;

  final SectionGenerationState generationState;
  final SectionValidationState validationState;
  final String validationMessage;

  /// Derived concatenation of the section's Part content; never stored here.
  final String content;

  /// Number of Parts currently in this section.
  final int partCount;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Storage-form `updated_at` used as the optimistic-locking token.
  ///
  /// Kept verbatim instead of re-serializing [updatedAt]: the token must match
  /// the database column exactly, and a `DateTime` round-trip could drop
  /// precision and turn a valid edit into a false conflict.
  final String updatedAtToken;

  final DateTime? validatedAt;

  bool get hasContent => content.isNotEmpty;

  bool get isBusy => generationState.isActive;

  bool get needsAttention => generationState.needsAttention;

  SectionControlEntry copyWith({
    String? title,
    String? summary,
    int? orderIndex,
    NodeStatus? status,
    SectionGenerationState? generationState,
    SectionValidationState? validationState,
    String? validationMessage,
    String? content,
    int? partCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? updatedAtToken,
    DateTime? validatedAt,
  }) {
    return SectionControlEntry(
      id: id,
      resourceId: resourceId,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      orderIndex: orderIndex ?? this.orderIndex,
      status: status ?? this.status,
      generationState: generationState ?? this.generationState,
      validationState: validationState ?? this.validationState,
      validationMessage: validationMessage ?? this.validationMessage,
      content: content ?? this.content,
      partCount: partCount ?? this.partCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedAtToken: updatedAtToken ?? this.updatedAtToken,
      validatedAt: validatedAt ?? this.validatedAt,
    );
  }

  @override
  String toString() => 'SectionControlEntry(${id.value}, order: $orderIndex, '
      'generation: ${generationState.storageValue}, '
      'validation: ${validationState.storageValue})';
}

/// One page of section controls.
///
/// Section lists are always paged: the caller never asks for "all sections of
/// a resource" implicitly, which keeps a 60k-character resource from loading
/// its whole tree at once.
final class SectionControlPage {
  const SectionControlPage({
    required this.entries,
    required this.totalCount,
    required this.offset,
  }) : assert(offset >= 0, 'offset must not be negative');

  final List<SectionControlEntry> entries;
  final int totalCount;
  final int offset;

  bool get isEmpty => entries.isEmpty;

  int get loadedThrough => offset + entries.length;

  bool get hasMore => loadedThrough < totalCount;

  @override
  String toString() =>
      'SectionControlPage(${entries.length}/$totalCount from $offset)';
}

/// One concrete problem found while validating a section.
final class SectionValidationIssue {
  const SectionValidationIssue({
    required this.message,
    this.partId,
    this.tooLong = false,
  });

  final PartId? partId;
  final String message;

  /// Whether the issue is a length-budget overflow rather than a hole.
  final bool tooLong;

  @override
  String toString() =>
      'SectionValidationIssue(${partId?.value ?? 'section'}: $message)';
}

/// Result of validating one section.
final class SectionValidationResult {
  const SectionValidationResult({
    required this.sectionId,
    required this.state,
    this.issues = const <SectionValidationIssue>[],
    this.characterCount = 0,
  });

  final SectionId sectionId;
  final SectionValidationState state;
  final List<SectionValidationIssue> issues;
  final int characterCount;

  bool get isValid => state == SectionValidationState.valid;

  @override
  String toString() => 'SectionValidationResult(${sectionId.value}, '
      '${state.storageValue}, issues: ${issues.length}, chars: $characterCount)';
}

// ---------------------------------------------------------------------------
// Rollup
// ---------------------------------------------------------------------------

/// Maps persisted per-Part task statuses onto one section generation state.
///
/// The Phase 5 task table is the only source of truth for in-flight work, so
/// the rollup never invents a state the tasks cannot justify. Precedence is
/// `active > failed > cancelled > pending > completed`, which makes a section
/// with one running and one failed Part report "generating" while the runtime
/// is still working, and "failed" once it stops.
abstract final class SectionGenerationRollup {
  static SectionGenerationState fromTaskStatuses(
    Iterable<String> statuses, {
    required bool hasContent,
  }) {
    final values = statuses.toList(growable: false);
    if (values.isEmpty) {
      // No generation task: the section was authored outside the AI pipeline.
      return hasContent
          ? SectionGenerationState.generated
          : SectionGenerationState.pending;
    }

    var anyCompleted = false;
    var allCompleted = true;
    var anyPending = false;
    var anyFailed = false;
    var anyCancelled = false;

    for (final raw in values) {
      switch (raw) {
        case 'generating':
          return SectionGenerationState.generating;
        case 'validating':
          return SectionGenerationState.validating;
        case 'failed':
          anyFailed = true;
          allCompleted = false;
        case 'cancelled':
          anyCancelled = true;
          allCompleted = false;
        case 'pending':
        case 'ready':
          anyPending = true;
          allCompleted = false;
        case 'completed':
          anyCompleted = true;
        default:
          allCompleted = false;
      }
    }

    if (anyFailed) return SectionGenerationState.failed;
    if (anyCancelled) return SectionGenerationState.cancelled;
    if (anyPending) return SectionGenerationState.pending;
    if (anyCompleted && allCompleted) return SectionGenerationState.completed;
    return hasContent
        ? SectionGenerationState.generated
        : SectionGenerationState.pending;
  }
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

/// One Part's body, reduced to what validation needs.
///
/// Validation is deliberately structural: Phase 7 checks that a section is
/// complete and within the frozen Part budget. Semantic/LLM grading and
/// capacity compression belong to later phases.
final class SectionValidationPart {
  const SectionValidationPart({
    required this.partId,
    required this.title,
    required this.content,
  });

  final PartId partId;
  final String title;
  final String content;
}

/// Pure rules for validating one section's committed content.
abstract final class SectionContentValidator {
  static SectionValidationResult validate({
    required SectionId sectionId,
    required List<SectionValidationPart> parts,
  }) {
    final issues = <SectionValidationIssue>[];
    var characterCount = 0;

    if (parts.isEmpty) {
      return SectionValidationResult(
        sectionId: sectionId,
        state: SectionValidationState.invalid,
        issues: const [
          SectionValidationIssue(
            message: 'Section 没有任何 Part，无法构成可组装内容',
          ),
        ],
      );
    }

    for (final part in parts) {
      characterCount += part.content.length;
      if (part.content.trim().isEmpty) {
        issues.add(
          SectionValidationIssue(
            partId: part.partId,
            message:
                '${part.title.isEmpty ? part.partId.value : part.title} 尚未生成正文',
          ),
        );
        continue;
      }
      if (part.content.length > ResourceLimits.maxPartCharacters) {
        issues.add(
          SectionValidationIssue(
            partId: part.partId,
            tooLong: true,
            message: '${part.title.isEmpty ? part.partId.value : part.title} '
                '长度 ${part.content.length} 超出单 Part 上限 '
                '${ResourceLimits.maxPartCharacters}',
          ),
        );
      }
    }

    return SectionValidationResult(
      sectionId: sectionId,
      state: issues.isEmpty
          ? SectionValidationState.valid
          : SectionValidationState.invalid,
      issues: issues,
      characterCount: characterCount,
    );
  }
}
