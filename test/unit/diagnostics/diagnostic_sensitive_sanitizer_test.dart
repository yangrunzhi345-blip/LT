import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/diagnostics/diagnostic_sensitive_sanitizer.dart';

void main() {
  group('DiagnosticSensitiveSanitizer', () {
    const sanitizer = DiagnosticSensitiveSanitizer();

    test('redacts blacklisted keys in Map regardless of case', () {
      final input = {
        'api_key': 'sk-12345678901234567890',
        'ApiKey': 'sk-secret-key-12345678',
        'AUTHORIZATION': 'Bearer token-value-xyz',
        'password': 'my-secret-password',
        'token_count': 1024,
        'budget_tokens': 2048,
        'recommended_tokens': 512,
        'sessionTokens': 300,
        'nested': {
          'client_secret': 'abc-123',
          'cookie': 'session=abc',
          'normal_metric': 'ok',
        },
      };

      final result = sanitizer.sanitizeMap(input);

      expect(result['api_key'], equals('[REDACTED_CREDENTIAL]'));
      expect(result['ApiKey'], equals('[REDACTED_CREDENTIAL]'));
      expect(result['AUTHORIZATION'], equals('[REDACTED_CREDENTIAL]'));
      expect(result['password'], equals('[REDACTED_CREDENTIAL]'));
      expect(result['token_count'], equals(1024));
      expect(result['budget_tokens'], equals(2048));
      expect(result['recommended_tokens'], equals(512));
      expect(result['sessionTokens'], equals(300));

      final nested = result['nested'] as Map<String, dynamic>;
      expect(nested['client_secret'], equals('[REDACTED_CREDENTIAL]'));
      expect(nested['cookie'], equals('[REDACTED_CREDENTIAL]'));
      expect(nested['normal_metric'], equals('ok'));
    });

    test(
        'replaces credential substrings inside user text while preserving narrative',
        () {
      const userText = '我输入了指令：使用密钥 sk-abcdefghijklmnopqrstuvwxyz123 尝试开启石门。';
      final sanitized = sanitizer.sanitizeString(userText);

      expect(
        sanitized,
        equals('我输入了指令：使用密钥 [REDACTED_API_KEY] 尝试开启石门。'),
      );
    });

    test('replaces Bearer authorization substrings inside text', () {
      const text =
          'Error while connecting with Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9 to provider.';
      final sanitized = sanitizer.sanitizeString(text);

      expect(
        sanitized,
        contains('Bearer [REDACTED_BEARER_TOKEN] to provider.'),
      );
    });

    test('redacts labeled credentials inside diagnostic text', () {
      const text =
          'request failed: Authorization: Bearer abc123 Cookie=session_xyz';

      final sanitized = sanitizer.sanitizeString(text);

      expect(sanitized, contains('Authorization=[REDACTED_CREDENTIAL]'));
      expect(sanitized, contains('Cookie=[REDACTED_CREDENTIAL]'));
      expect(sanitized, isNot(contains('abc123')));
      expect(sanitized, isNot(contains('session_xyz')));
    });

    test(
        'does not falsely redact natural story words containing token or secret',
        () {
      const storyText = '艾莲娜从怀中取出一枚古老的秘银 token 徽章，轻声说道：“这是我们家族守护的 secret 秘密。”';
      final sanitized = sanitizer.sanitizeString(storyText);

      expect(sanitized, equals(storyText));
    });

    test('sanitizes mixed Lists properly', () {
      final list = [
        '普通文本',
        {'api_key': 'secret-123'},
        ['嵌套', 'Bearer eyJhbGciOiJIUzI1NiJ9'],
      ];

      final sanitized = sanitizer.sanitizeList(list);

      expect(sanitized[0], equals('普通文本'));
      expect((sanitized[1] as Map)['api_key'], equals('[REDACTED_CREDENTIAL]'));
      expect(
        (sanitized[2] as List)[1],
        equals('Bearer [REDACTED_BEARER_TOKEN]'),
      );
    });
  });
}
