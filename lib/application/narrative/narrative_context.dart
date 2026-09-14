import '../../models/adventure_config.dart';
import '../../models/adventure_runtime_state.dart';
import '../../models/message.dart';
import '../../models/model_context_capability.dart';
import '../../models/persona.dart';
import '../../models/scene_state.dart';
import '../../models/supporting_character.dart';
import '../../models/world_entry.dart';
import '../../models/worldview_details.dart';
import '../../utils/token_estimator.dart';
import 'conflict_resolver.dart';
import 'user_intent.dart';

enum WorldContextKind { constraint, fact, lore }

final class WorldContextItem {
  final WorldContextKind kind;
  final String content;
  final int? entryId;
  final String sourceType;
  final int score;
  final int estimatedTokens;

  const WorldContextItem({
    required this.kind,
    required this.content,
    required this.sourceType,
    required this.score,
    required this.estimatedTokens,
    this.entryId,
  });
}

final class WorldRetrievalAuditItem {
  final int? entryId;
  final String sourceType;
  final WorldContextKind classifiedKind;
  final int matchedKeys;
  final bool locationMatched;
  final bool isSticky;
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
  });
}

/// Privacy-safe metadata for inspecting context composition in development.
final class ContextTrace {
  final List<ContextTraceEntry> entries;
  final List<String> conflictRules;
  final int totalEstimatedTokens;
  final int responseReserveTokens;
  final List<WorldRetrievalAuditItem> worldRetrieval;

  const ContextTrace({
    required this.entries,
    required this.conflictRules,
    required this.totalEstimatedTokens,
    required this.responseReserveTokens,
    this.worldRetrieval = const [],
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
            },
        ],
        if (worldRetrieval.isNotEmpty)
          'world_retrieval': [
            for (final audit in worldRetrieval) audit.toDiagnostics(),
          ],
        'conflict_rules': conflictRules,
      };
}

final class NarrativeContext {
  final NarrativeIntent intent;
  final SceneState sceneState;
  final WorldRuntimeContext world;
  final String characterContext;
  final String personaContext;
  final RuntimeContextView runtime;
  final String? historicalSummary;
  final List<Message> recentHistory;
  final String controlContext;
  final ContextBudget budget;
  final ContextTrace trace;

  const NarrativeContext({
    required this.intent,
    required this.sceneState,
    required this.world,
    required this.characterContext,
    required this.personaContext,
    required this.runtime,
    required this.historicalSummary,
    required this.recentHistory,
    required this.controlContext,
    required this.budget,
    required this.trace,
  });
}

/// A bounded projection of the branch-local Runtime HEAD for one prompt.
/// It never contains an entire card, snapshot, or commit archive.
final class RuntimeContextView {
  final int revision;
  final String memory;
  final List<String> archiveRetrievalFacts;
  final int filteredEntityCount;
  final int selectedEntityCount;

  const RuntimeContextView({
    this.revision = 0,
    this.memory = '',
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
    final lines = <String>[];
    for (final entity in relevant) {
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
    var memory = lines.join('\n');
    if (TokenEstimator(memory).tokens > maximumTokens) {
      memory = memory
          .substring(
              0,
              (memory.length * maximumTokens / TokenEstimator(memory).tokens)
                  .floor())
          .trimRight();
    }
    return RuntimeContextView(
      revision: revision,
      memory: memory,
      archiveRetrievalFacts: List.unmodifiable(archiveRetrievalFacts.take(5)),
      filteredEntityCount: entities.length - relevant.length,
      selectedEntityCount: relevant.length,
    );
  }
}

/// Builds the sole runtime view of an immutable worldview asset snapshot.
final class WorldContextBuilder {
  const WorldContextBuilder();

  WorldRuntimeContext build({
    required List<WorldEntry> entries,
    required String query,
    required String location,
    required Iterable<String> characterNames,
    required int tokenBudget,
    Map<String, dynamic>? worldviewSnapshot,
    String legacyWorldview = '',
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
            classifiedKind: _classify(entry),
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
      final kind = _classify(entry);
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

    candidates.sort((a, b) => b.score.compareTo(a.score));
    final selected = <WorldContextItem>[];
    var used = 0;
    for (final item in candidates) {
      final audit = candidateAudits[item]!;
      if (used + item.estimatedTokens > tokenBudget &&
          item.kind != WorldContextKind.constraint) {
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

  WorldContextKind _classify(WorldEntry entry) {
    final content = entry.content;
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
  }) {
    final knownCharacters = <String, String>{
      'protagonist': config?.name ?? '主角',
      // Selected snapshots are the canonical adventure roster. Legacy
      // supporting characters supplement it only when they are not the same
      // frozen character under an older storage shape.
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
    final worldBudget =
        ((budget.inputLimitTokens - mandatoryTokens) ~/ 4).clamp(128, 4096);
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
    );
    final characterContext = _buildCharacterContext(
      config,
      conflict.sceneState,
      rawInput,
      knownCharacters,
    );
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
    final worldTokens = world.all.fold<int>(
      0,
      (sum, item) => sum + item.estimatedTokens,
    );
    var remaining = budget.inputLimitTokens -
        mandatoryTokens -
        worldTokens -
        TokenEstimator(characterContext).tokens -
        TokenEstimator(runtime.memory).tokens -
        runtime.archiveRetrievalFacts.fold<int>(
          0,
          (sum, fact) => sum + TokenEstimator(fact).tokens,
        );
    final rawPersona = persona?.toPromptString() ?? '';
    final personaContext = _truncateToTokens(
      rawPersona,
      remaining.clamp(0, 1024).toInt(),
    );
    remaining -= TokenEstimator(personaContext).tokens;
    final effectiveSummary = _truncateToTokens(
      summary ?? '',
      remaining.clamp(0, 2048).toInt(),
    );

    const retainMessageCount = 12;
    final history = List<Message>.from(messages);
    if (history.lastOrNull case final last?
        when last.isUser && last.content.trim() == rawInput.trim()) {
      history.removeLast();
    }
    var recent = history.length <= retainMessageCount
        ? history
        : history.sublist(history.length - retainMessageCount);
    final fixedTokens = worldTokens +
        TokenEstimator(characterContext).tokens +
        TokenEstimator(runtime.memory).tokens +
        runtime.archiveRetrievalFacts.fold<int>(
          0,
          (sum, fact) => sum + TokenEstimator(fact).tokens,
        ) +
        TokenEstimator(personaContext).tokens +
        TokenEstimator(effectiveSummary).tokens +
        mandatoryTokens;
    var historyBudget = budget.inputLimitTokens - fixedTokens;
    while (recent.isNotEmpty && historyBudget < 0) {
      final removedTokens = TokenEstimator(recent.first.content).tokens;
      recent = recent.sublist(1);
      historyBudget += removedTokens;
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
        ),
      ContextTraceEntry(
        source: 'character_runtime',
        estimatedTokens: TokenEstimator(characterContext).tokens,
        decision: characterContext.isEmpty ? 'empty' : 'included',
      ),
      ContextTraceEntry(
        source: 'runtime_head',
        estimatedTokens: TokenEstimator(runtime.memory).tokens,
        decision: runtime.memory.isEmpty
            ? 'empty:selected:${runtime.selectedEntityCount}'
            : 'included:r${runtime.revision}:selected:${runtime.selectedEntityCount}',
      ),
      ContextTraceEntry(
        source: 'archive_retrieval',
        estimatedTokens: runtime.archiveRetrievalFacts
            .fold<int>(0, (sum, fact) => sum + TokenEstimator(fact).tokens),
        decision: runtime.archiveRetrievalFacts.isEmpty
            ? 'empty'
            : 'included:${runtime.archiveRetrievalFacts.length}',
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
    );
    return NarrativeContext(
      intent: intent,
      sceneState: conflict.sceneState,
      world: world,
      characterContext: characterContext,
      personaContext: personaContext,
      runtime: runtime,
      historicalSummary: effectiveSummary.isEmpty ? null : effectiveSummary,
      recentHistory: List.unmodifiable(recent),
      controlContext: controlContext,
      budget: budget,
      trace: trace,
    );
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

  String _truncateToTokens(String value, int maximumTokens) {
    if (value.isEmpty || maximumTokens <= 0) return '';
    if (TokenEstimator(value).tokens <= maximumTokens) return value;
    var low = 0;
    var high = value.length;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (TokenEstimator(value.substring(0, middle)).tokens <= maximumTokens) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return value.substring(0, low).trimRight();
  }
}
