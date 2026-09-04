import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

/// 全局通用 Loading 组件
class NarrAItorLoading extends StatelessWidget {
  final double size;
  final String? message;
  final bool scrim;

  const NarrAItorLoading({
    super.key,
    this.size = 48,
    this.message,
    this.scrim = false,
  });

  /// 行内迷你版 (16px, 用于按钮内)
  const NarrAItorLoading.mini({super.key, this.size = 16})
      : message = null,
        scrim = false;

  /// 标准版 (48px)
  const NarrAItorLoading.normal({super.key, this.message})
      : size = 48,
        scrim = false;

  /// 遮罩版
  const NarrAItorLoading.overlay({super.key, this.message})
      : size = 48,
        scrim = true;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Widget indicator;
    if (size <= 24) {
      indicator = SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(
            isDark ? AppColors.darkPrimary : AppColors.primary,
          ),
        ),
      );
    } else {
      indicator = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(
                isDark ? AppColors.darkPrimary : AppColors.primary,
              ),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ],
      );
    }

    if (scrim) {
      return Container(
        color: Colors.black.withValues(alpha: 0.3),
        child: Center(child: indicator),
      );
    }

    return Center(child: indicator);
  }
}

typedef LTLoading = NarrAItorLoading;
typedef AppLoading = NarrAItorLoading;
