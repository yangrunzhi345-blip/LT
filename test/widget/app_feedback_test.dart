import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/core/feedback/app_feedback.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';

import '../helpers/responsive_test_helper.dart';

/// Transient feedback must appear centred in the viewport — not as a bottom
/// SnackBar — while staying non-modal, accessible and single-instance.
void main() {
  const Key surfaceKey = Key('app-feedback-surface');
  const Key messageKey = Key('app-feedback-message');
  const Key actionKey = Key('app-feedback-action');

  Future<BuildContext> pumpHost(
    WidgetTester tester, {
    Size size = const Size(800, 600),
    ThemeMode themeMode = ThemeMode.light,
    double textScale = 1.0,
  }) async {
    setViewport(tester, width: size.width, height: size.height);
    late BuildContext host;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(builder: (context) {
            host = context;
            return const SizedBox.expand();
          }),
        ),
      ),
    );
    await tester.pump();
    return host;
  }

  Future<void> showAndSettle(WidgetTester tester, VoidCallback show) async {
    show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  Rect surfaceRect(WidgetTester tester) =>
      tester.getRect(find.byKey(surfaceKey));

  group('semantic types render one centred surface', () {
    for (final (label, show) in <(String, void Function(BuildContext, String))>[
      ('success', (c, m) => AppFeedback.success(c, m)),
      ('error', (c, m) => AppFeedback.error(c, m)),
      ('warning', (c, m) => AppFeedback.warning(c, m)),
      ('info', (c, m) => AppFeedback.info(c, m)),
    ]) {
      testWidgets('$label shows its message once', (tester) async {
        final host = await pumpHost(tester);
        await showAndSettle(tester, () => show(host, 'message-$label'));

        expect(find.byKey(surfaceKey), findsOneWidget);
        expect(find.text('message-$label'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('centred geometry', () {
    for (final size in const <Size>[
      Size(320, 568),
      Size(375, 812),
      Size(800, 600),
      Size(1280, 900),
    ]) {
      testWidgets('centred within 1px at ${size.width}x${size.height}',
          (tester) async {
        final host = await pumpHost(tester, size: size);
        await showAndSettle(tester, () => AppFeedback.success(host, 'Saved'));

        final viewSize =
            tester.view.physicalSize / tester.view.devicePixelRatio;
        final rect = surfaceRect(tester);
        expect(
            (rect.center.dx - viewSize.width / 2).abs(), lessThanOrEqualTo(1));
        expect(
            (rect.center.dy - viewSize.height / 2).abs(), lessThanOrEqualTo(1));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('desktop card is capped and not a full-width bar',
        (tester) async {
      final host = await pumpHost(tester, size: const Size(1280, 900));
      await showAndSettle(tester, () => AppFeedback.success(host, 'Saved'));

      final rect = surfaceRect(tester);
      expect(rect.width, lessThanOrEqualTo(480));
      expect(tester.takeException(), isNull);
    });

    testWidgets('320px card keeps a 16px side margin', (tester) async {
      final host = await pumpHost(tester, size: const Size(320, 568));
      await showAndSettle(tester, () => AppFeedback.success(host, 'Saved'));

      final rect = surfaceRect(tester);
      expect(rect.width, lessThanOrEqualTo(320 - 32));
      expect(rect.left, greaterThanOrEqualTo(16 - 0.5));
      expect(tester.takeException(), isNull);
    });
  });

  group('one at a time and auto-dismiss', () {
    testWidgets('identical message dedupes within the window', (tester) async {
      final host = await pumpHost(tester);
      await showAndSettle(tester, () => AppFeedback.info(host, 'Copied'));
      await showAndSettle(tester, () => AppFeedback.info(host, 'Copied'));

      expect(find.byKey(surfaceKey), findsOneWidget);
      expect(find.text('Copied'), findsOneWidget);
    });

    testWidgets('a new message replaces the current one', (tester) async {
      final host = await pumpHost(tester);
      await showAndSettle(tester, () => AppFeedback.info(host, 'First'));
      await showAndSettle(tester, () => AppFeedback.success(host, 'Second'));

      expect(find.byKey(surfaceKey), findsOneWidget);
      expect(find.text('First'), findsNothing);
      expect(find.text('Second'), findsOneWidget);
    });

    testWidgets('auto-dismisses after the default duration', (tester) async {
      final host = await pumpHost(tester);
      await showAndSettle(tester, () => AppFeedback.success(host, 'Saved'));
      expect(find.byKey(surfaceKey), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.byKey(surfaceKey), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('honours a custom short duration', (tester) async {
      final host = await pumpHost(tester);
      await showAndSettle(
          tester,
          () => AppFeedback.info(
                host,
                'Copied',
                duration: const Duration(milliseconds: 1200),
              ));

      await tester.pump(const Duration(milliseconds: 900));
      expect(find.byKey(surfaceKey), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.byKey(surfaceKey), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('action feedback', () {
    testWidgets('runs the action and dismisses', (tester) async {
      final host = await pumpHost(tester);
      var tapped = false;
      await showAndSettle(
        tester,
        () => AppFeedback.error(
          host,
          'Connection failed',
          actionLabel: 'Go to settings',
          onAction: () => tapped = true,
        ),
      );

      expect(find.byKey(actionKey), findsOneWidget);
      expect(find.byType(TextButton), findsOneWidget);

      await tester.tap(find.byKey(actionKey));
      await tester.pump();
      expect(tapped, isTrue);
      expect(find.byKey(surfaceKey), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('accessibility and layout', () {
    testWidgets('exposes a live-region semantic label', (tester) async {
      final host = await pumpHost(tester);
      await showAndSettle(tester, () => AppFeedback.success(host, 'Saved'));

      final semantics = tester.widget<Semantics>(find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.liveRegion == true,
      ));
      expect(semantics.properties.label, contains('Saved'));
    });

    testWidgets('long message wraps without clipping or overflow',
        (tester) async {
      final host = await pumpHost(tester, size: const Size(320, 568));
      const long = '这是一条非常长的本地化反馈消息用于验证窄屏下自动换行不会发生任何溢出或被截断的问题';
      await showAndSettle(tester, () => AppFeedback.warning(host, long));

      final rect = surfaceRect(tester);
      expect(rect.width, lessThanOrEqualTo(320 - 32));
      expect(rect.height, greaterThan(48));
      final text = tester.widget<Text>(find.byKey(messageKey));
      expect(text.maxLines, isNull);
      expect(text.overflow, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('holds up in dark theme', (tester) async {
      final host = await pumpHost(tester, themeMode: ThemeMode.dark);
      await showAndSettle(tester, () => AppFeedback.error(host, 'Failed'));
      expect(find.byKey(surfaceKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final scale in const <double>[1.0, 1.5, 2.0]) {
      testWidgets('no overflow at ${scale}x text scale', (tester) async {
        final host = await pumpHost(
          tester,
          size: const Size(320, 568),
          textScale: scale,
        );
        await showAndSettle(tester, () => AppFeedback.success(host, 'Saved'));
        expect(find.byKey(surfaceKey), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
