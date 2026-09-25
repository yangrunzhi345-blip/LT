import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../models/adventure_config.dart';
import '../../models/adventure_runtime_state.dart';
import '../../models/message.dart';
import '../../models/model_context_capability.dart';
import '../../models/persona.dart';
import '../../models/scene_state.dart';
import '../../models/supporting_character.dart';
import '../../models/world_entry.dart';
import '../../models/worldview_details.dart';
import '../../services/embedding/semantic_embedding_service.dart';
import '../../utils/token_estimator.dart';
import 'conflict_resolver.dart';
import 'user_intent.dart';
import 'world_semantic_retrieval.dart';
import 'context_weighting.dart';

enum WorldContextKind { constraint, fact, lore }

final class WorldContextItem {
  final WorldContextKind kind;
  final String content;
  final int? entryId;
  final String sourceType;
  final int score;
  final int estimatedTokens;
  final String retrievalSource;
  final double? semanticSimilarity;

  const WorldContextItem({
    required this.kind,
    required this.content,
    required this.sourceType,
    required this.score,
    required this.estimatedTokens,
    this.entryId,
    this.retrievalSource = 'deterministic',
    this.semanticSimilarity,
  });
}

final class WorldRetrievalAuditItem {
  final int? entryId;
  final String sourceType;
  final WorldContextKind classifiedKind;
  final int matchedKeys;
  final bool locationMatched;
  final bool isSticky;
  final String retrievalSource;
  final double? semanticSimilarity;
  final int score;
  final int estimatedTokens;
  final bool included;
  final String? filterReason;

  const WorldRetrievalAuditItem({
    required this.entryId,
    required this.sourceType,
    required this.classifiedKind,
    required this.matchedKeys,
    required this.locationMatched,
    required this.isSticky,
    this.retrievalSource = 'deterministic',
    this.semanticSimilarity,
    required this.score,
    required this.estimatedTokens,
    required this.included,
    this.filterReason,
  });

  WorldRetrievalAuditItem copyWith({
    int? entryId,
    String? sourceType,
    WorldContextKind? classifiedKind,
    int? matchedKeys,
    bool? locationMatched,
    bool? isSticky,
    String? retrievalSource,
    double? semanticSimilarity,
    int? score,
    int? estimatedTokens,
    bool? included,
    String? filterReason,
  }) {
    return WorldRetrievalAuditItem(
      entryId: entryId ?? this.entryId,
      sourceType: sourceType ?? this.sourceType,
      classifiedKind: classifiedKind ?? this.classifiedKind,
      matchedKeys: matchedKeys ?? this.matchedKeys,
      locationMatched: locationMatched ?? this.locationMatched,
      isSticky: isSticky ?? this.isSticky,
      retrievalSource: retrievalSource ?? this.retrievalSource,
      semanticSimilarity: semanticSimilarity ?? this.semanticSimilarity,
      score: score ?? this.score,
      estimatedTokens: estimatedTokens ?? this.estimatedTokens,
      included: included ?? this.included,
      filterReason: filterReason ?? this.filterReason,
    );
  }

  Map<String, Object?> toDiagnostics() => {
        if (entryId != null) 'entry_id': entryId,
        'source_type': sourceType,
        'classified_kind': classifiedKind.name,
        'matched_keys': matchedKeys,
        'location_matched': locationMatched,
        'sticky': isSticky,
        'retrieval_source': retrievalSource,
        if (semanticSimilarity != null)
          'semantic_similarity':
              double.parse(semanticSimilarity!.toStringAsFixed(4)),
        'score': score,
        'estimated_tokens': estimatedTokens,
        'included': included,
        if (filterReason != null) 'filter_reason': filterReason,
      };
}

final class WorldRuntimeContext {
  final List<WorldContextItem> constraints;
  final List<WorldContextItem> facts;
  final List<WorldContextItem> lore;
  final List<int> filteredEntryIds;
  final Map<int, String> filteredEntryReasons;
  final List<WorldRetrievalAuditItem> retrievalAudit;

  const WorldRuntimeContext({
    this.constraints = const [],
    this.facts = const [],
    this.lore = const [],
    this.filteredEntryIds = const [],
    this.filteredEntryReasons = const {},
    this.retrievalAudit = const [],
  });

  Iterable<WorldContextItem> get all => [
        ...constraints,
        ...facts,
        ...lore,
      ];
}

final class ContextBudget {
  final int contextWindowTokens;
  final int responseReserveTokens;
  final int inputLimitTokens;

  const ContextBudget({
    required this.contextWindowTokens,
    required this.responseReserveTokens,
    required this.inputLimitTokens,
  });

  factory ContextBudget.resolve({
    required ModelContextCapability capability,
    required int requestedResponseTokens,
  }) {
    final responseReserve = requestedResponseTokens
        .clamp(256, capability.maximumOutputTokens)
        .toInt();
    final inputLimit = (capability.maximumContextTokens - responseReserve - 512)
        .clamp(1024, capability.maximumContextTokens)
        .toInt();
    return ContextBudget(
      contextWindowTokens: capability.maximumContextTokens,
      responseReserveTokens: responseReserve,
      inputLimitTokens: inputLimit,
    );
  }
}

final class ContextTraceEntry {
  final String source;
  final int estimatedTokens;
  final String decision;
  final int? sourceId;
  final int? score;
  final int? matchedKeys;
  final bool? locationMatched;
  final bool? isSticky;
  final String? filterReason;
  final String? classifiedKind;
  final String? retrievalSource;
  final double? semanticSimilarity;

  const ContextTraceEntry({
    required this.source,
    required this.estimatedTokens,
    required this.decision,
    this.sourceId,
    this.score,
    this.matchedKeys,
    this.locationMatched,
    this.isSticky,
    this.filterReason,
    this.classifiedKind,
    this.retrievalSource,
    this.semanticSimilarity,
  });
}

/// Privacy-safe metadata for inspecting context composition in development.
final class ContextTrace {
  final List<ContextTraceEntry> entries;
  final List<String> conflictRules;
  final int totalEstimatedTokens;
  final int responseReserveTokens;
  final List<WorldRetrievalAuditItem> worldRetrieval;
  final Map<String, Object?>? allocation;

  const ContextTrace({
    required this.entries,
    required this.conflictRules,
    required this.totalEstimatedTokens,
    required this.responseReserveTokens,
    this.worldRetrieval = const [],
    this.allocation,
  });

  Map<String, Object?> toDiagnostics() => {
        'input_tokens_estimated': totalEstimatedTokens,
        'response_tokens_reserved': responseReserveTokens,
        'sources': [
          for (final entry in entries)
            {
              'source': entry.source,
              'tokens': entry.estimatedTokens,
              'decision': entry.decision,
              if (entry.sourceId != null) 'source_id': entry.sourceId,
              if (entry.score != null) 'score': entry.score,
              if (entry.matchedKeys != null) 'matched_keys': entry.matchedKeys,
              if (entry.locationMatched != null)
                'location_matched': entry.locationMatched,
              if (entry.isSticky != null) 'sticky': entry.isSticky,
              if (entry.filterReason != null)
                'filter_reason': entry.filterReason,
              if (entry.classifiedKind != null)
                'classified_kind': entry.classifiedKind,
              if (entry.retrievalSource != null)
                'retrieval_source': entry.retrievalSource,
              if (entry.semanticSimilarity != null)
                'semantic_similarity':
                    double.parse(entry.semanticSimilarity!.toStringAsFixed(4)),
            },
        ],
        if (worldRetrieval.isNotEmpty)
          'world_retrieval': [
            for (final audit in worldRetrieval) audit.toDiagnostics(),
          ],
        'conflict_rules': conflictRules,
        if (allocation != null) 'allocation': allocation,
      };
}

final class NarrativeContext {
  final NarrativeIntent intent;
  final SceneState sceneState;
  final WorldRuntimeContext world;

  /// Planner-approved current user input. It is mandatory and therefore kept
  /// intact unless the configured hard input limit cannot contain it.
  final String plannedUserInput;
  final String characterContext;

  /// Planner-approved rendering of the current scene source.
  final String plannedSceneContext;

  /// Planner-approved rendering of the complete worldview source.
  final String plannedWorldContext;
  final String personaContext;
  final RuntimeContextView runtime;
  final String? historicalSummary;
  final List<Message> recentHistory;
  final String controlContext;
  final ContextBudget budget;
  final ContextTrace trace;
  final ContextWeightProfile weightProfile;

  const NarrativeContext({
    required this.intent,
    required this.sceneState,
    required this.world,
    required this.plannedUserInput,
    required this.characterContext,
    required this.plannedSceneContext,
    required this.plannedWorldContext,
    required this.personaContext,
    required this.runtime,
    required this.historicalSummary,
    required this.recentHistory,
    required this.controlContext,
    required this.budget,
    required this.trace,
    this.weightProfile = const ContextWeightProfile(),
  });
}

/// A bounded projection of the branch-local Runtime HEAD for one prompt.
/// It never contains an entire card, snapshot, or commit archive.
final class RuntimeContextView {
  final int revision;
  final String memory;
  final String worldMemory;
  final List<String> archiveRetrievalFacts;
  final int filteredEntityCount;
  final int selectedEntityCount;

  const RuntimeContextView({
    this.revision = 0,
    this.memory = '',
    this.worldMemory = '',
    this.archiveRetrievalFacts = const [],
    this.filteredEntityCount = 0,
    this.selectedEntityCount = 0,
  });
}

/// Deterministically projects overlays into a small working-memory section.
final class RuntimeMemoryProjector {
  static const int maximumEntities = 8;
  static const int maximumTokens = 600;

  const RuntimeMemoryProjector();

  RuntimeContextView project({
    required int revision,
    required Iterable<RuntimeEntityState> entities,
    required Set<String> relevantEntityIds,
    List<String> archiveRetrievalFacts = const [],
  }) {
    final relevant = entities
        .where((entity) => relevantEntityIds.contains(entity.entityId))
        .take(maximumEntities)
        .toList(growable: false);
    String render(Iterable<RuntimeEntityState> source) {
      final lines = <String>[];
      for (final entity in source) {
        final fields = <String>[
          if (entity.lifecycleStatus != 'active')
            'lifecycle=${entity.lifecycleStatus}',
          for (final entry in entity.overlay.entries)
            '${entry.key}=${entry.value}',
        ];
        if (fields.isNotEmpty) {
          lines.add(
              '${entity.entityType.name}:${entity.entityId} — ${fields.join('；')}');
        }
      }
      // R05-C: structured trim — keep whole entity lines while they fit and
      // token-truncate only the overflowing line (surrogate-safe), instead of
      // a proportional substring that could split a line or an astral
      // character in half.
      var memory = lines.join('\n');
      if (TokenEstimator(memory).tokens > maximumTokens) {
        final buffer = StringBuffer();
        var used = 0;
        for (final line in lines) {
          final lineTokens = TokenEstimator(line).tokens + 1;
          if (used + lineTokens > maximumTokens) {
            final remaining = maximumTokens - used;
            if (remaining > 32) {
              final truncated = truncateToTokens(line, remaining);
              if (truncated.isNotEmpty) buffer.writeln(truncated);
            }
            break;
          }
          buffer.writeln(line);
          used += lineTokens;
        }
        memory = buffer.toString().trimRight();
      }
      return memory;
    }

    final characterEntities = relevant.where((entity) =>
        entity.entityType == RuntimeEntityType.character ||
        entity.entityType == RuntimeEntityType.npc ||
        entity.entityType == RuntimeEntityType.relationship);
    final worldEntities = relevant.where((entity) =>
        entity.entityType == RuntimeEntityType.world ||
        entity.entityType == RuntimeEntityType.location ||
        entity.entityType == RuntimeEntityType.faction);
    return RuntimeContextView(
      revision: revision,
      memory: render(characterEntities),
      worldMemory: render(worldEntities),
      archiveRetrievalFacts: List.unmodifiable(archiveRetrievalFacts.take(5)),
      filteredEntityCount: entities.length - relevant.length,
      selectedEntityCount: relevant.length,
    );
  }
}

/// Builds the sole runtime view of an immutable worldview asset snapshot.
enum WorldRetrievalMode {
  legacyBaseline,
  deterministicHardened,
  hybrid,
}

/// Builds the sole runtime view of an immutable worldview asset snapshot.
final class WorldContextBuilder {
  final WorldRetrievalMode mode;
  final SemanticWorldRetriever? semanticRetriever;
  final double minSimilarityThreshold;
  final int topKSemantic;

  const WorldContextBuilder({
    this.mode = WorldRetrievalMode.hybrid,
    this.semanticRetriever,
    this.minSimilarityThreshold = 0.35,
    this.topKSemantic = 8,
  });

  const WorldContextBuilder.legacy()
      : mode = WorldRetrievalMode.legacyBaseline,
        semanticRetriever = null,
        minSimilarityThreshold = 0.35,
        topKSemantic = 8;

  const WorldContextBuilder.hardened()
      : mode = WorldRetrievalMode.deterministicHardened,
        semanticRetriever = null,
        minSimilarityThreshold = 0.35,
        topKSemantic = 8;

  const WorldContextBuilder.hybrid({
    this.semanticRetriever,
    this.minSimilarityThreshold = 0.35,
    this.topKSemantic = 8,
  }) : mode = WorldRetrievalMode.hybrid;

  Future<WorldRuntimeContext> buildAsync({
    required List<WorldEntry> entries,
    required String query,
    required String location,
    required Iterable<String> characterNames,
    required int tokenBudget,
    Map<String, dynamic>? worldviewSnapshot,
    String legacyWorldview = '',
    int? adventureId,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    List<SemanticCandidate>? candidates;
    if (semanticRetriever != null && mode == WorldRetrievalMode.hybrid) {
      final effectiveEntries = entries.isNotEmpty
          ? entries
          : _fallbackEntries(worldviewSnapshot, legacyWorldview);
      try {
        candidates = await semanticRetriever!
            .retrieve(
              query: query,
              entries: effectiveEntries,
              adventureId: adventureId,
              minSimilarity: minSimilarityThreshold,
              topK: topKSemantic,
              classifier: (e) => _classify(e, mode),
            )
            .timeout(timeout);
      } catch (e) {
        debugPrint(
            '[WorldContextBuilder] Semantic retrieval timed out or failed: $e');
        candidates = const [];
      }
    }
    return build(
      entries: entries,
      query: query,
      location: location,
      characterNames: characterNames,
      tokenBudget: tokenBudget,
      worldviewSnapshot: worldviewSnapshot,
      legacyWorldview: legacyWorldview,
      semanticCandidates: candidates,
      adventureId: adventureId,
    );
  }

  WorldRuntimeContext build({
    required List<WorldEntry> entries,
    required String query,
    required String location,
    required Iterable<String> characterNames,
    required int tokenBudget,
    Map<String, dynamic>? worldviewSnapshot,
    String legacyWorldview = '',
    List<SemanticCandidate>? semanticCandidates,
    int? adventureId,
  }) {
    final effectiveEntries = entries.isNotEmpty
        ? entries
        : _fallbackEntries(worldviewSnapshot, legacyWorldview);
    final searchText = [query, location, ...characterNames]
        .where((value) => value.trim().isNotEmpty)
        .join(' ')
        .toLowerCase();
    final seen = <String>{};
    final candidates = <WorldContextItem>[];
    final filtered = <int>[];
    final filteredReasons = <int, String>{};
    final auditItems = <WorldRetrievalAuditItem>[];
    final candidateAudits = <WorldContextItem, WorldRetrievalAuditItem>{};

    if (mode == WorldRetrievalMode.legacyBaseline) {
      return _buildLegacy(
        effectiveEntries: effectiveEntries,
        searchText: searchText,
        location: location,
        tokenBudget: tokenBudget,
      );
    }

    // Resolve semantic similarities in hybrid mode
    final semanticMap = <int, double>{};
    if (mode == WorldRetrievalMode.hybrid) {
      if (semanticCandidates != null) {
        for (final cand in semanticCandidates) {
          if (cand.entry.id case final id?) {
            semanticMap[id] = cand.similarity;
          }
        }
      } else if (semanticRetriever != null && query.trim().isNotEmpty) {
        // Fast synchronous deterministic pseudo-dense vector generation
        final service = semanticRetriever!.embeddingService;
        final qVec = DeterministicFakeEmbeddingService.generateVector(
          query.trim(),
          service.dimensions,
        );
        final scored = <(int, double)>[];
        for (final entry in effectiveEntries) {
          if (!entry.enabled || entry.content.trim().isEmpty) continue;
          final entryId = entry.id;
          if (entryId == null) continue;
          final eVec = DeterministicFakeEmbeddingService.generateVector(
            entry.content.trim(),
            service.dimensions,
          );
          final sim = cosineSimilarity(qVec, eVec);
          if (sim >= minSimilarityThreshold) {
            scored.add((entryId, sim));
          }
        }
        // Tie-break on entry id so equal scores keep a deterministic order.
        scored.sort((a, b) {
          final bySim = b.$2.compareTo(a.$2);
          return bySim != 0 ? bySim : a.$1.compareTo(b.$1);
        });
        for (final pair in scored.take(topKSemantic)) {
          semanticMap[pair.$1] = pair.$2;
        }
      }
    }

    for (final entry in effectiveEntries.where((entry) => entry.enabled)) {
      final normalized = _normalize(entry.content);
      final kind = _classify(entry, mode);
      if (normalized.isEmpty || !seen.add(normalized)) {
        if (entry.id case final id?) {
          filtered.add(id);
          filteredReasons[id] = 'duplicate';
          auditItems.add(WorldRetrievalAuditItem(
            entryId: id,
            sourceType:
                entry.sourceType.isEmpty ? 'world_entry' : entry.sourceType,
            classifiedKind: kind,
            matchedKeys: 0,
            locationMatched: false,
            isSticky: entry.sticky > 0,
            retrievalSource: 'deterministic',
            score: 0,
            estimatedTokens: TokenEstimator(entry.content).tokens,
            included: false,
            filterReason: 'duplicate',
          ));
        }
        continue;
      }

      final matchedKeys = entry.keys
          .where((key) => key.trim().isNotEmpty)
          .where((key) => searchText.contains(key.toLowerCase()))
          .length;
      final aliasMatched = _matchesContentAlias(searchText, entry.content);
      final locationMatched = location.isNotEmpty &&
          (entry.content.contains(location) ||
              _matchLocationHierarchy(location, entry));
      final characterMatched = characterNames.any((name) =>
          name.trim().isNotEmpty &&
          (entry.keys.contains(name) || entry.content.contains(name)));

      final isDeterministicHit = kind == WorldContextKind.constraint ||
          entry.sticky > 0 ||
          matchedKeys > 0 ||
          aliasMatched ||
          locationMatched ||
          characterMatched;

      final semanticSim = entry.id != null ? semanticMap[entry.id!] : null;
      final isSemanticHit =
          semanticSim != null && semanticSim >= minSimilarityThreshold;

      final isRelevant = isDeterministicHit || isSemanticHit;

      final retrievalSource = (isDeterministicHit && isSemanticHit)
          ? 'hybrid'
          : (isSemanticHit ? 'semantic' : 'deterministic');

      final baseScore = switch (kind) {
        WorldContextKind.constraint => 1000,
        WorldContextKind.fact => 500,
        WorldContextKind.lore => 100,
      };

      final detScore = (matchedKeys + (aliasMatched ? 1 : 0)) * 50 +
          (locationMatched ? 60 : 0) +
          (characterMatched ? 60 : 0) +
          (entry.sticky > 0 ? 25 : 0);

      final semScore = isSemanticHit ? (semanticSim * 200).round() : 0;

      final hybridBonus = (retrievalSource == 'hybrid') ? 30 : 0;
      final orderPenalty = entry.insertionOrder.clamp(0, 100);

      final score =
          baseScore + detScore + semScore + hybridBonus - orderPenalty;
      final tokens = TokenEstimator(entry.content).tokens;

      if (!isRelevant) {
        if (entry.id case final id?) {
          filtered.add(id);
          filteredReasons[id] = 'irrelevant';
          auditItems.add(WorldRetrievalAuditItem(
            entryId: id,
            sourceType:
                entry.sourceType.isEmpty ? 'world_entry' : entry.sourceType,
            classifiedKind: kind,
            matchedKeys: matchedKeys,
            locationMatched: locationMatched,
            isSticky: entry.sticky > 0,
            retrievalSource: retrievalSource,
            semanticSimilarity: semanticSim,
            score: score,
            estimatedTokens: tokens,
            included: false,
            filterReason: 'irrelevant',
          ));
        }
        continue;
      }

      final item = WorldContextItem(
        kind: kind,
        content: entry.content.trim(),
        entryId: entry.id,
        sourceType: entry.sourceType.isEmpty ? 'world_entry' : entry.sourceType,
        score: score,
        estimatedTokens: tokens,
        retrievalSource: retrievalSource,
        semanticSimilarity: semanticSim,
      );
      candidates.add(item);
      candidateAudits[item] = WorldRetrievalAuditItem(
        entryId: entry.id,
        sourceType: entry.sourceType.isEmpty ? 'world_entry' : entry.sourceType,
        classifiedKind: kind,
        matchedKeys: matchedKeys,
        locationMatched: locationMatched,
        isSticky: entry.sticky > 0,
        retrievalSource: retrievalSource,
        semanticSimilarity: semanticSim,
        score: score,
        estimatedTokens: tokens,
        included: false,
      );
    }

    // R05-C: stable ordering — score first, entry id as deterministic
    // tie-break, so repeated assemblies of the same DB state select the same
    // entries even when scores are equal.
    candidates.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return (a.entryId ?? -1).compareTo(b.entryId ?? -1);
    });
    return _selectWithinBudget(
      candidates: candidates,
      candidateAudits: candidateAudits,
      auditItems: auditItems,
      filtered: filtered,
      filteredReasons: filteredReasons,
      tokenBudget: tokenBudget,
    );
  }

  WorldRuntimeContext _buildLegacy({
    required List<WorldEntry> effectiveEntries,
    required String searchText,
    required String location,
    required int tokenBudget,
  }) {
    final seen = <String>{};
    final candidates = <WorldContextItem>[];
    final filtered = <int>[];
    final filteredReasons = <int, String>{};
    final auditItems = <WorldRetrievalAuditItem>[];
    final candidateAudits = <WorldContextItem, WorldRetrievalAuditItem>{};

    for (final entry in effectiveEntries.where((entry) => entry.enabled)) {
      final normalized = _normalize(entry.content);
      if (normalized.isEmpty || !seen.add(normalized)) {
        if (entry.id case final id?) {
          filtered.add(id);
          filteredReasons[id] = 'duplicate';
          auditItems.add(WorldRetrievalAuditItem(
            entryId: id,
            sourceType:
                entry.sourceType.isEmpty ? 'world_entry' : entry.sourceType,
            classifiedKind: _classify(entry, WorldRetrievalMode.legacyBaseline),
            matchedKeys: 0,
            locationMatched: false,
            isSticky: entry.sticky > 0,
            score: 0,
            estimatedTokens: TokenEstimator(entry.content).tokens,
            included: false,
            filterReason: 'duplicate',
          ));
        }
        continue;
      }
      final kind = _classify(entry, WorldRetrievalMode.legacyBaseline);
      final matchedKeys = entry.keys
          .where((key) => key.trim().isNotEmpty)
          .where((key) => searchText.contains(key.toLowerCase()))
          .length;
      final locationMatched =
          location.isNotEmpty && entry.content.contains(location);
      final isRelevant = kind == WorldContextKind.constraint ||
          entry.sticky > 0 ||
          matchedKeys > 0 ||
          locationMatched;
      final score = switch (kind) {
            WorldContextKind.constraint => 1000,
            WorldContextKind.fact => 500,
            WorldContextKind.lore => 100,
          } +
          matchedKeys * 50 +
          (entry.sticky > 0 ? 25 : 0) -
          entry.insertionOrder.clamp(0, 100);
      final tokens = TokenEstimator(entry.content).tokens;

      if (!isRelevant) {
        if (entry.id case final id?) {
          filtered.add(id);
          filteredReasons[id] = 'irrelevant';
          auditItems.add(WorldRetrievalAuditItem(
            entryId: id,
            sourceType:
                entry.sourceType.isEmpty ? 'world_entry' : entry.sourceType,
            classifiedKind: kind,
            matchedKeys: matchedKeys,
            locationMatched: locationMatched,
            isSticky: entry.sticky > 0,
            score: score,
            estimatedTokens: tokens,
            included: false,
            filterReason: 'irrelevant',
          ));
        }
        continue;
      }

      final item = WorldContextItem(
        kind: kind,
        content: entry.content.trim(),
        entryId: entry.id,
        sourceType: entry.sourceType.isEmpty ? 'world_entry' : entry.sourceType,
        score: score,
        estimatedTokens: tokens,
      );
      candidates.add(item);
      candidateAudits[item] = WorldRetrievalAuditItem(
        entryId: entry.id,
        sourceType: entry.sourceType.isEmpty ? 'world_entry' : entry.sourceType,
        classifiedKind: kind,
        matchedKeys: matchedKeys,
        locationMatched: locationMatched,
        isSticky: entry.sticky > 0,
        score: score,
        estimatedTokens: tokens,
        included: false,
      );
    }

    // R05-C: stable ordering, see the hardened path above.
    candidates.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return (a.entryId ?? -1).compareTo(b.entryId ?? -1);
    });
    return _selectWithinBudget(
      candidates: candidates,
      candidateAudits: candidateAudits,
      auditItems: auditItems,
      filtered: filtered,
      filteredReasons: filteredReasons,
      tokenBudget: tokenBudget,
    );
  }

  /// Single budget boundary shared by hardened/hybrid/legacy selection.
  ///
  /// R05-C: constraint-classified entries previously bypassed the budget
  /// entirely, so one huge constraint could push the prompt past the input
  /// limit. Constraints still win by score (base 1000 sorts them first), but
  /// the budget itself is now a hard limit for every kind: an entry that no
  /// longer fits is dropped whole (never mid-entry) and recorded as
  /// 'token_budget' in the trace.
  WorldRuntimeContext _selectWithinBudget({
    required List<WorldContextItem> candidates,
    required Map<WorldContextItem, WorldRetrievalAuditItem> candidateAudits,
    required List<WorldRetrievalAuditItem> auditItems,
    required List<int> filtered,
    required Map<int, String> filteredReasons,
    required int tokenBudget,
  }) {
    final selected = <WorldContextItem>[];
    var used = 0;
    for (final item in candidates) {
      final audit = candidateAudits[item]!;
      if (used + item.estimatedTokens > tokenBudget) {
        if (item.entryId case final id?) {
          filtered.add(id);
          filteredReasons[id] = 'token_budget';
        }
        auditItems.add(audit.copyWith(
          included: false,
          filterReason: 'token_budget',
        ));
        continue;
      }
      selected.add(item);
      used += item.estimatedTokens;
      auditItems.add(audit.copyWith(
        included: true,
      ));
    }
    return WorldRuntimeContext(
      constraints: selected
          .where((item) => item.kind == WorldContextKind.constraint)
          .toList(growable: false),
      facts: selected
          .where((item) => item.kind == WorldContextKind.fact)
          .toList(growable: false),
      lore: selected
          .where((item) => item.kind == WorldContextKind.lore)
          .toList(growable: false),
      filteredEntryIds: List.unmodifiable(filtered),
      filteredEntryReasons: Map.unmodifiable(filteredReasons),
      retrievalAudit: List.unmodifiable(auditItems),
    );
  }

  bool _matchesContentAlias(String searchText, String content) {
    if (searchText.isEmpty || content.isEmpty) return false;
    final aliasRegex = RegExp(r'[（(](?:俗称|简称|又名|又称|aka)\s*([^）)]+)[）)]');
    for (final match in aliasRegex.allMatches(content)) {
      final alias = match.group(1)?.trim().toLowerCase();
      if (alias != null && alias.length >= 2 && searchText.contains(alias)) {
        return true;
      }
    }
    return false;
  }

  bool _matchLocationHierarchy(String location, WorldEntry entry) {
    if (location.isEmpty) return false;
    final isLocationType = entry.sourceType == 'location' ||
        entry.content.contains('【世界观/locations】');
    if (!isLocationType) return false;

    for (final key in entry.keys) {
      final k = key.trim();
      if (k.length >= 2 && (location.contains(k) || k.contains(location))) {
        return true;
      }
    }

    final maxLen = min(4, location.length);
    for (var len = maxLen; len >= 2; len--) {
      final prefix = location.substring(0, len);
      if (entry.content.contains(prefix)) {
        return true;
      }
    }

    return false;
  }

  WorldContextKind _classify(WorldEntry entry, WorldRetrievalMode mode) {
    final content = entry.content;
    if (mode == WorldRetrievalMode.legacyBaseline) {
      if (content.startsWith('【世界观/世界规则】') || entry.sourceType == 'rule') {
        return WorldContextKind.constraint;
      }
      if (content.contains('【世界观/当前世界状态】') ||
          content.contains('【世界观/locations】') ||
          content.contains('【世界观/factions】') ||
          entry.sourceType == 'location' ||
          entry.sourceType == 'faction') {
        return WorldContextKind.fact;
      }
      return WorldContextKind.lore;
    }

    // Hardened and Hybrid classification
    if (content.startsWith('【世界观/世界规则】') ||
        content.startsWith('【世界观/创作约束】') ||
        entry.sourceType == 'rule' ||
        entry.sourceType == 'constraint' ||
        entry.keys.contains('世界规则') ||
        entry.keys.contains('创作约束')) {
      return WorldContextKind.constraint;
    }
    if (content.contains('【世界观/当前世界状态】') ||
        content.contains('【世界观/locations】') ||
        content.contains('【世界观/factions】') ||
        entry.sourceType == 'location' ||
        entry.sourceType == 'faction') {
      return WorldContextKind.fact;
    }
    return WorldContextKind.lore;
  }

  List<WorldEntry> _fallbackEntries(
    Map<String, dynamic>? snapshot,
    String legacyWorldview,
  ) {
    final detailJson = snapshot?['detail_json'];
    final details = WorldviewDetails.fromJson(
      detailJson is Map ? Map<String, dynamic>.from(detailJson) : null,
      fallbackDescription:
          snapshot?['description']?.toString() ?? legacyWorldview,
    );
    final entries = <WorldEntry>[];
    for (final module in details.confirmedModules().entries) {
      entries.add(WorldEntry(
        keys: [module.key],
        content: '【世界观/${module.key}】${module.value}',
        sticky: module.key == 'world_rules' ? 1 : 0,
        sourceType: 'worldview_snapshot_runtime',
      ));
    }
    if (entries.isEmpty && legacyWorldview.trim().isNotEmpty) {
      entries.add(WorldEntry(
        content: '【世界观/概览】${legacyWorldview.trim()}',
        sticky: 1,
        sourceType: 'legacy_worldview_runtime',
      ));
    }
    return entries;
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'[，。！？、；：,.!?;:\-—_\[\]【】]'), '');
}

/// Coordinates runtime sources and applies a single budget before prompting.
final class ContextOrchestrator {
  final IntentResolver intentResolver;
  final NarrativeConflictResolver conflictResolver;
  final WorldContextBuilder worldBuilder;
  final RuntimeMemoryProjector runtimeProjector;

  const ContextOrchestrator({
    this.intentResolver = const IntentResolver(),
    this.conflictResolver = const NarrativeConflictResolver(),
    this.worldBuilder = const WorldContextBuilder(),
    this.runtimeProjector = const RuntimeMemoryProjector(),
  });

  NarrativeContext build({
    required String rawInput,
    required AdventureConfig? config,
    required SceneState sceneState,
    required List<WorldEntry> worldEntries,
    required List<Message> messages,
    required String? summary,
    required Persona? persona,
    required ModelContextCapability capability,
    required int requestedResponseTokens,
    String controlContext = '',
    int runtimePolicyTokens = 0,
    int runtimeRevision = 0,
    List<RuntimeEntityState> runtimeEntities = const [],
    List<String> archiveRetrievalFacts = const [],
    int? adventureId,
    ContextWeightProfile weightProfile = const ContextWeightProfile(),
  }) {
    final knownCharacters = <String, String>{
      'protagonist': config?.name ?? '主角',
      for (final character in _legacySupportingCharacters(config))
        character.id: character.name,
      for (final character in config?.selectedCharacters ?? const [])
        character.characterId: character.characterName,
    };
    final intent = intentResolver.resolve(
      rawInput,
      knownCharacters: knownCharacters,
    );
    final conflict = conflictResolver.resolve(sceneState, intent);
    final budget = ContextBudget.resolve(
      capability: capability,
      requestedResponseTokens: requestedResponseTokens,
    );
    final mandatoryTokens = TokenEstimator(rawInput).tokens +
        TokenEstimator(controlContext).tokens +
        runtimePolicyTokens.clamp(0, budget.inputLimitTokens).toInt() +
        512;
    final worldBudget = _sourceBudget(
      budget.inputLimitTokens - mandatoryTokens,
      weightProfile[ContextSourceId.worldview],
      minimum: 128,
      maximum: 4096,
      divisor: 4,
    );
    final world = worldBuilder.build(
      entries: worldEntries,
      query: rawInput,
      location: conflict.sceneState.location,
      characterNames: knownCharacters.entries
          .where((entry) =>
              conflict.sceneState.presentCharacterIds.contains(entry.key) ||
              rawInput.contains(entry.value))
          .map((entry) => entry.value),
      tokenBudget: worldBudget,
      worldviewSnapshot: config?.worldviewSnapshot,
      legacyWorldview: config?.worldview ?? '',
      adventureId: adventureId,
    );
    return _assembleContext(
      rawInput: rawInput,
      config: config,
      conflict: conflict,
      intent: intent,
      budget: budget,
      world: world,
      mandatoryTokens: mandatoryTokens,
      controlContext: controlContext,
      runtimePolicyTokens: runtimePolicyTokens,
      runtimeRevision: runtimeRevision,
      runtimeEntities: runtimeEntities,
      archiveRetrievalFacts: archiveRetrievalFacts,
      knownCharacters: knownCharacters,
      messages: messages,
      summary: summary,
      persona: persona,
      weightProfile: weightProfile,
    );
  }

  /// Non-blocking asynchronous assembly of narrative context with semantic retrieval.
  /// Enforces [semanticTimeout] to protect UI responsiveness on mobile devices.
  Future<NarrativeContext> buildAsync({
    required String rawInput,
    required AdventureConfig? config,
    required SceneState sceneState,
    required List<WorldEntry> worldEntries,
    required List<Message> messages,
    required String? summary,
    required Persona? persona,
    required ModelContextCapability capability,
    required int requestedResponseTokens,
    String controlContext = '',
    int runtimePolicyTokens = 0,
    int runtimeRevision = 0,
    List<RuntimeEntityState> runtimeEntities = const [],
    List<String> archiveRetrievalFacts = const [],
    int? adventureId,
    Duration semanticTimeout = const Duration(seconds: 3),
    ContextWeightProfile weightProfile = const ContextWeightProfile(),
  }) async {
    final knownCharacters = <String, String>{
      'protagonist': config?.name ?? '主角',
      for (final character in _legacySupportingCharacters(config))
        character.id: character.name,
      for (final character in config?.selectedCharacters ?? const [])
        character.characterId: character.characterName,
    };
    final intent = intentResolver.resolve(
      rawInput,
      knownCharacters: knownCharacters,
    );
    final conflict = conflictResolver.resolve(sceneState, intent);
    final budget = ContextBudget.resolve(
      capability: capability,
      requestedResponseTokens: requestedResponseTokens,
    );
    final mandatoryTokens = TokenEstimator(rawInput).tokens +
        TokenEstimator(controlContext).tokens +
        runtimePolicyTokens.clamp(0, budget.inputLimitTokens).toInt() +
        512;
    final worldBudget = _sourceBudget(
      budget.inputLimitTokens - mandatoryTokens,
      weightProfile[ContextSourceId.worldview],
      minimum: 128,
      maximum: 4096,
      divisor: 4,
    );
    final world = await worldBuilder.buildAsync(
      entries: worldEntries,
      query: rawInput,
      location: conflict.sceneState.location,
      characterNames: knownCharacters.entries
          .where((entry) =>
              conflict.sceneState.presentCharacterIds.contains(entry.key) ||
              rawInput.contains(entry.value))
          .map((entry) => entry.value),
      tokenBudget: worldBudget,
      worldviewSnapshot: config?.worldviewSnapshot,
      legacyWorldview: config?.worldview ?? '',
      adventureId: adventureId,
      timeout: semanticTimeout,
    );
    return _assembleContext(
      rawInput: rawInput,
      config: config,
      conflict: conflict,
      intent: intent,
      budget: budget,
      world: world,
      mandatoryTokens: mandatoryTokens,
      controlContext: controlContext,
      runtimePolicyTokens: runtimePolicyTokens,
      runtimeRevision: runtimeRevision,
      runtimeEntities: runtimeEntities,
      archiveRetrievalFacts: archiveRetrievalFacts,
      knownCharacters: knownCharacters,
      messages: messages,
      summary: summary,
      persona: persona,
      weightProfile: weightProfile,
    );
  }

  NarrativeContext _assembleContext({
    required String rawInput,
    required AdventureConfig? config,
    required ConflictResolution conflict,
    required NarrativeIntent intent,
    required ContextBudget budget,
    required WorldRuntimeContext world,
    required int mandatoryTokens,
    required String controlContext,
    required int runtimePolicyTokens,
    required int runtimeRevision,
    required List<RuntimeEntityState> runtimeEntities,
    required List<String> archiveRetrievalFacts,
    required Map<String, String> knownCharacters,
    required List<Message> messages,
    required String? summary,
    required Persona? persona,
    required ContextWeightProfile weightProfile,
  }) {
    final rawCharacterContext = _buildCharacterContext(
      config,
      conflict.sceneState,
      rawInput,
      knownCharacters,
    );
    // R05-C (M13): character context is deducted from the budget but was
    // never truncated, so a huge card could consume the whole input window
    // and silently push summary/history out. Bound it to a fixed share of
    // the disposable budget, after system/policy and the current turn.
    final disposableTokens = budget.inputLimitTokens - mandatoryTokens;
    final characterBudget = _sourceBudget(
      disposableTokens,
      weightProfile[ContextSourceId.characterProfile],
      minimum: 128,
      maximum: 2048,
      divisor: 4,
    );
    final characterFallback =
        truncateToTokens(rawCharacterContext, characterBudget);
    final runtime = runtimeProjector.project(
      revision: runtimeRevision,
      entities: runtimeEntities,
      relevantEntityIds: {
        ...conflict.sceneState.presentCharacterIds,
        for (final entry in knownCharacters.entries)
          if (rawInput.contains(entry.value)) entry.key,
      },
      archiveRetrievalFacts: archiveRetrievalFacts,
    );
    const planner = WeightedContextPlanner();
    final worldText = _renderWorldPrompt(world);
    final archiveText = runtime.archiveRetrievalFacts.join('\n');
    final sceneText = [
      conflict.sceneState.location,
      conflict.sceneState.time,
      ...conflict.sceneState.activeGoals.map((goal) => goal.description),
    ].where((value) => value.trim().isNotEmpty).join('\n');
    final sourceHistory = messages
        .where((message) =>
            !(message.isUser && message.content.trim() == rawInput.trim()))
        .toList(growable: false);
    final historyWindow = sourceHistory.length <= 12
        ? sourceHistory
        : sourceHistory.sublist(sourceHistory.length - 12);
    final recentText =
        historyWindow.map((message) => message.content).join('\n');
    final allocationPlan = planner.plan(
      inputLimitTokens: (budget.inputLimitTokens -
              mandatoryTokens +
              TokenEstimator(rawInput).tokens)
          .clamp(0, budget.inputLimitTokens),
      profile: weightProfile,
      candidates: [
        // rawInput is captured per turn and cannot be const.
        // ignore: prefer_const_constructors
        ContextCandidate(
          source: ContextSourceId.userControl,
          content: rawInput,
          policy: const ContextSourcePolicy(
            priority: ContextSourcePriority.mandatory,
            minimumTokens: 0,
            maximumTokens: 1 << 30,
          ),
        ),
        ContextCandidate(
          source: ContextSourceId.worldview,
          content: worldText,
          policy: const ContextSourcePolicy(
            priority: ContextSourcePriority.core,
            minimumTokens: 128,
            maximumTokens: 4096,
          ),
        ),
        ContextCandidate(
          source: ContextSourceId.currentScene,
          content: sceneText,
          policy: const ContextSourcePolicy(
            priority: ContextSourcePriority.mandatory,
            minimumTokens: 0,
            maximumTokens: 1024,
          ),
        ),
        ContextCandidate(
          source: ContextSourceId.runtimeWorldState,
          content: runtime.worldMemory,
          policy: const ContextSourcePolicy(
            priority: ContextSourcePriority.core,
            minimumTokens: 0,
            maximumTokens: 1024,
          ),
        ),
        ContextCandidate(
          source: ContextSourceId.characterProfile,
          content: rawCharacterContext,
          policy: const ContextSourcePolicy(
            priority: ContextSourcePriority.core,
            minimumTokens: 128,
            maximumTokens: 2048,
          ),
        ),
        ContextCandidate(
          source: ContextSourceId.historicalSummary,
          content: summary ?? '',
          policy: const ContextSourcePolicy(
            priority: ContextSourcePriority.supporting,
            minimumTokens: 0,
            maximumTokens: 2048,
          ),
        ),
        ContextCandidate(
          source: ContextSourceId.runtimeCharacterState,
          content: runtime.memory,
          policy: const ContextSourcePolicy(
            priority: ContextSourcePriority.core,
            minimumTokens: 0,
            maximumTokens: RuntimeMemoryProjector.maximumTokens,
          ),
        ),
        ContextCandidate(
          source: ContextSourceId.archiveRetrieval,
          content: archiveText,
          policy: const ContextSourcePolicy(
            priority: ContextSourcePriority.supporting,
            minimumTokens: 0,
            maximumTokens: 1024,
          ),
        ),
        ContextCandidate(
          source: ContextSourceId.recentDialogue,
          content: recentText,
          policy: const ContextSourcePolicy(
            priority: ContextSourcePriority.supporting,
            minimumTokens: 0,
            maximumTokens: 4096,
          ),
        ),
      ],
    );
    String planned(ContextSourceId source, String fallback) =>
        allocationPlan.allocations
            .where((item) => item.source == source)
            .firstOrNull
            ?.content ??
        fallback;
    final characterContext =
        planned(ContextSourceId.characterProfile, characterFallback);
    final plannedUserInput = planned(ContextSourceId.userControl, rawInput);
    final plannedSceneContext =
        planned(ContextSourceId.currentScene, sceneText);
    final plannedWorldContext = planned(ContextSourceId.worldview, worldText);
    final runtimeMemory =
        planned(ContextSourceId.runtimeCharacterState, runtime.memory);
    final runtimeWorldMemory =
        planned(ContextSourceId.runtimeWorldState, runtime.worldMemory);
    final archiveFacts = planned(ContextSourceId.archiveRetrieval, archiveText)
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);
    final worldTokens = world.all.fold<int>(
      0,
      (sum, item) => sum + item.estimatedTokens,
    );
    var remaining = budget.inputLimitTokens -
        mandatoryTokens -
        worldTokens -
        TokenEstimator(characterContext).tokens -
        TokenEstimator(runtimeMemory).tokens -
        archiveFacts.fold<int>(
          0,
          (sum, fact) => sum + TokenEstimator(fact).tokens,
        );
    final rawPersona = persona?.toPromptString() ?? '';
    final personaContext = _truncateToTokens(
      rawPersona,
      _sourceBudget(remaining, weightProfile[ContextSourceId.characterProfile],
          minimum: 0, maximum: 1024, divisor: 8),
    );
    remaining -= TokenEstimator(personaContext).tokens;
    final effectiveSummary = planned(ContextSourceId.historicalSummary, '');

    final retainMessageCount = _sourceBudget(
      12,
      weightProfile[ContextSourceId.recentDialogue],
      minimum: 2,
      maximum: 12,
      divisor: 1,
    );
    final history = List<Message>.from(messages);
    if (history.lastOrNull case final last?
        when last.isUser && last.content.trim() == rawInput.trim()) {
      history.removeLast();
    }
    var recent = history.length <= retainMessageCount
        ? history
        : history.sublist(history.length - retainMessageCount);
    var recentTokens = recent.fold<int>(
      0,
      (sum, message) => sum + TokenEstimator(message.content).tokens,
    );
    final fixedTokens = worldTokens +
        TokenEstimator(characterContext).tokens +
        TokenEstimator(runtimeMemory).tokens +
        archiveFacts.fold<int>(
          0,
          (sum, fact) => sum + TokenEstimator(fact).tokens,
        ) +
        TokenEstimator(personaContext).tokens +
        TokenEstimator(effectiveSummary).tokens +
        mandatoryTokens;
    // R05-C: the retained window itself must fit the remaining budget.
    // Previously only the fixed context was subtracted, so the drop-oldest
    // loop never fired and twelve long messages could exceed the input
    // limit. Drop from the oldest end until the window fits.
    final historyBudget = budget.inputLimitTokens - fixedTokens;
    while (recent.isNotEmpty && recentTokens > historyBudget) {
      recentTokens -= TokenEstimator(recent.first.content).tokens;
      recent = recent.sublist(1);
    }

    final traceEntries = <ContextTraceEntry>[
      ContextTraceEntry(
        source: 'runtime_policy',
        estimatedTokens: runtimePolicyTokens,
        decision: runtimePolicyTokens == 0 ? 'not_reported' : 'reserved',
      ),
      for (final item in world.all)
        ContextTraceEntry(
          source: 'world:${item.kind.name}:${item.sourceType}',
          sourceId: item.entryId,
          estimatedTokens: item.estimatedTokens,
          decision: 'included',
          score: item.score,
          matchedKeys: world.retrievalAudit
              .where((a) => a.entryId == item.entryId)
              .firstOrNull
              ?.matchedKeys,
          locationMatched: world.retrievalAudit
              .where((a) => a.entryId == item.entryId)
              .firstOrNull
              ?.locationMatched,
          isSticky: world.retrievalAudit
              .where((a) => a.entryId == item.entryId)
              .firstOrNull
              ?.isSticky,
          classifiedKind: item.kind.name,
          retrievalSource: world.retrievalAudit
              .where((a) => a.entryId == item.entryId)
              .firstOrNull
              ?.retrievalSource,
          semanticSimilarity: world.retrievalAudit
              .where((a) => a.entryId == item.entryId)
              .firstOrNull
              ?.semanticSimilarity,
        ),
      for (final entry in world.filteredEntryReasons.entries)
        ContextTraceEntry(
          source: 'world:filtered',
          sourceId: entry.key,
          estimatedTokens: 0,
          decision: 'filtered:${entry.value}',
          score: world.retrievalAudit
              .where((a) => a.entryId == entry.key)
              .firstOrNull
              ?.score,
          matchedKeys: world.retrievalAudit
              .where((a) => a.entryId == entry.key)
              .firstOrNull
              ?.matchedKeys,
          locationMatched: world.retrievalAudit
              .where((a) => a.entryId == entry.key)
              .firstOrNull
              ?.locationMatched,
          isSticky: world.retrievalAudit
              .where((a) => a.entryId == entry.key)
              .firstOrNull
              ?.isSticky,
          filterReason: entry.value,
          classifiedKind: world.retrievalAudit
              .where((a) => a.entryId == entry.key)
              .firstOrNull
              ?.classifiedKind
              .name,
          retrievalSource: world.retrievalAudit
              .where((a) => a.entryId == entry.key)
              .firstOrNull
              ?.retrievalSource,
          semanticSimilarity: world.retrievalAudit
              .where((a) => a.entryId == entry.key)
              .firstOrNull
              ?.semanticSimilarity,
        ),
      ContextTraceEntry(
        source: 'character_runtime',
        estimatedTokens: TokenEstimator(characterContext).tokens,
        decision: characterContext.isEmpty
            ? 'empty'
            : characterContext.length == rawCharacterContext.length
                ? 'included'
                : 'truncated',
      ),
      ContextTraceEntry(
        source: 'runtime_head',
        estimatedTokens: TokenEstimator(runtimeMemory).tokens,
        decision: runtimeMemory.isEmpty
            ? 'empty:selected:${runtime.selectedEntityCount}'
            : 'included:r${runtime.revision}:selected:${runtime.selectedEntityCount}',
      ),
      ContextTraceEntry(
        source: 'archive_retrieval',
        estimatedTokens: archiveFacts.fold<int>(
            0, (sum, fact) => sum + TokenEstimator(fact).tokens),
        decision:
            archiveFacts.isEmpty ? 'empty' : 'included:${archiveFacts.length}',
      ),
      ContextTraceEntry(
        source: 'persona_runtime',
        estimatedTokens: TokenEstimator(personaContext).tokens,
        decision: rawPersona.isEmpty
            ? 'empty'
            : personaContext.length == rawPersona.length
                ? 'included'
                : 'truncated',
      ),
      ContextTraceEntry(
        source: 'historical_summary',
        estimatedTokens: TokenEstimator(effectiveSummary).tokens,
        decision: summary?.trim().isNotEmpty != true
            ? 'empty'
            : effectiveSummary.length == summary!.length
                ? 'included'
                : 'truncated',
      ),
      ContextTraceEntry(
        source: 'recent_history',
        estimatedTokens: recent.fold<int>(
          0,
          (sum, message) => sum + TokenEstimator(message.content).tokens,
        ),
        decision: 'included:${recent.length}',
      ),
      ContextTraceEntry(
        source: 'current_user_input',
        estimatedTokens: TokenEstimator(rawInput).tokens,
        decision: 'protected',
      ),
    ];
    final total = traceEntries.fold<int>(
      0,
      (sum, entry) => sum + entry.estimatedTokens,
    );
    final trace = ContextTrace(
      entries: List.unmodifiable(traceEntries),
      conflictRules: conflict.triggeredRules,
      totalEstimatedTokens: total,
      responseReserveTokens: budget.responseReserveTokens,
      worldRetrieval: world.retrievalAudit,
      allocation: {
        'profile': weightProfile.toJson(),
        'input_limit_tokens': budget.inputLimitTokens,
        'planner': allocationPlan.toDiagnostics(),
        'sources': {
          ContextSourceId.userControl.value:
              TokenEstimator(plannedUserInput).tokens,
          ContextSourceId.currentScene.value:
              TokenEstimator(plannedSceneContext).tokens,
          ContextSourceId.worldview.value:
              TokenEstimator(plannedWorldContext).tokens,
          ContextSourceId.characterProfile.value:
              TokenEstimator(characterContext).tokens,
          ContextSourceId.runtimeCharacterState.value:
              TokenEstimator(runtimeMemory).tokens,
          ContextSourceId.runtimeWorldState.value:
              TokenEstimator(runtimeWorldMemory).tokens,
          ContextSourceId.recentDialogue.value: recentTokens,
          ContextSourceId.historicalSummary.value:
              TokenEstimator(effectiveSummary).tokens,
          ContextSourceId.archiveRetrieval.value: archiveFacts.fold<int>(
              0, (sum, fact) => sum + TokenEstimator(fact).tokens),
        },
      },
    );
    return NarrativeContext(
      intent: intent,
      sceneState: conflict.sceneState,
      world: world,
      plannedUserInput: plannedUserInput,
      characterContext: characterContext,
      plannedSceneContext: plannedSceneContext,
      plannedWorldContext: plannedWorldContext,
      personaContext: personaContext,
      runtime: RuntimeContextView(
        revision: runtime.revision,
        memory: runtimeMemory,
        worldMemory: runtimeWorldMemory,
        archiveRetrievalFacts: List.unmodifiable(archiveFacts),
        filteredEntityCount: runtime.filteredEntityCount,
        selectedEntityCount: runtime.selectedEntityCount,
      ),
      historicalSummary: effectiveSummary.isEmpty ? null : effectiveSummary,
      recentHistory: List.unmodifiable(recent),
      controlContext: controlContext,
      budget: budget,
      trace: trace,
      weightProfile: weightProfile,
    );
  }

  int _sourceBudget(
    int available,
    int weight, {
    required int minimum,
    required int maximum,
    int divisor = 1,
  }) {
    if (available <= 0 || weight <= 0) return 0;
    final value = (available * weight) ~/ (75 * divisor);
    return value.clamp(minimum, maximum).toInt();
  }

  String _buildCharacterContext(
    AdventureConfig? config,
    SceneState state,
    String query,
    Map<String, String> names,
  ) {
    if (config == null) return '';
    final relevantIds = <String>{
      'protagonist',
      ...state.presentCharacterIds,
      for (final entry in names.entries)
        if (query.contains(entry.value)) entry.key,
    };
    final lines = <String>[];
    if (relevantIds.contains('protagonist')) {
      lines.add([
        config.name,
        config.protagonistClass,
        config.personality,
      ].where((value) => value.trim().isNotEmpty).join('；'));
    }
    for (final character in _legacySupportingCharacters(config)) {
      if (!relevantIds.contains(character.id)) continue;
      lines.add([
        character.name,
        character.role,
        character.personality,
      ].where((value) => value.trim().isNotEmpty).join('；'));
    }
    for (final selected in config.selectedCharacters) {
      if (!relevantIds.contains(selected.characterId)) continue;
      final card = selected.characterCardJson ?? const <String, dynamic>{};
      final data = card['data'] is Map
          ? Map<String, dynamic>.from(card['data'] as Map)
          : card;
      lines.add([
        selected.characterName,
        selected.effectiveRole,
        data['personality']?.toString() ?? '',
        (data['world_profile'] is Map
                    ? (data['world_profile'] as Map)['public_goal']
                    : null)
                ?.toString() ??
            '',
      ].where((value) => value.trim().isNotEmpty).join('；'));
    }
    return lines.where((line) => line.isNotEmpty).toSet().join('\n');
  }

  Iterable<SupportingCharacter> _legacySupportingCharacters(
    AdventureConfig? config,
  ) {
    if (config == null) return const [];
    final frozenIds = <String>{
      for (final selected in config.selectedCharacters) ...[
        selected.id.trim(),
        selected.characterId.trim(),
      ]
    }..remove('');
    return config.supportingCharacters.where(
      (character) => !frozenIds.contains(character.id.trim()),
    );
  }

  String _truncateToTokens(String value, int maximumTokens) =>
      truncateToTokens(value, maximumTokens);

  String _renderWorldPrompt(WorldRuntimeContext world) {
    final buffer = StringBuffer();
    void writeItems(String title, Iterable<WorldContextItem> items) {
      final values = items
          .map((item) => item.content.trim())
          .where((content) => content.isNotEmpty);
      if (values.isEmpty) return;
      buffer.writeln('【$title】');
      for (final value in values) {
        buffer.writeln('- $value');
      }
    }

    writeItems('世界硬约束', world.constraints);
    writeItems('本轮相关世界事实', world.facts);
    writeItems('本轮相关世界背景', world.lore);
    return buffer.toString().trim();
  }
}
