import '../models/scene_state.dart';

final class SceneStateProposalValidation {
  final SceneState? state;
  final List<String> diagnostics;

  const SceneStateProposalValidation(this.state, this.diagnostics);
}

/// Applies only validated, local scene-working-state changes.
final class SceneStateProposalValidator {
  const SceneStateProposalValidator();

  SceneStateProposalValidation apply({
    required SceneState current,
    required SceneStateChangeProposal? proposal,
    required Set<String> knownCharacterIds,
    required Set<String> deadCharacterIds,
  }) {
    if (proposal == null) {
      return SceneStateProposalValidation(current, const []);
    }
    final diagnostics = <String>[];
    final entering = proposal.charactersEnter.toSet();
    final leaving = proposal.charactersLeave.toSet();
    final present = current.presentCharacterIds.toSet();
    if (proposal.charactersEnter.length != entering.length) {
      diagnostics.add('scene_state_changes:characters_enter:duplicate');
    }
    if (proposal.charactersLeave.length != leaving.length) {
      diagnostics.add('scene_state_changes:characters_leave:duplicate');
    }
    for (final id in entering.intersection(leaving)) {
      diagnostics.add('scene_state_changes:characters:conflict:$id');
      entering.remove(id);
      leaving.remove(id);
    }
    for (final id in entering) {
      if (!knownCharacterIds.contains(id) || deadCharacterIds.contains(id)) {
        diagnostics.add('scene_state_changes:characters_enter:forbidden:$id');
      } else if (!present.add(id)) {
        diagnostics.add('scene_state_changes:characters_enter:duplicate:$id');
      }
    }
    for (final id in leaving) {
      if (id == 'protagonist') {
        diagnostics.add('scene_state_changes:characters_leave:protagonist');
        continue;
      }
      if (!present.remove(id)) {
        diagnostics.add('scene_state_changes:characters_leave:absent:$id');
      }
    }
    present.add('protagonist');

    final goals = {for (final goal in current.goals) goal.id: goal};
    for (final goal in proposal.goalsAdd) {
      if (goals.containsKey(goal.id)) {
        diagnostics.add('scene_state_changes:goals_add:duplicate:${goal.id}');
      } else {
        goals[goal.id] = goal;
      }
    }
    for (final entry in proposal.goalsUpdate.entries) {
      final existing = goals[entry.key];
      if (existing == null) {
        diagnostics
            .add('scene_state_changes:goals_update:missing:${entry.key}');
      } else {
        goals[entry.key] = existing.copyWith(status: entry.value);
      }
    }
    for (final id in proposal.goalsRemove) {
      if (goals.remove(id) == null) {
        diagnostics.add('scene_state_changes:goals_remove:missing:$id');
      }
    }
    return SceneStateProposalValidation(
      current.copyWith(
        location: proposal.location,
        time: proposal.time,
        presentCharacterIds: List.unmodifiable(present),
        goals: List.unmodifiable(goals.values),
      ),
      List.unmodifiable(diagnostics),
    );
  }
}
