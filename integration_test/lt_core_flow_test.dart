import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lt_dialogue/core/router/app_router.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_limits.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_ai_create_page.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';

import 'support/lt_ui_driver.dart';
import 'support/lt_ui_keys.dart';
import 'support/scripted_llm_gateway.dart';

/// Device-scoped end-to-end entry point for LT's core business flow.
///
/// Run on a real device with:
///   flutter test integration_test/lt_core_flow_test.dart -d <deviceId>
///
/// It is **not** executed by `flutter test` (which skips `integration_test/`),
/// so no device is required to build or verify the host suite. The device run
/// uses the real SQLite/Android path with a deterministic model double
/// ([ScriptedLlmGateway]); the real-LLM dialogue turn stays on the manual device
/// checklist and is not claimed here.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Widget wrapWithLocalizations(Widget child) => MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      );

  Future<LtUiDriver> pumpBudgetPage(WidgetTester tester,
      {ResourceType type = ResourceType.character}) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: wrapWithLocalizations(ResourceAiCreatePage(initialType: type)),
      ),
    );
    return LtUiDriver(tester);
  }

  group('Test A/B — budget typed through the numeric input (driver)', () {
    for (final budget in <int>[8000, 20000]) {
      testWidgets('$budget reaches the input, the Slider and the shown value',
          (tester) async {
        final driver = await pumpBudgetPage(tester);

        await driver.setTargetWords(budget);
        expect(await driver.readTargetWordsInput(), '$budget');
        expect(await driver.readTargetSlider(), budget);
        expect(await driver.readTargetWords(), budget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Test C — budget boundaries (driver)', () {
    testWidgets('out-of-range and non-numeric values never change the state',
        (tester) async {
      final driver = await pumpBudgetPage(tester, type: ResourceType.worldview);

      await driver.setTargetWords(9000);
      expect(await driver.readTargetWords(), 9000);

      // Empty is rejected; the field reverts and the state is unchanged.
      await driver.enterTextKey(LtUiKeys.targetWordsInput, '');
      await driver.tapKey(LtUiKeys.targetWordsConfirm);
      expect(await driver.readTargetWords(), 9000);

      // Non-numeric is rejected the same way.
      await driver.enterTextKey(LtUiKeys.targetWordsInput, 'abc');
      await driver.tapKey(LtUiKeys.targetWordsConfirm);
      expect(await driver.readTargetWords(), 9000);

      // A value above the cap clamps to the maximum.
      await driver.setTargetWords(999999);
      expect(await driver.readTargetWords(),
          ResourceLimits.worldviewNominalCharacters);
      expect(tester.takeException(), isNull);
    });
  });

  group('Test D — creation flow to the Studio (device entry)', () {
    testWidgets('worldview creation reaches the Studio with the typed budget',
        (tester) async {
      final container = ProviderContainer(
        overrides: [llmGatewayProvider.overrideWithValue(ScriptedLlmGateway())],
      );
      addTearDown(container.dispose);
      await tester.runAsync(
          () => container.read(settingsProvider).setApiKey('test-only-key'));

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
      final driver = LtUiDriver(tester);
      await driver.openLibrary();
      await driver.openCreateFlow();
      await driver.chooseAiCreate();
      await driver.enterResourceName('自动化流程资源');
      await driver.enterReference('用于自动化流程验证的参考资料。');
      await driver.setTargetWords(8000);
      await driver.submitCreate();
      await driver.waitForStudio();
      expect(tester.takeException(), isNull);
    });
  });
}
