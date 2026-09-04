import '../models/supporting_character.dart';

/// 好感度管理器
class AffinityManager {
  /// 好感度等级标签
  static const Map<int, String> affinityLabels = {
    0: '敌对',
    20: '陌生',
    40: '友好',
    60: '信任',
    80: '亲密',
  };

  /// 关键词 → 好感度变化映射
  static const _keywordMap = <String, int>{
    // 正面
    '谢谢你': 5, '感激': 5, '多谢': 5, '感谢': 4,
    '对不起': 3, '抱歉': 3, '原谅': 3,
    '喜欢你': 8, '爱你': 8, '喜欢': 5,
    '真厉害': 3, '佩服': 4, '好厉害': 3,
    '漂亮': 2, '美丽': 2, '帅气': 2,
    '好心': 3, '善良': 3, '温柔': 3,
    '请': 1, '拜托': 1,
    // 负面
    '滚开': -10, '讨厌': -8, '恶心': -8, '滚': -10,
    '背叛': -15, '欺骗': -12, '骗': -8,
    '混蛋': -10, '蠢货': -7, '白痴': -7,
    '恨你': -12, '恨': -8,
    '走开': -5, '别烦': -5,
    '说谎': -6, '撒谎': -6,
  };

  /// 获取好感度标签
  static String getLabel(int affinity) {
    if (affinity < 10) return affinityLabels[0]!;
    if (affinity < 30) return affinityLabels[20]!;
    if (affinity < 50) return affinityLabels[40]!;
    if (affinity < 70) return affinityLabels[60]!;
    return affinityLabels[80]!;
  }

  /// 根据好感度获取颜色索引（用于头像环）
  /// 返回 0=红(敌对), 1=橙(陌生), 2=黄(友好), 3=绿(信任), 4=蓝(亲密)
  static int getAffinityColorIndex(int affinity) {
    if (affinity < 10) return 0;
    if (affinity < 30) return 1;
    if (affinity < 50) return 2;
    if (affinity < 70) return 3;
    return 4;
  }

  /// 获取好感度对应的颜色（Material Color 格式）
  static int getAffinityColor(int affinity) {
    if (affinity < 10) return 0xFFEF4444; // red
    if (affinity < 30) return 0xFFF97316; // orange
    if (affinity < 50) return 0xFFEAB308; // yellow
    if (affinity < 70) return 0xFF22C55E; // green
    return 0xFF3B82F6; // blue
  }

  /// 本地关键词匹配（快速）
  /// 返回 Map<NPC名称, 好感度变化>
  Map<String, int> analyzeKeywords(String msg, List<SupportingCharacter> npcs) {
    final result = <String, int>{};
    if (msg.isEmpty) return result;

    // 检查消息中是否提到 NPC
    for (final npc in npcs) {
      if (!msg.contains(npc.name)) continue;

      int totalChange = 0;
      for (final entry in _keywordMap.entries) {
        if (msg.contains(entry.key)) {
          totalChange += entry.value;
        }
      }
      if (totalChange != 0) {
        result[npc.name] = totalChange;
      }
    }

    return result;
  }

  /// 分析用户消息，更新 NPC 好感度
  /// 返回好感度变化的 NPC 列表
  List<Map<String, dynamic>> applyAffinityChanges(
      String msg, List<SupportingCharacter> npcs) {
    final changes = analyzeKeywords(msg, npcs);
    final results = <Map<String, dynamic>>[];

    for (final entry in changes.entries) {
      final npc = npcs.firstWhere(
        (n) => n.name == entry.key,
        orElse: () => SupportingCharacter(),
      );
      if (npc.name.isEmpty) continue;

      final oldVal = npc.affinity;
      npc.affinity = (npc.affinity + entry.value).clamp(0, 100);
      final newVal = npc.affinity;

      final milestones = checkMilestones(npc.name, oldVal, newVal);
      results.add({
        'npc': npc.name,
        'oldAffinity': oldVal,
        'newAffinity': newVal,
        'change': entry.value,
        'milestones': milestones,
      });
    }

    return results;
  }

  /// 阈值触发事件（跨越 0/20/40/60/80 时）
  List<String> checkMilestones(String npcId, int oldVal, int newVal) {
    final milestones = <String>[];
    for (final threshold in affinityLabels.keys) {
      final crossedUp = oldVal < threshold && newVal >= threshold;
      final crossedDown = oldVal >= threshold && newVal < threshold;

      if (crossedUp) {
        milestones.add('${affinityLabels[threshold]} ($threshold)');
      } else if (crossedDown) {
        milestones.add('下降至${affinityLabels[threshold]}以下');
      }
    }
    return milestones;
  }

  /// AI 提示词注入
  String getPromptSummary(Map<String, int> affinities) {
    if (affinities.isEmpty) return '';

    final buf = StringBuffer();
    buf.writeln('【角色好感度】');
    for (final entry in affinities.entries) {
      final label = getLabel(entry.value);
      buf.writeln('  ${entry.key}: $label (${entry.value}/100)');
    }
    buf.writeln('当好感度发生显著变化时，请在 JSON 中附加 "affinity_change" 字段。');
    return buf.toString();
  }
}
