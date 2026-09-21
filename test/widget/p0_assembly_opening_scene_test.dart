import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/screens/adventure_session_screen.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_response.dart';
import 'package:lt_dialogue/providers/chat_provider.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/settings_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/world_entry_repository_impl.dart';

/// P0 回归：带有效序章的冒险踏入后，Session 首屏必须直接进入该序章场景并展示
/// 可点击的初始行动，而不是「纯净冒险白板」。
///
/// 断言的是首屏实际渲染内容与持久化结果，而不是「某个回调被调用过」。
AdventureConfig _prologueConfig() => AdventureConfig(
      name: '测试主角',
      worldview: '测试世界',
      openingScene: '测试序章',
      openingOptions: const ['调查四周', '寻找同伴', '立即离开'],
      selectedCharacters: [
        AdventureSelectedCharacter(
          id: 'p1',
          characterId: 'p1',
          characterName: '测试主角',
          isProtagonist: true,
          narrativeRole: AdventureCharacterRole.protagonist,
          characterCardJson: const {'name': '测试主角'},
        ),
      ],
    );

AdventureConfig _emptyPrologueConfig() {
  final config = _prologueConfig();
  config.openingScene = '';
  config.openingOptions = const [];
  return config;
}

ChatProvider _newChatProvider() => ChatProvider.withRepos(
      adventureRepo:
          AdventureRepositoryImpl(getDb: () => DatabaseService.database),
      worldEntryRepo:
          WorldEntryRepositoryImpl(getDb: () => DatabaseService.database),
      libraryRepo: LibraryRepositoryImpl(getDb: () => DatabaseService.database),
      settingsRepo:
          SettingsRepositoryImpl(getDb: () => DatabaseService.database),
    );

/// Builds a provider and drains its fire-and-forget `_init()` DB read, so a
/// later tearDown cannot close the database under a pending query.
Future<ChatProvider> _newSettledProvider() async {
  final chat = _newChatProvider();
  await chat.loadApiKey();
  return chat;
}

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
    // 不配置 API Key：首轮推演必然失败，用于验证「失败也不退化为空白板」，
    // 同时避免测试真的发起网络请求。
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tempDir = await Directory.systemTemp.createTemp('lt_opening_scene_');
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

  test('a configured prologue is materialized as the first assistant message',
      () async {
    final chat = await _newSettledProvider();
    final config = _prologueConfig();
    final id = await chat.startAdventureWithConfig(config);

    // 只有序章消息，没有把「开场场景」当作用户输入发给模型。
    expect(chat.messages.length, 1);
    final opening = chat.messages.single;
    expect(opening.isUser, isFalse);
    expect(opening.id, 'opening-$id');

    final parsed = AdventureResponse.tryParseSplit(opening.content);
    expect(parsed, isNotNull);
    expect(parsed!.narrative.join('\n'), contains('测试序章'));
    expect(parsed.scene, '序章');
    expect(parsed.options, ['调查四周', '寻找同伴', '立即离开']);

    // 序章必须落库：重新打开同一个冒险仍然不是空白板。
    final repo = AdventureRepositoryImpl(getDb: () => DatabaseService.database);
    final stored = await repo.getMessages(id);
    expect(stored.length, 1);
    expect(stored.single.content, opening.content);
  });

  test('a config without any prologue or branches seeds no opening message',
      () async {
    final chat = await _newSettledProvider();
    final empty = _emptyPrologueConfig();
    // 直接走创建 + 落章接口，避免未配置序章时触发的后台首轮生成请求。
    final id = await chat.adventureProvider.createAdventure('空白冒险', empty);
    expect(await chat.adventureProvider.seedOpeningScene(empty), isFalse);
    expect(chat.messages, isEmpty);

    final repo = AdventureRepositoryImpl(getDb: () => DatabaseService.database);
    expect(await repo.getMessages(id), isEmpty);
  });

  testWidgets(
      'entering the adventure shows the prologue and its three initial actions '
      'instead of the blank board', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final chat = container.read(chatProvider);

    await tester.runAsync(() async {
      await chat.startAdventureWithConfig(_prologueConfig());
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
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
              return const Scaffold(body: Text('DASHBOARD_VISIBLE'));
            },
          ),
        ),
      ),
    );
    await _pumpFrames(tester);

    expect(find.byType(AdventureSessionScreen), findsOneWidget);
    expect(find.text('纯净冒险白板'), findsNothing);
    expect(find.textContaining('测试序章'), findsOneWidget);
    expect(find.text('调查四周'), findsOneWidget);
    expect(find.text('寻找同伴'), findsOneWidget);
    expect(find.text('立即离开'), findsOneWidget);
  });

  testWidgets('a failed first AI turn still keeps the prologue and its options',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final chat = container.read(chatProvider);

    await tester.runAsync(() async {
      await chat.startAdventureWithConfig(_prologueConfig());
      // 没有可用 API Key：首轮推演必然失败，但绝不能退化为空白板。
      await chat.sendMessage('调查四周');
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const AdventureSessionScreen(),
        ),
      ),
    );
    await _pumpFrames(tester);

    expect(find.text('纯净冒险白板'), findsNothing);
    expect(find.textContaining('测试序章'), findsOneWidget);
    expect(find.text('调查四周'), findsOneWidget);
    expect(find.text('寻找同伴'), findsOneWidget);
    expect(find.text('立即离开'), findsOneWidget);
  });
}

/// Bounded frame pumping: [AdventureSessionScreen] is a live screen, so
/// `pumpAndSettle` is not a valid completion signal here.
Future<void> _pumpFrames(WidgetTester tester, {int frames = 20}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
