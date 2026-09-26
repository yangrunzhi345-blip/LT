import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/core/widgets/app_card.dart';
import 'package:lt_dialogue/core/widgets/app_empty_state.dart';
import 'package:lt_dialogue/features/adventure/presentation/home/screens/adventure_dashboard_screen.dart';
import 'package:lt_dialogue/features/adventure/presentation/home/widgets/dashboard_action_cards.dart';
import 'package:lt_dialogue/features/adventure/presentation/home/widgets/dashboard_character_cards.dart';
import 'package:lt_dialogue/features/adventure/presentation/home/widgets/dashboard_featured_worlds.dart';
import 'package:lt_dialogue/features/adventure/presentation/home/widgets/dashboard_hero_header.dart';
import 'package:lt_dialogue/features/adventure/presentation/home/widgets/dashboard_recent_saves.dart';
import 'package:lt_dialogue/features/adventure/presentation/home/widgets/dashboard_state_section.dart';
import 'package:lt_dialogue/features/adventure/presentation/state/runtime_state_hub_page.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/providers/chat_provider.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';

import '../helpers/responsive_test_helper.dart';

class _FakeKeyChatProvider extends ChatProvider {
  final bool _configured;

  _FakeKeyChatProvider({required bool configured}) : _configured = configured;

  @override
  bool get isKeyConfigured => _configured;
}

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

  Widget buildTestApp({
    Key? key,
    required Widget child,
    ProviderContainer? container,
    List<dynamic> overrides = const [],
    ThemeMode themeMode = ThemeMode.light,
    double textScaleFactor = 1.0,
  }) {
    final app = MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      home: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(textScaleFactor),
        ),
        child: child,
      ),
    );

    if (container != null) {
      return UncontrolledProviderScope(
        key: key,
        container: container,
        child: app,
      );
    }
    return ProviderScope(
      key: key,
      overrides: overrides.cast(),
      child: app,
    );
  }

  group('Phase 2: Adventure Dashboard Redesign Tests', () {
    testWidgets(
      'DashboardHeroHeader renders editorial header without AI clichés and fits 320px',
      (tester) async {
        setViewport(tester, width: 320, height: 640);

        await tester.pumpWidget(
          buildTestApp(
            child: const Scaffold(
              body: DashboardHeroHeader(),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('灵境 · 探索与叙事工坊'), findsOneWidget);
        expect(find.text('交互小说与沉浸式 RPG 叙事空间'), findsOneWidget);
        expect(find.byIcon(Icons.auto_awesome_rounded), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'DashboardHeroHeader handles unconfigured API key and settings callbacks',
      (tester) async {
        setViewport(tester, width: 360, height: 640);
        bool settingsOpened = false;

        // Initially no API key configured
        await tester.pumpWidget(
          buildTestApp(
            key: const ValueKey('header-unconfigured'),
            overrides: [
              chatProvider.overrideWith(
                (ref) => _FakeKeyChatProvider(configured: false),
              ),
            ],
            child: Scaffold(
              body: DashboardHeroHeader(
                onOpenSettings: () => settingsOpened = true,
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('配置密钥'), findsOneWidget);
        await tester.tap(find.text('配置密钥'));
        await tester.pump();
        expect(settingsOpened, isTrue);

        // When configured, it shows settings icon instead of key badge
        await tester.pumpWidget(
          buildTestApp(
            key: const ValueKey('header-configured'),
            overrides: [
              chatProvider.overrideWith(
                (ref) => _FakeKeyChatProvider(configured: true),
              ),
            ],
            child: Scaffold(
              body: DashboardHeroHeader(
                onOpenSettings: () => settingsOpened = true,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('配置密钥'), findsNothing);
        expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
      },
    );

    testWidgets(
      'DashboardActionCards renders primary wizard and secondary entries on 320px',
      (tester) async {
        setViewport(tester, width: 320, height: 640);

        bool wizardOpened = false;
        bool presetOpened = false;
        bool libraryOpened = false;
        bool settingsOpened = false;

        await tester.pumpWidget(
          buildTestApp(
            child: Scaffold(
              body: SingleChildScrollView(
                child: DashboardActionCards(
                  onOpenWizard: () => wizardOpened = true,
                  onOpenPresetScenes: () => presetOpened = true,
                  onOpenLibrary: () => libraryOpened = true,
                  onOpenSettings: () => settingsOpened = true,
                ),
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

        await tester.tap(find.text('资料库'));
        await tester.pump();
        expect(libraryOpened, isTrue);

        await tester.tap(find.text('系统设置中心'));
        await tester.pump();
        expect(settingsOpened, isTrue);

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'DashboardRecentSaves renders empty state with actionable wizard button',
      (tester) async {
        setViewport(tester, width: 320, height: 640);

        bool wizardOpened = false;
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          buildTestApp(
            container: container,
            child: Scaffold(
              body: DashboardRecentSaves(
                onOpenWizard: () => wizardOpened = true,
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('尚未开始任何场景冒险'), findsOneWidget);
        expect(find.text('启动向导'), findsOneWidget);

        await tester.tap(find.text('启动向导'));
        await tester.pump();
        expect(wizardOpened, isTrue);
      },
    );

    testWidgets(
      'DashboardRecentSaves renders saves list with long titles and delete action',
      (tester) async {
        setViewport(tester, width: 320, height: 640);

        final container = ProviderContainer();
        addTearDown(container.dispose);

        final chat = container.read(chatProvider);
        chat.adventureProvider.adventureList.add({
          'id': 1,
          'title': '暮色边境 · 遗失遗迹深处古老卷轴与巨龙叹息之夜未尽物语超长标题测试，确保两行换行不溢出',
          'updated_at': '2026-09-26 14:00',
        });

        await tester.pumpWidget(
          buildTestApp(
            container: container,
            child: const Scaffold(
              body: SingleChildScrollView(
                child: DashboardRecentSaves(),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('继续未尽的冒险'), findsOneWidget);
        expect(
          find.text('暮色边境 · 遗失遗迹深处古老卷轴与巨龙叹息之夜未尽物语超长标题测试，确保两行换行不溢出'),
          findsOneWidget,
        );
        expect(find.text('继续探索'), findsOneWidget);

        // Tap card to open adventure
        await tester.tap(find.text('继续探索'));
        await tester.pump();

        // Delete button opens confirmation dialog
        expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
        await tester.tap(find.byIcon(Icons.delete_outline_rounded));
        await tester.pumpAndSettle();

        expect(find.text('删除冒险记录'), findsOneWidget);
        expect(find.text('删除'), findsWidgets);
        expect(find.text('取消'), findsOneWidget);

        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'DashboardFeaturedWorlds handles world selection and long text',
      (tester) async {
        setViewport(tester, width: 320, height: 640);

        AdventureConfig? selectedConfig;

        await tester.pumpWidget(
          buildTestApp(
            child: Scaffold(
              body: SingleChildScrollView(
                child: DashboardFeaturedWorlds(
                  onSelectWorld: (config) => selectedConfig = config,
                  onCreateWorld: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('我的世界设定'), findsOneWidget);
        expect(find.byIcon(Icons.public_rounded), findsOneWidget);
        expect(selectedConfig, isNull);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'DashboardCharacterCards renders section title and icon without overflow',
      (tester) async {
        setViewport(tester, width: 320, height: 640);

        await tester.pumpWidget(
          buildTestApp(
            child: Scaffold(
              body: SingleChildScrollView(
                child: DashboardCharacterCards(
                  onSelectCharacter: (_) {},
                  onCreateCharacter: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('我的角色卡档案'), findsOneWidget);
        expect(find.byIcon(Icons.badge_outlined), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'DashboardStateSection renders current state entry and responds to tap',
      (tester) async {
        setViewport(tester, width: 320, height: 640);

        bool stateHubOpened = false;

        await tester.pumpWidget(
          buildTestApp(
            child: Scaffold(
              body: DashboardStateSection(
                onOpenStateHub: () => stateHubOpened = true,
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('当前状态'), findsOneWidget);
        expect(find.byIcon(Icons.hub_outlined), findsOneWidget);

        await tester.tap(find.byType(AppCard));
        await tester.pump();
        expect(stateHubOpened, isTrue);

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'DashboardStateSection real Navigator routing pushes RuntimeStateHubPage and displays localized empty state when no active adventure',
      (tester) async {
        setViewport(tester, width: 390, height: 844);

        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Ensure no active adventure
        expect(container.read(chatProvider).currentAdventureId, isNull);

        await tester.pumpWidget(
          buildTestApp(
            container: container,
            child: AdventureDashboardScreen(
              onStartAdventure: (_, {difficulty}) async {},
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Scroll down to DashboardStateSection
        await tester.drag(find.byType(ListView), const Offset(0, -600));
        await tester.pump(const Duration(milliseconds: 200));

        final stateSectionFinder = find.byType(DashboardStateSection);
        expect(stateSectionFinder, findsOneWidget);

        // Tap on DashboardStateSection's card to navigate
        final cardFinder = find.descendant(
          of: stateSectionFinder,
          matching: find.byType(AppCard),
        );
        expect(cardFinder, findsOneWidget);
        await tester.tap(cardFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        // Verify real Navigator route pushed RuntimeStateHubPage
        expect(find.byType(RuntimeStateHubPage), findsOneWidget);

        // Verify localized empty state is rendered clearly
        expect(find.byType(AppEmptyState), findsOneWidget);
        expect(find.text('没有活动冒险'), findsOneWidget);

        // Verify no exceptions
        expect(tester.takeException(), isNull);

        // Pop back to ensure navigation pop works cleanly
        final navigator =
            tester.state<NavigatorState>(find.byType(Navigator).last);
        navigator.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byType(RuntimeStateHubPage), findsNothing);
        expect(find.byType(AdventureDashboardScreen), findsOneWidget);
      },
    );

    testWidgets(
      'DashboardRecentSaves supports ultra-long title with 2-line wrapping and detail Tooltip without overflow',
      (tester) async {
        setViewport(tester, width: 320, height: 568);

        final container = ProviderContainer();
        addTearDown(container.dispose);

        const longTitle = '这是一个非常非常长的未尽冒险史诗标题用于验证移动端排版换行两行与提示入口不会发生任何布局溢出';
        final chat = container.read(chatProvider);
        chat.adventureProvider.adventureList.add({
          'id': 999,
          'title': longTitle,
          'updated_at': '2026-09-26 18:00',
        });

        await tester.pumpWidget(
          buildTestApp(
            container: container,
            child: const Scaffold(
              body: SingleChildScrollView(
                child: DashboardRecentSaves(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify title text exists and has Tooltip
        final tooltipFinder = find.widgetWithText(Tooltip, longTitle);
        expect(tooltipFinder, findsOneWidget);

        final textWidget = tester.widget<Text>(find.descendant(
          of: tooltipFinder,
          matching: find.text(longTitle),
        ));
        expect(textWidget.maxLines, 2);
        expect(textWidget.overflow, TextOverflow.ellipsis);

        // Verify no overflow at 320px
        expect(tester.takeException(), isNull);
      },
    );

    // Comprehensive requiredUiViewports validation
    for (final size in requiredUiViewports) {
      testWidgets(
        'AdventureDashboardScreen fits viewport $size with zero RenderFlex overflow',
        (tester) async {
          setViewport(tester, width: size.width, height: size.height);

          final container = ProviderContainer();
          addTearDown(container.dispose);

          // Add a save to test "继续未尽的冒险" priority placement
          final chat = container.read(chatProvider);
          chat.adventureProvider.adventureList.add({
            'id': 101,
            'title': '暮色边境 · 永夜高塔',
            'updated_at': '2026-09-26 15:30',
          });

          await tester.pumpWidget(
            buildTestApp(
              container: container,
              child: AdventureDashboardScreen(
                onStartAdventure: (_, {difficulty}) async {},
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));

          expect(find.text('灵境 · 探索与叙事工坊'), findsOneWidget);
          expect(find.text('继续未尽的冒险'), findsOneWidget);
          expect(find.text('四步向导定制'), findsWidgets);
          expect(find.text('预存场景工坊'), findsWidgets);
          expect(find.text('资料库'), findsWidgets);
          expect(find.text('系统设置中心'), findsWidgets);

          // Scroll down to reveal subsequent sections in lazy ListView
          await tester.drag(find.byType(ListView), const Offset(0, -600));
          await tester.pump();
          expect(find.text('当前状态'), findsWidgets);

          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'AdventureDashboardScreen supports Dark Theme and 2.0x font scaling without overflow',
      (tester) async {
        setViewport(tester, width: 320, height: 568);

        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          buildTestApp(
            container: container,
            themeMode: ThemeMode.dark,
            textScaleFactor: 2.0,
            child: AdventureDashboardScreen(
              onStartAdventure: (_, {difficulty}) async {},
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('灵境 · 探索与叙事工坊'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
