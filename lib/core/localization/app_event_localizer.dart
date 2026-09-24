import '../../domain/events/app_event.dart';
import '../../l10n/generated/app_localizations.dart';

/// Renders a structured event for the active locale.
String localizeAppEvent(AppLocalizations l10n, AppEvent event) {
  final p = event.payload;
  switch (event.code) {
    case AppEventCode.combatVictory:
      return l10n.eventCombatVictory(
        (p['exp'] as num?)?.toInt() ?? 0,
        (p['gold'] as num?)?.toInt() ?? 0,
      );
    case AppEventCode.combatAttack:
      return l10n.eventCombatAttack(p['actor']?.toString() ?? '');
    case AppEventCode.combatCriticalHit:
      return l10n.eventCombatCriticalHit(p['actor']?.toString() ?? '');
    case AppEventCode.combatSkillUsed:
      return l10n.eventCombatSkillUsed(p['skill']?.toString() ?? '');
    case AppEventCode.combatDefeat:
      return l10n.eventCombatDefeat;
    case AppEventCode.levelUp:
      return l10n.eventLevelUp((p['level'] as num?)?.toInt() ?? 0);
    case AppEventCode.restCompleted:
      return l10n.eventRestCompleted;
    case AppEventCode.itemAdded:
      return l10n.eventItemAdded(p['item']?.toString() ?? '');
    case AppEventCode.itemRemoved:
      return l10n.eventItemRemoved(p['item']?.toString() ?? '');
    case AppEventCode.itemUsed:
      return l10n.eventItemUsed(p['item']?.toString() ?? '');
    case AppEventCode.skillLearned:
      return l10n.eventSkillLearned(p['skill']?.toString() ?? '');
    case AppEventCode.skillFailed:
      return l10n.eventSkillFailed;
  }
}
