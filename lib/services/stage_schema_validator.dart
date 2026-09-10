/// Stable schema identity for one detailed-character generation stage.
///
/// These values are part of the generation contract and must never be derived
/// from user-facing display text: a renamed or localised stage label used to
/// silently disable validation.
enum CharacterGenerationStage { identity, appearance, backgroundWorld }

/// Validates the parsed JSON produced by a single generation stage.
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
  /// The background stage prompt asks for a *single-level* JSON object, so
  /// these keys arrive flat and are folded into `world_profile` by the
  /// assembler right after validation. Requiring a literal `world_profile`
  /// key here would fail 100% of real responses, so the flat shape is the
  /// contract and `world_profile` is accepted as an equivalent container.
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
  static bool validate(CharacterGenerationStage? stage, Map<String, dynamic> data) {
    if (stage == null) return false;
    return switch (stage) {
      CharacterGenerationStage.identity => _hasAll(data, _identityFields),
      CharacterGenerationStage.appearance => _hasAll(data, _appearanceFields),
      CharacterGenerationStage.backgroundWorld =>
        _hasAll(data, _backgroundFields) || _hasWorldProfile(data),
    };
  }

  static bool _hasWorldProfile(Map<String, dynamic> data) {
    final profile = data['world_profile'];
    if (profile is! Map) return false;
    return _hasAll(Map<String, dynamic>.from(profile), _backgroundFields
        .where((field) => field != 'description')
        .toList(growable: false));
  }

  static bool _hasAll(Map<String, dynamic> data, List<String> fields) {
    for (final field in fields) {
      if (!_hasValue(data[field])) return false;
    }
    return true;
  }

  static bool _hasValue(Object? value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is Iterable) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }
}
