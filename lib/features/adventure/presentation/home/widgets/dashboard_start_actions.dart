import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/workbench_section.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';

/// Compact start actions; settings belong to workspace navigation.
class DashboardStartActions extends StatelessWidget {
  const DashboardStartActions(
      {super.key,
      required this.onOpenWizard,
      required this.onOpenLibrary,
      this.onOpenPresetScenes});
  final VoidCallback onOpenWizard;
  final VoidCallback onOpenLibrary;
  final VoidCallback? onOpenPresetScenes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    return WorkbenchSection(
      title: l10n.sidebarNewAdventure,
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          FilledButton(
              key: const Key('dashboard-new-adventure'),
              onPressed: onOpenWizard,
              child: Text(l10n.dashboardWizardCardAction)),
          if (onOpenPresetScenes != null)
            TextButton(
                onPressed: onOpenPresetScenes,
                child: Text(l10n.dashboardPresetCardTitle)),
          TextButton(onPressed: onOpenLibrary, child: Text(l10n.navLibrary)),
        ],
      ),
    );
  }
}
