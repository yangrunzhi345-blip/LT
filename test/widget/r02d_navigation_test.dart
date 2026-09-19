import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/screens/message_edit_page.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/screens/model_select_page.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/models/llm_provider.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/screens/chat/widgets/chat_dialogs.dart';
import 'package:lt_dialogue/screens/chat/widgets/inventory_screen.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/settings_repository.dart';
import '../helpers/responsive_test_helper.dart';

class _NavigationSettingsRepository implements ISettingsRepository {
  final _settings = <String, String>{};

  @override
  Future<int?> getSettingInt(String key) async =>
      int.tryParse(_settings[key] ?? '');

  @override
  Future<String?> getSetting(String key) async => _settings[key];

  @override
  Future<Map<String, String>> getAllSettings() async => Map.of(_settings);

  @override
  Future<Map<String, String>> getEncryptedApiKeys() async => {};

  @override
  Future<void> setSettings(Map<String, String> values) async =>
      _settings.addAll(values);

  @override
  Future<void> saveLlmConfiguration({
    required String provider,
    required String model,
    required String baseUrl,
    String? recentModels,
  }) async =>
      _settings.addAll({
        'llm_provider': provider,
        'llm_model': model,
        'llm_model_$provider': model,
        'api_base_url': baseUrl,
        if (recentModels != null) 'recent_models': recentModels,
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('lt_r02d_nav_test_');
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

  Widget createTestWidget(
      {required Widget child, ProviderContainer? container}) {
    return UncontrolledProviderScope(
      container: container ?? ProviderContainer(),
      child: MaterialApp(
        theme: AppTheme.light(),
        home: child,
      ),
    );
  }

  group('R02-D: ModelSelectPage Navigation & Switching Tests', () {
    testWidgets(
        'ModelSelectPage renders provider and recommends, switches model',
        (tester) async {
      final container = ProviderContainer(overrides: [
        settingsRepoProvider.overrideWithValue(_NavigationSettingsRepository()),
      ]);
      addTearDown(container.dispose);
      final chat = container.read(chatProvider);
      final selected = Completer<ModelSelectionResult>();

      await tester.pumpWidget(
        createTestWidget(
          container: container,
          child: ModelSelectPage(
            onModelSelected: (provider, model) => selected.complete(
              ModelSelectionResult(provider: provider, model: model),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('选择语言模型'), findsWidgets);
      expect(find.text('服务提供商'), findsOneWidget);
      expect(find.text('推荐在服模型'), findsOneWidget);
      expect(find.text('deepseek-flash'), findsWidgets);

      // 输入自定义模型
      await tester.enterText(
        find.byKey(const Key('custom-model-input')),
        'deepseek-reasoner',
      );
      await tester.pump();

      // 点击确认应用
      await tester.tap(find.byKey(const Key('model-select-confirm-button')));
      await tester
          .runAsync(() => selected.future.timeout(const Duration(seconds: 5)));
      await tester.pumpAndSettle();

      expect(chat.modelName, equals('deepseek-reasoner'));
    });

    testWidgets(
        'ModelSelectPage in regenerate mode triggers confirmation and pop',
        (tester) async {
      final container = ProviderContainer(overrides: [
        settingsRepoProvider.overrideWithValue(_NavigationSettingsRepository()),
      ]);
      addTearDown(container.dispose);

      final dummyMsg = Message(
        id: 'msg_1',
        content: '你好，开始冒险吧',
        isUser: true,
        timestamp: DateTime.now(),
      );
      final chat = container.read(chatProvider);
      chat.messages.add(dummyMsg);

      ModelSelectionResult? result;
      final completed = Completer<void>();

      await tester.pumpWidget(
        createTestWidget(
          container: container,
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await Navigator.of(context).push<ModelSelectionResult>(
                  MaterialPageRoute(
                    builder: (_) => ModelSelectPage(
                      isRegenerate: true,
                      message: dummyMsg,
                    ),
                  ),
                );
                completed.complete();
              },
              child: const Text('打开重算'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 打开页面
      await tester.tap(find.text('打开重算'));
      await tester.pumpAndSettle();

      expect(find.text('选择模型重新生成'), findsWidgets);
      expect(find.text('重新生成'), findsOneWidget);

      // 点击重新生成
      await tester.tap(find.byKey(const Key('model-select-confirm-button')));
      await tester
          .runAsync(() => completed.future.timeout(const Duration(seconds: 5)));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.provider, equals(LLMProvider.deepseek));
    });

    testWidgets('showModelSwitchMenu pushes ModelSelectPage as a route',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        createTestWidget(
          container: container,
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showModelSwitchMenu(context),
              child: const Text('打开模型菜单'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('打开模型菜单'));
      await tester.pumpAndSettle();

      // 验证打开的是全屏 ModelSelectPage 路由，而非旧 ModalBottomSheet
      expect(find.byType(ModelSelectPage), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    });
  });

  group('R02-D: MessageEditPage Navigation & Editing Tests', () {
    testWidgets('MessageEditPage loads initial text, edits and saves',
        (tester) async {
      String? savedText;

      final dummyMsg = Message(
        id: 'msg_user_1',
        content: '旧的用户指令内容',
        isUser: true,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(
        createTestWidget(
          child: MessageEditPage(
            message: dummyMsg,
            onSave: (val) => savedText = val,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('编辑你的消息'), findsWidgets);
      expect(find.text('旧的用户指令内容'), findsOneWidget);
      expect(find.textContaining('修改后将从该消息开始重新生成'), findsOneWidget);

      // 编辑文本
      await tester.enterText(
        find.byKey(const Key('message-edit-text-input')),
        '更新后的用户精细行动方案',
      );
      await tester.pump();

      // 点击保存
      await tester.tap(find.byKey(const Key('message-edit-save-button')));
      await tester.pumpAndSettle();

      expect(savedText, equals('更新后的用户精细行动方案'));
    });

    testWidgets('MessageEditPage validates empty text and prevents save',
        (tester) async {
      var saveCalled = false;

      final dummyMsg = Message(
        id: 'msg_ai_1',
        content: 'AI 回复内容',
        isUser: false,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(
        createTestWidget(
          child: MessageEditPage(
            message: dummyMsg,
            onSave: (_) => saveCalled = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('编辑 AI 回复'), findsWidgets);

      // 清空文本
      await tester.enterText(
        find.byKey(const Key('message-edit-text-input')),
        '   ',
      );
      await tester.pump();

      // 点击保存
      await tester.tap(find.byKey(const Key('message-edit-save-button')));
      await tester.pump();

      expect(saveCalled, isFalse);
    });

    testWidgets('showEditDialog pushes MessageEditPage as a route',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final chat = container.read(chatProvider);

      final dummyMsg = Message(
        id: 'msg_test',
        content: '测试消息内容',
        isUser: false,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(
        createTestWidget(
          container: container,
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showEditDialog(context, dummyMsg, chat),
              child: const Text('打开编辑'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('打开编辑'));
      await tester.pumpAndSettle();

      expect(find.byType(MessageEditPage), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('should retain a stale message instead of reporting a save',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final message = Message(id: 'stale', content: 'old', isUser: false);
      await tester.pumpWidget(createTestWidget(
        container: container,
        child: Builder(
            builder: (context) => FilledButton(
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => MessageEditPage(message: message),
                  )),
                  child: const Text('编辑'),
                )),
      ));
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('message-edit-text-input')), 'new');
      await tester.tap(find.byKey(const Key('message-edit-save-button')));
      await tester.pump();
      expect(find.byType(MessageEditPage), findsOneWidget);
      expect(find.textContaining('消息已不在当前对话'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('R02-D: Inventory Convergence Tests', () {
    testWidgets(
        'showInventorySheet pushes InventoryScreen page instead of bottom sheet',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        createTestWidget(
          container: container,
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  showInventorySheet(context, ['精铁长剑', '治疗药水'], false),
              child: const Text('打开背包'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('打开背包'));
      await tester.pumpAndSettle();

      // 验证推入的是全屏 InventoryScreen，而非旧的 ModalBottomSheet
      expect(find.byType(InventoryScreen), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    });
  });

  group('R02-D: Responsive Viewport Hard Gate (320px, 360px, 390px)', () {
    final viewports = requiredUiViewports;

    for (final size in viewports) {
      testWidgets(
          'ModelSelectPage and MessageEditPage render without overflow on $size',
          (tester) async {
        setViewport(tester, width: size.width, height: size.height);
        if (size.width == 320) {
          tester.view.platformDispatcher.textScaleFactorTestValue = 1.3;
          addTearDown(
              tester.view.platformDispatcher.clearTextScaleFactorTestValue);
        }

        final container = ProviderContainer();
        addTearDown(container.dispose);

        // 验证 ModelSelectPage
        await tester.pumpWidget(
          createTestWidget(
            container: container,
            child: const ModelSelectPage(
              initialModel:
                  'custom-provider-model-with-an-extremely-long-name-for-layout-regression',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        // 验证 MessageEditPage (长文本)
        final longMessage = Message(
          id: 'long_msg',
          content: '一段非常漫长的剧情叙述内容。' * 20,
          isUser: true,
          timestamp: DateTime.now(),
        );

        await tester.pumpWidget(
          createTestWidget(
            container: container,
            child: MessageEditPage(message: longMessage),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }
  });
}
