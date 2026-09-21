import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/domain/read_aloud/read_aloud_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/pages/resource_studio_page.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/widgets/resource_studio_part_card.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/read_aloud/read_aloud_controller.dart';

import '../helpers/read_aloud_fakes.dart';
import '../helpers/resource_capacity_fakes.dart';
import '../helpers/resource_studio_fakes.dart';
import '../helpers/responsive_test_helper.dart';
import '../helpers/section_control_fakes.dart';

void main() {
  late FakeReadAloudEngine engine;
  late ReadAloudController controller;
  late ResourceTree tree;
  late FakeResourceStudioRuntime runtime;

  setUp(() {
    tree = buildStudioTestTree();
    runtime = FakeResourceStudioRuntime(
      tree: tree,
      session: buildStudioTestSession(tree),
    );
    engine = FakeReadAloudEngine();
    controller = ReadAloudController(
      engine: engine,
      initialPreferences: const ReadAloudPreferences(enabled: true),
    );
  });

  tearDown(() {
    runtime.dispose();
  });

  Widget wrap(Widget child) {
    return ProviderScope(
      overrides: [
        readAloudControllerProvider.overrideWith(
          (ref) => controller,
          disposeNotifier: false,
        ),
      ],
      // 与生产一致：卡片位于可滚动区域内，否则超长正文会撑破测试视口。
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
  }

  /// 同一组 overrides 对应两个不同的页面树：Riverpod 不允许在同一个
  /// ProviderScope 上增删 override，因此“离开页面”必须复用同一组 overrides。
  Widget studioShell({required Widget child}) {
    return ProviderScope(
      overrides: [
        resourceStudioRuntimeProvider.overrideWithValue(runtime),
        sectionControlRuntimeProvider.overrideWithValue(
          FakeSectionControlRuntime(),
        ),
        resourceCapacityRuntimeProvider.overrideWithValue(
          FakeResourceCapacityRuntime(),
        ),
        readAloudControllerProvider.overrideWith(
          (ref) => controller,
          disposeNotifier: false,
        ),
      ],
      child: MaterialApp(home: child),
    );
  }

  Widget studioApp() => studioShell(
        child: const ResourceStudioPage(sessionId: 'gen_studio_test'),
      );

  group('ResourceStudioPartCard 朗读', () {
    testWidgets('提供本段朗读入口并朗读该段正文', (tester) async {
      final part = tree.parts.first;
      await tester.pumpWidget(
        wrap(
          ResourceStudioPartCard(
            part: part,
            content: '这是第一段正文。',
            isActive: false,
            isValidating: false,
            hasError: false,
            onRetry: null,
          ),
        ),
      );
      await tester.pump();

      final button = find.byIcon(Icons.volume_up_rounded);
      expect(button, findsOneWidget);

      await tester.tap(button);
      await tester.pump();
      await tester.pump();

      expect(engine.spokenTexts, ['这是第一段正文。']);
      expect(controller.state.sourceId,
          ResourceStudioPartCard.readAloudIdFor(part));
      expect(controller.state.sourceType, ReadAloudSourceType.studioPart);
    });

    testWidgets('20000+ 字角色卡分段朗读且每段不超上限', (tester) async {
      final part = tree.parts.first;
      final longContent = List.filled(4200, '角色设定内容。').join();
      expect(longContent.length, greaterThan(20000));

      await tester.pumpWidget(
        wrap(
          ResourceStudioPartCard(
            part: part,
            content: longContent,
            isActive: false,
            isValidating: false,
            hasError: false,
            onRetry: null,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.volume_up_rounded));
      await tester.pump();
      await tester.pump();

      expect(controller.state.segmentCount, greaterThan(100));
      expect(controller.state.currentText.length, lessThanOrEqualTo(140));
      expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
    });

    testWidgets('空正文不渲染朗读入口', (tester) async {
      await tester.pumpWidget(
        wrap(
          ResourceStudioPartCard(
            part: tree.parts.first,
            content: '   ',
            isActive: false,
            isValidating: false,
            hasError: false,
            onRetry: null,
          ),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.volume_up_rounded), findsNothing);
    });
  });

  group('ResourceStudioPage 连续朗读', () {
    testWidgets('提供全文连续朗读并把每个 Part 映射成一段', (tester) async {
      await tester.pumpWidget(studioApp());
      await tester.pumpAndSettle();

      expect(find.byTooltip('连续朗读全文'), findsOneWidget);
      await tester.tap(find.byTooltip('连续朗读全文'));
      await tester.pump();
      await tester.pump();

      expect(controller.state.sourceType, ReadAloudSourceType.studioResource);
      expect(controller.state.segmentCount, tree.parts.length);
      expect(
        controller.state.currentChunkId,
        ResourceStudioPartCard.readAloudIdFor(tree.parts.first),
      );
    });

    testWidgets('页面 dispose 会停止本页发起的朗读会话', (tester) async {
      await tester.pumpWidget(studioApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('连续朗读全文'));
      await tester.pump();
      await tester.pump();
      expect(controller.state.hasActiveSession, isTrue);

      // 离开页面：不能留下失控朗读任务。
      await tester.pumpWidget(studioShell(child: const SizedBox.shrink()));
      await tester.pump();
      await tester.pump();

      expect(controller.state.hasActiveSession, isFalse);
      expect(controller.state.status, ReadAloudStatus.stopped);
    });

    testWidgets('320px 窄屏下朗读入口不产生布局异常', (tester) async {
      for (final size in requiredUiViewports) {
        setViewport(tester, width: size.width, height: size.height);
        await tester.pumpWidget(studioApp());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '创作工作台在 $size 下不应有布局异常');
      }
    });
  });
}
