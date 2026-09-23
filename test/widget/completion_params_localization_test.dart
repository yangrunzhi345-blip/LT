import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/widgets/app_dialogs.dart';

void main() {
  for (final locale in const [Locale('en'), Locale('ja')]) {
    testWidgets('completion parameter labels follow $locale', (tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showCompletionParamsDialog(context),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final l10n = lookupAppLocalizations(locale);
      expect(find.text(l10n.temperatureTitle), findsOneWidget);
      expect(find.text(l10n.topPTitle), findsOneWidget);
      expect(find.text(l10n.maxTokensTitle), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
