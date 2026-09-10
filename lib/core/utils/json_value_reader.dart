/// Tolerant readers for values coming from trust boundaries.
///
/// Persisted legacy data (SQLite rows, SharedPreferences, historical JSON
/// blobs) and external imports routinely store a semantically valid value
/// under a different JSON type, e.g. `"8192"` or `8192.0` for an int field, or
/// `"true"` / `1` for a bool. A strict `as int?` / `as bool?` cast turns one
/// recoverable variant into a `TypeError` that resets settings or drops a row.
///
/// These helpers centralize that conversion. They are only for trust
/// boundaries; in-memory DTOs produced by current code in the same
/// transaction/schema may keep strict casts.
class JsonValueReader {
  const JsonValueReader._();

  /// Reads a scalar as text, tolerating numbers and booleans.
  static String? stringScalar(Object? value) {
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    return null;
  }

  /// Parses an int, tolerating integral doubles and numeric strings.
  ///
  /// Returns null for non-integral values so callers can fall back to a
  /// default instead of silently truncating meaningful data.
  static int? intScalar(Object? value) {
    if (value is int) return value;
    if (value is num) {
      if (value.isFinite && value == value.truncateToDouble()) {
        return value.toInt();
      }
      return null;
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      final asInt = int.tryParse(trimmed);
      if (asInt != null) return asInt;
      final asDouble = double.tryParse(trimmed);
      if (asDouble != null &&
          asDouble.isFinite &&
          asDouble == asDouble.truncateToDouble()) {
        return asDouble.toInt();
      }
    }
    return null;
  }

  /// Parses a double, tolerating numeric strings.
  static double? doubleScalar(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      return double.tryParse(trimmed);
    }
    return null;
  }

  /// Parses a bool from bool, numeric (`0`/`1`/other) or string variants.
  static bool? boolScalar(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      switch (value.trim().toLowerCase()) {
        case 'true':
        case '1':
        case 'yes':
        case 'on':
          return true;
        case 'false':
        case '0':
        case 'no':
        case 'off':
          return false;
      }
    }
    return null;
  }

  /// Reads a JSON object, tolerating `_Map<dynamic, dynamic>` decoded shapes.
  static Map<String, dynamic>? object(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;
}
