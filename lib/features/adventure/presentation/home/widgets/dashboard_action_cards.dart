import 'package:flutter/material.dart';

import '../../../../../core/theme/app_dimensions.dart';
import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/app_card.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

/// 冒险工坊启动入口组件
/// 遵循 Editorial 版式设计，克制优雅，消除 SaaS 宣传浮夸感，以内容为优先
class DashboardActionCards extends StatelessWidget {
  final VoidCallback onOpenWizard;
  final VoidCallback onOpenLibrary;
  final VoidCallback? onOpenPresetScenes;
  final VoidCallback? onOpenSettings;

  const DashboardActionCards({
    super.key,
    required this.onOpenWizard,
    required this.onOpenLibrary,
    this.onOpenPresetScenes,
    this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // 主操作卡片：向导定制
    final wizardCard = AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: onOpenWizard,
      borderColor: scheme.primary.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  Icons.explore_rounded,
                  color: scheme.primary,
                  size: 18,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  l10n.dashboardWizardBadge,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.dashboardWizardCardTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            l10n.dashboardWizardCardDesc,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 11,
              height: 1.35,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppDimensions.controlHeightSm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.dashboardWizardCardAction,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 13,
                  color: scheme.primary,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // 次级入口：预设场景
    final presetScenesCard = _SecondaryActionCard(
      icon: Icons.movie_filter_outlined,
      badgeText: l10n.dashboardPresetBadge,
      title: l10n.dashboardPresetCardTitle,
      description: l10n.dashboardPresetCardDesc,
      actionLabel: l10n.dashboardPresetCardAction,
      onTap: onOpenPresetScenes ?? () {},
    );

    // 内容入口：资料库
    final libraryCard = _SecondaryActionCard(
      icon: Icons.auto_stories_outlined,
      badgeText: l10n.dashboardLibraryBadge,
      title: l10n.dashboardLibraryCardTitle,
      description: l10n.dashboardLibraryCardDesc,
      actionLabel: l10n.dashboardLibraryCardAction,
      onTap: onOpenLibrary,
    );

    // 低频辅助入口：系统设置
    final settingsCard = _SecondaryActionCard(
      icon: Icons.tune_outlined,
      badgeText: l10n.dashboardSettingsBadge,
      title: l10n.dashboardSettingsCardTitle,
      description: l10n.dashboardSettingsCardDesc,
      actionLabel: l10n.dashboardSettingsCardAction,
      onTap: onOpenSettings ?? () {},
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isWide = width >= 760;
        final isMedium = width >= 500 && width < 760;

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 4, child: wizardCard),
              const SizedBox(width: AppSpacing.md),
              Expanded(flex: 3, child: presetScenesCard),
              const SizedBox(width: AppSpacing.md),
              Expanded(flex: 3, child: libraryCard),
              const SizedBox(width: AppSpacing.md),
              Expanded(flex: 3, child: settingsCard),
            ],
          );
        } else if (isMedium) {
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: wizardCard),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: presetScenesCard),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: libraryCard),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: settingsCard),
                ],
              ),
            ],
          );
        }

        // 紧凑移动端单列 (保证在 320px 零溢出)
        return Column(
          children: [
            wizardCard,
            const SizedBox(height: AppSpacing.sm),
            presetScenesCard,
            const SizedBox(height: AppSpacing.sm),
            libraryCard,
            const SizedBox(height: AppSpacing.sm),
            settingsCard,
          ],
        );
      },
    );
  }
}

class _SecondaryActionCard extends StatelessWidget {
  final IconData icon;
  final String badgeText;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback onTap;

  const _SecondaryActionCard({
    required this.icon,
    required this.badgeText,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  icon,
                  color: scheme.onSurfaceVariant,
                  size: 16,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 11,
              height: 1.35,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppDimensions.controlHeightSm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  actionLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 13,
                  color: scheme.primary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
