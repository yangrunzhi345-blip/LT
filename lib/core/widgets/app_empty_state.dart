import 'package:flutter/material.dart';
import '../theme/app_spacing.dart';
import 'app_svg_icon.dart';

/// 全局统一空状态组件 (AppEmptyState)
///
/// Editorial Workbench 规范：层级由排版与留白承担，而不是容器。
/// - 小尺寸 SVG（默认 28px），不使用圆形底衬或卡片
/// - 标题 14–16px / w600
/// - 说明 12–13px / muted
/// - 可选一个主要操作
class AppEmptyState extends StatelessWidget {
  final String? icon;
  final String title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double iconSize;

  const AppEmptyState({
    super.key,
    this.icon,
    required this.title,
    this.description,
    this.actionLabel,
    this.onAction,
    this.iconSize = 28,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon case final icon?) ...[
              AppSvgIcon(
                icon,
                size: iconSize,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            if (description != null) ...[
              const SizedBox(height: AppSpacing.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Text(
                  description!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
