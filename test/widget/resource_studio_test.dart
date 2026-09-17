import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_patch.dart';
import 'package:lt_dialogue/domain/resources/streaming_generation_runtime_contracts.dart';
import 'package:lt_dialogue/features/resource_studio/application/use_cases/resource_studio_runtime.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/controllers/resource_studio_controller.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/pages/resource_studio_page.dart';
import 'package:lt_dialogue/features/resource_studio/domain/models/resource_studio_state.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';

void main() {
  late _FakeResourceStudioRuntime runtime;
  late ResourceTree tree;
  late StreamingGenerationSession session;

  setUp(() {
    const resourceId = ResourceId('res_studio_test');
    const sectionId = SectionId('section_studio_test');
    const partId = PartId('part_studio_test');
    tree = ResourceTree(
      resource: const Resource(
        id: resourceId,
        type: ResourceType.worldview,
        name: '一个很长的 Resource Studio 测试标题，用于窄屏换行',
        summary: '用于验证状态展示、滚动和响应式布局。',
      ),
      sections: [
        const ResourceSection(
          id: sectionId,
          resourceId: resourceId,
          title: '第一章：一个很长的 Section 标题用于验证截断和换行',
          sortOrder: 0,
        ),
      ],
      parts: [
        const ResourcePart(
          id: partId,
          sectionId: sectionId,
          title: 'Part 标题',
          content: '已有正文。',
          sortOrder: 0,
        ),
      ],
    );
    session = StreamingGenerationSession(
      sessionId: 'gen_studio_test',
      resourceId: resourceId,
      blueprintId: 'bp_studio_test',
      status: StreamingLifecycleStatus.paused,
      totalPartsCount: 1,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    runtime = _FakeResourceStudioRuntime(tree: tree, session: session);
  });

  tearDown(() => runtime.dispose());

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
        referenceText: '参考材料',
      );

      expect(runtime.createCalled, isTrue);
      expect(controller.state.session, isNotNull);
      expect(controller.state.status, ResourceStudioStatus.generating);
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

        expect(find.text('Resource Studio'), findsOneWidget);
        expect(find.text('Part 标题'), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('should expose generating, validating, error and retry states',
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
      expect(find.text('校验中'), findsOneWidget);

      runtime.eventsController.add(GenerationFailed(
        generationId: session.sessionId,
        resourceId: session.resourceId,
        errorMessage: '需要重试',
        timestamp: DateTime(2026),
        failedPartId: tree.parts.single.id,
      ));
      await tester.pumpAndSettle();
      expect(find.text('需要处理'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
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
      await tester.tap(find.text('开始'));
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
  _FakeResourceStudioRuntime runtime, {
  String? sessionId = 'gen_studio_test',
}) {
  return ProviderScope(
    overrides: [resourceStudioRuntimeProvider.overrideWithValue(runtime)],
    child: MaterialApp(
      home: ResourceStudioPage(sessionId: sessionId),
    ),
  );
}

final class _FakeResourceStudioRuntime implements ResourceStudioRuntime {
  _FakeResourceStudioRuntime({required this.tree, required this.session});

  final ResourceTree tree;
  StreamingGenerationSession session;
  final StreamController<GenerationRuntimeEvent> eventsController =
      StreamController<GenerationRuntimeEvent>.broadcast();
  bool createCalled = false;

  @override
  Stream<GenerationRuntimeEvent> get events => eventsController.stream;

  @override
  Future<ResourceTree?> readTree(ResourceId resourceId) async => tree;

  @override
  Future<StreamingGenerationSession?> getSession(String sessionId) async =>
      session.sessionId == sessionId ? session : null;

  @override
  Future<StreamingGenerationSession?> getLatestSessionForResource(
    String resourceId,
  ) async =>
      session.resourceId.value == resourceId ? session : null;

  @override
  Future<StreamingGenerationSession?> ensureSession(
          ResourceId resourceId) async =>
      session.resourceId == resourceId ? session : null;

  @override
  Future<List<StreamingGenerationSession>> findActiveSessions() async =>
      [session];

  @override
  Future<List<Resource>> listResources() async => [tree.resource];

  @override
  Future<bool> start(String sessionId) async => true;

  @override
  Future<void> pause(String sessionId) async {}

  @override
  Future<bool> resume(String sessionId) async => true;

  @override
  Future<void> cancel(String sessionId) async {}

  @override
  Future<bool> retryPart(String sessionId, String partId) async => true;

  @override
  Future<bool> recover(String sessionId) async => true;

  @override
  Future<StreamingGenerationSession> createAndStart({
    required ResourceType resourceType,
    required String name,
    required String referenceText,
  }) async {
    createCalled = true;
    return session;
  }

  @override
  void dispose() {
    unawaited(eventsController.close());
  }
}
