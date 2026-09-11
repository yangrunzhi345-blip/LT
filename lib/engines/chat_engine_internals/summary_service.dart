import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show VoidCallback;
import '../../models/message.dart';
import '../../models/game_state.dart';
import '../../models/quest.dart';
import '../../models/completion_params.dart';
import '../../models/llm_task.dart';
import '../../models/model_capabilities.dart';
import '../../services/llm_task_policy.dart';
import '../../services/repositories/adventure_repository.dart';
import '../chat_engine_host.dart';

class SummaryService {
  final IAdventureRepository _adventureRepo;
  final ChatEngineHost? host;
  bool _summaryInFlight = false;

  /// 触发摘要的消息数阈值
  static const summaryThreshold = 12;

  /// 保留最近 N 条消息不被摘要。
  ///
  /// 必须与 PromptBuilder 的智能窗口（最近 6 轮 = 12 条完整消息）对齐：
  /// 若小于窗口长度，同一段对话会同时以“时间线摘要 + 完整原文”两种形式
  /// 进入 Prompt，模型读到重复内容后会复述相似剧情并生成相似选项。
  static const summarizeRetainCount = retainFullRounds * 2;

  /// 两次摘要之间的冷却消息数
  static const summaryCooldownCount = 10;

  /// v2.1: 保留最近 N 轮的完整消息（每轮 = 用户消息 + AI 回复 = 2条消息）
  static const retainFullRounds = 6;

  SummaryService({
    required IAdventureRepository adventureRepo,
    this.host,
  }) : _adventureRepo = adventureRepo;

  /// v2.13: 构建当前游戏状态的结构化快照，供摘要 LLM 追踪状态变更。
  /// 返回紧凑的 JSON 字符串，包含 hp/gold/level/quests/affinities 等。
  static String buildStateSnapshot(
    GameState gs,
    List<Quest>? activeQuests,
    Map<String, int>? affinities,
  ) {
    final snapshot = <String, dynamic>{
      'hp': gs.hp,
      'max_hp': gs.maxHp,
      'energy': gs.energy,
      'gold': gs.gold,
      'level': gs.level,
      'experience': gs.experience,
      'mp': gs.mp,
      'base_atk': gs.baseAtk,
      'base_def': gs.baseDef,
      'base_speed': gs.baseSpeed,
      'skill_points': gs.skillPoints,
      'scene': gs.currentScene,
    };
    if (activeQuests != null && activeQuests.isNotEmpty) {
      snapshot['active_quests'] = activeQuests
          .map((q) => {
                'title': q.title,
                'status': q.status.name,
                'objectives': q.objectives
                    .map((o) =>
                        '${o.description}(${o.currentCount}/${o.targetCount})')
                    .toList(),
              })
          .toList();
    }
    if (affinities != null && affinities.isNotEmpty) {
      snapshot['affinities'] = affinities;
    }
    return const JsonEncoder.withIndent('  ').convert(snapshot);
  }

  void maybeSummarize({
    required ChatEngineHost host,
    required List<Message> messages,
    required int generation,
    required bool Function(int adventureId, int branchId, int generation)
        isCurrent,
    required int lastSummaryAt,
    required DateTime? lastSummaryTime,
    required Future<void> Function(
      List<Message> msgs,
      int upToIndex,
      int adventureId,
      int branchId,
      int generation,
    ) onGenerate,
  }) {
    final totalMsgs = messages.length;
    if (_summaryInFlight ||
        totalMsgs <= summaryThreshold ||
        host.currentAdventureId == null) {
      return;
    }

    if (lastSummaryAt > 0 && totalMsgs - lastSummaryAt < summaryCooldownCount) {
      return;
    }
    if (lastSummaryTime != null &&
        DateTime.now().difference(lastSummaryTime).inMinutes < 5) {
      return;
    }

    final capturedAdventureId = host.currentAdventureId;
    if (capturedAdventureId == null) return;
    final capturedBranchId = host.currentBranchId;
    final capturedMessages = List<Message>.from(messages);
    _summaryInFlight = true;
    unawaited(() async {
      try {
        final upTo =
            await _adventureRepo.getLatestSummaryUpToId(capturedAdventureId);
        if (!isCurrent(capturedAdventureId, capturedBranchId, generation)) {
          return;
        }

        final summarizeStart = upTo > 0 ? upTo : 0;
        const retainCount = summarizeRetainCount;
        final summarizeEnd = totalMsgs - retainCount;
        if (summarizeEnd <= summarizeStart) return;

        final toSummarize = capturedMessages
            .sublist(summarizeStart, summarizeEnd)
            .toList(growable: false);
        if (toSummarize.isEmpty) return;

        await onGenerate(toSummarize, summarizeEnd, capturedAdventureId,
            capturedBranchId, generation);
      } catch (_) {
        // 摘要是后台维护任务；失败不得形成未处理的异步异常。
      } finally {
        _summaryInFlight = false;
      }
    }());
  }

  Future<void> generateSummary({
    required List<Message> msgs,
    required int upToIndex,
    required ChatEngineHost host,
    required int adventureId,
    required int branchId,
    required int generation,
    required bool Function(int adventureId, int branchId, int generation)
        isCurrent,
    required void Function(String summary) onSuccess,
    required VoidCallback onNotify,
    String? stateSnapshot,
    String? previousStateSnapshot,
  }) async {
    if (!isCurrent(adventureId, branchId, generation)) return;

    // 尝试从已有摘要中提取时间线（如果存在，追加而非覆盖）
    final existingSummary =
        await _adventureRepo.getLatestSummary(adventureId, branchId: branchId);
    if (!isCurrent(adventureId, branchId, generation)) return;

    final existingTimeline =
        existingSummary != null && existingSummary.isNotEmpty
            ? '\n\n【已有时间线（勿重复）】\n$existingSummary'
            : '';

    // v2.13: 状态快照 — 帮助 LLM 追踪此期间的状态变更
    final stateSection = stateSnapshot != null && stateSnapshot.isNotEmpty
        ? '\n\n【本期状态】\n$stateSnapshot'
        : '';
    final prevStateSection =
        previousStateSnapshot != null && previousStateSnapshot.isNotEmpty
            ? '\n\n【上期快照】\n$previousStateSnapshot'
            : '';

    final systemPrompt = '你是一个冒险日志记录员。请从以下对话中提取关键事件，整理为时间线格式。'
        '\n\n规则：'
        '\n1. 按时间顺序列出关键事件，每条前面标序号'
        '\n2. 每条格式：[第X-Y轮] 事件描述（包含地点、涉及角色、重要结果）'
        '\n3. 必须严格基于提供的对话内容，禁止编造'
        '\n4. 每条控制在 30 字以内，总共不超过 15 条'
        '\n5. 保留未完待续的任务和悬念'
        '\n6. 【重要】若此期间发生状态变化，在对应时间线条目末尾附加变更标记，格式如下：'
        '\n   「HP-20」「HP+15」「金币+50」「Lv+1」「获得:物品名」「失去:物品名」「好感:角色名±N」「任务:任务名完成」'
        '\n   请参照【本期状态】与【上期快照】的差异，结合对话内容确定具体数值。'
        '\n   仅标注对话中实际发生的变更，禁止编造未发生的事件或数值。'
        '$existingTimeline'
        '$stateSection'
        '$prevStateSection';

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final messages = [
          {'role': 'system', 'content': systemPrompt},
          {
            'role': 'user',
            'content':
                '从以下冒险记录中提取时间线：\n\n${msgs.map((m) => '${m.isUser ? "玩家" : "旁白"}: ${m.content}').join('\n')}',
          },
        ];
        final summary = (await host.llmService.sendMessageStream(
          messages,
          (_) {},
          () {},
          // 时间线摘要是结构化抽取任务：任务策略显式关闭思考以降低延迟与成本。
          params: const LlmTaskResolver().resolve(
            task: LlmTask.summary,
            capabilities: ModelCapabilityRegistry.resolve(
              host.llmService.config.model,
            ),
            userParams: const CompletionParams(
              temperature: .2,
              maxTokens: 800,
            ),
          ),
        ))
            .trim();
        if (summary.isNotEmpty && summary.length < 500) {
          if (!isCurrent(adventureId, branchId, generation)) return;
          await _adventureRepo.saveSummary(adventureId, summary, upToIndex,
              branchId: branchId, stateSnapshot: stateSnapshot);
          if (!isCurrent(adventureId, branchId, generation)) return;
          onSuccess(summary);
          await cleanupOldSummaries(adventureId);
          onNotify();
          return;
        }
      } catch (_) {
        if (attempt < 2) {
          await Future.delayed(Duration(seconds: 3 * (attempt + 1)));
        }
      }
    }
  }

  Future<void> cleanupOldSummaries(int adventureId) async {
    try {
      await _adventureRepo.cleanupOldSummaries(adventureId);
    } catch (_) {}
  }
}
