import 'dart:convert';

class GameState {
  int adventureId;
  int hp;
  int maxHp;
  int energy;
  int maxEnergy;
  int gold;
  List<String> inventory;
  int chapter;
  String currentScene;
  // v13: 技能系统属性
  int level;
  int experience;
  int mp;
  int maxMp;
  int baseAtk;
  int baseDef;
  int baseSpeed;
  int skillPoints;

  GameState({
    this.adventureId = 0,
    this.hp = 100,
    this.maxHp = 100,
    this.energy = 100,
    this.maxEnergy = 100,
    this.gold = 0,
    List<String>? inventory,
    this.chapter = 1,
    this.currentScene = '',
    this.level = 1,
    this.experience = 0,
    this.mp = 100,
    this.maxMp = 100,
    this.baseAtk = 5,
    this.baseDef = 3,
    this.baseSpeed = 5,
    this.skillPoints = 0,
  }) : inventory = inventory ?? [];

  Map<String, dynamic> toMap() => {
        'adventure_id': adventureId,
        'hp': hp,
        'max_hp': maxHp,
        'energy': energy,
        'max_energy': maxEnergy,
        'gold': gold,
        'inventory': jsonEncode(inventory),
        'chapter': chapter,
        'current_scene': currentScene,
        'level': level,
        'experience': experience,
        'mp': mp,
        'max_mp': maxMp,
        'base_atk': baseAtk,
        'base_def': baseDef,
        'base_speed': baseSpeed,
        'skill_points': skillPoints,
      };

  factory GameState.fromMap(Map<String, dynamic> map) {
    return GameState(
      adventureId: map['adventure_id'] as int? ?? 0,
      hp: map['hp'] as int? ?? 100,
      maxHp: map['max_hp'] as int? ?? 100,
      energy: map['energy'] as int? ?? 100,
      maxEnergy: map['max_energy'] as int? ?? 100,
      gold: map['gold'] as int? ?? 0,
      inventory: map['inventory'] is String
          ? List<String>.from(jsonDecode(map['inventory'] as String))
          : (map['inventory'] as List<dynamic>?)?.cast<String>() ?? [],
      chapter: map['chapter'] as int? ?? 1,
      currentScene: map['current_scene'] as String? ?? '',
      level: map['level'] as int? ?? 1,
      experience: map['experience'] as int? ?? 0,
      mp: map['mp'] as int? ?? 100,
      maxMp: map['max_mp'] as int? ?? 100,
      baseAtk: map['base_atk'] as int? ?? 5,
      baseDef: map['base_def'] as int? ?? 3,
      baseSpeed: map['base_speed'] as int? ?? 5,
      skillPoints: map['skill_points'] as int? ?? 0,
    );
  }

  // ─── v2.1: 便捷 getter ───

  /// 能量比例 (0.0 ~ 1.0)
  double get energyRatio =>
      maxEnergy > 0 ? (energy / maxEnergy).clamp(0.0, 1.0) : 1.0;

  /// 是否能量耗尽 (≤10 惩罚阈值)
  bool get isExhausted => energy <= 10;

  /// 升级所需经验
  int get expToNextLevel => level * 100;

  /// 距离升级还需多少经验
  int get expRemaining => (expToNextLevel - experience).clamp(0, 999999);

  GameState copyWith({
    int? adventureId,
    int? hp,
    int? maxHp,
    int? energy,
    int? maxEnergy,
    int? gold,
    List<String>? inventory,
    int? chapter,
    String? currentScene,
    int? level,
    int? experience,
    int? mp,
    int? maxMp,
    int? baseAtk,
    int? baseDef,
    int? baseSpeed,
    int? skillPoints,
  }) {
    return GameState(
      adventureId: adventureId ?? this.adventureId,
      hp: hp ?? this.hp,
      maxHp: maxHp ?? this.maxHp,
      energy: energy ?? this.energy,
      maxEnergy: maxEnergy ?? this.maxEnergy,
      gold: gold ?? this.gold,
      inventory: inventory ?? this.inventory,
      chapter: chapter ?? this.chapter,
      currentScene: currentScene ?? this.currentScene,
      level: level ?? this.level,
      experience: experience ?? this.experience,
      mp: mp ?? this.mp,
      maxMp: maxMp ?? this.maxMp,
      baseAtk: baseAtk ?? this.baseAtk,
      baseDef: baseDef ?? this.baseDef,
      baseSpeed: baseSpeed ?? this.baseSpeed,
      skillPoints: skillPoints ?? this.skillPoints,
    );
  }
}
