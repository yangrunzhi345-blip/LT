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

  /// The turn was blocked before any request because no API key is configured.
  apiKeyNotConfigured,

  /// Assistant notice after a rest action recovered HP / MP / energy.
  restRecovered,

  /// A turn-commit level-up that also restored HP/MP and raised every stat.
  levelUpRecovery,
}

/// A business event that can be rendered for the active locale.
final class AppEvent {
  const AppEvent(
      {required this.code, this.payload = const <String, Object?>{}});

  final AppEventCode code;
  final Map<String, Object?> payload;
}
