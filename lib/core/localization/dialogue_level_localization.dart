import '../../l10n/generated/app_localizations.dart';
import '../../models/dialogue_level.dart';

String localizedDialogueLevelLabel(
  DialogueLevel level,
  AppLocalizations l10n,
) =>
    switch (level.id) {
      'L0' => l10n.dialogueLevelFast,
      'L1' => l10n.dialogueLevelConcise,
      'L2' => l10n.dialogueLevelStandard,
      'L3' => l10n.dialogueLevelDetailed,
      'L4' => l10n.dialogueLevelDeep,
      'L5' => l10n.dialogueLevelProduction,
      _ => level.label,
    };

String localizedDialogueLevelDescription(
  DialogueLevel level,
  AppLocalizations l10n,
) =>
    switch (level.id) {
      'L0' => l10n.dialogueLevelFastDesc,
      'L1' => l10n.dialogueLevelConciseDesc,
      'L2' => l10n.dialogueLevelStandardDesc,
      'L3' => l10n.dialogueLevelDetailedDesc,
      'L4' => l10n.dialogueLevelDeepDesc,
      'L5' => l10n.dialogueLevelProductionDesc,
      _ => level.description,
    };

String localizedDialogueLevelWordRange(
  DialogueLevel level,
  AppLocalizations l10n,
) =>
    level.openEnded
        ? l10n.dialogueWordsAbove(level.minWords)
        : '${level.minWords}-${level.maxWords}';
