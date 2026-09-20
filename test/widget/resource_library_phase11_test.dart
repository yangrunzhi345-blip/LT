import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/controllers/resource_crud_controller.dart';
import 'package:lt_dialogue/features/resource_library/application/use_cases/resource_library_runtime.dart';
import 'package:lt_dialogue/features/resource_library/domain/models/resource_library_view_state.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_library_detail_page.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_library_screen.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';

import '../helpers/responsive_test_helper.dart';

final class _LibraryRuntime implements ResourceLibraryRuntime {
  const _LibraryRuntime(this.items);

  final List<ResourceLibraryItem> items;

  @override
  Future<List<ResourceLibraryItem>> load(ResourceLibraryMode mode) async =>
      items;

  @override
  Future<ResourceOperationResult> moveToTrash({
    required ResourceLibraryItem item,
    required ResourceLibraryMode mode,
  }) async =>
      const ResourceOperationResult.success(message: '已移入回收站');

  @override
  Future<String> createManual({
    required ResourceType type,
    required String name,
    required String summary,
    required ResourceLibraryMode mode,
  }) async =>
      items.first.id;
}

final class _RecordingLibraryRuntime implements ResourceLibraryRuntime {
  _RecordingLibraryRuntime({this.shouldFail = false});

  final bool shouldFail;
  final List<ResourceLibraryItem> items = <ResourceLibraryItem>[..._items];
  int moveToTrashCalls = 0;

  @override
  Future<List<ResourceLibraryItem>> load(ResourceLibraryMode mode) async =>
      List<ResourceLibraryItem>.unmodifiable(items);

  @override
  Future<ResourceOperationResult> moveToTrash({
    required ResourceLibraryItem item,
    required ResourceLibraryMode mode,
  }) async {
    moveToTrashCalls++;
    if (shouldFail) return const ResourceOperationResult.failure('写入失败');
    items.removeWhere((candidate) => candidate.id == item.id);
    return const ResourceOperationResult.success(message: '已移入回收站');
  }

  @override
  Future<String> createManual({
    required ResourceType type,
    required String name,
    required String summary,
    required ResourceLibraryMode mode,
  }) async =>
      items.first.id;
}

const _longName =
    '一个用于验证长中文和 Long English Resource Name Without Internal Identifiers 的资源标题';

const _items = <ResourceLibraryItem>[
  ResourceLibraryItem(
    id: 'resource_world',
    type: ResourceType.worldview,
    name: _longName,
    summary: '很长的简介，用来验证列表在窄屏和放大字体下仍然可读且不会产生横向溢出。',
    updatedAt: '2026-09-18',
    status: ResourceDisplayStatus.ready,
    isStudioAvailable: true,
  ),
  ResourceLibraryItem(
    id: 'resource_character',
    type: ResourceType.character,
    name: '林舟',
    summary: '守夜人',
    updatedAt: '2026-09-17',
    status: ResourceDisplayStatus.optimizing,
    isStudioAvailable: true,
  ),
];

void main() {
  group('ResourceLibraryScreen Phase 11', () {
    for (final viewport in requiredUiViewports) {
      testWidgets(
        'should render at ${viewport.width}x${viewport.height} without overflow',
        (tester) async {
          setViewport(
            tester,
            width: viewport.width,
            height: viewport.height,
          );
          await _pumpLibrary(tester);

          expect(tester.takeException(), isNull);
          expect(
              find.byKey(const Key('resource-create-button')), findsOneWidget);
          expect(
              find.byKey(const Key('resource-search-field')), findsOneWidget);
          expect(find.text('已准备完成'), findsOneWidget);
          expect(find.text('正在优化'), findsOneWidget);
        },
      );
    }

    testWidgets('should expose only AI and manual creation choices',
        (tester) async {
      setViewport(tester, width: 320, height: 568);
      await _pumpLibrary(tester);
      await tester.tap(find.byKey(const Key('resource-create-button')));
      await tester.pumpAndSettle();

      expect(find.text('AI 创建'), findsOneWidget);
      expect(find.text('手动创建'), findsOneWidget);
      expect(find.textContaining('导入'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('should search and filter resources', (tester) async {
      setViewport(tester, width: 390, height: 844);
      await _pumpLibrary(tester);

      await tester.enterText(
        find.byKey(const Key('resource-search-field')),
        '守夜人',
      );
      await tester.pump();
      expect(find.text('林舟'), findsOneWidget);
      expect(find.text(_longName), findsNothing);

      await tester.enterText(
        find.byKey(const Key('resource-search-field')),
        '',
      );
      await tester.tap(find.text('世界观'));
      await tester.pump();
      expect(find.text(_longName), findsOneWidget);
      expect(find.text('林舟'), findsNothing);
    });

    testWidgets('should navigate from a card to details', (tester) async {
      setViewport(tester, width: 390, height: 844);
      await _pumpLibrary(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('resource-card-resource_world')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ResourceLibraryDetailPage), findsOneWidget);
      expect(find.text('进入创作工作台'), findsOneWidget);
      expect(find.text('移入回收站'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final viewport in requiredUiViewports.take(4)) {
      testWidgets(
        'details actions fit at ${viewport.width}x${viewport.height}',
        (tester) async {
          setViewport(
            tester,
            width: viewport.width,
            height: viewport.height,
          );
          await _pumpLibrary(tester);
          await tester.tap(
            find.byKey(
              const ValueKey<String>('resource-card-resource_world'),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            find.byKey(const Key('resource-move-to-trash-button')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('cancel keeps the resource and does not invoke delete',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      final runtime = _RecordingLibraryRuntime();
      await _pumpLibrary(tester, runtime: runtime);
      await tester.tap(
        find.byKey(const ValueKey<String>('resource-card-resource_world')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('resource-move-to-trash-button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('将「$_longName」移入回收站？之后可在回收站中恢复。'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();

      expect(runtime.moveToTrashCalls, 0);
      expect(find.byType(ResourceLibraryDetailPage), findsOneWidget);
    });

    testWidgets('confirmed delete returns and refreshes the list',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      final runtime = _RecordingLibraryRuntime();
      await _pumpLibrary(tester, runtime: runtime);
      await tester.tap(
        find.byKey(const ValueKey<String>('resource-card-resource_world')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('resource-move-to-trash-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '移入回收站'));
      await tester.pumpAndSettle();

      expect(runtime.moveToTrashCalls, 1);
      expect(find.byType(ResourceLibraryDetailPage), findsNothing);
      expect(find.text(_longName), findsNothing);
      expect(find.text('已移入回收站'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('failed delete stays on details and reports an error',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      final runtime = _RecordingLibraryRuntime(shouldFail: true);
      await _pumpLibrary(tester, runtime: runtime);
      await tester.tap(
        find.byKey(const ValueKey<String>('resource-card-resource_world')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('resource-move-to-trash-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '移入回收站'));
      await tester.pumpAndSettle();

      expect(runtime.moveToTrashCalls, 1);
      expect(find.byType(ResourceLibraryDetailPage), findsOneWidget);
      expect(find.text('移入回收站失败，请重试'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('should survive large text and keyboard in creation flow',
        (tester) async {
      setViewport(tester, width: 320, height: 568);
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      addTearDown(tester.view.resetViewInsets);
      await _pumpLibrary(tester, textScale: 1.6);
      await tester.tap(find.byKey(const Key('resource-create-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('手动创建'));
      await tester.pumpAndSettle();

      expect(find.text('手动创建'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('should not leak implementation terminology', (tester) async {
      setViewport(tester, width: 390, height: 844);
      await _pumpLibrary(tester);
      final forbidden = <String>[
        'Part',
        'revision ID',
        'JSON',
        'absolute limit',
        'compression job',
        'assembly revision',
      ];
      for (final term in forbidden) {
        expect(find.textContaining(term), findsNothing);
      }
    });
  });
}

Future<void> _pumpLibrary(
  WidgetTester tester, {
  double textScale = 1,
  ResourceLibraryRuntime runtime = const _LibraryRuntime(_items),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        resourceLibraryRuntimeProvider.overrideWithValue(
          runtime,
        ),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: const ResourceLibraryScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
