/// Utility class for validating the JSON schema returned by each generation stage.
/// Returns `true` if the supplied [data] contains the required fields for the
/// given [stageName]. The required fields are derived from the expectations of
/// the corresponding guard (`CharacterCardGenerationGuard`).


enum CharacterGenerationStage { identity, appearance, backgroundWorld, roleplay, other }

class StageSchemaValidator {
  static const _stageRequirements = <CharacterGenerationStage, List<String>>{
    // Stage 1 – 基础角色信息 (name, gender, age, profession, personality)
    CharacterGenerationStage.identity: ['name', 'gender', 'age', 'profession', 'personality'],
    // Stage 2 – 外貌 & 身体描述
    CharacterGenerationStage.appearance: ['appearance', 'bodyDescription'],
    // Stage 3 – 背景 & 世界定位 (description, world_profile)
    CharacterGenerationStage.backgroundWorld: ['description', 'world_profile'],
    // Stage 4 – 角色扮演行为 (scenario, first_mes, mes_example)
    CharacterGenerationStage.roleplay: ['scenario', 'first_mes', 'mes_example'],
    // Stage 5 – 其他约束/细节 (no hard checks)
    CharacterGenerationStage.other: [],
  };

  /// Validates the parsed JSON [data] for the given Chinese [stageName].
  /// Returns false for unknown stage names.
  static bool validate(String stageName, Map<String, dynamic> data) {
    final stage = _stageNameToEnum(stageName);
    // For detailed worldview stages (not in CharacterGenerationStage), allow any JSON.
    if (stage == null) return true;
    final requirements = _stageRequirements[stage]!;
    for (final field in requirements) {
      if (!data.containsKey(field) || data[field] == null) {
        return false;
      }
    }
    return true;
  }

  /// Maps Chinese UI stage names to the enum values.
  static CharacterGenerationStage? _stageNameToEnum(String name) {
    switch (name) {
      case '身份与性格':
        return CharacterGenerationStage.identity;
      case '外貌':
        return CharacterGenerationStage.appearance;
      case '背景':
        return CharacterGenerationStage.backgroundWorld;
      case '角色扮演':
        return CharacterGenerationStage.roleplay;
      case '其他':
        return CharacterGenerationStage.other;
      default:
        return null;
    }
  }
}
