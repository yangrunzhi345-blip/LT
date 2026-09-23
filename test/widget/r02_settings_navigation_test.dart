import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/features/prompt_settings/presentation/screens/prompt_preview_page.dart';
import 'package:lt_dialogue/features/settings/presentation/screens/chat_transfer_pages.dart';
import 'package:lt_dialogue/features/settings/presentation/screens/settings_pages.dart';
import 'package:lt_dialogue/main.dart' show MainGate;
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';

import '../helpers/responsive_test_helper.dart';

void main() {
  final l10n = AppLocalizationsZh();
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory databaseDirectory;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    databaseDirectory =
        await Directory.systemTemp.createTemp('lt_r02_settings_');
    DatabaseService.customDbDir = databaseDirectory.path;
    await DatabaseService.resetDatabase();
  });
  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (databaseDirectory.existsSync()) {
      databaseDirectory.deleteSync(recursive: true);
    }
  });

  Widget application(Widget page) => ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: page,
        ),
      );

  group('R02 settings navigation', () {
    testWidgets(
        'should enter the app and offer settings on startup without a key',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.runAsync(() => container.read(chatProvider).loadApiKey());
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('zh'),
          home: MainGate(),
        ),
      ));
      await tester.runAsync(() => container.read(chatProvider).loadApiKey());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(Dialog), findsNothing);
      expect(find.textContaining('尚未配置 API 密钥'), findsWidgets);
      expect(find.text('前往设置'), findsOneWidget);
      await tester.tap(find.text('前往设置'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final size in requiredUiViewports) {
      testWidgets('should open API settings and return at $size',
          (tester) async {
        setViewport(tester, width: size.width, height: size.height);
        await tester.pumpWidget(application(const SettingsPage()));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('settings-api-hint')), findsOneWidget);
        await tester.tap(find.text(l10n.providerConfigTitle));
        await tester.pumpAndSettle();
        expect(find.byType(ApiSettingsPage), findsOneWidget);
        expect(find.byType(Dialog), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('返回'));
        await tester.pumpAndSettle();
        expect(find.byType(SettingsPage), findsOneWidget);
      });
    }

    testWidgets('should navigate to model and advanced settings',
        (tester) async {
      setViewport(tester, width: 320, height: 568);
      tester.view.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(application(const SettingsPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.modelParamsSectionTitle));
      await tester.pumpAndSettle();
      expect(find.byType(ModelSettingsPage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.settingsSystemConfig));
      await tester.pumpAndSettle();
      expect(find.byType(AdvancedSettingsPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('should validate empty chat import without writing',
        (tester) async {
      setViewport(tester, width: 320, height: 568);
      await tester.pumpWidget(application(const ImportPage()));
      await tester.tap(find.byKey(const Key('chat-import-submit')));
      await tester.pump();
      expect(find.text('请先粘贴聊天内容'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('should render export as a page', (tester) async {
      setViewport(tester, width: 390, height: 844);
      await tester.pumpWidget(application(const ExportPage()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat-export-save')), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('should preview a long prompt without a modal', (tester) async {
      setViewport(tester, width: 320, height: 568);
      await tester.pumpWidget(application(PromptPreviewPage(
        preview: [
          {'role': 'system', 'content': '长提示词内容' * 150},
        ],
      )));
      await tester.pumpAndSettle();
      expect(find.byTooltip('复制完整 Prompt'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
