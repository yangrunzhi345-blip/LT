import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/controllers/resource_crud_controller.dart';
import 'package:lt_dialogue/core/router/app_router.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/features/adventure/presentation/templates/screens/preset_scenes_screen.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/providers/chat_provider.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/settings_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/world_entry_repository_impl.dart';

/// P0 回归：预存场景工坊的「一键启程」必须在冒险创建成功后立即退出本页。
///
/// 真实缺陷是 [PresetScenesScreen] 由 `AppRouter.push` 推成独立 Route，冒险创建
/// 成功后 ChatProvider 已经把 `isAdventureChatOpen` 置为 true，但本页没有 pop，
/// 于是用户仍停留在预存场景工坊，看不到底层已经切好的对话页。
///
/// 因此这里的断言必须是**导航结果**（Route 被移除 + 底层对话页可见），而不是
/// 「callback 被调用过」。
class _QuickStartChatProvider extends ChatProvider {
  _QuickStartChatProvider({this.failStart = false})
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

  final bool failStart;
  int startCalls = 0;
  AdventureConfig? lastStartedConfig;
  bool _isOpen = false;

  @override
  bool get isKeyConfigured => true;

  @override
  bool get isAdventureChatOpen => _isOpen;

  @override
  Future<int> startAdventureWithConfig(AdventureConfig c) async {
    startCalls++;
    lastStartedConfig = c;
    if (failStart) throw StateError('start-adventure-boom');
    _isOpen = true;
    notifyListeners();
    return 1;
  }

  /// 让 `widget.onStartAdventure` 入口（AdventureDashboardScreen 那条路径）复用
  /// 同一份启动语义，避免测试自己实现一套假的启动流程。
  Future<void> startFromCallback(AdventureConfig c) =>
      startAdventureWithConfig(c);
}

/// 只替换模板读取，其余保持生产 Controller 行为。
class _StubCrudController extends ResourceCrudController {
  _StubCrudController(this.rows)
      : super(
          repository:
              LibraryRepositoryImpl(getDb: () => DatabaseService.database),
        );

  final List<Map<String, dynamic>> rows;

  @override
  Future<List<Map<String, dynamic>>> loadAdventureTemplates({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async =>
      rows;
}

/// legacy 形状的模板行：没有 full-preview 标记，走 [buildPresetData] 的扁平解析
/// 路径，由 [PresetScenesScreen] 自己组装 [AdventureConfig]。
Map<String, dynamic> _templateRow() => {
      'id': 'preset-1',
      'name': '石桥夜谈',
      'worldview_name': '灵境大陆',
      'worldview_desc': '一片被月光笼罩的大陆。',
      'status': 'complete',
      'updated_at': '2026-09-15T10:00:00.000',
      'char_data_json': jsonEncode({
        'name': '旅人',
        'gender': '男',
        'age': '青年',
        'profession': '游侠',
        'background': '来自北方的流浪者。',
        'openingScene': '你站在石桥边。',
        'options': ['继续前进', '检查装备', '观察河面'],
      }),
      'npc_data_json': jsonEncode({'npcs': <Map<String, dynamic>>[]}),
    };

void main() {
  late Directory tempDir;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    // SettingsProvider 构造时会创建 connectivity 流；flutter_test 没有平台实现，
    // 不屏蔽会以 MissingPluginException 形式污染测试结果。
    final messenger = TestWidgetsFlutterBinding.instance.defaultBinaryMessenger;
    for (final name in const [
      'dev.fluttercommunity.plus/connectivity',
      'dev.fluttercommunity.plus/connectivity_status',
    ]) {
      messenger.setMockMethodCallHandler(
          MethodChannel(name), (call) async => null);
    }
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'deepseek_api_key': 'test', 'openai_api_key': 'test'});
    // ChatProvider 的初始化会走 settings repository；用临时库隔离，避免碰用户数据。
    tempDir = await Directory.systemTemp.createTemp('lt_preset_quick_start_');
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

  /// 宿主界面镜像 MainGate 的判定：对话页是否可见只由
  /// [ChatProvider.isAdventureChatOpen] 决定。
  Future<void> pumpHost(
    WidgetTester tester,
    _QuickStartChatProvider chat, {
    Future<void> Function(AdventureConfig config, {String? difficulty})?
        onStartAdventure,
    Size viewport = const Size(1280, 800),
  }) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatProvider.overrideWith((ref) => chat),
          resourceCrudControllerProvider
              .overrideWith((ref) => _StubCrudController([_templateRow()])),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Consumer(
            builder: (context, ref, _) {
              final isOpen = ref.watch(
                chatProvider.select((c) => c.isAdventureChatOpen),
              );
              return Scaffold(
                body: Column(
                  children: [
                    Text(isOpen ? 'SESSION_VISIBLE' : 'DASHBOARD_VISIBLE'),
                    Builder(
                      builder: (buttonContext) => ElevatedButton(
                        onPressed: () => AppRouter.push<void>(
                          buttonContext,
                          pageBuilder: (_) => PresetScenesScreen(
                            onStartAdventure: onStartAdventure,
                          ),
                        ),
                        child: const Text('打开预存场景工坊'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('打开预存场景工坊'));
    await tester.pumpAndSettle();
    expect(find.byType(PresetScenesScreen), findsOneWidget);
  }

  Future<void> tapQuickStart(WidgetTester tester) async {
    await tester.tap(find.text('一键启程'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'quick start through the dashboard callback pops the preset route and '
      'reveals the session', (tester) async {
    final chat = _QuickStartChatProvider();
    await pumpHost(
      tester,
      chat,
      onStartAdventure: (config, {difficulty}) =>
          chat.startFromCallback(config),
    );

    // 预存场景 Route 覆盖在大厅之上，底层内容处于 offstage；此时仍未进入对话。
    expect(find.text('DASHBOARD_VISIBLE', skipOffstage: false), findsOneWidget);
    expect(find.text('SESSION_VISIBLE', skipOffstage: false), findsNothing);

    await tapQuickStart(tester);

    expect(find.byType(PresetScenesScreen), findsNothing);
    // Route 退出后底层重新成为可见内容，且已经是对话页。
    expect(find.text('SESSION_VISIBLE'), findsOneWidget);
    expect(find.text('DASHBOARD_VISIBLE', skipOffstage: false), findsNothing);
    expect(chat.startCalls, 1);
  });

  testWidgets(
      'quick start without a callback (resource library entry) also enters the '
      'session', (tester) async {
    final chat = _QuickStartChatProvider();
    await pumpHost(tester, chat);

    await tapQuickStart(tester);

    expect(find.byType(PresetScenesScreen), findsNothing);
    expect(find.text('SESSION_VISIBLE'), findsOneWidget);
    expect(chat.startCalls, 1);
    // 由预存场景数据组装出的配置必须原样交给 ChatProvider。
    expect(chat.lastStartedConfig?.name, '旅人');
    expect(chat.lastStartedConfig?.protagonistClass, '游侠');
    expect(chat.lastStartedConfig?.openingOptions, ['继续前进', '检查装备', '观察河面']);
  });

  testWidgets('a failed start never pops the preset route', (tester) async {
    final chat = _QuickStartChatProvider(failStart: true);
    await pumpHost(
      tester,
      chat,
      onStartAdventure: (config, {difficulty}) =>
          chat.startFromCallback(config),
    );

    await tapQuickStart(tester);

    expect(find.byType(PresetScenesScreen), findsOneWidget);
    expect(find.text('DASHBOARD_VISIBLE', skipOffstage: false), findsOneWidget);
    expect(find.text('SESSION_VISIBLE', skipOffstage: false), findsNothing);
    expect(find.textContaining('启动预设场景失败'), findsOneWidget);
    expect(chat.startCalls, 1);
  });

  testWidgets('navigation needs no opening AI round to complete',
      (tester) async {
    final chat = _QuickStartChatProvider();
    await pumpHost(
      tester,
      chat,
      onStartAdventure: (config, {difficulty}) =>
          chat.startFromCallback(config),
    );

    // 假实现只完成「冒险记录已创建」这一步，不触发任何 LLM 请求；
    // pumpAndSettle 不依赖开场正文生成，导航必须已经完成。
    await tapQuickStart(tester);
    expect(find.byType(PresetScenesScreen), findsNothing);
    expect(chat.startCalls, 1);
  });

  testWidgets('a second tap is impossible once the route is gone',
      (tester) async {
    final chat = _QuickStartChatProvider();
    await pumpHost(
      tester,
      chat,
      onStartAdventure: (config, {difficulty}) =>
          chat.startFromCallback(config),
    );

    await tapQuickStart(tester);
    expect(chat.startCalls, 1);
    // 预存场景 Route 已经退出，页面上不存在第二个可触发的「一键启程」，
    // 因此同一份预存场景不会被重复创建。
    expect(find.text('一键启程'), findsNothing);
    expect(chat.startCalls, 1);
  });
}
