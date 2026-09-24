/// Locale-neutral business events. Payload values are typed facts, not copy.
enum AppEventCode {
  combatVictory,
  combatDefeat,
  combatAttack,
  combatCriticalHit,
  combatSkillUsed,
  levelUp,
  restCompleted,
  itemAdded,
  itemRemoved,
  itemUsed,
  skillLearned,
  skillFailed,
}

/// A business event that can be rendered for the active locale.
final class AppEvent {
  const AppEvent(
      {required this.code, this.payload = const <String, Object?>{}});

  final AppEventCode code;
  final Map<String, Object?> payload;
}
