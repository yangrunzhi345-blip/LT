import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/core/widgets/app_card.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/features/adventure/presentation/home/screens/adventure_dashboard_screen.dart';
import 'package:lt_dialogue/features/adventure/presentation/home/widgets/dashboard_start_actions.dart';
import 'package:lt_dialogue/features/adventure/presentation/home/widgets/dashboard_character_cards.dart';
import 'package:lt_dialogue/features/adventure/presentation/home/widgets/dashboard_featured_worlds.dart';
import 'package:lt_dialogue/features/adventure/presentation/home/widgets/dashboard_hero_header.dart';
import 'package:lt_dialogue/features/adventure/presentation/home/widgets/dashboard_recent_saves.dart';
import 'package:lt_dialogue/features/adventure/presentation/home/widgets/dashboard_state_section.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/app_section.dart';
import 'package:lt_dialogue/models/message.dart';
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

class _RecordingAdventureChatProvider extends ChatProvider {
  Future<void>? openedAdventure;
  Future<void>? movedAdventure;
  @override
  Future<void> moveAdventureToTrash(int id) {
    final operation = super.moveAdventureToTrash(id);
    movedAdventure = operation;
    return operation;
  }

  @override
  Future<void> openAdventure(int id) {
    final operation = super.openAdventure(id);
    openedAdventure = operation;
    return operation;
  }
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
      home: Builder(
          builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(textScaleFactor)),
                child: child,
              )),
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

        expect(find.text('冒险'), findsOneWidget);
        expect(find.text('交互小说与沉浸式 RPG 叙事空间'), findsNothing);
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

        expect(find.byTooltip('配置密钥'), findsOneWidget);
        await tester.tap(find.byTooltip('配置密钥'));
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
        expect(find.byTooltip('配置密钥'), findsNothing);
        expect(find.byTooltip('配置密钥'), findsNothing);
      },
    );

    testWidgets(
      'DashboardStartActions renders primary wizard and secondary entries on 320px',
      (tester) async {
        setViewport(tester, width: 320, height: 640);

        bool wizardOpened = false;
        bool presetOpened = false;
        bool libraryOpened = false;

        await tester.pumpWidget(
          buildTestApp(
            child: Scaffold(
              body: SingleChildScrollView(
                child: DashboardStartActions(
                  onOpenWizard: () => wizardOpened = true,
                  onOpenPresetScenes: () => presetOpened = true,
                  onOpenLibrary: () => libraryOpened = true,
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('启动向导'), findsOneWidget);
        expect(find.text('预存场景工坊'), findsOneWidget);
        expect(find.text('资料库'), findsOneWidget);
        expect(find.text('系统设置中心'), findsNothing);
        expect(find.byType(AppCard), findsNothing);

        await tester.tap(find.text('启动向导'));
        await tester.pump();
        expect(wizardOpened, isTrue);

        await tester.tap(find.text('预存场景工坊'));
        await tester.pump();
        expect(presetOpened, isTrue);

        await tester.tap(find.text('资料库'));
        await tester.pump();
        expect(libraryOpened, isTrue);

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'DashboardRecentSaves renders nothing without saves (onboarding is owned by start actions)',
      (tester) async {
        setViewport(tester, width: 320, height: 640);

        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          buildTestApp(
            container: container,
            child: const Scaffold(body: DashboardRecentSaves()),
          ),
        );
        await tester.pump();

        // The empty onboarding invitation lives in DashboardStartActions, so a
        // save-less recent list must not add a second "启动向导" entry.
        expect(find.text('尚未开始任何场景冒险'), findsNothing);
        expect(find.text('启动向导'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'DashboardRecentSaves keeps main CTA and moves long-title story to recoverable trash',
      (tester) async {
        setViewport(tester, width: 320, height: 640);

        late _RecordingAdventureChatProvider recordingChat;
        late ProviderContainer container;
        await tester.runAsync(() async {
          await DatabaseService.database;
          recordingChat = _RecordingAdventureChatProvider();
          container = ProviderContainer(
              overrides: [chatProvider.overrideWith((ref) => recordingChat)]);
          await recordingChat.loadApiKey();
        });
        addTearDown(container.dispose);
        final chat = container.read(chatProvider);
        final repo = container.read(adventureRepoProvider);
        const title = '暮色边境 · 遗失遗迹深处古老卷轴与巨龙叹息之夜未尽物语超长标题测试，确保两行换行不溢出';
        late int id;
        await tester.runAsync(() async {
          await chat.loadApiKey();
          id = await repo.createAdventure(title, AdventureConfig());
          await repo.insertMessage(id,
              Message(id: 'kept-message', content: '保留的叙事正文', isUser: false));
          await chat.loadAdventureList();
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

        // The confirmation itself must not mutate any persisted story data.
        expect(find.byTooltip('移入回收站'), findsOneWidget);
        await tester.tap(find.byTooltip('移入回收站'));
        await tester.pumpAndSettle();
        expect(find.text('取消'), findsOneWidget);
        await tester.runAsync(() async {
          expect(await repo.getAdventureById(id), isNotNull);
          expect(await container.read(resourceTrashServiceProvider).list(),
              isEmpty);
        });
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          expect(await repo.getAdventureById(id), isNotNull);
        });

        await tester.tap(find.byTooltip('移入回收站'));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(find.text('移入回收站').last);
          await recordingChat.movedAdventure;
        });
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          expect(await repo.getAdventureById(id), isNull);
          final db = await DatabaseService.database;
          expect(await db.query('adventures', where: 'id = ?', whereArgs: [id]),
              hasLength(1));
          expect(await repo.getMessages(id), hasLength(1));
          final marker =
              (await container.read(resourceTrashServiceProvider).list())
                  .single;
          await container
              .read(resourceTrashRuntimeProvider)
              .restore(marker.trashId);
          expect(await repo.getAdventureById(id), isNotNull);
          expect((await repo.getMessages(id)).single.content, '保留的叙事正文');
          expect(chat.adventureList.single['id'], id);
        });
        await tester.pump();
        expect(find.text('继续探索'), findsOneWidget);

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
        expect(find.byIcon(Icons.public_rounded), findsNothing);
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
        expect(find.byIcon(Icons.badge_outlined), findsNothing);
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
        expect(find.byIcon(Icons.hub_outlined), findsNothing);

        await tester.tap(find.byKey(const Key('dashboard-runtime-state')));
        await tester.pump();
        expect(stateHubOpened, isTrue);

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'DashboardStateSection navigates through the existing workspace authority',
      (tester) async {
        setViewport(tester, width: 390, height: 844);
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await tester.pumpWidget(buildTestApp(
            container: container,
            child: AdventureDashboardScreen(
                onStartAdventure: (_, {difficulty}) async {})));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        final entry = find.byKey(const Key('dashboard-runtime-state'));
        await tester.ensureVisible(entry);
        await tester.tap(entry);
        await tester.pump();
        expect(container.read(chatProvider).currentSection,
            AppSection.runtimeState);
        expect(Navigator.of(tester.element(entry)).canPop(), isFalse);
        expect(tester.takeException(), isNull);
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

    testWidgets('should resume a real stored adventure in one click',
        (tester) async {
      setViewport(tester, width: 320, height: 568);
      final recordingChat = _RecordingAdventureChatProvider();
      final container = ProviderContainer(
          overrides: [chatProvider.overrideWith((ref) => recordingChat)]);
      addTearDown(container.dispose);
      final chat = container.read(chatProvider);
      final id = await tester.runAsync(() => container
          .read(adventureRepoProvider)
          .createAdventure(
              '已保存的长篇故事：穿越群山和漫长海岸，返回银月城的未尽旅程', AdventureConfig(name: '主角')));
      await tester.runAsync(chat.loadAdventureList);
      await tester.pumpWidget(buildTestApp(
          container: container,
          child: const Scaffold(
              body: SingleChildScrollView(child: DashboardRecentSaves()))));
      await tester.pumpAndSettle();
      await tester
          .tap(find.text(AppLocalizationsZh().dashboardContinueExploring));
      expect(recordingChat.openedAdventure, isNotNull);
      await tester.runAsync(() => recordingChat.openedAdventure!);
      await tester.pumpAndSettle();
      expect(chat.currentAdventureId, id);
      expect(chat.isAdventureChatOpen, isTrue);
      expect(tester.takeException(), isNull);
    });

    // Comprehensive requiredUiViewports validation
    for (final size in [
      ...requiredUiViewports,
      const Size(375, 812),
      const Size(1024, 768),
      const Size(1440, 900)
    ]) {
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

          expect(find.text('冒险'), findsOneWidget);
          expect(find.text('继续未尽的冒险'), findsOneWidget);
          expect(
              find.byKey(const Key('dashboard-new-adventure')), findsOneWidget);
          expect(find.text('预存场景工坊'), findsWidgets);
          expect(find.text('资料库'), findsWidgets);
          expect(find.text('系统设置中心'), findsNothing);

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

        expect(find.text('冒险'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
