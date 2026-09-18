import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/features/adventure/presentation/wizard/widgets/assembly_readiness_dialogs.dart';

import '../../helpers/responsive_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // An obviously over-long message: dynamic text must never break the layout.
  const longMessage = '「一个名字特别特别特别长的世界观资源名称示例」准备失败：原因信息也非常长，'
      '长到足以覆盖多行文本并测试对话框在小屏设备上的滚动与换行行为，'
      '以及中文与英文混排 The quick brown fox jumps over the lazy dog 0123456789。';

  Future<void> pumpBlockDialog(
    WidgetTester tester, {
    required double width,
    required double height,
  }) async {
    setViewport(tester, width: width, height: height);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  showAssemblyReadinessBlockDialog(
                    context,
                    const <String>['「测试世界观」正在组装准备，请稍候', longMessage],
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> pumpChoiceDialog(
    WidgetTester tester, {
    required double width,
    required double height,
  }) async {
    setViewport(tester, width: width, height: height);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  showStaleAssemblyChoiceDialog(
                    context,
                    const <String>['「测试世界观」已修改，可使用上一个已就绪版本', longMessage],
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('AssemblyReadiness dialogs stay usable at every required viewport', () {
    const viewports = <(double, double)>[
      (320, 568),
      (360, 640),
      (390, 844),
      (412, 915),
      (768, 1024),
    ];

    for (final (width, height) in viewports) {
      testWidgets('block dialog renders without overflow at $width×$height',
          (tester) async {
        await pumpBlockDialog(tester, width: width, height: height);
        expect(tester.takeException(), isNull);
        expect(find.text('暂时无法开始冒险'), findsOneWidget);
        expect(find.text('知道了'), findsOneWidget);
      });

      testWidgets(
          'choice dialog renders and both actions work at '
          '$width×$height', (tester) async {
        await pumpChoiceDialog(tester, width: width, height: height);
        expect(tester.takeException(), isNull);
        expect(find.text('使用上一个已就绪版本'), findsOneWidget);
        expect(find.text('取消'), findsOneWidget);

        await tester.tap(find.text('使用上一个已就绪版本'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('dialog content scrolls when text exceeds the viewport',
        (tester) async {
      await pumpBlockDialog(tester, width: 320, height: 568);
      await tester.scrollUntilVisible(
        find.text('知道了'),
        100,
        scrollable: find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(Scrollable),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
