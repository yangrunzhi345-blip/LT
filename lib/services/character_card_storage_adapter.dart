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
