import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// NarrAItor Material 3 主题 — 手工艺字体 + 暖色板 + 语义半径
class AppTheme {
  AppTheme._();

  // ─── 语义化圆角令牌（Editorial Workbench：控件 6 / 容器 12） ───
  static const _radiusSm = 6.0; // 紧凑控件: 按钮、输入框、导航项
  static const _radiusMd = 6.0; // 交互元素: 按钮、输入框
  static const _radiusLg = 12.0; // 容器: 卡片、对话框、底栏抽屉

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
  ///
  /// 层级约定（Editorial Workbench）：
  /// - Page title  20 / w600
  /// - Section title 13–14 / w600
  /// - List title  14 / w600
  /// - Body        13–14 / w400
  /// - Secondary   12–13 / w400
  /// - Metadata    11–12 / w400–500
  ///
  /// 全表必须完整定义：缺失的样式会回退到 Material 默认值，
  /// 导致各页面的 section / metadata 层级互不一致。
  static TextTheme _buildTextTheme(Color textColor, Color secondaryColor) {
    final displayFamily = _displayFont();
    final bodyFamily = _bodyFont();
    TextStyle serif(double size, FontWeight weight, double spacing) =>
        TextStyle(
          fontFamily: displayFamily,
          fontSize: size,
          fontWeight: weight,
          letterSpacing: spacing,
          color: textColor,
          fontFamilyFallback: _serifFallback,
        );
    TextStyle sans(double size, FontWeight weight, double spacing,
            {Color? color, double? height}) =>
        TextStyle(
          fontFamily: bodyFamily,
          fontSize: size,
          fontWeight: weight,
          letterSpacing: spacing,
          height: height,
          color: color ?? textColor,
          fontFamilyFallback: _cjkFallback,
        );
    return TextTheme(
      // 大标题 — 衬线
      displayLarge: serif(28, FontWeight.w600, -0.4),
      // 段落标题
      headlineMedium: serif(22, FontWeight.w600, -0.2),
      // 工作区页标题 — 无衬线，克制
      headlineSmall: sans(17, FontWeight.w600, 0.1),
      // 页面标题 — 衬线
      titleLarge: serif(20, FontWeight.w600, -0.1),
      // 表单标签 / 分组标题
      titleMedium: sans(15, FontWeight.w600, 0.1),
      // 列表标题 / section 标题
      titleSmall: sans(14, FontWeight.w600, 0.1),
      // 正文 — 高行距适合叙事
      bodyLarge: sans(15, FontWeight.w400, 0.2, height: 1.6),
      // 辅助 UI 文字
      bodyMedium: sans(13.5, FontWeight.w400, 0.15, height: 1.5),
      // 小标签 / 描述
      bodySmall: sans(12, FontWeight.w400, 0.2, color: secondaryColor),
      // 控件文字
      labelLarge: sans(13, FontWeight.w500, 0.2),
      // section / 导航分组标题
      labelMedium: sans(12, FontWeight.w500, 0.3, color: secondaryColor),
      // 元数据 / 时间戳
      labelSmall: sans(11, FontWeight.w500, 0.4, color: secondaryColor),
    );
  }

  /// 三层表面阶梯 + 低对比度描边写入 ColorScheme。
  ///
  /// ColorScheme.fromSeed 会把所有 container 层级从同一 seed 推导出来，
  /// 暗色下几乎无法区分，因此这里显式覆盖，页面不再自行硬编码颜色。
  static ColorScheme _applySurfaces(
    ColorScheme scheme, {
    required bool isDark,
  }) {
    if (isDark) {
      return scheme.copyWith(
        surface: AppColors.darkPanel,
        onSurface: AppColors.darkTextPrimary,
        surfaceContainerLowest: AppColors.darkBackground,
        surfaceContainerLow: AppColors.darkPanel,
        surfaceContainer: AppColors.darkPanel,
        surfaceContainerHigh: AppColors.darkRaised,
        surfaceContainerHighest: AppColors.darkHover,
        outlineVariant: AppColors.darkBorder,
        outline: AppColors.darkBorderStrong,
      );
    }
    return scheme.copyWith(
      surface: AppColors.lightRaised,
      onSurface: AppColors.textPrimary,
      surfaceContainerLowest: AppColors.lightPanel,
      surfaceContainerLow: AppColors.lightRaised,
      surfaceContainer: AppColors.lightPanel,
      surfaceContainerHigh: AppColors.lightHover,
      surfaceContainerHighest: AppColors.lightHover,
      outlineVariant: AppColors.lightBorder,
      outline: AppColors.lightBorderStrong,
    );
  }

  /// 紧凑控件度量：桌面工具栏按钮 30–34、输入 34、行高紧凑。
  static const _compactButtonPadding =
      EdgeInsets.symmetric(horizontal: 14, vertical: 8);
  static const _compactInputPadding =
      EdgeInsets.symmetric(horizontal: 12, vertical: 10);

  /// 支持动态 colorSchemeSeed 运行时切换
  static ThemeData light({Color? colorSchemeSeed}) {
    final seed = colorSchemeSeed ?? AppColors.primary;
    final textTheme =
        _buildTextTheme(AppColors.textPrimary, AppColors.textSecondary);
    final scheme = _applySurfaces(
      ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.light,
      ),
      isDark: false,
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
      // ── Card ──
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusLg),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.35),
            width: 1.0,
          ),
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
          padding: _compactButtonPadding,
          textStyle: TextStyle(
            fontFamily: _bodyFont(),
            fontSize: 13.5,
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
          padding: _compactButtonPadding,
        ),
      ),
      // ── TextButton ──
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: seed,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_radiusMd)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          textStyle: TextStyle(
            fontFamily: _bodyFont(),
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFamilyFallback: _cjkFallback,
          ),
        ),
      ),
      // ── Divider ──
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1.0,
        space: 1.0,
      ),
      // ── InputDecoration ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        hintStyle: TextStyle(
          fontFamily: _bodyFont(),
          color: AppColors.textDisabled,
          fontSize: 14,
          fontFamilyFallback: _cjkFallback,
        ),
        contentPadding: _compactInputPadding,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
          borderSide:
              BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
          borderSide: BorderSide(color: seed, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
          borderSide:
              BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
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
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radiusSm)),
        side: BorderSide.none,
        backgroundColor: AppColors.surface,
        labelStyle: TextStyle(
          fontFamily: _bodyFont(),
          fontSize: 13,
          fontFamilyFallback: _cjkFallback,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
    final scheme = _applySurfaces(
      ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
      ),
      isDark: true,
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
        color: scheme.surfaceContainerLow,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusLg),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.35),
            width: 1.0,
          ),
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
          padding: _compactButtonPadding,
          textStyle: TextStyle(
            fontFamily: _bodyFont(),
            fontSize: 13.5,
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
          padding: _compactButtonPadding,
        ),
      ),
      // ── TextButton ──
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: seed,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_radiusMd)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          textStyle: TextStyle(
            fontFamily: _bodyFont(),
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFamilyFallback: _cjkFallback,
          ),
        ),
      ),
      // ── Divider ──
      dividerTheme: const DividerThemeData(
        color: AppColors.darkDivider,
        thickness: 1.0,
        space: 1.0,
      ),
      // ── InputDecoration ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        hintStyle: TextStyle(
          fontFamily: _bodyFont(),
          color: AppColors.darkTextSecondary,
          fontSize: 14,
          fontFamilyFallback: _cjkFallback,
        ),
        contentPadding: _compactInputPadding,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
          borderSide:
              BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
          borderSide: BorderSide(color: seed, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
          borderSide:
              BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
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
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radiusSm)),
        side: BorderSide.none,
        backgroundColor: AppColors.darkSurfaceElevated,
        labelStyle: TextStyle(
          fontFamily: _bodyFont(),
          fontSize: 13,
          color: AppColors.darkTextPrimary,
          fontFamilyFallback: _cjkFallback,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      // ── Text ──
      textTheme: textTheme,
    );
  }
}
