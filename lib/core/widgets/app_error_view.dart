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

  /// 对展示给用户的错误说明进行脱敏处理，杜绝泄露 API Key、SQL、内部路径与堆栈跟踪。
  static String? sanitizeErrorText(String? input) {
    if (input == null || input.trim().isEmpty) return null;
    var text = input;

    // 1. API Keys & Bearer tokens
    text = text.replaceAll(
      RegExp(r'sk-[a-zA-Z0-9]{8,}', caseSensitive: false),
      '[REDACTED_KEY]',
    );
    text = text.replaceAll(
      RegExp(r'Authorization:\s*(Bearer\s+)?[\w.\-]+', caseSensitive: false),
      'Authorization: [REDACTED]',
    );
    text = text.replaceAll(
      RegExp(r'Bearer\s+[\w.\-]+', caseSensitive: false),
      'Bearer [REDACTED]',
    );
    text = text.replaceAll(
      RegExp(r'x-api-key["\s:=]+[a-zA-Z0-9._\-]+', caseSensitive: false),
      'x-api-key: [REDACTED]',
    );

    // 2. SQL 语句与 SQLite 异常
    text = text.replaceAll(
      RegExp(
        r'(SELECT|INSERT INTO|UPDATE|DELETE FROM|CREATE TABLE|DROP TABLE|ALTER TABLE)\s+.*?(?=;|\n|$)',
        caseSensitive: false,
      ),
      '[DATABASE_QUERY]',
    );
    text = text.replaceAll(
      RegExp(r'sqlite[3]?\s+error.*', caseSensitive: false),
      'Database operation failed',
    );
    text = text.replaceAll(
      RegExp(r'DatabaseException\(.*?\)', caseSensitive: false),
      'Database error',
    );

    // 3. 内部文件路径与 URI
    text = text.replaceAll(
      RegExp(r'(/home|/data|/usr|/var|/tmp|[A-Z]:\\)[\w./\\-]+'),
      '[INTERNAL_PATH]',
    );
    text = text.replaceAll(
      RegExp(r'file:///[\w./\\-]+'),
      '[INTERNAL_URI]',
    );

    // 4. 堆栈跟踪与内部运行时源码标识
    text = text.replaceAll(
      RegExp(r'#\d+\s+.*(\n|$)', caseSensitive: false),
      '',
    );
    text = text.replaceAll(
      RegExp(r'(dart:|package:)[\w./\\-]+'),
      '[INTERNAL_TRACE]',
    );

    final result = text.trim();
    return result.isEmpty ? null : result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final effectiveTitle = title ?? l10n?.pageLoadError ?? 'Error';
    final effectiveRetryLabel = retryLabel ?? l10n?.retryAction ?? 'Retry';
    final sanitizedMessage = sanitizeErrorText(message);
    final sanitizedDetails = sanitizeErrorText(details);

    Widget? effectiveAction = actionWidget;
    if (effectiveAction == null && onRetry != null) {
      effectiveAction = AppSecondaryButton(
        label: effectiveRetryLabel,
        icon: Icons.refresh,
        onPressed: onRetry,
      );
    }

    return Center(
      child: SingleChildScrollView(
        padding: padding ?? const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
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
              if (sanitizedMessage != null && sanitizedMessage.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Text(
                    sanitizedMessage,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
              if (sanitizedDetails != null && sanitizedDetails.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Text(
                    sanitizedDetails,
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
      ),
    );
  }
}
