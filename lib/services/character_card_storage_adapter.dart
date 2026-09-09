import 'dart:convert';

/// Preserves the original character-card envelope while exposing one logical
/// payload for both top-level cards and SillyTavern `data` wrapped cards.
class CharacterCardStorageAdapter {
  final Map<String, dynamic> original;
  final Map<String, dynamic> data;
  final bool isDataWrapped;

  CharacterCardStorageAdapter._({
    required this.original,
    required this.data,
    required this.isDataWrapped,
  });

  factory CharacterCardStorageAdapter.fromStored(Object? value) {
    Map<String, dynamic> root = {};
    try {
      final decoded = value is String ? jsonDecode(value) : value;
      if (decoded is Map) root = Map<String, dynamic>.from(decoded);
    } catch (_) {}
    final wrapped = root['data'] is Map;
    return CharacterCardStorageAdapter._(
      original: root,
      data: wrapped
          ? Map<String, dynamic>.from(root['data'] as Map)
          : Map<String, dynamic>.from(root),
      isDataWrapped: wrapped,
    );
  }

  /// Converts an AI payload into the single storage-compatible card schema.
  ///
  /// Generation endpoints have historically used both `background` and
  /// `description`, plus camel/snake aliases for body and custom fields. This
  /// boundary keeps those aliases out of application and UI code while
  /// retaining every user-visible field supported by [CharacterCard].
  static Map<String, dynamic> canonicalizeGenerated(Map<String, dynamic> raw) {
    final source = raw['data'] is Map
        ? Map<String, dynamic>.from(raw['data'] as Map)
        : raw;
    final profile = _object(source['world_profile']);
    return <String, dynamic>{
      'name': _text(source, const ['name']),
      'gender': _text(source, const ['gender']),
      'age': _text(source, const ['age']),
      'profession': _text(source, const ['profession', 'occupation', 'role']),
      'personality': _text(source, const ['personality']),
      'description': _text(source, const ['description', 'background']),
      'appearance': _text(source, const ['appearance']),
      'bodyDescription':
          _text(source, const ['bodyDescription', 'body_description']),
      'scenario': _text(source, const ['scenario']),
      'first_mes': _text(source, const ['first_mes', 'firstMessage']),
      'mes_example': _text(source, const ['mes_example', 'exampleDialogues']),
      'ability': _text(source, const ['ability']),
      'weakness': _text(source, const ['weakness']),
      'equipment': _text(source, const ['equipment']),
      'custom_attributes': _list(
        source['custom_attributes'] ?? source['customAttributes'],
      ),
      'world_profile': <String, dynamic>{
        'faction': _text(profile, const ['faction']),
        'home_location':
            _text(profile, const ['home_location', 'homeLocation']),
        'public_goal': _text(profile, const ['public_goal', 'publicGoal']),
        'hidden_motivation': _text(
          profile,
          const ['hidden_motivation', 'hiddenMotivation'],
        ),
        'secrets': profile['secrets'] ?? const <dynamic>[],
        'ability_source':
            _text(profile, const ['ability_source', 'abilitySource']),
        'ability_cost': _text(profile, const ['ability_cost', 'abilityCost']),
        'taboos': profile['taboos'] ?? const <dynamic>[],
        'relationship_notes': _text(
          profile,
          const ['relationship_notes', 'relationshipNotes'],
        ),
      },
    };
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is! String || value.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(value);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static String _text(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static List<dynamic> _list(Object? value) {
    if (value is List) return List<dynamic>.from(value);
    if (value is! String || value.trim().isEmpty) return const <dynamic>[];
    try {
      final decoded = jsonDecode(value);
      return decoded is List ? List<dynamic>.from(decoded) : const <dynamic>[];
    } catch (_) {
      return const <dynamic>[];
    }
  }

  Map<String, dynamic> overlay({
    required Map<String, dynamic> fields,
    Map<String, dynamic>? worldProfile,
  }) {
    final nextData = Map<String, dynamic>.from(data)..addAll(fields);
    if (worldProfile != null) {
      final originalProfile = nextData['world_profile'] is Map
          ? Map<String, dynamic>.from(nextData['world_profile'] as Map)
          : <String, dynamic>{};
      nextData['world_profile'] = originalProfile..addAll(worldProfile);
    }
    if (!isDataWrapped) return nextData;
    return Map<String, dynamic>.from(original)..['data'] = nextData;
  }
}
