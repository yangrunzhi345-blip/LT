import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_dimensions.dart';
import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../widgets/app_dialogs.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

/// 冒险工坊顶部氛围横幅与状态指示器
/// 遵循 Editorial 版式风格，消除夸张发光渐变与 AI 营销口号，保持安静克制的文学质感
class DashboardHeroHeader extends ConsumerWidget {
  final VoidCallback? onMenuPressed;
  final VoidCallback? onOpenSettings;

  const DashboardHeroHeader({
    super.key,
    this.onMenuPressed,
    this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = _l10n(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chat = ref.watch(chatProvider);
    final isConfigured = chat.isKeyConfigured;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final isNarrow = width < 360;
          final isWide = width >= 720;
          final horizontalPad = isNarrow ? AppSpacing.sm : AppSpacing.xl;

          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPad,
              vertical: AppSpacing.sm + 4,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (onMenuPressed != null) ...[
                  IconButton(
                    icon: const Icon(Icons.menu_rounded),
                    tooltip: l10n.dashboardToggleSidebar,
                    onPressed: onMenuPressed,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: AppDimensions.controlHeightLg,
                      minHeight: AppDimensions.controlHeightLg,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
                if (!isNarrow) ...[
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Icon(
                      Icons.auto_stories_rounded,
                      color: scheme.primary,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.dashboardHeroTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.dashboardHeroSubtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                if (!isConfigured) ...[
                  if (isNarrow)
                    IconButton(
                      icon: Icon(
                        Icons.vpn_key_outlined,
                        color: scheme.error,
                        size: 20,
                      ),
                      tooltip: l10n.dashboardConfigureApiKey,
                      visualDensity: VisualDensity.compact,
                      onPressed:
                          onOpenSettings ?? () => showApiSettings(context),
                      constraints: const BoxConstraints(
                        minWidth: AppDimensions.controlHeightLg,
                        minHeight: AppDimensions.controlHeightLg,
                      ),
                    )
                  else
                    InkWell(
                      onTap: onOpenSettings ?? () => showApiSettings(context),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          border: Border.all(
                            color: scheme.error.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.vpn_key_outlined,
                              size: 13,
                              color: scheme.error,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              l10n.dashboardConfigureApiKey,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: scheme.error,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ] else if (isWide) ...[
                  FilledButton.tonalIcon(
                    onPressed: onOpenSettings ?? () => showApiSettings(context),
                    icon: const Icon(Icons.settings_outlined, size: 15),
                    label: Text(l10n.dashboardSystemSettings),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ] else ...[
                  IconButton(
                    icon: const Icon(Icons.settings_outlined, size: 20),
                    tooltip: l10n.dashboardSystemSettings,
                    visualDensity: VisualDensity.compact,
                    onPressed: onOpenSettings ?? () => showApiSettings(context),
                    constraints: const BoxConstraints(
                      minWidth: AppDimensions.controlHeightLg,
                      minHeight: AppDimensions.controlHeightLg,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
