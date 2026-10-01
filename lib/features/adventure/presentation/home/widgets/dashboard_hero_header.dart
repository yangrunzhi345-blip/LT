import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/app_svg_icon.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../widgets/app_dialogs.dart';

/// Quiet workspace title, showing service configuration only when needed.
class DashboardHeroHeader extends ConsumerWidget {
  const DashboardHeroHeader(
      {super.key, this.onMenuPressed, this.onOpenSettings});
  final VoidCallback? onMenuPressed;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final configured =
        ref.watch(chatProvider.select((chat) => chat.isKeyConfigured));
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            if (onMenuPressed != null)
              IconButton(
                  tooltip: l10n.dashboardToggleSidebar,
                  onPressed: onMenuPressed,
                  icon: const AppSvgIcon('panel')),
            Expanded(
                child: Text(l10n.workbenchAdventures,
                    style: Theme.of(context).textTheme.titleLarge)),
            if (!configured)
              IconButton(
                  tooltip: l10n.dashboardConfigureApiKey,
                  onPressed: onOpenSettings ?? () => showApiSettings(context),
                  icon: AppSvgIcon('settings',
                      color: Theme.of(context).colorScheme.error)),
          ],
        ),
      ),
    );
  }
}
