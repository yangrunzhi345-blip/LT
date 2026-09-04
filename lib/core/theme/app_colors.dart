import 'package:flutter/material.dart';

/// NarrAItor 配色系统 — 文学极简色板 + 6 主题 + 无渐变
///
/// 设计原则（v2.9 去 AI 味）：
/// - 单色基底 + 仅交互元素使用 accent
/// - 暖棕色主色（皮革/书页感），替代紫蓝"AI 科技"色
/// - 无渐变，纯色扁平化
/// - 暖白纸质感背景保留
class AppColors {
  AppColors._();

  // ─── 主色调（v2.9.1: 高对比度经典蓝） ───
  /// 经典蓝主色 — WCAG AA 对比度 7:1 vs 暖白纸背景
  static const primary = Color(0xFF1D4ED8);

  /// 浅蓝主色背景 — 选中态/标签背景
  static const primaryLight = Color(0xFFDBEAFE);

  /// 辅色 — 用于交互元素（按钮/链接/选中态文字）
  static const accent = Color(0xFF2563EB);

  // ─── 背景色（保留 v2.8.1 暖白纸质感） ───
  /// 暖白 — 替代纯白 FFFFFF，带纸质感
  static const background = Color(0xFFFBFAF8);

  /// 暖灰表面 — 替代 iOS 灰 F2F2F7
  static const surface = Color(0xFFF3F1ED);
  static const inputBg = Color(0xFFF3F1ED);

  /// 浮起表面 — 用于 elevation > 0 的卡片
  static const surfaceElevated = Color(0xFFF8F6F3);

  // ─── 文字色（保留 v2.8.1） ───
  /// 暖黑 — 非纯黑，带纸墨感
  static const textPrimary = Color(0xFF1C1B18);

  /// 暖灰 — 替代 iOS 灰 8E8E93
  static const textSecondary = Color(0xFF787670);
  static const textDisabled = Color(0xFFBFBCB5);

  // ─── 聊天气泡 ───
  static const bubbleUser = Color(0xFF1D4ED8);
  static const bubbleAi = Color(0xFFF3F1ED);

  // ─── 功能色（保留） ───
  static const success = Color(0xFF10B981); // emerald-500
  static const warning = Color(0xFFF59E0B); // amber-500
  static const error = Color(0xFFEF4444); // red-500

  // ─── 暗色模式 — 高对比度 ───
  static const darkPrimary = Color(0xFF7CB3FF);
  static const darkAccent = Color(0xFF4F8DFF);

  /// 暗色背景
  static const darkBackground = Color(0xFF0E0F12);
  static const darkSurface = Color(0xFF1A1D24);
  static const darkSurfaceElevated = Color(0xFF20242D);

  /// 暗色文字
  static const darkTextPrimary = Color(0xFFF5F7FA);
  static const darkTextSecondary = Color(0xFFB8C0CC);
  static const darkTextMuted = Color(0xFF8A94A6);
  static const darkBubbleAi = Color(0xFF252220);

  // ─── 12 套预设主题色板（与设置中心主题选择保持一致） ───
  static const Map<String, Color> colorSeeds = {
    '海洋蓝': Color(0xFF3B82F6), // blue-500 — 温和海洋蓝
    '日落橙': Color(0xFFEA580C), // orange-600 — 深沉日落
    '森林绿': Color(0xFF16A34A), // green-600 — 自然森林
    '紫罗兰': Color(0xFF9333EA), // purple-600 — 浓郁紫
    '玫瑰粉': Color(0xFFE11D48), // rose-600 — 复古玫瑰
    '极简灰': Color(0xFF6B7280), // gray-500 — 中性灰
    '湖水青': Color(0xFF0891B2),
    '青瓷绿': Color(0xFF0D9488),
    '琥珀金': Color(0xFFD97706),
    '珊瑚红': Color(0xFFDC2626),
    '靛青蓝': Color(0xFF4F46E5),
    '摩卡棕': Color(0xFF9A6846),
  };

  static Color seedForName(String name) =>
      colorSeeds[name] ?? colorSeeds['海洋蓝']!;

  /// 青色强调 — 资源库标签/图标/标题
  static const teal = Color(0xFF4ECDC4);

  // ─── 角色头像色板（保留） ───
  static const List<Color> avatarColors = [
    teal, // 青
    Color(0xFFFF6B6B), // 珊瑚
    Color(0xFFFFE66D), // 金
    Color(0xFF51CF66), // 绿
    Color(0xFF845EF7), // 紫
    Color(0xFFFF922B), // 橙
    Color(0xFF20C997), // 翠
    Color(0xFFF06595), // 粉
  ];

  static Color avatarColor(int index) =>
      avatarColors[index % avatarColors.length];

  // ─── AI 气泡左侧装饰条颜色（v2.9: 纯色，无渐变） ───
  static const Color bubbleAccentBar = accent;

  // Chat surface colors used by the centered conversation layout.
  static const Color chatUser = Color(0xFFFF8A3D);
  static const Color chatAi = Color(0xFFEEF2F7);
  static const Color chatAiBorder = Color(0xFFDFE5EC);
}
