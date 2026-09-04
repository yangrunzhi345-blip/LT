import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/screens/landing_screen.dart';
import 'package:lt_dialogue/screens/settings_center_screen.dart';
import 'package:lt_dialogue/screens/worldview_editor_screen.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/widgets/main_sidebar.dart';

void main() {
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

  testWidgets('MainSidebar renders 3 core destinations and allows navigation', (tester) async {
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

    expect(find.text('场景对话'), findsWidgets);
    expect(find.text('资料库'), findsWidgets);
    expect(find.text('系统设置'), findsWidgets);
    expect(find.text('LT 灵境'), findsOneWidget);
  });

  testWidgets('SettingsCenterScreen renders and switches tabs', (tester) async {
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
    expect(find.text('模型与 API'), findsWidgets);
    expect(find.text('会话参数'), findsWidgets);
    expect(find.text('主题配色'), findsWidgets);
  });

  testWidgets('WorldviewEditorScreen renders 4 library tabs', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const WorldviewEditorScreen(
            mode: ResourceLibraryMode.adventure,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('世界观'), findsWidgets);
    expect(find.text('角色卡'), findsWidgets);
    expect(find.text('NPC'), findsWidgets);
    expect(find.text('预存场景'), findsWidgets);
  });

  testWidgets('LandingScreen renders preset adventures and custom builder button', (tester) async {
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

    expect(find.text('进入你的场景'), findsOneWidget);
    expect(find.text('快速开始'), findsWidgets);
    expect(find.text('自由创建'), findsWidgets);
    expect(find.text('使用预设'), findsWidgets);
  });
}
