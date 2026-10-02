import 'dart:io';
import 'package:lt_dialogue/core/debug/generation_diagnostics.dart';
import 'package:lt_dialogue/engines/chat_engine_internals/prompt_builder.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/models/dialogue_level.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lt_dialogue/core/widgets/app_svg_icon.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/screens/chat/widgets/search_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/features/adventure/presentation/session/widgets/session_controls.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/domain/read_aloud/read_aloud_contracts.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/screens/adventure_session_screen.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/widgets/session_app_bar.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/widgets/session_input_bar.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/widgets/session_message_list.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/widgets/session_settling_hint.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/widgets/status_hud_bar.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/game_state.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:lt_dialogue/providers/chat_provider.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/screens/chat/widgets/character_switcher.dart';
import 'package:lt_dialogue/screens/chat/widgets/message_bubble.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/read_aloud/read_aloud_controller.dart';

import '../helpers/read_aloud_fakes.dart';
import '../helpers/responsive_test_helper.dart';

class TestSessionChatProvider extends ChatProvider {
  final List<String> sentOptions = [];
  @override
  Future<void> sendMessage(String content,
      {Future<String> Function(String content)? promptTransformer}) async {
    sentOptions.add(content);
  }

  String _mockTitle = '';
  @override
  String get currentTitle => _mockTitle;
  void setMockTitle(String title) {
    _mockTitle = title;
    titleBarVersion.value++;
    notifyListeners();
  }

  bool _mockIsStreaming = false;
  @override
  bool get isStreaming => _mockIsStreaming;
  void setMockStreaming(bool val) {
    _mockIsStreaming = val;
    stateVersion.value++;
    notifyListeners();
  }
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;
  const connectivityChannel =
      MethodChannel('dev.fluttercommunity.plus/connectivity_status');

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, (call) async {
      if (call.method == 'listen' || call.method == 'cancel') return null;
      throw MissingPluginException('Unexpected connectivity method');
    });
    SharedPreferences.setMockInitialValues({
      'openai_api_key': 'test',
      'deepseek_api_key': 'test',
    });
    tempDir = await Directory.systemTemp.createTemp('lt_phase3_test_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, null);
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  Widget buildTestApp({
    required ProviderContainer container,
    ThemeData? theme,
    Locale locale = const Locale('zh'),
    double textScale = 1.0,
    EdgeInsets viewInsets = EdgeInsets.zero,
    Widget? home,
  }) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: theme ?? AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            viewInsets: viewInsets,
          ),
          child: child!,
        ),
        home: home ?? const AdventureSessionScreen(),
      ),
    );
  }

  group('Phase 3: Adventure Session Comprehensive Tests', () {
    testWidgets('custom models retain the conservative response reserve',
        (tester) async {
      final container = await tester.runAsync(() async {
        final container = ProviderContainer();
        final cp = container.read(chatProvider);
        await cp.settingsProvider.setModel('custom-provider-model');
        await cp.settingsProvider
            .setCompletionParams(const CompletionParams(maxTokens: 12000));
        return container;
      });
      addTearDown(container!.dispose);
      final capability =
          container.read(chatProvider).messagingProvider.modelContextCapability;
      expect(capability.maximumContextTokens, 32768);
      expect(capability.maximumOutputTokens, 12000);
    });
    testWidgets(
        'prompt reserves the entire thinking and prose request without expanding context window',
        (tester) async {
      final container = await tester.runAsync(() async {
        final container = ProviderContainer();
        final cp = container.read(chatProvider);
        await cp.settingsProvider.setCompletionParams(
            const CompletionParams(enableThinking: true, maxTokens: 4096));
        await cp.settingsProvider.setDialogueLevel(DialogueLevel.l5);
        return container;
      });
      addTearDown(container!.dispose);
      final cp = container.read(chatProvider);
      final builder = PromptBuilder();
      builder.buildMessages(
          cp.messagingProvider, '询问老板', cp.messages, null, null);
      expect(cp.messagingProvider.modelContextCapability.maximumContextTokens,
          32768);
      expect(builder.lastContextTrace!.responseReserveTokens, 13904);
      expect(
          builder.lastContextTrace!.totalEstimatedTokens +
              builder.lastContextTrace!.responseReserveTokens,
          lessThan(32768));
    });

    testWidgets('engine re-init keeps the same live engine and notifiers',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final cp = container.read(chatProvider);
      final stream = cp.streamNotifier;
      final reasoning = cp.reasoningStreamNotifier;
      final markersBefore = GenerationDiagnostics.instance
          .markerTail(2000)
          .where((m) => m.contains('[ChatEngine][CREATE]'))
          .length;
      cp.messagingProvider.initChatEngine((_) async {}, (_) async {});
      cp.messagingProvider.initChatEngine((_) async {}, (_) async {});
      expect(identical(cp.streamNotifier, stream), isTrue);
      expect(identical(cp.reasoningStreamNotifier, reasoning), isTrue);
      expect(
          GenerationDiagnostics.instance
              .markerTail(2000)
              .where((m) => m.contains('[ChatEngine][CREATE]'))
              .length,
          markersBefore);
      expect(tester.takeException(), isNull);
    });

    testWidgets('one option tap dispatches exactly one provider intent',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      final cp = TestSessionChatProvider();
      final container = ProviderContainer(
          overrides: [chatProvider.overrideWith((ref) => cp)]);
      addTearDown(container.dispose);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      const option = '先向旅店老板打听更多关于魔物躁动和失踪商队的细节';
      cp.messages.add(Message(
          id: 'a-option',
          isUser: false,
          content:
              '旅店老板擦拭酒杯。\n---JSON---\n{"options":["$option","观察旅店","检查行囊"]}'));
      await tester.pumpWidget(buildTestApp(
          container: container,
          home: Scaffold(
              body: SessionMessageList(scrollController: controller))));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(option));
      await tester.tap(find.text(option));
      await tester.pump();
      expect(cp.sentOptions, [option]);
      expect(tester.takeException(), isNull);
    });

    for (final width in [320.0, 390.0, 1024.0]) {
      testWidgets(
          'reasoning recovery preserves reasoning, prose and Stop at $width px',
          (tester) async {
        setViewport(tester, width: width, height: 844);
        final cp = TestSessionChatProvider()..setMockStreaming(true);
        final inputController = TextEditingController();
        final inputFocus = FocusNode();
        addTearDown(inputController.dispose);
        addTearDown(inputFocus.dispose);
        cp.reasoningStreamNotifier.value = '分析旅店内的线索';
        cp.isThinkingNotifier.value = true;
        final container = ProviderContainer(
            overrides: [chatProvider.overrideWith((ref) => cp)]);
        addTearDown(container.dispose);
        final controller = ScrollController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(buildTestApp(
            container: container,
            home: Scaffold(
                body: Column(children: [
              Expanded(child: SessionMessageList(scrollController: controller)),
              SessionInputBar(
                  controller: inputController,
                  focusNode: inputFocus,
                  onSend: () {})
            ]))));
        await tester.pump();
        expect(
            find.text(AppLocalizationsZh().deepThinkingStatus), findsOneWidget);
        expect(find.text('分析旅店内的线索'), findsOneWidget);
        expect(find.byTooltip(AppLocalizationsZh().stopGenerationAction),
            findsOneWidget);
        expect(cp.streamNotifier.value, isEmpty);
        cp.isThinkingNotifier.value = false;
        await tester.pump();
        expect(
            find.text(AppLocalizationsZh().deepThinkingStatus), findsNothing);
        expect(
            find.text(AppLocalizationsZh().writingStoryStatus), findsOneWidget);
        expect(
            tester
                .widget<ReasoningBlock>(find.byType(ReasoningBlock))
                .reasoning,
            '分析旅店内的线索');
        cp.streamNotifier.value = '旅店老板放下酒杯，压低了声音。';
        await tester.pump();
        expect(find.text('旅店老板放下酒杯，压低了声音。'), findsOneWidget);
        expect(
            find.text(AppLocalizationsZh().writingStoryStatus), findsNothing);
        expect(find.byType(StreamingBubble), findsOneWidget);
        await tester.tap(find
            .descendant(
                of: find.byType(ReasoningBlock), matching: find.byType(InkWell))
            .first);
        await tester.pump();
        expect(find.text('分析旅店内的线索'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    // 1. AdventureSessionScreen 空状态
    testWidgets('1. AdventureSessionScreen renders blank slate empty state',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(buildTestApp(container: container));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final l10n = AppLocalizationsZh();
      expect(find.text(l10n.adventureBlankSlateTitle), findsOneWidget);
      expect(find.text(l10n.beginAdventureAction), findsOneWidget);
      expect(find.byType(SessionAppBar), findsOneWidget);
      expect(find.byType(StatusHudBar), findsOneWidget);
      expect(find.byType(SessionInputBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 2. AdventureSessionScreen 有消息时的整体布局
    testWidgets('2. AdventureSessionScreen renders message bubbles in layout',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final cp = container.read(chatProvider);
      cp.messages.addAll([
        Message(
          id: 'u1',
          content: '调查神殿深处的祭坛',
          isUser: true,
        ),
        Message(
          id: 'a1',
          content: '祭坛上布满了古老的铭文，微弱的蓝光在石缝间流转。',
          isUser: false,
        ),
      ]);

      await tester.pumpWidget(buildTestApp(container: container));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('调查神殿深处的祭坛'), findsOneWidget);
      expect(find.text('祭坛上布满了古老的铭文，微弱的蓝光在石缝间流转。'), findsOneWidget);
      expect(find.byType(UserBubble), findsOneWidget);
      expect(find.byType(AiBubble), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 3. SessionAppBar 在 320px、360px、桌面下无异常，操作菜单正常
    testWidgets('3. SessionAppBar renders without overflow across viewports',
        (tester) async {
      final l10n = AppLocalizationsZh();
      for (final width in [320.0, 360.0, 1024.0]) {
        setViewport(tester, width: width, height: 640);
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          buildTestApp(
            container: container,
            home: const Scaffold(
              appBar: SessionAppBar(),
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(SessionAppBar), findsOneWidget);
        expect(
            find.byTooltip(AppLocalizationsZh().backToLobby), findsOneWidget);
        expect(find.byTooltip(AppLocalizationsZh().searchConversationAction),
            findsOneWidget);
        expect(find.byTooltip(AppLocalizationsZh().moreOptionsAction),
            findsOneWidget);

        // 打开更多菜单
        await tester
            .tap(find.byTooltip(AppLocalizationsZh().moreOptionsAction));
        await tester.pumpAndSettle();

        expect(find.text(l10n.characterStatusTitle), findsNothing);
        expect(find.text(l10n.inventoryTitle), findsNothing);
        expect(find.text(l10n.replyLengthSetting), findsNothing);
        expect(find.text(l10n.switchModelAction), findsNothing);
        expect(find.text(l10n.promptSettingsAction), findsNothing);
        expect(find.text(l10n.restartAdventureAction), findsOneWidget);
        expect(find.text(l10n.settingsCenter), findsNothing);

        // 关闭菜单
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      }
    });

    // 4. 长标题不会破坏返回按钮和 actions (320px)
    testWidgets('4. Long Adventure title wraps/truncates cleanly at 320px',
        (tester) async {
      setViewport(tester, width: 320, height: 568);
      final testCp = TestSessionChatProvider();
      final container = ProviderContainer(
        overrides: [
          chatProvider.overrideWith((ref) => testCp),
        ],
      );
      addTearDown(container.dispose);

      const longTitle = '在极北冻原与深渊巨龙搏击并寻求上古遗失王冠的史诗传奇';
      testCp.setMockTitle(longTitle);

      await tester.pumpWidget(
        buildTestApp(
          container: container,
          home: const Scaffold(appBar: SessionAppBar()),
        ),
      );
      await tester.pump();

      expect(find.byTooltip(AppLocalizationsZh().backToLobby), findsOneWidget);
      expect(find.byTooltip(AppLocalizationsZh().moreOptionsAction),
          findsOneWidget);
      expect(find.text(longTitle), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 5. StatusHudBar 可以打开 RuntimeStateHubPage
    testWidgets('5. StatusHudBar displays location/stats and triggers onTap',
        (tester) async {
      setViewport(tester, width: 360, height: 640);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(chatProvider).adventureProvider.setGameState(
            GameState(
              currentScene: '幽暗密林深处',
              hp: 92,
              maxHp: 100,
              mp: 45,
              maxMp: 60,
              gold: 888,
            ),
          );

      bool hubOpened = false;
      await tester.pumpWidget(
        buildTestApp(
          container: container,
          home: Scaffold(
            body: StatusHudBar(onTap: () => hubOpened = true),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('幽暗密林深处'), findsOneWidget);
      expect(find.textContaining('92/100'), findsOneWidget);
      expect(find.textContaining('45/60'), findsOneWidget);
      expect(find.textContaining('888'), findsOneWidget);

      await tester.tap(find.byType(StatusHudBar));
      await tester.pump();
      expect(hubOpened, isTrue);
      expect(tester.takeException(), isNull);
    });

    // 6. SceneState.presentCharacterIds 过滤死亡与不在场角色
    testWidgets('6. CharacterSwitcher respects presentCharacterIds and isAlive',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final config = AdventureConfig(
        name: '主角伊莱',
        personality: 'p',
        openingScene: 's',
        supportingCharacters: [
          SupportingCharacter(
            id: 'c1',
            name: '艾莉丝',
            isAlive: true,
          ),
          SupportingCharacter(
            id: 'c2',
            name: '已阵亡队友',
            isAlive: false, // 死亡角色
          ),
          SupportingCharacter(
            id: 'c3',
            name: '远方留守同伴',
            isAlive: true, // 不在场角色
          ),
        ],
      );

      await tester.pumpWidget(
        buildTestApp(
          container: container,
          home: Scaffold(
            body: CharacterSwitcher(
              isDark: false,
              config: config,
              selectedCharacterIndex: -1,
              autoAdvanceCharacter: false,
              sceneParticipantIds: const ['protagonist', 'c1'], // c3 不在场
              onSelectCharacter: (_) {},
              onToggleAutoAdvance: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('主角伊莱'), findsOneWidget);
      expect(find.text('艾莉丝'), findsOneWidget);
      expect(find.text('已阵亡队友'), findsNothing);
      expect(find.text('远方留守同伴'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    // 7. 角色切换条支持切换与长角色名
    testWidgets(
        '7. CharacterSwitcher selection, auto-advance, and tooltips work',
        (tester) async {
      setViewport(tester, width: 360, height: 640);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      int selectedIdx = -1;
      bool autoAdvanced = false;

      final config = AdventureConfig(
        name: '主角伊莱',
        personality: 'p',
        openingScene: 's',
        supportingCharacters: [
          SupportingCharacter(
            id: 'c1',
            name: '大魔导师奥兰多长名特长',
            isAlive: true,
          ),
        ],
      );

      await tester.pumpWidget(
        buildTestApp(
          container: container,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return CharacterSwitcher(
                  isDark: false,
                  config: config,
                  selectedCharacterIndex: selectedIdx,
                  autoAdvanceCharacter: autoAdvanced,
                  sceneParticipantIds: const ['protagonist', 'c1'],
                  onSelectCharacter: (idx) => setState(() => selectedIdx = idx),
                  onToggleAutoAdvance: () =>
                      setState(() => autoAdvanced = !autoAdvanced),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // 点击同伴切换
      await tester.tap(find.text('大魔导师奥兰多长名特长'));
      await tester.pump();
      expect(selectedIdx, 0);

      // 点击自动推进
      await tester
          .tap(find.byTooltip(AppLocalizationsZh().autoSwitchCharacterTooltip));
      await tester.pump();
      expect(autoAdvanced, isTrue);
      expect(find.byTooltip(AppLocalizationsZh().autoSwitchCharacterTooltip),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 8. SessionMessageList 支持长正文与多段落
    testWidgets('8. SessionMessageList renders long multi-paragraph narrative',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final cp = container.read(chatProvider);
      const longStory = '夜色渐浓，寒风穿过断壁残垣。\n\n'
          '伊莱握紧了手中的短剑，警惕地环视四周。空气中弥漫着泥土和陈旧魔法的气味。\n\n'
          '深处的阴影中，一双泛着猩红光芒的眼眸正静静地注视着闯入者。';

      cp.messages.add(
        Message(
          id: 'm-long',
          content: longStory,
          isUser: false,
        ),
      );

      await tester.pumpWidget(
        buildTestApp(
          container: container,
          home: Scaffold(
            body: SessionMessageList(scrollController: ScrollController()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('夜色渐浓'), findsOneWidget);
      expect(find.textContaining('一双泛着猩红光芒的眼眸'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 9. ReasoningBlock 默认收起，展开后可滚动与复制
    testWidgets('9. ReasoningBlock collapsed by default, expands on tap',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      final l10n = AppLocalizationsZh();

      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ReasoningBlock(
              reasoning: '推演：玩家向深处探索，检测周围陷阱与光照状态。',
              brightness: Brightness.light,
              fontSize: 14,
            ),
          ),
        ),
      );
      await tester.pump();

      // 默认收起态
      expect(find.text(l10n.reasoningCollapsedLabel), findsOneWidget);
      expect(find.text('推演：玩家向深处探索，检测周围陷阱与光照状态。'), findsNothing);

      // 点击展开
      await tester.tap(find.text(l10n.reasoningCollapsedLabel));
      await tester.pumpAndSettle();

      expect(find.text(l10n.reasoningExpandedLabel), findsOneWidget);
      expect(find.text('推演：玩家向深处探索，检测周围陷阱与光照状态。'), findsOneWidget);
      expect(find.text(l10n.copyReasoningAction), findsOneWidget);

      // 再次点击收起
      await tester.tap(find.text(l10n.reasoningExpandedLabel));
      await tester.pumpAndSettle();

      expect(find.text(l10n.reasoningCollapsedLabel), findsOneWidget);
      expect(find.text('推演：玩家向深处探索，检测周围陷阱与光照状态。'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    // 10. SessionSettlingHint 显示时不出现原始 JSON
    testWidgets('10. SessionSettlingHint never leaks raw JSON', (tester) async {
      setViewport(tester, width: 320, height: 568);
      final l10n = AppLocalizationsZh();

      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SessionSettlingHint(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text(l10n.sessionSettlingStatus), findsOneWidget);
      expect(find.textContaining('{'), findsNothing);
      expect(find.textContaining('options'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    // 11. SessionInputBar 在键盘弹出时仍可输入和发送
    testWidgets('11. SessionInputBar functions with simulated keyboard insets',
        (tester) async {
      setViewport(tester, width: 320, height: 568);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      String sentText = '';

      await tester.pumpWidget(
        buildTestApp(
          container: container,
          viewInsets: const EdgeInsets.only(bottom: 280), // 模拟软键盘弹出
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SessionInputBar(
                controller: controller,
                focusNode: focusNode,
                onSend: () => sentText = controller.text,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // 输入文字
      await tester.enterText(find.byType(TextField), '查看四周');
      await tester.pump();

      // 点击发送按钮
      await tester
          .tap(find.byTooltip('${AppLocalizationsZh().sendAction} (Enter)'));
      await tester.pump();

      expect(sentText, '查看四周');
      expect(tester.takeException(), isNull);
    });

    // 12. 生成中显示停止操作
    testWidgets('12. SessionInputBar shows stop button during generation',
        (tester) async {
      setViewport(tester, width: 360, height: 640);
      final testCp = TestSessionChatProvider();
      final container = ProviderContainer(
        overrides: [
          chatProvider.overrideWith((ref) => testCp),
        ],
      );
      addTearDown(container.dispose);

      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      bool stopped = false;
      testCp.setMockStreaming(true);

      await tester.pumpWidget(
        buildTestApp(
          container: container,
          home: Scaffold(
            body: SessionInputBar(
              controller: controller,
              focusNode: focusNode,
              onSend: () {},
              onStop: () => stopped = true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byTooltip(AppLocalizationsZh().stopGenerationAction),
          findsOneWidget);
      expect(find.byTooltip('${AppLocalizationsZh().sendAction} (Enter)'),
          findsNothing);

      await tester
          .tap(find.byTooltip(AppLocalizationsZh().stopGenerationAction));
      await tester.pump();
      expect(stopped, isTrue);
      expect(tester.takeException(), isNull);
    });

    // 13. 停止生成后输入栏恢复正常
    testWidgets(
        '13. SessionInputBar restores send button after generation stops',
        (tester) async {
      setViewport(tester, width: 360, height: 640);
      final testCp = TestSessionChatProvider();
      final container = ProviderContainer(
        overrides: [
          chatProvider.overrideWith((ref) => testCp),
        ],
      );
      addTearDown(container.dispose);

      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      testCp.setMockStreaming(true);

      await tester.pumpWidget(
        buildTestApp(
          container: container,
          home: Scaffold(
            body: SessionInputBar(
              controller: controller,
              focusNode: focusNode,
              onSend: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byTooltip(AppLocalizationsZh().stopGenerationAction),
          findsOneWidget);

      testCp.setMockStreaming(false);
      await tester.pump();
      expect(find.byTooltip('${AppLocalizationsZh().sendAction} (Enter)'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 14. 朗读入口与 capability 不可用状态
    testWidgets('14. Read aloud button appears when supported, hides when not',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      final message = Message(
        id: 'msg-voice',
        content: '微风拂过湖面，泛起阵阵涟漪。',
        isUser: false,
      );

      // Supported
      final supportedEngine = FakeReadAloudEngine(supported: true);
      final supportedController = ReadAloudController(
        engine: supportedEngine,
        initialPreferences: const ReadAloudPreferences(enabled: true),
      );

      await tester.pumpWidget(
        ProviderScope(
          key: const ValueKey('supported_scope'),
          overrides: [
            readAloudControllerProvider.overrideWith(
              (ref) => supportedController,
              disposeNotifier: false,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: AiBubble(
                message: message,
                chatFontSize: 14,
                brightness: Brightness.light,
                aiName: '向导',
                emotion: '',
                isBookmarked: false,
                onLongPress: () {},
                onRegenerate: () {},
                onDelete: () {},
                onToggleBookmark: () {},
                onOptionTap: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
          find.byWidgetPredicate(
              (widget) => widget is AppSvgIcon && widget.name == 'read_aloud'),
          findsOneWidget);

      // Unsupported
      final unsupportedEngine = FakeReadAloudEngine(supported: false);
      final unsupportedController = ReadAloudController(
        engine: unsupportedEngine,
        initialPreferences: const ReadAloudPreferences(enabled: true),
      );

      await tester.pumpWidget(
        ProviderScope(
          key: const ValueKey('unsupported_scope'),
          overrides: [
            readAloudControllerProvider.overrideWith(
              (ref) => unsupportedController,
              disposeNotifier: false,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: AiBubble(
                message: message,
                chatFontSize: 14,
                brightness: Brightness.light,
                aiName: '向导',
                emotion: '',
                isBookmarked: false,
                onLongPress: () {},
                onRegenerate: () {},
                onDelete: () {},
                onToggleBookmark: () {},
                onOptionTap: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
          find.byWidgetPredicate(
              (widget) => widget is AppSvgIcon && widget.name == 'read_aloud'),
          findsNothing);
      expect(tester.takeException(), isNull);
    });

    // 15. 消息操作入口 (复制、编辑、删除、重试、书签)
    testWidgets('15. Message actions exist and trigger correctly',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      bool editCalled = false;
      bool bookmarkCalled = false;
      bool copyCalled = false;

      final userMsg = Message(id: 'u1', content: '打开大门', isUser: true);

      await tester.pumpWidget(
        buildTestApp(
          container: container,
          home: Scaffold(
            body: UserBubble(
              message: userMsg,
              chatFontSize: 14,
              userAvatarLabel: '我',
              onLongPress: () {},
              onRegenerate: () {},
              isBookmarked: false,
              onToggleBookmark: () => bookmarkCalled = true,
              onEdit: () => editCalled = true,
              onCopy: () => copyCalled = true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byWidgetPredicate((w) => w is AppSvgIcon && w.name == 'edit'),
          findsOneWidget);
      expect(
          find.byWidgetPredicate(
              (w) => w is AppSvgIcon && w.name == 'bookmark'),
          findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is AppSvgIcon && w.name == 'copy'),
          findsOneWidget);

      await tester.tap(
          find.byWidgetPredicate((w) => w is AppSvgIcon && w.name == 'edit'));
      await tester.pump();
      expect(editCalled, isTrue);

      await tester.tap(find
          .byWidgetPredicate((w) => w is AppSvgIcon && w.name == 'bookmark'));
      await tester.pump();
      expect(bookmarkCalled, isTrue);

      await tester.tap(
          find.byWidgetPredicate((w) => w is AppSvgIcon && w.name == 'copy'));
      await tester.pump();
      expect(copyCalled, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('16. Session controls invoke their direct destinations',
        (tester) async {
      setViewport(tester, width: 320, height: 640);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final calls = <String>[];
      await tester.pumpWidget(buildTestApp(
        container: container,
        home: Scaffold(
            body: SessionControls(
          onContext: () => calls.add('context'),
          onCharacters: () => calls.add('characters'),
          onState: () => calls.add('state'),
          onModel: () => calls.add('model'),
        )),
      ));
      await tester.pump();
      for (final entry in ['context', 'characters', 'state', 'model']) {
        await tester.tap(find.byKey(Key('session-$entry')));
        await tester.pump();
      }
      expect(calls, ['context', 'characters', 'state', 'model']);
      expect(tester.takeException(), isNull);
    });

    // 17. Light and Dark Theme
    testWidgets(
        '17. Session renders without exception in both Light and Dark themes',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      for (final isDark in [false, true]) {
        await tester.pumpWidget(
          buildTestApp(
            container: container,
            theme: isDark ? AppTheme.dark() : AppTheme.light(),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.byType(AdventureSessionScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    // 18. 2.0x 字体缩放
    testWidgets(
        '18. 2.0x font scale survives without layout exception at 320px',
        (tester) async {
      setViewport(tester, width: 320, height: 568);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final cp = container.read(chatProvider);
      cp.messages.add(
        Message(
          id: 'm1',
          content: '这是一段在大字号下的测试剧情叙事文本。',
          isUser: false,
        ),
      );

      await tester.pumpWidget(
        buildTestApp(
          container: container,
          textScale: 2.0,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(AdventureSessionScreen), findsOneWidget);
      expect(find.text('这是一段在大字号下的测试剧情叙事文本。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 19. 320px 到桌面全端布局覆盖
    testWidgets(
        '19. All required viewports render AdventureSessionScreen cleanly',
        (tester) async {
      for (final viewport in requiredUiViewports) {
        setViewport(tester, width: viewport.width, height: viewport.height);
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(buildTestApp(container: container));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byType(AdventureSessionScreen), findsOneWidget,
            reason: 'Failed at viewport $viewport');
        expect(tester.takeException(), isNull,
            reason: 'Exception at viewport $viewport');
      }
    });

    // 20. 综合异常门禁
    testWidgets('20. Complete session flow runs with zero exceptions',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final cp = container.read(chatProvider);
      cp.adventureProvider.setGameState(
        GameState(currentScene: '王城大厅', hp: 100, maxHp: 100),
      );
      cp.messages.add(
        Message(id: 'm-init', content: '故事由此展开。', isUser: false),
      );

      await tester.pumpWidget(buildTestApp(container: container));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 切换搜索
      await tester
          .tap(find.byTooltip(AppLocalizationsZh().searchConversationAction));
      await tester.pumpAndSettle();
      expect(cp.settingsProvider.searchVisible, isTrue);

      // 关闭搜索
      await tester.tap(find.descendant(
          of: find.byType(ChatSearchBar),
          matching: find
              .byWidgetPredicate((w) => w is AppSvgIcon && w.name == 'close')));
      await tester.pumpAndSettle();
      expect(cp.settingsProvider.searchVisible, isFalse);

      expect(tester.takeException(), isNull);
    });
  });
}
