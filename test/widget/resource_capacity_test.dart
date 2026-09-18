import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/resource_capacity.dart';
import 'package:lt_dialogue/domain/resources/resource_compression.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/features/resource_studio/domain/models/resource_capacity_view_state.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/controllers/resource_capacity_controller.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/widgets/resource_capacity_panel.dart';

import '../helpers/resource_capacity_fakes.dart';
import '../helpers/responsive_test_helper.dart';

ResourceCapacitySnapshot snapshot({
  ResourceType type = ResourceType.worldview,
  int total = 42000,
  CapacityStatus? status,
}) {
  return ResourceCapacitySnapshot(
    resourceId: const ResourceId('res_panel'),
    type: type,
    totalCharacters: total,
    activeCharacters: total,
    archivedCharacters: 0,
    estimatedTokens: ResourceCapacityMath.tokensForCharacters(total),
    sectionCount: 12,
    partCount: 48,
    historicalRevisionCount: 3,
    status: status ?? ResourceCapacityMath.statusFor(type, total),
    measuredAt: DateTime(2026, 9, 17),
  );
}

ResourceCapacityViewState readyState({
  ResourceCapacitySnapshot? capacity,
  int candidates = 2,
  int queued = 1,
  int saved = 900,
  int retryableFailedJobs = 0,
  String latestFailureReason = '',
}) {
  return ResourceCapacityViewState(
    status: ResourceCapacityViewStatus.ready,
    resourceId: const ResourceId('res_panel'),
    summary: ResourceCapacitySummary(
      snapshot: capacity ?? snapshot(),
      candidateCount: candidates,
      queuedJobs: queued,
      potentialSavedCharacters: saved,
      retryableFailedJobs: retryableFailedJobs,
      latestFailureReason: latestFailureReason,
    ),
  );
}

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ResourceCapacityPanel — responsive', () {
    for (final viewport in requiredUiViewports) {
      testWidgets(
        'renders at ${viewport.width}x${viewport.height} without overflow',
        (tester) async {
          setViewport(
            tester,
            width: viewport.width,
            height: viewport.height,
          );
          await tester.pumpWidget(
            wrap(
              SingleChildScrollView(
                child: ResourceCapacityPanel(
                  state: readyState(
                    capacity: snapshot(total: 61234),
                  ),
                  onRefresh: () {},
                  onCompress: () {},
                  onRetry: () {},
                  onPublish: () {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('容量'), findsOneWidget);
          expect(find.text('超出预算'), findsOneWidget);
          expect(find.text('生成压缩候选'), findsOneWidget);
          expect(find.text('刷新容量'), findsOneWidget);
        },
      );
    }

    testWidgets('survives a long dynamic value at 320 px', (tester) async {
      setViewport(tester, width: 320, height: 568);
      await tester.pumpWidget(
        wrap(
          SingleChildScrollView(
            child: ResourceCapacityPanel(
              state: readyState(
                capacity: snapshot(total: 999999999),
                saved: 123456789,
              ),
              onRefresh: () {},
              onCompress: () {},
              onRetry: () {},
              onPublish: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('999999999'), findsWidgets);
    });

    testWidgets('survives a large text scale at 320 px', (tester) async {
      setViewport(tester, width: 320, height: 568);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: wrap(
            SingleChildScrollView(
              child: ResourceCapacityPanel(
                state: readyState(),
                onRefresh: () {},
                onCompress: () {},
                onRetry: () {},
                onPublish: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('生成压缩候选'), findsOneWidget);
    });
  });

  group('ResourceCapacityPanel — behaviour', () {
    testWidgets('compression is disabled until a capacity is measured',
        (tester) async {
      setViewport(tester, width: 360, height: 640);
      await tester.pumpWidget(
        wrap(
          ResourceCapacityPanel(
            state: const ResourceCapacityViewState.initial(),
            onRefresh: () {},
            onCompress: () {},
            onRetry: () {},
            onPublish: () {},
          ),
        ),
      );

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '生成压缩候选'),
      );
      expect(button.onPressed, isNull);
      expect(find.text('正在准备资源状态。'), findsOneWidget);
    });

    testWidgets('calls the callbacks', (tester) async {
      setViewport(tester, width: 390, height: 844);
      var refreshes = 0;
      var compressions = 0;
      await tester.pumpWidget(
        wrap(
          ResourceCapacityPanel(
            state: readyState(),
            onRefresh: () => refreshes++,
            onCompress: () => compressions++,
            onRetry: () {},
            onPublish: () {},
          ),
        ),
      );

      await tester.tap(find.text('刷新容量'));
      await tester.tap(find.text('生成压缩候选'));
      await tester.pump();

      expect(refreshes, 1);
      expect(compressions, 1);
    });

    testWidgets('shows the elastic band and the candidate saving',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      await tester.pumpWidget(
        wrap(
          SingleChildScrollView(
            child: ResourceCapacityPanel(
              state: readyState(
                capacity: snapshot(
                  status: CapacityStatus.elastic,
                  total: 52000,
                ),
              ),
              onRefresh: () {},
              onCompress: () {},
              onRetry: () {},
              onPublish: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('弹性'), findsOneWidget);
      expect(find.textContaining('采纳候选后约可减少'), findsOneWidget);
      expect(find.textContaining('优化会先生成预览'), findsOneWidget);
    });

    testWidgets(
        'offers retry with the count and the failure reason at 320 px '
        '(BUG-002 / BUG-004)', (tester) async {
      setViewport(tester, width: 320, height: 568);
      var retries = 0;
      await tester.pumpWidget(
        wrap(
          SingleChildScrollView(
            child: ResourceCapacityPanel(
              state: readyState(
                retryableFailedJobs: 2,
                latestFailureReason: '压缩校验未通过：压缩结果超出预算：原文 800 字，'
                    '实际 560 字，目标 480 字（达成比 0.70），可重试并加强压缩要求',
              ),
              onRefresh: () {},
              onCompress: () {},
              onRetry: () => retries++,
              onPublish: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('重试失败压缩（2）'), findsOneWidget);
      expect(find.textContaining('最近一次压缩失败原因'), findsOneWidget);
      expect(find.textContaining('目标 480 字'), findsOneWidget);

      await tester.tap(find.textContaining('重试失败压缩'));
      await tester.pump();
      expect(retries, 1);
    });

    testWidgets('disables retry when no failure still has attempt budget',
        (tester) async {
      setViewport(tester, width: 360, height: 640);
      await tester.pumpWidget(
        wrap(
          ResourceCapacityPanel(
            state: readyState(),
            onRefresh: () {},
            onCompress: () {},
            onRetry: () {},
            onPublish: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '重试失败压缩'),
      );
      expect(button.onPressed, isNull);
      expect(find.textContaining('最近一次压缩失败原因'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('ResourceCapacityController', () {
    test('load reports a measured summary', () async {
      final runtime = FakeResourceCapacityRuntime();
      final controller = ResourceCapacityController(runtime: runtime);

      await controller.load('res_1');
      expect(controller.state.status, ResourceCapacityViewStatus.ready);
      expect(controller.state.summary!.snapshot.totalCharacters, 1234);
      expect(runtime.summarizeCalls, ['res_1']);
      controller.dispose();
    });

    test('load surfaces a failure instead of inventing a capacity', () async {
      final runtime = FakeResourceCapacityRuntime()
        ..error = StateError('数据库不可用');
      final controller = ResourceCapacityController(runtime: runtime);

      await controller.load('res_1');
      expect(controller.state.status, ResourceCapacityViewStatus.failed);
      expect(controller.state.summary, isNull);
      expect(controller.state.errorMessage, contains('数据库不可用'));
      controller.dispose();
    });

    test('requestCompression queues, runs and refreshes without blocking',
        () async {
      final runtime = FakeResourceCapacityRuntime();
      final controller = ResourceCapacityController(runtime: runtime);
      await controller.load('res_1');

      await controller.requestCompression();
      expect(runtime.queueCalls, ['res_1'],
          reason: 'queueing targets the resource the measurement reported');

      await pumpEventQueue();
      expect(runtime.runCalls, 1);
      expect(controller.state.status, ResourceCapacityViewStatus.ready);
      expect(controller.state.lastMessage, contains('压缩候选'));
      expect(runtime.summarizeCalls.length, greaterThanOrEqualTo(2));
      controller.dispose();
    });

    test('requestCompression reports when nothing needed compressing',
        () async {
      final runtime = FakeResourceCapacityRuntime()..queuedCount = 0;
      final controller = ResourceCapacityController(runtime: runtime);
      await controller.load('res_1');

      await controller.requestCompression();
      await pumpEventQueue();

      expect(runtime.runCalls, 0);
      expect(controller.state.lastMessage, '没有需要压缩的章节');
      controller.dispose();
    });

    test('load only reads the panel and triggers nothing', () async {
      final runtime = FakeResourceCapacityRuntime()..editorLeaveActiveJobs = 2;
      final controller = ResourceCapacityController(runtime: runtime);

      await controller.load('res_1');
      expect(controller.state.status, ResourceCapacityViewStatus.ready);
      expect(controller.state.summary, isNotNull);
      await pumpEventQueue();

      // Reading a screen must not have side effects: the automatic trigger is
      // owned by the editor lifecycle, not by opening the panel.
      expect(runtime.editorLeaveCalls, isEmpty);
      expect(runtime.runCalls, 0);
      expect(runtime.retryCalls, isEmpty);
      controller.dispose();
    });

    test('dispose triggers the automatic path for the shown resource',
        () async {
      final runtime = FakeResourceCapacityRuntime();
      final controller = ResourceCapacityController(runtime: runtime);

      await controller.load('res_1');
      controller.dispose();
      await pumpEventQueue();

      expect(runtime.editorLeaveCalls, ['res_1'],
          reason: 'leaving the editor is the automatic compression boundary');
    });

    test('notifyEditorLeft is a no-op before a resource is known', () async {
      final runtime = FakeResourceCapacityRuntime();
      final controller = ResourceCapacityController(runtime: runtime);

      controller.notifyEditorLeft();
      await pumpEventQueue();

      expect(runtime.editorLeaveCalls, isEmpty);
      controller.dispose();
    });

    test('notifyEditorLeft survives a throwing runtime', () async {
      // Production never throws here, but leaving the editor is fire-and-forget
      // during dispose: a throwing implementation must not become an unhandled
      // async error.
      final runtime = FakeResourceCapacityRuntime()
        ..error = StateError('后台压缩不可用');
      final controller = ResourceCapacityController(runtime: runtime);
      await controller.load('res_1');

      controller.notifyEditorLeft();
      await pumpEventQueue();

      expect(runtime.editorLeaveCalls, ['res_1']);
      controller.dispose();
      await pumpEventQueue();
    });

    test('retryFailedCompression re-queues and then runs the retry', () async {
      final runtime = FakeResourceCapacityRuntime()
        ..retryableFailedJobs = 1
        ..retryOutcome = const CompressionRetryOutcome(requeued: 1);
      final controller = ResourceCapacityController(runtime: runtime);
      await controller.load('res_1');

      await controller.retryFailedCompression();
      expect(runtime.retryCalls, ['res_1']);
      await pumpEventQueue();
      expect(runtime.runCalls, 1);
      expect(runtime.runResourceIds, ['res_1'],
          reason: 'the retry pass must stay inside the resource');
      expect(controller.state.lastMessage, contains('压缩候选'));
      controller.dispose();
    });

    test('retryFailedCompression reports when the budget is spent', () async {
      final runtime = FakeResourceCapacityRuntime()
        ..retryableFailedJobs = 1
        ..retryOutcome = const CompressionRetryOutcome(skippedExhausted: 1);
      final controller = ResourceCapacityController(runtime: runtime);
      await controller.load('res_1');

      await controller.retryFailedCompression();
      await pumpEventQueue();

      expect(runtime.runCalls, 0,
          reason: 'nothing was re-queued, so there is nothing to run');
      expect(controller.state.lastMessage, contains('没有可重试的压缩任务'));
      controller.dispose();
    });

    test('retryFailedCompression reports skipped conflicts next to the retries',
        () async {
      final runtime = FakeResourceCapacityRuntime()
        ..retryableFailedJobs = 2
        ..retryOutcome = const CompressionRetryOutcome(
          requeued: 1,
          skippedActiveTarget: 1,
        );
      final controller = ResourceCapacityController(runtime: runtime);
      await controller.load('res_1');

      await controller.retryFailedCompression();
      await pumpEventQueue();

      expect(runtime.runCalls, 1);
      expect(controller.state.lastMessage, contains('压缩候选'));
      expect(controller.state.lastMessage, contains('已跳过'),
          reason: 'the skipped conflict must be reported, not swallowed');
      controller.dispose();
    });

    test(
        'retryFailedCompression reports a target conflict as a business '
        'result, never an error', () async {
      final runtime = FakeResourceCapacityRuntime()
        ..retryableFailedJobs = 1
        ..retryOutcome = const CompressionRetryOutcome(skippedActiveTarget: 1);
      final controller = ResourceCapacityController(runtime: runtime);
      await controller.load('res_1');

      await controller.retryFailedCompression();
      await pumpEventQueue();

      expect(runtime.runCalls, 0);
      expect(controller.state.status, ResourceCapacityViewStatus.ready);
      expect(controller.state.errorMessage, isEmpty,
          reason: 'a busy target is not a failure');
      expect(controller.state.lastMessage, contains('已跳过'));
      controller.dispose();
    });
  });
}
