import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../features/adventure/presentation/session/screens/model_select_page.dart';
import '../../features/adventure/presentation/wizard/screens/assembly_create_page.dart';
import '../../features/resource_library/presentation/screens/resource_create_page.dart';
import '../../features/resource_library/presentation/screens/resource_library_screen.dart';
import '../../features/resource_studio/presentation/pages/resource_studio_page.dart';
import '../../features/settings/presentation/screens/settings_pages.dart';
import '../../features/settings/presentation/screens/chat_transfer_pages.dart';

/// 路由统一管理 + 过渡动画
class AppRouter {
  static const String resourceLibraryPath = '/library';
  static const String resourceStudioPath = '/studio';

  /// Resolves canonical routes and the pre-Phase-11 deep-link spellings.
  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    final rawName = settings.name;
    if (rawName == null) return null;
    final uri = Uri.tryParse(rawName);
    if (uri == null) return null;
    final segments = uri.pathSegments;
    if (segments.isEmpty) return null;
    final first = segments.first;
    final resourceId =
        segments.length > 1 ? segments[1] : uri.queryParameters['resourceId'];
    final sessionId = uri.queryParameters['sessionId'];
    if (first == 'settings') {
      final page = switch (segments.length > 1 ? segments[1] : '') {
        'api' => const ApiSettingsPage(),
        'model' => const ModelSettingsPage(),
        'advanced' => const AdvancedSettingsPage(),
        'import' => const ImportPage(),
        'export' => const ExportPage(),
        _ => const SettingsPage(),
      };
      return MaterialPageRoute<void>(settings: settings, builder: (_) => page);
    }
    if (first == 'library' ||
        first == 'resource-library' ||
        first == 'resources') {
      if (segments.length > 1 && segments[1] == 'create') {
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const ResourceCreatePage(),
        );
      }
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => ResourceLibraryScreen(initialResourceId: resourceId),
      );
    }
    if (first == 'studio' || first == 'resource-studio') {
      if ((resourceId == null || resourceId.isEmpty) &&
          (sessionId == null || sessionId.isEmpty)) {
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const ResourceLibraryScreen(),
        );
      }
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => ResourceStudioPage(
          resourceId: resourceId,
          sessionId: sessionId,
        ),
      );
    }
    if (first == 'adventure') {
      if (segments.length > 1 &&
          (segments[1] == 'create' ||
              segments[1] == 'wizard' ||
              segments[1] == 'assembly')) {
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (ctx) => AssemblyCreatePage(
            onStartAdventure: (config) async {
              if (Navigator.of(ctx).canPop()) {
                Navigator.of(ctx).pop();
              }
            },
          ),
        );
      }
      if (segments.length > 1 && segments[1] == 'model-select') {
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const ModelSelectPage(),
        );
      }
    }
    return null;
  }

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
