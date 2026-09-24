import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/l10n/generated/app_localizations.dart';

/// Wraps [home] in a [MaterialApp] that actually provides LT localizations.
///
/// Widget tests do not run through the app's `LocaleController`, so a bare
/// `MaterialApp` leaves `AppLocalizations.of(context)` null and any localized
/// widget throws. Widget tests that render production UI should pump through
/// this helper (or supply the same delegates themselves).
///
/// The default locale is Simplified Chinese so existing expectations keep
/// matching the repo's primary copy; pass [locale] to assert another language.
MaterialApp localizedApp({
  required Widget home,
  Locale locale = const Locale('zh'),
  ThemeData? theme,
  List<NavigatorObserver> navigatorObservers = const [],
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: theme,
    navigatorObservers: navigatorObservers,
    home: home,
  );
}

/// Localized [WidgetTester.pageBack].
///
/// `pageBack()` only recognises the English "Back" tooltip or a Cupertino back
/// button, so it never finds the back affordance of a localized app. This taps
/// the localized back tooltip instead and falls back to a Material `BackButton`.
Future<void> localizedPageBack(
  WidgetTester tester, {
  Locale locale = const Locale('zh'),
}) async {
  final tooltip = find.byTooltip(lookupAppLocalizations(locale).backAction);
  if (tooltip.evaluate().isNotEmpty) {
    await tester.tap(tooltip);
    return;
  }
  final materialBack = find.byType(BackButton);
  expect(materialBack, findsOneWidget, reason: 'One back button expected');
  await tester.tap(materialBack);
}
