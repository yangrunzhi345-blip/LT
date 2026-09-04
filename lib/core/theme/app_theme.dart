import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// NarrAItor Material 3 主题 — 手工艺字体 + 暖色板 + 语义半径
class AppTheme {
  AppTheme._();

  // ─── 语义化圆角令牌 ───
  static const _radiusMd = 14.0; // 交互元素: 按钮、输入框
  static const _radiusLg = 20.0; // 容器: 卡片、对话框

  // ─── 间距令牌 ───
  static const spaceXs = 4.0;
  static const spaceSm = 8.0;
  static const spaceMd = 12.0;
  static const spaceLg = 16.0;
  static const spaceXl = 24.0;
  static const spaceXxl = 32.0;

  // ─── 字体族 ───
  /// 衬线标题: 手工艺编辑感
  static String _displayFont() => GoogleFonts.notoSerifSc().fontFamily!;

  /// 无衬线正文: 干净可读
  static String _bodyFont() => GoogleFonts.notoSansSc().fontFamily!;

  /// CJK 无衬线回退链
  static const _cjkFallback = ['PingFang SC', 'Microsoft YaHei', 'sans-serif'];

  /// CJK 衬线回退链
  static const _serifFallback = ['STSong', 'SimSun', 'serif'];

  /// 构建完整 TextTheme，含字号 / 字重 / 字距 / 行高
  /// 字体回退链: Google Font → 系统 CJK → 通用族
  static TextTheme _buildTextTheme(Color textColor, Color secondaryColor) {
    final displayFamily = _displayFont();
    final bodyFamily = _bodyFont();
    return TextTheme(
      // 大标题 — 衬线
      displayLarge: TextStyle(
        fontFamily: displayFamily,
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: textColor,
        fontFamilyFallback: _serifFallback,
      ),
      // 段落标题
      headlineMedium: TextStyle(
        fontFamily: displayFamily,
        fontSize: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.25,
        color: textColor,
        fontFamilyFallback: _serifFallback,
      ),
      // AppBar / 卡片标题
      titleLarge: TextStyle(
        fontFamily: displayFamily,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: textColor,
        fontFamilyFallback: _serifFallback,
      ),
      // 表单标签 / 列表标题
      titleMedium: TextStyle(
        fontFamily: bodyFamily,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.15,
        color: textColor,
        fontFamilyFallback: _cjkFallback,
      ),
      // 正文 — 高行距适合叙事
      bodyLarge: TextStyle(
        fontFamily: bodyFamily,
        fontSize: 15,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.3,
        height: 1.6,
        color: textColor,
        fontFamilyFallback: _cjkFallback,
      ),
      // 辅助 UI 文字
      bodyMedium: TextStyle(
        fontFamily: bodyFamily,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.2,
        height: 1.5,
        color: textColor,
        fontFamilyFallback: _cjkFallback,
      ),
      // 小标签
      bodySmall: TextStyle(
        fontFamily: bodyFamily,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.3,
        color: secondaryColor,
        fontFamilyFallback: _cjkFallback,
      ),
      // 元数据 / 时间戳
      labelSmall: TextStyle(
        fontFamily: bodyFamily,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: secondaryColor,
        fontFamilyFallback: _cjkFallback,
      ),
    );
  }

  /// 支持动态 colorSchemeSeed 运行时切换
  static ThemeData light({Color? colorSchemeSeed}) {
    final seed = colorSchemeSeed ?? AppColors.primary;
    final textTheme =
        _buildTextTheme(AppColors.textPrimary, AppColors.textSecondary);
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      surface: AppColors.surfaceElevated,
      onSurface: AppColors.textPrimary,
    );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.background,
      // ── AppBar ──
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surfaceElevated,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        titleTextStyle: textTheme.titleLarge,
      ),
      // ── Card (微浮起 + 暖阴影) ──
      cardTheme: CardThemeData(
        elevation: 0.5,
        color: AppColors.background,
        shadowColor: AppColors.textPrimary.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusLg),
          side: BorderSide(color: Colors.grey.shade200, width: 0.5),
        ),
      ),
      // ── FilledButton ──
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: seed,
          foregroundColor: Colors.white,
          elevation: 1,
          shadowColor: seed.withValues(alpha: 0.25),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_radiusMd)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: TextStyle(
            fontFamily: _bodyFont(),
            fontSize: 15,
            fontWeight: FontWeight.w600,
            fontFamilyFallback: _cjkFallback,
          ),
        ),
      ),
      // ── OutlinedButton ──
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: seed,
          side: BorderSide(color: seed, width: 1),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_radiusMd)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      // ── InputDecoration ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.inputBg,
        hintStyle: TextStyle(
          fontFamily: _bodyFont(),
          color: AppColors.textDisabled,
          fontSize: 14,
          fontFamilyFallback: _cjkFallback,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
          borderSide: BorderSide(color: seed, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
          borderSide: BorderSide.none,
        ),
      ),
      // ── Dialog ──
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radiusLg)),
        elevation: 2,
      ),
      // ── BottomSheet ──
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(_radiusLg)),
        ),
      ),
      // ── SnackBar ──
      snackBarTheme: SnackBarThemeData(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radiusMd)),
        behavior: SnackBarBehavior.floating,
      ),
      // ── Chip ──
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide.none,
        backgroundColor: AppColors.surface,
        labelStyle: TextStyle(
          fontFamily: _bodyFont(),
          fontSize: 13,
          fontFamilyFallback: _cjkFallback,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      // ── Text ──
      textTheme: textTheme,
    );
  }

  static ThemeData dark({Color? colorSchemeSeed}) {
    final seed = colorSchemeSeed ?? AppColors.darkPrimary;
    final textTheme = _buildTextTheme(
      AppColors.darkTextPrimary,
      AppColors.darkTextSecondary,
    );
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkTextPrimary,
      outline: const Color(0x1AFFFFFF),
    );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.darkBackground,
      // ── AppBar ──
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.darkBackground,
        foregroundColor: AppColors.darkTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        titleTextStyle: textTheme.titleLarge,
      ),
      // ── Card ──
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.darkSurface,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusLg),
          side: const BorderSide(color: Color(0x1AFFFFFF), width: 0.8),
        ),
      ),
      // ── FilledButton ──
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: seed,
          foregroundColor: Colors.white,
          elevation: 1,
          shadowColor: seed.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_radiusMd)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: TextStyle(
            fontFamily: _bodyFont(),
            fontSize: 15,
            fontWeight: FontWeight.w600,
            fontFamilyFallback: _cjkFallback,
          ),
        ),
      ),
      // ── OutlinedButton ──
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: seed,
          side: BorderSide(color: seed, width: 1),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_radiusMd)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      // ── InputDecoration ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSurfaceElevated,
        hintStyle: TextStyle(
          fontFamily: _bodyFont(),
          color: AppColors.darkTextSecondary,
          fontSize: 14,
          fontFamilyFallback: _cjkFallback,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
          borderSide: BorderSide(color: seed, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
          borderSide: BorderSide.none,
        ),
      ),
      // ── Dialog ──
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radiusLg)),
        elevation: 4,
      ),
      // ── BottomSheet ──
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(_radiusLg)),
        ),
      ),
      // ── SnackBar ──
      snackBarTheme: SnackBarThemeData(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radiusMd)),
        behavior: SnackBarBehavior.floating,
      ),
      // ── Chip ──
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide.none,
        backgroundColor: AppColors.darkSurfaceElevated,
        labelStyle: TextStyle(
          fontFamily: _bodyFont(),
          fontSize: 13,
          color: AppColors.darkTextPrimary,
          fontFamilyFallback: _cjkFallback,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      // ── Text ──
      textTheme: textTheme,
    );
  }
}
