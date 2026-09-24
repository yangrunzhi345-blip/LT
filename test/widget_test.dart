import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/main.dart';

import 'helpers/responsive_test_helper.dart';

void main() {
  testWidgets('App smoke test initializes MyApp', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('LT Dialogue'), findsOneWidget);
  });

  group('Global error widget', () {
    for (final locale in <Locale>[
      const Locale('en'),
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    ]) {
      for (final size in requiredUiViewports) {
        testWidgets('hides framework details at $locale and $size',
            (tester) async {
          setViewport(tester, width: size.width, height: size.height);
          tester.binding.platformDispatcher.localesTestValue = <Locale>[locale];
          addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
          final details = FlutterErrorDetails(
            exception: StateError('private database token'),
            stack: StackTrace.fromString('private stack trace'),
          );

          await tester.pumpWidget(buildGlobalErrorWidget(details));
          await tester.pumpAndSettle();

          final l10n = lookupAppLocalizations(locale);
          expect(find.text(l10n.pageLoadError), findsOneWidget);
          expect(find.text(l10n.errorUnknown), findsOneWidget);
          expect(find.text(l10n.reloadAction), findsOneWidget);
          expect(find.textContaining('private'), findsNothing);
          expect(find.textContaining('StateError'), findsNothing);
          expect(find.textContaining('Exception:'), findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
