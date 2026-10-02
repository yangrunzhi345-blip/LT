import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_library_screen.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/main.dart';
import 'package:lt_dialogue/models/app_section.dart';
import 'package:lt_dialogue/providers/chat_provider.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/screens/landing_screen.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/widgets/main_sidebar.dart';

import '../helpers/responsive_test_helper.dart';

/// The Resource Library is reachable both as a Main Workbench section
/// (`AppSection.resources`, no route) and as a pushed route (`/library`). The
/// return control must work for both without the two authorities colliding.
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
            (_) async => ['wifi']);
    SharedPreferences.setMockInitialValues({'main_sidebar_expanded': true});
    tempDir = await Directory.systemTemp.createTemp('lt_library_return_');
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

  Future<void> mountGate(WidgetTester tester, Size size,
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

  ChatProvider chatOf(WidgetTester tester) => ProviderScope.containerOf(
        tester.element(find.byType(MainGate)),
      ).read(chatProvider);

  Future<void> openLibrary(WidgetTester tester, double width) async {
    if (width >= 600) {
      await tester.tap(find.descendant(
        of: find.byType(MainSidebar),
        matching: find.text(l10n.navLibrary),
      ));
    } else {
      await tester.tap(find.text(l10n.navLibrary).first);
    }
    await settle(tester);
  }

  group('Main Workbench return', () {
    testWidgets('library returns to the lobby through the section authority',
        (tester) async {
      await mountGate(tester, const Size(1280, 900));
      final chat = chatOf(tester);
      expect(find.byType(LandingScreen), findsOneWidget);

      await openLibrary(tester, 1280);
      expect(chat.currentSection, AppSection.resources);
      expect(find.byKey(const Key('resource-library-return-home')),
          findsOneWidget);

      await tester.tap(find.byKey(const Key('resource-library-return-home')));
      await settle(tester);

      expect(chat.currentSection, AppSection.adventure);
      expect(chat.isAdventureChatOpen, isFalse);
      expect(find.byType(LandingScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('header menu control is not the return control',
        (tester) async {
      await mountGate(tester, const Size(1280, 900));
      final chat = chatOf(tester);
      await openLibrary(tester, 1280);

      // Two distinct controls with distinct keys.
      expect(find.byKey(const Key('resource-library-menu')), findsOneWidget);
      expect(find.byKey(const Key('resource-library-return-home')),
          findsOneWidget);

      final before = chat.isMainSidebarExpanded;
      await tester.tap(find.byKey(const Key('resource-library-menu')));
      await settle(tester);
      // The menu control toggles the sidebar and must not navigate home.
      expect(chat.isMainSidebarExpanded, !before);
      expect(chat.currentSection, AppSection.resources);
      expect(tester.takeException(), isNull);
    });

    for (final size in const <Size>[
      Size(320, 568),
      Size(375, 812),
      Size(600, 900),
      Size(960, 900),
      Size(1280, 900),
      Size(1440, 900),
    ]) {
      testWidgets('return control available and working at $size',
          (tester) async {
        await mountGate(tester, size);
        final chat = chatOf(tester);
        await openLibrary(tester, size.width);
        expect(chat.currentSection, AppSection.resources);
        expect(find.byKey(const Key('resource-library-return-home')),
            findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const Key('resource-library-return-home')));
        await settle(tester);
        expect(chat.currentSection, AppSection.adventure);
        expect(find.byType(LandingScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('return control works in dark theme', (tester) async {
      await mountGate(tester, const Size(1280, 900), dark: true);
      final chat = chatOf(tester);
      await openLibrary(tester, 1280);
      await tester.tap(find.byKey(const Key('resource-library-return-home')));
      await settle(tester);
      expect(chat.currentSection, AppSection.adventure);
      expect(tester.takeException(), isNull);
    });
  });

  group('Pushed route return', () {
    testWidgets('pops the route without touching the section authority',
        (tester) async {
      setViewport(tester, width: 1280, height: 900);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const ResourceLibraryScreen()),
                  ),
                  child: const Text('open-library'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      final before = container.read(chatProvider).currentSection;

      await tester.tap(find.text('open-library'));
      await settle(tester);
      expect(find.byType(ResourceLibraryScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('resource-library-return-home')));
      await settle(tester);

      expect(find.byType(ResourceLibraryScreen), findsNothing);
      expect(find.text('open-library'), findsOneWidget);
      expect(container.read(chatProvider).currentSection, before);
      expect(tester.takeException(), isNull);
    });

    testWidgets('root-mounted library falls back to the lobby section',
        (tester) async {
      setViewport(tester, width: 1280, height: 900);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: const ResourceLibraryScreen(),
        ),
      ));
      await settle(tester);

      expect(find.byKey(const Key('resource-library-return-home')),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('resource-library-return-home')));
      await settle(tester);

      expect(container.read(chatProvider).currentSection, AppSection.adventure);
      expect(tester.takeException(), isNull);
    });
  });
}
