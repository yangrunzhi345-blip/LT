import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/core/widgets/app_svg_icon.dart';
import 'package:lt_dialogue/features/settings/presentation/screens/settings_pages.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/main.dart';
import 'package:lt_dialogue/models/app_section.dart';
import 'package:lt_dialogue/providers/chat_provider.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/widgets/main_sidebar.dart';

import '../helpers/responsive_test_helper.dart';

/// On desktop / medium the permanent [MainSidebar]'s `sidebar-toggle` is the
/// sole collapse authority, so the Settings Center must not render a second
/// panel button. On compact the permanent sidebar is gone, so Settings keeps a
/// drawer opener (`settings-center-menu`) — a navigation entry, not a toggle.
void main() {
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
    tempDir = await Directory.systemTemp.createTemp('lt_settings_sidebar_');
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

  Future<void> mountSettings(WidgetTester tester, Size size) async {
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
    ProviderScope.containerOf(tester.element(find.byType(MainGate)))
        .read(chatProvider)
        .setCurrentSection(AppSection.settings);
    await settle(tester);
  }

  ChatProvider chatOf(WidgetTester tester) => ProviderScope.containerOf(
        tester.element(find.byType(MainGate)),
      ).read(chatProvider);

  Finder panelIconInsideSettings() => find.descendant(
        of: find.byType(SettingsPage),
        matching: find.byWidgetPredicate(
          (widget) => widget is AppSvgIcon && widget.name == 'panel',
        ),
      );

  const Key toggleKey = Key('sidebar-toggle');
  const Key menuKey = Key('settings-center-menu');

  group('Desktop / medium hide the duplicate settings toggle', () {
    for (final size in const <Size>[
      Size(960, 900),
      Size(1280, 900),
      Size(1440, 900),
    ]) {
      testWidgets('only MainSidebar owns the toggle at $size', (tester) async {
        await mountSettings(tester, size);

        expect(find.byType(SettingsPage), findsOneWidget);
        expect(find.byKey(toggleKey), findsOneWidget);
        expect(find.byKey(menuKey), findsNothing);
        expect(panelIconInsideSettings(), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('sidebar-toggle still collapses / expands', (tester) async {
      await mountSettings(tester, const Size(1280, 900));
      final chat = chatOf(tester);

      expect(chat.isMainSidebarExpanded, isTrue);
      await tester.tap(find.byKey(toggleKey));
      await settle(tester);
      expect(chat.isMainSidebarExpanded, isFalse);
      expect(find.byKey(toggleKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('600 px keeps the permanent sidebar and hides the menu',
        (tester) async {
      await mountSettings(tester, const Size(600, 900));

      expect(find.byKey(toggleKey), findsOneWidget);
      expect(find.byKey(menuKey), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Compact keeps a drawer navigation entry only', () {
    for (final size in const <Size>[Size(320, 568), Size(375, 812)]) {
      testWidgets('settings menu opens the drawer at $size', (tester) async {
        await mountSettings(tester, size);

        // No permanent sidebar on compact, hence no sidebar-toggle.
        expect(find.byType(MainSidebar), findsNothing);
        expect(find.byKey(toggleKey), findsNothing);
        expect(find.byKey(menuKey), findsOneWidget);

        await tester.tap(find.byKey(menuKey));
        await settle(tester);

        // The drawer carries the full navigation, not a sidebar collapse.
        expect(find.byType(MainSidebar), findsOneWidget);
        expect(find.byType(Drawer), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('320 px shows one menu icon and no overflow', (tester) async {
      await mountSettings(tester, const Size(320, 568));
      expect(find.byKey(menuKey), findsOneWidget);
      expect(find.byKey(toggleKey), findsNothing);
      expect(panelIconInsideSettings(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Compact detail keeps back and menu distinct', () {
    testWidgets('detail exposes back-to-list and the drawer opener',
        (tester) async {
      await mountSettings(tester, const Size(375, 812));

      await tester
          .tap(find.byKey(const ValueKey('settings-category-generation')));
      await settle(tester);

      final backKey = find.byKey(const Key('settings-detail-back'));
      expect(backKey, findsOneWidget);
      expect(find.byKey(menuKey), findsOneWidget);

      // Back returns to the category list, it does not open the drawer.
      await tester.tap(backKey);
      await settle(tester);
      expect(find.byKey(const Key('settings-detail-back')), findsNothing);
      expect(find.byType(Drawer), findsNothing);

      // Re-open a detail, then the menu opens the drawer independently.
      await tester
          .tap(find.byKey(const ValueKey('settings-category-generation')));
      await settle(tester);
      await tester.tap(find.byKey(menuKey));
      await settle(tester);
      expect(find.byType(Drawer), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Responsive boundary is driven by the shell split', () {
    for (final width in const <double>[320, 375, 599]) {
      testWidgets('at ${width}px the drawer menu is the only control',
          (tester) async {
        await mountSettings(tester, Size(width, 812));
        expect(find.byKey(menuKey), findsOneWidget);
        expect(find.byKey(toggleKey), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    for (final width in const <double>[600, 768, 960, 1280, 1440]) {
      testWidgets('at ${width}px the permanent sidebar owns the control',
          (tester) async {
        await mountSettings(tester, Size(width, 900));
        expect(find.byKey(toggleKey), findsOneWidget);
        expect(find.byKey(menuKey), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Settings feature never drives the sidebar authority directly', () {
    test('no production settings source calls toggleMainSidebarExpanded', () {
      final files = <File>[
        File('lib/screens/settings_center_screen.dart'),
        ...Directory('lib/features/settings')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart')),
      ];
      for (final file in files) {
        expect(
          file.readAsStringSync().contains('toggleMainSidebarExpanded'),
          isFalse,
          reason: '${file.path} must open the drawer via its onMenuPressed '
              'callback, never toggle the sidebar itself',
        );
      }
    });
  });
}
