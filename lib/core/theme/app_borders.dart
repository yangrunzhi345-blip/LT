import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppBorders {
  AppBorders._();

  static Color defaultColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.08);
  }

  static Color selectedColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? AppColors.darkPrimary : AppColors.primary;
  }

  static Color dangerColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? AppColors.error.withValues(alpha: 0.75) : AppColors.error;
  }

  static BorderSide defaultSide(BuildContext context) =>
      BorderSide(color: defaultColor(context));

  static BorderSide selectedSide(BuildContext context) =>
      BorderSide(color: selectedColor(context), width: 1.2);

  static BorderSide dangerSide(BuildContext context) =>
      BorderSide(color: dangerColor(context), width: 1.2);
}
