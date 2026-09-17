import '../../domain/resources/resource_compression.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_limits.dart';
import '../../utils/token_estimator.dart';

/// Why a piece of context is being considered, highest importance first.
///
/// The order is the Phase 8 context policy: what the model is working on now,
/// then the state it must not contradict, then open threads, then recent plot,
/// and only last the historical summaries. A tighter budget therefore drops
/// history before it drops the current section.
enum ResourceContextPriority {
  currentSection(1),
  currentState(2),
  unresolvedEvents(3),
  recentPlot(4),
  historicalSummary(5);

  const ResourceContextPriority(this.rank);

  /// Lower rank is more important.
  final int rank;
}

/// One candidate piece of context, with an optional compressed form.
///
/// [compressedText] is the "compressed summary" half of the
/// active-content + summary pair: when present the packer sends it instead of
/// the full text, which is how a large current section still fits a budget.
final class ResourceContextCandidate {
  const ResourceContextCandidate({
    required this.priority,
    required this.label,
    required this.text,
    this.compressedText,
    this.order = 0,
  });

  final ResourceContextPriority priority;
  final String label;
  final String text;
  final String? compressedText;

  /// Stable tie-break inside one priority band.
  final int order;

  String get packedText {
    final compressed = compressedText?.trim() ?? '';
    if (compressed.isEmpty) return text;
    return compressed;
  }
}

/// One selected piece of context.
final class ResourceContextFragment {
  const ResourceContextFragment({
    required this.priority,
    required this.label,
    required this.text,
    required this.tokens,
    required this.wasCompressed,
  });

  final ResourceContextPriority priority;
  final String label;
  final String text;
  final int tokens;

  /// True when [text] is the candidate's compressed summary, not its full body.
  final bool wasCompressed;

  @override
  String toString() =>
      'ResourceContextFragment(${priority.name}, $label, $tokens tokens)';
}

/// The packed, budget-bounded context.
final class ResourceContextPacking {
  const ResourceContextPacking({
    required this.fragments,
    required this.droppedLabels,
    required this.budgetTokens,
    required this.ungroupedTokens,
  });

  final List<ResourceContextFragment> fragments;

  /// Labels that did not fit; reported so a caller can explain or compress
  /// further instead of silently losing them.
  final List<String> droppedLabels;

  final int budgetTokens;

  /// Total tokens of every candidate, including the dropped ones. Comparing it
  /// with [usedTokens] shows how much the packing actually saved.
  final int ungroupedTokens;

  int get usedTokens =>
      fragments.fold(0, (sum, fragment) => sum + fragment.tokens);

  int get droppedCount => droppedLabels.length;

  bool get isEmpty => fragments.isEmpty;

  /// The packing is budget-bounded by construction, so a caller may assert it.
  bool get withinBudget => usedTokens <= budgetTokens;

  @override
  String toString() => 'ResourceContextPacking(${fragments.length} fragments, '
      '$usedTokens/$budgetTokens tokens, dropped: $droppedCount)';
}

/// Priority-ordered, budget-bounded context packing.
///
/// Pure and deterministic. It selects whole fragments only: nothing is
/// substring-cut, so a fragment is either sent as its compressed summary or
/// dropped with a reason.
abstract final class ResourceContextCompressor {
  static ResourceContextPacking pack({
    required List<ResourceContextCandidate> candidates,
    int budgetTokens = ResourceLimits.resourceContextTokenBudget,
  }) {
    if (budgetTokens < 0) {
      throw ArgumentError.value(
        budgetTokens,
        'budgetTokens',
        'token budget must not be negative',
      );
    }

    final ordered = List<ResourceContextCandidate>.from(candidates)
      ..sort((a, b) {
        final byPriority = a.priority.rank.compareTo(b.priority.rank);
        if (byPriority != 0) return byPriority;
        final byOrder = a.order.compareTo(b.order);
        if (byOrder != 0) return byOrder;
        return a.label.compareTo(b.label);
      });

    final fragments = <ResourceContextFragment>[];
    final dropped = <String>[];
    var used = 0;
    var total = 0;

    for (final candidate in ordered) {
      final packed = candidate.packedText.trim();
      final tokens = TokenEstimator(packed).tokens;
      total += tokens;

      if (packed.isEmpty) {
        dropped.add(candidate.label);
        continue;
      }
      if (used + tokens > budgetTokens) {
        dropped.add(candidate.label);
        continue;
      }

      used += tokens;
      fragments.add(ResourceContextFragment(
        priority: candidate.priority,
        label: candidate.label,
        text: packed,
        tokens: tokens,
        wasCompressed: packed != candidate.text.trim(),
      ));
    }

    return ResourceContextPacking(
      fragments: fragments,
      droppedLabels: dropped,
      budgetTokens: budgetTokens,
      ungroupedTokens: total,
    );
  }
}

/// Builds priority-tagged context candidates for one resource.
///
/// Sections are split into "recent plot" (the newest few, kept as full or
/// compressed bodies) and "historical summary" (older sections, only ever sent
/// through their compressed candidate). This is what stops a long resource from
/// sending every chapter to the model.
final class ResourceContextAssembler {
  const ResourceContextAssembler({this.recentSectionCount = 2});

  /// How many of the newest sections count as "recent plot".
  final int recentSectionCount;

  /// Assembles candidates in canonical order, newest sections first.
  ///
  /// [sectionText] returns the live body for a section (null when the section
  /// has no content); [candidateSummaries] maps a section or part id to an
  /// already validated compression summary. The assembler never invents a
  /// summary: a section without one is offered as full text under the priority
  /// its recency earns.
  List<ResourceContextCandidate> assemble({
    required Resource resource,
    required List<ResourceSection> sections,
    required String currentSectionId,
    required String? Function(SectionId sectionId) sectionText,
    Map<String, String> candidateSummaries = const <String, String>{},
  }) {
    final candidates = <ResourceContextCandidate>[];

    final ordered =
        sections.where((section) => section.status != NodeStatus.archived);
    final list = ordered.toList();

    final currentIndex = list.indexWhere(
      (section) => section.id.value == currentSectionId,
    );
    final recentBoundary = currentIndex < 0
        ? list.length
        : currentIndex - recentSectionCount < 0
            ? 0
            : currentIndex - recentSectionCount;

    var order = 0;
    for (var index = 0; index < list.length; index++) {
      final section = list[index];
      final text = sectionText(section.id);
      if (text == null || text.trim().isEmpty) continue;

      final isCurrent = section.id.value == currentSectionId;
      final isRecent = index >= recentBoundary && !isCurrent;
      final priority = isCurrent
          ? ResourceContextPriority.currentSection
          : isRecent
              ? ResourceContextPriority.recentPlot
              : ResourceContextPriority.historicalSummary;

      candidates.add(ResourceContextCandidate(
        priority: priority,
        label: section.title.isEmpty ? section.id.value : section.title,
        text: text,
        compressedText: candidateSummaries[section.id.value],
        order: order++,
      ));
    }

    final summary = resource.summary.trim();
    if (summary.isNotEmpty) {
      candidates.add(ResourceContextCandidate(
        priority: ResourceContextPriority.currentState,
        label: '${resource.name} · 当前状态',
        text: summary,
        order: 0,
      ));
    }

    return candidates;
  }

  /// Assembles and immediately packs under [budgetTokens].
  ResourceContextPacking build({
    required Resource resource,
    required List<ResourceSection> sections,
    required String currentSectionId,
    required String? Function(SectionId sectionId) sectionText,
    Map<String, String> candidateSummaries = const <String, String>{},
    int budgetTokens = ResourceLimits.resourceContextTokenBudget,
  }) {
    final candidates = assemble(
      resource: resource,
      sections: sections,
      currentSectionId: currentSectionId,
      sectionText: sectionText,
      candidateSummaries: candidateSummaries,
    );
    return ResourceContextCompressor.pack(
      candidates: candidates,
      budgetTokens: budgetTokens,
    );
  }
}

/// Convenience access to the trigger that decides whether a context needs
/// compression before it is sent.
abstract final class ResourceContextTriggers {
  /// Evaluates the *unpacked* size, i.e. what would have been sent before
  /// compression. Using the packed size would always be under budget and the
  /// trigger could never fire.
  static CompressionTriggerDecision evaluate({
    required ResourceContextPacking packing,
    CompressionThresholds thresholds = CompressionThresholds.defaults,
  }) {
    return CompressionTriggers.evaluateContext(
      contextTokens: packing.ungroupedTokens,
      thresholds: thresholds,
    );
  }
}
