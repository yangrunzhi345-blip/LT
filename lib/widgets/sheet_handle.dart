import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

/// 底部弹出层拖拽手柄 — 统一视觉风格，消除 5 处复制粘贴
class SheetHandle extends StatelessWidget {
  final double width;
  final double height;
  final Color? color;

  const SheetHandle({
    super.key,
    this.width = 36,
    this.height = 4,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final handleColor =
        color ?? (isDark ? AppColors.darkTextSecondary : Colors.grey.shade400);

    return Center(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: handleColor,
          borderRadius: BorderRadius.circular(height / 2),
        ),
      ),
    );
  }
}
