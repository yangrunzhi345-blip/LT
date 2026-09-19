import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'app_buttons.dart';
export 'app_empty_state.dart';

/// 全局统一优雅空状态组件 [AppEmptyView]
///
/// 替代各页面手写空状态布局，统一提供图标、标题、说明文案与操作按钮。
class AppEmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? actionWidget;
  final double iconSize;
  final EdgeInsetsGeometry? padding;

  const AppEmptyView({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    this.description,
    this.actionLabel,
    this.onAction,
    this.actionWidget,
    this.iconSize = 56,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Widget? effectiveAction = actionWidget;
    if (effectiveAction == null && actionLabel != null && onAction != null) {
      effectiveAction = AppPrimaryButton(
        label: actionLabel!,
        icon: Icons.add,
        onPressed: onAction,
      );
    }

    return Center(
      child: Padding(
        padding: padding ?? const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: iconSize + 32,
              height: iconSize + 32,
              decoration: BoxDecoration(
                color:
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: iconSize,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            if (description != null) ...[
              const SizedBox(height: AppSpacing.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(
                  description!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
            ],
            if (effectiveAction != null) ...[
              const SizedBox(height: AppSpacing.lg),
              effectiveAction,
            ],
          ],
        ),
      ),
    );
  }
}
