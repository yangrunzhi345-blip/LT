import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:lt_dialogue/screens/chat/widgets/message_bubble.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  group('DeepSeek Reasoning Chain Unit & Widget Tests', () {
    late Directory tempDir;
    late IAdventureRepository adventureRepo;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('lt_reasoning_test_');
      DatabaseService.customDbDir = tempDir.path;
      await DatabaseService.resetDatabase();
      adventureRepo =
          AdventureRepositoryImpl(getDb: () => DatabaseService.database);
    });

    tearDown(() async {
      await DatabaseService.resetDatabase();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('Message model correctly preserves reasoningContent', () {
      final msg = Message(
        id: 'msg-1',
        content: '这是最终的剧情回复。',
        reasoningContent: '思考过程：分析当前玩家的理智值与场景线索...',
        isUser: false,
      );

      expect(msg.reasoningContent, isNotNull);
      expect(msg.reasoningContent, contains('思考过程：分析当前玩家的理智值'));
      expect(msg.content, '这是最终的剧情回复。');

      final copied = msg.copyWith(
        content: '修改后的剧情',
      );
      expect(copied.content, '修改后的剧情');
      expect(copied.reasoningContent, msg.reasoningContent);

      final modifiedReasoning = msg.copyWith(
        reasoningContent: '新的思维链推演',
      );
      expect(modifiedReasoning.reasoningContent, '新的思维链推演');
    });

    test('AdventureRepository persists and restores reasoning_content',
        () async {
      final advId = await adventureRepo.createAdventure('推理链测试冒险', 
        AdventureConfig(name: '推理链测试冒险', worldview: '克苏鲁神话'),
      );
      

      final originalMsg = Message(
        id: '1',
        content: '你推开古宅沉重的橡木大门。',
        reasoningContent:
            '1. 分析玩家动作：推门入内\n2. 校验当前环境状态：暴雨夜、无光源\n3. 决定抛出环境叙事与感知检定选项',
        isUser: false,
      );

      await adventureRepo.insertMessage(advId, originalMsg);

      final messages = await adventureRepo.getMessages(advId);
      expect(messages.length, 1);
      expect(messages.first.content, '你推开古宅沉重的橡木大门。');
      expect(messages.first.reasoningContent, isNotNull);
      expect(messages.first.reasoningContent,
          contains('1. 分析玩家动作：推门入内'));
      expect(messages.first.reasoningContent,
          contains('3. 决定抛出环境叙事与感知检定选项'));

      // Also verify getMessagesByBranch
      final branchMessages =
          await adventureRepo.getMessagesByBranch(advId, 0);
      expect(branchMessages.length, 1);
      expect(branchMessages.first.reasoningContent,
          originalMsg.reasoningContent);
    });

    testWidgets('AiBubble renders collapsible ReasoningBlock and expands on tap',
        (tester) async {
      final testMessage = Message(
        id: 'msg-ai-1',
        content: '前方是一处幽暗的长廊。',
        reasoningContent: '深度思考推演：玩家选择向左移动，触发第3号暗雷。',
        isUser: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AiBubble(
                message: testMessage,
                chatFontSize: 14,
                brightness: Brightness.dark,
                aiName: '灵境引导者',
                emotion: '冷静',
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

      await tester.pumpAndSettle();

      // Verify AI name and narrative content render
      expect(find.text('灵境引导者'), findsOneWidget);
      expect(find.text('前方是一处幽暗的长廊。'), findsOneWidget);

      // Verify collapsed reasoning header shows
      expect(find.text('已深度思考 (点击展开思维链)'), findsOneWidget);
      expect(find.byIcon(Icons.psychology_rounded), findsOneWidget);

      // Tap to expand
      await tester.tap(find.text('已深度思考 (点击展开思维链)'));
      await tester.pumpAndSettle();

      // Now expanded: header changed and thought content is visible
      expect(find.text('思考过程 (点击收起)'), findsOneWidget);
      expect(find.text('深度思考推演：玩家选择向左移动，触发第3号暗雷。'),
          findsOneWidget);
      expect(find.text('复制思考过程'), findsOneWidget);

      // Tap again to collapse
      await tester.tap(find.text('思考过程 (点击收起)'));
      await tester.pumpAndSettle();
      expect(find.text('已深度思考 (点击展开思维链)'), findsOneWidget);
      expect(find.text('深度思考推演：玩家选择向左移动，触发第3号暗雷。'),
          findsNothing);
    });

    testWidgets(
        'StreamingBubble dynamically switches between thinking mode and content streaming',
        (tester) async {
      final streamNotifier = ValueNotifier<String>('');
      final reasoningStreamNotifier = ValueNotifier<String>('');
      final isThinkingNotifier = ValueNotifier<bool>(false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StreamingBubble(
                chatFontSize: 14,
                brightness: Brightness.dark,
                aiName: '灵境助手',
                streamNotifier: streamNotifier,
                reasoningStreamNotifier: reasoningStreamNotifier,
                isThinkingNotifier: isThinkingNotifier,
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // Initial state: waiting
      expect(find.text('正在撰写剧情...'), findsOneWidget);

      // Phase 1: Thinking streaming starts
      isThinkingNotifier.value = true;
      reasoningStreamNotifier.value = '正在梳理世界观设定...';
      await tester.pump();

      // Reasoning live view is shown
      expect(find.text('正在深度思考...'), findsOneWidget);
      expect(find.text('正在梳理世界观设定...'), findsOneWidget);

      // More reasoning chunks arrive
      reasoningStreamNotifier.value =
          '正在梳理世界观设定...\n确定判定规则：需要检定敏捷值。';
      await tester.pump();
      expect(find.text('正在梳理世界观设定...\n确定判定规则：需要检定敏捷值。'),
          findsOneWidget);

      // Phase 2: Thinking ends, narrative starts streaming
      isThinkingNotifier.value = false;
      streamNotifier.value = '你敏捷地跃过陷阱。';
      await tester.pump();

      // Narrative text appears
      expect(find.text('你敏捷地跃过陷阱。'), findsOneWidget);
      // Reasoning automatically collapses to header
      expect(find.text('已深度思考 (点击展开思维链)'), findsOneWidget);
    });

    test('CompletionParams converts correctly for DeepSeek V4 official API', () {
      // 1. 思考模式开启：传递 thinking 与 reasoning_effort，自适应采样省略 temperature/topP
      const thinkingParams = CompletionParams(
        enableThinking: true,
        reasoningEffort: 'high',
        temperature: 1.2,
        topP: 0.9,
        maxTokens: 4096,
      );
      final dsThinkingMap = thinkingParams.toRequestMap(
        isDeepSeek: true,
        model: 'deepseek-v4-flash',
      );
      expect(dsThinkingMap['thinking'], equals({'type': 'enabled'}));
      expect(dsThinkingMap['reasoning_effort'], equals('high'));
      expect(dsThinkingMap.containsKey('temperature'), isFalse);
      expect(dsThinkingMap.containsKey('top_p'), isFalse);
      expect(dsThinkingMap['max_tokens'], equals(4096));

      // 2. 思考模式关闭：传递 thinking: disabled，采样参数全面生效
      const nonThinkingParams = CompletionParams(
        enableThinking: false,
        temperature: 0.7,
        topP: 0.95,
        maxTokens: 2048,
        responseFormat: {'type': 'json_object'},
      );
      final dsNonThinkingMap = nonThinkingParams.toRequestMap(
        isDeepSeek: true,
        model: 'deepseek-v4-flash',
      );
      expect(dsNonThinkingMap['thinking'], equals({'type': 'disabled'}));
      expect(dsNonThinkingMap.containsKey('reasoning_effort'), isFalse);
      expect(dsNonThinkingMap['temperature'], equals(0.7));
      expect(dsNonThinkingMap['top_p'], equals(0.95));
      expect(dsNonThinkingMap['response_format'], equals({'type': 'json_object'}));

      // 3. LLMStreamResult 包含 KV Cache 命中度量指标
      const streamResult = LLMStreamResult(
        content: '剧情内容',
        reasoningContent: '推演过程',
        finishReason: LLMFinishReason.completed,
        responseCompleted: true,
        promptTokens: 1200,
        completionTokens: 350,
        promptCacheHitTokens: 1050,
        promptCacheMissTokens: 150,
      );
      expect(streamResult.promptCacheHitTokens, equals(1050));
      expect(streamResult.promptCacheMissTokens, equals(150));
    });
  });
}
