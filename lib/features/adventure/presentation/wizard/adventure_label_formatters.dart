import '../../../../l10n/generated/app_localizations.dart';
import '../../../../models/adventure_config.dart';

/// Localized label of an Adventure character role.
///
/// Shared by the wizard roster, the assembly preview and the character-step
/// widgets so every surface names a role identically.
String localizedAdventureRole(String value, AppLocalizations l10n) =>
    switch (value) {
      AdventureCharacterRole.protagonist => l10n.mainProtagonistTitle,
      AdventureCharacterRole.maleLead => l10n.roleMaleLead,
      AdventureCharacterRole.femaleLead => l10n.roleFemaleLead,
      AdventureCharacterRole.maleOne => l10n.roleMaleOne,
      AdventureCharacterRole.femaleOne => l10n.roleFemaleOne,
      AdventureCharacterRole.maleTwo => l10n.roleMaleTwo,
      AdventureCharacterRole.femaleTwo => l10n.roleFemaleTwo,
      AdventureCharacterRole.supporting => l10n.roleSupporting,
      AdventureCharacterRole.companion => l10n.relationCompanion,
      AdventureCharacterRole.villain => l10n.roleVillain,
      AdventureCharacterRole.mentor => l10n.roleMentor,
      AdventureCharacterRole.family => l10n.roleFamily,
      _ => value,
    };

/// Localized label of the bond between two roster characters.
String localizedAdventureRelation(String value, AppLocalizations l10n) =>
    switch (value) {
      AdventureRelationType.unset => l10n.notSpecifiedOption,
      AdventureRelationType.friend => l10n.relationFriend,
      AdventureRelationType.family => l10n.relationKin,
      AdventureRelationType.enemy => l10n.relationEnemy,
      AdventureRelationType.companion => l10n.relationCompanion,
      AdventureRelationType.lover => l10n.relationLover,
      AdventureRelationType.mentor => l10n.relationMentor,
      AdventureRelationType.rival => l10n.relationRival,
      AdventureRelationType.employer => l10n.relationEmployment,
      AdventureRelationType.stranger => l10n.relationStranger,
      AdventureRelationType.custom => l10n.relationCustom,
      _ => value,
    };
