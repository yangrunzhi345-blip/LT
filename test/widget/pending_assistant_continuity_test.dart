import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/engines/chat_engine.dart'
    show PendingAssistantPhase;
import 'package:lt_dialogue/features/adventure/presentation/session/widgets/session_message_list.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/widgets/session_settling_hint.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/providers/chat_provider.dart' show ChatProvider;
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/screens/chat/widgets/message_bubble.dart'
    show PendingAssistantBubble;
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';

import '../helpers/responsive_test_helper.dart';

/// BUG-2 回归：正文 → 结算 → 提交的展示连续性。
///
/// 同一个用户回合的 AI 回复从开始到 durable commit 必须是视觉上连续的
/// 一条回复：正文冻结后绝不撤回、消失、清空或重新播放；结算提示与
/// 状态/选项只追加在正文之后。
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'openai_api_key': 'test', 'deepseek_api_key': 'test'});
    tempDir = await Directory.systemTemp.createTemp('lt_pending_assistant_');
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

  const String narrative = '这是一个已经完整显示的长篇正文。艾莉丝沿着废弃的河谷古道长距离奔跑，'
      '随后与两名盗贼连续战斗了两回合，直到暮色四合才停下脚步。';

  const List<String> options = ['查看艾莉丝的伤势', '原地休息一会儿', '继续向前赶路'];

  String settledContent() => '$narrative\n---JSON---\n${jsonEncode({
            'scene': '河谷古道',
            'hp': 100,
            'max_hp': 100,
            'energy': 80,
            'max_energy': 100,
            'gold': 10,
            'inventory': <String>[],
            'options': options,
            'custom_status': [
              {
                'id': 'stamina',
                'name': '体力值',
                'value': '90/100',
                'currentValue': 90,
                'maxValue': 100,
                'characterName': '艾莉丝',
              },
            ],
          })}';

  Future<ChatProvider> pumpList(WidgetTester tester) async {
    late ChatProvider captured;
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (context, ref, _) {
            captured = ref.read(chatProvider);
            return MaterialApp(
              locale: const Locale('zh'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: AppTheme.light(),
              home: Scaffold(
                body: SessionMessageList(
                  scrollController: ScrollController(),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    return captured;
  }

  void reload(ChatProvider cp) {
    cp.notifyListeners();
    cp.triggerRebuild();
  }

  testWidgets(
      'streaming → settling → settled → committed keeps the narrative on '
      'screen the whole time', (tester) async {
    setViewport(tester, width: 390, height: 844);
    final cp = await pumpList(tester);

    // 用户消息已入列（等价于 streaming 阶段的列表状态）。
    cp.messages.add(Message(id: 'u1', content: '我们全速赶路', isUser: true));
    reload(cp);
    await tester.pumpAndSettle();

    // ─── settling：正文冻结显示 + 结算提示只作为 footer 追加 ───
    cp.debugSetPendingAssistantPresentation(
      content: narrative,
      phase: PendingAssistantPhase.settling,
    );
    reload(cp);
    await tester.pump();

    expect(find.textContaining('艾莉丝沿着废弃的河谷古道'), findsOneWidget,
        reason: 'settling 时正文绝不能消失');
    expect(find.textContaining(narrative), findsOneWidget);
    expect(
        find.text(AppLocalizationsZh().sessionSettlingStatus), findsOneWidget,
        reason: '结算提示只追加在正文之后');
    expect(tester.takeException(), isNull);

    // ─── settled：状态卡与选项追加出现，提示消失，正文原样 ───
    final settled = settledContent();
    cp.debugSetPendingAssistantPresentation(
      content: settled,
      phase: PendingAssistantPhase.settled,
    );
    reload(cp);
    await tester.pump();

    expect(find.textContaining(narrative), findsOneWidget,
        reason: '追加 tail 后正文必须原样保留');
    expect(find.text(AppLocalizationsZh().sessionSettlingStatus), findsNothing);
    expect(find.text('监测状态'), findsOneWidget);
    for (final option in options) {
      expect(find.text(option), findsOneWidget);
    }
    expect(find.textContaining('90/100'), findsOneWidget);
    expect(find.textContaining('"options"'), findsNothing,
        reason: '原始结算 JSON 不允许显示给用户');
    expect(tester.takeException(), isNull);

    // ─── committed：同一帧内 message 入列 + pending 释放，正文无感替换 ───
    cp.messages.add(Message(id: 'a1', content: settled, isUser: false));
    cp.debugSetPendingAssistantPresentation(
      phase: PendingAssistantPhase.none,
    );
    reload(cp);
    await tester.pumpAndSettle();

    expect(find.textContaining(narrative), findsOneWidget,
        reason: 'commit 后正文仍然只出现一次');
    expect(find.text('监测状态'), findsOneWidget);
    for (final option in options) {
      expect(find.text(option), findsOneWidget);
    }
    expect(find.text(AppLocalizationsZh().sessionSettlingStatus), findsNothing);
    expect(find.byType(PendingAssistantBubble), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'pending bubble renders without overflow at every required viewport '
      'and at large text scale', (tester) async {
    for (final viewport in requiredUiViewports) {
      setViewport(tester, width: viewport.width, height: viewport.height);
      final cp = await pumpList(tester);
      cp.messages.add(Message(id: 'u1', content: '继续', isUser: true));
      cp.debugSetPendingAssistantPresentation(
        content: settledContent(),
        phase: PendingAssistantPhase.settled,
      );
      reload(cp);
      await tester.pump();

      expect(tester.takeException(), isNull, reason: '$viewport');
      expect(find.textContaining(narrative), findsOneWidget,
          reason: '$viewport');
    }

    // 大字号 + 320px 最低宽度：直接渲染 pending 气泡本体。
    setViewport(tester, width: 320, height: 568);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: PendingAssistantBubble(
                content: narrative,
                chatFontSize: 14,
                brightness: Brightness.light,
                aiName: '冒险助手',
                footer: SessionSettlingHint(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining(narrative), findsOneWidget);
    expect(
        find.text(AppLocalizationsZh().sessionSettlingStatus), findsOneWidget);
  });
}
