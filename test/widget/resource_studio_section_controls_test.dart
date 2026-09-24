import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/application/resources/section_control_service.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/section_control.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/controllers/section_control_controller.dart';
import 'package:lt_dialogue/features/resource_studio/domain/models/section_control_view_state.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/pages/resource_studio_page.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/widgets/resource_studio_section_controls.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';

import '../helpers/resource_capacity_fakes.dart';
import '../helpers/responsive_test_helper.dart';
import '../helpers/resource_studio_fakes.dart';
import '../helpers/section_control_fakes.dart';
import '../helpers/studio_scroll_helper.dart';

const _longTitle = '第一章：一个非常长的章节标题用于验证窄屏换行与截断策略是否正确';

SectionControlEntry _entry({
  String id = 'sec_1',
  String title = _longTitle,
  int orderIndex = 0,
  // The default is a task-backed section that can still run: a fully completed
  // section is deliberately gated off until Phase 9 provides a reset/revision
  // (Phase 7 D2, option B), and the generic fixtures must exercise the
  // supported path.
  SectionGenerationState generation = SectionGenerationState.failed,
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
  SectionControlNotice? lastNotice,
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
    lastNotice: lastNotice,
  );
}

Future<void> _pumpPanel(
  WidgetTester tester,
  SectionControlViewState state, {
  bool expand = true,
  void Function(SectionControlEntry entry)? onValidate,
  void Function(SectionControlEntry entry)? onRegenerate,
  void Function(SectionControlEntry entry, String title)? onRename,
  void Function(SectionControlEntry entry)? onDelete,
  void Function(SectionControlEntry entry, int targetIndex)? onMove,
  VoidCallback? onCreate,
  VoidCallback? onLoadMore,
  VoidCallback? onRefresh,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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
  if (expand) {
    await tester.pump();
    await tester.tap(find.text('章节控制'));
  }
}

void main() {
  testWidgets('starts collapsed and toggles section controls', (tester) async {
    setViewport(tester, width: 390, height: 844);
    await _pumpPanel(tester, _viewState(), expand: false);
    await tester.pumpAndSettle();

    expect(find.text('章节控制'), findsOneWidget);
    expect(find.text('验证'), findsNothing);

    await tester.tap(find.text('章节控制'));
    await tester.pumpAndSettle();
    expect(find.text('验证'), findsOneWidget);

    await tester.tap(find.text('章节控制'));
    await tester.pumpAndSettle();
    expect(find.text('验证'), findsNothing);
  });

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
                _entry(generation: SectionGenerationState.completed),
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
                  generation: SectionGenerationState.completed,
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
          expect(find.text('优化失败'), findsNWidgets(2));
          expect(find.text('建议优化'), findsNWidgets(2));
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
          lastNotice: const SectionControlNotice(
            type: SectionControlNoticeType.validationPassed,
            title: '第一章',
          ),
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

    testWidgets('enables regenerate for a task-backed section that can run',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      SectionControlEntry? regenerated;
      await _pumpPanel(
        tester,
        _viewState(
          entries: [
            _entry(
              id: 'sec_generated',
              generation: SectionGenerationState.failed,
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

    test('uses Chinese terminology in regenerate success messages', () async {
      final runtime = FakeSectionControlRuntime(entries: [
        _entry(
          id: 'sec_message',
          partCount: 2,
          hasGenerationTasks: true,
        ),
      ]);
      final controller = SectionControlController(runtime: runtime);
      addTearDown(controller.dispose);
      await controller.load(const ResourceId('res_1'));
      await controller.regenerateSection(controller.state.entries.single);

      expect(
        controller.state.lastNotice?.type,
        SectionControlNoticeType.regenerated,
      );
      expect(controller.state.lastNotice?.completedParts, 2);
      expect(controller.state.lastNotice?.totalParts, 2);
    });

    test('maps internal terminology in regenerate failure messages', () async {
      final runtime = FakeSectionControlRuntime(entries: [
        _entry(
          id: 'sec_failure_message',
          partCount: 1,
          hasGenerationTasks: true,
        ),
      ]);
      runtime.nextRegenerationOutcome = const SectionGenerationOutcome(
        sectionId: SectionId('sec_failure_message'),
        generationId: 'generation_failure',
        partCount: 1,
        completedPartCount: 0,
        characterCount: 0,
        success: false,
        errorMessage: 'Part JSON compression job 未完成',
      );
      final controller = SectionControlController(runtime: runtime);
      addTearDown(controller.dispose);
      await controller.load(const ResourceId('res_1'));

      await controller.regenerateSection(controller.state.entries.single);

      final notice = controller.state.lastNotice!;
      expect(notice.type, SectionControlNoticeType.generationFailed);
      expect(notice.detail, isNot(contains('Part')));
      expect(notice.detail, isNot(contains('JSON')));
      expect(notice.detail, isNot(contains('compression job')));
    });

    testWidgets(
        'offers regenerate for a fully completed section now that Phase 9 '
        'reopens the tasks behind a revision boundary', (tester) async {
      setViewport(tester, width: 390, height: 844);
      SectionControlEntry? regenerated;
      await _pumpPanel(
        tester,
        _viewState(
          entries: [
            _entry(
              id: 'sec_completed',
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
      expect(
        button.onPressed,
        isNotNull,
        reason: 'Phase 9 records the pre-regeneration snapshot and reopens the '
            'completed tasks, so the action is available again',
      );
      expect(
        find.byTooltip('重新运行该章节的生成任务；当前内容会先记录为历史版本，可随时恢复'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(TextButton, '重新生成'));
      await tester.pump();
      expect(regenerated?.id, const SectionId('sec_completed'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('disables regenerate while a run is in flight', (tester) async {
      setViewport(tester, width: 390, height: 844);
      await _pumpPanel(
        tester,
        _viewState(
          entries: [
            _entry(
              id: 'sec_running',
              generation: SectionGenerationState.generating,
              partCount: 2,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '重新生成'),
      );
      expect(button.onPressed, isNull);
      expect(tester.takeException(), isNull);
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
            // A failed section is regenerable; a fully completed one is
            // deliberately gated off until Phase 9 provides a reset/revision
            // (Phase 7 D2, option B).
            generation: SectionGenerationState.failed,
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
      final sectionControlsTitle = find.text('章节控制');
      await tester.ensureVisible(sectionControlsTitle);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(sectionControlsTitle);
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
      final sectionControlsTitle = find.text('章节控制');
      await tester.ensureVisible(sectionControlsTitle);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(sectionControlsTitle);
      await _pumpStudio(tester);

      // The page scrolls, and the capacity panel sits above the section
      // controls, so the target must be brought into view before tapping.
      final validateButton = find.widgetWithText(TextButton, '验证');
      await tester.ensureVisible(validateButton);
      await _pumpStudio(tester);
      await tester.tap(validateButton);
      await _pumpStudio(tester);

      expect(sectionRuntime.validateCalls, [tree.sections.single.id.value]);
    });

    testWidgets('regenerates a section that has generation tasks',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      await tester.pumpWidget(_app(studioRuntime, sectionRuntime));
      await _pumpStudio(tester);
      final sectionControlsTitle = find.text('章节控制');
      await tester.ensureVisible(sectionControlsTitle);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(sectionControlsTitle);
      await _pumpStudio(tester);

      final regenerateButton = find.widgetWithText(TextButton, '重新生成');
      await tester.ensureVisible(regenerateButton);
      await _pumpStudio(tester);
      await tester.tap(regenerateButton);
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
      final sectionControlsTitle = find.text('章节控制');
      await tester.ensureVisible(sectionControlsTitle);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(sectionControlsTitle);
      await _pumpStudio(tester);

      final createButton = find.text('新增章节');
      await tester.ensureVisible(createButton);
      await _pumpStudio(tester);
      await tester.tap(createButton);
      await _pumpStudio(tester);
      await tester.enterText(find.byType(TextField), '新增的章节');
      await tester.tap(find.widgetWithText(FilledButton, '创建'));
      await _pumpStudio(tester);

      expect(sectionRuntime.createCalls, ['新增的章节']);
      expect(find.text('新增的章节'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('deletes the selected part into the recycle bin',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      await tester.pumpWidget(_app(studioRuntime, sectionRuntime));
      await _pumpStudio(tester);

      final deleteButton = find.widgetWithText(OutlinedButton, '删除段落');
      await revealInStudio(tester, deleteButton);
      await _pumpStudio(tester);
      await tester.tap(deleteButton);
      await _pumpStudio(tester);

      // Deletion is a destructive action, so it must ask first.
      expect(find.text('删除段落'), findsWidgets);
      await tester.tap(find.widgetWithText(FilledButton, '删除').last);
      await _pumpStudio(tester);

      expect(
        sectionRuntime.deletedParts,
        [tree.parts.single.id.value],
        reason: 'the Part delete capability was implemented but had no entry '
            'point (P9-M8)',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('cancelling the part delete prompt changes nothing',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      await tester.pumpWidget(_app(studioRuntime, sectionRuntime));
      await _pumpStudio(tester);

      final deleteButton = find.widgetWithText(OutlinedButton, '删除段落');
      await revealInStudio(tester, deleteButton);
      await _pumpStudio(tester);
      await tester.tap(deleteButton);
      await _pumpStudio(tester);

      await tester.tap(find.widgetWithText(TextButton, '取消').last);
      await _pumpStudio(tester);

      expect(sectionRuntime.deletedParts, isEmpty);
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
      resourceCapacityRuntimeProvider.overrideWithValue(
        FakeResourceCapacityRuntime(),
      ),
    ],
    child: const MaterialApp(
      locale: Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ResourceStudioPage(sessionId: 'gen_studio_test'),
    ),
  );
}
