import '../../models/scene_state.dart';
import 'user_intent.dart';

final class ConflictResolution {
  final SceneState sceneState;
  final List<String> triggeredRules;

  const ConflictResolution(this.sceneState, this.triggeredRules);
}

/// Projects explicit current intent onto scene goals without deciding for the
/// player.
final class NarrativeConflictResolver {
  const NarrativeConflictResolver();

  ConflictResolution resolve(SceneState state, NarrativeIntent intent) {
    final goals = List<SceneGoal>.from(state.goals);
    final rules = <String>[];

    for (var index = 0; index < goals.length; index++) {
      final goal = goals[index];
      if (goal.status != SceneGoalStatus.active) continue;
      if (intent.refusals.any(
        (refusal) => _conflicts(refusal, goal.description),
      )) {
        goals[index] = goal.copyWith(status: SceneGoalStatus.cancelled);
        rules.add('current_user_cancels_scene_goal:${goal.id}');
      }
    }

    for (final description in intent.goals) {
      if (goals.any((goal) =>
          goal.status == SceneGoalStatus.active &&
          _normalize(goal.description) == _normalize(description))) {
        continue;
      }
      goals.add(SceneGoal(
        id: 'intent-${_stableHash(description)}',
        description: description,
      ));
      rules.add('current_user_adds_scene_goal');
    }

    if (intent.excludedCharacterIds.isNotEmpty) {
      rules.add('current_user_excludes_character');
    }
    final present = state.presentCharacterIds
        .where((id) => !intent.excludedCharacterIds.contains(id))
        .toList(growable: false);

    return ConflictResolution(
      state.copyWith(
        goals: List.unmodifiable(goals),
        presentCharacterIds: List.unmodifiable(present),
        recentChanges: [
          ...state.recentChanges.take(4),
          ...intent.refusals,
          ...intent.goals,
        ],
      ),
      List.unmodifiable(rules),
    );
  }

  bool _conflicts(String refusal, String goal) {
    final normalizedRefusal = _normalize(refusal);
    final normalizedGoal = _normalize(goal);
    if (normalizedGoal.isEmpty) return false;
    return normalizedRefusal.contains(normalizedGoal) ||
        _significantTerms(normalizedGoal).any(normalizedRefusal.contains);
  }

  Iterable<String> _significantTerms(String text) => text
      .split(RegExp(r'\s+'))
      .where((term) => term.length >= 2)
      .followedBy(RegExp(r'[\u4e00-\u9fff]{2,}').allMatches(text).map(
            (match) => match.group(0)!,
          ));

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(
          RegExp(
            r'(?:玩家|我|准备|决定|想要|想|要|前往|去|不再|不去|不要|取消|停止|放弃|the|to|i|will|want|go|not|don[’\x27]?t)',
            caseSensitive: false,
          ),
          '')
      .replaceAll(RegExp(r'[^\u4e00-\u9fffa-z0-9]+'), ' ')
      .trim();

  int _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
