import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/resource_lifecycle_projection.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_library_runtime.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_service.dart';
import 'package:lt_dialogue/core/responsive/app_breakpoints.dart';
import 'package:lt_dialogue/core/widgets/app_empty_state.dart';
import 'package:lt_dialogue/core/widgets/app_error_view.dart';
import 'package:lt_dialogue/core/widgets/app_text_field.dart';
import 'package:lt_dialogue/core/widgets/workbench_chrome.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/setting_cards/setting_card.dart';
import 'package:lt_dialogue/features/resource_library/application/use_cases/resource_library_runtime.dart';
import 'package:lt_dialogue/features/resource_library/domain/models/resource_library_view_state.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_library_screen.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/setting_card_detail_page.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';

import '../helpers/responsive_test_helper.dart';
import '../helpers/setting_card_fakes.dart';

final class _MockResourceLibraryRuntime implements ResourceLibraryRuntime {
  _MockResourceLibraryRuntime({
    this.items = const [],
    this.throwError = false,
  });

  List<ResourceLibraryItem> items;
  final bool throwError;

  @override
  Future<List<ResourceLibraryItem>> load(ResourceLibraryMode mode) async {
    if (throwError) {
      throw Exception('Database query failed');
    }
    return List.unmodifiable(items);
  }
}

final _testItems = <ResourceLibraryItem>[
  const ResourceLibraryItem(
    id: 'res_1',
    type: ResourceType.worldview,
    name: '艾尔登法环世界观：交界地与黄金律法的历史渊源以及破碎战争的全景展开长标题',
    summary:
        '详细阐述了黄金律法被毁之后，玛莉卡女王的诸位半神子嗣为了夺取大卢恩发动破碎战争的宏大历史背景。包含宁姆格福、利耶尼亚、盖利德以及罗德尔王城的地理与势力分布。',
    updatedAt: '2026-09-26 12:00',
    status: ResourceDisplayStatus.ready,
    isConsumable: true,
    lifecycleState: ResourceLifecycleState.ready,
  ),
  const ResourceLibraryItem(
    id: 'res_2',
    type: ResourceType.character,
    name: '魔女菈妮',
    summary: '暗月之剑的主人，卡利亚王室的真正继承人。',
    updatedAt: '2026-09-25 10:00',
    status: ResourceDisplayStatus.generating,
    isConsumable: false,
    lifecycleState: ResourceLifecycleState.generating,
  ),
  const ResourceLibraryItem(
    id: 'res_3',
    type: ResourceType.npc,
    name: '铁拳亚历山大',
    summary: '活壶战士，为了磨砺自我前往盖利德参与红狮子城战斗祭典。',
    updatedAt: '2026-09-24 08:00',
    status: ResourceDisplayStatus.optimizing,
    isConsumable: false,
    lifecycleState: ResourceLifecycleState.validating,
  ),
  const ResourceLibraryItem(
    id: 'res_4',
    type: ResourceType.character,
    name: '半狼布莱泽',
    summary: '菈妮的从者与忠诚卫士。',
    updatedAt: '2026-09-20 18:00',
    status: ResourceDisplayStatus.optimizationFailed,
    isConsumable: false,
    lifecycleState: ResourceLifecycleState.failed,
  ),
];

/// Seeds one card per list fixture so the master/detail pane can resolve the
/// selected row. The list itself is still driven by the injected runtime.
MemorySettingCardRepository _seedCards() {
  final repository = MemorySettingCardRepository();
  for (final item in _testItems) {
    repository.cards[item.id] = SettingCard(
      id: item.id,
      kind: switch (item.type) {
        ResourceType.worldview => SettingCardKind.worldview,
        ResourceType.character => SettingCardKind.character,
        ResourceType.npc => SettingCardKind.npc,
      },
      name: item.name,
      summary: item.summary,
      content: item.isConsumable ? '设定卡正文' : '',
      mode: 'adventure',
      createdAt: item.updatedAt,
      updatedAt: item.updatedAt,
    );
  }
  return repository;
}

/// Current value of the detail page's name field (the card UI has no separate
/// detail title).
String? _detailName(WidgetTester tester) => tester
    .widget<AppTextField>(find.byKey(const Key('setting-card-name')))
    .controller
    ?.text;

Widget _buildTestApp({
  required ResourceLibraryRuntime runtime,
  SettingCardService? cardService,
  ThemeMode themeMode = ThemeMode.light,
  double textScaleFactor = 1.0,
}) {
  final service = cardService ?? SettingCardService(repository: _seedCards());
  return ProviderScope(
    overrides: [
      resourceLibraryRuntimeProvider.overrideWithValue(runtime),
      settingCardServiceProvider.overrideWithValue(service),
    ],
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: themeMode,
      home: Builder(
        builder: (context) {
          final mediaQuery = MediaQuery.of(context);
          return MediaQuery(
            data: mediaQuery.copyWith(
              textScaler: TextScaler.linear(textScaleFactor),
            ),
            child: const ResourceLibraryScreen(),
          );
        },
      ),
    ),
  );
}

void main() {
  group('Resource library visual polish', () {
    testWidgets('rows show a locale-aware timestamp, never the raw value',
        (tester) async {
      setViewport(tester, width: 1440, height: 900);
      final runtime = _MockResourceLibraryRuntime(items: _testItems);
      await tester.pumpWidget(_buildTestApp(runtime: runtime));
      await tester.pumpAndSettle();

      // Persisted ISO-like values must never reach the UI.
      expect(find.textContaining('2026-09-26 12:00'), findsNothing);
      expect(find.textContaining('2026-09-26T'), findsNothing);
      // The compact locale-aware rendering is shown instead.
      expect(find.textContaining('9\u670826\u65e5'), findsWidgets);
    });

    testWidgets('filters are quiet text tabs, not choice chips',
        (tester) async {
      setViewport(tester, width: 960, height: 800);
      final runtime = _MockResourceLibraryRuntime(items: _testItems);
      await tester.pumpWidget(_buildTestApp(runtime: runtime));
      await tester.pumpAndSettle();

      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(SegmentedButton<Object?>), findsNothing);
      // All / Worldview / Character / NPC / Character Status.
      expect(find.byType(WorkbenchTabButton), findsNWidgets(5));
      expect(
        find.byKey(const ValueKey('resource-filter-trackedState')),
        findsOneWidget,
      );
    });

    testWidgets('shows master/detail side by side at 960 px', (tester) async {
      setViewport(tester, width: 960, height: 800);
      final runtime = _MockResourceLibraryRuntime(items: _testItems);
      await tester.pumpWidget(_buildTestApp(runtime: runtime));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('resource-list')), findsOneWidget);
      expect(find.byType(SettingCardDetailPage), findsOneWidget);
      // The inline detail is the card editor for the auto-selected row.
      expect(_detailName(tester), _testItems.first.name);
      // The search control stays a compact single-line field.
      final searchBox =
          tester.getSize(find.byKey(const Key('resource-search-field')));
      expect(searchBox.height, lessThanOrEqualTo(40));
    });
  });

  group('ResourceLibraryScreen Phase 5 UX and Responsive Tests', () {
    for (final viewport in requiredUiViewports) {
      testWidgets(
        'renders cleanly at ${viewport.width}x${viewport.height} without RenderFlex overflow',
        (tester) async {
          setViewport(tester, width: viewport.width, height: viewport.height);
          final runtime = _MockResourceLibraryRuntime(items: _testItems);

          await tester.pumpWidget(_buildTestApp(runtime: runtime));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(
              find.byKey(const Key('resource-search-field')), findsOneWidget);
          expect(
              find.byKey(const Key('resource-status-filter')), findsOneWidget);
          expect(find.byKey(const Key('resource-sort-select')), findsOneWidget);
          expect(find.text('可用于冒险'), findsWidgets);
        },
      );
    }

    for (final width in [
      320.0,
      360.0,
      375.0,
      390.0,
      412.0,
      768.0,
      1024.0,
      1280.0,
      1440.0
    ]) {
      testWidgets('selects actual resource and returns at $width',
          (tester) async {
        setViewport(tester, width: width, height: 900);
        final runtime = _MockResourceLibraryRuntime(items: _testItems);
        await tester.pumpWidget(_buildTestApp(
            runtime: runtime, themeMode: ThemeMode.dark, textScaleFactor: 1.5));
        await tester.pumpAndSettle();
        final row = find.byKey(const ValueKey('resource-card-res_2'));
        final name = find.descendant(of: row, matching: find.text('魔女菈妮'));
        if (name.evaluate().isEmpty) {
          await tester.scrollUntilVisible(row, 150,
              scrollable: find.descendant(
                  of: find.byKey(const Key('resource-list')),
                  matching: find.byType(Scrollable)));
        }
        await tester.ensureVisible(
            find.descendant(of: row, matching: find.text('魔女菈妮')));
        await tester.tap(find.descendant(of: row, matching: find.text('魔女菈妮')));
        await tester.pumpAndSettle();
        expect(_detailName(tester), '魔女菈妮');
        final page = tester
            .widget<SettingCardDetailPage>(find.byType(SettingCardDetailPage));
        expect(page.embedded, width >= AppBreakpoints.libraryTriPaneMin);
        final navigator =
            Navigator.of(tester.element(find.byType(SettingCardDetailPage)));
        expect(navigator.canPop(), width < AppBreakpoints.libraryTriPaneMin);
        if (width < AppBreakpoints.libraryTriPaneMin) {
          await tester.tap(find.byTooltip(MaterialLocalizations.of(
                  tester.element(find.byType(SettingCardDetailPage)))
              .backButtonTooltip));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('resource-list')), findsOneWidget);
          await tester.scrollUntilVisible(
              find.byKey(const Key('resource-search-field')), -150,
              scrollable: find
                  .descendant(
                      of: find.byKey(const Key('resource-workspace')),
                      matching: find.byType(Scrollable))
                  .first);
          expect(
              find.byKey(const Key('resource-search-field')), findsOneWidget);
        } else {
          await tester.tap(find.byKey(const ValueKey('resource-filter-npc')));
          await tester.pumpAndSettle();
          expect(_detailName(tester), '铁拳亚历山大');
          expect(navigator.canPop(), isFalse);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('inline delete confirms mutation and keeps workspace',
        (tester) async {
      setViewport(tester, width: 1280, height: 900);
      final cards = _seedCards();
      final service = SettingCardService(repository: cards);
      await tester.pumpWidget(_buildTestApp(
        runtime: SettingCardLibraryRuntime(service: service),
        cardService: service,
      ));
      await tester.pumpAndSettle();

      // The wide layout auto-selects the first card into the inline editor.
      expect(_detailName(tester), _testItems.first.name);
      final remove = find.byKey(const Key('setting-card-delete'));
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      // Merely opening the confirmation must not delete the card.
      expect(cards.cards['res_1']!.isDeleted, isFalse);
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expect(cards.cards['res_1']!.isDeleted, isTrue);
      expect(find.byKey(const ValueKey('resource-card-res_1')), findsNothing);
      // The workspace falls back to the next card instead of leaving the editor.
      expect(_detailName(tester), '魔女菈妮');
      expect(
          Navigator.of(tester.element(find.byType(SettingCardDetailPage)))
              .canPop(),
          isFalse);
      expect(tester.takeException(), isNull);
      // Retire the transient feedback card and its dismiss timer.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets(
        'renders cleanly in dark theme and 2.0x font scaling at 320x568',
        (tester) async {
      setViewport(tester, width: 320, height: 568);
      final runtime = _MockResourceLibraryRuntime(items: _testItems);

      await tester.pumpWidget(
        _buildTestApp(
          runtime: runtime,
          themeMode: ThemeMode.dark,
          textScaleFactor: 2.0,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('resource-search-field')), findsOneWidget);
    });

    testWidgets('filters by search keyword', (tester) async {
      setViewport(tester, width: 390, height: 844);
      final runtime = _MockResourceLibraryRuntime(items: _testItems);

      await tester.pumpWidget(_buildTestApp(runtime: runtime));
      await tester.pumpAndSettle();

      expect(find.text('魔女菈妮'), findsOneWidget);
      expect(find.text('铁拳亚历山大'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('resource-search-field')),
        '菈妮',
      );
      await tester.pumpAndSettle();

      expect(find.text('魔女菈妮'), findsOneWidget);
      expect(find.text('铁拳亚历山大'), findsNothing);

      // Clear search
      await tester.enterText(
        find.byKey(const Key('resource-search-field')),
        '',
      );
      await tester.pumpAndSettle();
      expect(find.text('铁拳亚历山大'), findsOneWidget);
    });

    testWidgets('filters by resource type tabs', (tester) async {
      setViewport(tester, width: 390, height: 844);
      final runtime = _MockResourceLibraryRuntime(items: _testItems);

      await tester.pumpWidget(_buildTestApp(runtime: runtime));
      await tester.pumpAndSettle();

      // Tap '角色' filter
      await tester.tap(find.descendant(
        of: find.byKey(const Key('resource-filter')),
        matching: find.text('角色'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('魔女菈妮'), findsOneWidget);
      expect(find.text('半狼布莱泽'), findsOneWidget);
      expect(find.text('铁拳亚历山大'), findsNothing);

      // Tap 'NPC' filter
      await tester.tap(find.descendant(
        of: find.byKey(const Key('resource-filter')),
        matching: find.text('NPC'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('铁拳亚历山大'), findsOneWidget);
      expect(find.text('魔女菈妮'), findsNothing);

      // Tap '全部' filter
      await tester.tap(find.descendant(
        of: find.byKey(const Key('resource-filter')),
        matching: find.text('全部'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('魔女菈妮'), findsOneWidget);
      expect(find.text('铁拳亚历山大'), findsOneWidget);
    });

    testWidgets('filters by lifecycle status', (tester) async {
      setViewport(tester, width: 390, height: 844);
      final runtime = _MockResourceLibraryRuntime(items: _testItems);

      await tester.pumpWidget(_buildTestApp(runtime: runtime));
      await tester.pumpAndSettle();

      // Tap status dropdown
      await tester.tap(find.byKey(const Key('resource-status-filter')));
      await tester.pumpAndSettle();

      // Select '生成/处理中'
      await tester.tap(find.text('生成/处理中'));
      await tester.pumpAndSettle();

      expect(find.text('魔女菈妮'), findsOneWidget);
      expect(find.text('铁拳亚历山大'), findsOneWidget);
      expect(find.text('艾尔登法环世界观：交界地与黄金律法的历史渊源以及破碎战争的全景展开长标题'), findsNothing);
    });

    testWidgets('changes sorting options', (tester) async {
      setViewport(tester, width: 390, height: 844);
      final runtime = _MockResourceLibraryRuntime(items: _testItems);

      await tester.pumpWidget(_buildTestApp(runtime: runtime));
      await tester.pumpAndSettle();

      // Tap sort select
      await tester.tap(find.byKey(const Key('resource-sort-select')));
      await tester.pumpAndSettle();

      // Select name ascending
      await tester.tap(find.text('名称 (A-Z)'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('paginates resources correctly', (tester) async {
      setViewport(tester, width: 390, height: 844);
      // Generate 25 items so total pages = 3 (pageSize = 12)
      final manyItems = List.generate(
        25,
        (i) => ResourceLibraryItem(
          id: 'item_$i',
          type: ResourceType.character,
          name: '角色卡 #$i',
          summary: '这是角色卡 $i 的简短介绍。',
          updatedAt: '2026-09-26 10:${(30 - i).toString().padLeft(2, '0')}',
          status: ResourceDisplayStatus.ready,
          isConsumable: true,
          lifecycleState: ResourceLifecycleState.ready,
        ),
      );

      final runtime = _MockResourceLibraryRuntime(items: manyItems);
      await tester.pumpWidget(_buildTestApp(runtime: runtime));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('resource-page-info')), findsOneWidget);
      expect(find.text('角色卡 #0'), findsOneWidget);
      expect(find.text('角色卡 #1'), findsOneWidget);
      expect(find.text('角色卡 #12'), findsNothing);

      // Go to next page
      await tester.tap(find.byKey(const Key('resource-page-next')));
      await tester.pumpAndSettle();

      expect(find.text('角色卡 #12'), findsOneWidget);
      expect(find.text('角色卡 #0'), findsNothing);

      // Go back to previous page
      await tester.tap(find.byKey(const Key('resource-page-prev')));
      await tester.pumpAndSettle();

      expect(find.text('角色卡 #0'), findsOneWidget);
    });

    testWidgets('displays empty state when no resources match', (tester) async {
      setViewport(tester, width: 390, height: 844);
      final runtime = _MockResourceLibraryRuntime(items: const []);

      await tester.pumpWidget(_buildTestApp(runtime: runtime));
      await tester.pumpAndSettle();

      expect(find.byType(AppEmptyState), findsOneWidget);
      expect(find.text('还没有资源'), findsOneWidget);
    });

    testWidgets('displays error state and retries on load failure',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      final runtime = _MockResourceLibraryRuntime(throwError: true);

      await tester.pumpWidget(_buildTestApp(runtime: runtime));
      await tester.pumpAndSettle();

      expect(find.byType(AppErrorView), findsOneWidget);
      expect(find.text('资源库加载失败，请重试'), findsOneWidget);

      // Verify retry button exists and does not crash
      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('Workbench toolbar alignment', () {
    const toolbarHeight = 32.0;

    Rect control(WidgetTester tester, Key key) =>
        tester.getRect(find.byKey(key));

    double textCenterDy(WidgetTester tester, Key key) => tester
        .getRect(find
            .descendant(of: find.byKey(key), matching: find.byType(Text))
            .first)
        .center
        .dy;

    final tabKeys = <Key>[
      const ValueKey('resource-filter-all'),
      const ValueKey('resource-filter-worldview'),
      const ValueKey('resource-filter-character'),
      const ValueKey('resource-filter-npc'),
    ];

    testWidgets('tabs and toolbar selects share one vertical center at 1280',
        (tester) async {
      setViewport(tester, width: 1280, height: 900);
      await tester.pumpWidget(_buildTestApp(
          runtime: _MockResourceLibraryRuntime(items: _testItems)));
      await tester.pumpAndSettle();

      const statusKey = Key('resource-status-filter');
      const sortKey = Key('resource-sort-select');

      final rects = <Rect>[
        for (final key in tabKeys) control(tester, key),
        control(tester, statusKey),
        control(tester, sortKey),
      ];

      // Every control sits on the same horizontal text/visual center.
      final baseline = rects.first.center.dy;
      for (final rect in rects) {
        expect((rect.center.dy - baseline).abs(), lessThanOrEqualTo(0.5));
      }

      // All controls honour the shared toolbar control-height contract.
      for (final rect in rects) {
        expect(rect.height, toolbarHeight);
      }

      // The label is centered on the full control box, not pushed up by the
      // underline. Holds for both the selected (全部) and unselected tabs.
      for (final key in tabKeys) {
        final box = control(tester, key);
        expect((textCenterDy(tester, key) - box.center.dy).abs(),
            lessThanOrEqualTo(0.5));
      }

      // The select trigger text is likewise centered.
      for (final key in <Key>[statusKey, sortKey]) {
        final box = control(tester, key);
        expect((textCenterDy(tester, key) - box.center.dy).abs(),
            lessThanOrEqualTo(0.5));
      }

      expect(tester.takeException(), isNull);
    });

    testWidgets('selected and unselected tabs measure the same height',
        (tester) async {
      setViewport(tester, width: 1280, height: 900);
      await tester.pumpWidget(_buildTestApp(
          runtime: _MockResourceLibraryRuntime(items: _testItems)));
      await tester.pumpAndSettle();

      final selected = control(tester, tabKeys.first); // 全部 (default selected)
      final unselected = control(tester, tabKeys[1]); // 世界观
      expect(selected.height, unselected.height);
      expect(selected.height, toolbarHeight);
      expect(tester.takeException(), isNull);
    });

    testWidgets('selected tab keeps a bottom-anchored underline',
        (tester) async {
      setViewport(tester, width: 1280, height: 900);
      await tester.pumpWidget(_buildTestApp(
          runtime: _MockResourceLibraryRuntime(items: _testItems)));
      await tester.pumpAndSettle();

      Finder underlineIn(Key key) => find.descendant(
            of: find.byKey(key),
            matching: find.byKey(const Key('workbench-tab-underline')),
          );

      // Only the selected tab draws the underline.
      expect(underlineIn(tabKeys.first), findsOneWidget);
      expect(underlineIn(tabKeys[1]), findsNothing);

      final box = control(tester, tabKeys.first);
      final underline = tester.getRect(underlineIn(tabKeys.first));
      expect(underline.height, 2);
      expect(underline.width, 18);
      expect((underline.bottom - box.bottom).abs(), lessThanOrEqualTo(0.5));
      expect(tester.takeException(), isNull);
    });

    for (final width in const <double>[320, 375, 600, 960, 1280, 1440]) {
      testWidgets('all toolbar controls keep a 32px box at ${width}px',
          (tester) async {
        setViewport(tester, width: width, height: 900);
        await tester.pumpWidget(_buildTestApp(
            runtime: _MockResourceLibraryRuntime(items: _testItems)));
        await tester.pumpAndSettle();

        final keys = <Key>[
          ...tabKeys,
          const Key('resource-status-filter'),
          const Key('resource-sort-select'),
        ];
        for (final key in keys) {
          expect(control(tester, key).height, toolbarHeight,
              reason: 'control $key height at ${width}px');
        }
        expect(tester.takeException(), isNull);
      });
    }

    for (final scale in const <double>[1.0, 1.5, 2.0]) {
      testWidgets('toolbar stays aligned at text scale $scale', (tester) async {
        setViewport(tester, width: 1280, height: 900);
        await tester.pumpWidget(_buildTestApp(
            runtime: _MockResourceLibraryRuntime(items: _testItems),
            textScaleFactor: scale));
        await tester.pumpAndSettle();

        final baseline = control(tester, tabKeys.first).center.dy;
        const statusKey = Key('resource-status-filter');
        expect((control(tester, statusKey).center.dy - baseline).abs(),
            lessThanOrEqualTo(0.5));
        expect(control(tester, statusKey).height, toolbarHeight);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
