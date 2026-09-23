import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/features/adventure/presentation/templates/screens/preset_scenes_screen.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_library_screen.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/screens/landing_screen.dart';
import 'package:lt_dialogue/screens/settings_center_screen.dart';
import 'package:lt_dialogue/main.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/widgets/main_sidebar.dart';

void main() {
  final l10n = AppLocalizationsZh();
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'main_sidebar_expanded': true,
    });
    tempDir = await Directory.systemTemp.createTemp('lt_widget_test_');
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

  testWidgets(
      'MainSidebar renders new adventure, past conversations and settings',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final scaffoldKey = GlobalKey<ScaffoldState>();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            key: scaffoldKey,
            body: Row(
              children: [
                MainSidebar(scaffoldKey: scaffoldKey, permanent: true),
                const Expanded(child: Center(child: Text('Content'))),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('探索'), findsOneWidget);
    expect(find.text('新建冒险'), findsOneWidget);
    expect(find.text('资料库'), findsOneWidget);
    expect(find.text('最近'), findsOneWidget);
    expect(find.text('系统设置'), findsWidgets);
    expect(find.text('LT 灵境'), findsOneWidget);
    // 旧版已被移除，避免死代码回归
    expect(find.text('场景对话'), findsNothing);
    expect(find.text('开启新冒险'), findsNothing);
    expect(find.text('过去的对话'), findsNothing);
  });

  testWidgets('MainSidebar renders collapsed by default when no preference set',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferences.setMockInitialValues({});
    final scaffoldKey = GlobalKey<ScaffoldState>();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            key: scaffoldKey,
            body: Row(
              children: [
                MainSidebar(scaffoldKey: scaffoldKey, permanent: true),
                const Expanded(child: Center(child: Text('Content'))),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // In collapsed mode, expanded title and labels are not rendered
    expect(find.text('LT 灵境'), findsNothing);
    expect(find.text('探索'), findsNothing);
    expect(find.text('新建冒险'), findsNothing);
    // Editorial auto_stories icon is rendered in header
    expect(find.byIcon(Icons.auto_stories_rounded), findsOneWidget);
    // Expand chevron button is rendered
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
  });

  testWidgets('SettingsCenterScreen opens API settings as a page',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SettingsCenterScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('设置中心'), findsOneWidget);
    expect(find.text(l10n.providerConfigTitle), findsOneWidget);
    await tester.tap(find.text(l10n.providerConfigTitle));
    await tester.pumpAndSettle();
    expect(find.text(l10n.testConnection), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('设置中心'), findsOneWidget);
  });

  testWidgets(
      'ResourceLibraryScreen renders unified filters and creation entry',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ResourceLibraryScreen(
            mode: ResourceLibraryMode.adventure,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('世界观'), findsWidgets);
    expect(find.text('角色'), findsWidgets);
    expect(find.text('NPC'), findsWidgets);
    expect(find.byKey(const Key('resource-filter')), findsOneWidget);
    expect(find.byKey(const Key('resource-create-button')), findsOneWidget);
    expect(find.text('预存场景工坊'), findsNothing);
  });

  testWidgets(
      'LandingScreen renders preset adventures and custom builder button',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: LandingScreen(
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
    expect(find.text('我的世界设定'), findsWidgets);
  });

  testWidgets(
      'PresetScenesScreen renders header, search bar, and action buttons',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const PresetScenesScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('预存场景工坊'), findsWidgets);
    expect(find.text('返回大厅'), findsWidgets);
    expect(find.text('向导新建场景'), findsWidgets);
  });

  testWidgets('LandingScreen navigates to PresetScenesScreen and back',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: LandingScreen(
            onStartAdventure: (_, {difficulty}) async {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Tap on the 预存场景工坊 card
    final cardFinder = find.text('预存场景工坊');
    expect(cardFinder, findsWidgets);
    await tester.tap(cardFinder.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // Verify PresetScenesScreen is displayed
    expect(find.text('向导新建场景'), findsOneWidget);
    expect(find.text('返回大厅'), findsOneWidget);

    // Tap 返回大厅
    await tester.tap(find.text('返回大厅'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify back to LandingScreen
    expect(find.text('灵境 · 探索与叙事工坊'), findsOneWidget);
  });

  testWidgets(
      'Mobile adaptive shell renders BottomNavigationBar and switches tabs',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const MainGate(
            showApiDialogOnInit: false,
            skipSplashOnInit: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Verify BottomNavigationBar is present on compact screen
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('探索'), findsWidgets);
    expect(find.text('资料库'), findsWidgets);
    expect(find.text('设置'), findsWidgets);

    // Tap on 资料库 tab
    await tester.tap(find.text('资料库').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(ResourceLibraryScreen), findsOneWidget);

    // Tap on 设置 tab
    await tester.tap(find.text('设置').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(SettingsCenterScreen), findsOneWidget);

    // Tap back to 探索 tab
    await tester.tap(find.text('探索').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(LandingScreen), findsOneWidget);
  });

  testWidgets(
      'Desktop adaptive shell hides BottomNavigationBar and renders permanent sidebar',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const MainGate(
            showApiDialogOnInit: false,
            skipSplashOnInit: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // On desktop, BottomNavigationBar should NOT be present
    expect(find.byType(NavigationBar), findsNothing);
    // Permanent sidebar should be present
    expect(find.byType(MainSidebar), findsOneWidget);
  });

  testWidgets(
      'App shell and NavigationBar render cleanly on minimum 320px screen width',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const MainGate(
            showApiDialogOnInit: false,
            skipSplashOnInit: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
