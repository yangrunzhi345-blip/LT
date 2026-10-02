import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/resource_lifecycle_projection.dart';
import 'package:lt_dialogue/controllers/resource_crud_controller.dart';
import 'package:lt_dialogue/core/widgets/app_empty_state.dart';
import 'package:lt_dialogue/core/widgets/app_error_view.dart';
import 'package:lt_dialogue/core/widgets/workbench_chrome.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/features/resource_library/application/use_cases/resource_library_runtime.dart';
import 'package:lt_dialogue/features/resource_library/domain/models/resource_library_view_state.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_library_screen.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';

import '../helpers/responsive_test_helper.dart';
import '../helpers/resource_studio_fakes.dart';
import '../helpers/section_control_fakes.dart';
import '../helpers/resource_capacity_fakes.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/pages/resource_studio_page.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_library_detail_page.dart';

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

  @override
  Future<ResourceOperationResult> moveToTrash({
    required ResourceLibraryItem item,
    required ResourceLibraryMode mode,
  }) async {
    items = items.where((candidate) => candidate.id != item.id).toList();
    return const ResourceOperationResult.success(message: '已移入回收站');
  }

  @override
  Future<String> createManual({
    required ResourceType type,
    required String name,
    required String summary,
    required ResourceLibraryMode mode,
  }) async =>
      'item_manual_1';
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
    isStudioAvailable: true,
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
    isStudioAvailable: true,
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
    isStudioAvailable: true,
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
    isStudioAvailable: true,
    isConsumable: false,
    lifecycleState: ResourceLifecycleState.failed,
  ),
];

Widget _buildTestApp({
  required ResourceLibraryRuntime runtime,
  ThemeMode themeMode = ThemeMode.light,
  double textScaleFactor = 1.0,
}) {
  final tree = buildStudioTestTree();
  final studio = FakeResourceStudioRuntime(
      tree: tree, session: buildStudioTestSession(tree));
  addTearDown(studio.eventsController.close);
  return ProviderScope(
    overrides: [
      resourceLibraryRuntimeProvider.overrideWithValue(runtime),
      resourceStudioRuntimeProvider.overrideWithValue(studio),
      sectionControlRuntimeProvider
          .overrideWithValue(FakeSectionControlRuntime()),
      resourceCapacityRuntimeProvider
          .overrideWithValue(FakeResourceCapacityRuntime()),
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
      expect(find.byType(WorkbenchTabButton), findsNWidgets(4));
    });

    testWidgets('shows master/detail side by side at 960 px', (tester) async {
      setViewport(tester, width: 960, height: 800);
      final runtime = _MockResourceLibraryRuntime(items: _testItems);
      await tester.pumpWidget(_buildTestApp(runtime: runtime));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('resource-list')), findsOneWidget);
      expect(find.byType(ResourceLibraryDetailPage), findsOneWidget);
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
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
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
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
            tester
                .widget<Text>(find.byKey(const Key('resource-detail-title')))
                .data,
            '魔女菈妮');
        final page = tester.widget<ResourceLibraryDetailPage>(
            find.byType(ResourceLibraryDetailPage));
        expect(page.embedded, width >= 1000);
        final navigator = Navigator.of(
            tester.element(find.byType(ResourceLibraryDetailPage)));
        expect(navigator.canPop(), width < 1000);
        if (width < 1000) {
          await tester.tap(find.byTooltip(MaterialLocalizations.of(
                  tester.element(find.byType(ResourceLibraryDetailPage)))
              .backButtonTooltip));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
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
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(
              tester
                  .widget<Text>(find.byKey(const Key('resource-detail-title')))
                  .data,
              '铁拳亚历山大');
          expect(navigator.canPop(), isFalse);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
        'desktop Studio stays in library and preserves search on return',
        (tester) async {
      setViewport(tester, width: 1280, height: 900);
      final tree = buildStudioTestTree();
      final runtime = _MockResourceLibraryRuntime(items: [
        ResourceLibraryItem(
          id: tree.resource.id.value,
          type: tree.resource.type,
          name: tree.resource.name,
          summary: tree.resource.summary,
          updatedAt: '2026-10-01',
          status: ResourceDisplayStatus.ready,
          isStudioAvailable: true,
          isConsumable: true,
        )
      ]);
      await tester.pumpWidget(_buildTestApp(runtime: runtime));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('resource-search-field')), '测试标题');
      await tester.pumpAndSettle();
      final open = find.byKey(const Key('resource-open-studio-button'));
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pumpAndSettle();
      final page =
          tester.widget<ResourceStudioPage>(find.byType(ResourceStudioPage));
      expect(page.embedded, isTrue);
      expect(
          Navigator.of(tester.element(find.byType(ResourceStudioPage)))
              .canPop(),
          isFalse);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.byType(ResourceStudioPage), findsNothing);
      final field = tester
          .widget<TextField>(find.byKey(const Key('resource-search-field')));
      expect(field.controller!.text, '测试标题');
      expect(
          tester
              .widget<Text>(find.byKey(const Key('resource-detail-title')))
              .data,
          tree.resource.name);
      expect(tester.takeException(), isNull);
    });

    testWidgets('inline trash confirms mutation and keeps workspace',
        (tester) async {
      setViewport(tester, width: 1280, height: 900);
      final runtime = _MockResourceLibraryRuntime(items: _testItems);
      await tester.pumpWidget(_buildTestApp(runtime: runtime));
      await tester.pumpAndSettle();
      final remove = find.byKey(const Key('resource-move-to-trash-button'));
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      // Merely opening the confirmation must not mutate the resource list.
      expect(runtime.items.length, 4);
      await tester.tap(find.widgetWithText(FilledButton, '移入回收站'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(runtime.items.map((item) => item.id), isNot(contains('res_1')));
      expect(find.byKey(const ValueKey('resource-card-res_1')), findsNothing);
      expect(
          tester
              .widget<Text>(find.byKey(const Key('resource-detail-title')))
              .data,
          '魔女菈妮');
      expect(
          Navigator.of(tester.element(find.byType(ResourceLibraryDetailPage)))
              .canPop(),
          isFalse);
      expect(tester.takeException(), isNull);
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
          isStudioAvailable: true,
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
