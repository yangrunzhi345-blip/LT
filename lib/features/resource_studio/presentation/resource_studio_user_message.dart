/// Converts runtime and protocol errors into terminology suitable for Studio.
///
/// Runtime errors remain detailed for diagnostics, but the presentation layer
/// must not expose protocol names from older resource-system phases.
String resourceStudioUserMessage(Object error) {
  var message = error.toString().trim();
  message = message.replaceFirst(
    RegExp(r'^(?:Bad state|StateError|Exception):\s*'),
    '',
  );

  const replacements = <String, String>{
    r'\bResourceTree\b': '资源内容',
    r'\bsections?\b': '章节',
    r'\brevision\s+ID\b': '历史版本标识',
    r'\brevisionId\b': '历史版本标识',
    r'\bJSON\b': '数据格式',
    r'\babsolute\s+limit\b': '容量上限',
    r'\bcompression\s+jobs?\b': '优化任务',
    r'\bassembly\s+revision\b': '资源版本',
    r'\bsectionId\b': '章节标识',
    r'\bgenerationId\b': '生成任务标识',
    r'\bresourceId\b': '资源标识',
    r'\btaskId\b': '任务标识',
    r'\battemptId\b': '尝试标识',
    r'\bpart[_ ]?id\b': '段落标识',
    r'\bparts?\b': '段落',
  };
  for (final replacement in replacements.entries) {
    message = message.replaceAll(
      RegExp(replacement.key, caseSensitive: false),
      replacement.value,
    );
  }
  return message.isEmpty ? '操作失败，请重试' : message;
}
