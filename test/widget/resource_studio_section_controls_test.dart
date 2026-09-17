import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/section_control.dart';
import 'package:lt_dialogue/features/resource_studio/domain/models/section_control_view_state.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/pages/resource_studio_page.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/widgets/resource_studio_section_controls.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';

import '../helpers/responsive_test_helper.dart';
import '../helpers/resource_studio_fakes.dart';
import '../helpers/section_control_fakes.dart';

const _longTitle = '第一章：一个非常长的章节标题用于验证窄屏换行与截断策略是否正确';

SectionControlEntry _entry({
  String id = 'sec_1',
  String title = _longTitle,
  int orderIndex = 0,
  SectionGenerationState generation = SectionGenerationState.completed,
  SectionValidationState validation = SectionValidationState.unvalidated,
  String validationMessage = '',
  int partCount = 1,
  bool hasGenerationTasks = true,
  String content = '正文',
}) {
  return SectionControlEntry(
    id: SectionId(id),
    resourceId: const ResourceId('res_1'),
    title: title,
    orderIndex: orderIndex,
    generationState: generation,
    validationState: validation,
    validationMessage: validationMessage,
    content: content,
    partCount: partCount,
    hasGenerationTasks: hasGenerationTasks,
    updatedAt: DateTime(2026, 9, 17, 12, 30),
    updatedAtToken: 'token-$id',
  );
}

SectionControlViewState _viewState({
  List<SectionControlEntry>? entries,
  bool hasMore = false,
  SectionControlViewStatus status = SectionControlViewStatus.ready,
  String errorMessage = '',
  String lastMessage = '',
  Set<String> busy = const <String>{},
}) {
  final resolved = entries ?? [_entry()];
  return SectionControlViewState(
    status: status,
    resourceId: const ResourceId('res_1'),
    entries: resolved,
    totalCount: hasMore ? resolved.length + 5 : resolved.length,
    hasMore: hasMore,
    busySectionIds: busy,
    errorMessage: errorMessage,
    lastMessage: lastMessage,
  );
}

Future<void> _pumpPanel(
  WidgetTester tester,
  SectionControlViewState state, {
  void Function(SectionControlEntry entry)? onValidate,
  void Function(SectionControlEntry entry)? onRegenerate,
  void Function(SectionControlEntry entry, String title)? onRename,
  void Function(SectionControlEntry entry)? onDelete,
  void Function(SectionControlEntry entry, int targetIndex)? onMove,
  VoidCallback? onCreate,
  VoidCallback? onLoadMore,
  VoidCallback? onRefresh,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ResourceStudioSectionControls(
            state: state,
            onRefresh: onRefresh ?? () {},
            onLoadMore: onLoadMore ?? () {},
            onCreate: onCreate ?? () {},
            onRename: onRename ?? (_, __) {},
            onDelete: onDelete ?? (_) {},
            onMove: onMove ?? (_, __) {},
            onValidate: onValidate ?? (_) {},
            onRegenerate: onRegenerate ?? (_) {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('ResourceStudioSectionControls responsiveness', () {
    for (final viewport in requiredUiViewports) {
      testWidgets(
        'renders states and actions without overflow at ${viewport.width}x'
        '${viewport.height}',
        (tester) async {
          setViewport(
            tester,
            width: viewport.width,
            height: viewport.height,
          );

          await _pumpPanel(
            tester,
            _viewState(
              entries: [
                _entry(),
                _entry(
                  id: 'sec_2',
                  title: '第二章',
                  orderIndex: 1,
                  generation: SectionGenerationState.failed,
                  validation: SectionValidationState.invalid,
                  validationMessage: '开场 尚未生成正文；第二段 长度 3200 超出单 Part 上限 3000',
                ),
                _entry(
                  id: 'sec_3',
                  title: '第三章：内容被 AI 重新生成后需要重新验证',
                  orderIndex: 2,
                  validation: SectionValidationState.stale,
                ),
              ],
              hasMore: true,
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('章节控制'), findsOneWidget);
          expect(find.text('待生成'), findsNothing);
          expect(find.text('生成失败'), findsOneWidget);
          expect(find.text('验证未通过'), findsOneWidget);
          expect(find.text('内容已变更，需重新验证'), findsOneWidget);
          expect(find.text('验证'), findsNWidgets(3));
          expect(find.textContaining('加载更多'), findsOneWidget);
        },
      );
    }

    testWidgets('handles an empty section list', (tester) async {
      setViewport(tester, width: 320, height: 568);
      await _pumpPanel(
        tester,
        _viewState(
          entries: const <SectionControlEntry>[],
          status: SectionControlViewStatus.ready,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('该资源还没有章节。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows error and result messages', (tester) async {
      setViewport(tester, width: 360, height: 640);
      await _pumpPanel(
        tester,
        _viewState(
          status: SectionControlViewStatus.failed,
          errorMessage: 'Section 已被并发修改，写入被拒绝',
          lastMessage: '「第一章」校验通过',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('已被并发修改'), findsOneWidget);
      expect(find.textContaining('校验通过'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('locks actions for the busy section only', (tester) async {
      setViewport(tester, width: 390, height: 844);
      await _pumpPanel(
        tester,
        _viewState(
          entries: [_entry(id: 'sec_1'), _entry(id: 'sec_2', orderIndex: 1)],
          busy: const <String>{'sec_1'},
        ),
      );
      // A busy row shows an indeterminate spinner, so pumpAndSettle would never
      // reach an idle frame; one pump is enough to lay the row out.
      await tester.pump();

      final validateButtons =
          tester.widgetList<TextButton>(find.widgetWithText(TextButton, '验证'));
      final enabled =
          validateButtons.where((button) => button.onPressed != null);
      expect(enabled, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('invokes the validate and regenerate callbacks',
        (tester) async {
      setViewport(tester, width: 412, height: 915);
      SectionControlEntry? validated;
      SectionControlEntry? regenerated;
      await _pumpPanel(
        tester,
        _viewState(),
        onValidate: (entry) => validated = entry,
        onRegenerate: (entry) => regenerated = entry,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, '验证'));
      await tester.pumpAndSettle();
      expect(validated?.id, const SectionId('sec_1'));

      await tester.tap(find.widgetWithText(TextButton, '重新生成'));
      await tester.pumpAndSettle();
      expect(regenerated?.id, const SectionId('sec_1'));
    });

    testWidgets('routes rename, move and delete through the overflow menu',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      SectionControlEntry? renamed;
      String? newTitle;
      SectionControlEntry? deleted;
      SectionControlEntry? moved;
      int? movedTo;
      await _pumpPanel(
        tester,
        _viewState(
          entries: [_entry(), _entry(id: 'sec_2', orderIndex: 1)],
        ),
        onRename: (entry, title) {
          renamed = entry;
          newTitle = title;
        },
        onDelete: (entry) => deleted = entry,
        onMove: (entry, target) {
          moved = entry;
          movedTo = target;
        },
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('更多操作').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('重命名'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '新的章节标题');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(renamed?.id, const SectionId('sec_1'));
      expect(newTitle, '新的章节标题');

      await tester.tap(find.byTooltip('更多操作').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('上移'));
      await tester.pumpAndSettle();
      expect(moved?.id, const SectionId('sec_2'));
      expect(movedTo, 0);

      await tester.tap(find.byTooltip('更多操作').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.textContaining('确定删除'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expect(deleted?.id, const SectionId('sec_1'));
    });
  });

  group('ResourceStudioSectionControls generation gating', () {
    testWidgets('disables generate for a manual section that has Parts',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      SectionControlEntry? regenerated;
      await _pumpPanel(
        tester,
        _viewState(
          entries: [
            _entry(
              id: 'sec_manual',
              generation: SectionGenerationState.generated,
              partCount: 3,
              hasGenerationTasks: false,
            ),
          ],
        ),
        onRegenerate: (entry) => regenerated = entry,
      );
      await tester.pumpAndSettle();

      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '生成'),
      );
      expect(
        button.onPressed,
        isNull,
        reason: '没有生成任务的章节不得显示可用的生成操作',
      );
      expect(
        find.byTooltip('该章节没有生成任务（非 AI 蓝图创建），无法生成'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(TextButton, '生成'));
      await tester.pump();
      expect(regenerated, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('enables regenerate for a task-backed completed section',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      SectionControlEntry? regenerated;
      await _pumpPanel(
        tester,
        _viewState(
          entries: [
            _entry(
              id: 'sec_generated',
              generation: SectionGenerationState.completed,
              partCount: 2,
              hasGenerationTasks: true,
            ),
          ],
        ),
        onRegenerate: (entry) => regenerated = entry,
      );
      await tester.pumpAndSettle();

      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '重新生成'),
      );
      expect(button.onPressed, isNotNull);

      await tester.tap(find.widgetWithText(TextButton, '重新生成'));
      await tester.pumpAndSettle();
      expect(regenerated?.id, const SectionId('sec_generated'));
    });

    testWidgets('disables generate for an empty section', (tester) async {
      setViewport(tester, width: 320, height: 568);
      await _pumpPanel(
        tester,
        _viewState(
          entries: [
            _entry(
              id: 'sec_empty',
              generation: SectionGenerationState.pending,
              partCount: 0,
              hasGenerationTasks: false,
              content: '',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '生成'),
      );
      expect(button.onPressed, isNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('ResourceStudioPage section control integration', () {
    late FakeResourceStudioRuntime studioRuntime;
    late FakeSectionControlRuntime sectionRuntime;
    late ResourceTree tree;

    setUp(() {
      tree = buildStudioTestTree();
      studioRuntime = FakeResourceStudioRuntime(
        tree: tree,
        session: buildStudioTestSession(tree),
      );
      sectionRuntime = FakeSectionControlRuntime(
        entries: [
          _entry(
            id: tree.sections.single.id.value,
            title: tree.sections.single.title,
          ),
        ],
      );
    });

    tearDown(() {
      studioRuntime.dispose();
      sectionRuntime.dispose();
    });

    testWidgets('renders the section panel inside the Studio', (tester) async {
      setViewport(tester, width: 320, height: 568);
      await tester.pumpWidget(_app(studioRuntime, sectionRuntime));
      await _pumpStudio(tester);

      expect(find.text('章节控制'), findsOneWidget);
      expect(find.text(tree.sections.single.title), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('validates the selected section through the runtime',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      await tester.pumpWidget(_app(studioRuntime, sectionRuntime));
      await _pumpStudio(tester);

      await tester.tap(find.widgetWithText(TextButton, '验证'));
      await _pumpStudio(tester);

      expect(sectionRuntime.validateCalls, [tree.sections.single.id.value]);
    });

    testWidgets('regenerates a section that has generation tasks',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      await tester.pumpWidget(_app(studioRuntime, sectionRuntime));
      await _pumpStudio(tester);

      await tester.tap(find.widgetWithText(TextButton, '重新生成'));
      await _pumpStudio(tester);

      expect(
        sectionRuntime.regenerateCalls,
        ['${tree.sections.single.id.value}:regenerate'],
      );
    });

    testWidgets('creates a section through the dialog', (tester) async {
      setViewport(tester, width: 412, height: 915);
      await tester.pumpWidget(_app(studioRuntime, sectionRuntime));
      await _pumpStudio(tester);

      await tester.tap(find.text('新增章节'));
      await _pumpStudio(tester);
      await tester.enterText(find.byType(TextField), '新增的章节');
      await tester.tap(find.widgetWithText(FilledButton, '创建'));
      await _pumpStudio(tester);

      expect(sectionRuntime.createCalls, ['新增的章节']);
      expect(find.text('新增的章节'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

/// Pumps the Studio with bounded durations.
///
/// The panel intentionally shows an indeterminate spinner while loading, so
/// `pumpAndSettle` would never reach an idle frame; explicit pumps advance the
/// pending microtasks and route animations instead.
Future<void> _pumpStudio(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 400));
}

Widget _app(
  FakeResourceStudioRuntime studioRuntime,
  FakeSectionControlRuntime sectionRuntime,
) {
  return ProviderScope(
    overrides: [
      resourceStudioRuntimeProvider.overrideWithValue(studioRuntime),
      sectionControlRuntimeProvider.overrideWithValue(sectionRuntime),
    ],
    child: const MaterialApp(
      home: ResourceStudioPage(sessionId: 'gen_studio_test'),
    ),
  );
}
