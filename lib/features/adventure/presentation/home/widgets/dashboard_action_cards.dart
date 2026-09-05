import 'package:flutter/material.dart';

import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';

/// 冒险工坊核心启动入口卡片组 (纯白板·用户自主定义)
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final wizardCard = _ActionCard(
      icon: Icons.explore_rounded,
      accentColor: scheme.primary,
      badgeText: '向导定制',
      title: '四步向导定制',
      description: '白板起步，自主设定世界观、角色卡、序章开局与初始行动分支。',
      actionLabel: '启动向导',
      onTap: onOpenWizard,
      isPrimary: true,
    );

    final presetScenesCard = _ActionCard(
      icon: Icons.movie_filter_rounded,
      accentColor: const Color(0xFF3B82F6),
      badgeText: '完整剧本',
      title: '预存场景工坊',
      description: '浏览已构建的预设冒险场景剧本，支持一键启程或载入向导微调。',
      actionLabel: '查看预存场景',
      onTap: onOpenPresetScenes ?? () {},
    );

    final libraryCard = _ActionCard(
      icon: Icons.auto_stories_rounded,
      accentColor: const Color(0xFF2A9D8F),
      badgeText: '全景资产',
      title: '资料库',
      description: '查阅与管理你所创建的世界观预设、角色卡档案与 NPC 关系网络。',
      actionLabel: '管理资料库',
      onTap: onOpenLibrary,
    );

    final settingsCard = _ActionCard(
      icon: Icons.tune_rounded,
      accentColor: const Color(0xFFE76F51),
      badgeText: '模型与系统',
      title: '系统设置中心',
      description: '配置大模型 API 密钥、会话推演参数、外观主题与历史数据管理。',
      actionLabel: '进入设置',
      onTap: onOpenSettings ?? () {},
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isUltraWide = constraints.maxWidth >= 1180;
        final isTabletOrMedium = constraints.maxWidth >= 640 && !isUltraWide;

        if (isUltraWide) {
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
        } else if (isTabletOrMedium) {
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

        // 紧凑移动端布局
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
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: widget.isPrimary
                ? scheme.primaryContainer.withValues(alpha: _isHovered ? 0.45 : 0.3)
                : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: widget.isPrimary
                  ? scheme.primary.withValues(alpha: _isHovered ? 0.7 : 0.35)
                  : scheme.outlineVariant.withValues(alpha: _isHovered ? 0.6 : 0.3),
              width: widget.isPrimary ? 1.5 : 1.0,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: widget.accentColor.withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: widget.accentColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(
                      widget.icon,
                      color: widget.accentColor,
                      size: 22,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: widget.accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Text(
                      widget.badgeText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: widget.accentColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                widget.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                widget.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Text(
                    widget.actionLabel,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: widget.accentColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 14,
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
