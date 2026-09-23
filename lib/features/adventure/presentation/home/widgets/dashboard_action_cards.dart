import 'package:flutter/material.dart';

import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

/// 冒险工坊启动入口卡片组
/// 遵循 Editorial 版式设计，克制优雅，消除 SaaS 宣传浮夸感
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

    final wizardCard = _ActionCard(
      icon: Icons.explore_rounded,
      accentColor: scheme.primary,
      badgeText: l10n.dashboardWizardBadge,
      title: l10n.dashboardWizardCardTitle,
      description: l10n.dashboardWizardCardDesc,
      actionLabel: l10n.dashboardWizardCardAction,
      onTap: onOpenWizard,
      isPrimary: true,
    );

    final presetScenesCard = _ActionCard(
      icon: Icons.movie_filter_rounded,
      accentColor: const Color(0xFF2563EB),
      badgeText: l10n.dashboardPresetBadge,
      title: l10n.dashboardPresetCardTitle,
      description: l10n.dashboardPresetCardDesc,
      actionLabel: l10n.dashboardPresetCardAction,
      onTap: onOpenPresetScenes ?? () {},
    );

    final libraryCard = _ActionCard(
      icon: Icons.auto_stories_rounded,
      accentColor: const Color(0xFF0D9488),
      badgeText: l10n.dashboardLibraryBadge,
      title: l10n.dashboardLibraryCardTitle,
      description: l10n.dashboardLibraryCardDesc,
      actionLabel: l10n.dashboardLibraryCardAction,
      onTap: onOpenLibrary,
    );

    final settingsCard = _ActionCard(
      icon: Icons.tune_rounded,
      accentColor: const Color(0xFFEA580C),
      badgeText: l10n.dashboardSettingsBadge,
      title: l10n.dashboardSettingsCardTitle,
      description: l10n.dashboardSettingsCardDesc,
      actionLabel: l10n.dashboardSettingsCardAction,
      onTap: onOpenSettings ?? () {},
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isWide = width >= 900;
        final isMedium = width >= 560 && width < 900;

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: wizardCard),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: presetScenesCard),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: libraryCard),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: settingsCard),
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

        // 紧凑移动端布局 (单列，严禁在 320px 下溢出)
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

class _ActionCard extends StatefulWidget {
  final IconData icon;
  final Color accentColor;
  final String badgeText;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback onTap;
  final bool isPrimary;

  const _ActionCard({
    required this.icon,
    required this.accentColor,
    required this.badgeText,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  State<_ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<_ActionCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: widget.isPrimary
                ? scheme.primaryContainer
                    .withValues(alpha: _isHovered ? 0.35 : 0.22)
                : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: widget.isPrimary
                  ? scheme.primary.withValues(alpha: _isHovered ? 0.6 : 0.3)
                  : scheme.outlineVariant
                      .withValues(alpha: _isHovered ? 0.6 : 0.3),
              width: widget.isPrimary ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: widget.accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(
                      widget.icon,
                      color: widget.accentColor,
                      size: 18,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: widget.accentColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      widget.badgeText,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: widget.accentColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                widget.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                widget.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Text(
                    widget.actionLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: widget.accentColor,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 13,
                    color: widget.accentColor,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
