import 'dart:convert';
import 'package:equatable/equatable.dart';

/// 技能数据模型
class Skill with Equatable {
  final String id;
  final String name;
  final String description;
  final SkillType type;
  final String category;
  final int maxLevel;
  final int baseMpCost;
  final int mpCostPerLevel;
  final Map<String, int> baseEffects;
  final Map<String, int> effectsPerLevel;
  final String? prerequisiteSkillId;
  final int prerequisiteLevel;
  final Map<String, int>? statRequirements;
  final String icon;
  final String worldviewCategory;

  const Skill({
    required this.id,
    required this.name,
    this.description = '',
    this.type = SkillType.active,
    this.category = 'combat',
    this.maxLevel = 5,
    this.baseMpCost = 0,
    this.mpCostPerLevel = 0,
    this.baseEffects = const {},
    this.effectsPerLevel = const {},
    this.prerequisiteSkillId,
    this.prerequisiteLevel = 0,
    this.statRequirements,
    this.icon = '',
    this.worldviewCategory = '',
  });

  /// 获取指定等级的伤害/效果值
  int getEffect(String key, int level) {
    final base = baseEffects[key] ?? 0;
    final perLevel = effectsPerLevel[key] ?? 0;
    return base + (perLevel * (level - 1));
  }

  /// 获取指定等级的 MP 消耗
  int getMpCost(int level) => baseMpCost + (mpCostPerLevel * (level - 1));

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'type': type.name,
        'category': category,
        'max_level': maxLevel,
        'base_mp_cost': baseMpCost,
        'mp_cost_per_level': mpCostPerLevel,
        'effects_json': _encodeEffects(baseEffects),
        'effects_per_level_json': _encodeEffects(effectsPerLevel),
        'prerequisite_skill_id': prerequisiteSkillId,
        'prerequisite_level': prerequisiteLevel,
        'stat_requirements_json':
            statRequirements != null ? _encodeEffects(statRequirements!) : '{}',
        'icon': icon,
        'worldview_category': worldviewCategory,
      };

  factory Skill.fromRow(Map<String, dynamic> row) {
    return Skill(
      id: row['id'] as String,
      name: row['name'] as String? ?? '',
      description: row['description'] as String? ?? '',
      type: SkillType.values.firstWhere((e) => e.name == row['skill_type'],
          orElse: () => SkillType.active),
      category: row['category'] as String? ?? 'combat',
      maxLevel: row['max_level'] as int? ?? 5,
      baseMpCost: row['base_mp_cost'] as int? ?? 0,
      mpCostPerLevel: row['mp_cost_per_level'] as int? ?? 0,
      baseEffects: _decodeEffects(row['effects_json'] as String?),
      effectsPerLevel: _decodeEffects(row['effects_per_level_json'] as String?),
      prerequisiteSkillId: row['prerequisite_skill_id'] as String?,
      prerequisiteLevel: row['prerequisite_level'] as int? ?? 0,
      statRequirements: row['stat_requirements_json'] != null
          ? _decodeEffects(row['stat_requirements_json'] as String?)
          : null,
      icon: row['icon'] as String? ?? '',
      worldviewCategory: row['worldview_category'] as String? ?? '',
    );
  }

  static String _encodeEffects(Map<String, int> effects) {
    return '{${effects.entries.map((e) => '"${e.key}":${e.value}').join(',')}}';
  }

  static Map<String, int> _decodeEffects(String? json) {
    if (json == null || json.isEmpty || json == '{}') return {};
    try {
      final map = Map<String, dynamic>.from(jsonDecode(json) as Map);
      return map.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  @override
  List<Object?> get props => [id];
}

enum SkillType { active, passive, ultimate }

/// 角色技能关联
class CharacterSkill with Equatable {
  final int? id;
  final String characterId;
  final String characterType;
  final String skillId;
  final int currentLevel;
  final int experience;

  const CharacterSkill({
    this.id,
    required this.characterId,
    this.characterType = 'player',
    required this.skillId,
    this.currentLevel = 1,
    this.experience = 0,
  });

  @override
  List<Object?> get props => [id];

  Map<String, dynamic> toRow() => {
        if (id != null) 'id': id,
        'character_id': characterId,
        'character_type': characterType,
        'skill_id': skillId,
        'current_level': currentLevel,
        'experience': experience,
      };
}
