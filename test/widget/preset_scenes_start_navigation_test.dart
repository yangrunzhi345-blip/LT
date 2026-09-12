import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/controllers/adventure_template_controller.dart';
import 'package:lt_dialogue/controllers/resource_crud_controller.dart';
import 'package:lt_dialogue/core/router/app_router.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/features/adventure/presentation/templates/screens/preset_scenes_screen.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/app_section.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/providers/chat_provider.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/settings_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/world_entry_repository_impl.dart';

class _FakeResourceCrudController extends ResourceCrudController {
  _FakeResourceCrudController(this.templates)
      : super(
          repository:
              LibraryRepositoryImpl(getDb: () => DatabaseService.database),
        );

  final List<Map<String, dynamic>> templates;

  @override
  Future<List<Map<String, dynamic>>> loadAdventureTemplates({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    return templates;
  }
}

class _TestChatProvider extends ChatProvider {
  _TestChatProvider()
      : super.withRepos(
          adventureRepo:
              AdventureRepositoryImpl(getDb: () => DatabaseService.database),
          worldEntryRepo:
              WorldEntryRepositoryImpl(getDb: () => DatabaseService.database),
          libraryRepo:
              LibraryRepositoryImpl(getDb: () => DatabaseService.database),
          settingsRepo:
              SettingsRepositoryImpl(getDb: () => DatabaseService.database),
        );

  bool _mockChatOpen = false;

  @override
  bool get isKeyConfigured => true;

  @override
  bool get isAdventureChatOpen => _mockChatOpen;

  void setMockChatOpen(bool val) {
    _mockChatOpen = val;
    notifyListeners();
  }

  @override
  Future<int> startAdventureWithConfig(AdventureConfig c) async {
    _mockChatOpen = true;
    setCurrentSection(AppSection.adventure);
    notifyListeners();
    return 1;
  }
}

Map<String, dynamic> _createMockTemplate({
  String id = 'template-test-1',
  String name = '星际穿越探险',
  String worldviewName = '未来科幻',
  String worldviewDesc = '浩瀚的银河时代',
  String protagonistName = '舰长阿尔法',
}) {
  return {
    'id': id,
    'name': name,
    'worldview_name': worldviewName,
    'worldview_desc': worldviewDesc,
    'status': 'complete',
    'created_at': DateTime.now().toIso8601String(),
    'updated_at': DateTime.now().toIso8601String(),
    'char_data_json': jsonEncode({
      AdventureTemplateController.previewMarkerKey: true,
      'name': protagonistName,
      'worldview': worldviewDesc,
      'gender': '男',
      'age': '28',
      'protagonistClass': '指挥官',
      'protagonistBackground': '星际巡航舰队资深领航员',
      'openingScene': '警报声骤响，跃迁引擎发生轻微偏航。',
      'openingOptions': ['检查偏航数据', '联络领航副手'],
      'supportingCharacters': <dynamic>[],
    }),
  };
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    final messenger = TestWidgetsFlutterBinding.instance.defaultBinaryMessenger;
    for (final name in const [
      'dev.fluttercommunity.plus/connectivity',
      'dev.fluttercommunity.plus/connectivity_status',
    ]) {
      messenger.setMockMethodCallHandler(
          MethodChannel(name), (call) async => null);
    }
  });

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'deepseek_api_key': 'test', 'openai_api_key': 'test'});
    tempDir = await Directory.systemTemp.createTemp('lt_preset_nav_test_');
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

  Future<void> pumpPresetScenesScreen(
    WidgetTester tester, {
    required _TestChatProvider chatProviderInstance,
    required List<Map<String, dynamic>> templates,
    Future<void> Function(AdventureConfig config, {String? difficulty})?
        onStartAdventure,
  }) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final overrides = <Object>[
      chatProvider.overrideWith((ref) => chatProviderInstance),
      resourceCrudControllerProvider.overrideWith(
        (ref) => _FakeResourceCrudController(templates),
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides.cast(),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  key: const ValueKey('open_preset_scenes_button'),
                  onPressed: () {
                    AppRouter.push(
                      context,
                      pageBuilder: (_) => PresetScenesScreen(
                        onStartAdventure: onStartAdventure,
                      ),
                    );
                  },
                  child: const Text('打开预设场景页面'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Initial pump: Tap to open PresetScenesScreen
    await tester.tap(find.byKey(const ValueKey('open_preset_scenes_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('PresetScenesScreen Start Adventure Navigation & Pop Tests', () {
    testWidgets(
        'PresetScenesScreen pops route when custom onStartAdventure completes and chat is open',
        (tester) async {
      final chat = _TestChatProvider();
      final templates = [_createMockTemplate()];

      AdventureConfig? capturedConfig;
      Future<void> mockStart(AdventureConfig config,
          {String? difficulty}) async {
        capturedConfig = config;
        chat.setMockChatOpen(true);
      }

      await pumpPresetScenesScreen(
        tester,
        chatProviderInstance: chat,
        templates: templates,
        onStartAdventure: mockStart,
      );

      // Verify PresetScenesScreen is displayed with mock template
      expect(find.byType(PresetScenesScreen), findsOneWidget);
      expect(find.text('星际穿越探险'), findsOneWidget);

      // Tap 一键启程
      final startButton = find.text('一键启程');
      expect(startButton, findsOneWidget);
      await tester.tap(startButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify onStart was invoked
      expect(capturedConfig, isNotNull);
      expect(capturedConfig!.name, '舰长阿尔法');

      // Verify PresetScenesScreen is popped and no longer found on the Navigator stack
      expect(find.byType(PresetScenesScreen), findsNothing);
      expect(find.byKey(const ValueKey('open_preset_scenes_button')),
          findsOneWidget);
    });

    testWidgets(
        'PresetScenesScreen pops route when using chatProvider.startAdventureWithConfig fallback',
        (tester) async {
      final chat = _TestChatProvider();
      final templates = [_createMockTemplate()];

      await pumpPresetScenesScreen(
        tester,
        chatProviderInstance: chat,
        templates: templates,
        onStartAdventure: null, // Test default fallback
      );

      expect(find.byType(PresetScenesScreen), findsOneWidget);
      expect(find.text('星际穿越探险'), findsOneWidget);

      // Tap 一键启程
      final startButton = find.text('一键启程');
      expect(startButton, findsOneWidget);
      await tester.tap(startButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify chat provider state changed and screen popped
      expect(chat.isAdventureChatOpen, isTrue);
      expect(find.byType(PresetScenesScreen), findsNothing);
      expect(find.byKey(const ValueKey('open_preset_scenes_button')),
          findsOneWidget);
    });

    testWidgets(
        'PresetScenesScreen remains visible and shows error when onStartAdventure fails',
        (tester) async {
      final chat = _TestChatProvider();
      final templates = [_createMockTemplate()];

      Future<void> failingStart(AdventureConfig config,
          {String? difficulty}) async {
        throw StateError('Network connection failed');
      }

      await pumpPresetScenesScreen(
        tester,
        chatProviderInstance: chat,
        templates: templates,
        onStartAdventure: failingStart,
      );

      expect(find.byType(PresetScenesScreen), findsOneWidget);

      // Tap 一键启程
      final startButton = find.text('一键启程');
      expect(startButton, findsOneWidget);
      await tester.tap(startButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Should NOT pop when start fails
      expect(find.byType(PresetScenesScreen), findsOneWidget);
      expect(chat.isAdventureChatOpen, isFalse);

      // Verify error feedback is shown
      expect(find.text('启动预设场景失败，请稍后重试'), findsOneWidget);
    });

    testWidgets(
        'Detail modal 立即启程 dismisses bottom sheet and pops PresetScenesScreen',
        (tester) async {
      final chat = _TestChatProvider();
      final templates = [_createMockTemplate()];

      Future<void> mockStart(AdventureConfig config,
          {String? difficulty}) async {
        chat.setMockChatOpen(true);
      }

      await pumpPresetScenesScreen(
        tester,
        chatProviderInstance: chat,
        templates: templates,
        onStartAdventure: mockStart,
      );

      // Tap 详情
      final detailButton = find.text('详情');
      expect(detailButton, findsOneWidget);
      await tester.tap(detailButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify detail bottom sheet is visible with 立即启程
      final modalStartButton = find.text('立即启程');
      expect(modalStartButton, findsOneWidget);

      // Tap 立即启程
      await tester.tap(modalStartButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Verify PresetScenesScreen and bottom sheet are both popped
      expect(find.text('立即启程'), findsNothing);
      expect(find.byType(PresetScenesScreen), findsNothing);
      expect(find.byKey(const ValueKey('open_preset_scenes_button')),
          findsOneWidget);
    });

    testWidgets('While starting, secondary taps on 一键启程 are ignored',
        (tester) async {
      final chat = _TestChatProvider();
      final templates = [_createMockTemplate()];

      int invocationCount = 0;
      Future<void> slowStart(AdventureConfig config,
          {String? difficulty}) async {
        invocationCount++;
        // Simulate async in flight without finishing immediately
        await Future<void>.delayed(const Duration(milliseconds: 50));
        chat.setMockChatOpen(true);
      }

      await pumpPresetScenesScreen(
        tester,
        chatProviderInstance: chat,
        templates: templates,
        onStartAdventure: slowStart,
      );

      final startButton = find.text('一键启程');
      expect(startButton, findsOneWidget);

      // Tap once
      await tester.tap(startButton);
      await tester.pump(const Duration(milliseconds: 10));

      // Attempt second tap while first is in flight
      await tester.tap(startButton, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      // Verify onStartAdventure was only invoked once
      expect(invocationCount, 1);
      expect(find.byType(PresetScenesScreen), findsNothing);
    });
  });
}
