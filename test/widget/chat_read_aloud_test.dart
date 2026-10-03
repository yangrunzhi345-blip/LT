import 'package:lt_dialogue/core/widgets/app_read_aloud.dart';
import 'package:flutter/material.dart';
import 'package:lt_dialogue/core/widgets/app_svg_icon.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/domain/read_aloud/read_aloud_contracts.dart';
import 'package:lt_dialogue/domain/tts/speech_plan.dart';
import 'package:lt_dialogue/core/widgets/narrative_paragraph_read_view.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/screens/chat/widgets/message_bubble.dart';
import 'package:lt_dialogue/services/read_aloud/read_aloud_controller.dart';

import '../helpers/read_aloud_fakes.dart';
import '../helpers/responsive_test_helper.dart';
import '../helpers/tts_casting_fixture.dart';

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

  Widget app(Widget child, {double textScale = 1}) {
    return ProviderScope(
      overrides: [
        readAloudControllerProvider.overrideWith(
          (ref) => controller,
          disposeNotifier: false,
        ),
      ],
      child: MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!),
          home: Scaffold(body: child)),
    );
  }

  Widget aiBubbleWith(Message message,
      {required double chatFontSize,
      NarrativeSpeakerContext speakerContext =
          const NarrativeSpeakerContext.empty()}) {
    return ListView(
      children: [
        AiBubble(
          message: message,
          speakerContext: speakerContext,
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
    testWidgets(
        'should preserve character voices and paragraph ids at all viewports',
        (tester) async {
      const context = NarrativeSpeakerContext(speakers: [
        NarrativeSpeakerRef(resourceId: 'lin', displayName: '林雪'),
        NarrativeSpeakerRef(resourceId: 'chen', displayName: '陈默'),
      ]);
      final message = Message(
          id: 'speakers',
          isUser: false,
          content: '林雪说：“你好。”\n\n陈默说：“再见。”\n---JSON---\n{"options":[]}');
      for (final size in requiredUiViewports) {
        final casting = TtsCastingFixture();
        addTearDown(casting.dispose);
        controller = casting.controller;
        setViewport(tester, width: size.width, height: size.height);
        await tester.pumpWidget(app(
            aiBubbleWith(message, chatFontSize: 18, speakerContext: context),
            textScale: 1.5));
        await tester.pump();
        expect(find.byType(NarrativeParagraphReadView), findsOneWidget);
        await tester.tap(find.descendant(
            of: find.byType(AppReadAloudButton),
            matching: find.byType(IconButton)));
        await tester.pump();
        for (var i = 0; i < 4; i++) {
          casting.audio.emitComplete();
          await tester.pump();
        }
        // Ignore only the segmenter's documented boundary whitespace.
        final texts = casting.neural.synthesizedTexts
            .map((text) => text.replaceAll(RegExp(r'\s+'), ''))
            .toList();
        expect(texts, contains('“你好。”'));
        expect(texts, contains('“再见。”'));
        expect(casting.neural.synthesizedSpeakers[texts.indexOf('“你好。”')], 3);
        expect(casting.neural.synthesizedSpeakers[texts.indexOf('“再见。”')], 58);
        await tester.longPress(find.text('陈默说：“再见。”'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Read this paragraph'));
        await tester.pumpAndSettle();
        expect(controller.state.currentChunkId, 'chat:speakers#p1');
        expect(tester.takeException(), isNull, reason: '$size / large text');
        await controller.stop();
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets(
        'should distinguish repeated paragraph text when reading and highlighting',
        (tester) async {
      final message =
          Message(id: 'repeat', content: '重复正文。\n\n重复正文。', isUser: false);
      await tester.pumpWidget(app(aiBubble(message)));
      await tester.longPress(find.text('重复正文。').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Read this paragraph'));
      await tester.pumpAndSettle();
      expect(controller.state.currentChunkId, 'chat:repeat#p1');
      final active = tester.widget<AnimatedContainer>(find.ancestor(
          of: find.text('重复正文。').last,
          matching: find.byType(AnimatedContainer)));
      final inactive = tester.widget<AnimatedContainer>(find.ancestor(
          of: find.text('重复正文。').first,
          matching: find.byType(AnimatedContainer)));
      expect(active.decoration, isNotNull);
      expect(inactive.decoration, isNull);
      expect(tester.takeException(), isNull);
    });

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

      final button = find.byWidgetPredicate(
          (widget) => widget is AppSvgIcon && widget.name == 'read_aloud');
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

      await tester.tap(find.byWidgetPredicate(
          (widget) => widget is AppSvgIcon && widget.name == 'read_aloud'));
      await tester.pump();
      await tester.pump();

      expect(controller.state.status, ReadAloudStatus.playing);
      expect(
          find.descendant(
              of: find.byType(AppReadAloudButton),
              matching: find.byWidgetPredicate(
                  (widget) => widget is AppSvgIcon && widget.name == 'stop')),
          findsOneWidget);
    });

    testWidgets('正文为空时不渲染朗读入口', (tester) async {
      final message = Message(
        id: 'm3',
        content: '\n---JSON---\n{"hp":1}',
        isUser: false,
      );

      await tester.pumpWidget(app(aiBubble(message)));
      await tester.pump();

      expect(
          find.byWidgetPredicate(
              (widget) => widget is AppSvgIcon && widget.name == 'read_aloud'),
          findsNothing);
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
