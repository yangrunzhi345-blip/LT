import '../models/scene_state.dart';

/// Vocabulary that says "someone arrived" without naming them. Shared with
/// [SceneConsistencyValidator] so the interruption heuristic has one source.
///
/// These words are **diagnostic only**: they never authorize an entry. A
/// keyword such as 「走进」 appearing anywhere in the prose must not be able
/// to release an arbitrary `characters_enter`, so the authorizer requires the
/// entering roster character to be *named* (or explicitly invited).
final class NarrativeArrivalVocabulary {
  /// Normal arrival phrasing: a character is depicted reaching the scene.
  static final RegExp arrival = RegExp(
    r'走进|推门|步入|抵达|赶来|走过来|坐了过来|出现在门口|推开门|步入厅|'
    r'arriv(?:ed|es|ing)|walks? in|enters?|steps? in|comes? over',
    caseSensitive: false,
  );

  /// Interruption phrasing: an arrival framed as a sudden disruption. A
  /// private-scene interruption is reported as a continuity warning instead
  /// of being silently accepted.
  static final RegExp interruption = RegExp(
    r'突然|就在这时|忽然|猝然|猛地推开门|闯进|不请自来|without warning|suddenly|out of nowhere|burst(?:ed|ing)? in',
    caseSensitive: false,
  );

  const NarrativeArrivalVocabulary._();
}

/// Everything the authorizer needs to decide whether one turn's scene-state
/// proposal is backed by the player or by the turn's own narrative.
///
/// The rule is deliberately narrow and deterministic: a character may only
/// **enter or leave** the scene when the player authorized it (invitation /
/// dismissal / exclusion) or when the final narrative of this very turn
/// names that character. A location or time change is vetoed only when the
/// player explicitly forbade it.
///
/// Why naming is required for `characters_enter`: the proposal claims that a
/// *specific roster character* entered. Narration that depicts an unnamed
/// arrival cannot be attributed to that identity, and accepting it on
/// arrival keywords alone would let any `characters_enter` ride on one
/// generic sentence — exactly the bypass that protects quiet two-person
/// scenes. An unnamed stranger is a new character and belongs in
/// `scene_candidates`, which is also what the prompt contract states.
final class SceneEntryAuthorization {
  /// Roster ids the player explicitly excluded this turn. An excluded
  /// character may never enter; leaving is allowed because it serves the
  /// exclusion.
  final Set<String> excludedCharacterIds;

  /// Roster ids the player explicitly invited this turn.
  final Set<String> invitedCharacterIds;

  /// Roster ids the player explicitly asked to leave this turn.
  final Set<String> dismissedCharacterIds;

  /// Display names that appear in the final narrative of this turn.
  final Set<String> narrativeNames;

  /// True when the final narrative depicts an arrival without naming the
  /// arriving character. Used only to distinguish "state fabricated with no
  /// trace" from "state claims an unnamed arrival" in diagnostics.
  final bool narrativeHasArrival;

  /// Stable id → display name for the whole roster, used to resolve the
  /// narrative basis and to render readable diagnostics.
  final Map<String, String> characterNames;

  /// False only when the player explicitly forbade a scene change this turn.
  final bool allowsLocationChange;

  /// False only when the player explicitly forbade a time skip this turn.
  final bool allowsTimeChange;

  const SceneEntryAuthorization({
    this.excludedCharacterIds = const {},
    this.invitedCharacterIds = const {},
    this.dismissedCharacterIds = const {},
    this.narrativeNames = const {},
    this.narrativeHasArrival = false,
    this.characterNames = const {},
    this.allowsLocationChange = true,
    this.allowsTimeChange = true,
  });
}

/// Result of [SceneEntryAuthorizer.authorize].
final class SceneEntryAuthorizationResult {
  /// The proposal with unauthorized deltas removed (null when nothing
  /// survives).
  final SceneStateChangeProposal? proposal;

  /// One diagnostic per rejected delta, persisted with the turn so a filtered
  /// proposal is always observable.
  final List<String> diagnostics;

  const SceneEntryAuthorizationResult({
    required this.proposal,
    required this.diagnostics,
  });
}

/// Filters a model-proposed [SceneStateChangeProposal] down to the deltas the
/// player or the turn's own narrative actually authorize.
///
/// Structural validation (unknown ids, dead ids, duplicates, protagonist
/// removal) stays in [SceneStateProposalValidator]; this class only answers
/// the authorization question, so the two compose without overlap. Removed
/// deltas are reported as diagnostics and persisted with the turn, so a
/// filtered proposal is always observable instead of silently dropped.
final class SceneEntryAuthorizer {
  const SceneEntryAuthorizer();

  /// Returns the authorized proposal (or null when nothing survives) together
  /// with one diagnostic per rejected delta.
  SceneEntryAuthorizationResult authorize({
    required SceneStateChangeProposal? proposal,
    required SceneEntryAuthorization authorization,
    required String currentLocation,
    required String currentTime,
  }) {
    if (proposal == null) {
      return const SceneEntryAuthorizationResult(
          proposal: null, diagnostics: []);
    }
    final diagnostics = <String>[];

    final entering = <String>[];
    for (final id in proposal.charactersEnter) {
      if (authorization.excludedCharacterIds.contains(id)) {
        diagnostics.add('scene_state_changes:characters_enter:excluded:$id');
        continue;
      }
      if (!_hasBasis(id, authorization) &&
          !authorization.invitedCharacterIds.contains(id)) {
        // Distinguish "no trace at all" from "the prose depicts an arrival
        // the model did not attribute by name": the second is a protocol
        // deviation the model can fix next turn, the first is fabrication.
        diagnostics.add(authorization.narrativeHasArrival
            ? 'scene_state_changes:characters_enter:unnamed:$id'
            : 'scene_state_changes:characters_enter:unauthorized:$id');
        continue;
      }
      entering.add(id);
    }

    final leaving = <String>[];
    for (final id in proposal.charactersLeave) {
      // The protagonist can never be removed; leave that structural rule to
      // the validator so its specific diagnostic stays intact.
      if (id == 'protagonist') {
        leaving.add(id);
        continue;
      }
      if (!_hasBasis(id, authorization) &&
          !authorization.dismissedCharacterIds.contains(id) &&
          !authorization.excludedCharacterIds.contains(id)) {
        diagnostics
            .add('scene_state_changes:characters_leave:unauthorized:$id');
        continue;
      }
      leaving.add(id);
    }

    String? location = proposal.location;
    if (location != null &&
        !authorization.allowsLocationChange &&
        location.trim() != currentLocation.trim()) {
      diagnostics.add('scene_state_changes:location:forbidden');
      location = null;
    }

    String? time = proposal.time;
    if (time != null &&
        !authorization.allowsTimeChange &&
        time.trim() != currentTime.trim()) {
      diagnostics.add('scene_state_changes:time:forbidden');
      time = null;
    }

    final authorized = SceneStateChangeProposal(
      location: location,
      time: time,
      charactersEnter: entering,
      charactersLeave: leaving,
      goalsAdd: proposal.goalsAdd,
      goalsUpdate: proposal.goalsUpdate,
      goalsRemove: proposal.goalsRemove,
    );
    return SceneEntryAuthorizationResult(
      proposal: authorized.isEmpty ? null : authorized,
      diagnostics: List.unmodifiable(diagnostics),
    );
  }

  /// A character has basis when the turn's final narrative names them: the
  /// model can only assert an entrance/exit it actually depicted for that
  /// identity.
  bool _hasBasis(String id, SceneEntryAuthorization authorization) {
    final name = authorization.characterNames[id];
    if (name == null || name.trim().isEmpty) return false;
    return authorization.narrativeNames.contains(name.trim());
  }
}
