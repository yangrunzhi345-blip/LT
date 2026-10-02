import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';
import 'dashboard_section.dart';

/// Start region: onboarding when the user has no story, a compact "start
/// something new" group once they do.
///
/// Exactly one dominant primary action exists at any time: the wizard is a
/// [FilledButton] only when no adventure is in progress. When a story exists the
/// "continue" action owns the primary weight and this entry drops to a quiet
/// [TextButton], so the page never shows two competing CTAs.
class DashboardStartActions extends StatelessWidget {
  const DashboardStartActions(
      {super.key,
      required this.onOpenWizard,
      required this.onOpenLibrary,
      this.onOpenPresetScenes,
      this.hasAdventure = false});
  final VoidCallback onOpenWizard;
  final VoidCallback onOpenLibrary;
  final VoidCallback? onOpenPresetScenes;

  /// Whether the user already has at least one adventure.
  final bool hasAdventure;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final theme = Theme.of(context);
    final wizard = hasAdventure
        ? TextButton(
            key: const Key('dashboard-new-adventure'),
            onPressed: onOpenWizard,
            child: Text(l10n.dashboardWizardCardAction))
        : FilledButton(
            key: const Key('dashboard-new-adventure'),
            onPressed: onOpenWizard,
            child: Text(l10n.dashboardWizardCardAction));
    return DashboardGroup(
      key: const Key('dashboard-group-start'),
      title: hasAdventure
          ? l10n.dashboardStartNewAdventure
          : l10n.dashboardStartFirstAdventure,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!hasAdventure) ...[
            Text(
              l10n.dashboardStartFirstAdventureDesc,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              wizard,
              if (onOpenPresetScenes != null)
                TextButton(
                    onPressed: onOpenPresetScenes,
                    child: Text(l10n.dashboardPresetCardTitle)),
              TextButton(
                  onPressed: onOpenLibrary, child: Text(l10n.navLibrary)),
            ],
          ),
        ],
      ),
    );
  }
}
