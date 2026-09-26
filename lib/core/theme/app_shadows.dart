import 'package:flutter/material.dart';

/// NarrAItor 阴影令牌系统
///
/// 遵循 Editorial Narrative Workspace 克制规范：
/// - 弱阴影、低对比度
/// - 消除过度高斯模糊与发光感 (Glow)
/// - 消除彩色投影外框
/// - 严格适配浅色（纸质感）与暗色（高对比度）模式
class AppShadows {
  AppShadows._();

  /// 无阴影（纯平风格）
  static const List<BoxShadow> none = <BoxShadow>[];

  /// 微弱阴影 — 用于卡片、ListItem 悬浮与微交互 (elevation ~1)
  static List<BoxShadow> subtle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return <BoxShadow>[
      BoxShadow(
        color: isDark
            ? Colors.black.withValues(alpha: 0.28)
            : Colors.black.withValues(alpha: 0.04),
        blurRadius: 4,
        offset: const Offset(0, 1),
      ),
    ];
  }

  /// 中度阴影 — 用于浮起卡片、下拉菜单、快捷菜单 (elevation ~3)
  static List<BoxShadow> elevated(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return <BoxShadow>[
      BoxShadow(
        color: isDark
            ? Colors.black.withValues(alpha: 0.38)
            : Colors.black.withValues(alpha: 0.07),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ];
  }

  /// 模态阴影 — 用于 Dialog、浮层面板 (elevation ~6)
  static List<BoxShadow> dialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return <BoxShadow>[
      BoxShadow(
        color: isDark
            ? Colors.black.withValues(alpha: 0.48)
            : Colors.black.withValues(alpha: 0.12),
        blurRadius: 20,
        offset: const Offset(0, 8),
      ),
    ];
  }
}
