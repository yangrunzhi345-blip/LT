import 'dart:convert';

import '../../models/worldview_details.dart';

/// Selects the parts of oversized reference material that fit a generation
/// prompt without silently flooding it.
///
/// Generation is a single-shot request: the gateway has no separate reference
/// channel, so anything not selected here is simply lost. Every selector is
/// therefore bounded and ordered by relevance to the user's instruction rather
/// than by document order, which keeps the prompt useful when the source card
/// itself is already large.
final class SettingCardContextBudgeter {
  const SettingCardContextBudgeter();

  static const int maximumReferenceCharacters = 8000;
  static const int maximumWorldviewCharacters = 8000;
  static const int maximumModuleCharacters = 1600;
  static const int maximumPersonalityCharacters = 280;
  static const int maximumBackgroundCharacters = 400;

  /// Keeps [reference] verbatim while it fits, otherwise keeps the paragraphs
  /// that share the most terms with [source].
  ///
  /// Paragraphs are split on blank lines; documents without blank lines fall
  /// back to one unit per line so a dense paste is still rankable. Ties keep
  /// document order, so a document with no term overlap degrades to "first
  /// paragraphs first" instead of an unstable order.
  String selectReference({required String source, required String reference}) {
    if (reference.trim().isEmpty) return '';
    if (reference.length <= maximumReferenceCharacters) return reference;

    final terms = _terms(source);
    final units = _splitUnits(reference);
    final scores = <int, int>{
      for (var index = 0; index < units.length; index++)
        index: _matchCount(units[index], terms),
    };
    final order = List<int>.generate(units.length, (index) => index)
      ..sort((left, right) {
        final byScore = scores[right]!.compareTo(scores[left]!);
        if (byScore != 0) return byScore;
        return left.compareTo(right);
      });

    final buffer = StringBuffer();
    var remaining = maximumReferenceCharacters;
    for (final index in order) {
      if (remaining <= 0) break;
      final text = units[index].trim();
      if (text.isEmpty) continue;
      // Separators count against the budget: the returned length is used as the
      // prompt fragment length, so it must stay within the cap.
      final separator = buffer.isEmpty ? 0 : 2;
      final available = remaining - separator;
      if (available <= 0) break;
      final chunk = _truncate(text, available);
      if (chunk.isEmpty) continue;
      if (separator > 0) buffer.write('\n\n');
      buffer.write(chunk);
      remaining -= separator + chunk.length;
    }
    return buffer.toString();
  }

  /// Bounds a worldview payload: JSON details are scored module by module,
  /// plain text is cut at the cap.
  String selectWorldview({required String source, required String worldview}) {
    final raw = worldview.trim();
    if (raw.isEmpty) return '';
    final details = _decodeDetails(raw);
    if (details == null) return _truncate(raw, maximumWorldviewCharacters);

    final terms = _terms(source);
    final modules = details.modules.entries.toList();
    final insertionOrder = <String, int>{
      for (var index = 0; index < modules.length; index++)
        modules[index].key: index,
    };
    modules.sort((left, right) {
      final byScore =
          _moduleScore(right, terms).compareTo(_moduleScore(left, terms));
      if (byScore != 0) return byScore;
      return insertionOrder[left.key]!.compareTo(insertionOrder[right.key]!);
    });

    final buffer = StringBuffer();
    var remaining = maximumWorldviewCharacters;
    for (final entry in modules) {
      if (remaining <= 0) break;
      final visible = _visibleText(entry.value).trim();
      if (visible.isEmpty) continue;
      final separator = buffer.isEmpty ? 0 : 2;
      final header = '【${entry.key}】\n';
      final available = remaining - separator - header.length;
      if (available <= 0) break;
      final limit = available < maximumModuleCharacters
          ? available
          : maximumModuleCharacters;
      final section = _truncate(visible, limit);
      if (section.isEmpty) continue;
      if (separator > 0) buffer.write('\n\n');
      buffer.write(header);
      buffer.write(section);
      remaining -= separator + header.length + section.length;
    }
    return buffer.toString();
  }

  /// Copies only the fields a generation prompt needs from linked characters.
  ///
  /// The input maps are read, never mutated, because callers may reuse them for
  /// snapshot creation after generation returns.
  List<Map<String, String>> summarizeAssociatedCharacters(
    List<Map<String, String>> characters,
  ) =>
      [
        for (final character in characters) _summarizeCharacter(character),
      ];

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

  int _moduleScore(MapEntry<String, dynamic> entry, Set<String> terms) {
    final text = '${entry.key} ${_visibleText(entry.value)}'.toLowerCase();
    final matches = terms.where(text.contains).length;
    final preferred = switch (entry.key) {
      'overview' => 4,
      'world_rules' || 'locations' || 'factions' || 'customs_and_life' => 3,
      'timeline' => 2,
      _ => 1,
    };
    return matches * 10 + preferred;
  }

  int _matchCount(String text, Set<String> terms) {
    final lowered = text.toLowerCase();
    return terms.where(lowered.contains).length;
  }

  /// The status key is bookkeeping and must never leak into the prompt as
  /// prose.
  String _visibleText(Object? value) => switch (value) {
        String text => text,
        Iterable values => values.map(_visibleText).join('\n'),
        Map values => values.entries
            .where((entry) => entry.key.toString() != 'status')
            .map((entry) => _visibleText(entry.value))
            .join('\n'),
        _ => '',
      };

  /// Terms shorter than two characters are noise for relevance scoring.
  Set<String> _terms(String source) => source
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((term) => term.length >= 2)
      .toSet();

  List<String> _splitUnits(String reference) {
    final paragraphs = reference.split(RegExp(r'\n\s*\n'));
    final lines = paragraphs.length > 1 ? paragraphs : reference.split('\n');
    return lines
        .where((unit) => unit.trim().isNotEmpty)
        .toList(growable: false);
  }

  Map<String, String> _summarizeCharacter(Map<String, String> character) => {
        'name': character['name']?.trim() ?? '',
        'profession':
            character['profession']?.trim() ?? character['role']?.trim() ?? '',
        'personality': _truncate(
          character['personality']?.trim() ?? '',
          maximumPersonalityCharacters,
        ),
        'background': _truncate(
          character['background']?.trim() ?? '',
          maximumBackgroundCharacters,
        ),
        'relation': character['relation']?.trim() ??
            character['relationship']?.trim() ??
            '',
      };

  /// Cutting at an arbitrary index can split a surrogate pair, leaving invalid
  /// UTF-16 at the end of the prompt fragment; back off one unit when the last
  /// kept unit is a high surrogate.
  String _truncate(String value, int limit) {
    if (limit <= 0) return '';
    if (value.length <= limit) return value;
    var end = limit;
    final lastUnit = value.codeUnitAt(end - 1);
    if (lastUnit >= 0xD800 && lastUnit <= 0xDBFF) {
      end -= 1;
    }
    return value.substring(0, end);
  }
}
