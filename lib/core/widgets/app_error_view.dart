import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../theme/app_spacing.dart';
import 'app_buttons.dart';

/// 全局统一错误与重试状态组件 [AppErrorView]
///
/// 用于页面或区块加载失败、网络异常、操作受阻等场景的统一视觉与重试交互。
class AppErrorView extends StatelessWidget {
  final String? title;
  final String? message;
  final String? details;
  final IconData icon;
  final VoidCallback? onRetry;
  final String? retryLabel;
  final Widget? actionWidget;
  final EdgeInsetsGeometry? padding;

  const AppErrorView({
    super.key,
    this.title,
    this.message,
    this.details,
    this.icon = Icons.error_outline,
    this.onRetry,
    this.retryLabel,
    this.actionWidget,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final effectiveTitle = title ?? l10n?.pageLoadError ?? 'Error';
    final effectiveRetryLabel = retryLabel ?? l10n?.retryAction ?? 'Retry';

    Widget? effectiveAction = actionWidget;
    if (effectiveAction == null && onRetry != null) {
      effectiveAction = AppSecondaryButton(
        label: effectiveRetryLabel,
        icon: Icons.refresh,
        onPressed: onRetry,
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
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 40,
                color: colorScheme.error,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              effectiveTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            if (message != null && message!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
            ],
            if (details != null && details!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(
                  details!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                    fontFamily: 'monospace',
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
