import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/router/app_router.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/core/widgets/app_buttons.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/screens/adventure_session_screen.dart';
import 'package:lt_dialogue/features/adventure/presentation/wizard/screens/assembly_create_page.dart';
import 'package:lt_dialogue/features/adventure/presentation/wizard/screens/assembly_preview_page.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/providers/chat_provider.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/settings_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/world_entry_repository_impl.dart';

/// P0 回归：装配流水线「踏入冒险」成功后必须退出整个装配 Route 栈，露出
/// MainGate 已经准备好的 Session；失败必须留在本页重试；无论快速连点、慢速连点
/// 还是路由动画期间重复点击，都只能创建一个 Adventure。
///
/// 断言的是最终导航/UI 状态与创建次数，而不是「callback 被调用过」。
class _AssemblyLaunchChatProvider extends ChatProvider {
  _AssemblyLaunchChatProvider({this.failStart = false})
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
  int adventuresCreated = 0;
  bool _isOpen = false;
  int? _adventureId;

  @override
  bool get isKeyConfigured => true;

  @override
  bool get isAdventureChatOpen => _isOpen;

  @override
  int? get currentAdventureId => _adventureId;

  @override
  Future<int> startAdventureWithConfig(AdventureConfig c) async {
    startCalls++;
    if (failStart) throw StateError('assembly-start-boom');
    adventuresCreated++;
    _adventureId = adventuresCreated;
    _isOpen = true;
    notifyListeners();
    return _adventureId!;
  }
}

AdventureConfig _launchConfig() => AdventureConfig(
      worldview: '遗忘群岛',
      name: '亚瑟',
      protagonistClass: '圣骑士',
      openingScene: '海风呼啸，战舰在暗礁前触底震颤。',
      openingOptions: const ['拔剑固守船头', '退入船舱查看漏水'],
      selectedCharacters: [
        AdventureSelectedCharacter(
          id: 'p1',
          characterId: 'p1',
          characterName: '亚瑟',
          isProtagonist: true,
          narrativeRole: AdventureCharacterRole.protagonist,
          characterCardJson: const {'name': '亚瑟', 'profession': '圣骑士'},
        ),
      ],
    );

void main() {
  late Directory tempDir;

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

  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'deepseek_api_key': 'test', 'openai_api_key': 'test'});
    tempDir = await Directory.systemTemp.createTemp('lt_assembly_launch_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    // 在真实异步区（setUp）先建立连接：若留到 widget test body 里惰性打开，
    // 连接 Future 会绑定在 FakeAsync 区，永远不会完成。
    await DatabaseService.database;
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  /// 宿主镜像 MainGate 的判定：Session 是否可见只由 ChatProvider 决定，装配页
  /// 不允许自己 push 第二个 Session。
  Future<void> pumpHost(
    WidgetTester tester,
    _AssemblyLaunchChatProvider chat,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatProvider.overrideWith((ref) => chat),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Consumer(
            builder: (context, ref, _) {
              final isOpen =
                  ref.watch(chatProvider.select((c) => c.isAdventureChatOpen));
              final id =
                  ref.watch(chatProvider.select((c) => c.currentAdventureId));
              if (isOpen && id != null) {
                return const AdventureSessionScreen();
              }
              return Scaffold(
                body: Column(
                  children: [
                    const Text('DASHBOARD_VISIBLE'),
                    Builder(
                      builder: (buttonContext) => ElevatedButton(
                        onPressed: () => AppRouter.push<void>(
                          buttonContext,
                          pageBuilder: (_) => AssemblyCreatePage(
                            onStartAdventure: chat.startAdventureWithConfig,
                            initialConfig: _launchConfig(),
                            initialWorldviewDesc: '迷雾笼罩的古老海域',
                          ),
                        ),
                        child: const Text('打开装配页'),
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
  }

  /// MainGate → AssemblyCreatePage → AssemblyPreviewPage。
  Future<void> openPreview(WidgetTester tester) async {
    await tester.tap(find.text('打开装配页'));
    await tester.pumpAndSettle();
    expect(find.byType(AssemblyCreatePage), findsOneWidget);

    await tester.tap(find.text('4. 装配总览'));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const Key('assembly-open-preview-page-button')));
    await tester.pumpAndSettle();
    expect(find.byType(AssemblyPreviewPage), findsOneWidget);
    // 资源就绪状态必须先解析完成，否则「踏入冒险」是禁用态。
    expect(find.text('冒险要素装配完毕'), findsOneWidget);
  }

  testWidgets(
      'a successful launch exits the whole assembly stack and reveals the '
      'session with exactly one adventure', (tester) async {
    final chat = _AssemblyLaunchChatProvider();
    await pumpHost(tester, chat);
    await openPreview(tester);

    // 两层装配 Route 同时存在，底层 Session 还没被露出。
    expect(
        find.byType(AssemblyCreatePage, skipOffstage: false), findsOneWidget);
    expect(
        find.byType(AdventureSessionScreen, skipOffstage: false), findsNothing);

    await tester.tap(find.byKey(const Key('assembly-preview-start-button')));
    await _pumpFrames(tester);

    expect(chat.startCalls, 1);
    expect(chat.adventuresCreated, 1);
    // 整个装配栈退出，而不是只 pop 预览页再回到 AssemblyCreatePage。
    expect(find.byType(AssemblyPreviewPage), findsNothing);
    expect(find.byType(AssemblyCreatePage, skipOffstage: false), findsNothing);
    // Session 成为真正可见页面。
    expect(find.byType(AdventureSessionScreen), findsOneWidget);
    expect(find.text('DASHBOARD_VISIBLE', skipOffstage: false), findsNothing);
    // 不存在第二个可触发的「踏入冒险」。
    expect(find.text('踏入冒险'), findsNothing);
  });

  testWidgets('a failed launch stays on the assembly page and allows a retry',
      (tester) async {
    final chat = _AssemblyLaunchChatProvider(failStart: true);
    await pumpHost(tester, chat);
    await openPreview(tester);

    await tester.tap(find.byKey(const Key('assembly-preview-start-button')));
    await tester.pumpAndSettle();

    expect(chat.startCalls, 1);
    expect(chat.adventuresCreated, 0);
    expect(find.byType(AssemblyPreviewPage), findsOneWidget);
    expect(find.textContaining('启动冒险失败'), findsOneWidget);
    expect(
        find.byType(AdventureSessionScreen, skipOffstage: false), findsNothing);
    expect(find.text('DASHBOARD_VISIBLE', skipOffstage: false), findsOneWidget);

    // 失败后按钮必须重新可用，允许再次尝试。
    expect(
      tester
          .widget<AppPrimaryButton>(
              find.byKey(const Key('assembly-preview-start-button')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('assembly-preview-start-button')));
    await tester.pumpAndSettle();
    expect(chat.startCalls, 2);
  });

  testWidgets('five taps during the route animation still create one adventure',
      (tester) async {
    final chat = _AssemblyLaunchChatProvider();
    await pumpHost(tester, chat);
    await openPreview(tester);

    final startFinder = find.byKey(const Key('assembly-preview-start-button'));
    for (var i = 0; i < 5; i++) {
      if (startFinder.evaluate().isEmpty) break;
      await tester.tap(startFinder, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await _pumpFrames(tester);

    expect(chat.startCalls, 1);
    expect(chat.adventuresCreated, 1);
    expect(find.byType(AssemblyPreviewPage), findsNothing);
    expect(find.byType(AdventureSessionScreen), findsOneWidget);
  });

  testWidgets(
      'the inline 踏入冒险 entry on the assembly page has the same semantics',
      (tester) async {
    final chat = _AssemblyLaunchChatProvider();
    await pumpHost(tester, chat);

    await tester.tap(find.text('打开装配页'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4. 装配总览'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('assembly-start-adventure-button')));
    await _pumpFrames(tester);

    expect(chat.startCalls, 1);
    expect(chat.adventuresCreated, 1);
    expect(find.byType(AssemblyCreatePage, skipOffstage: false), findsNothing);
    expect(find.byType(AdventureSessionScreen), findsOneWidget);

    // 装配页已退出：慢速重复点击不可能再创建第二个 Adventure。
    expect(find.text('踏入冒险'), findsNothing);
    expect(
        find.byKey(const Key('assembly-start-adventure-button'),
            skipOffstage: false),
        findsNothing);
    expect(chat.adventuresCreated, 1);
  });
}

/// Bounded frame pumping: [AdventureSessionScreen] is a live screen, so
/// `pumpAndSettle` is not a valid completion signal once it is on top.
Future<void> _pumpFrames(WidgetTester tester, {int frames = 20}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
