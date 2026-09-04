class TokenEstimator {
  final String text;
  late final int estimatedTokens;

  TokenEstimator(this.text) : estimatedTokens = _estimate(text);

  static int _estimate(String text) {
    if (text.isEmpty) return 0;
    var tokens = 0.0;
    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (code >= 0x4E00 && code <= 0x9FFF) {
        tokens += 0.7;
      } else if (code > 127) {
        tokens += 0.5;
      } else if (code == 32) {
        tokens += 0.25;
      } else {
        tokens += 0.3;
      }
    }
    return tokens.ceil();
  }

  int get tokens => estimatedTokens;

  Map<String, int> analyzePrompt(List<Map<String, String>> messages) {
    final parts = <String, int>{};
    var total = 0;
    for (final msg in messages) {
      final key = msg['role'] == 'system' ? '系统提示词' : '${msg['role']}消息';
      final tk = TokenEstimator(msg['content'] ?? '').tokens;
      parts[key] = (parts[key] ?? 0) + tk;
      total += tk;
    }
    parts['总计'] = total;
    return parts;
  }

  String windowWarning(int threshold) {
    if (tokens > threshold) return '⚠️ 超出 ($tokens/$threshold)';
    if (tokens > threshold * 0.8) return '⚠️ 接近上限 ($tokens/$threshold)';
    return '✅ ($tokens/$threshold)';
  }
}
