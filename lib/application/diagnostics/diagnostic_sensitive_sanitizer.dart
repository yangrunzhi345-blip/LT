/// Sensitive data sanitizer for diagnostic session export.
///
/// Implements defense-in-depth sanitization:
/// 1. Blacklists exact credential keys in structured Maps.
/// 2. Redacts high-confidence credential tokens (e.g. `sk-...`, `Bearer ...`)
///    within arbitrary strings without mutating natural story narrative.
/// 3. Protects normal counters (`token_count`, `budget_tokens`, etc.).
class DiagnosticSensitiveSanitizer {
  const DiagnosticSensitiveSanitizer();

  static const Set<String> _credentialKeyBlacklist = {
    'api_key',
    'apikey',
    'api-key',
    'authorization',
    'auth_header',
    'auth_token',
    'access_token',
    'refresh_token',
    'client_secret',
    'password',
    'secret',
    'secret_key',
    'cookie',
    'set-cookie',
  };

  // High-confidence patterns for real credentials:
  // - Bearer tokens: e.g. "Bearer eyJhbGci..."
  // - OpenAI / DeepSeek API keys: e.g. "sk-abc12345678901234567890"
  // - GitHub personal access tokens: e.g. "ghp_abc..."
  static final RegExp _bearerPattern = RegExp(
    r'Bearer\s+[A-Za-z0-9\-._~+/]+=*',
    caseSensitive: false,
  );

  static final RegExp _apiKeyPattern = RegExp(
    r'\b(?:sk|ghp|gho|ghu|ghs|ghr)-[A-Za-z0-9]{20,}\b',
  );

  static final RegExp _labeledCredentialPattern = RegExp(
    r'\b(?:authorization|x-api-key|api[_-]?key|cookie|set-cookie|'
    r'client[_-]?secret|password|secret)\s*[:=]\s*[^\s,;]+',
    caseSensitive: false,
  );

  /// Sanitizes an arbitrary object (Map, List, String, or primitive).
  Object? sanitize(Object? value) {
    if (value == null) return null;
    if (value is Map) {
      return sanitizeMap(value);
    }
    if (value is List) {
      return sanitizeList(value);
    }
    if (value is String) {
      return sanitizeString(value);
    }
    return value;
  }

  /// Recursively sanitizes a Map, redacting sensitive keys and values.
  Map<String, dynamic> sanitizeMap(Map<dynamic, dynamic> map) {
    final result = <String, dynamic>{};
    for (final entry in map.entries) {
      final keyStr = entry.key.toString();
      final lowerKey = keyStr.toLowerCase().trim();

      if (_credentialKeyBlacklist.contains(lowerKey)) {
        result[keyStr] = '[REDACTED_CREDENTIAL]';
      } else {
        result[keyStr] = sanitize(entry.value);
      }
    }
    return result;
  }

  /// Recursively sanitizes a List.
  List<dynamic> sanitizeList(List<dynamic> list) {
    return list.map(sanitize).toList();
  }

  /// Scans a string for high-confidence credentials and replaces only the
  /// credential substring, preserving surrounding narrative/user text.
  String sanitizeString(String text) {
    if (text.isEmpty) return text;
    var sanitized = text;

    sanitized = sanitized.replaceAllMapped(_bearerPattern, (match) {
      return 'Bearer [REDACTED_BEARER_TOKEN]';
    });

    sanitized = sanitized.replaceAllMapped(_apiKeyPattern, (match) {
      return '[REDACTED_API_KEY]';
    });

    sanitized = sanitized.replaceAllMapped(_labeledCredentialPattern, (match) {
      final label = match[0]!.split(RegExp(r'\s*[:=]')).first;
      return '$label=[REDACTED_CREDENTIAL]';
    });

    return sanitized;
  }
}
