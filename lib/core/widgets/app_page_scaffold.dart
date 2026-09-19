import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 全局统一页面 Shell 组件 [AppPageScaffold]
///
/// 遵循 R02 导航优先设计原则，统一全平台页面容器规范：
/// - 统一 SafeArea 与系统栏避让
/// - 统一 M3 规范的 AppBar、标题、返回行为与 actions
/// - 统一键盘展开时的 bottomBar / Insets 弹性补偿
/// - 统一点击空白处收起键盘
/// - 支持移动端 (320px+)、平板与桌面响应式最大宽度约束
class AppPageScaffold extends StatelessWidget {
  final String? title;
  final Widget? titleWidget;
  final Widget body;
  final List<Widget>? actions;
  final Widget? leading;
  final VoidCallback? onBack;
  final bool showBackButton;
  final Widget? bottomBar;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final double? maxWidth;
  final bool resizeToAvoidBottomInset;
  final bool useSafeArea;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final PreferredSizeWidget? customAppBar;
  final bool scrollable;

  const AppPageScaffold({
    super.key,
    this.title,
    this.titleWidget,
    required this.body,
    this.actions,
    this.leading,
    this.onBack,
    this.showBackButton = true,
    this.bottomBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.maxWidth = 840,
    this.resizeToAvoidBottomInset = true,
    this.useSafeArea = true,
    this.padding,
    this.backgroundColor,
    this.customAppBar,
    this.scrollable = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    Widget? effectiveLeading = leading;
    if (effectiveLeading == null && showBackButton) {
      final ModalRoute<dynamic>? parentRoute = ModalRoute.of(context);
      final bool canPop = parentRoute?.canPop ?? false;
      if (canPop) {
        effectiveLeading = IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回',
          onPressed: onBack ?? () => Navigator.of(context).maybePop(),
        );
      }
    }

    PreferredSizeWidget? effectiveAppBar = customAppBar;
    if (effectiveAppBar == null &&
        (title != null ||
            titleWidget != null ||
            actions != null ||
            effectiveLeading != null)) {
      effectiveAppBar = AppBar(
        title: titleWidget ?? (title != null ? Text(title!) : null),
        leading: effectiveLeading,
        actions: actions,
        elevation: 0,
        backgroundColor: backgroundColor ??
            (isDark ? AppColors.darkBackground : AppColors.background),
        surfaceTintColor: Colors.transparent,
      );
    }

    Widget content = body;
    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }
    if (scrollable) {
      content = SingleChildScrollView(
        child: content,
      );
    }

    if (maxWidth != null && maxWidth!.isFinite) {
      content = Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth!),
          child: content,
        ),
      );
    }

    if (useSafeArea) {
      content = SafeArea(child: content);
    }

    content = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: content,
    );

    return Scaffold(
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      backgroundColor: backgroundColor ??
          (isDark ? AppColors.darkBackground : AppColors.background),
      appBar: effectiveAppBar,
      body: content,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      bottomNavigationBar: bottomBar == null
          ? null
          : SafeArea(
              top: false,
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.only(bottom: bottomInset),
                child: bottomBar!,
              ),
            ),
    );
  }

  /// 便捷路由打开方法
  static Future<T?> push<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    String? title,
    double? maxWidth = 840,
    List<Widget>? actions,
    Widget? bottomBar,
  }) {
    return Navigator.of(context).push<T>(
      MaterialPageRoute(
        builder: (pageContext) => AppPageScaffold(
          title: title,
          maxWidth: maxWidth,
          actions: actions,
          bottomBar: bottomBar,
          body: builder(pageContext),
        ),
      ),
    );
  }
}
