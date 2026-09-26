import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/resource_lifecycle_projection.dart';
import 'package:lt_dialogue/controllers/resource_crud_controller.dart';
import 'package:lt_dialogue/core/widgets/app_empty_state.dart';
import 'package:lt_dialogue/core/widgets/app_error_view.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/features/resource_library/application/use_cases/resource_library_runtime.dart';
import 'package:lt_dialogue/features/resource_library/domain/models/resource_library_view_state.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_library_screen.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';

import '../helpers/responsive_test_helper.dart';

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
  return ProviderScope(
    overrides: [
      resourceLibraryRuntimeProvider.overrideWithValue(runtime),
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
}
