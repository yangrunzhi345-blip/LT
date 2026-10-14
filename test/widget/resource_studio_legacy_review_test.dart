import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/part_contract_status.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/widgets/resource_studio_outline.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';

import '../helpers/responsive_test_helper.dart';

/// U6-D: the Studio outline shows the low-key legacy review hint ONLY for a
/// legacyUnknownContract Part, in every locale, without overflow.
void main() {
  const section = ResourceSection(
    id: SectionId('res_x_sec'),
    resourceId: ResourceId('res_x'),
    title: '章节',
    sortOrder: 0,
  );
  const part = ResourcePart(
    id: PartId('res_x_p0'),
    sectionId: SectionId('res_x_sec'),
    title: '段落',
    content: '两字',
    sortOrder: 0,
  );

  Widget wrap(
    Map<String, PartContractStatus> statuses, {
    Locale locale = const Locale('zh'),
    double textScale = 1,
  }) =>
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: ResourceStudioOutline(
            sections: const [section],
            parts: const [part],
            selectedPartId: null,
            onPartSelected: (_) {},
            partContractStatuses: statuses,
          ),
        ),
      );

  const legacyKey = ValueKey<String>('outline-legacy-review-res_x_p0');

  testWidgets('shows the legacy hint for legacyUnknownContract only',
      (tester) async {
    setViewport(tester, width: 390, height: 844);
    await tester.pumpWidget(
        wrap(const {'res_x_p0': PartContractStatus.legacyUnknownContract}));
    await tester.pumpAndSettle();
    expect(find.byKey(legacyKey), findsOneWidget);
    expect(find.text('内容完整性尚未确认'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final status in const [
    PartContractStatus.confirmedContract,
    PartContractStatus.notApplicable,
    PartContractStatus.unavailable,
  ]) {
    testWidgets('no hint for ${status.name}', (tester) async {
      setViewport(tester, width: 390, height: 844);
      await tester.pumpWidget(wrap({'res_x_p0': status}));
      await tester.pumpAndSettle();
      expect(find.byKey(legacyKey), findsNothing);
    });
  }

  testWidgets('no hint when no status is available', (tester) async {
    setViewport(tester, width: 390, height: 844);
    await tester.pumpWidget(wrap(const {}));
    await tester.pumpAndSettle();
    expect(find.byKey(legacyKey), findsNothing);
  });

  for (final scale in [1.0, 1.8]) {
    testWidgets('320px, textScale $scale: hint renders without overflow',
        (tester) async {
      setViewport(tester, width: 320, height: 568);
      await tester.pumpWidget(wrap(
        const {'res_x_p0': PartContractStatus.legacyUnknownContract},
        textScale: scale,
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(legacyKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the hint is localized in every supported locale',
      (tester) async {
    setViewport(tester, width: 390, height: 844);
    for (final locale in const [
      Locale('en'),
      Locale('ja'),
      Locale('ko'),
      Locale('zh'),
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    ]) {
      await tester.pumpWidget(wrap(
        const {'res_x_p0': PartContractStatus.legacyUnknownContract},
        locale: locale,
      ));
      await tester.pumpAndSettle();
      final expected =
          lookupAppLocalizations(locale).partContentIntegrityUnconfirmed;
      expect(expected.trim(), isNotEmpty, reason: locale.toString());
      expect(find.text(expected), findsOneWidget, reason: locale.toString());
      expect(tester.takeException(), isNull);
    }
  });
}
