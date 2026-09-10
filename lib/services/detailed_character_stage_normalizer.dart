import 'stage_schema_validator.dart';

/// Canonical, strictly typed payload for one detailed-character stage.
///
/// The generation pipeline is:
/// `raw JSON object → normalize aliases/shape → typed validation → payload DTO
/// → assembler`. The assembler may only read typed getters from a payload, so a
/// validator-passing value can never blow up later on an `as String?` cast.
sealed class DetailedCharacterStagePayload {
  const DetailedCharacterStagePayload();

  /// Canonical map replayed to later stages and merged into the final card.
  Map<String, dynamic> toCanonicalJson();
}

class CharacterIdentityPayload extends DetailedCharacterStagePayload {
  final String name;
  final String gender;
  final String age;
  final String profession;
  final String archetype;
  final String personality;

  const CharacterIdentityPayload({
    required this.name,
    required this.gender,
    required this.age,
    required this.profession,
    required this.archetype,
    required this.personality,
  });

  @override
  Map<String, dynamic> toCanonicalJson() => {
        'name': name,
        'gender': gender,
        'age': age,
        'profession': profession,
        'archetype': archetype,
        'personality': personality,
      };
}

class CharacterAppearancePayload extends DetailedCharacterStagePayload {
  final String appearance;
  final String bodyDescription;

  const CharacterAppearancePayload({
    required this.appearance,
    required this.bodyDescription,
  });

  @override
  Map<String, dynamic> toCanonicalJson() => {
        'appearance': appearance,
        'bodyDescription': bodyDescription,
      };
}

class CharacterBackgroundPayload extends DetailedCharacterStagePayload {
  final String description;
  final String publicGoal;
  final String hiddenMotivation;
  final String abilitySource;
  final String abilityCost;
  final String faction;
  final String homeLocation;
  final String relationshipNotes;
  final List<String> taboos;

  const CharacterBackgroundPayload({
    required this.description,
    required this.publicGoal,
    required this.hiddenMotivation,
    required this.abilitySource,
    required this.abilityCost,
    required this.faction,
    required this.homeLocation,
    required this.relationshipNotes,
    required this.taboos,
  });

  @override
  Map<String, dynamic> toCanonicalJson() => {
        'description': description,
        'public_goal': publicGoal,
        'hidden_motivation': hiddenMotivation,
        'ability_source': abilitySource,
        'ability_cost': abilityCost,
        'faction': faction,
        'home_location': homeLocation,
        'relationship_notes': relationshipNotes,
        'taboos': taboos,
      };
}

/// Raised internally when a raw stage object cannot be normalised. It never
/// escapes [DetailedCharacterStageNormalizer.normalize]; callers see `null`.
class _InvalidStagePayload implements Exception {
  const _InvalidStagePayload();
}

/// Normalises and type-checks one raw stage object.
///
/// Returns `null` when the raw object violates the canonical contract, which
/// leaves the failure inside the current stage so only that stage is retried.
class DetailedCharacterStageNormalizer {
  const DetailedCharacterStageNormalizer._();

  /// Fallback taboo used when the model emits none, kept from the previous
  /// assembler behaviour so a valid stage is never failed for a missing list.
  static const String defaultTaboo = '绝不背弃生死相托的同伴';

  static DetailedCharacterStagePayload? normalize(
    CharacterGenerationStage stage,
    Map<String, dynamic> raw,
  ) {
    try {
      final payload = switch (stage) {
        CharacterGenerationStage.identity => _identity(raw),
        CharacterGenerationStage.appearance => _appearance(raw),
        CharacterGenerationStage.backgroundWorld => _background(raw),
      };
      // Keep StageSchemaValidator as the single contract gate: a payload is
      // accepted only if the canonical shape it produces also validates.
      if (!StageSchemaValidator.validate(stage, payload.toCanonicalJson())) {
        return null;
      }
      return payload;
    } on _InvalidStagePayload {
      return null;
    }
  }

  static CharacterIdentityPayload _identity(Map<String, dynamic> raw) {
    return CharacterIdentityPayload(
      name: _requiredText(raw, const ['name']),
      gender: _requiredText(raw, const ['gender']),
      // `age` is the single documented scalar coercion: models legitimately
      // return a number (`24`) even though the schema shows a string.
      age: _requiredText(raw, const ['age'], allowNumber: true),
      profession: _requiredText(raw, const ['profession']),
      archetype: _optionalText(raw, const ['archetype']),
      personality: _requiredText(raw, const ['personality']),
    );
  }

  static CharacterAppearancePayload _appearance(Map<String, dynamic> raw) {
    return CharacterAppearancePayload(
      appearance: _requiredText(raw, const ['appearance']),
      bodyDescription: _requiredText(
        raw,
        const ['bodyDescription', 'body_description'],
      ),
    );
  }

  static CharacterBackgroundPayload _background(Map<String, dynamic> raw) {
    // Canonical Stage2B shape is flat. A nested `world_profile` container is
    // still accepted for legacy responses, but the root object always wins on a
    // key conflict and a malformed nested value never silently overrides it.
    final nested = raw['world_profile'] is Map
        ? Map<String, dynamic>.from(raw['world_profile'] as Map)
        : const <String, dynamic>{};

    String field(List<String> keys) {
      final fromRoot = _tryText(raw, keys);
      if (fromRoot != null) return fromRoot;
      final fromNested = _tryText(nested, keys);
      if (fromNested != null) return fromNested;
      throw const _InvalidStagePayload();
    }

    String optionalField(List<String> keys) {
      final fromRoot = _tryText(raw, keys);
      if (fromRoot != null) return fromRoot;
      return _tryText(nested, keys) ?? '';
    }

    final taboos = _tryTaboos(raw) ?? _tryTaboos(nested) ?? const <String>[];

    return CharacterBackgroundPayload(
      description: field(const ['description', 'background']),
      publicGoal: field(const ['public_goal']),
      hiddenMotivation: field(const ['hidden_motivation']),
      abilitySource: optionalField(const ['ability_source']),
      abilityCost: optionalField(const ['ability_cost']),
      faction: field(const ['faction']),
      homeLocation: field(const ['home_location']),
      relationshipNotes: optionalField(const ['relationship_notes']),
      taboos: taboos.isEmpty ? const [defaultTaboo] : taboos,
    );
  }

  /// Returns the first non-empty string found under [keys], or `null` when none
  /// is present. A present but non-string value is a hard failure so `true` or
  /// a nested map can never masquerade as text.
  static String? _tryText(
    Map<String, dynamic> source,
    List<String> keys, {
    bool allowNumber = false,
  }) {
    for (final key in keys) {
      if (!source.containsKey(key)) continue;
      final value = source[key];
      if (value == null) continue;
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isEmpty) throw const _InvalidStagePayload();
        return trimmed;
      }
      if (allowNumber && value is num) return value.toString();
      throw const _InvalidStagePayload();
    }
    return null;
  }

  static String _requiredText(
    Map<String, dynamic> source,
    List<String> keys, {
    bool allowNumber = false,
  }) {
    final value = _tryText(source, keys, allowNumber: allowNumber);
    if (value == null) throw const _InvalidStagePayload();
    return value;
  }

  static String _optionalText(Map<String, dynamic> source, List<String> keys) =>
      _tryText(source, keys) ?? '';

  /// Returns the taboo list when present, `null` when absent, and throws when a
  /// present value is not a list of strings.
  static List<String>? _tryTaboos(Map<String, dynamic> source) {
    if (!source.containsKey('taboos')) return null;
    final value = source['taboos'];
    if (value == null) return null;
    if (value is! List) throw const _InvalidStagePayload();
    final result = <String>[];
    for (final item in value) {
      if (item is! String) throw const _InvalidStagePayload();
      final trimmed = item.trim();
      if (trimmed.isNotEmpty) result.add(trimmed);
    }
    return result;
  }
}
