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

/// P0 regression: the Wizard must distinguish empty / error / partial-success
/// loading, and a poisoned legacy row must never take the other resources down.
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;
  late LibraryRepositoryImpl repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'openai_api_key': 'test', 'deepseek_api_key': 'test'});
    tempDir = await Directory.systemTemp.createTemp('lt_p0_wizard_test_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    repo = LibraryRepositoryImpl(getDb: () => DatabaseService.database);

    final now = DateTime.now().toIso8601String();
    await repo.saveWorldviewPreset(
      id: 'wv1',
      name: '星穹界',
      description: '机械与灵力交织的大陆',
      entriesJson: '[]',
      now: now,
    );
    await repo.saveWorldviewPreset(
      id: 'wv2',
      name: '荒海界',
      description: '沉船与潮汐的世界',
      entriesJson: '[]',
      now: now,
    );
    for (final entry in const [('char_ok1', '亚瑟'), ('char_ok2', '薇薇安')]) {
      await repo.saveCharacterCard(
        id: entry.$1,
        name: entry.$2,
        jsonData: jsonEncode({
          'data': {
            'name': entry.$2,
            'gender': '女',
            'age': '22',
            'profession': '学者',
          },
        }),
        source: '测试',
        now: now,
        matchingWorldviewId: 'wv1',
      );
    }
    // Legacy row whose json_data cannot be decoded.
    await repo.saveCharacterCard(
      id: 'char_bad',
      name: '损坏卡',
      jsonData: '{"data": {"name": "未闭合',
      source: 'PNG导入',
      now: now,
    );
    await repo.saveNpcCard(
      id: 'npc1',
      name: '酒馆老板',
      jsonData: jsonEncode({'name': '酒馆老板'}),
      source: '测试',
      now: now,
    );
    await repo.saveNpcCard(
      id: 'npc2',
      name: '巡逻卫兵',
      jsonData: jsonEncode({'name': '巡逻卫兵'}),
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
    tester.view.devicePixelRatio = 1;
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

  Future<void> goToStep(WidgetTester tester, int step) async {
    final stepper = tester.widget<Stepper>(find.byType(Stepper));
    stepper.onStepTapped!(step);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets(
      'wizard keeps usable resources selectable and reports the damaged row',
      (tester) async {
    await pumpWizardAt(tester, const Size(320, 568));

    // Worldview step: both worldviews remain selectable.
    expect(find.textContaining('星穹界'), findsWidgets);
    expect(find.textContaining('荒海界'), findsWidgets);
    expect(tester.takeException(), isNull);

    await goToStep(tester, 1);

    // Character step: two valid cards remain usable, the poisoned one is
    // reported instead of crashing the list. Chips render combined labels
    // ("名字 (职业) · 来源"), so match with textContaining.
    expect(find.textContaining('亚瑟'), findsWidgets);
    expect(find.textContaining('薇薇安'), findsWidgets);
    expect(find.textContaining('数据损坏'), findsOneWidget);
    expect(find.textContaining('损坏卡'), findsNothing);
    expect(tester.takeException(), isNull);

    await goToStep(tester, 2);

    // NPC step: still fully usable after the character row failure.
    expect(find.textContaining('酒馆老板'), findsWidgets);
    expect(find.textContaining('巡逻卫兵'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wizard shows no overflow on common phone viewports',
      (tester) async {
    const viewports = [
      Size(320, 568),
      Size(360, 640),
      Size(390, 844),
      Size(412, 915),
    ];
    for (final size in viewports) {
      await pumpWizardAt(tester, size);
      expect(tester.takeException(), isNull, reason: '$size should not throw');

      for (var step = 0; step < 4; step++) {
        await goToStep(tester, step);
        expect(tester.takeException(), isNull,
            reason: '$size step $step should not overflow');
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
