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
import '../helpers/responsive_test_helper.dart';
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
      await tester.tap(find.byKey(
        const ValueKey<String>('resource_studio_outline_toggle'),
      ));
      await tester.pump();
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

    for (final size in const <Size>[Size(360, 640), Size(450, 800)]) {
      testWidgets('should collapse the outline by default on mobile at $size',
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
        final toggle = find.byKey(
          const ValueKey<String>('resource_studio_outline_toggle'),
        );
        expect(outline, findsNothing);
        expect(main, findsOneWidget);
        expect(toggle, findsOneWidget);
        expect(tester.getSize(main).width, greaterThan(300));

        await tester.tap(toggle);
        await tester.pump();

        expect(outline, findsOneWidget);
        expect(tester.getTopLeft(outline).dx,
            lessThan(tester.getTopLeft(main).dx));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('should keep the outline expanded on desktop', (tester) async {
      tester.view.physicalSize = const Size(900, 800);
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
      expect(
          find.byKey(
            const ValueKey<String>('resource_studio_outline_toggle'),
          ),
          findsNothing);
      expect(
          tester.getTopLeft(outline).dx, lessThan(tester.getTopLeft(main).dx));
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

    group('continuous reader', () {
      late ResourceTree continuousTree;
      late StreamingGenerationSession continuousSession;

      setUp(() {
        continuousTree = _buildContinuousReaderTree();
        continuousSession = buildStudioTestSession(continuousTree);
        runtime.dispose();
        runtime = FakeResourceStudioRuntime(
          tree: continuousTree,
          session: continuousSession,
        );
      });

      testWidgets('should render every Part in ResourceTree order',
          (tester) async {
        setViewport(tester, width: 1280, height: 800);
        await tester.pumpWidget(_app(runtime));
        await tester.pumpAndSettle();

        expect(find.text('Part A'), findsNWidgets(2));
        expect(find.text('Part B'), findsNWidgets(2));
        expect(find.text('Part C'), findsNWidgets(2));
        expect(
          tester.getTopLeft(find.text('Part A').last).dy,
          lessThan(tester.getTopLeft(find.text('Part B').last).dy),
        );
        expect(
          tester.getTopLeft(find.text('Part B').last).dy,
          lessThan(tester.getTopLeft(find.text('Part C').last).dy),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('should keep the target selected during outline navigation',
          (tester) async {
        setViewport(tester, width: 1280, height: 800);
        await tester.pumpWidget(_app(runtime));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Part C').first);
        await tester.pump(const Duration(milliseconds: 150));

        final selectedTile = tester.widget<ListTile>(
          find.byWidgetPredicate(
            (widget) =>
                widget is ListTile &&
                widget.selected &&
                widget.title is Text &&
                (widget.title! as Text).data == 'Part C',
          ),
        );
        expect(selectedTile.selected, isTrue);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.text('Part C').last).dy, lessThan(220));
        expect(tester.takeException(), isNull);
      });

      testWidgets('should update the outline after natural reader scrolling',
          (tester) async {
        setViewport(tester, width: 1280, height: 800);
        await tester.pumpWidget(_app(runtime));
        await tester.pumpAndSettle();

        await tester.fling(
          find.byKey(const ValueKey<String>('resource_studio_main')),
          const Offset(0, -6000),
          4000,
        );
        await tester.pumpAndSettle();

        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is ListTile &&
                widget.selected &&
                widget.title is Text &&
                (widget.title! as Text).data == 'Part C',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('should retain the collapsed mobile outline after navigation',
          (tester) async {
        setViewport(tester, width: 360, height: 640);
        await tester.pumpWidget(_app(runtime));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('resource_studio_outline')),
          findsNothing,
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('resource_studio_outline_toggle')),
        );
        await tester.pump();
        await tester.tap(find.text('Part C').first);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('resource_studio_outline')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('should open a 50-Part, 50000-character reader',
          (tester) async {
        final largeTree = _buildLargeContinuousReaderTree();
        runtime.dispose();
        runtime = FakeResourceStudioRuntime(
          tree: largeTree,
          session: buildStudioTestSession(largeTree),
        );
        setViewport(tester, width: 1280, height: 800);

        await tester.pumpWidget(_app(runtime));
        await tester.pumpAndSettle();

        expect(find.text('Part 1'), findsNWidgets(2));
        expect(find.text('Part 50'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });
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

ResourceTree _buildContinuousReaderTree() {
  const resourceId = ResourceId('continuous_resource');
  const firstSectionId = SectionId('continuous_section_a');
  const secondSectionId = SectionId('continuous_section_b');
  final longContent = List<String>.filled(1800, '正文').join();
  return ResourceTree(
    resource: const Resource(
      id: resourceId,
      type: ResourceType.worldview,
      name: '连续阅读测试资源',
    ),
    sections: const [
      ResourceSection(
        id: firstSectionId,
        resourceId: resourceId,
        title: 'Section A',
        sortOrder: 0,
      ),
      ResourceSection(
        id: secondSectionId,
        resourceId: resourceId,
        title: 'Section B',
        sortOrder: 1,
      ),
    ],
    parts: [
      ResourcePart(
        id: const PartId('continuous_part_a'),
        sectionId: firstSectionId,
        title: 'Part A',
        content: longContent,
        sortOrder: 0,
      ),
      ResourcePart(
        id: const PartId('continuous_part_b'),
        sectionId: firstSectionId,
        title: 'Part B',
        content: longContent,
        sortOrder: 1,
      ),
      ResourcePart(
        id: const PartId('continuous_part_c'),
        sectionId: secondSectionId,
        title: 'Part C',
        content: longContent,
        sortOrder: 0,
      ),
    ],
  );
}

ResourceTree _buildLargeContinuousReaderTree() {
  const resourceId = ResourceId('large_continuous_resource');
  const sectionId = SectionId('large_continuous_section');
  final content = List<String>.filled(1000, '文').join();
  return ResourceTree(
    resource: const Resource(
      id: resourceId,
      type: ResourceType.worldview,
      name: '大规模连续阅读测试资源',
    ),
    sections: const [
      ResourceSection(
        id: sectionId,
        resourceId: resourceId,
        title: '性能章节',
        sortOrder: 0,
      ),
    ],
    parts: [
      for (var index = 0; index < 50; index++)
        ResourcePart(
          id: PartId('large_part_$index'),
          sectionId: sectionId,
          title: 'Part ${index + 1}',
          content: content,
          sortOrder: index,
        ),
    ],
  );
}
