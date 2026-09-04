import 'dart:convert';

enum StructuredJsonFailure {
  missing,
  incomplete,
  malformed,
  wrongType,
}

class StructuredJsonException implements FormatException {
  final StructuredJsonFailure failure;
  @override
  final String message;
  @override
  final Object? source;
  @override
  final int? offset;

  const StructuredJsonException(
    this.failure,
    this.message, {
    this.source,
    this.offset,
  });

  @override
  String toString() => 'FormatException: $message';
}

/// One implementation for extracting model-produced structured JSON.
///
/// Strict parsing never repairs input. Tolerant parsing may unwrap prose or a
/// Markdown fence and repair literal control characters and trailing commas.
class StructuredJsonCodec {
  static final _fence = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```');

  const StructuredJsonCodec._();

  static Map<String, dynamic> decodeObjectStrict(String source) {
    final value = jsonDecode(source);
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw StructuredJsonException(
      StructuredJsonFailure.wrongType,
      'Expected a JSON object.',
      source: source,
    );
  }

  static Map<String, dynamic>? tryDecodeObject(
    String source, {
    bool repair = false,
  }) {
    for (final candidate in _candidates(source)) {
      try {
        return decodeObjectStrict(candidate);
      } catch (_) {
        if (!repair) continue;
        final normalized = _escapeControlCharacters(candidate)
            .replaceAllMapped(RegExp(r',\s*([}\]])'), (m) => m.group(1)!);
        try {
          return decodeObjectStrict(normalized);
        } catch (_) {}
      }
    }
    return null;
  }

  /// Parses persisted JSON without extracting prose or applying repairs.
  static Map<String, dynamic>? tryDecodeStoredObject(Object? source) {
    if (source is Map<String, dynamic>) return source;
    if (source is Map) return Map<String, dynamic>.from(source);
    if (source is! String || source.trim().isEmpty) return null;
    try {
      return decodeObjectStrict(source);
    } catch (_) {
      return null;
    }
  }

  static String extractCompleteValue(String source) {
    final fenced = _fence.firstMatch(source)?.group(1);
    final candidate = fenced ?? source;
    final extracted = _firstBalancedValue(candidate);
    if (extracted != null) return extracted;
    if (!RegExp(r'[\[{]').hasMatch(candidate)) {
      throw StructuredJsonException(
        StructuredJsonFailure.missing,
        'No JSON object or array found.',
        source: source,
      );
    }
    throw StructuredJsonException(
      StructuredJsonFailure.incomplete,
      'JSON object or array is incomplete.',
      source: source,
    );
  }

  static Iterable<String> _candidates(String source) sync* {
    final fenced = _fence.firstMatch(source)?.group(1);
    if (fenced != null) yield fenced;
    final balanced = _firstBalancedValue(source);
    if (balanced != null && balanced != fenced) yield balanced;
    if (fenced == null && balanced == null) yield source.trim();
  }

  static String? _firstBalancedValue(String source) {
    final object = source.indexOf('{');
    final array = source.indexOf('[');
    final start = object < 0
        ? array
        : array < 0
            ? object
            : object < array
                ? object
                : array;
    if (start < 0) return null;
    final stack = <String>[];
    var inString = false;
    var escaped = false;
    for (var index = start; index < source.length; index++) {
      final char = source[index];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }
      if (char == '"') {
        inString = true;
      } else if (char == '{' || char == '[') {
        stack.add(char);
      } else if (char == '}' || char == ']') {
        if (stack.isEmpty) return null;
        final expected = char == '}' ? '{' : '[';
        if (stack.removeLast() != expected) return null;
        if (stack.isEmpty) return source.substring(start, index + 1);
      }
    }
    return null;
  }

  static String _escapeControlCharacters(String source) {
    final result = StringBuffer();
    var inString = false;
    var escaped = false;
    for (final rune in source.runes) {
      final char = String.fromCharCode(rune);
      if (inString && rune < 0x20) {
        result.write(switch (rune) {
          0x08 => r'\b',
          0x09 => r'\t',
          0x0A => r'\n',
          0x0C => r'\f',
          0x0D => r'\r',
          _ => ' ',
        });
        continue;
      }
      result.write(char);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
      } else if (char == '"') {
        inString = true;
      }
    }
    return result.toString();
  }
}
