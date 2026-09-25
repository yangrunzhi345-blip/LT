import 'dart:convert';

import '../../utils/token_estimator.dart';

/// Stable, locale independent identifiers for narrative context sources.
enum ContextSourceId {
  userControl,
  currentScene,
  characterProfile,
  runtimeCharacterState,
  worldview,
  runtimeWorldState,
  recentDialogue,
  historicalSummary,
  archiveRetrieval,
}

extension ContextSourceIdCodec on ContextSourceId {
  String get value => switch (this) {
        ContextSourceId.userControl => 'userControl',
        ContextSourceId.currentScene => 'currentScene',
        ContextSourceId.characterProfile => 'characterProfile',
        ContextSourceId.runtimeCharacterState => 'runtimeCharacterState',
        ContextSourceId.worldview => 'worldview',
        ContextSourceId.runtimeWorldState => 'runtimeWorldState',
        ContextSourceId.recentDialogue => 'recentDialogue',
        ContextSourceId.historicalSummary => 'historicalSummary',
        ContextSourceId.archiveRetrieval => 'archiveRetrieval',
      };

  static ContextSourceId? parse(String value) =>
      ContextSourceId.values.where((id) => id.value == value).firstOrNull;
}

enum ContextSourcePriority { mandatory, core, supporting, optional }

final class ContextSourcePolicy {
  final ContextSourcePriority priority;
  final int minimumTokens;
  final int maximumTokens;

  const ContextSourcePolicy({
    required this.priority,
    required this.minimumTokens,
    required this.maximumTokens,
  })  : assert(minimumTokens >= 0),
        assert(maximumTokens >= minimumTokens);
}

/// User adjustable weights. Values are always serialized by stable source ID.
final class ContextWeightProfile {
  static const schemaVersion = 1;
  final String presetId;
  final Map<ContextSourceId, int> weights;

  const ContextWeightProfile({
    this.presetId = 'balanced',
    this.weights = const {},
  });

  int operator [](ContextSourceId id) =>
      (weights[id] ?? ContextWeightPresets.balancedValue(id)).clamp(0, 100);

  ContextWeightProfile copyWith({
    String? presetId,
    Map<ContextSourceId, int>? weights,
  }) =>
      ContextWeightProfile(
        presetId: presetId ?? this.presetId,
        weights: weights ?? this.weights,
      );

  Map<String, Object?> toJson() => {
        'schema_version': schemaVersion,
        'preset_id': presetId,
        'weights': {
          for (final id in ContextSourceId.values) id.value: this[id]
        },
      };

  String encode() => jsonEncode(toJson());

  factory ContextWeightProfile.fromJson(Map<String, dynamic> json) {
    final raw = json['weights'];
    final values = <ContextSourceId, int>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        final id = ContextSourceIdCodec.parse(entry.key.toString());
        final value = entry.value is num ? (entry.value as num).toInt() : null;
        if (id != null && value != null) values[id] = value;
      }
    }
    return ContextWeightProfile(
      presetId: json['preset_id']?.toString() ?? 'balanced',
      weights: values,
    );
  }

  factory ContextWeightProfile.decode(String value) {
    try {
      final json = jsonDecode(value);
      return json is Map
          ? ContextWeightProfile.fromJson(Map<String, dynamic>.from(json))
          : const ContextWeightProfile();
    } catch (_) {
      return const ContextWeightProfile();
    }
  }
}

final class ContextWeightPresets {
  static const ids = ['balanced', 'highControl', 'immersive', 'custom'];

  static ContextWeightProfile get balanced => _preset('balanced', {
        for (final id in ContextSourceId.values) id: balancedValue(id),
      });
  static ContextWeightProfile get highControl => _preset('highControl', {
        for (final id in ContextSourceId.values)
          id: switch (id) {
            ContextSourceId.userControl => 100,
            ContextSourceId.currentScene => 90,
            ContextSourceId.characterProfile => 65,
            ContextSourceId.runtimeCharacterState => 90,
            ContextSourceId.worldview => 55,
            ContextSourceId.runtimeWorldState => 80,
            ContextSourceId.recentDialogue => 55,
            ContextSourceId.historicalSummary => 25,
            ContextSourceId.archiveRetrieval => 25,
          },
      });
  static ContextWeightProfile get immersive => _preset('immersive', {
        for (final id in ContextSourceId.values)
          id: switch (id) {
            ContextSourceId.userControl => 65,
            ContextSourceId.currentScene => 90,
            ContextSourceId.characterProfile => 90,
            ContextSourceId.runtimeCharacterState => 85,
            ContextSourceId.worldview => 90,
            ContextSourceId.runtimeWorldState => 85,
            ContextSourceId.recentDialogue => 90,
            ContextSourceId.historicalSummary => 75,
            ContextSourceId.archiveRetrieval => 65,
          },
      });

  static int balancedValue(ContextSourceId id) => switch (id) {
        ContextSourceId.userControl => 80,
        ContextSourceId.currentScene => 90,
        ContextSourceId.characterProfile => 70,
        ContextSourceId.runtimeCharacterState => 85,
        ContextSourceId.worldview => 75,
        ContextSourceId.runtimeWorldState => 80,
        ContextSourceId.recentDialogue => 75,
        ContextSourceId.historicalSummary => 55,
        ContextSourceId.archiveRetrieval => 45,
      };

  static ContextWeightProfile _preset(
          String id, Map<ContextSourceId, int> values) =>
      ContextWeightProfile(presetId: id, weights: values);
}

final class ContextCandidate {
  final ContextSourceId source;
  final String content;
  final ContextSourcePolicy policy;
  final int score;

  const ContextCandidate({
    required this.source,
    required this.content,
    required this.policy,
    this.score = 0,
  });
}

final class ContextAllocation {
  final ContextSourceId source;
  final String content;
  final int allocatedTokens;
  final int usedTokens;
  final String decision;

  const ContextAllocation({
    required this.source,
    required this.content,
    required this.allocatedTokens,
    required this.usedTokens,
    required this.decision,
  });
}

final class WeightedContextPlan {
  final List<ContextAllocation> allocations;
  final int inputLimitTokens;

  const WeightedContextPlan(this.allocations, this.inputLimitTokens);

  int get usedTokens =>
      allocations.fold(0, (sum, item) => sum + item.usedTokens);

  Map<String, Object?> toDiagnostics() => {
        'input_limit_tokens': inputLimitTokens,
        'used_tokens': usedTokens,
        'sources': [
          for (final item in allocations)
            {
              'source': item.source.value,
              'allocated_tokens': item.allocatedTokens,
              'used_tokens': item.usedTokens,
              'decision': item.decision,
            },
        ],
      };
}

/// Deterministic floor/cap allocator. Mandatory candidates are never weighted out.
final class WeightedContextPlanner {
  const WeightedContextPlanner();

  WeightedContextPlan plan({
    required int inputLimitTokens,
    required ContextWeightProfile profile,
    required Iterable<ContextCandidate> candidates,
  }) {
    final ordered = candidates.toList()
      ..sort((a, b) {
        final priority =
            a.policy.priority.index.compareTo(b.policy.priority.index);
        return priority != 0
            ? priority
            : a.source.index.compareTo(b.source.index);
      });
    final allocations = <ContextAllocation>[];
    var remaining = inputLimitTokens.clamp(0, inputLimitTokens).toInt();
    for (final candidate in ordered.where(
      (c) => c.policy.priority == ContextSourcePriority.mandatory,
    )) {
      final cap = candidate.policy.maximumTokens;
      final text = truncateToTokens(candidate.content, cap);
      final actual = TokenEstimator(text).tokens;
      allocations.add(ContextAllocation(
        source: candidate.source,
        content: text,
        allocatedTokens: cap,
        usedTokens: actual,
        decision: actual > 0 ? 'mandatory' : 'empty',
      ));
      remaining = (remaining - actual).clamp(0, inputLimitTokens);
    }
    final optional = ordered
        .where((c) => c.policy.priority != ContextSourcePriority.mandatory)
        .toList(growable: false);
    final targets = <ContextCandidate, int>{};
    var active = optional.where((c) => profile[c.source] > 0).toList();
    var pool = remaining;
    while (active.isNotEmpty && pool > 0) {
      final weightSum =
          active.fold<int>(0, (sum, c) => sum + profile[c.source]);
      var assigned = 0;
      final saturated = <ContextCandidate>[];
      for (final candidate in active) {
        final proportional = (pool * profile[candidate.source]) ~/ weightSum;
        final raw = TokenEstimator(candidate.content).tokens;
        final requested = proportional.clamp(
            candidate.policy.minimumTokens, candidate.policy.maximumTokens);
        final target = requested.clamp(0, raw).toInt();
        final old = targets[candidate] ?? 0;
        final delta = (target - old).clamp(0, pool).toInt();
        targets[candidate] = old + delta;
        assigned += delta;
        if (target < candidate.policy.minimumTokens ||
            target >= candidate.policy.maximumTokens ||
            target >= raw) {
          saturated.add(candidate);
        }
      }
      pool -= assigned;
      if (assigned == 0) {
        final next = active.firstWhere(
          (candidate) =>
              (targets[candidate] ?? 0) <
              TokenEstimator(candidate.content).tokens,
          orElse: () => active.first,
        );
        targets[next] = (targets[next] ?? 0) + 1;
        pool--;
      }
      active =
          active.where((candidate) => !saturated.contains(candidate)).toList();
    }
    for (final candidate in optional) {
      final raw = TokenEstimator(candidate.content).tokens;
      final target = (targets[candidate] ?? 0).clamp(0, remaining).toInt();
      final text = truncateToTokens(candidate.content, target);
      final actual = TokenEstimator(text).tokens;
      allocations.add(ContextAllocation(
        source: candidate.source,
        content: text,
        allocatedTokens: target,
        usedTokens: actual,
        decision:
            raw == 0 ? 'empty' : (actual < raw ? 'truncated' : 'included'),
      ));
      remaining -= actual;
    }
    return WeightedContextPlan(
        List.unmodifiable(allocations), inputLimitTokens);
  }
}
