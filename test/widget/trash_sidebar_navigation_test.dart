import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/features/resource_library/presentation/widgets/resource_trash_sheet.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/main.dart';
import 'package:lt_dialogue/models/app_section.dart';
import 'package:lt_dialogue/providers/chat_provider.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/widgets/main_sidebar.dart';

import '../helpers/responsive_test_helper.dart';

/// The recycle bin is a first-class workbench destination, not a destructive
/// action: this suite proves the sidebar/drawer entry point, the route-to-
/// selected mapping, and that the selection survives responsive resizes.
void main() {
  final l10n = AppLocalizationsZh();
  late Directory tempDir;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    // The app shell listens to connectivity; without a handler every test
    // records a MissingPluginException and `takeException` can never be null.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel(
                'dev.fluttercommunity.plus/connectivity_status'),
            (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/connectivity'),
            (_) async => ['wifi']);
    SharedPreferences.setMockInitialValues({'main_sidebar_expanded': true});
    tempDir = await Directory.systemTemp.createTemp('lt_trash_nav_');
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

  /// Advances the tree while letting real SQLite futures complete. The trash
  /// page keeps a progress indicator alive while its real I/O is in flight, so
  /// `pumpAndSettle` would never return here.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> mount(WidgetTester tester, Size size,
      {bool dark = false}) async {
    setViewport(tester, width: size.width, height: size.height);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          home: const MainGate(
            showApiDialogOnInit: false,
            skipSplashOnInit: true,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  ChatProvider chatOf(WidgetTester tester) {
    final element = tester.element(find.byType(MainGate));
    return ProviderScope.containerOf(element).read(chatProvider);
  }

  Finder sidebarLabel(String label) => find.descendant(
        of: find.byType(MainSidebar),
        matching: find.text(label),
      );

  Future<void> resize(WidgetTester tester, double width, double height) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    await settle(tester);
  }

  group('Trash workbench destination — desktop', () {
    testWidgets('wide sidebar exposes trash, selects it, and clears library',
        (tester) async {
      await mount(tester, const Size(1280, 900));
      final chat = chatOf(tester);

      expect(find.byKey(const Key('sidebar-nav-trash')), findsOneWidget);
      expect(
        sidebarLabel(l10n.recycleBinTitle),
        findsOneWidget,
        reason: 'trash label renders in the wide sidebar',
      );

      await tester.tap(find.byKey(const Key('sidebar-nav-trash')));
      await settle(tester);

      expect(chat.currentSection, AppSection.trash);
      expect(find.byType(ResourceTrashPage), findsOneWidget);
      // The library is no longer the active destination.
      expect(chat.currentSection, isNot(AppSection.resources));

      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.byKey(const Key('sidebar-nav-trash'))),
        isSemantics(isSelected: true),
      );
      handle.dispose();

      expect(tester.takeException(), isNull);
    });

    testWidgets('medium sidebar keeps readable trash text with no overflow',
        (tester) async {
      await mount(tester, const Size(960, 800));

      // 960 px must remain a compact text sidebar, never an icon rail.
      expect(find.byKey(const Key('sidebar-nav-trash')), findsOneWidget);
      expect(sidebarLabel(l10n.recycleBinTitle), findsOneWidget);
      expect(find.byTooltip(l10n.recycleBinTitle), findsNothing);

      await tester.tap(find.byKey(const Key('sidebar-nav-trash')));
      await settle(tester);
      expect(chatOf(tester).currentSection, AppSection.trash);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark theme without regression', (tester) async {
      await mount(tester, const Size(1280, 900), dark: true);

      await tester.tap(find.byKey(const Key('sidebar-nav-trash')));
      await settle(tester);
      expect(chatOf(tester).currentSection, AppSection.trash);
      expect(find.byType(ResourceTrashPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('collapsed rail shows only the icon with a tooltip',
        (tester) async {
      SharedPreferences.setMockInitialValues({'main_sidebar_expanded': false});
      await mount(tester, const Size(1440, 900));

      expect(sidebarLabel(l10n.recycleBinTitle), findsNothing);
      expect(find.byTooltip(l10n.recycleBinTitle), findsOneWidget);

      final handle = tester.ensureSemantics();
      await tester.tap(find.byTooltip(l10n.recycleBinTitle));
      await settle(tester);
      expect(chatOf(tester).currentSection, AppSection.trash);
      expect(
        tester.getSemantics(find.byTooltip(l10n.recycleBinTitle)),
        isSemantics(isSelected: true),
      );
      handle.dispose();
      expect(tester.takeException(), isNull);
    });
  });

  group('Trash workbench destination — mobile', () {
    for (final size in const [Size(320, 568), Size(375, 812)]) {
      testWidgets('drawer reaches trash without overflow at $size',
          (tester) async {
        await mount(tester, size);

        // Bottom navigation keeps its current information architecture.
        expect(find.byType(NavigationBar), findsOneWidget);

        // Reach the library, whose header owns the drawer affordance.
        await tester.tap(find.text(l10n.navLibrary).first);
        await settle(tester);
        await tester.tap(find.byTooltip(l10n.menuTooltip));
        await settle(tester);

        expect(find.byType(MainSidebar), findsOneWidget);
        await tester.tap(sidebarLabel(l10n.recycleBinTitle));
        await settle(tester);

        expect(chatOf(tester).currentSection, AppSection.trash);
        expect(find.byType(ResourceTrashPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Trash workbench destination — responsive persistence', () {
    testWidgets('selection survives 1280 -> 960 -> 375 -> 1280',
        (tester) async {
      await mount(tester, const Size(1280, 900));
      await tester.tap(find.byKey(const Key('sidebar-nav-trash')));
      await settle(tester);
      expect(chatOf(tester).currentSection, AppSection.trash);

      await resize(tester, 960, 800);
      expect(chatOf(tester).currentSection, AppSection.trash);
      expect(find.byType(MainSidebar), findsOneWidget);

      await resize(tester, 375, 812);
      expect(chatOf(tester).currentSection, AppSection.trash);
      expect(find.byType(ResourceTrashPage), findsOneWidget);

      await resize(tester, 1280, 900);
      expect(chatOf(tester).currentSection, AppSection.trash);
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.byKey(const Key('sidebar-nav-trash'))),
        isSemantics(isSelected: true),
      );
      handle.dispose();
      expect(tester.takeException(), isNull);
    });
  });

  group('Trash workbench destination — viewport sweep', () {
    // Breakpoints from AGENTS.md that must keep the destination reachable and
    // overflow-free: the compact rail boundary, the full-sidebar boundary and
    // the hard minimum width.
    for (final width in const <double>[
      320,
      375,
      600,
      768,
      950,
      960,
      1024,
      1100,
      1280,
      1440,
    ]) {
      testWidgets('reaches trash without overflow at ${width}px',
          (tester) async {
        await mount(tester, Size(width, 900));

        if (width >= 600) {
          expect(find.byType(MainSidebar), findsOneWidget);
          expect(find.byKey(const Key('sidebar-nav-trash')), findsOneWidget);
          await tester.tap(find.byKey(const Key('sidebar-nav-trash')));
        } else {
          expect(find.byType(NavigationBar), findsOneWidget);
          await tester.tap(find.text(l10n.navLibrary).first);
          await settle(tester);
          await tester.tap(find.byTooltip(l10n.menuTooltip));
          await settle(tester);
          await tester.tap(sidebarLabel(l10n.recycleBinTitle));
        }
        await settle(tester);

        expect(chatOf(tester).currentSection, AppSection.trash);
        expect(find.byType(ResourceTrashPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
