import 'package:flutter/material.dart';

import '../../../../../../core/theme/app_spacing.dart';
import '../../../../../../core/utils/worldview_character_scope_policy.dart';
import '../../../../../../core/widgets/app_svg_icon.dart';
import '../../../../../../l10n/generated/app_localizations.dart';
import '../../../../../../models/character_card_entry.dart';
import '../wizard_resource_banner.dart';

/// Step 2 library picker: parse-error banner, selectable character chips and
/// the empty-state hint.
///
/// Selection is owned by the wizard; this panel only renders [availableCards]
/// and reports toggles.
class WizardCharacterLibraryPanel extends StatelessWidget {
  const WizardCharacterLibraryPanel({
    super.key,
    required this.l10n,
    required this.availableCards,
    required this.selectedIds,
    required this.selectedWorldviewId,
    required this.hasLoadError,
    required this.malformedCount,
    required this.onToggleCard,
  });

  final AppLocalizations l10n;
  final List<CharacterCardEntry> availableCards;
  final Set<String> selectedIds;
  final String? selectedWorldviewId;
  final bool hasLoadError;
  final int malformedCount;
  final ValueChanged<CharacterCardEntry> onToggleCard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasLoadError)
          WizardResourceBanner(
            icon: 'error',
            isError: true,
            message: malformedCount > 0
                ? l10n.wizardMalformedCharacterCards(malformedCount)
                : l10n.resourceLoadFailedRetry,
          )
        else if (malformedCount > 0)
          WizardResourceBanner(
            icon: 'warning',
            isError: true,
            message: l10n.wizardMalformedCharacterCards(malformedCount),
          ),
        if (availableCards.isNotEmpty) ...[
          Text(
            l10n.characterSelectionSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: availableCards.map((card) {
              final isSelected = selectedIds.contains(card.id);
              final compatibility = WorldviewCharacterScopePolicy.compatibility(
                card.matchingWorldviewId,
                selectedWorldviewId,
              );
              final originLabel = switch (compatibility) {
                CharacterWorldviewCompatibility.native =>
                  ' · ${l10n.characterCompatNative}',
                CharacterWorldviewCompatibility.unbound =>
                  ' · ${l10n.characterCompatUnbound}',
                CharacterWorldviewCompatibility.crossWorld =>
                  ' · ${l10n.characterCompatCrossWorld}',
              };

              return ChoiceChip(
                avatar: isSelected
                    ? const AppSvgIcon('check', size: 14)
                    : const AppSvgIcon('person', size: 14),
                label: Text(
                  '${card.name}${card.profession.isNotEmpty ? " (${card.profession})" : ""}$originLabel',
                ),
                selected: isSelected,
                onSelected: (_) => onToggleCard(card),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.md),
        ] else if (!hasLoadError) ...[
          WizardResourceBanner(
            icon: 'info',
            isError: false,
            message: l10n.characterSelectionEmptyDesc,
          ),
        ],
      ],
    );
  }
}
