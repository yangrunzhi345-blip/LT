import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// 全局统一加载状态组件 [AppLoadingView]
///
/// 遵循 Material 3 与 LT 设计规范，提供页面级与嵌入级加载展示。
class AppLoadingView extends StatelessWidget {
  final String? message;
  final double size;
  final bool scrim;
  final EdgeInsetsGeometry? padding;

  const AppLoadingView({
    super.key,
    this.message,
    this.size = 40.0,
    this.scrim = false,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final Widget indicator = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            strokeWidth: 3.0,
            valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
          ),
        ),
        if (message != null && message!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Text(
              message!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );

    final Widget content = Center(
      child: SingleChildScrollView(
        padding: padding ?? const EdgeInsets.all(AppSpacing.xl),
        child: indicator,
      ),
    );

    if (scrim) {
      return Container(
        color: Colors.black.withValues(alpha: 0.35),
        child: content,
      );
    }

    return content;
  }
}
