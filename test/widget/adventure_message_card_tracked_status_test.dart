import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/widgets/adventure_message_card.dart';

import '../helpers/responsive_test_helper.dart';

/// The assistant narrative body must show, in order:
///   prose → this turn's monitored state → options.
///
/// The block is rendered from the persisted `custom_status` snapshot, so a
/// historical turn always shows the value settled at that turn — never a live
/// read of the current runtime overlay.
void main() {
  final zh = AppLocalizationsZh();

  String contentWith(List<Map<String, dynamic>> customStatus,
      {List<String> options = const ['继续', '等待']}) {
    return '她停下脚步，望向远处的山脊。\n'
        '---JSON---\n'
        '${jsonEncode({
          'options': options,
          'custom_status': customStatus,
        })}';
  }

  Map<String, dynamic> numeric(String id, String name, int cur, int max,
          {required String characterName}) =>
      {
        'id': id,
        'name': name,
        'value': '$cur/$max',
        'currentValue': cur,
        'maxValue': max,
        'characterName': characterName,
        'value_kind': 'integer',
      };

  Map<String, dynamic> untriggered(String id, String name,
          {required String characterName}) =>
      {
        'id': id,
        'name': name,
        'value': '',
        'characterName': characterName,
        'untriggered': true,
        'value_kind': 'integer',
      };

  Future<void> pumpCard(WidgetTester tester, String content,
      {double width = 420,
      double height = 900,
      double scale = 1.0,
      Brightness brightness = Brightness.light,
      void Function(String)? onOptionTap}) async {
    setViewport(tester, width: width, height: height);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: AdventureMessageCard(
            jsonContent: content,
            brightness: brightness,
            onOptionTap: onOptionTap,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('Case A: rendered as narrative → status → options, in order',
      (tester) async {
    await pumpCard(
        tester,
        contentWith([
          numeric('curse', '精神污染', 18, 100, characterName: '林澈'),
        ]));

    expect(find.text('她停下脚步，望向远处的山脊。'), findsOneWidget);
    expect(find.text('精神污染'), findsOneWidget);
    expect(find.text('18/100'), findsOneWidget);
    expect(find.text('林澈'), findsOneWidget);

    // Strict ordering: prose above the status block above the options block.
    final narrativeY = tester.getTopLeft(find.text('她停下脚步，望向远处的山脊。')).dy;
    final statusY = tester.getTopLeft(find.text('精神污染')).dy;
    final optionsY =
        tester.getTopLeft(find.textContaining(zh.optionsSectionTitle(2))).dy;
    expect(narrativeY, lessThan(statusY));
    expect(statusY, lessThan(optionsY));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Case B: a definition with no value shows「尚未触发」', (tester) async {
    await pumpCard(
        tester,
        contentWith([
          untriggered('trust', '信任度', characterName: '林澈'),
        ]));

    expect(find.text('信任度'), findsOneWidget);
    expect(find.text(zh.trackedStateUntriggered), findsWidgets);
    expect(find.text('0/100'), findsNothing);
    expect(find.text('0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Case C: two characters keep their own values', (tester) async {
    await pumpCard(
        tester,
        contentWith([
          numeric('fear', '恐惧', 20, 100, characterName: 'Alice'),
          numeric('fear', '恐惧', 70, 100, characterName: 'Bob'),
        ]));

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('20/100'), findsOneWidget);
    expect(find.text('70/100'), findsOneWidget);
    expect(find.text('恐惧'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('boolean shows localized yes / no', (tester) async {
    await pumpCard(
        tester,
        contentWith([
          {
            'id': 'wounded',
            'name': '受伤状态',
            'value': 'true',
            'characterName': '林澈',
            'value_kind': 'boolean',
          },
        ]));

    expect(find.text('受伤状态'), findsOneWidget);
    expect(find.text(zh.trackedStateBoolYes), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Case E: each historical turn keeps its own snapshot value',
      (tester) async {
    final roundOne =
        contentWith([numeric('fear', '恐惧', 20, 100, characterName: '林澈')]);
    final roundTwo =
        contentWith([numeric('fear', '恐惧', 40, 100, characterName: '林澈')]);

    setViewport(tester, width: 420, height: 900);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              AdventureMessageCard(
                  jsonContent: roundOne, brightness: Brightness.light),
              AdventureMessageCard(
                  jsonContent: roundTwo, brightness: Brightness.light),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Round 1 still reads 20; round 2 reads 40. No live-runtime bleed.
    expect(find.text('20/100'), findsOneWidget);
    expect(find.text('40/100'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Case G: a legacy custom_status message still renders',
      (tester) async {
    await pumpCard(
        tester,
        contentWith([
          {'name': 'SAN值', 'value': '60/100'},
        ]));

    expect(find.text('SAN值'), findsOneWidget);
    expect(find.text('60/100'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no block is rendered when custom_status is absent',
      (tester) async {
    await pumpCard(tester, '只有正文。\n---JSON---\n${jsonEncode({'options': []})}');

    expect(find.text('只有正文。'), findsOneWidget);
    expect(find.text(zh.trackedStateUntriggered), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('typed text presentation', () {
    Map<String, dynamic> status(String value,
            {String kind = 'text', bool isUntriggered = false}) =>
        {
          'id': 'thought',
          'name': '心声',
          'value': value,
          'characterName': '林澈',
          'value_kind': kind,
          'untriggered': isUntriggered,
        };

    void expectFullText(WidgetTester tester, String value) {
      final finder = find.text(value);
      expect(finder, findsOneWidget);
      final text = tester.widget<Text>(finder);
      expect(text.maxLines, isNull);
      expect(text.softWrap, isNot(false));
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      final paragraph = tester.renderObject<RenderParagraph>(finder);
      expect(paragraph.didExceedMaxLines, isFalse);
      final rect = tester.getRect(finder);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(tester.view.physicalSize.width));
      expect(rect.top, greaterThan(tester.getRect(find.text('心声')).bottom));
      // The body spans the item, rather than sharing a narrow chip row.
      expect(rect.width, greaterThan(tester.view.physicalSize.width - 100));
    }

    const longText = '澈已落帆掉头脱离浪线，十五米测绳被啃断，她正带着断头返港，'
        '我让她关灯慢行，在蓝港内港东闸等她。';

    for (final value in ['她还没有回来。', longText, '第一行\n第二行\n第三行', '123/456']) {
      testWidgets('should display complete typed text: $value', (tester) async {
        await pumpCard(tester, contentWith([status(value)]), width: 320);
        expectFullText(tester, value);
        if (value == longText) {
          expect(
              tester
                  .renderObject<RenderParagraph>(find.text(value))
                  .getBoxesForSelection(
                      TextSelection(baseOffset: 0, extentOffset: value.length))
                  .length,
              greaterThan(1));
        } else if (value.contains('\n')) {
          expect(
              tester
                  .renderObject<RenderParagraph>(find.text(value))
                  .getBoxesForSelection(
                      TextSelection(baseOffset: 0, extentOffset: value.length))
                  .length,
              3);
        }
        expect(tester.takeException(), isNull);
      });
    }

    for (final (kind, value, label, isUntriggered) in [
      ('enumValue', '高度戒备', '高度戒备', false),
      ('boolean', 'true', zh.trackedStateBoolYes, false),
      ('text', '', zh.trackedStateUntriggered, true),
    ]) {
      testWidgets('should retain compact $kind / untriggered=$isUntriggered',
          (tester) async {
        await pumpCard(
            tester,
            contentWith([
              status(value, kind: kind, isUntriggered: isUntriggered),
            ]));
        final text = tester.widget<Text>(find.text(label));
        expect(text.maxLines, 1);
        expect(text.overflow, TextOverflow.ellipsis);
        expect(tester.getTopLeft(find.text(label)).dy,
            closeTo(tester.getTopLeft(find.text('心声')).dy, 4));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('should retain a single-line collapsed summary and reopen全文',
        (tester) async {
      await pumpCard(tester, contentWith([status(longText)]));
      await tester.tap(find.text(zh.monitoredStatus));
      await tester.pumpAndSettle();
      expect(find.text(longText), findsNothing);
      final summary = find.textContaining('林澈·心声');
      expect(tester.widget<Text>(summary).maxLines, 1);
      expect(tester.widget<Text>(summary).overflow, TextOverflow.ellipsis);
      await tester.tap(summary);
      await tester.pumpAndSettle();
      expectFullText(tester, longText);
      expect(tester.takeException(), isNull);
    });

    for (final size in requiredUiViewports) {
      for (final scale in [1.0, 1.6, 2.0]) {
        for (final brightness in [Brightness.light, Brightness.dark]) {
          testWidgets(
              'should wrap full text at ${size.width} @ $scale $brightness',
              (tester) async {
            // More than ten lines and an explicit final line exercise natural
            // height, preservation of newlines and the bottom of a long item.
            final value = '${List.filled(12, longText).join('\n')}\n最后一行。';
            String? selected;
            await pumpCard(tester, contentWith([status(value)]),
                width: size.width,
                height: size.height,
                scale: scale,
                brightness: brightness,
                onOptionTap: (option) => selected = option);
            expectFullText(tester, value);
            final paragraph =
                tester.renderObject<RenderParagraph>(find.text(value));
            final lines = paragraph.getBoxesForSelection(
                TextSelection(baseOffset: 0, extentOffset: value.length));
            expect(lines.length, greaterThan(12));
            expect(lines.last.bottom,
                lessThanOrEqualTo(paragraph.size.height + 0.01));
            final scrollable = find.byType(Scrollable).first;
            final scrollState = tester.state<ScrollableState>(scrollable);
            final rect = tester.getRect(find.text(value));
            scrollState.position.jumpTo((rect.bottom - size.height / 2)
                .clamp(0, scrollState.position.maxScrollExtent));
            await tester.pumpAndSettle();
            expect(tester.getRect(find.text(value)).bottom,
                inInclusiveRange(0, size.height));
            await tester.ensureVisible(find.text('继续'));
            await tester.tap(find.text('继续'));
            await tester.pumpAndSettle();
            expect(selected, '继续');
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  group('responsive', () {
    for (final size in requiredUiViewports) {
      for (final scale in const <double>[1.0, 1.6, 2.0]) {
        testWidgets(
            'no overflow at ${size.width.toInt()}x${size.height.toInt()} @${scale}x',
            (tester) async {
          await pumpCard(
            tester,
            contentWith([
              numeric('curse', '精神污染', 18, 100, characterName: '林澈'),
              untriggered('trust', '信任度', characterName: '林澈'),
              numeric('fear', '一个很长很长的检测状态名称用于验证省略号', 70, 100,
                  characterName: '一位名字非常长的角色'),
            ]),
            width: size.width,
            height: size.height,
            scale: scale,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
