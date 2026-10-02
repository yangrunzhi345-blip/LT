import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_en.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/widgets/adventure_message_card.dart';

import '../helpers/responsive_test_helper.dart';

/// Geometry contract for the adventure options header.
///
/// The expand/collapse action must always sit at the right edge of the panel —
/// in the expanded and the collapsed state alike, across widths, text scales,
/// locales and themes. The old `Flexible` + `Spacer` + `MainAxisSize.min`
/// header left unused trailing space and pulled the action away from the edge,
/// and it drifted differently between the two states.
const Key _kPanel = Key('adventure-options-panel');
const Key _kHeader = Key('adventure-options-header');
const Key _kTitle = Key('adventure-options-title');
const Key _kExpand = Key('adventure-options-expand');
const Key _kCollapse = Key('adventure-options-collapse');

/// Both states pad their header 10 px from the panel edge.
const double _panelPadding = 10;
const double _tolerance = 1;

String _content(String tag, {List<String>? options, int count = 3}) {
  final list =
      options ?? List.generate(count, (i) => '「$tag」行动选项${i + 1}：验证折叠与右对齐');
  return '旅店老板擦拭着酒杯，压低了声音。\n'
      '---JSON---\n'
      '${jsonEncode({'scene': '旅店', 'options': list})}';
}

Future<void> _mount(
  WidgetTester tester, {
  required String tag,
  double width = 375,
  double height = 900,
  double scale = 1.0,
  bool dark = false,
  Locale locale = const Locale('zh'),
  List<String>? options,
  int count = 3,
  void Function(String)? onOptionTap,
}) async {
  setViewport(tester, width: width, height: height);
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: dark ? AppTheme.dark() : AppTheme.light(),
    builder: scale == 1.0
        ? null
        : (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
    home: Scaffold(
      body: AdventureMessageCard(
        jsonContent: _content(tag, options: options, count: count),
        brightness: dark ? Brightness.dark : Brightness.light,
        onOptionTap: onOptionTap,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Rect _rect(WidgetTester tester, Key key) => tester.getRect(find.byKey(key));

double _rightGap(WidgetTester tester, Key actionKey) =>
    _rect(tester, _kPanel).right - _rect(tester, actionKey).right;

/// Asserts the action's right edge is exactly [_panelPadding] inside the panel,
/// which is what "always on the header's right" means geometrically.
void _expectRightAligned(WidgetTester tester, Key actionKey, {String? reason}) {
  expect(find.byKey(_kHeader), findsOneWidget);
  final gap = _rightGap(tester, actionKey);
  expect(
    (gap - _panelPadding).abs(),
    lessThanOrEqualTo(_tolerance),
    reason: 'action right edge must be $_panelPadding px inside the panel '
        '${reason ?? ''} (got gap=$gap)',
  );
}

void main() {
  group('Options header right edge is a stable contract', () {
    for (final width in const <double>[320, 375, 600, 960, 1280]) {
      testWidgets('expand and collapse share one right edge at ${width}px',
          (tester) async {
        await _mount(tester, tag: 'geo$width', width: width);

        // Default is expanded.
        expect(find.byKey(_kCollapse), findsOneWidget);
        expect(find.byKey(_kExpand), findsNothing);
        _expectRightAligned(tester, _kCollapse, reason: 'expanded @$width');
        final expandedPanel = _rect(tester, _kPanel);
        final expandedActionRight = _rect(tester, _kCollapse).right;
        final expandedTitleLeft = _rect(tester, _kTitle).left;

        await tester.tap(find.byKey(_kCollapse));
        await tester.pumpAndSettle();

        expect(find.byKey(_kExpand), findsOneWidget);
        expect(find.byKey(_kCollapse), findsNothing);
        _expectRightAligned(tester, _kExpand, reason: 'collapsed @$width');
        final collapsedPanel = _rect(tester, _kPanel);
        final collapsedActionRight = _rect(tester, _kExpand).right;

        expect(
          (collapsedPanel.width - expandedPanel.width).abs(),
          lessThanOrEqualTo(_tolerance),
          reason: 'panel width must not change between states',
        );
        expect(
          (collapsedActionRight - expandedActionRight).abs(),
          lessThanOrEqualTo(_tolerance),
          reason: 'expand and collapse right edges must match',
        );
        expect(
          (_rect(tester, _kTitle).left - expandedTitleLeft).abs(),
          lessThanOrEqualTo(_tolerance),
          reason: 'title left edge must not move between states',
        );

        // Re-expanding restores the original geometry.
        await tester.tap(find.byKey(_kExpand));
        await tester.pumpAndSettle();
        expect(
          (_rect(tester, _kCollapse).right - expandedActionRight).abs(),
          lessThanOrEqualTo(_tolerance),
          reason: 're-expand must not jump',
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Text scale keeps the action pinned', () {
    for (final scale in const <double>[1.0, 1.5, 2.0]) {
      for (final width in const <double>[320, 375]) {
        testWidgets('${width}px at ${scale}x stays right-aligned',
            (tester) async {
          await _mount(tester,
              tag: 'scale-$width-$scale', width: width, scale: scale);
          _expectRightAligned(tester, _kCollapse,
              reason: 'expanded @${width}px ${scale}x');
          await tester.tap(find.byKey(_kCollapse));
          await tester.pumpAndSettle();
          _expectRightAligned(tester, _kExpand,
              reason: 'collapsed @${width}px ${scale}x');
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('Locales keep the action pinned', () {
    testWidgets('zh-Hans header stays right-aligned', (tester) async {
      final l10n = AppLocalizationsZh();
      for (final width in const <double>[320, 375]) {
        await _mount(tester, tag: 'zh$width', width: width);
        expect(find.text(l10n.collapseAction), findsOneWidget);
        _expectRightAligned(tester, _kCollapse, reason: 'zh expanded @$width');
        await tester.tap(find.byKey(_kCollapse));
        await tester.pumpAndSettle();
        expect(find.text(l10n.expandAction), findsOneWidget);
        _expectRightAligned(tester, _kExpand, reason: 'zh collapsed @$width');
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('english header stays right-aligned on narrow screens',
        (tester) async {
      final l10n = AppLocalizationsEn();
      for (final width in const <double>[320, 375]) {
        await _mount(tester,
            tag: 'en$width', width: width, locale: const Locale('en'));
        expect(find.text(l10n.collapseAction), findsOneWidget);
        _expectRightAligned(tester, _kCollapse, reason: 'en expanded @$width');
        await tester.tap(find.byKey(_kCollapse));
        await tester.pumpAndSettle();
        expect(find.text(l10n.expandAction), findsOneWidget);
        _expectRightAligned(tester, _kExpand, reason: 'en collapsed @$width');
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('Themes keep the action pinned', () {
    for (final dark in <bool>[false, true]) {
      testWidgets('${dark ? 'dark' : 'light'} theme', (tester) async {
        await _mount(tester, tag: 'theme-$dark', width: 375, dark: dark);
        _expectRightAligned(tester, _kCollapse, reason: 'expanded');
        await tester.tap(find.byKey(_kCollapse));
        await tester.pumpAndSettle();
        _expectRightAligned(tester, _kExpand, reason: 'collapsed');
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Option wrap never moves the header', () {
    testWidgets('three long options wrap without shifting the action',
        (tester) async {
      await _mount(tester, tag: 'long', width: 375, options: const [
        '深入幽暗的废弃矿坑，寻找失踪商队留下的补给与线索',
        '立刻返回旅店向老板询问关于魔物躁动的更多情报细节',
        '埋伏在村庄外围的高地，静待夜色中的敌人现身',
      ]);
      _expectRightAligned(tester, _kCollapse, reason: 'long options');
      await tester.tap(find.byKey(_kCollapse));
      await tester.pumpAndSettle();
      _expectRightAligned(tester, _kExpand, reason: 'long options collapsed');
      expect(tester.takeException(), isNull);
    });

    testWidgets('five options stay right-aligned', (tester) async {
      await _mount(tester, tag: 'five', width: 320, count: 5);
      _expectRightAligned(tester, _kCollapse, reason: '5 options');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a single short option stays right-aligned', (tester) async {
      await _mount(tester, tag: 'single', width: 375, options: const ['走']);
      _expectRightAligned(tester, _kCollapse, reason: 'single option');
      await tester.tap(find.byKey(_kCollapse));
      await tester.pumpAndSettle();
      _expectRightAligned(tester, _kExpand, reason: 'single option collapsed');
      expect(tester.takeException(), isNull);
    });
  });

  group('Header hit target and collapse behaviour', () {
    testWidgets('tapping the title toggles the whole header', (tester) async {
      await _mount(tester, tag: 'hittarget');
      await tester.tap(find.byKey(_kTitle));
      await tester.pumpAndSettle();
      expect(find.byKey(_kExpand), findsOneWidget,
          reason: 'whole header must be tappable, not only the action label');
      await tester.tap(find.byKey(_kTitle));
      await tester.pumpAndSettle();
      expect(find.byKey(_kCollapse), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('collapse hides options; expand restores them and taps work',
        (tester) async {
      final tapped = <String>[];
      await _mount(tester,
          tag: 'tap',
          options: const ['走向北门', '搜查地窖', '询问旅店老板'],
          onOptionTap: tapped.add);

      expect(find.text('搜查地窖'), findsOneWidget);
      await tester.tap(find.text('搜查地窖'));
      await tester.pump();
      expect(tapped, ['搜查地窖']);
      expect(find.byKey(_kCollapse), findsOneWidget,
          reason: 'selecting an option keeps the panel open');

      await tester.tap(find.byKey(_kCollapse));
      await tester.pumpAndSettle();
      expect(find.text('搜查地窖'), findsNothing,
          reason: 'collapsed shows only the header');
      expect(find.byKey(_kExpand), findsOneWidget);

      await tester.tap(find.byKey(_kExpand));
      await tester.pumpAndSettle();
      expect(find.text('搜查地窖'), findsOneWidget,
          reason: 'expanding restores the options');
      expect(tester.takeException(), isNull);
    });
  });
}
