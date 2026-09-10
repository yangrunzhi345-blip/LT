/// Stable schema identity for one detailed-character generation stage.
///
/// These values are part of the generation contract and must never be derived
/// from user-facing display text: a renamed or localised stage label used to
/// silently disable validation.
enum CharacterGenerationStage { identity, appearance, backgroundWorld }

/// Validates a **canonical, already normalised** stage payload.
///
/// This is the single contract shared with the assembler: every field checked
/// here is read by the assembler as a non-empty `String` (see
/// [DetailedCharacterStageNormalizer]). The previous loose "has any value"
/// check let `{"name": 123}` pass and then crash the consumer on `as String?`;
/// validation now rejects any non-string scalar outright. Raw provider output
/// must be normalised (aliases, nested `world_profile`, allowed `age` number)
/// before it reaches this validator.
///
/// A stage either satisfies the schema or it fails; there is no "unknown
/// stage" escape hatch that returns `true`.
class StageSchemaValidator {
  const StageSchemaValidator._();

  /// [CharacterCardGenerationGuard] requires these four identity anchors
  /// (`structurallyConsistent`) plus a `personality` of at least 160 chars.
  static const _identityFields = <String>[
    'name',
    'gender',
    'age',
    'profession',
    'personality',
  ];

  /// Guard `appearanceAndPhysicality` reads `appearance` / `bodyDescription`
  /// and needs at least 100 chars.
  static const _appearanceFields = <String>['appearance', 'bodyDescription'];

  /// Guard `personalityAndHistory` needs `description`, and Guard
  /// `worldPosition` needs the world-location fields below.
  ///
  /// The background stage contract is a **flat** object; a nested
  /// `world_profile` container is folded into this flat shape by
  /// [DetailedCharacterStageNormalizer] before validation.
  static const _backgroundFields = <String>[
    'description',
    'faction',
    'home_location',
    'public_goal',
    'hidden_motivation',
  ];

  /// Returns whether [data] satisfies the schema of [stage].
  ///
  /// [stage] is nullable so an unmapped stage is an explicit validation
  /// failure rather than an automatic pass.
  static bool validate(
      CharacterGenerationStage? stage, Map<String, dynamic> data) {
    if (stage == null) return false;
    return switch (stage) {
      CharacterGenerationStage.identity => _hasAllText(data, _identityFields),
      CharacterGenerationStage.appearance =>
        _hasAllText(data, _appearanceFields),
      CharacterGenerationStage.backgroundWorld =>
        _hasAllText(data, _backgroundFields),
    };
  }

  static bool _hasAllText(Map<String, dynamic> data, List<String> fields) {
    for (final field in fields) {
      final value = data[field];
      if (value is! String || value.trim().isEmpty) return false;
    }
    return true;
  }
}
