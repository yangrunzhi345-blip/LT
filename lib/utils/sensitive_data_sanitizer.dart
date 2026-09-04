/// 导出内容共用的敏感信息脱敏规则。
const sensitiveFieldPatterns = [
  'apikey',
  'api_key',
  'authorization',
  'bearer',
  'token',
  'secret',
  'password',
  'access_key',
  'dashscope',
  'deepseek',
  'openai_key',
  'model_key',
];

final sensitiveContentRegexes = [
  RegExp(r'sk-[a-zA-Z0-9]{8,}', caseSensitive: false),
  RegExp(r'Bearer\s+[a-zA-Z0-9._\-]+', caseSensitive: false),
  RegExp(r'Authorization:\s*[a-zA-Z0-9._\-]+', caseSensitive: false),
  RegExp(r'x-api-key["\s:=]+[a-zA-Z0-9._\-]+', caseSensitive: false),
];

String sanitizeSensitiveText(String value) {
  var sanitized = value;
  for (final regex in sensitiveContentRegexes) {
    sanitized = sanitized.replaceAll(regex, '[REDACTED]');
  }
  return sanitized;
}

Map<String, Object?> sanitizeSensitiveRow(Map<String, Object?> row) {
  return row.map((key, value) {
    final lowerKey = key.toLowerCase();
    if (sensitiveFieldPatterns.any(lowerKey.contains)) {
      return MapEntry(key, '[REDACTED]');
    }
    if (value is String && value.isNotEmpty) {
      return MapEntry(key, sanitizeSensitiveText(value));
    }
    return MapEntry(key, value);
  });
}
