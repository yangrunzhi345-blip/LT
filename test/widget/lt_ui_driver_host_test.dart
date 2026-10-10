import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_limits.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_ai_create_page.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../integration_test/support/lt_ui_driver.dart';
import '../../integration_test/support/lt_ui_keys.dart';

/// Host-side validation of the shared UI-driver layer.
///
/// Proves the same [LtUiDriver] used by the device `integration_test` entry
/// works against the real AI-create page on the host: no coordinates, only
/// stable keys and bounded waits. This keeps the driver honest without a device.
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('lt_ui_driver_host_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  Future<LtUiDriver> pumpCreatePage(
    WidgetTester tester, {
    ResourceType type = ResourceType.character,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          home: ResourceAiCreatePage(initialType: type),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return LtUiDriver(tester);
  }

  testWidgets('driver sets 8000 and reads it back from input, Slider and value',
      (tester) async {
    final driver = await pumpCreatePage(tester);
    await driver.setTargetWords(8000);
    expect(await driver.readTargetWordsInput(), '8000');
    expect(await driver.readTargetSlider(), 8000);
    expect(await driver.readTargetWords(), 8000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('driver sets 20000 on a character resource', (tester) async {
    final driver = await pumpCreatePage(tester, type: ResourceType.character);
    await driver.setTargetWords(20000);
    expect(await driver.readTargetWordsInput(), '20000');
    expect(await driver.readTargetSlider(), 20000);
    expect(await driver.readTargetWords(), 20000);
  });

  testWidgets('driver rejects empty and non-numeric input without state change',
      (tester) async {
    final driver = await pumpCreatePage(tester, type: ResourceType.worldview);
    await driver.setTargetWords(12000);
    expect(await driver.readTargetWords(), 12000);

    await driver.enterTextKey(LtUiKeys.targetWordsInput, '');
    await driver.tapKey(LtUiKeys.targetWordsConfirm);
    expect(await driver.readTargetWords(), 12000);

    await driver.enterTextKey(LtUiKeys.targetWordsInput, 'xyz');
    await driver.tapKey(LtUiKeys.targetWordsConfirm);
    expect(await driver.readTargetWords(), 12000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('driver clamps an over-range value to the type maximum',
      (tester) async {
    final driver = await pumpCreatePage(tester, type: ResourceType.character);
    await driver.setTargetWords(999999);
    expect(await driver.readTargetWords(),
        ResourceLimits.characterNominalCharacters);
    expect(await driver.readTargetSlider(),
        ResourceLimits.characterNominalCharacters);
  });

  testWidgets('driver times out with a diagnostic on a missing key',
      (tester) async {
    final driver = LtUiDriver(
      tester,
      defaultTimeout: const Duration(milliseconds: 300),
      pumpInterval: const Duration(milliseconds: 20),
    );
    await pumpCreatePage(tester);
    Object? caught;
    try {
      await driver.waitForKey(const Key('definitely-not-present'));
    } catch (error) {
      caught = error;
    }
    expect(caught, isA<LtUiTimeoutException>());
    expect(caught.toString(), contains('definitely-not-present'));
  });
}
