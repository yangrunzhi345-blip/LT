import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/resource_autosave_service.dart';
import 'package:lt_dialogue/domain/resources/resource_autosave.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/widgets/resource_studio_part_editor.dart';

import '../helpers/responsive_test_helper.dart';

/// Records what the editor asked the autosave session to do.
///
/// The debounce, journal and revision rules live in the service tests; this
/// fake exists so the widget test can prove what the UI does with the answers.
final class _FakeAutosaveSession implements AutosaveSession {
  final List<String> scheduled = <String>[];
  final List<AutosaveFlushTrigger> flushes = <AutosaveFlushTrigger>[];
  AutosaveFlushResult? nextResult;
  Object? nextError;
  bool disposed = false;

  @override
  void Function(AutosaveFlushResult result)? onFlushed;

  @override
  int get pendingCount => scheduled.isEmpty ? 0 : 1;

  @override
  void schedule({
    required ResourceId resourceId,
    required PartId partId,
    required String content,
    required String expectedUpdatedAt,
  }) {
    scheduled.add(content);
  }

  @override
  Future<AutosaveFlushResult> flush({
    AutosaveFlushTrigger trigger = AutosaveFlushTrigger.manual,
  }) async {
    flushes.add(trigger);
    if (nextError != null) throw nextError!;
    final result = nextResult ??
        AutosaveFlushResult(
          trigger: trigger,
          outcomes: <AutosaveWriteOutcome>[
            const AutosaveWriteOutcome(
              partId: 'part_1',
              status: AutosaveWriteStatus.applied,
              checkpointId: 'auto_1',
              contentCharacters: 4,
            ),
          ],
        );
    onFlushed?.call(result);
    return result;
  }

  /// Draft the fake reports as pending, if any.
  ResourceAutosaveDraft? pending;
  int reconcileCalls = 0;
  final List<String> discarded = <String>[];

  @override
  Future<List<AutosaveRecoveryOutcome>> reconcilePendingDrafts({
    ResourceId? resourceId,
  }) async {
    reconcileCalls++;
    if (pending == null) return const <AutosaveRecoveryOutcome>[];
    return <AutosaveRecoveryOutcome>[
      AutosaveRecoveryOutcome(
        draft: pending!,
        disposition: AutosaveRecoveryDisposition.needsUserDecision,
      ),
    ];
  }

  @override
  Future<ResourceAutosaveDraft?> pendingDraft(PartId partId) async => pending;

  @override
  Future<void> discardDraft(ResourceAutosaveDraft draft) async {
    discarded.add(draft.checkpointId);
    pending = null;
  }

  AutosaveWriteOutcome? keepMineOutcome;
  AutosaveWriteOutcome? discardMineOutcome;
  final List<String> keepMineContents = <String>[];
  int discardMineCalls = 0;

  @override
  Future<AutosaveWriteOutcome> resolveConflictKeepMine({
    required ResourceId resourceId,
    required PartId partId,
    required String content,
  }) async {
    keepMineContents.add(content);
    return keepMineOutcome ??
        AutosaveWriteOutcome(
          partId: partId.value,
          status: AutosaveWriteStatus.applied,
          checkpointId: 'auto_resolved',
        );
  }

  @override
  Future<AutosaveWriteOutcome> resolveConflictDiscardMine({
    required ResourceId resourceId,
    required PartId partId,
  }) async {
    discardMineCalls++;
    return discardMineOutcome ??
        AutosaveWriteOutcome(
          partId: partId.value,
          status: AutosaveWriteStatus.adoptedLive,
          checkpointId: '',
          adoptedLiveContent: '外部最新内容',
          message: '已放弃我的文本，正文已采用最新内容',
        );
  }

  @override
  Future<AutosaveFlushResult> dispose() async {
    disposed = true;
    return const AutosaveFlushResult(
      trigger: AutosaveFlushTrigger.dispose,
      outcomes: <AutosaveWriteOutcome>[],
    );
  }
}

const _partId = PartId('part_1');

void main() {
  late _FakeAutosaveSession session;

  setUp(() {
    session = _FakeAutosaveSession();
  });

  Widget build({
    String initialContent = '初始正文',
    String updatedAt = 'tok_0',
    void Function(String content)? onSaved,
    VoidCallback? onClose,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ResourceStudioPartEditor(
              resourceId: const ResourceId('res_1'),
              partId: _partId,
              partTitle: '开场',
              initialContent: initialContent,
              updatedAt: updatedAt,
              autosaveFactory: () => session,
              onSaved: onSaved ?? (_) {},
              onClose: onClose ?? () {},
            ),
          ),
        ),
      );

  group('ResourceStudioPartEditor — responsive', () {
    for (final viewport in requiredUiViewports) {
      testWidgets(
        'renders at ${viewport.width}x${viewport.height} without overflow',
        (tester) async {
          setViewport(
            tester,
            width: viewport.width,
            height: viewport.height,
          );
          await tester.pumpWidget(build());
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.byType(TextField), findsOneWidget);
          expect(find.text('开场'), findsOneWidget);
        },
      );
    }

    testWidgets('survives a long dynamic title at 320 px', (tester) async {
      setViewport(tester, width: 320, height: 568);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: build(
            initialContent: '一段很长的正文内容，用于验证窄屏输入区域与按钮排布不会溢出。' * 4,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('ResourceStudioPartEditor — draft recovery (P9-M2)', () {
    ResourceAutosaveDraft draft({String content = '上次未保存的正文'}) =>
        ResourceAutosaveDraft(
          checkpointId: 'auto_pending',
          resourceId: const ResourceId('res_1'),
          partId: _partId,
          content: content,
          contentHash: 'hash',
          baseUpdatedAt: 'tok_0',
          createdAtToken: '2026-09-17T10:00:00.000',
          updatedAtToken: '2026-09-17T10:00:00.000',
        );

    testWidgets('asks the session to reconcile on open', (tester) async {
      setViewport(tester, width: 390, height: 844);
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      expect(
        session.reconcileCalls,
        1,
        reason: 'opening the editor is the production recovery entry point',
      );
    });

    testWidgets('surfaces a pending draft instead of hiding it',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      session.pending = draft();
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      expect(find.text('发现未保存的草稿'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '载入草稿'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('loading the draft puts the text back in the editor',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      session.pending = draft();
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, '载入草稿'));
      await tester.pumpAndSettle();

      expect(find.text('上次未保存的正文'), findsOneWidget);
      expect(find.text('发现未保存的草稿'), findsNothing);
      expect(
        session.scheduled,
        contains('上次未保存的正文'),
        reason: 'the loaded text must be scheduled so saving writes it',
      );
    });

    testWidgets('discarding the draft is an explicit user action',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      session.pending = draft();
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, '丢弃草稿'));
      await tester.pumpAndSettle();

      expect(session.discarded, <String>['auto_pending']);
      expect(find.text('发现未保存的草稿'), findsNothing);
    });

    testWidgets('the banner fits 320 px with a long draft', (tester) async {
      setViewport(tester, width: 320, height: 568);
      session.pending = draft(content: '很长的草稿内容' * 40);
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(FilledButton, '载入草稿'), findsOneWidget);
    });
  });

  group('ResourceStudioPartEditor — conflict visibility (P9-M2)', () {
    testWidgets('a keystroke does not silently clear a save conflict',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      await tester.pumpWidget(build());
      await tester.enterText(find.byType(TextField), '触发冲突');

      session.nextResult = const AutosaveFlushResult(
        trigger: AutosaveFlushTrigger.manual,
        outcomes: <AutosaveWriteOutcome>[
          AutosaveWriteOutcome(
            partId: 'part_1',
            status: AutosaveWriteStatus.conflict,
            checkpointId: 'auto_1',
            message: '已被并发修改',
          ),
        ],
      );
      await tester.tap(find.widgetWithText(FilledButton, '立即保存'));
      await tester.pumpAndSettle();
      expect(find.textContaining('保存冲突'), findsOneWidget);

      // Keep typing: the user must still see that nothing was saved.
      await tester.enterText(find.byType(TextField), '触发冲突后再输入');
      await tester.pump();

      expect(
        find.textContaining('保存冲突'),
        findsOneWidget,
        reason: 'a conflict must stay visible until a save actually succeeds',
      );
      expect(find.textContaining('编辑中'), findsNothing);
    });

    testWidgets('a later successful save clears the conflict', (tester) async {
      setViewport(tester, width: 390, height: 844);
      await tester.pumpWidget(build());
      await tester.enterText(find.byType(TextField), '第一次');

      session.nextResult = const AutosaveFlushResult(
        trigger: AutosaveFlushTrigger.manual,
        outcomes: <AutosaveWriteOutcome>[
          AutosaveWriteOutcome(
            partId: 'part_1',
            status: AutosaveWriteStatus.conflict,
            checkpointId: 'auto_1',
          ),
        ],
      );
      await tester.tap(find.widgetWithText(FilledButton, '立即保存'));
      await tester.pumpAndSettle();
      expect(find.textContaining('保存冲突'), findsOneWidget);

      session.nextResult = const AutosaveFlushResult(
        trigger: AutosaveFlushTrigger.manual,
        outcomes: <AutosaveWriteOutcome>[
          AutosaveWriteOutcome(
            partId: 'part_1',
            status: AutosaveWriteStatus.applied,
            checkpointId: 'auto_2',
            contentCharacters: 3,
          ),
        ],
      );
      await tester.tap(find.widgetWithText(FilledButton, '立即保存'));
      await tester.pumpAndSettle();

      expect(find.textContaining('保存冲突'), findsNothing);
      expect(find.textContaining('已自动保存'), findsOneWidget);
    });
  });

  group('ResourceStudioPartEditor — external conflict resolution (R2-M1)', () {
    AutosaveFlushResult conflictResult() => const AutosaveFlushResult(
          trigger: AutosaveFlushTrigger.manual,
          outcomes: <AutosaveWriteOutcome>[
            AutosaveWriteOutcome(
              partId: 'part_1',
              status: AutosaveWriteStatus.conflict,
              checkpointId: 'auto_1',
              requiresUserResolution: true,
              message: '已被并发修改',
            ),
          ],
        );

    testWidgets('an external conflict surfaces the two resolution actions',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      await tester.pumpWidget(build());
      await tester.enterText(find.byType(TextField), '我的草稿');

      session.nextResult = conflictResult();
      await tester.tap(find.widgetWithText(FilledButton, '立即保存'));
      await tester.pumpAndSettle();

      expect(find.text('检测到内容冲突'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '使用我的文本'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '放弃我的文本'), findsOneWidget);
    });

    testWidgets(
        '「使用我的文本」passes the current editor text and clears the '
        'banner on success', (tester) async {
      setViewport(tester, width: 390, height: 844);
      final saved = <String>[];
      await tester.pumpWidget(build(onSaved: saved.add));
      await tester.enterText(find.byType(TextField), '我的草稿 v3');

      session.nextResult = conflictResult();
      await tester.tap(find.widgetWithText(FilledButton, '立即保存'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, '使用我的文本'));
      await tester.pumpAndSettle();

      expect(session.keepMineContents, <String>['我的草稿 v3']);
      expect(find.text('检测到内容冲突'), findsNothing);
      expect(find.textContaining('已保留我的文本'), findsOneWidget);
      expect(saved, contains('我的草稿 v3'));
    });

    testWidgets('a second race during resolution keeps the conflict banner',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      await tester.pumpWidget(build());
      await tester.enterText(find.byType(TextField), '我的草稿');

      session.nextResult = conflictResult();
      await tester.tap(find.widgetWithText(FilledButton, '立即保存'));
      await tester.pumpAndSettle();

      session.keepMineOutcome = const AutosaveWriteOutcome(
        partId: 'part_1',
        status: AutosaveWriteStatus.conflict,
        checkpointId: 'auto_2',
        requiresUserResolution: true,
        message: '再次冲突',
      );
      await tester.tap(find.widgetWithText(FilledButton, '使用我的文本'));
      await tester.pumpAndSettle();

      expect(find.text('检测到内容冲突'), findsOneWidget);
      expect(find.textContaining('冲突仍未解决'), findsOneWidget);
    });

    testWidgets('「放弃我的文本」adopts the live content into the editor',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      await tester.pumpWidget(build());
      await tester.enterText(find.byType(TextField), '我的旧草稿');

      session.nextResult = conflictResult();
      await tester.tap(find.widgetWithText(FilledButton, '立即保存'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, '放弃我的文本'));
      await tester.pumpAndSettle();

      expect(session.discardMineCalls, 1);
      expect(find.text('外部最新内容'), findsOneWidget);
      expect(find.text('检测到内容冲突'), findsNothing);
      expect(find.textContaining('已放弃我的文本'), findsOneWidget);
    });

    testWidgets('the conflict banner fits 320 px', (tester) async {
      setViewport(tester, width: 320, height: 568);
      await tester.pumpWidget(build());
      await tester.enterText(find.byType(TextField), '很长的用户草稿内容' * 10);

      session.nextResult = conflictResult();
      await tester.tap(find.widgetWithText(FilledButton, '立即保存'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(FilledButton, '使用我的文本'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '放弃我的文本'), findsOneWidget);
    });
  });

  group('ResourceStudioPartEditor — saving', () {
    testWidgets('shows the initial content and no status', (tester) async {
      setViewport(tester, width: 390, height: 844);
      await tester.pumpWidget(build());

      expect(find.text('初始正文'), findsOneWidget);
      expect(find.textContaining('编辑中'), findsNothing);
    });

    testWidgets('a keystroke is buffered, not written', (tester) async {
      setViewport(tester, width: 390, height: 844);
      await tester.pumpWidget(build());

      await tester.enterText(find.byType(TextField), '改了一半');
      await tester.pump();

      expect(session.scheduled, contains('改了一半'));
      expect(
        session.flushes.where((trigger) => trigger.isForced),
        isEmpty,
        reason: 'typing must not force a save',
      );
      expect(find.textContaining('编辑中'), findsOneWidget);
    });

    testWidgets('a debounce flush reports the save and the trigger',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      final saved = <String>[];
      await tester.pumpWidget(build(onSaved: saved.add));
      await tester.enterText(find.byType(TextField), '保存后的正文');

      session.nextResult = const AutosaveFlushResult(
        trigger: AutosaveFlushTrigger.debounce,
        outcomes: <AutosaveWriteOutcome>[
          AutosaveWriteOutcome(
            partId: 'part_1',
            status: AutosaveWriteStatus.applied,
            checkpointId: 'auto_1',
            contentCharacters: 6,
          ),
        ],
      );
      await tester.tap(find.widgetWithText(FilledButton, '立即保存'));
      await tester.pumpAndSettle();

      expect(session.flushes, contains(AutosaveFlushTrigger.manual));
      expect(find.textContaining('已自动保存'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a conflict is surfaced and blocks the success message',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      await tester.pumpWidget(build());
      await tester.enterText(find.byType(TextField), '基于陈旧版本的编辑');

      session.nextResult = const AutosaveFlushResult(
        trigger: AutosaveFlushTrigger.manual,
        outcomes: <AutosaveWriteOutcome>[
          AutosaveWriteOutcome(
            partId: 'part_1',
            status: AutosaveWriteStatus.conflict,
            checkpointId: 'auto_1',
            message: '已被并发修改',
          ),
        ],
      );
      await tester.tap(find.widgetWithText(FilledButton, '立即保存'));
      await tester.pumpAndSettle();

      expect(find.textContaining('保存冲突'), findsOneWidget);
      expect(find.textContaining('已自动保存'), findsNothing);
    });

    testWidgets('a dropped draft is reported as such', (tester) async {
      setViewport(tester, width: 390, height: 844);
      await tester.pumpWidget(build());

      session.nextResult = const AutosaveFlushResult(
        trigger: AutosaveFlushTrigger.manual,
        outcomes: <AutosaveWriteOutcome>[
          AutosaveWriteOutcome(
            partId: 'part_1',
            status: AutosaveWriteStatus.missingTarget,
            checkpointId: 'auto_1',
          ),
        ],
      );
      await tester.tap(find.widgetWithText(FilledButton, '立即保存'));
      await tester.pumpAndSettle();

      expect(find.textContaining('目标内容已不存在'), findsOneWidget);
    });
  });

  group('ResourceStudioPartEditor — exit boundaries', () {
    testWidgets('closing the editor flushes before reporting the close',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      var closed = false;
      await tester.pumpWidget(build(onClose: () => closed = true));
      await tester.enterText(find.byType(TextField), '关闭前的内容');

      await tester.tap(find.widgetWithText(OutlinedButton, '完成编辑'));
      await tester.pumpAndSettle();

      expect(
        session.flushes,
        contains(AutosaveFlushTrigger.pageLeave),
        reason: 'an exit must save, not drop the buffer',
      );
      expect(closed, isTrue);
    });

    testWidgets('removing the editor disposes the session', (tester) async {
      setViewport(tester, width: 390, height: 844);
      await tester.pumpWidget(build());
      await tester.enterText(find.byType(TextField), '被移除时的内容');

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();

      expect(
        session.disposed,
        isTrue,
        reason: 'the final flush must be triggered by disposal, because the '
            'debounce timer may still be armed',
      );
    });
  });
}
