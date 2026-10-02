import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lt_dialogue/core/theme/app_colors.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
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

  group('Light theme selection controls', () {
    // WCAG helpers mirrored from the theme contrast suite so widget tests can
    // assert the *rendered* control contract, not only the raw theme data.
    double linearize(double c) => c <= 0.04045
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    double lum(Color c) =>
        0.2126 * linearize(c.r) +
        0.7152 * linearize(c.g) +
        0.0722 * linearize(c.b);
    double ratio(Color a, Color b) {
      final la = lum(a), lb = lum(b);
      return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
    }

    Future<ThemeData> mountAppearance(
      WidgetTester tester, {
      Color? seed,
      bool dark = false,
      Size size = const Size(420, 900),
      double scale = 1.5,
    }) async {
      setViewport(tester, width: size.width, height: size.height);
      final theme = dark
          ? AppTheme.dark(colorSchemeSeed: seed)
          : AppTheme.light(colorSchemeSeed: seed);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(child: AppearanceSection()),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return theme;
    }

    List<ChoiceChip> themeModeChips(WidgetTester tester) => [
          for (final mode in ThemeMode.values)
            tester.widget<ChoiceChip>(
              find.byKey(ValueKey('theme-mode-${mode.name}')),
            ),
        ];

    testWidgets(
        'light ThemeMode chips are readable and own no local colour overrides',
        (tester) async {
      final theme = await mountAppearance(tester);
      final chips = themeModeChips(tester);
      expect(chips, hasLength(3));

      // The theme is the single colour authority: no chip carries a bespoke
      // selectedColor / labelStyle / backgroundColor.
      for (final chip in chips) {
        expect(chip.selectedColor, isNull);
        expect(chip.labelStyle, isNull);
        expect(chip.backgroundColor, isNull);
      }

      final chipTheme = theme.chipTheme;
      final unselectedBg = chipTheme.color!.resolve(const <WidgetState>{})!;
      final unselectedFg = WidgetStateProperty.resolveAs<Color?>(
        chipTheme.labelStyle!.color,
        const <WidgetState>{},
      )!;
      final selectedBg = Color.alphaBlend(
        chipTheme.color!.resolve(const <WidgetState>{WidgetState.selected})!,
        unselectedBg,
      );
      final selectedFg = WidgetStateProperty.resolveAs<Color?>(
        chipTheme.labelStyle!.color,
        const <WidgetState>{WidgetState.selected},
      )!;
      final disabledFg = WidgetStateProperty.resolveAs<Color?>(
        chipTheme.labelStyle!.color,
        const <WidgetState>{WidgetState.disabled},
      )!;

      expect(ratio(unselectedFg, unselectedBg), greaterThanOrEqualTo(4.5));
      expect(ratio(selectedFg, selectedBg), greaterThanOrEqualTo(4.5));
      // Unselected must not look disabled.
      expect(unselectedFg, isNot(disabledFg));
      expect(unselectedFg, theme.colorScheme.onSurface);

      // Every ThemeMode label is present and non-empty.
      for (final mode in ThemeMode.values) {
        expect(find.byKey(ValueKey('theme-mode-${mode.name}')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('selected ThemeMode is visibly distinct from unselected',
        (tester) async {
      final theme = await mountAppearance(tester);
      final chips = themeModeChips(tester);
      final selectedCount = chips.where((chip) => chip.selected).length;
      expect(selectedCount, inInclusiveRange(0, 1));

      final chipTheme = theme.chipTheme;
      final unselectedBg = chipTheme.color!.resolve(const <WidgetState>{})!;
      final selectedBg = chipTheme.color!.resolve(
        const <WidgetState>{WidgetState.selected},
      )!;
      expect(selectedBg, isNot(unselectedBg));
      final side = WidgetStateProperty.resolveAs<BorderSide?>(
        chipTheme.side,
        const <WidgetState>{WidgetState.selected},
      )!;
      expect(side.color, theme.colorScheme.primary);
      expect(tester.takeException(), isNull);
    });

    for (final seedName in const ['海洋蓝', '日落橙', '森林绿', '紫罗兰', '极简灰']) {
      testWidgets('dynamic seed $seedName keeps ThemeMode chips readable',
          (tester) async {
        final theme = await mountAppearance(tester,
            seed: AppColors.seedForName(seedName));
        final chipTheme = theme.chipTheme;
        final unselectedBg = chipTheme.color!.resolve(const <WidgetState>{})!;
        final fg = WidgetStateProperty.resolveAs<Color?>(
          chipTheme.labelStyle!.color,
          const <WidgetState>{},
        )!;
        expect(ratio(fg, unselectedBg), greaterThanOrEqualTo(4.5),
            reason: '$seedName unselected');
        final selectedBg = Color.alphaBlend(
          chipTheme.color!.resolve(const <WidgetState>{WidgetState.selected})!,
          unselectedBg,
        );
        expect(ratio(fg, selectedBg), greaterThanOrEqualTo(4.5),
            reason: '$seedName selected');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('renders at 320px with 2.0 text scale without overflow',
        (tester) async {
      await mountAppearance(
        tester,
        size: const Size(320, 568),
        scale: 2.0,
      );
      expect(find.byType(ChoiceChip), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('dark theme chips stay readable and unchanged', (tester) async {
      final theme = await mountAppearance(tester, dark: true);
      final chipTheme = theme.chipTheme;
      final unselectedBg = chipTheme.color!.resolve(const <WidgetState>{})!;
      final fg = WidgetStateProperty.resolveAs<Color?>(
        chipTheme.labelStyle!.color,
        const <WidgetState>{},
      )!;
      expect(ratio(fg, unselectedBg), greaterThanOrEqualTo(4.5));
      expect(find.byType(ChoiceChip), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });
  });
}
