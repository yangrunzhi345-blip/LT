import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/features/settings/presentation/widgets/provider_config_section.dart';
import 'package:lt_dialogue/models/llm_provider.dart';
import 'package:lt_dialogue/services/database_service.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_model_picker_');
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

  Future<void> pumpSection(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: SingleChildScrollView(child: ProviderConfigSection()),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('Model picker catalog', () {
    testWidgets('offers only the recommended V4.1 Flash model on desktop',
        (tester) async {
      await pumpSection(tester, const Size(1280, 800));

      expect(find.text('选择在服模型'), findsOneWidget);
      expect(
        find.text('DeepSeek V4.1 Flash 最新推荐 · 多模态 · 支持深度思考'),
        findsOneWidget,
      );
      // The retired model is not advertised anywhere in the section.
      expect(find.textContaining('deepseek-v4-pro'), findsNothing);
      expect(find.textContaining('V4 极速叙事'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('picker model list is capability-driven', (tester) async {
      // The picker source must reflect the registry's selectable models.
      expect(LLMProvider.deepseek.availableModels, ['deepseek-flash']);
      expect(LLMProvider.deepseek.defaultModel, 'deepseek-flash');
      expect(LLMProvider.deepseek.knownModels, contains('deepseek-v4-pro'));
    });

    testWidgets('no layout overflow at 320px and 390px widths', (tester) async {
      for (final size in const [Size(320, 568), Size(390, 844)]) {
        await pumpSection(tester, size);
        expect(tester.takeException(), isNull,
            reason: 'unexpected overflow/exception at ${size.width}px');
      }
    });
  });
}
