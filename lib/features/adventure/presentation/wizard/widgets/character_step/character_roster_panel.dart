import 'package:flutter/material.dart';

import '../../../../../../core/theme/app_radius.dart';
import '../../../../../../core/theme/app_spacing.dart';
import '../../../../../../core/widgets/app_dropdown.dart';
import '../../../../../../core/widgets/app_svg_icon.dart';
import '../../../../../../l10n/generated/app_localizations.dart';
import '../../../../../../models/adventure_config.dart';
import '../../adventure_label_formatters.dart';
import '../../models/wizard_character_item.dart';

/// Step 2 roster: selected characters with protagonist marking, role
/// assignment and per-character actions.
class WizardCharacterRosterPanel extends StatelessWidget {
  const WizardCharacterRosterPanel({
    super.key,
    required this.l10n,
    required this.characters,
    required this.onSetProtagonist,
    required this.onRemove,
    required this.onEdit,
    required this.onSaveToLibrary,
    required this.onRoleChanged,
    required this.onCustomRoleNameChanged,
  });

  final AppLocalizations l10n;
  final List<WizardCharacterItem> characters;
  final ValueChanged<String> onSetProtagonist;
  final ValueChanged<String> onRemove;
  final ValueChanged<WizardCharacterItem> onEdit;
  final ValueChanged<WizardCharacterItem> onSaveToLibrary;
  final void Function(WizardCharacterItem character, String role) onRoleChanged;
  final void Function(WizardCharacterItem character, String customName)
      onCustomRoleNameChanged;

  static const List<String> _assignableRoles = [
    AdventureCharacterRole.maleLead,
    AdventureCharacterRole.femaleLead,
    AdventureCharacterRole.maleOne,
    AdventureCharacterRole.femaleOne,
    AdventureCharacterRole.maleTwo,
    AdventureCharacterRole.femaleTwo,
    AdventureCharacterRole.companion,
    AdventureCharacterRole.mentor,
    AdventureCharacterRole.family,
    AdventureCharacterRole.supporting,
    AdventureCharacterRole.villain,
    AdventureCharacterRole.custom,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.xs,
          runSpacing: 2,
          children: [
            Text(
              l10n.rosterSectionTitle(characters.length),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (characters.isNotEmpty)
              Text(
                l10n.rosterSectionDesc,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: scheme.outline,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (characters.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              children: [
                AppSvgIcon(
                  'group',
                  size: 36,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.noCharactersAddedYet,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.clickAboveToAddCharactersHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          )
        else
          ...characters.map(
            (character) => _RosterCharacterCard(
              l10n: l10n,
              character: character,
              onSetProtagonist: onSetProtagonist,
              onRemove: onRemove,
              onEdit: onEdit,
              onSaveToLibrary: onSaveToLibrary,
              onRoleChanged: onRoleChanged,
              onCustomRoleNameChanged: onCustomRoleNameChanged,
            ),
          ),
      ],
    );
  }
}

class _RosterCharacterCard extends StatelessWidget {
  const _RosterCharacterCard({
    required this.l10n,
    required this.character,
    required this.onSetProtagonist,
    required this.onRemove,
    required this.onEdit,
    required this.onSaveToLibrary,
    required this.onRoleChanged,
    required this.onCustomRoleNameChanged,
  });

  final AppLocalizations l10n;
  final WizardCharacterItem character;
  final ValueChanged<String> onSetProtagonist;
  final ValueChanged<String> onRemove;
  final ValueChanged<WizardCharacterItem> onEdit;
  final ValueChanged<WizardCharacterItem> onSaveToLibrary;
  final void Function(WizardCharacterItem character, String role) onRoleChanged;
  final void Function(WizardCharacterItem character, String customName)
      onCustomRoleNameChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: character.isProtagonist
            ? scheme.primaryContainer.withValues(alpha: 0.15)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: character.isProtagonist
              ? scheme.primary.withValues(alpha: 0.5)
              : scheme.outlineVariant.withValues(alpha: 0.6),
          width: character.isProtagonist ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(scheme),
          const SizedBox(height: 8),
          _roleRow(scheme),
          if (character.personality.isNotEmpty ||
              character.background.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (character.personality.isNotEmpty)
                    Text(
                      l10n.personalityFeatureLabel(character.personality),
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (character.background.isNotEmpty)
                    Text(
                      l10n.backgroundStoryPrefix(character.background),
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _header(ColorScheme scheme) {
    final identity = <Widget>[
      CircleAvatar(
        radius: 16,
        backgroundColor: character.isProtagonist
            ? scheme.primary
            : scheme.secondaryContainer,
        child: Text(
          character.name.isNotEmpty ? character.name[0] : '?',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: character.isProtagonist
                ? Colors.white
                : scheme.onSecondaryContainer,
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(
              character.name,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (character.profession.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  character.profession,
                  style:
                      TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ),
            if (character.gender.isNotEmpty || character.age.isNotEmpty)
              Text(
                [
                  if (character.gender.isNotEmpty) character.gender,
                  if (character.age.isNotEmpty)
                    l10n.characterAgeYears(character.age),
                ].join(' · '),
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
          ],
        ),
      ),
    ];
    final starAction = character.isProtagonist
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppSvgIcon('star', size: 14, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  l10n.mainProtagonistTitle,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          )
        : OutlinedButton.icon(
            onPressed: () => onSetProtagonist(character.id),
            icon: const AppSvgIcon('star', size: 14),
            label: Text(
              l10n.setAsMainProtagonist,
              style: const TextStyle(fontSize: 11),
            ),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
          );
    final actions = <Widget>[
      starAction,
      IconButton(
        onPressed: () => onSaveToLibrary(character),
        icon: const AppSvgIcon('bookmark', size: 18),
        tooltip: l10n.saveToLibraryNow,
        visualDensity: VisualDensity.compact,
      ),
      IconButton(
        onPressed: () => onEdit(character),
        icon: const AppSvgIcon('edit', size: 18),
        tooltip: l10n.editAction,
        visualDensity: VisualDensity.compact,
      ),
      IconButton(
        onPressed: () => onRemove(character.id),
        icon: const AppSvgIcon('close', size: 18),
        tooltip: l10n.removeRosterCharacter,
        visualDensity: VisualDensity.compact,
        color: scheme.error,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Below 360 logical px the identity line, the protagonist action and
        // the three icon buttons cannot share one row without squeezing the
        // name to nothing; the actions move to their own wrapped line.
        if (constraints.maxWidth < 360) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: identity),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: actions,
              ),
            ],
          );
        }
        return Row(
          children: [
            ...identity,
            starAction,
            const SizedBox(width: 4),
            ...actions.skip(1),
          ],
        );
      },
    );
  }

  Widget _roleRow(ColorScheme scheme) {
    final label = Text(
      l10n.scriptRoleOrientation,
      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
    );
    final roleControl = character.isProtagonist
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              l10n.mainProtagonistDescription,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.primary,
              ),
            ),
          )
        : AppDropdown<String>.compact(
            value: character.narrativeRole,
            options: WizardCharacterRosterPanel._assignableRoles
                .map(
                  (role) => AppDropdownOption(
                    value: role,
                    label: localizedAdventureRole(role, l10n),
                  ),
                )
                .toList(),
            onChanged: (newRole) {
              if (newRole != null) onRoleChanged(character, newRole);
            },
          );
    final customField = character.narrativeRole == AdventureCharacterRole.custom
        ? SizedBox(
            height: 32,
            child: TextField(
              controller: TextEditingController(
                text: character.customRoleName,
              )..selection = TextSelection.collapsed(
                  offset: character.customRoleName.length,
                ),
              decoration: InputDecoration(
                hintText: l10n.scriptRoleOrientation,
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              ),
              style: const TextStyle(fontSize: 12),
              onChanged: (val) =>
                  onCustomRoleNameChanged(character, val.trim()),
            ),
          )
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Same 360 px threshold as the header: the label plus the role picker
        // (and the custom-role field) cannot fit one line on the narrowest
        // supported phones, so the field drops below the picker.
        if (constraints.maxWidth < 360) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [label, roleControl],
              ),
              if (customField != null) ...[
                const SizedBox(height: 6),
                SizedBox(width: double.infinity, child: customField),
              ],
            ],
          );
        }
        return Row(
          children: [
            label,
            const SizedBox(width: 8),
            roleControl,
            if (customField != null) ...[
              const SizedBox(width: 8),
              Expanded(child: customField),
            ],
          ],
        );
      },
    );
  }
}
