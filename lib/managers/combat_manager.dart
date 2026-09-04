import 'package:flutter/foundation.dart';
import 'dart:math';
import '../models/combat_state.dart';
import '../models/game_state.dart';
import '../models/skill.dart';

// CombatAction enum moved to lib/models/combat_state.dart

/// 战斗行动结果
class CombatTurnResult {
  final String actorName;
  final String action;
  final String? targetName;
  final int? damage;
  final bool isCrit;
  final String description;
  final bool isVictory;
  final bool isDefeat;
  final bool escaped;
  final Map<String, int>? effects;

  const CombatTurnResult({
    required this.actorName,
    required this.action,
    this.targetName,
    this.damage,
    this.isCrit = false,
    this.description = '',
    this.isVictory = false,
    this.isDefeat = false,
    this.escaped = false,
    this.effects,
  });
}

/// 战斗奖励
class CombatReward {
  final int exp;
  final int gold;
  final List<String> items;

  const CombatReward({
    this.exp = 0,
    this.gold = 0,
    this.items = const [],
  });
}

/// 战斗管理器
class CombatManager {
  CombatState? _active;
  final Random _random = Random();

  /// 获取游戏状态
  final GameState Function() getGameState;

  /// 设置游戏状态
  final void Function(GameState) setGameState;

  /// 获取所有技能（用于 combat skill lookup）
  final List<Skill> Function() getAllSkills;

  /// 获取角色技能
  final List<CharacterSkill> Function(String charId) getCharacterSkills;

  /// 通知 UI
  final VoidCallback? notifyUI;

  CombatManager({
    required this.getGameState,
    required this.setGameState,
    required this.getAllSkills,
    required this.getCharacterSkills,
    this.notifyUI,
  });

  VoidCallback get _notify => notifyUI ?? () {};

  bool get isActive => _active?.isActive ?? false;
  CombatState? get activeCombat => _active;

  /// 进入战斗（AI 返回 combat:true 时触发）
  void enter(List<CombatUnit> enemies, GameState? playerState) {
    _active = CombatState(
      enemies: enemies,
      turnNumber: 1,
      phase: CombatPhase.playerTurn,
      isActive: true,
    );
    _notify();
  }

  /// 退出战斗
  void exit() {
    _active?.isActive = false;
    _active = null;
    _notify();
  }

  /// 玩家行动
  CombatTurnResult playerAct(CombatAction action,
      {String? skillId, String? targetId}) {
    final combat = _active;
    if (combat == null || !combat.isActive) {
      return const CombatTurnResult(
          actorName: '', action: '', description: '不在战斗中');
    }
    if (combat.phase != CombatPhase.playerTurn) {
      return const CombatTurnResult(
          actorName: '', action: '', description: '不是你的回合');
    }

    final gameState = getGameState();
    // v2.1: Low energy penalty
    final energyPenalty = gameState.isExhausted ? 0.8 : 1.0;
    final player = CombatUnit(
      id: 'player',
      name: '主角',
      icon: '👤',
      maxHp: gameState.maxHp,
      currentHp: gameState.hp,
      atk: (gameState.baseAtk * energyPenalty).round(),
      def: (gameState.baseDef * energyPenalty).round(),
      speed: (gameState.baseSpeed * energyPenalty).round(),
    );

    CombatTurnResult result;

    switch (action) {
      case CombatAction.attack:
        result = _doAttack(player, combat, targetId);
        break;
      case CombatAction.skill:
        result = _doSkill(player, combat, skillId, targetId);
        break;
      case CombatAction.defend:
        result = _doDefend(player, combat);
        break;
      case CombatAction.item:
        result = _doItem(player, combat);
        break;
      case CombatAction.flee:
        result = _doFlee(combat);
        break;
    }

    // 检查胜利
    if (combat.isVictory) {
      combat.phase = CombatPhase.victory;
      _applySettle();
    } else {
      combat.phase = CombatPhase.enemyTurn;
    }

    _notify();
    return result;
  }

  /// 敌方 AI 回合
  List<CombatTurnResult> enemyTurn() {
    final combat = _active;
    if (combat == null || !combat.isActive) return [];
    if (combat.phase != CombatPhase.enemyTurn) return [];

    final gameState = getGameState();
    final energyPenalty = gameState.isExhausted ? 0.8 : 1.0;
    final player = CombatUnit(
      id: 'player',
      name: '主角',
      icon: '👤',
      maxHp: gameState.maxHp,
      currentHp: gameState.hp,
      atk: (gameState.baseAtk * energyPenalty).round(),
      def: (gameState.baseDef * energyPenalty).round(),
      speed: (gameState.baseSpeed * energyPenalty).round(),
    );

    final results = <CombatTurnResult>[];
    for (final enemy in combat.enemies.where((e) => !e.isDead)) {
      // 敌人 AI：随机选择攻击或技能
      final useSkill = _random.nextDouble() < 0.3 && enemy.skills.isNotEmpty;
      if (useSkill) {
        // Enemy uses a random skill
        final skill = enemy.skills[_random.nextInt(enemy.skills.length)];
        results.add(_enemySkill(enemy, player, combat, skill));
      } else {
        results.add(_enemyAttack(enemy, player, combat));
      }
    }

    // 检查玩家是否战败
    final newHp = gameState.hp;
    if (newHp <= 0) {
      combat.phase = CombatPhase.defeat;
      combat.isActive = false;
    } else {
      // 新回合
      combat.phase = CombatPhase.playerTurn;
    }

    _notify();
    return results;
  }

  /// 结算（经验/金币）
  CombatReward settle() {
    final combat = _active;
    if (combat == null) return const CombatReward();

    final totalExp =
        combat.enemies.fold<int>(0, (sum, e) => sum + (e.atk ~/ 2));
    final goldReward = 10 + _random.nextInt(totalExp ~/ 2 + 1);

    // Apply to game state
    final gameState = getGameState();
    setGameState(gameState.copyWith(
      gold: gameState.gold + goldReward,
      experience: gameState.experience + totalExp,
    ));

    return CombatReward(exp: totalExp, gold: goldReward);
  }

  void _applySettle() {
    final combat = _active;
    if (combat == null || !combat.isVictory) return;

    final reward = settle();
    combat.combatLog.add('🎉 战斗胜利！获得 ${reward.exp} EXP, ${reward.gold} 金币');
    combat.phase = CombatPhase.victory;
  }

  // ─── 战斗行动实现 ───

  CombatTurnResult _doAttack(
      CombatUnit player, CombatState combat, String? targetId) {
    final target = _findTarget(combat, targetId);
    if (target == null) {
      return const CombatTurnResult(
          actorName: '主角', action: '攻击', description: '没有可攻击的目标');
    }

    final roll = combat.rollD20();
    final isCrit = roll >= 17;
    final critMultiplier = roll >= 19 ? 2.5 : (isCrit ? 2.0 : 1.0);
    final dmg =
        (max(1, (player.atk * critMultiplier - target.def).round())).toInt();
    target.takeDamage(dmg);

    final desc = isCrit ? '暴击！造成 $dmg 点伤害' : '造成 $dmg 点伤害';
    combat.combatLog
        .add('⚔️ ${player.name} 攻击 ${target.name} — $desc (D20=$roll)');

    // Update game state from damage taken during enemy turn
    final gameState = getGameState();
    setGameState(gameState.copyWith(hp: player.currentHp));

    return CombatTurnResult(
      actorName: player.name,
      action: '攻击',
      targetName: target.name,
      damage: dmg,
      isCrit: isCrit,
      description: desc,
      isVictory: combat.isVictory,
    );
  }

  CombatTurnResult _doSkill(CombatUnit player, CombatState combat,
      String? skillId, String? targetId) {
    final target = _findTarget(combat, targetId);
    if (target == null) {
      return const CombatTurnResult(
          actorName: '主角', action: '技能', description: '没有可攻击的目标');
    }
    if (skillId == null) {
      return const CombatTurnResult(
          actorName: '主角', action: '技能', description: '请选择技能');
    }

    // Look up skill from available skills
    final skills = getAllSkills();
    final skill = skills.cast<Skill?>().firstWhere(
          (s) => s!.id == skillId,
          orElse: () => null,
        );
    if (skill == null) {
      return const CombatTurnResult(
          actorName: '主角', action: '技能', description: '技能不存在');
    }

    final charSkills = getCharacterSkills('player');
    final cs = charSkills.cast<CharacterSkill?>().firstWhere(
          (c) => c!.skillId == skillId,
          orElse: () => null,
        );
    final level = cs?.currentLevel ?? 1;

    final roll = combat.rollD20();
    final isCrit = roll >= 17;
    final critMultiplier = roll >= 19 ? 2.5 : (isCrit ? 2.0 : 1.0);
    final skillDmg = skill.getEffect('damage_min', level);
    final skillDmgMax = skill.getEffect('damage_max', level);
    final actualSkillDmg = skillDmg +
        (skillDmgMax > skillDmg
            ? _random.nextInt(skillDmgMax - skillDmg + 1)
            : 0);
    final dmg = (max(
            1,
            ((player.atk + actualSkillDmg) * critMultiplier - target.def)
                .round()))
        .toInt();
    target.takeDamage(dmg);

    final desc =
        isCrit ? '暴击！${skill.name}造成 $dmg 点伤害' : '${skill.name}造成 $dmg 点伤害';
    combat.combatLog.add(
        '🔥 ${player.name} 使用 ${skill.name} → ${target.name} — $desc (D20=$roll)');

    // Deduct MP (handled by SkillManager externally)
    final gameState = getGameState();
    final mpCost = skill.getMpCost(level);
    setGameState(gameState.copyWith(
      hp: player.currentHp,
      mp: max(0, gameState.mp - mpCost),
    ));

    return CombatTurnResult(
      actorName: player.name,
      action: '技能:${skill.name}',
      targetName: target.name,
      damage: dmg,
      isCrit: isCrit,
      description: desc,
      isVictory: combat.isVictory,
      effects: {'mp_cost': mpCost},
    );
  }

  CombatTurnResult _doDefend(CombatUnit player, CombatState combat) {
    player.buffs['def_bonus'] = (player.buffs['def_bonus'] ?? 0) + 10;
    combat.combatLog.add('🛡️ ${player.name} 防御 — 防御力+10 (本回合)');
    return CombatTurnResult(
      actorName: player.name,
      action: '防御',
      description: '防御力提升10点',
    );
  }

  CombatTurnResult _doItem(CombatUnit player, CombatState combat) {
    // Simplified: use a healing item
    final healAmount = 20 + _random.nextInt(11);
    final gameState = getGameState();
    final newHp = min(gameState.hp + healAmount, gameState.maxHp);
    setGameState(gameState.copyWith(hp: newHp));
    player.currentHp = newHp;

    combat.combatLog.add('💊 ${player.name} 使用回复道具 — 回复 $healAmount HP');
    return CombatTurnResult(
      actorName: player.name,
      action: '道具',
      description: '回复 $healAmount HP',
      effects: {'heal': healAmount},
    );
  }

  CombatTurnResult _doFlee(CombatState combat) {
    final success = combat.tryFlee();
    if (success) {
      combat.phase = CombatPhase.escaped;
      combat.isActive = false;
      combat.combatLog.add('🏃 逃跑成功！');
    } else {
      combat.combatLog.add('🏃 逃跑失败...');
    }
    return CombatTurnResult(
      actorName: '主角',
      action: '逃跑',
      escaped: success,
      description: success ? '逃跑成功' : '逃跑失败',
    );
  }

  // ─── 敌方行动 ───

  CombatTurnResult _enemyAttack(
      CombatUnit enemy, CombatUnit player, CombatState combat) {
    final roll = combat.rollD20();
    final isCrit = roll >= 17;
    final critMultiplier = roll >= 19 ? 2.5 : (isCrit ? 2.0 : 1.0);
    final dmg =
        (max(1, (enemy.atk * critMultiplier - player.def).round())).toInt();

    // Consider player defense buff
    final defBuff = player.buffs['def_bonus'] ?? 0;
    final actualDmg = max(1, dmg - defBuff);
    player.takeDamage(actualDmg);

    // Reset defense buff after use
    player.buffs['def_bonus'] = 0;

    final desc = isCrit ? '暴击！造成 $actualDmg 点伤害' : '造成 $actualDmg 点伤害';
    combat.combatLog.add('👊 ${enemy.name} 攻击 — $desc (D20=$roll)');

    // Update game state HP
    final gameState = getGameState();
    setGameState(gameState.copyWith(hp: player.currentHp));

    return CombatTurnResult(
      actorName: enemy.name,
      action: '攻击',
      targetName: player.name,
      damage: actualDmg,
      isCrit: isCrit,
      description: desc,
      isDefeat: player.isDead,
    );
  }

  CombatTurnResult _enemySkill(
      CombatUnit enemy, CombatUnit player, CombatState combat, Skill skill) {
    final roll = combat.rollD20();
    final isCrit = roll >= 17;
    final critMultiplier = roll >= 19 ? 2.5 : (isCrit ? 2.0 : 1.0);
    final skillDmg = skill.getEffect('damage_min', 1);
    final dmg =
        (max(1, ((enemy.atk + skillDmg) * critMultiplier - player.def).round()))
            .toInt();
    player.takeDamage(dmg);

    final desc =
        isCrit ? '暴击！${skill.name}造成 $dmg 点伤害' : '${skill.name}造成 $dmg 点伤害';
    combat.combatLog
        .add('💥 ${enemy.name} 使用 ${skill.name} — $desc (D20=$roll)');

    final gameState = getGameState();
    setGameState(gameState.copyWith(hp: player.currentHp));

    return CombatTurnResult(
      actorName: enemy.name,
      action: '技能:${skill.name}',
      targetName: player.name,
      damage: dmg,
      isCrit: isCrit,
      description: desc,
      isDefeat: player.isDead,
    );
  }

  // ─── 辅助方法 ───

  CombatUnit? _findTarget(CombatState combat, String? targetId) {
    final alive = combat.enemies.where((e) => !e.isDead).toList();
    if (alive.isEmpty) return null;
    if (targetId != null) {
      return alive.cast<CombatUnit?>().firstWhere(
                (e) => e!.id == targetId,
                orElse: () => null,
              ) ??
          alive.first;
    }
    return alive.first; // default: first alive enemy
  }

  /// 从 AI JSON 创建敌人
  static List<CombatUnit> enemiesFromJson(List<dynamic>? json) {
    if (json == null || json.isEmpty) return [];
    return json.map((e) {
      final map = e as Map<String, dynamic>;
      return CombatUnit(
        id: map['id'] as String? ??
            'enemy_${DateTime.now().millisecondsSinceEpoch}',
        name: map['name'] as String? ?? '敌人',
        icon: map['icon'] as String? ?? '👹',
        maxHp: map['max_hp'] as int? ?? 50,
        currentHp: map['hp'] as int?,
        atk: map['atk'] as int? ?? 8,
        def: map['def'] as int? ?? 3,
        speed: map['speed'] as int? ?? 5,
      );
    }).toList();
  }
}
