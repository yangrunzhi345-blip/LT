import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/domain/read_aloud/read_aloud_contracts.dart';
import 'package:lt_dialogue/features/settings/presentation/widgets/data_management_section.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/read_aloud/read_aloud_controller.dart';
import 'package:lt_dialogue/services/read_aloud/read_aloud_settings_store.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';

import '../helpers/read_aloud_fakes.dart';
import '../helpers/responsive_test_helper.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    // SettingsProvider 构造时会订阅 connectivity_plus；flutter_test 没有
    // 平台实现，未 mock 会抛 MissingPluginException。
    final messenger = TestWidgetsFlutterBinding.instance.defaultBinaryMessenger;
    for (final name in const [
      'dev.fluttercommunity.plus/connectivity',
      'dev.fluttercommunity.plus/connectivity_status',
    ]) {
      messenger.setMockMethodCallHandler(
          MethodChannel(name), (call) async => null);
    }
  });

  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('lt_settings_tts_test_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    container = ProviderContainer();
  });

  tearDown(() async {
    container.dispose();
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  Future<void> pumpSection(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: const Scaffold(
            body: SingleChildScrollView(child: DataManagementSection()),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('设置页朗读偏好', () {
    testWidgets('展示启用/自动朗读开关与语速音调滑杆', (tester) async {
      setViewport(tester, width: 390, height: 844);
      await pumpSection(tester);

      expect(find.text('语音消息朗读 (TTS)'), findsOneWidget);
      expect(find.text('启用语音朗读'), findsOneWidget);
      expect(find.text('完成时自动朗读'), findsOneWidget);
      expect(find.text('语速'), findsOneWidget);
      expect(find.text('音调'), findsOneWidget);
      expect(find.byType(Slider), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('开关与滑杆写入 SettingsRepository KV', (tester) async {
      setViewport(tester, width: 390, height: 844);
      await pumpSection(tester);

      final repository = container.read(settingsRepoProvider);
      // sqflite 是真实 I/O：在 testWidgets 里必须通过 runAsync 驱动。
      expect(
        await tester.runAsync(
          () => repository.getSetting(ReadAloudSettingKeys.enabled),
        ),
        isNot('1'),
      );

      await tester.tap(find.text('启用语音朗读'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();

      expect(container.read(readAloudControllerProvider).enabled, isTrue);
      expect(
        await tester.runAsync(
          () => repository.getSetting(ReadAloudSettingKeys.enabled),
        ),
        '1',
      );

      await tester.tap(find.text('完成时自动朗读'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(
        await tester.runAsync(
          () => repository.getSetting(ReadAloudSettingKeys.autoRead),
        ),
        '1',
      );

      await tester.drag(find.byType(Slider).first, const Offset(60, 0));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();

      final storedRate = await tester.runAsync(
        () => repository.getSetting(ReadAloudSettingKeys.rate),
      );
      expect(storedRate, isNotNull);
      expect(storedRate, isNot('0.5'));
      expect(container.read(readAloudControllerProvider).rate, isNot(0.5));
    });

    testWidgets('320px 窄屏下 TTS 设置卡片无布局溢出', (tester) async {
      for (final size in requiredUiViewports) {
        setViewport(tester, width: size.width, height: size.height);
        await pumpSection(tester);
        expect(tester.takeException(), isNull, reason: 'TTS 设置卡片在 $size 下不应溢出');
      }
    });
  });

  group('设置页朗读语言', () {
    testWidgets('展示自动检测与精选语言选项', (tester) async {
      setViewport(tester, width: 390, height: 844);
      await pumpSection(tester);

      expect(find.text('朗读语言'), findsOneWidget);
      expect(find.text('自动检测'), findsOneWidget);
      expect(find.text('简体中文'), findsOneWidget);
      expect(find.text('繁体中文'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('日本語'), findsOneWidget);
      expect(find.text('한국어'), findsOneWidget);
      expect(find.text('根据每段正文自动选择可用的系统语音语言。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('选择固定语言切换模式并写入 languageMode / languageTag', (tester) async {
      // 高视口让语言选择器直接落在可视区域内，点击无需滚动。
      setViewport(tester, width: 390, height: 2000);
      await pumpSection(tester);

      final repository = container.read(settingsRepoProvider);
      // 必须先在真实 async 区打开数据库：否则首次 DB I/O 会在 fake-async 区
      // 发起而永远挂起（sqflite 是真实 I/O）。
      await tester.runAsync(
        () => repository.getSetting(ReadAloudSettingKeys.languageTag),
      );

      await tester.tap(find.text('日本語'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();

      final controller = container.read(readAloudControllerProvider);
      expect(controller.languageMode, ReadAloudLanguageMode.fixed);
      expect(controller.languageTag, 'ja-JP');
      expect(
        await tester.runAsync(
          () => repository.getSetting(ReadAloudSettingKeys.languageMode),
        ),
        'fixed',
      );
      expect(
        await tester.runAsync(
          () => repository.getSetting(ReadAloudSettingKeys.languageTag),
        ),
        'ja-JP',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('系统不支持的语言被标注不支持且不可选', (tester) async {
      setViewport(tester, width: 390, height: 844);
      final controller = ReadAloudController(
        engine: FakeReadAloudEngine(
          availableLanguageTags: const <String>['zh-CN', 'en-US'],
        ),
        initialPreferences: const ReadAloudPreferences(enabled: true),
      );
      final localContainer = ProviderContainer(
        overrides: [
          readAloudControllerProvider.overrideWith(
            (ref) => controller,
            disposeNotifier: false,
          ),
        ],
      );
      addTearDown(localContainer.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: localContainer,
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light(),
            home: const Scaffold(
              body: SingleChildScrollView(child: DataManagementSection()),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('简体中文'), findsOneWidget);
      expect(find.text('日本語（不支持）'), findsOneWidget);
      expect(find.text('한국어（不支持）'), findsOneWidget);
      expect(find.text('系统可用语言：2 种'), findsOneWidget);
      expect(localContainer.read(readAloudControllerProvider).languageTag,
          ReadAloudPreferences.defaultLanguageTag);
      expect(tester.takeException(), isNull);
    });
  });
}
