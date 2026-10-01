import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lt_dialogue/features/settings/presentation/screens/settings_pages.dart';
import 'package:lt_dialogue/features/settings/presentation/widgets/data_management_section.dart';
import 'package:lt_dialogue/features/settings/presentation/widgets/appearance_section.dart';
import 'package:lt_dialogue/features/settings/presentation/widgets/provider_config_section.dart';
import 'package:lt_dialogue/features/prompt_settings/presentation/screens/prompt_advanced_settings.dart';
import 'package:lt_dialogue/features/prompt_settings/presentation/screens/context_weight_controls.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';
import '../helpers/responsive_test_helper.dart';

class _RouteObserver extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
  }
}

void main() {
  final l10n = AppLocalizationsZh();
  late Directory directory;
  late ProviderContainer container;
  late _RouteObserver observer;
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (_) async => null,
    );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({'main_sidebar_expanded': true});
    directory = await Directory.systemTemp.createTemp('lt_settings_workbench_');
    DatabaseService.customDbDir = directory.path;
    await DatabaseService.resetDatabase();
    container = ProviderContainer();
    observer = _RouteObserver();
  });
  tearDown(() async {
    container.dispose();
    await DatabaseService.resetDatabase();
    DatabaseService.customDbDir = null;
    await directory.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester,
      {Widget? home, double scale = 1.5}) async {
    await tester.runAsync(
        () => container.read(chatProvider).settingsProvider.loadApiKey());
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData.dark(useMaterial3: true),
        navigatorObservers: [observer],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: home ?? const SettingsPage(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  for (final size in [
    ...requiredUiViewports,
    const Size(375, 812),
    const Size(1024, 768),
    const Size(1440, 900)
  ]) {
    testWidgets(
        'Settings replaces category content without route pushes at $size',
        (tester) async {
      setViewport(tester, width: size.width, height: size.height);
      await mount(tester);
      final initialPushes = observer.pushes;
      for (final category in SettingsCategory.values) {
        final target =
            find.byKey(ValueKey('settings-category-${category.name}'));
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('settings-content-${category.name}')),
            findsOneWidget);
        expect(observer.pushes, initialPushes);
        if (category == SettingsCategory.context) {
          expect(find.byType(ContextWeightControls), findsOneWidget);
          expect(find.byType(PromptAdvancedSettings), findsOneWidget);
          expect(find.byType(ProviderConfigSection), findsNothing);
        }
        if (category == SettingsCategory.data) {
          expect(find.byType(DataManagementSection), findsOneWidget);
          expect(find.byType(ReadAloudSettingsSection), findsNothing);
        }
        if (category == SettingsCategory.readAloud) {
          expect(find.byType(ReadAloudSettingsSection), findsOneWidget);
          expect(find.byType(DataManagementSection), findsNothing);
        }
        if (size.width < 600) {
          await tester.tap(find.byTooltip(l10n.settingsReturnList));
          await tester.pumpAndSettle();
        } else {
          expect(target, findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('Appearance persists through original settings provider',
      (tester) async {
    setViewport(tester, width: 320, height: 568);
    await mount(tester,
        home: const SettingsPage(initialCategory: SettingsCategory.appearance),
        scale: 2);
    expect(find.byType(AppearanceSection), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('theme-mode-dark')));
    await tester.pump();
    expect(container.read(chatProvider).settingsProvider.themeMode,
        ThemeMode.dark);
    expect(tester.takeException(), isNull);
  });
}
