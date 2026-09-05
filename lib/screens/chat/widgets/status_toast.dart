import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// 状态变化 Toast — 在屏幕顶部短暂浮现后自动消失
class StatusToast {
  static OverlayEntry? _currentEntry;

  /// 显示状态变化提示
  /// [topOffset] 额外的顶部偏移（如离线横幅可见时需下移）
  static const bool _enabled = false;

  static void show(
    BuildContext context, {
    required String icon,
    required int delta,
    required int current,
    required int max,
    double topOffset = 0,
  }) {
    if (!_enabled) return;
    // 移除之前的 toast
    _currentEntry?.remove();
    _currentEntry = null;


    final isPositive = delta >= 0;
    final color = isPositive ? AppColors.success : AppColors.error;
    final sign = isPositive ? '+' : '';

    final overlay = Overlay.of(context, rootOverlay: true);
    _currentEntry = OverlayEntry(
  builder: (ctx) {
    final mediaQuery = MediaQuery.maybeOf(ctx);
    final topPadding = mediaQuery?.padding.top ?? 0;
    return Positioned(
      top: topPadding + 8 + topOffset,
      left: 16,
      right: 16,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: -80.0, end: 0.0),
        duration: const Duration(milliseconds: 300),
        curve: Curves.elasticOut,
        builder: (ctx, value, child) => Transform.translate(
          offset: Offset(0, value),
          child: child,
        ),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(icon, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(
                  '$sign$delta',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$current/$max',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  },
);


    overlay.insert(_currentEntry!);

    // 2 秒后自动消失
    Future.delayed(const Duration(seconds: 2), () {
      _currentEntry?.remove();
      _currentEntry = null;
    });
  }
}
