import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'app_breakpoints.dart';

/// 内容容器宽度风格
enum ContentWidthStyle {
  /// 叙事与小说阅读模式 (最大 760px)
  reading,

  /// 表单与设置面板模式 (最大 640px)
  form,

  /// 资料库画廊与工作区模式 (最大 1200px)
  workspace,

  /// 不限制宽度
  full,
}

/// 限制最大内容宽度的居中自适应容器
///
/// 遵循 Editorial Workspace 理念，防止超宽显示器下长文本与表单无限横向拉伸。
class AdaptiveContainer extends StatelessWidget {
  final Widget child;
  final ContentWidthStyle style;
  final double? customMaxWidth;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry alignment;

  const AdaptiveContainer({
    super.key,
    required this.child,
    this.style = ContentWidthStyle.workspace,
    this.customMaxWidth,
    this.padding,
    this.alignment = Alignment.topCenter,
  });

  /// 阅读型容器专有构造器 (最大 760px)
  const AdaptiveContainer.reading({
    super.key,
    required this.child,
    this.padding,
    this.alignment = Alignment.topCenter,
  })  : style = ContentWidthStyle.reading,
        customMaxWidth = null;

  /// 表单型容器专有构造器 (最大 640px)
  const AdaptiveContainer.form({
    super.key,
    required this.child,
    this.padding,
    this.alignment = Alignment.topCenter,
  })  : style = ContentWidthStyle.form,
        customMaxWidth = null;

  double get _effectiveMaxWidth {
    if (customMaxWidth != null) return customMaxWidth!;
    return switch (style) {
      ContentWidthStyle.reading => AppBreakpoints.narrativeMaxWidth,
      ContentWidthStyle.form => AppBreakpoints.formMaxWidth,
      ContentWidthStyle.workspace => AppBreakpoints.contentMaxWidth,
      ContentWidthStyle.full => double.infinity,
    };
  }

  @override
  Widget build(BuildContext context) {
    Widget content = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: _effectiveMaxWidth),
      child: child,
    );

    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }

    return Align(
      alignment: alignment,
      child: content,
    );
  }
}

/// 根据视口断点提供自适应 padding 的便捷辅助工具
class ResponsivePadding {
  ResponsivePadding._();

  /// 页面水平边距：compact 16, medium 24, expanded 32
  static EdgeInsets pageHorizontal(BuildContext context) {
    final bp = AppBreakpoints.of(context);
    return switch (bp) {
      ResponsiveBreakpoint.compact =>
        const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      ResponsiveBreakpoint.medium =>
        const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      ResponsiveBreakpoint.expanded =>
        const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
    };
  }

  /// 页面完整外边距：compact 16, medium 20/24, expanded 24/32
  static EdgeInsets page(BuildContext context) {
    final bp = AppBreakpoints.of(context);
    return switch (bp) {
      ResponsiveBreakpoint.compact => const EdgeInsets.all(AppSpacing.lg),
      ResponsiveBreakpoint.medium => const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.lg,
        ),
      ResponsiveBreakpoint.expanded => const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxl,
          vertical: AppSpacing.xl,
        ),
    };
  }
}
