import 'package:flutter/material.dart';

import '../theme/app_borders.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

/// 统一表单分块布局组件 [AppFormSection]
///
/// 替代各页面散落重复的 Column + Padding + Text 模式，提供统一的：
/// - 分区标题 (section title)
/// - 辅助描述 (description)
/// - 头部右侧操作区 (headerAction，如开关、重置、辅助说明)
/// - 规范间距与子控件列表 (spacing + children / child)
/// - 分区级错误区域 (error area)
/// - 可选卡片化背景 (card)
class AppFormSection extends StatelessWidget {
  final String? title;
  final Widget? titleWidget;
  final String? description;
  final Widget? descriptionWidget;
  final Widget? headerAction;
  final List<Widget>? children;
  final Widget? child;
  final String? errorText;
  final Widget? errorWidget;
  final double spacing;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool card;
  final bool showDivider;

  const AppFormSection({
    super.key,
    this.title,
    this.titleWidget,
    this.description,
    this.descriptionWidget,
    this.headerAction,
    this.children,
    this.child,
    this.errorText,
    this.errorWidget,
    this.spacing = AppSpacing.md,
    this.padding,
    this.margin,
    this.card = false,
    this.showDivider = false,
  }) : assert(child != null || children != null,
            'Either child or children must be provided to AppFormSection');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final hasHeader = title != null ||
        titleWidget != null ||
        description != null ||
        descriptionWidget != null ||
        headerAction != null;

    final Widget? effectiveHeader = hasHeader
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null || titleWidget != null || headerAction != null)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: titleWidget ??
                          Text(
                            title!,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                    ),
                    if (headerAction != null) ...[
                      const SizedBox(width: AppSpacing.sm),
                      headerAction!,
                    ],
                  ],
                ),
              if (description != null || descriptionWidget != null) ...[
                const SizedBox(height: AppSpacing.xs),
                descriptionWidget ??
                    Text(
                      description!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
              ],
            ],
          )
        : null;

    final Widget? effectiveError = errorWidget ??
        (errorText != null && errorText!.isNotEmpty
            ? Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(
                    color: colorScheme.error.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline,
                        size: 16, color: colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        errorText!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : null);

    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (effectiveHeader != null) ...[
          effectiveHeader,
          const SizedBox(height: AppSpacing.sm),
        ],
        if (effectiveError != null) ...[
          effectiveError,
          const SizedBox(height: AppSpacing.sm),
        ],
        if (child != null)
          child!
        else if (children != null)
          for (int i = 0; i < children!.length; i++) ...[
            if (i > 0) SizedBox(height: spacing),
            children![i],
          ],
        if (showDivider) ...[
          const SizedBox(height: AppSpacing.lg),
          const Divider(height: 1),
        ],
      ],
    );

    Widget result = content;
    if (card) {
      result = Container(
        padding: padding ?? const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppBorders.defaultColor(context)),
        ),
        child: result,
      );
    } else if (padding != null) {
      result = Padding(padding: padding!, child: result);
    }

    if (margin != null) {
      result = Padding(padding: margin!, child: result);
    } else if (!card && !showDivider) {
      result = Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: result,
      );
    }

    return result;
  }
}

/// 规划文档别名兼容
typedef LtFormSection = AppFormSection;
