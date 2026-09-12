import 'package:flutter/material.dart';

/// 统一响应式屏幕断点类型
enum ResponsiveBreakpoint {
  /// 手机 / 极窄屏幕 (< 600)
  compact,

  /// 平板 / 紧凑桌面 (600–899)
  medium,

  /// 桌面 / 宽屏 (>= 900)
  expanded,
}

/// LT 统一响应式断点基础设施
///
/// 消除散落在各处的魔法数值 (420, 560, 640, 700, 720, 760, 800, 1180)，
/// 建立统一的页面级与组件级响应式判断规范。
class AppBreakpoints {
  AppBreakpoints._();

  // ─── 页面级标准断点界限 ───
  /// Compact 紧凑屏上限逻辑宽度 (< 600)
  static const double compactMax = 599.0;

  /// Medium 中屏下限 (>= 600)
  static const double mediumMin = 600.0;

  /// Medium 中屏上限 (< 900)
  static const double mediumMax = 899.0;

  /// Expanded 展开桌面屏下限 (>= 900)
  static const double expandedMin = 900.0;

  // ─── 内容最大宽度边界（避免大屏无限拉伸，强化 Editorial 体验） ───
  /// 叙事与小说阅读舒适正文最大宽度 (约 35–45 个中文字符)
  static const double narrativeMaxWidth = 760.0;

  /// 表单与设置面板单列舒适最大宽度
  static const double formMaxWidth = 640.0;

  /// 资料库与资产卡片画廊最大宽度
  static const double contentMaxWidth = 1200.0;

  // ─── 最低兼容逻辑宽度（硬门槛） ───
  /// AGENTS.md 规定的最低兼容逻辑宽度，绝不允许出现横向 RenderFlex Overflow
  static const double minSupportedWidth = 320.0;

  /// 根据宽度数值获取断点类型
  static ResponsiveBreakpoint fromWidth(double width) {
    if (width < mediumMin) return ResponsiveBreakpoint.compact;
    if (width < expandedMin) return ResponsiveBreakpoint.medium;
    return ResponsiveBreakpoint.expanded;
  }

  /// 根据当前可用约束 [BoxConstraints] 判断
  static ResponsiveBreakpoint fromConstraints(BoxConstraints constraints) {
    return fromWidth(constraints.maxWidth);
  }

  /// 根据当前上下文视口 [BuildContext] 判断
  static ResponsiveBreakpoint of(BuildContext context) {
    return fromWidth(MediaQuery.sizeOf(context).width);
  }

  /// 是否为手机 / 紧凑尺寸 (< 600)
  static bool isCompact(BuildContext context) =>
      of(context) == ResponsiveBreakpoint.compact;

  /// 是否为平板 / 中等尺寸 (600–899)
  static bool isMedium(BuildContext context) =>
      of(context) == ResponsiveBreakpoint.medium;

  /// 是否为桌面 / 宽屏尺寸 (>= 900)
  static bool isExpanded(BuildContext context) =>
      of(context) == ResponsiveBreakpoint.expanded;

  /// 语义化别名
  static bool isMobile(BuildContext context) => isCompact(context);
  static bool isTablet(BuildContext context) => isMedium(context);
  static bool isDesktop(BuildContext context) => isExpanded(context);
}
