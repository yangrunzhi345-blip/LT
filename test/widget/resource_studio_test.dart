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
      expect(controller.state.partContents[partId.value], '已有正文。',
          reason: 'validation failure must discard the uncommitted preview');
    });

    test('should refresh committed tree after generation completes', () async {
      final emptyTree = ResourceTree(
        resource: tree.resource,
        sections: tree.sections,
        parts: [tree.parts.single.copyWith(content: '')],
      );
      runtime.dispose();
      runtime = FakeResourceStudioRuntime(
        tree: emptyTree,
        session: session,
      );
      final controller = ResourceStudioController(
        runtime: runtime,
        sessionId: session.sessionId,
      );
      addTearDown(controller.dispose);

      await controller.load();
      final partId = emptyTree.parts.single.id;
      final sectionId = emptyTree.sections.single.id;
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
          textDelta: 'preview 正文',
          cursor: 11,
        ),
        accumulatedLength: 11,
        timestamp: DateTime(2026),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 35));
      expect(controller.state.partContents[partId.value], 'preview 正文');
      expect(controller.state.tree!.parts.single.content, isEmpty,
          reason: 'preview must not change the committed tree');

      runtime.authoritativeTree = ResourceTree(
        resource: emptyTree.resource,
        sections: emptyTree.sections,
        parts: [emptyTree.parts.single.copyWith(content: '已提交正文')],
      );
      runtime.eventsController.add(GenerationCompleted(
        generationId: session.sessionId,
        resourceId: session.resourceId,
        totalParts: 1,
        totalCharacters: 5,
        timestamp: DateTime(2026),
      ));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.tree!.parts.single.content, '已提交正文');
      expect(controller.state.partContents[partId.value], '已提交正文');
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
        targetCharacters: 12000,
      );

      expect(runtime.createCalled, isTrue);
      expect(runtime.createdTargetCharacters, 12000);
      expect(controller.state.session, isNotNull);
      expect(controller.state.status, ResourceStudioStatus.generating);
    });

    test('should resume failed generation despite a completed selection',
        () async {
      final completedPart = tree.parts.single.id;
      session = StreamingGenerationSession(
        sessionId: session.sessionId,
        resourceId: session.resourceId,
        blueprintId: session.blueprintId,
        status: StreamingLifecycleStatus.failed,
        currentPartId: completedPart,
        currentTaskId: 'completed_task',
        currentAttemptId: 'completed_attempt',
        completedPartsCount: 1,
        totalPartsCount: 2,
        createdAt: session.createdAt,
        updatedAt: session.updatedAt,
      );
      runtime.session = session;
      final controller = ResourceStudioController(
        runtime: runtime,
        sessionId: session.sessionId,
      );
      addTearDown(controller.dispose);

      await controller.load();
      controller.selectPart(completedPart);
      await controller.retry();

      expect(runtime.resumeCalls, [session.sessionId]);
      expect(runtime.retryPartCalls, isEmpty);
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

    testWidgets('should show committed generation in the outline',
        (tester) async {
      final emptyTree = ResourceTree(
        resource: tree.resource,
        sections: tree.sections,
        parts: [tree.parts.single.copyWith(content: '')],
      );
      runtime.dispose();
      runtime = FakeResourceStudioRuntime(
        tree: emptyTree,
        session: session,
      );
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(runtime));
      await tester.pumpAndSettle();
      expect(find.text('待生成'), findsOneWidget);

      runtime.authoritativeTree = ResourceTree(
        resource: emptyTree.resource,
        sections: emptyTree.sections,
        parts: [emptyTree.parts.single.copyWith(content: '已提交正文')],
      );
      runtime.eventsController.add(GenerationCompleted(
        generationId: session.sessionId,
        resourceId: session.resourceId,
        totalParts: 1,
        totalCharacters: 5,
        timestamp: DateTime(2026),
      ));
      await tester.pumpAndSettle();

      expect(find.text('已生成'), findsOneWidget);
      expect(find.text('待生成'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final size in const <Size>[Size(1200, 800), Size(450, 800)]) {
      testWidgets('should keep the outline on the left at $size',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_app(runtime));
        await tester.pumpAndSettle();

        final outline = find.byKey(
          const ValueKey<String>('resource_studio_outline'),
        );
        final main = find.byKey(
          const ValueKey<String>('resource_studio_main'),
        );
        expect(outline, findsOneWidget);
        expect(main, findsOneWidget);
        expect(find.widgetWithText(ExpansionTile, '目录'), findsNothing);
        expect(tester.getTopLeft(outline).dx,
            lessThan(tester.getTopLeft(main).dx));
        expect(tester.getSize(main).width, greaterThan(0));
        expect(tester.takeException(), isNull);
      });
    }

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
