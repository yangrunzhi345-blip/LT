import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/resource_capacity.dart';
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
}) {
  return ResourceCapacityViewState(
    status: ResourceCapacityViewStatus.ready,
    resourceId: const ResourceId('res_panel'),
    summary: ResourceCapacitySummary(
      snapshot: capacity ?? snapshot(),
      candidateCount: candidates,
      queuedJobs: queued,
      potentialSavedCharacters: saved,
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
          ),
        ),
      );

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '生成压缩候选'),
      );
      expect(button.onPressed, isNull);
      expect(find.text('尚未测量该资源容量。'), findsOneWidget);
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
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('弹性'), findsOneWidget);
      expect(find.textContaining('采纳候选后约可减少'), findsOneWidget);
      expect(find.textContaining('压缩只生成候选'), findsOneWidget);
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
      expect(runtime.queueCalls, ['res_fake'],
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
  });
}
