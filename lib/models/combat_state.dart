import 'dart:math';
import 'skill.dart';

/// 战斗状态机
class CombatState {
  List<CombatUnit> enemies;
  int turnNumber;
  CombatPhase phase;
  List<String> combatLog;
  Map<String, int> playerBuffs;
  Map<String, int> enemyBuffs;
  bool isActive;

  CombatState({
    List<CombatUnit>? enemies,
    this.turnNumber = 1,
    this.phase = CombatPhase.playerTurn,
    List<String>? combatLog,
    Map<String, int>? playerBuffs,
    Map<String, int>? enemyBuffs,
    this.isActive = true,
  })  : enemies = enemies ?? [],
        combatLog = combatLog ?? [],
        playerBuffs = playerBuffs ?? {},
        enemyBuffs = enemyBuffs ?? {};

  static final _random = Random();

  /// D20 骰子 (1-20)
  int rollD20() => _random.nextInt(20) + 1;

  /// 伤害计算
  int calculateDamage(CombatUnit attacker, CombatUnit defender,
      {Skill? skill}) {
    final atkBuff = attacker.buffs['atk_bonus'] ?? 0;
    final defBuff = defender.buffs['def_bonus'] ?? 0;
    final baseAtk = attacker.atk + atkBuff;
    final baseDef = defender.def + defBuff;
    final roll = rollD20();
    final critMultiplier = roll >= 19 ? 2.5 : (roll >= 17 ? 2.0 : 1.0);
    final skillDmg =
        skill?.getEffect('damage_min', skill is CharacterSkill ? 1 : 1) ??
            (_random.nextInt(6) + 1);
    return max(1, ((baseAtk + skillDmg) * critMultiplier - baseDef).round());
  }

  /// 逃跑成功率
  double get fleeChance => 0.6; // base 60%

  bool tryFlee() => _random.nextDouble() < fleeChance;

  /// 检查战斗是否结束
  bool get isVictory => enemies.every((e) => e.isDead);
  bool get isDefeat => false; // player defeat handled separately

  CombatState copyWith({
    List<CombatUnit>? enemies,
    int? turnNumber,
    CombatPhase? phase,
    List<String>? combatLog,
    Map<String, int>? playerBuffs,
    Map<String, int>? enemyBuffs,
    bool? isActive,
  }) =>
      CombatState(
        enemies: enemies ?? this.enemies,
        turnNumber: turnNumber ?? this.turnNumber,
        phase: phase ?? this.phase,
        combatLog: combatLog ?? this.combatLog,
        playerBuffs: playerBuffs ?? this.playerBuffs,
        enemyBuffs: enemyBuffs ?? this.enemyBuffs,
        isActive: isActive ?? this.isActive,
      );
}

enum CombatPhase { playerTurn, enemyTurn, victory, defeat, escaped }

/// 战斗行动类型
enum CombatAction { attack, skill, defend, item, flee }

/// 战斗单位
class CombatUnit {
  final String id;
  final String name;
  final String icon;
  final int maxHp;
  int currentHp;
  int atk;
  int def;
  int speed;
  final List<Skill> skills;
  final Map<String, int> buffs;

  CombatUnit({
    required this.id,
    required this.name,
    this.icon = '👤',
    required this.maxHp,
    int? currentHp,
    this.atk = 10,
    this.def = 3,
    this.speed = 5,
    List<Skill>? skills,
    Map<String, int>? buffs,
  })  : currentHp = currentHp ?? maxHp,
        skills = skills ?? [],
        buffs = buffs ?? {};

  bool get isDead => currentHp <= 0;

  void takeDamage(int dmg) {
    currentHp = max(0, currentHp - dmg);
  }

  CombatUnit copyWith({
    int? currentHp,
    int? atk,
    int? def,
    int? speed,
    List<Skill>? skills,
    Map<String, int>? buffs,
  }) =>
      CombatUnit(
        id: id,
        name: name,
        icon: icon,
        maxHp: maxHp,
        currentHp: currentHp ?? this.currentHp,
        atk: atk ?? this.atk,
        def: def ?? this.def,
        speed: speed ?? this.speed,
        skills: skills ?? this.skills,
        buffs: buffs ?? this.buffs,
      );
}
