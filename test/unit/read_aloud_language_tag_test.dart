import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/services/read_aloud/language_tag.dart';

void main() {
  group('BCP-47 归一化', () {
    test('下划线 / 大小写归一化为标准 tag', () {
      expect(normalizeBcp47('zh_CN'), 'zh-CN');
      expect(normalizeBcp47('zh-cn'), 'zh-CN');
      expect(normalizeBcp47('ZH-cn'), 'zh-CN');
      expect(normalizeBcp47('EN_us'), 'en-US');
      expect(normalizeBcp47('en-US'), 'en-US');
      expect(normalizeBcp47('en-GB'), 'en-GB');
      expect(normalizeBcp47('  ja-jp  '), 'ja-JP');
    });

    test('带 script 的标签语义完整保留', () {
      expect(normalizeBcp47('zh-Hans-CN'), 'zh-Hans-CN');
      expect(normalizeBcp47('zh-Hant-TW'), 'zh-Hant-TW');
      expect(normalizeBcp47('zh_hans_cn'), 'zh-Hans-CN');
      expect(normalizeBcp47('ZH-HANT-tw'), 'zh-Hant-TW');
    });

    test('非法或空输入返回空字符串', () {
      expect(normalizeBcp47(null), '');
      expect(normalizeBcp47(''), '');
      expect(normalizeBcp47('   '), '');
      expect(normalizeBcp47('-'), '');
      expect(normalizeBcp47('123'), '');
      expect(normalizeBcp47('a'), '');
      expect(isValidBcp47('zh-CN'), isTrue);
      expect(isValidBcp47('123'), isFalse);
    });

    test('languageFamily / languageScript / sameLanguageFamily', () {
      expect(languageFamily('zh-Hant-TW'), 'zh');
      expect(languageFamily('en-US'), 'en');
      expect(languageFamily(''), isNull);
      expect(languageScript('zh-Hant-TW'), 'Hant');
      expect(languageScript('zh-CN'), isNull);

      expect(sameLanguageFamily('en-GB', 'en_US'), isTrue);
      expect(sameLanguageFamily('zh-TW', 'en-US'), isFalse);
      expect(sameLanguageFamily(null, 'en-US'), isFalse);
    });
  });
}
