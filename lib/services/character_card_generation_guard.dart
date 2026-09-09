/// Evaluates whether a detailed AI-generated character card is ready to use.
///
/// This intentionally has different semantics from [WorldviewLengthGuard] and
/// [NarrativeLengthGuard]: a long character background is not sufficient when
/// the card has no roleplay behaviour or world position.
enum CharacterModuleReadiness { empty, thin, ready, notApplicable }

enum CharacterCardGenerationModule {
  identity,
  personalityAndHistory,
  appearanceAndPhysicality,
  abilityAndLimits,
  worldPosition,
  roleplayBehavior,
}

class CharacterCardGenerationReport {
  final int currentCharacters;
  final int targetCharacters;
  final bool lengthReached;
  final bool requiredModulesReady;
  final bool structurallyConsistent;
  final Map<CharacterCardGenerationModule, CharacterModuleReadiness>
      moduleReadiness;
  final List<String> missingRequiredFields;

  const CharacterCardGenerationReport({
    required this.currentCharacters,
    required this.targetCharacters,
    required this.lengthReached,
    required this.requiredModulesReady,
    required this.structurallyConsistent,
    required this.moduleReadiness,
    required this.missingRequiredFields,
  });

  List<String> get weakModules => [
        for (final entry in moduleReadiness.entries)
          if (entry.value == CharacterModuleReadiness.empty ||
              entry.value == CharacterModuleReadiness.thin)
            entry.key.name,
      ];

  bool get completed =>
      lengthReached && requiredModulesReady && structurallyConsistent;
}

/// Counts visible character-card prose and checks detailed generation modules.
final class CharacterCardGenerationGuard {
  const CharacterCardGenerationGuard();

  static const _requiredModules = {
    CharacterCardGenerationModule.identity,
    CharacterCardGenerationModule.personalityAndHistory,
    CharacterCardGenerationModule.appearanceAndPhysicality,
    CharacterCardGenerationModule.worldPosition,
    CharacterCardGenerationModule.roleplayBehavior,
  };

  /// Counts user-visible content after whitespace and exact duplicate removal.
  int count(Map<String, dynamic> card) {
    final payload = _payload(card);
    final profile = _map(payload['world_profile']);
    final values = <Object?>[
      payload['description'] ?? payload['background'],
      payload['personality'],
      payload['scenario'],
      payload['first_mes'] ?? payload['firstMessage'],
      payload['mes_example'] ?? payload['exampleDialogues'],
      payload['appearance'],
      payload['bodyDescription'] ?? payload['body_description'],
      payload['ability'],
      payload['weakness'],
      payload['equipment'],
      profile['faction'],
      profile['home_location'],
      profile['public_goal'],
      profile['hidden_motivation'],
      profile['secrets'],
      profile['ability_source'],
      profile['ability_cost'],
      profile['taboos'],
      profile['relationship_notes'],
      _customAttributeValues(
        payload['custom_attributes'] ?? payload['customAttributes'],
      ),
    ];
    final seen = <String>{};
    var total = 0;
    for (final value in values) {
      for (final text in _texts(value)) {
        final normalized = _normalize(text);
        if (normalized.isNotEmpty && seen.add(normalized)) {
          total += normalized.length;
        }
      }
    }
    return total;
  }

  CharacterCardGenerationReport evaluate({
    required Map<String, dynamic> card,
    required int targetCharacters,
  }) {
    final payload = _payload(card);
    final profile = _map(payload['world_profile']);
    final readiness = <CharacterCardGenerationModule, CharacterModuleReadiness>{
      CharacterCardGenerationModule.identity: _identityReadiness(payload),
      CharacterCardGenerationModule.personalityAndHistory: _textReadiness(
        [
          payload['personality'],
          payload['description'] ?? payload['background']
        ],
        minimumCharacters: 160,
        minimumPopulatedFields: 2,
      ),
      CharacterCardGenerationModule.appearanceAndPhysicality: _textReadiness(
        [
          payload['appearance'],
          payload['bodyDescription'] ?? payload['body_description']
        ],
        minimumCharacters: 100,
      ),
      CharacterCardGenerationModule.abilityAndLimits:
          _abilityReadiness(payload, profile),
      CharacterCardGenerationModule.worldPosition: _textReadiness(
        [
          profile['faction'],
          profile['home_location'],
          profile['public_goal'],
          profile['hidden_motivation'],
          profile['secrets'],
          profile['relationship_notes'],
        ],
        minimumCharacters: 140,
        minimumPopulatedFields: 2,
      ),
      CharacterCardGenerationModule.roleplayBehavior: _textReadiness(
        [
          payload['scenario'],
          payload['first_mes'] ?? payload['firstMessage'],
          payload['mes_example'] ?? payload['exampleDialogues'],
        ],
        minimumCharacters: 180,
        minimumPopulatedFields: 2,
      ),
    };
    final missing = <String>[
      if (_string(payload['name']).isEmpty) 'name',
      if (_string(payload['gender']).isEmpty) 'gender',
      if (_string(payload['age']).isEmpty) 'age',
      if (_string(payload['profession']).isEmpty) 'profession',
    ];
    final requiredReady = _requiredModules.every(
      (module) => readiness[module] == CharacterModuleReadiness.ready,
    );
    final current = count(card);
    return CharacterCardGenerationReport(
      currentCharacters: current,
      targetCharacters: targetCharacters,
      lengthReached: current >= targetCharacters,
      requiredModulesReady: requiredReady,
      structurallyConsistent: missing.isEmpty,
      moduleReadiness: Map.unmodifiable(readiness),
      missingRequiredFields: List.unmodifiable(missing),
    );
  }

  CharacterModuleReadiness _identityReadiness(Map<String, dynamic> card) {
    final populated = [
      card['name'],
      card['gender'],
      card['age'],
      card['profession'],
    ].where((value) => _string(value).isNotEmpty).length;
    return switch (populated) {
      0 => CharacterModuleReadiness.empty,
      < 4 => CharacterModuleReadiness.thin,
      _ => CharacterModuleReadiness.ready,
    };
  }

  CharacterModuleReadiness _abilityReadiness(
    Map<String, dynamic> payload,
    Map<String, dynamic> profile,
  ) {
    final ability = _string(payload['ability']);
    final source = _string(profile['ability_source']);
    if (_isNotApplicable(ability) || _isNotApplicable(source)) {
      return CharacterModuleReadiness.notApplicable;
    }
    return _textReadiness(
      [
        payload['ability'],
        payload['weakness'],
        payload['equipment'],
        profile['ability_source'],
        profile['ability_cost'],
        profile['taboos'],
      ],
      minimumCharacters: 100,
      minimumPopulatedFields: 2,
    );
  }

  CharacterModuleReadiness _textReadiness(
    List<Object?> values, {
    required int minimumCharacters,
    int minimumPopulatedFields = 1,
  }) {
    final texts = [for (final value in values) ..._texts(value)];
    final populated = texts.where((text) => _normalize(text).isNotEmpty).length;
    final length =
        texts.fold<int>(0, (sum, text) => sum + _normalize(text).length);
    if (populated == 0) return CharacterModuleReadiness.empty;
    if (populated < minimumPopulatedFields || length < minimumCharacters) {
      return CharacterModuleReadiness.thin;
    }
    return CharacterModuleReadiness.ready;
  }

  Map<String, dynamic> _payload(Map<String, dynamic> card) =>
      card['data'] is Map
          ? Map<String, dynamic>.from(card['data'] as Map)
          : card;

  Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  List<Object?> _customAttributeValues(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is Map) item['value'] ?? item['description'],
    ];
  }

  List<String> _texts(Object? value) => switch (value) {
        String text => [text],
        Iterable values => [for (final item in values) ..._texts(item)],
        _ => const [],
      };

  String _string(Object? value) => value?.toString().trim() ?? '';

  bool _isNotApplicable(String value) {
    final normalized = value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    return normalized == 'not_applicable' ||
        normalized == 'n/a' ||
        normalized == '无';
  }

  String _normalize(String value) => value.replaceAll(RegExp(r'\s+'), '');
}
