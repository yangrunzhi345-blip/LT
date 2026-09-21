import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/services/read_aloud/read_aloud_language_resolver.dart';

void main() {
  const resolver = ReadAloudLanguageResolver();

  ReadAloudLanguageResolution resolve({
    required String requested,
    required List<String> available,
    String fallback = 'zh-CN',
  }) =>
      resolver.resolve(
        requestedTag: requested,
        availableLanguages: available,
        fallbackTag: fallback,
      );

  group('ReadAloudLanguageResolver fallback 链', () {
    test('精确命中直接使用，不发生 fallback', () {
      final result = resolve(requested: 'en-US', available: ['en-US', 'zh-CN']);
      expect(result.resolvedTag, 'en-US');
      expect(result.fallbackApplied, isFalse);
      expect(result.unavailable, isFalse);
    });

    test('归一化后比较，不因分隔符/大小写误判不支持', () {
      final result = resolve(requested: 'zh-CN', available: ['zh_CN']);
      expect(result.resolvedTag, 'zh-CN');
      expect(result.fallbackApplied, isFalse);
    });

    test('en-GB 在只有 en-US 的设备上按家族降级', () {
      final result = resolve(requested: 'en-GB', available: ['en-US']);
      expect(result.requestedTag, 'en-GB');
      expect(result.resolvedTag, 'en-US');
      expect(result.fallbackApplied, isTrue);
    });

    test('zh-TW 在只有 zh-CN 的设备上降级，但不伪装成 zh-TW', () {
      final result = resolve(requested: 'zh-TW', available: ['zh-CN']);
      expect(result.requestedTag, 'zh-TW');
      expect(result.resolvedTag, 'zh-CN');
      expect(result.fallbackApplied, isTrue);
      expect(result.resolvedTag, isNot(result.requestedTag));
    });

    test('无同家族时使用用户兜底语言', () {
      final result = resolve(
        requested: 'ja-JP',
        available: ['zh-CN', 'en-US'],
        fallback: 'zh-CN',
      );
      expect(result.resolvedTag, 'zh-CN');
      expect(result.fallbackApplied, isTrue);
    });

    test('用户兜底也无精确命中时使用其同家族 locale', () {
      final result = resolve(
        requested: 'ja-JP',
        available: ['fr-FR', 'en-GB'],
        fallback: 'en-US',
      );
      expect(result.resolvedTag, 'en-GB');
      expect(result.fallbackApplied, isTrue);
    });

    test('系统已知语言里没有任何可接受目标 → unavailable', () {
      final result = resolve(
        requested: 'ja-JP',
        available: ['en-US'],
        fallback: 'ko-KR',
      );
      expect(result.resolvedTag, isNull);
      expect(result.unavailable, isTrue);
    });

    test('能力未知（空列表）时乐观透传，不谎报支持/不支持', () {
      final result = resolve(requested: 'ko-KR', available: const <String>[]);
      expect(result.resolvedTag, 'ko-KR');
      expect(result.unavailable, isFalse);
      expect(result.fallbackApplied, isFalse);
    });

    test('非法 tag 收敛到兜底语言', () {
      final result = resolve(requested: '!!!', available: ['zh-CN']);
      expect(result.requestedTag, 'zh-CN');
      expect(result.resolvedTag, 'zh-CN');
    });
  });
}
