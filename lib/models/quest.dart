import 'dart:convert';

/// 任务数据模型
class Quest {
  final String id;
  final int adventureId;
  final String title;
  final String description;
  final QuestType type;
  QuestStatus status;
  List<QuestObjective> objectives;
  List<QuestReward> rewards;
  final String? giverNpcId;
  final String createdAt;
  String? completedAt;
  final String? expiry;

  Quest({
    required this.id,
    required this.adventureId,
    required this.title,
    this.description = '',
    this.type = QuestType.side,
    this.status = QuestStatus.active,
    List<QuestObjective>? objectives,
    List<QuestReward>? rewards,
    this.giverNpcId,
    required this.createdAt,
    this.completedAt,
    this.expiry,
  })  : objectives = objectives ?? [],
        rewards = rewards ?? [];

  double get progress {
    if (objectives.isEmpty) return status == QuestStatus.completed ? 1.0 : 0.0;
    final done = objectives.fold<int>(0, (s, o) => s + (o.isDone ? 1 : 0));
    return done / objectives.length;
  }

  String get progressText => '${(progress * 100).round()}%';

  Map<String, dynamic> toRow() => {
        'id': id,
        'adventure_id': adventureId,
        'title': title,
        'description': description,
        'quest_type': type.name,
        'status': status.name,
        'objectives_json':
            jsonEncode(objectives.map((o) => o.toJson()).toList()),
        'rewards_json': jsonEncode(rewards.map((r) => r.toJson()).toList()),
        'giver_npc_id': giverNpcId,
        'created_at': createdAt,
        'completed_at': completedAt,
        'expiry': expiry,
      };

  factory Quest.fromRow(Map<String, dynamic> row) {
    List<QuestObjective> parseObjectives(String? json) {
      if (json == null || json.isEmpty) return [];
      try {
        return (jsonDecode(json) as List)
            .map((e) => QuestObjective.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        return [];
      }
    }

    List<QuestReward> parseRewards(String? json) {
      if (json == null || json.isEmpty) return [];
      try {
        return (jsonDecode(json) as List)
            .map((e) => QuestReward.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        return [];
      }
    }

    return Quest(
      id: row['id'] as String,
      adventureId: row['adventure_id'] as int? ?? 0,
      title: row['title'] as String? ?? '',
      description: row['description'] as String? ?? '',
      type: QuestType.values.firstWhere((e) => e.name == row['quest_type'],
          orElse: () => QuestType.side),
      status: QuestStatus.values.firstWhere((e) => e.name == row['status'],
          orElse: () => QuestStatus.active),
      objectives: parseObjectives(row['objectives_json'] as String?),
      rewards: parseRewards(row['rewards_json'] as String?),
      giverNpcId: row['giver_npc_id'] as String?,
      createdAt:
          row['created_at'] as String? ?? DateTime.now().toIso8601String(),
      completedAt: row['completed_at'] as String?,
      expiry: row['expiry'] as String?,
    );
  }

  Quest copyWith(
          {QuestStatus? status,
          String? completedAt,
          bool clearCompletedAt = false}) =>
      Quest(
        id: id,
        adventureId: adventureId,
        title: title,
        description: description,
        type: type,
        status: status ?? this.status,
        objectives: objectives,
        rewards: rewards,
        giverNpcId: giverNpcId,
        createdAt: createdAt,
        completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
        expiry: expiry,
      );
}

enum QuestType { main, side, random, achievement }

enum QuestStatus { active, completed, failed }

class QuestObjective {
  String description;
  int targetCount;
  int currentCount;
  ObjectiveType type;
  String? targetId;

  QuestObjective({
    this.description = '',
    this.targetCount = 1,
    this.currentCount = 0,
    this.type = ObjectiveType.collect,
    this.targetId,
  });

  bool get isDone => currentCount >= targetCount;

  Map<String, dynamic> toJson() => {
        'description': description,
        'target_count': targetCount,
        'current_count': currentCount,
        'type': type.name,
        'target_id': targetId,
      };

  factory QuestObjective.fromJson(Map<String, dynamic> json) => QuestObjective(
        description: json['description'] as String? ?? '',
        targetCount: json['target_count'] as int? ?? 1,
        currentCount: json['current_count'] as int? ?? 0,
        type: ObjectiveType.values.firstWhere((e) => e.name == json['type'],
            orElse: () => ObjectiveType.collect),
        targetId: json['target_id'] as String?,
      );

  QuestObjective copyWith({
    String? description,
    int? targetCount,
    int? currentCount,
    ObjectiveType? type,
    String? targetId,
    bool clearTargetId = false,
  }) =>
      QuestObjective(
        description: description ?? this.description,
        targetCount: targetCount ?? this.targetCount,
        currentCount: currentCount ?? this.currentCount,
        type: type ?? this.type,
        targetId: clearTargetId ? null : targetId ?? this.targetId,
      );
}

enum ObjectiveType { kill, collect, reach, talk, useSkill }

class QuestReward {
  RewardType type;
  int amount;
  String? itemId;
  String? skillId;

  QuestReward(
      {this.type = RewardType.gold,
      this.amount = 0,
      this.itemId,
      this.skillId});

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'amount': amount,
        'item_id': itemId,
        'skill_id': skillId,
      };

  factory QuestReward.fromJson(Map<String, dynamic> json) => QuestReward(
        type: RewardType.values.firstWhere((e) => e.name == json['type'],
            orElse: () => RewardType.gold),
        amount: json['amount'] as int? ?? 0,
        itemId: json['item_id'] as String?,
        skillId: json['skill_id'] as String?,
      );

  QuestReward copyWith({
    RewardType? type,
    int? amount,
    String? itemId,
    String? skillId,
  }) =>
      QuestReward(
        type: type ?? this.type,
        amount: amount ?? this.amount,
        itemId: itemId ?? this.itemId,
        skillId: skillId ?? this.skillId,
      );
}

enum RewardType { gold, exp, item, skill, affinity }
