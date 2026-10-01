import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/screens/chat/widgets/message_bubble.dart';
import 'package:lt_dialogue/services/read_aloud/read_aloud_controller.dart';

import '../helpers/read_aloud_fakes.dart';
import '../helpers/responsive_test_helper.dart';

/// B/E — narrative reading typography and layout regressions.
void main() {
  Widget app(Widget child) => ProviderScope(
        overrides: [
          readAloudControllerProvider.overrideWith(
            (ref) => ReadAloudController(engine: FakeReadAloudEngine()),
            disposeNotifier: false,
          ),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      );

  Widget bubble(Message message, {double chatFontSize = 18}) => ListView(
        children: [
          AiBubble(
            message: message,
            chatFontSize: chatFontSize,
            brightness: Brightness.light,
            aiName: '旁白',
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

  testWidgets('narrative body renders at the configured size with wide leading',
      (tester) async {
    const content = '林恩走进银月城的北门，夜色在石板路上铺开。远处的钟楼敲响了第一声。';
    setViewport(tester, width: 390, height: 844);
    await tester.pumpWidget(app(bubble(
      Message(id: 'a1', content: content, isUser: false),
      chatFontSize: 18,
    )));
    await tester.pump();

    final text = tester.widget<Text>(find.text(content));
    expect(text.style?.fontSize, 18);
    expect(text.style?.height, greaterThanOrEqualTo(1.6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('long CJK narrative stays clean across required viewports',
      (tester) async {
    final longContent = List.filled(
      40,
      '她抬头望向远方的群山，风从峡谷深处吹来，带着松脂与湿土的气息。',
    ).join('\n');
    for (final viewport in requiredUiViewports) {
      setViewport(tester, width: viewport.width, height: viewport.height);
      await tester.pumpWidget(app(bubble(
        Message(id: 'a2', content: longContent, isUser: false),
      )));
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: 'reading overflow at $viewport');
    }
  });
}
