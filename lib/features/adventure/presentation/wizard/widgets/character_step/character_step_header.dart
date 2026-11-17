import 'package:flutter/material.dart';

import '../../../../../../core/theme/app_spacing.dart';
import '../../../../../../core/widgets/app_svg_icon.dart';
import '../../../../../../l10n/generated/app_localizations.dart';

/// Step 2 header: section title plus the create / browse entry points.
///
/// Both actions stack under the title below 420 px so the title never gets
/// squeezed on a phone.
class WizardCharacterStepHeader extends StatelessWidget {
  const WizardCharacterStepHeader({
    super.key,
    required this.l10n,
    required this.onNewCharacter,
    required this.onOpenSelection,
  });

  final AppLocalizations l10n;
  final VoidCallback onNewCharacter;
  final VoidCallback onOpenSelection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final stackActions = constraints.maxWidth < 420;
        if (stackActions) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppSvgIcon('group', size: 20, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.characterSelectionTitle,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: onNewCharacter,
                    icon: const AppSvgIcon('person_add', size: 16),
                    label: Text(l10n.newCharacterAction),
                  ),
                  OutlinedButton.icon(
                    onPressed: onOpenSelection,
                    icon: const AppSvgIcon('person_search', size: 16),
                    label: Text(l10n.fullscreenSelectionAction),
                  ),
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            AppSvgIcon('group', size: 20, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.characterSelectionTitle,
                style: theme.textTheme.titleMedium,
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: onNewCharacter,
              icon: const AppSvgIcon('person_add', size: 16),
              label: Text(l10n.newCharacterAction),
            ),
            const SizedBox(width: AppSpacing.xs),
            OutlinedButton.icon(
              onPressed: onOpenSelection,
              icon: const AppSvgIcon('person_search', size: 16),
              label: Text(l10n.fullscreenSelectionAction),
            ),
          ],
        );
      },
    );
  }
}
