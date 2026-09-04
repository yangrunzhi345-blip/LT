import 'dart:math';

import '../models/map_encounter.dart';

export '../models/map_encounter.dart';

/// 随机遭遇管理器
class EncounterManager {
  static final _random = Random();

  /// 随机物品池
  static const _randomItems = [
    {
      'name': '回复药',
      'icon': '🧪',
      'type': 'consumable',
      'data': {'heal_hp': 30}
    },
    {
      'name': '魔力药水',
      'icon': '💧',
      'type': 'consumable',
      'data': {'heal_mp': 20}
    },
    {
      'name': '干粮',
      'icon': '🍞',
      'type': 'consumable',
      'data': {'restore_energy': 15}
    },
    {
      'name': '金币袋',
      'icon': '💰',
      'type': 'consumable',
      'data': {'gold': 50}
    },
    {'name': '铁矿石', 'icon': '🪨', 'type': 'material', 'data': {}},
    {
      'name': '草药',
      'icon': '🌿',
      'type': 'material',
      'data': {'heal_hp': 10}
    },
    {
      'name': '解毒草',
      'icon': '🥬',
      'type': 'consumable',
      'data': {'cure_poison': 1}
    },
    {'name': '火之碎片', 'icon': '🔥', 'type': 'material', 'data': {}},
  ];

  /// 随机战斗敌人池
  static const _randomEnemies = [
    {
      'name': '哥布林',
      'icon': '👺',
      'hp': 25,
      'max_hp': 25,
      'atk': 6,
      'def': 2,
      'speed': 4
    },
    {
      'name': '野狼',
      'icon': '🐺',
      'hp': 30,
      'max_hp': 30,
      'atk': 8,
      'def': 3,
      'speed': 6
    },
    {
      'name': '骷髅兵',
      'icon': '💀',
      'hp': 35,
      'max_hp': 35,
      'atk': 7,
      'def': 4,
      'speed': 3
    },
    {
      'name': '史莱姆',
      'icon': '🟢',
      'hp': 20,
      'max_hp': 20,
      'atk': 4,
      'def': 1,
      'speed': 2
    },
    {
      'name': '山贼',
      'icon': '🥷',
      'hp': 40,
      'max_hp': 40,
      'atk': 9,
      'def': 4,
      'speed': 5
    },
  ];

  /// 掷骰遭遇（null = 无事发生）
  static MapEncounter? rollEncounter({bool isExplored = false}) {
    if (isExplored) return null; // 已探索节点无遭遇
    final roll = _random.nextInt(100);
    if (roll < 60) return null; // 60% 无事

    if (roll < 85) {
      // 25% 获得物品
      final item = _randomItems[_random.nextInt(_randomItems.length)];
      return MapEncounter.foundItem(
        item['name'] as String,
        item['icon'] as String,
        Map<String, dynamic>.from(item['data'] as Map),
      );
    }

    if (roll < 95) {
      // 10% 战斗
      return MapEncounter.combat();
    }

    // 5% 特殊事件
    return MapEncounter.specialEvent();
  }

  /// 获取随机敌人
  static Map<String, dynamic> getRandomEnemy() {
    final template = _randomEnemies[_random.nextInt(_randomEnemies.length)];
    return Map<String, dynamic>.from(template);
  }

  /// 获取多个随机敌人
  static List<Map<String, dynamic>> getRandomEnemies(
      {int minCount = 1, int maxCount = 3}) {
    final count = minCount + _random.nextInt(maxCount - minCount + 1);
    return List.generate(count, (_) => getRandomEnemy());
  }
}
