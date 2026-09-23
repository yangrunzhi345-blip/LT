import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/features/adventure/presentation/wizard/screens/adventure_wizard_screen.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;
  late LibraryRepositoryImpl repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'openai_api_key': 'test',
      'deepseek_api_key': 'test',
    });
    tempDir = await Directory.systemTemp.createTemp('lt_wizard_resp_test_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    repo = LibraryRepositoryImpl(getDb: () => DatabaseService.database);

    final now = DateTime.now().toIso8601String();
    await repo.saveWorldviewPreset(
      id: 'wv_resp',
      name: '魔法大陆',
      description: '奇幻魔法大陆',
      entriesJson: '[]',
      now: now,
    );
    await repo.saveCharacterCard(
      id: 'char_resp_1',
      name: '艾丽娅',
      jsonData: jsonEncode({
        'data': {
          'name': '艾丽娅',
          'gender': '女',
          'age': '20',
          'profession': '魔法使',
        },
      }),
      source: '测试',
      now: now,
    );
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  Future<void> pumpWizardAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: AdventureWizardScreen(onStartAdventure: (_) async {}),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
      'AdventureWizardScreen adapts across supported compact viewports without overflow',
      (tester) async {
    const viewports = [
      Size(320, 568),
      Size(360, 640),
      Size(390, 844),
      Size(412, 915),
      Size(768, 1024),
    ];

    for (final viewport in viewports) {
      await pumpWizardAt(tester, viewport);

      expect(find.text('定制冒险向导'), findsOneWidget);
      for (int step = 0; step <= 4; step++) {
        final stepper = tester.widget<Stepper>(find.byType(Stepper));
        expect(
          stepper.type,
          equals(viewport.width < 600
              ? StepperType.vertical
              : StepperType.horizontal),
        );
        expect(stepper.onStepTapped, isNotNull);
        stepper.onStepTapped!(step);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        expect(tester.takeException(), isNull,
            reason: 'viewport: $viewport, step: $step');
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
      'AdventureWizardScreen adapts to desktop 1280px with horizontal Stepper and maxWidth constraint',
      (tester) async {
    await pumpWizardAt(tester, const Size(1280, 800));

    expect(find.text('定制冒险向导'), findsOneWidget);
    final stepper = tester.widget<Stepper>(find.byType(Stepper));
    expect(stepper.type, equals(StepperType.horizontal));

    // Verify maxWidth constraint
    final constrainedBoxFinder = find.ancestor(
      of: find.byType(Stepper),
      matching: find.byType(ConstrainedBox),
    );
    expect(constrainedBoxFinder, findsWidgets);
    final constrainedBox =
        tester.widget<ConstrainedBox>(constrainedBoxFinder.first);
    expect(constrainedBox.constraints.maxWidth, equals(1040));
    expect(tester.takeException(), isNull);
  });
}
