import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/domain/read_aloud/read_aloud_contracts.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/screens/chat/widgets/message_bubble.dart';
import 'package:lt_dialogue/services/read_aloud/read_aloud_controller.dart';

import '../helpers/read_aloud_fakes.dart';
import '../helpers/responsive_test_helper.dart';

void main() {
  late FakeReadAloudEngine engine;
  late ReadAloudController controller;

  setUp(() {
    engine = FakeReadAloudEngine();
    controller = ReadAloudController(
      engine: engine,
      initialPreferences: const ReadAloudPreferences(enabled: true),
    );
  });

  Widget app(Widget child) {
    return ProviderScope(
      overrides: [
        readAloudControllerProvider.overrideWith(
          (ref) => controller,
          disposeNotifier: false,
        ),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  Widget aiBubbleWith(Message message, {required double chatFontSize}) {
    return ListView(
      children: [
        AiBubble(
          message: message,
          chatFontSize: chatFontSize,
          brightness: Brightness.light,
          aiName: 'LT',
          emotion: '',
          isBookmarked: false,
          onLongPress: () {},
          onRegenerate: () {},
          onDelete: () {},
          onToggleBookmark: () {},
          onOptionTap: (_) {},
        ),
      ],
    );
  }

  Widget aiBubble(Message message) => aiBubbleWith(message, chatFontSize: 14);

  group('Chat AI 消息朗读', () {
    testWidgets('朗读入口存在，且只朗读可见叙事正文', (tester) async {
      final message = Message(
        id: 'm1',
        content: '灯塔亮了，潮声压过街巷。\n---JSON---\n'
            '{"options":["前进","观察"],"hp":10}',
        reasoningContent: '这里是不该被朗读的思维链',
        isUser: false,
      );

      await tester.pumpWidget(app(aiBubble(message)));
      await tester.pump();

      final button = find.byIcon(Icons.volume_up_rounded);
      expect(button, findsOneWidget);

      await tester.tap(button);
      await tester.pump();
      await tester.pump();

      final spoken = engine.spokenTexts.join();
      expect(spoken, contains('灯塔亮了'));
      expect(spoken, isNot(contains('options')));
      expect(spoken, isNot(contains('hp')));
      expect(spoken, isNot(contains('---JSON---')));
      expect(spoken, isNot(contains('不该被朗读')));
      expect(controller.state.sourceType, ReadAloudSourceType.chat);
      expect(controller.state.sourceId, 'chat:m1');
    });

    testWidgets('点击后图标变为停止，说明状态来自全局 Authority', (tester) async {
      final message = Message(
        id: 'm2',
        content: '只有叙事正文。',
        isUser: false,
      );

      await tester.pumpWidget(app(aiBubble(message)));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.volume_up_rounded));
      await tester.pump();
      await tester.pump();

      expect(controller.state.status, ReadAloudStatus.playing);
      expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
    });

    testWidgets('正文为空时不渲染朗读入口', (tester) async {
      final message = Message(
        id: 'm3',
        content: '\n---JSON---\n{"hp":1}',
        isUser: false,
      );

      await tester.pumpWidget(app(aiBubble(message)));
      await tester.pump();

      expect(find.byIcon(Icons.volume_up_rounded), findsNothing);
    });

    testWidgets('320px 窄屏下 AI 气泡与朗读入口无布局异常', (tester) async {
      final message = Message(
        id: 'm4',
        content: '这是一段用于验证窄屏布局的较长叙事正文，'
            '需要确认消息气泡、底部操作栏与朗读入口在极窄宽度下都不会溢出。'
            '\n---JSON---\n{"options":["前进","观察","等待"]}',
        isUser: false,
      );

      for (final size in requiredUiViewports) {
        setViewport(tester, width: size.width, height: size.height);
        await tester.pumpWidget(app(aiBubbleWith(message, chatFontSize: 18)));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'AI 气泡在 $size 下不应有布局异常');
      }
    });
  });
}
