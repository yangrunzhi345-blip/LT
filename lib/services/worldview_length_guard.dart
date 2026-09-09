import '../models/worldview_details.dart';

/// Counts user-visible detailed-worldview text without serialisation metadata.
///
/// This is deliberately independent from [NarrativeLengthGuard]: narrative
/// output is measured in Chinese characters, whereas a worldview is measured
/// across all visible structured content after whitespace is removed.
final class WorldviewLengthGuard {
  const WorldviewLengthGuard();

  static const _metadataKeys = <String>{
    'status',
    'format_version',
    'mode',
    'generation',
    'question_index',
    'total_questions',
    'part',
    'total_parts',
    'source_hash',
    'target_total_characters',
  };

  /// Returns effective characters in [detailJson].
  ///
  /// Detailed payloads count their modules only. The top-level description is
  /// used solely when `overview` has no visible content, preventing the common
  /// description/overview double count.
  int count({
    required Map<String, dynamic>? detailJson,
    String fallbackDescription = '',
  }) {
    final modules = detailJson?['modules'];
    if (modules is! Map) return _countText(fallbackDescription);

    final seen = <String>{};
    var total = 0;
    var hasOverview = false;
    for (final key in WorldviewDetails.moduleKeys) {
      final value = modules[key];
      if (value == null) continue;
      final moduleTexts = _visibleTexts(value);
      if (key == 'overview' && moduleTexts.isNotEmpty) hasOverview = true;
      for (final text in moduleTexts) {
        final normalized = _normalize(text);
        if (normalized.isEmpty || !seen.add(normalized)) continue;
        total += normalized.length;
      }
    }
    if (!hasOverview) total += _countText(fallbackDescription);
    return total;
  }

  List<String> _visibleTexts(Object? value) {
    if (value is String) return [value];
    if (value is List) {
      return [for (final item in value) ..._visibleTexts(item)];
    }
    if (value is Map) {
      return [
        for (final entry in value.entries)
          if (!_metadataKeys.contains(entry.key.toString()))
            ..._visibleTexts(entry.value),
      ];
    }
    return const [];
  }

  int _countText(String value) => _normalize(value).length;

  String _normalize(String value) => value.replaceAll(RegExp(r'\s+'), '');
}
