import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_patch.dart';
import 'package:lt_dialogue/domain/resources/section_control.dart';
import 'package:lt_dialogue/domain/resources/streaming_generation_runtime_contracts.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/controllers/resource_studio_controller.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/pages/resource_studio_page.dart';
import 'package:lt_dialogue/features/resource_studio/domain/models/resource_studio_state.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';

import '../helpers/resource_capacity_fakes.dart';
import '../helpers/resource_studio_fakes.dart';
import '../helpers/section_control_fakes.dart';

void main() {
  late FakeResourceStudioRuntime runtime;
  late FakeSectionControlRuntime sectionRuntime;
  late ResourceTree tree;
  late StreamingGenerationSession session;

  setUp(() {
    tree = buildStudioTestTree();
    session = buildStudioTestSession(tree);
    runtime = FakeResourceStudioRuntime(tree: tree, session: session);
    sectionRuntime = FakeSectionControlRuntime(
      entries: [
        SectionControlEntry(
          id: tree.sections.single.id,
          resourceId: tree.resource.id,
          title: '第一章：一个很长的 Section 标题用于验证窄屏布局',
          orderIndex: 0,
          content: '已有正文。',
          partCount: 1,
          generationState: SectionGenerationState.generated,
          updatedAtToken: 'token-1',
        ),
      ],
    );
  });

  tearDown(() {
    runtime.dispose();
    sectionRuntime.dispose();
  });

  group('ResourceStudioController', () {
    test('should translate runtime events into immutable state', () async {
      final controller = ResourceStudioController(
        runtime: runtime,
        sessionId: session.sessionId,
      );
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.state.status, ResourceStudioStatus.paused);

      runtime.eventsController.add(GenerationStarted(
        generationId: session.sessionId,
        resourceId: session.resourceId,
        blueprintId: session.blueprintId,
        timestamp: DateTime(2026),
      ));
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.status, ResourceStudioStatus.generating);

      final partId = tree.parts.single.id;
      final sectionId = tree.sections.single.id;
      runtime.eventsController.add(PartStarted(
        generationId: session.sessionId,
        resourceId: session.resourceId,
        partId: partId,
        taskId: 'task',
        attemptId: 'attempt',
        attemptNumber: 1,
        timestamp: DateTime(2026),
      ));
      runtime.eventsController.add(PatchReceived(
        generationId: session.sessionId,
        resourceId: session.resourceId,
        partId: partId,
        taskId: 'task',
        attemptId: 'attempt',
        patch: ResourceGenerationPatch(
          protocolVersion: 1,
          generationId: session.sessionId,
          resourceId: session.resourceId,
          sectionId: sectionId,
          partId: partId,
          attemptId: 'attempt',
          sequence: 1,
          op: ResourcePatchOp.appendText,
          textDelta: '增量正文',
          cursor: 4,
        ),
        accumulatedLength: 4,
        timestamp: DateTime(2026),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 35));
      expect(controller.state.partContents[partId.value], '增量正文');

      runtime.eventsController.add(ValidationStarted(
        generationId: session.sessionId,
        resourceId: session.resourceId,
        partId: partId,
        taskId: 'task',
        attemptId: 'attempt',
        timestamp: DateTime(2026),
      ));
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.status, ResourceStudioStatus.validating);

      runtime.eventsController.add(GenerationFailed(
        generationId: session.sessionId,
        resourceId: session.resourceId,
        errorMessage: '测试错误',
        timestamp: DateTime(2026),
        failedPartId: partId,
      ));
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.status, ResourceStudioStatus.failed);
      expect(controller.state.errorMessage, '测试错误');
    });

    test('should create and start a generation through the runtime boundary',
        () async {
      final controller = ResourceStudioController(runtime: runtime);
      addTearDown(controller.dispose);

      await controller.load();
      await controller.createAndStart(
        resourceType: ResourceType.worldview,
        name: '新资源',
        referenceSource: ReferenceSource.text('参考材料'),
      );

      expect(runtime.createCalled, isTrue);
      expect(controller.state.session, isNotNull);
      expect(controller.state.status, ResourceStudioStatus.generating);
    });

    test('should describe a missing retry target as a segment', () async {
      final controller = ResourceStudioController(runtime: runtime);
      addTearDown(controller.dispose);

      await controller.load();
      await controller.retry();

      expect(controller.state.errorMessage, '没有可重试的段落');
      expect(controller.state.errorMessage, isNot(contains('Part')));
    });
  });

  group('ResourceStudioPage', () {
    for (final size in const <Size>[
      Size(320, 568),
      Size(360, 640),
      Size(390, 844),
      Size(412, 915),
      Size(768, 1024),
      Size(1280, 800),
    ]) {
      testWidgets('should render without overflow at $size', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_app(runtime));
        await tester.pumpAndSettle();

        expect(find.text('创作工作台'), findsOneWidget);
        expect(find.text('段落标题'), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('should expose generating, optimizing, error and retry states',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(runtime));
      await tester.pump();
      runtime.eventsController.add(GenerationStarted(
        generationId: session.sessionId,
        resourceId: session.resourceId,
        blueprintId: session.blueprintId,
        timestamp: DateTime(2026),
      ));
      await tester.pump();
      expect(find.text('生成中'), findsOneWidget);

      runtime.eventsController.add(ValidationStarted(
        generationId: session.sessionId,
        resourceId: session.resourceId,
        partId: tree.parts.single.id,
        taskId: 'task',
        attemptId: 'attempt',
        timestamp: DateTime(2026),
      ));
      await tester.pump();
      expect(find.text('生成中'), findsOneWidget);

      runtime.eventsController.add(GenerationFailed(
        generationId: session.sessionId,
        resourceId: session.resourceId,
        errorMessage: '需要重试',
        timestamp: DateTime(2026),
        failedPartId: tree.parts.single.id,
      ));
      await tester.pumpAndSettle();
      expect(find.text('优化失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('should map internal runtime terms before displaying an error',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      runtime.nextSessionError = StateError(
        'Part revision ID JSON absolute limit compression job '
        'assembly revision',
      );

      await tester.pumpWidget(_app(runtime));
      await tester.pumpAndSettle();

      const forbidden = <String>[
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
      expect(find.textContaining('段落'), findsOneWidget);
      expect(find.textContaining('数据格式'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('should expose the create-and-start entry from the chooser',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(runtime, sessionId: null));
      await tester.pumpAndSettle();
      await tester.tap(find.text('创建并开始生成'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '新建工作台资源');
      await tester.enterText(find.byType(TextField).at(1), '足够的参考材料');
      await tester.tap(find.text('开始创建'));
      // The resulting generating state intentionally contains an indeterminate
      // progress indicator, so it never reaches pumpAndSettle's idle condition.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(runtime.createCalled, isTrue);
      expect(find.text('生成中'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

Widget _app(
  FakeResourceStudioRuntime runtime, {
  String? sessionId = 'gen_studio_test',
  FakeSectionControlRuntime? sectionRuntime,
}) {
  return ProviderScope(
    overrides: [
      resourceStudioRuntimeProvider.overrideWithValue(runtime),
      sectionControlRuntimeProvider.overrideWithValue(
        sectionRuntime ?? FakeSectionControlRuntime(),
      ),
      resourceCapacityRuntimeProvider.overrideWithValue(
        FakeResourceCapacityRuntime(),
      ),
    ],
    child: MaterialApp(
      home: ResourceStudioPage(sessionId: sessionId),
    ),
  );
}
