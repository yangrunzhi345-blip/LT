import 'package:flutter/foundation.dart';
import '../models/skill.dart';
import '../models/game_state.dart';

/// 技能学习结果
class SkillLearnResult {
  final bool success;
  final String message;
  final CharacterSkill? characterSkill;

  const SkillLearnResult(
      {required this.success, this.message = '', this.characterSkill});
}

/// 技能升级结果
class SkillUpgradeResult {
  final bool success;
  final String message;
  final int newLevel;

  const SkillUpgradeResult(
      {required this.success, this.message = '', this.newLevel = 1});
}

/// 技能使用结果
class SkillUseResult {
  final bool success;
  final String message;
  final Map<String, int> effects;
  final int expGained;
  final bool leveledUp;

  const SkillUseResult({
    required this.success,
    this.message = '',
    this.effects = const {},
    this.expGained = 0,
    this.leveledUp = false,
  });
}

/// 技能管理器
class SkillManager {
  /// 获取所有技能
  final Future<List<Skill>> Function() getAllSkills;

  /// 获取角色技能
  final Future<List<CharacterSkill>> Function(String charId) getCharacterSkills;

  /// 保存角色技能
  final Future<int> Function(CharacterSkill cs) saveCharacterSkill;

  /// 更新角色技能
  final Future<void> Function(int id, Map<String, dynamic> updates)
      updateCharacterSkill;

  /// 获取当前游戏状态
  final GameState Function() getGameState;

  /// 设置游戏状态
  final void Function(GameState) setGameState;

  /// 通知 UI 重建
  final VoidCallback? notifyUI;

  SkillManager({
    required this.getAllSkills,
    required this.getCharacterSkills,
    required this.saveCharacterSkill,
    required this.updateCharacterSkill,
    required this.getGameState,
    required this.setGameState,
    this.notifyUI,
  });

  VoidCallback get _notify => notifyUI ?? () {};

  /// 学习技能 — 检查前置技能等级和属性要求
  Future<SkillLearnResult> learnSkill(String charId, String skillId) async {
    final allSkills = await getAllSkills();
    final skill = allSkills.cast<Skill?>().firstWhere(
          (s) => s!.id == skillId,
          orElse: () => null,
        );
    if (skill == null) {
      return const SkillLearnResult(success: false, message: '技能不存在');
    }

    // 检查是否已学习
    final charSkills = await getCharacterSkills(charId);
    final existing = charSkills.cast<CharacterSkill?>().firstWhere(
          (cs) => cs!.skillId == skillId,
          orElse: () => null,
        );
    if (existing != null) {
      return const SkillLearnResult(success: false, message: '已学习过此技能');
    }

    final gameState = getGameState();

    // 检查前置技能
    if (skill.prerequisiteSkillId != null &&
        skill.prerequisiteSkillId!.isNotEmpty) {
      final prereq = charSkills.cast<CharacterSkill?>().firstWhere(
            (cs) => cs!.skillId == skill.prerequisiteSkillId,
            orElse: () => null,
          );
      if (prereq == null) {
        final prereqSkill = allSkills.cast<Skill?>().firstWhere(
              (s) => s!.id == skill.prerequisiteSkillId,
              orElse: () => null,
            );
        return SkillLearnResult(
          success: false,
          message:
              '需要先学习：${prereqSkill?.name ?? skill.prerequisiteSkillId} Lv.${skill.prerequisiteLevel}',
        );
      }
      if (prereq.currentLevel < skill.prerequisiteLevel) {
        final prereqSkill = allSkills.cast<Skill?>().firstWhere(
              (s) => s!.id == skill.prerequisiteSkillId,
              orElse: () => null,
            );
        return SkillLearnResult(
          success: false,
          message:
              '需要 ${prereqSkill?.name ?? skill.prerequisiteSkillId} 达到 Lv.${skill.prerequisiteLevel}',
        );
      }
    }

    // 检查属性要求
    if (skill.statRequirements != null) {
      final stats = <String, int>{
        'STR': gameState.baseAtk,
        'INT': gameState.mp > gameState.maxMp
            ? gameState.mp ~/ 2
            : gameState.mp, // rough INT proxy
        'DEF': gameState.baseDef,
        'SPD': gameState.baseSpeed,
      };
      for (final entry in skill.statRequirements!.entries) {
        final current = stats[entry.key] ?? 0;
        if (current < entry.value) {
          return SkillLearnResult(
            success: false,
            message: '需要 ${entry.key} ≥ ${entry.value}（当前 $current）',
          );
        }
      }
    }

    // 创建 CharacterSkill
    final cs = CharacterSkill(
      characterId: charId,
      characterType: 'player',
      skillId: skillId,
      currentLevel: 1,
      experience: 0,
    );
    final id = await saveCharacterSkill(cs);
    _notify();

    return SkillLearnResult(
      success: true,
      message: '学会了 ${skill.name}！',
      characterSkill: CharacterSkill(
        id: id,
        characterId: charId,
        skillId: skillId,
        currentLevel: 1,
        experience: 0,
      ),
    );
  }

  /// 升级技能 — 消耗技能点
  Future<SkillUpgradeResult> upgradeSkill(String charId, String skillId) async {
    final charSkills = await getCharacterSkills(charId);
    final cs = charSkills.cast<CharacterSkill?>().firstWhere(
          (cs) => cs!.skillId == skillId,
          orElse: () => null,
        );
    if (cs == null) {
      return const SkillUpgradeResult(success: false, message: '尚未学习此技能');
    }

    final allSkills = await getAllSkills();
    final skill = allSkills.cast<Skill?>().firstWhere(
          (s) => s!.id == skillId,
          orElse: () => null,
        );
    if (skill == null) {
      return const SkillUpgradeResult(success: false, message: '技能数据不存在');
    }

    if (cs.currentLevel >= skill.maxLevel) {
      return SkillUpgradeResult(
          success: false, message: '已达到最高等级', newLevel: cs.currentLevel);
    }

    // 消耗技能点：Lv1→Lv2 消耗 1 点，Lv2→Lv3 消耗 2 点，以此类推
    final cost = cs.currentLevel;
    final gameState = getGameState();
    if (gameState.skillPoints < cost) {
      return SkillUpgradeResult(
        success: false,
        message: '技能点不足（需要 $cost 点，当前 ${gameState.skillPoints} 点）',
        newLevel: cs.currentLevel,
      );
    }

    // 消耗技能点并升级
    final newState =
        gameState.copyWith(skillPoints: gameState.skillPoints - cost);
    setGameState(newState);

    final newLevel = cs.currentLevel + 1;
    await updateCharacterSkill(cs.id!, {
      'current_level': newLevel,
      'experience': 0,
    });
    _notify();

    return SkillUpgradeResult(
      success: true,
      message: '${skill.name} 升级到 Lv.$newLevel！',
      newLevel: newLevel,
    );
  }

  /// 使用技能 — 扣除 MP，计算效果，增加熟练度
  Future<SkillUseResult> useSkill(String charId, String skillId) async {
    final charSkills = await getCharacterSkills(charId);
    final cs = charSkills.cast<CharacterSkill?>().firstWhere(
          (cs) => cs!.skillId == skillId,
          orElse: () => null,
        );
    if (cs == null) {
      return const SkillUseResult(success: false, message: '尚未学习此技能');
    }

    final allSkills = await getAllSkills();
    final skill = allSkills.cast<Skill?>().firstWhere(
          (s) => s!.id == skillId,
          orElse: () => null,
        );
    if (skill == null) {
      return const SkillUseResult(success: false, message: '技能数据不存在');
    }

    final gameState = getGameState();
    final mpCost = skill.getMpCost(cs.currentLevel);

    // 被动技能不消耗MP
    if (skill.type != SkillType.passive && gameState.mp < mpCost) {
      return SkillUseResult(
        success: false,
        message: 'MP 不足（需要 $mpCost，当前 ${gameState.mp}）',
      );
    }

    // 扣除 MP
    if (skill.type != SkillType.passive) {
      final newState = gameState.copyWith(mp: gameState.mp - mpCost);
      setGameState(newState);
    }

    // 计算效果
    final effects = <String, int>{};
    for (final key in skill.baseEffects.keys) {
      effects[key] = skill.getEffect(key, cs.currentLevel);
    }

    // 增加熟练度经验
    const expGain = 10;
    final newExp = cs.experience + expGain;
    bool leveledUp = false;
    int newLevel = cs.currentLevel;
    int carryExp = newExp;

    // 检查升级（满 100 EXP 升级）
    const expNeeded = 100;
    if (newExp >= expNeeded && cs.currentLevel < skill.maxLevel) {
      newLevel = cs.currentLevel + 1;
      carryExp = newExp - expNeeded;
      leveledUp = true;
    }

    await updateCharacterSkill(cs.id!, {
      'current_level': newLevel,
      'experience': carryExp.clamp(0, 999),
    });
    _notify();

    return SkillUseResult(
      success: true,
      message:
          leveledUp ? '${skill.name} 升级到 Lv.$newLevel！' : '使用 ${skill.name}！',
      effects: effects,
      expGained: expGain,
      leveledUp: leveledUp,
    );
  }

  /// 获取角色已学习的技能列表
  Future<List<Skill>> getAvailableSkills(String charId) async {
    final allSkills = await getAllSkills();
    final charSkills = await getCharacterSkills(charId);
    final learnedIds = charSkills.map((cs) => cs.skillId).toSet();

    return allSkills.where((s) => learnedIds.contains(s.id)).toList();
  }

  /// 获取可解锁但未学习的技能
  Future<List<Skill>> getUnlockableSkills(String charId) async {
    final allSkills = await getAllSkills();
    final charSkills = await getCharacterSkills(charId);
    final learnedIds = charSkills.map((cs) => cs.skillId).toSet();
    final learnedLevels = <String, int>{};
    for (final cs in charSkills) {
      learnedLevels[cs.skillId] = cs.currentLevel;
    }

    return allSkills.where((skill) {
      if (learnedIds.contains(skill.id)) return false;

      // Check prerequisite
      if (skill.prerequisiteSkillId != null &&
          skill.prerequisiteSkillId!.isNotEmpty) {
        final currentPrereqLevel =
            learnedLevels[skill.prerequisiteSkillId] ?? 0;
        if (currentPrereqLevel < skill.prerequisiteLevel) return false;
      }

      return true;
    }).toList();
  }

  /// 获取角色技能关联（含等级和熟练度）
  Future<List<CharacterSkill>> getCharacterSkillList(String charId) async {
    return await getCharacterSkills(charId);
  }
}
