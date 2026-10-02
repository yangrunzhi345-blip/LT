import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/core/widgets/app_svg_icon.dart';
import 'package:lt_dialogue/features/adventure/presentation/home/widgets/dashboard_hero_header.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/main.dart';
import 'package:lt_dialogue/providers/chat_provider.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/screens/landing_screen.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/widgets/main_sidebar.dart';

import '../helpers/responsive_test_helper.dart';

/// Desktop / medium has exactly one collapse authority: the permanent
/// [MainSidebar]'s `sidebar-toggle`. The Adventure Dashboard must not render a
/// second panel button there. Compact widths have no permanent sidebar, so the
/// dashboard keeps a drawer entry — genuinely a navigation menu, not a toggle.
void main() {
  final l10n = AppLocalizationsZh();
  late Directory tempDir;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel(
                'dev.fluttercommunity.plus/connectivity_status'),
            (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/connectivity'),
            (_) async => <String>['wifi']);
    SharedPreferences.setMockInitialValues({'main_sidebar_expanded': true});
    tempDir = await Directory.systemTemp.createTemp('lt_dashboard_sidebar_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    DatabaseService.customDbDir = null;
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> mountGate(WidgetTester tester, Size size) async {
    setViewport(tester, width: size.width, height: size.height);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: const MainGate(
            showApiDialogOnInit: false,
            skipSplashOnInit: true,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  ChatProvider chatOf(WidgetTester tester) => ProviderScope.containerOf(
        tester.element(find.byType(MainGate)),
      ).read(chatProvider);

  Finder panelIconsInDashboard() => find.descendant(
        of: find.byType(DashboardHeroHeader),
        matching: find.byWidgetPredicate(
          (widget) => widget is AppSvgIcon && widget.name == 'panel',
        ),
      );

  group('Desktop keeps a single sidebar collapse authority', () {
    for (final size in const <Size>[Size(1280, 900), Size(960, 900)]) {
      testWidgets('only MainSidebar exposes the toggle at $size',
          (tester) async {
        await mountGate(tester, size);

        expect(find.byType(LandingScreen), findsOneWidget);
        expect(find.byType(MainSidebar), findsOneWidget);
        // Exactly one desktop collapse control...
        expect(find.byKey(const Key('sidebar-toggle')), findsOneWidget);
        // ...and the Adventure Dashboard does not duplicate it.
        expect(find.byKey(const Key('adventure-dashboard-menu')), findsNothing);
        expect(panelIconsInDashboard(), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('sidebar-toggle still drives expand / collapse',
        (tester) async {
      await mountGate(tester, const Size(1280, 900));
      final chat = chatOf(tester);

      expect(chat.isMainSidebarExpanded, isTrue);
      await tester.tap(find.byKey(const Key('sidebar-toggle')));
      await settle(tester);
      expect(chat.isMainSidebarExpanded, isFalse);

      // Rail mode keeps the toggle so the sidebar can be restored.
      expect(find.byKey(const Key('sidebar-toggle')), findsOneWidget);
      await tester.tap(find.byKey(const Key('sidebar-toggle')));
      await settle(tester);
      expect(chat.isMainSidebarExpanded, isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  group('Compact keeps a drawer navigation entry only', () {
    testWidgets('dashboard menu opens the drawer at 375 px', (tester) async {
      await mountGate(tester, const Size(375, 812));

      // No permanent sidebar on compact, hence no sidebar-toggle.
      expect(find.byType(MainSidebar), findsNothing);
      expect(find.byKey(const Key('sidebar-toggle')), findsNothing);

      final menu = find.byKey(const Key('adventure-dashboard-menu'));
      expect(menu, findsOneWidget);
      expect(find.byType(DashboardHeroHeader), findsOneWidget);

      await tester.tap(menu);
      await settle(tester);

      // The drawer carries the full navigation, not a sidebar collapse toggle.
      expect(find.byType(MainSidebar), findsOneWidget);
      expect(find.text(l10n.navExplore), findsWidgets);
      expect(find.byKey(const Key('sidebar-toggle')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('320 px shows one menu icon and no overflow', (tester) async {
      await mountGate(tester, const Size(320, 568));

      expect(find.byKey(const Key('adventure-dashboard-menu')), findsOneWidget);
      expect(find.byKey(const Key('sidebar-toggle')), findsNothing);
      // Exactly one panel affordance in the whole shell.
      expect(panelIconsInDashboard(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Adventure dashboard header is viewport aware', () {
    testWidgets('hides the menu on medium widths without a duplicate',
        (tester) async {
      await mountGate(tester, const Size(768, 1024));

      expect(find.byType(MainSidebar), findsOneWidget);
      expect(find.byKey(const Key('sidebar-toggle')), findsOneWidget);
      expect(find.byKey(const Key('adventure-dashboard-menu')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
