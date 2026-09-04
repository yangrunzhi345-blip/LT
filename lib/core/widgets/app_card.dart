import 'package:flutter/material.dart';

import '../theme/app_borders.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final bool selected;
  final bool highlighted;
  final double? borderRadius;
  final Color? backgroundColor;
  final Color? borderColor;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.selected = false,
    this.highlighted = false,
    this.borderRadius,
    this.backgroundColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(borderRadius ?? AppRadius.md);
    final bg = backgroundColor ??
        (highlighted
            ? (isDark
                ? AppColors.darkPrimary.withValues(alpha: 0.10)
                : AppColors.primaryLight.withValues(alpha: 0.55))
            : (isDark ? AppColors.darkSurface : AppColors.surfaceElevated));
    final side = BorderSide(
      color: borderColor ??
          (selected
              ? AppBorders.selectedColor(context)
              : AppBorders.defaultColor(context)),
      width: selected ? 1.2 : 1,
    );

    final content = Padding(
      padding: padding ?? const EdgeInsets.all(AppSpacing.md),
      child: child,
    );

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: radius, side: side),
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? content
            : InkWell(
                onTap: onTap,
                child: content,
              ),
      ),
    );
  }
}
