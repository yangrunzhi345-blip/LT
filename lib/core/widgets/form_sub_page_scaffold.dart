import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: actions,
        elevation: 0,
        backgroundColor:
            isDark ? AppColors.darkBackground : AppColors.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: child,
            ),
          ),
        ),
      ),
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
