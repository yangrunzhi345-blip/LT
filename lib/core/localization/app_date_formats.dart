import 'package:intl/intl.dart';

/// Locale-aware, compact timestamp formatting for metadata surfaces.
///
/// List rows, trash entries and revision metadata must never show a raw
/// persisted value such as `2026-09-21T18:27:27.765301`. This helper renders a
/// short, locale-aware form (`9月21日 18:27` / `Sep 21, 18:27`) and includes the
/// year only when it differs from the current year.
///
/// It uses the existing `intl` dependency and the active locale; no additional
/// date package is introduced.
class AppDateFormats {
  AppDateFormats._();

  /// Pattern without the year, for entries inside the current year.
  static const _currentYearPattern = 'MMM d, HH:mm';

  /// Pattern with the year, for older entries.
  static const _pastYearPattern = 'MMM d, yyyy HH:mm';

  /// Formats [value] for display next to other metadata.
  ///
  /// [localeName] comes from `AppLocalizations.localeName`. [now] is injectable
  /// so the year-cutoff rule is deterministic in tests.
  static String compactTimestamp(
    DateTime value,
    String localeName, {
    DateTime? now,
  }) {
    final local = value.toLocal();
    final reference = now ?? DateTime.now();
    final pattern =
        local.year == reference.year ? _currentYearPattern : _pastYearPattern;
    final locale = localeName.trim().isEmpty ? 'en' : localeName.trim();
    try {
      return DateFormat(pattern, locale).format(local);
    } on Exception {
      // Unknown locale data must never break the row; fall back to en.
      return DateFormat(pattern).format(local);
    }
  }

  /// Parses a persisted timestamp (ISO-8601). Returns null when unusable, so
  /// callers can omit the metadata instead of printing the raw string.
  static DateTime? tryParse(String? raw) {
    final cleaned = raw?.trim() ?? '';
    if (cleaned.isEmpty) return null;
    return DateTime.tryParse(cleaned);
  }

  /// Convenience: parse a persisted value then format it, or return null.
  static String? formatPersisted(
    String? raw,
    String localeName, {
    DateTime? now,
  }) {
    final parsed = tryParse(raw);
    if (parsed == null) return null;
    return compactTimestamp(parsed, localeName, now: now);
  }
}
