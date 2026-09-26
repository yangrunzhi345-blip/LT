import 'package:flutter/material.dart';

import 'app_page_scaffold.dart';

/// 表单子页面脚手架
///
/// 现基于统一的 [AppPageScaffold] 实现，保留完全向后兼容的 API，并支持响应式滚动与扩展。
class FormSubPageScaffold extends StatelessWidget {
  const FormSubPageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.bottomBar,
    this.maxWidth = 840,
    this.scrollable = false,
    this.padding,
    this.leading,
    this.onBack,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.resizeToAvoidBottomInset = true,
    this.useSafeArea = true,
    this.backgroundColor,
    this.customAppBar,
  });

  final String title;
  final Widget child;
  final List<Widget>? actions;
  final Widget? bottomBar;
  final double maxWidth;
  final bool scrollable;
  final EdgeInsetsGeometry? padding;
  final Widget? leading;
  final VoidCallback? onBack;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final bool resizeToAvoidBottomInset;
  final bool useSafeArea;
  final Color? backgroundColor;
  final PreferredSizeWidget? customAppBar;

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: title,
      maxWidth: maxWidth,
      actions: actions,
      bottomBar: bottomBar,
      scrollable: scrollable,
      padding: padding,
      leading: leading,
      onBack: onBack,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      useSafeArea: useSafeArea,
      backgroundColor: backgroundColor,
      customAppBar: customAppBar,
      body: child,
    );
  }
}

Future<T?> showFormSubPage<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
  double maxWidth = 840,
  List<Widget>? actions,
  Widget? bottomBar,
  bool scrollable = false,
  EdgeInsetsGeometry? padding,
}) {
  return Navigator.of(context).push<T>(
    MaterialPageRoute(
      builder: (pageContext) => FormSubPageScaffold(
        title: title,
        maxWidth: maxWidth,
        actions: actions,
        bottomBar: bottomBar,
        scrollable: scrollable,
        padding: padding,
        child: builder(pageContext),
      ),
    ),
  );
}
