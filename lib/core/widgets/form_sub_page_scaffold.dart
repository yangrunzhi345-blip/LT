import 'package:flutter/material.dart';

import 'app_page_scaffold.dart';

/// 表单子页面脚手架
///
/// 现基于统一的 [AppPageScaffold] 实现，保留完全向后兼容的 API。
class FormSubPageScaffold extends StatelessWidget {
  const FormSubPageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.bottomBar,
    this.maxWidth = 840,
  });

  final String title;
  final Widget child;
  final List<Widget>? actions;
  final Widget? bottomBar;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: title,
      maxWidth: maxWidth,
      actions: actions,
      bottomBar: bottomBar,
      body: child,
    );
  }
}

Future<T?> showFormSubPage<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
  double maxWidth = 840,
}) {
  return Navigator.of(context).push<T>(
    MaterialPageRoute(
      builder: (pageContext) => FormSubPageScaffold(
        title: title,
        maxWidth: maxWidth,
        child: builder(pageContext),
      ),
    ),
  );
}
