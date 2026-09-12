import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/features/settings/presentation/screens/settings_screen.dart';
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
    tempDir = await Directory.systemTemp.createTemp('lt_settings_mobile_test_');
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

  group('Phase 6: Mobile Settings Architecture Tests', () {
    for (final width in [320.0, 360.0, 390.0, 412.0]) {
      testWidgets(
        'Mobile Settings renders clean category list on ${width}px without TabBar and with zero overflow',
        (tester) async {
          tester.view.physicalSize = Size(width, 700);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                theme: AppTheme.light(),
                home: const SettingsScreen(),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));

          expect(find.text('设置中心'), findsOneWidget);
          expect(find.text('模型与 API'), findsOneWidget);
          expect(find.text('会话参数'), findsOneWidget);
          expect(find.text('主题配色'), findsOneWidget);
          expect(find.text('数据管理'), findsOneWidget);

          // TabBar should NOT be present on mobile
          expect(find.byType(TabBar), findsNothing);

          // Zero layout overflow
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'Mobile Settings navigates to subpage and back to category list on 320px viewport',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const SettingsScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Tap '模型与 API' category
        await tester.tap(find.text('模型与 API'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Should be on subpage
        expect(find.text('LLM 服务提供商'), findsOneWidget);
        expect(find.text('API 密钥 (API Key)'), findsOneWidget);

        // Tap back to return to category list
        final backButton = find.byTooltip('返回设置列表');
        expect(backButton, findsOneWidget);
        await tester.tap(backButton);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Back on category list
        expect(find.text('设置中心'), findsOneWidget);
        expect(find.text('配置分类'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
