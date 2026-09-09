import 'dart:convert';

import '../../models/worldview_details.dart';

class RelevantCharacterGenerationContext {
  final String worldview;
  final List<Map<String, String>> associatedCharacters;

  const RelevantCharacterGenerationContext({
    required this.worldview,
    required this.associatedCharacters,
  });
}

/// Produces bounded, role-relevant context instead of copying an entire
/// detailed worldview or every linked character card into a generation prompt.
final class CharacterGenerationContextBuilder {
  static const _maximumWorldviewCharacters = 8000;
  static const _maximumModuleCharacters = 1600;

  const CharacterGenerationContextBuilder();

  RelevantCharacterGenerationContext build({
    required String source,
    String worldview = '',
    List<Map<String, String>> associatedCharacters = const [],
  }) {
    return RelevantCharacterGenerationContext(
      worldview: _selectWorldview(source, worldview),
      associatedCharacters: [
        for (final character in associatedCharacters)
          _summarizeCharacter(character),
      ],
    );
  }

  String _selectWorldview(String source, String rawWorldview) {
    final raw = rawWorldview.trim();
    if (raw.isEmpty) return '';
    final details = _decodeDetails(raw);
    if (details == null) return _truncate(raw, _maximumWorldviewCharacters);

    final sourceTerms = _terms(source);
    final modules = details.modules.entries.toList()
      ..sort((left, right) => _moduleScore(right, sourceTerms)
          .compareTo(_moduleScore(left, sourceTerms)));
    final parts = <String>[];
    var remaining = _maximumWorldviewCharacters;
    for (final entry in modules) {
      if (remaining <= 0) break;
      final visible = _visibleText(entry.value).trim();
      if (visible.isEmpty) continue;
      final section = _truncate(
        visible,
        _maximumModuleCharacters.clamp(0, remaining).toInt(),
      );
      parts.add('【${entry.key}】\n$section');
      remaining -= section.length;
    }
    return parts.join('\n\n');
  }

  WorldviewDetails? _decodeDetails(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return WorldviewDetails.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      // Plain-text worldviews are valid input and use the bounded fallback.
    }
    return null;
  }

  int _moduleScore(MapEntry<String, dynamic> entry, Set<String> sourceTerms) {
    final text = '${entry.key} ${_visibleText(entry.value)}'.toLowerCase();
    final matches = sourceTerms.where(text.contains).length;
    final preferred = switch (entry.key) {
      'overview' => 4,
      'world_rules' || 'locations' || 'factions' || 'customs_and_life' => 3,
      'timeline' => 2,
      _ => 1,
    };
    return matches * 10 + preferred;
  }

  Set<String> _terms(String source) => source
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((term) => term.length >= 2)
      .toSet();

  String _visibleText(Object? value) => switch (value) {
        String text => text,
        Iterable values => values.map(_visibleText).join('\n'),
        Map values => values.entries
            .where((entry) => entry.key.toString() != 'status')
            .map((entry) => _visibleText(entry.value))
            .join('\n'),
        _ => '',
      };

  Map<String, String> _summarizeCharacter(Map<String, String> character) => {
        'name': character['name']?.trim() ?? '',
        'profession':
            character['profession']?.trim() ?? character['role']?.trim() ?? '',
        'personality': _truncate(character['personality']?.trim() ?? '', 280),
        'background': _truncate(character['background']?.trim() ?? '', 400),
        'relation': character['relation']?.trim() ??
            character['relationship']?.trim() ??
            '',
      };

  String _truncate(String value, int limit) =>
      value.length <= limit ? value : value.substring(0, limit);
}
