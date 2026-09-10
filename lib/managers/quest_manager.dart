import 'package:flutter/foundation.dart';
import 'dart:math';
import '../models/quest.dart';

/// 任务管理器
class QuestManager {
  /// 获取任务列表
  final Future<List<Map<String, dynamic>>> Function(int adventureId) getQuests;

  /// 保存任务
  final Future<void> Function(Map<String, dynamic> quest) saveQuest;

  /// 更新任务
  final Future<void> Function(String id, Map<String, dynamic> updates)
      updateQuest;

  /// 删除任务
  final Future<void> Function(String id) deleteQuest;

  /// 获取当前游戏状态
  final dynamic Function() getGameState;

  /// 设置游戏状态
  final void Function(dynamic) setGameState;

  /// 通知 UI
  final VoidCallback? notifyUI;

  /// 当前活跃任务缓存
  List<Quest> _activeQuests = [];

  QuestManager({
    required this.getQuests,
    required this.saveQuest,
    required this.updateQuest,
    required this.deleteQuest,
    required this.getGameState,
    required this.setGameState,
    this.notifyUI,
  });

  VoidCallback get _notify => notifyUI ?? () {};

  /// 加载冒险的所有任务
  Future<List<Quest>> loadQuests(int adventureId) async {
    final rows = await getQuests(adventureId);
    _activeQuests = rows.map((r) => Quest.fromRow(r)).toList();
    return _activeQuests;
  }

  /// 获取活跃任务
  List<Quest> get activeQuests =>
      _activeQuests.where((q) => q.status == QuestStatus.active).toList();

  /// 获取已完成任务
  List<Quest> get completedQuests =>
      _activeQuests.where((q) => q.status == QuestStatus.completed).toList();

  /// 创建任务
  Future<Quest> createQuest({
    required int adventureId,
    required String title,
    String description = '',
    QuestType type = QuestType.side,
    List<QuestObjective>? objectives,
    List<QuestReward>? rewards,
    String? giverNpcId,
  }) async {
    final id =
        'quest_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}';
    final now = DateTime.now().toIso8601String();
    final quest = Quest(
      id: id,
      adventureId: adventureId,
      title: title,
      description: description,
      type: type,
      status: QuestStatus.active,
      objectives: objectives ?? [],
      rewards: rewards ?? [],
      giverNpcId: giverNpcId,
      createdAt: now,
    );

    await saveQuest(quest.toRow());
    _activeQuests.add(quest);
    _notify();
    return quest;
  }

  /// 更新任务进度
  Future<void> updateProgress(String questId,
      {int objectiveIndex = 0, int increment = 1}) async {
    final quest = _activeQuests.firstWhere(
      (q) => q.id == questId,
      orElse: () => Quest(
        id: questId,
        adventureId: 0,
        title: '',
        createdAt: '',
      ),
    );
    if (quest.id != questId) return; // not found

    if (objectiveIndex < 0 || objectiveIndex >= quest.objectives.length) return;

    final obj = quest.objectives[objectiveIndex];
    obj.currentCount = (obj.currentCount + increment).clamp(0, obj.targetCount);

    // Persist updated objectives
    await updateQuest(questId, {
      'objectives_json': quest.toRow()['objectives_json'],
    });
    _notify();
  }

  /// 检查并自动完成任务
  Future<List<Quest>> checkCompletions() async {
    final completed = <Quest>[];
    for (final quest in _activeQuests) {
      if (quest.status != QuestStatus.active) continue;
      if (quest.progress >= 1.0) {
        quest.status = QuestStatus.completed;
        quest.completedAt = DateTime.now().toIso8601String();
        await updateQuest(quest.id, {
          'status': 'completed',
          'completed_at': quest.completedAt,
        });

        // 发放奖励
        _grantRewards(quest);
        completed.add(quest);
      }
    }
    if (completed.isNotEmpty) _notify();
    return completed;
  }

  /// 发放任务奖励
  void _grantRewards(Quest quest) {
    try {
      final gameState = getGameState();
      if (gameState == null) return;

      int goldBonus = 0;
      int expBonus = 0;

      for (final reward in quest.rewards) {
        switch (reward.type) {
          case RewardType.gold:
            goldBonus += reward.amount;
            break;
          case RewardType.exp:
            expBonus += reward.amount;
            break;
          case RewardType.item:
            // Item granting handled by inventory manager
            break;
          case RewardType.skill:
            // Skill granting handled by skill manager
            break;
          case RewardType.affinity:
            // Affinity handled by affinity manager
            break;
        }
      }

      if (goldBonus > 0 || expBonus > 0) {
        setGameState(gameState.copyWith(
          gold: gameState.gold + goldBonus,
          experience: gameState.experience + expBonus,
        ));
      }
    } catch (_) {
      // Non-critical path
    }
  }

  /// 从 AI 触发创建任务
  Future<Quest?> handleAiTrigger(
      int adventureId, Map<String, dynamic> trigger) async {
    try {
      final title = trigger['title'] as String?;
      if (title == null || title.isEmpty) return null;

      final objectives = (trigger['objectives'] as List<dynamic>?)
              ?.map((o) => QuestObjective(
                    description: o['description'] as String? ?? '',
                    targetCount: o['target_count'] as int? ?? 1,
                    type: ObjectiveType.values.firstWhere(
                      (e) => e.name == o['type'],
                      orElse: () => ObjectiveType.collect,
                    ),
                  ))
              .toList() ??
          [];

      final rewards = (trigger['rewards'] as List<dynamic>?)
              ?.map((r) => QuestReward(
                    type: RewardType.values.firstWhere(
                      (e) => e.name == r['type'],
                      orElse: () => RewardType.gold,
                    ),
                    amount: r['amount'] as int? ?? 0,
                  ))
              .toList() ??
          [];

      // 任务持久化失败也属于本入口承诺处理的 AI 触发失败，必须在 try 内等待。
      return await createQuest(
        adventureId: adventureId,
        title: title,
        description: trigger['description'] as String? ?? '',
        type: _parseQuestType(trigger['quest_type'] as String?),
        objectives: objectives,
        rewards: rewards,
        giverNpcId: trigger['giver_npc_id'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  QuestType _parseQuestType(String? type) {
    if (type == null) return QuestType.side;
    return QuestType.values.firstWhere(
      (e) => e.name == type,
      orElse: () => QuestType.side,
    );
  }

  /// 生成 AI 提示词注入文本
  String getPromptSummary(List<Quest>? quests) {
    final list = quests ?? activeQuests;
    if (list.isEmpty) return '';

    final buf = StringBuffer();
    buf.writeln('【当前任务】');
    for (final quest in list) {
      final typeIcon = switch (quest.type) {
        QuestType.main => '⭐',
        QuestType.side => '📌',
        QuestType.random => '🎲',
        QuestType.achievement => '🎯',
      };
      final status = quest.status == QuestStatus.completed ? '✅' : '';
      buf.write('$typeIcon $status ${quest.title}');
      buf.write(' (${quest.progressText})');

      // 显示未完成目标
      final incomplete = quest.objectives.where((o) => !o.isDone).toList();
      if (incomplete.isNotEmpty) {
        buf.write(' — ');
        buf.write(incomplete
            .map((o) => '${o.description}(${o.currentCount}/${o.targetCount})')
            .join(', '));
      }
      buf.writeln();
    }
    buf.writeln('当玩家完成以上任务目标时，请在 JSON 中附加 "quest_progress" 字段。');
    buf.writeln('任务全部目标完成时，附加 "quest_completed":"任务ID"。');
    return buf.toString();
  }
}
