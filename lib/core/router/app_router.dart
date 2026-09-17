import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 路由统一管理 + 过渡动画
class AppRouter {
  static Future<T?> push<T extends Object?>(
    BuildContext context, {
    required WidgetBuilder pageBuilder,
  }) {
    return Navigator.of(context)
        .push<T>(pageRoute(context, pageBuilder: pageBuilder));
  }

  /// Replaces the current page while preserving the app's transition policy.
  static Future<T?> pushReplacement<T extends Object?, TO extends Object?>(
    BuildContext context, {
    required WidgetBuilder pageBuilder,
    TO? result,
  }) {
    return Navigator.of(context).pushReplacement<T, TO>(
      pageRoute(context, pageBuilder: pageBuilder),
      result: result,
    );
  }

  static PageRoute<T> pageRoute<T extends Object?>(
    BuildContext context, {
    required WidgetBuilder pageBuilder,
  }) {
    final mediaQuery = MediaQuery.maybeOf(context);
    final disableAnimations = mediaQuery?.disableAnimations ?? false;
    final desktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS);
    if (disableAnimations) return MaterialPageRoute<T>(builder: pageBuilder);
    return PageRouteBuilder<T>(
      pageBuilder: (routeContext, _, __) => pageBuilder(routeContext),
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      transitionsBuilder: (_, animation, secondaryAnimation, child) {
        final curved =
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        if (desktop) return FadeTransition(opacity: curved, child: child);
        return SlideTransition(
          position:
              Tween<Offset>(begin: const Offset(0.12, 0), end: Offset.zero)
                  .animate(curved),
          child: child,
        );
      },
    );
  }

  /// 创建带 SlideTransition 的页面路由
  static PageRouteBuilder<T> slide<T extends Object?>({
    required WidgetBuilder pageBuilder,
    Offset begin = const Offset(0.15, 0),
  }) {
    return PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => pageBuilder(_),
      transitionsBuilder: (_, animation, __, child) => SlideTransition(
        position: Tween<Offset>(begin: begin, end: Offset.zero)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: child,
      ),
    );
  }
}
