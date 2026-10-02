import 'package:flutter/material.dart';

import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';
import 'dashboard_section.dart';

/// Runtime region: the entry into the state hub, framed as a first-class
/// dashboard group rather than a stray link at the end of the page.
class DashboardStateSection extends StatelessWidget {
  const DashboardStateSection({super.key, required this.onOpenStateHub});
  final VoidCallback onOpenStateHub;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final theme = Theme.of(context);
    return DashboardGroup(
      key: const Key('dashboard-group-runtime'),
      title: l10n.runtimeStateCurrent,
      action: TextButton(
        key: const Key('dashboard-runtime-state'),
        onPressed: onOpenStateHub,
        child: Text(l10n.dashboardOpenStateHub),
      ),
      child: Text(
        l10n.dashboardStateSummary,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
