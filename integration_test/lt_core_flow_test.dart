import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lt_dialogue/core/router/app_router.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_library_screen.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';

import 'support/lt_ui_driver.dart';
import 'support/lt_ui_keys.dart';

/// Device-scoped end-to-end entry point for LT's core business flow.
///
/// Run on a real device with:
///   flutter test integration_test/lt_core_flow_test.dart -d <deviceId>
///
/// It is **not** executed by `flutter test` (which skips `integration_test/`),
/// so no device is required to build or verify the host suite. The flow boots
/// the real app shell through the router, creates one lightweight setting card
/// through the library create action and opens its detail page. It needs no
/// model call, so the real-LLM dialogue turn stays on the manual device
/// checklist and is not claimed here.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('library boots and creates a setting card end to end',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          initialRoute: '/library',
          onGenerateRoute: AppRouter.onGenerateRoute,
        ),
      ),
    );

    // App boot: the router lands on the resource library workspace.
    final driver = LtUiDriver(tester);
    await driver.openLibrary();
    expect(find.byType(ResourceLibraryScreen), findsOneWidget);
    expect(find.byKey(LtUiKeys.libraryWorkspace), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Library -> create -> lightweight setting card (manual, no model call).
    const cardName = '自动化流程设定卡';
    await driver.openCreateFlow();
    await driver.waitForKey(LtUiKeys.settingCardCreateName);
    await driver.enterSettingCardName(cardName);
    await driver.createSettingCardManually();

    // The create page pops, the library reloads and opens the new card.
    await driver.waitForSettingCardDetail();
    expect(find.byKey(LtUiKeys.settingCardDetailName), findsOneWidget);
    expect(
      await driver.readFieldText(LtUiKeys.settingCardDetailName),
      cardName,
    );
    expect(tester.takeException(), isNull);

    // On narrow layouts the detail is a pushed route; return to the list so
    // the newly created card row is visible. Wide layouts embed it already.
    final navigator =
        tester.state<NavigatorState>(find.byType(Navigator).first);
    if (navigator.canPop()) {
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    expect(find.text(cardName), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
