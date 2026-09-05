import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/core/widgets/app_text_field.dart';
import 'package:lt_dialogue/features/settings/presentation/screens/settings_screen.dart';
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
    tempDir = await Directory.systemTemp.createTemp('lt_settings_test_');
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

  group('Phase 2: Settings Feature & AppTextField Tests', () {
    testWidgets('AppTextField toggles password obscure visibility', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: AppTextField(
              label: '测试密钥',
              initialValue: 'sk-secret-key-12345',
              isPassword: true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('测试密钥'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

      // 点击显示明文
      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pump();

      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });

    testWidgets('SettingsScreen renders responsive sections and tab switching', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
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
      expect(find.text('LLM 服务提供商'), findsOneWidget);
      expect(find.text('API 密钥 (API Key)'), findsOneWidget);

      // 切换到会话参数 Tab
      await tester.tap(find.text('会话参数'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('推理超参与采样调节'), findsOneWidget);
      expect(find.text('启用深度思考模式 (Deep Thinking)'), findsOneWidget);

      // 切换到主题配色 Tab
      await tester.tap(find.text('主题配色'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('外观与视觉主题'), findsOneWidget);
      expect(find.text('主题模式'), findsOneWidget);
    });

    testWidgets('AppearanceSection switches ThemeMode and ColorSeed interactively', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (context, ref, _) {
              capturedRef = ref;
              final cp = ref.watch(chatProvider);
              return ListenableBuilder(
                listenable: cp.themeVersion,
                builder: (context, _) {
                  return MaterialApp(
                    themeMode: cp.themeMode,
                    theme: AppTheme.light(colorSchemeSeed: cp.colorSeed),
                    darkTheme: AppTheme.dark(colorSchemeSeed: cp.colorSeed),
                    home: const SettingsScreen(initialTab: 2),
                  );
                },
              );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final chat = capturedRef.read(chatProvider);
      final initialVersion = chat.themeVersion.value;

      // 切换到暗黑模式
      expect(find.text('暗黑'), findsWidgets);
      await tester.tap(find.text('暗黑').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(chat.themeMode, equals(ThemeMode.dark));
      expect(chat.themeVersion.value, greaterThan(initialVersion));

      // 点击日落橙色板
      final sunsetFinder = find.byTooltip('日落橙');
      expect(sunsetFinder, findsOneWidget);
      await tester.tap(sunsetFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(chat.colorSeed?.toARGB32(), equals(const Color(0xFFEA580C).toARGB32()));
    });
  });
}
