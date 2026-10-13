import '../models/scene_dialogue.dart';
import '../models/scene_state.dart';
import 'scene_entry_authorizer.dart';

/// Deterministic first-pass continuity guard. It never mutates a response;
/// callers may use its result to request one narrative-only repair.
class SceneConsistencyValidator {
  const SceneConsistencyValidator();

  /// Bounded, diagnostic-only heuristic for the classic "third party barges
  /// into a private scene" failure: the narrative frames an arrival as a
  /// sudden interruption while the player never invited anyone. It never
  /// blocks a turn — deciding whether a surprise arrival was dramatically
  /// justified is semantic and stays with the prompt contract — but it makes
  /// the pattern observable in the persisted turn diagnostics.
  static final RegExp _interruptionPattern =
      NarrativeArrivalVocabulary.interruption;

  SceneConsistencyResult validate({
    required SceneDialogueContextSnapshot snapshot,
    required String narrative,
    required Map<String, dynamic>? payload,
    String userInput = '',
    Set<String> invitedCharacterIds = const {},
  }) {
    final warnings = <String>[];
    final names = snapshot.presentParticipants.map((p) => p.name).toSet();
    for (final participant in snapshot.presentParticipants) {
      if (!participant.isAlive && narrative.contains(participant.name)) {
        warnings.add('死亡角色“${participant.name}”出现在叙事中');
      }
    }
    if (payload != null) {
      final candidates = payload['scene_candidates'];
      if (candidates is List) {
        for (final candidate in candidates) {
          if (candidate is! Map ||
              !SceneSettingCandidate.allowedTypes
                  .contains(candidate['type']?.toString())) {
            warnings.add('包含不受支持的设定候选');
            break;
          }
        }
      }
      // The model must not use a candidate to fabricate an actor switch.
      final actorId = payload['actor_id']?.toString();
      if (actorId != null &&
          actorId.isNotEmpty &&
          !snapshot.presentParticipants.any((p) => p.id == actorId)) {
        warnings.add('状态补丁试图切换到不在场行动者');
      }
      final mentionedActor = payload['actor_name']?.toString();
      if (mentionedActor != null &&
          mentionedActor.isNotEmpty &&
          !names.contains(mentionedActor)) {
        warnings.add('状态补丁包含不在场角色');
      }
      final entering = SceneStateChangeProposal.parse(
        payload['scene_state_changes'],
        diagnostics: <String>[],
      )?.charactersEnter;
      if (entering != null &&
          entering.isNotEmpty &&
          userInput.trim().isNotEmpty &&
          _interruptionPattern.hasMatch(narrative) &&
          !invitedCharacterIds.any(entering.contains)) {
        warnings.add('叙事以突发方式引入入场角色，且玩家未邀请：${entering.join('、')}');
      }
    }
    return SceneConsistencyResult(warnings);
  }
}

class SceneConsistencyResult {
  final List<String> warnings;
  const SceneConsistencyResult(this.warnings);
  bool get isConsistent => warnings.isEmpty;
}
