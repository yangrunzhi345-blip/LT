import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/features/adventure/presentation/home/screens/adventure_dashboard_screen.dart';
import 'package:lt_dialogue/features/adventure/presentation/home/widgets/dashboard_action_cards.dart';
import 'package:lt_dialogue/features/adventure/presentation/home/widgets/dashboard_hero_header.dart';
import 'package:lt_dialogue/features/adventure/presentation/home/widgets/dashboard_recent_saves.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir =
        await Directory.systemTemp.createTemp('lt_dashboard_widget_test_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('Phase 4: Adventure Dashboard Widgets Tests', () {
    testWidgets(
      'DashboardHeroHeader renders editorial header without AI clichés and fits 320px',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const Scaffold(
                body: DashboardHeroHeader(),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('灵境 · 探索与叙事工坊'), findsOneWidget);
        expect(find.text('交互小说与沉浸式 RPG 叙事空间'), findsOneWidget);
        // Ensure auto_awesome is not used in the header
        expect(find.byIcon(Icons.auto_awesome_rounded), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'DashboardActionCards renders cleanly and fits 320px width without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        bool wizardOpened = false;
        bool presetOpened = false;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: DashboardActionCards(
                onOpenWizard: () => wizardOpened = true,
                onOpenPresetScenes: () => presetOpened = true,
                onOpenLibrary: () {},
                onOpenSettings: () {},
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('四步向导定制'), findsOneWidget);
        expect(find.text('预存场景工坊'), findsOneWidget);
        expect(find.text('资料库'), findsOneWidget);
        expect(find.text('系统设置中心'), findsOneWidget);

        await tester.tap(find.text('四步向导定制'));
        await tester.pump();
        expect(wizardOpened, isTrue);

        await tester.tap(find.text('预存场景工坊'));
        await tester.pump();
        expect(presetOpened, isTrue);

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'DashboardRecentSaves renders saves list when adventures exist',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final container = ProviderContainer();
        addTearDown(container.dispose);

        final chat = container.read(chatProvider);
        chat.adventureProvider.adventureList.add({
          'id': 1,
          'title': '暮色边境 · 遗失遗迹',
          'updated_at': '2026-09-12 14:00',
        });

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const Scaffold(
                body: SingleChildScrollView(
                  child: DashboardRecentSaves(),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('继续未尽的冒险'), findsOneWidget);
        expect(find.text('暮色边境 · 遗失遗迹'), findsOneWidget);
        expect(find.text('继续探索'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'AdventureDashboardScreen renders completely on 320px viewport with zero overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.light(),
              home: AdventureDashboardScreen(
                onStartAdventure: (_, {difficulty}) async {},
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('灵境 · 探索与叙事工坊'), findsOneWidget);
        expect(find.text('四步向导定制'), findsWidgets);
        expect(find.text('预存场景工坊'), findsWidgets);
        expect(find.text('资料库'), findsWidgets);
        expect(find.text('系统设置中心'), findsWidgets);

        // Zero layout overflow on 320px screen
        expect(tester.takeException(), isNull);
      },
    );
  });
}
