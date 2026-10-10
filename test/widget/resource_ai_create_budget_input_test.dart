import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_limits.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_ai_create_page.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Host-side widget tests for the AI-create target-word budget control.
///
/// These prove the typed value, the Slider and the submitted generation draft
/// all agree — the exact chain a device UI-automation run relies on. No device
/// and no real LLM are involved.
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('lt_ai_budget_input_test_');
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

  const inputKey = Key('ai_creation_target_words_input');
  const confirmKey = Key('ai_creation_target_words_confirm');
  const sliderKey = Key('ai-create-target-slider');
  const valueKey = Key('ai-create-target-value');

  Widget wrap(Widget home) => ProviderScope(
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          home: home,
        ),
      );

  Future<void> pumpPage(
    WidgetTester tester, {
    ResourceType type = ResourceType.worldview,
  }) async {
    await tester.pumpWidget(
      wrap(ResourceAiCreatePage(initialType: type)),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(inputKey));
    await tester.pumpAndSettle();
  }

  int sliderValue(WidgetTester tester) =>
      tester.widget<Slider>(find.byKey(sliderKey)).value.round();

  int shownValue(WidgetTester tester) {
    final text = tester.widget<Text>(find.byKey(valueKey)).data ?? '';
    return int.parse(RegExp(r'\d+').firstMatch(text)!.group(0)!);
  }

  String inputText(WidgetTester tester) {
    final widget = tester.widget<TextField>(
      find.descendant(
          of: find.byKey(inputKey), matching: find.byType(TextField)),
    );
    return widget.controller?.text ?? '';
  }

  Future<void> typeAndConfirm(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(inputKey), text);
    await tester.pump();
    await tester.tap(find.byKey(confirmKey));
    await tester.pumpAndSettle();
  }

  group('Test A — 8,000 budget', () {
    testWidgets('typing 8000 syncs Slider and the shown value', (tester) async {
      await pumpPage(tester);
      await typeAndConfirm(tester, '8000');

      expect(inputText(tester), '8000');
      expect(sliderValue(tester), 8000);
      expect(shownValue(tester), 8000);
      expect(tester.takeException(), isNull);
    });

    testWidgets('8000 reaches the submitted generation draft', (tester) async {
      final target = await _submitAndCaptureTarget(tester,
          type: ResourceType.worldview, budget: '8000');
      expect(target, 8000);
    });
  });

  group('Test B — 20,000 budget', () {
    testWidgets('typing 20000 syncs Slider and the shown value',
        (tester) async {
      await pumpPage(tester, type: ResourceType.character);
      await typeAndConfirm(tester, '20000');

      expect(inputText(tester), '20000');
      expect(sliderValue(tester), 20000);
      expect(shownValue(tester), 20000);
    });

    testWidgets('20000 reaches the submitted generation draft', (tester) async {
      final target = await _submitAndCaptureTarget(tester,
          type: ResourceType.character, budget: '20000');
      expect(target, 20000);
    });
  });

  group('Test C — boundaries and synchronization', () {
    testWidgets('below-minimum value clamps to the minimum', (tester) async {
      await pumpPage(tester);
      await typeAndConfirm(tester, '1');
      expect(sliderValue(tester),
          ResourceLimits.minimumGenerationTargetCharacters);
      expect(inputText(tester),
          '${ResourceLimits.minimumGenerationTargetCharacters}');
    });

    testWidgets('above-maximum value clamps to the type maximum',
        (tester) async {
      await pumpPage(tester, type: ResourceType.character);
      await typeAndConfirm(tester, '999999');
      expect(sliderValue(tester), ResourceLimits.characterNominalCharacters);
      expect(inputText(tester), '${ResourceLimits.characterNominalCharacters}');
    });

    testWidgets('empty value is rejected and the field reverts',
        (tester) async {
      await pumpPage(tester);
      await typeAndConfirm(tester, '9000');
      expect(sliderValue(tester), 9000);

      await typeAndConfirm(tester, '');
      expect(shownValue(tester), 9000,
          reason: 'invalid input never changes state');
      expect(inputText(tester), '9000');
      expect(find.text('请输入有效数字'), findsOneWidget);
    });

    testWidgets('non-numeric value is rejected and the field reverts',
        (tester) async {
      await pumpPage(tester);
      await typeAndConfirm(tester, '8000');
      await typeAndConfirm(tester, 'abc');
      expect(shownValue(tester), 8000);
      expect(inputText(tester), '8000');
      expect(find.text('请输入有效数字'), findsOneWidget);
    });

    testWidgets('negative value clamps to the minimum', (tester) async {
      await pumpPage(tester);
      await typeAndConfirm(tester, '-5');
      expect(sliderValue(tester),
          ResourceLimits.minimumGenerationTargetCharacters);
    });

    testWidgets('slider and input stay in two-way sync', (tester) async {
      await pumpPage(tester);
      // Slider -> input.
      await tester.drag(find.byKey(sliderKey), const Offset(-200, 0));
      await tester.pumpAndSettle();
      final afterDrag = sliderValue(tester);
      expect(afterDrag, lessThan(ResourceLimits.worldviewNominalCharacters));
      expect(inputText(tester), '$afterDrag');

      // Input -> slider. 13000 is on the 500-step grid.
      await typeAndConfirm(tester, '13000');
      expect(sliderValue(tester), 13000);
    });

    testWidgets('an off-grid typed value snaps to the step grid',
        (tester) async {
      await pumpPage(tester);
      await typeAndConfirm(tester, '12345');
      // 1000 + round((12345-1000)/500)*500 = 12500.
      expect(sliderValue(tester), 12500);
      expect(inputText(tester), '12500');
    });

    testWidgets('value survives a page rebuild (reference tab switch)',
        (tester) async {
      await pumpPage(tester);
      await typeAndConfirm(tester, '15000');
      await tester.tap(find.text('文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('粘贴'));
      await tester.pumpAndSettle();
      expect(sliderValue(tester), 15000);
      expect(inputText(tester), '15000');
    });

    testWidgets('type change clamps the typed value into the new domain',
        (tester) async {
      await tester.pumpWidget(wrap(const ResourceAiCreatePage()));
      await tester.pumpAndSettle();
      // Switch worldview -> character (nominal cap 20000).
      await tester.tap(find.text('世界观'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('角色').last);
      await tester.pumpAndSettle();
      expect(sliderValue(tester), ResourceLimits.characterNominalCharacters);

      // A worldview-sized value must clamp to the character cap.
      await tester.ensureVisible(find.byKey(inputKey));
      await tester.pumpAndSettle();
      await typeAndConfirm(tester, '45000');
      expect(sliderValue(tester), ResourceLimits.characterNominalCharacters);
      expect(tester.takeException(), isNull);
    });
  });
}

/// Pumps a launcher that opens [ResourceAiCreatePage], fills the required
/// fields, types [budget], submits and returns the captured target characters.
Future<int?> _submitAndCaptureTarget(
  WidgetTester tester, {
  required ResourceType type,
  required String budget,
}) async {
  ResourceStudioCreationDraft? captured;
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  captured = await Navigator.of(context)
                      .push<ResourceStudioCreationDraft>(
                    MaterialPageRoute<ResourceStudioCreationDraft>(
                      builder: (_) => ResourceAiCreatePage(initialType: type),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  await tester.enterText(
      find.byKey(const Key('ai-create-name-field')), '自动化预算测试资源');
  await tester.enterText(
      find.byKey(const Key('ai-create-paste-field')), '用于验证预算传递的参考资料。');
  await tester.pump();

  final input = find.byKey(const Key('ai_creation_target_words_input'));
  await tester.ensureVisible(input);
  await tester.enterText(input, budget);
  await tester.pump();
  await tester.tap(find.byKey(const Key('ai_creation_target_words_confirm')));
  await tester.pumpAndSettle();

  final submit = find.byKey(const Key('ai-create-submit-button'));
  await tester.ensureVisible(submit);
  await tester.pumpAndSettle();
  await tester.tap(submit);
  await tester.pumpAndSettle();
  return captured?.targetCharacters;
}
