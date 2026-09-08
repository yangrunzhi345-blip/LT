import '../../models/adventure_config.dart';
import '../../models/message.dart';
import '../../models/model_context_capability.dart';
import '../../models/persona.dart';
import '../../models/scene_state.dart';
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

final class WorldRuntimeContext {
  final List<WorldContextItem> constraints;
  final List<WorldContextItem> facts;
  final List<WorldContextItem> lore;
  final List<int> filteredEntryIds;

  const WorldRuntimeContext({
    this.constraints = const [],
    this.facts = const [],
    this.lore = const [],
    this.filteredEntryIds = const [],
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

  const ContextTraceEntry({
    required this.source,
    required this.estimatedTokens,
    required this.decision,
    this.sourceId,
  });
}

/// Privacy-safe metadata for inspecting context composition in development.
final class ContextTrace {
  final List<ContextTraceEntry> entries;
  final List<String> conflictRules;
  final int totalEstimatedTokens;
  final int responseReserveTokens;

  const ContextTrace({
    required this.entries,
    required this.conflictRules,
    required this.totalEstimatedTokens,
    required this.responseReserveTokens,
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
            },
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
    required this.historicalSummary,
    required this.recentHistory,
    required this.controlContext,
    required this.budget,
    required this.trace,
  });
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

    for (final entry in effectiveEntries.where((entry) => entry.enabled)) {
      final normalized = _normalize(entry.content);
      if (normalized.isEmpty || !seen.add(normalized)) {
        if (entry.id case final id?) filtered.add(id);
        continue;
      }
      final kind = _classify(entry);
      final matchedKeys = entry.keys
          .where((key) => key.trim().isNotEmpty)
          .where((key) => searchText.contains(key.toLowerCase()))
          .length;
      final isRelevant = kind == WorldContextKind.constraint ||
          entry.sticky > 0 ||
          matchedKeys > 0 ||
          (location.isNotEmpty && entry.content.contains(location));
      if (!isRelevant) {
        if (entry.id case final id?) filtered.add(id);
        continue;
      }
      final score = switch (kind) {
            WorldContextKind.constraint => 1000,
            WorldContextKind.fact => 500,
            WorldContextKind.lore => 100,
          } +
          matchedKeys * 50 +
          (entry.sticky > 0 ? 25 : 0) -
          entry.insertionOrder.clamp(0, 100);
      candidates.add(WorldContextItem(
        kind: kind,
        content: entry.content.trim(),
        entryId: entry.id,
        sourceType: entry.sourceType.isEmpty ? 'world_entry' : entry.sourceType,
        score: score,
        estimatedTokens: TokenEstimator(entry.content).tokens,
      ));
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    final selected = <WorldContextItem>[];
    var used = 0;
    for (final item in candidates) {
      if (used + item.estimatedTokens > tokenBudget &&
          item.kind != WorldContextKind.constraint) {
        if (item.entryId case final id?) filtered.add(id);
        continue;
      }
      selected.add(item);
      used += item.estimatedTokens;
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

  const ContextOrchestrator({
    this.intentResolver = const IntentResolver(),
    this.conflictResolver = const NarrativeConflictResolver(),
    this.worldBuilder = const WorldContextBuilder(),
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
  }) {
    final knownCharacters = <String, String>{
      'protagonist': config?.name ?? '主角',
      for (final character in config?.supportingCharacters ?? const [])
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
        800;
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
    final worldTokens = world.all.fold<int>(
      0,
      (sum, item) => sum + item.estimatedTokens,
    );
    var remaining = budget.inputLimitTokens -
        mandatoryTokens -
        worldTokens -
        TokenEstimator(characterContext).tokens;
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
      for (final item in world.all)
        ContextTraceEntry(
          source: 'world:${item.kind.name}:${item.sourceType}',
          sourceId: item.entryId,
          estimatedTokens: item.estimatedTokens,
          decision: 'included',
        ),
      ContextTraceEntry(
        source: 'character_runtime',
        estimatedTokens: TokenEstimator(characterContext).tokens,
        decision: characterContext.isEmpty ? 'empty' : 'included',
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
    );
    return NarrativeContext(
      intent: intent,
      sceneState: conflict.sceneState,
      world: world,
      characterContext: characterContext,
      personaContext: personaContext,
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
    for (final character in config.supportingCharacters) {
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
