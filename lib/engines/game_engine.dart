import '../managers/combat_manager.dart';
import '../managers/quest_manager.dart';
import '../managers/skill_manager.dart';
import '../managers/affinity_manager.dart';
import '../managers/inventory_manager.dart';
import '../managers/encounter_manager.dart';

// Re-export all types for backward compatibility
export '../managers/combat_manager.dart';
export '../managers/quest_manager.dart';
export '../managers/skill_manager.dart';
export '../managers/affinity_manager.dart';
export '../managers/inventory_manager.dart';
export '../managers/encounter_manager.dart';

/// P1-02: GameEngine — RPG 游戏机制统一入口
///
/// 合并 CombatManager / QuestManager / SkillManager / AffinityManager /
/// InventoryManager / EncounterManager 六个 Manager。
/// v2.7 P0: DI 激活 — 所有 Manager 现在通过 AdventureProvider 注入。
class GameEngine {
  final CombatManager combatMgr;
  final QuestManager questMgr;
  final SkillManager skillMgr;
  final AffinityManager affinityMgr;
  final InventoryManager inventoryMgr;

  /// EncounterManager 是全静态工具类，无需实例化。
  /// 通过 [EncounterManager.rollEncounter] / [EncounterManager.getRandomEnemy] 直接调用。

  GameEngine({
    required this.combatMgr,
    required this.questMgr,
    required this.skillMgr,
    required this.affinityMgr,
    required this.inventoryMgr,
  });
}
