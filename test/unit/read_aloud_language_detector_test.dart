import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/services/read_aloud/read_aloud_language_detector.dart';

void main() {
  const detector = ReadAloudLanguageDetector();

  String detect(String text, {String fallback = 'zh-CN'}) =>
      detector.detect(text, fallback: fallback);

  group('ReadAloudLanguageDetector script 规则', () {
    test('纯简体中文 → zh-CN', () {
      expect(detect('这个说法是对的，我们一起看看。'), 'zh-CN');
      expect(detect('简体中文默认使用简体字形。'), 'zh-CN');
    });

    test('纯繁体中文 → zh-TW', () {
      expect(detect('這個說法是對的，我們一起看看。'), 'zh-TW');
      expect(detect('繁體中文預設使用繁體字形。'), 'zh-TW');
    });

    test('英语 → en-US', () {
      expect(detect('The quick brown fox jumps over the lazy dog.'), 'en-US');
      expect(detect('Please read this sentence aloud.'), 'en-US');
    });

    test('日语 Hiragana → ja-JP', () {
      expect(detect('おはようございます。'), 'ja-JP');
    });

    test('日语 Katakana → ja-JP', () {
      expect(detect('コンピューターのテストです。'), 'ja-JP');
    });

    test('日语 Han + Kana → ja-JP（假名强信号）', () {
      expect(detect('日本語のテスト。'), 'ja-JP');
      expect(detect('Pythonのコードを実行します。'), 'ja-JP');
    });

    test('韩语 → ko-KR', () {
      expect(detect('안녕하세요. 반갑습니다.'), 'ko-KR');
      expect(detect('돌아온 것을 환영합니다.'), 'ko-KR');
    });
  });

  group('ReadAloudLanguageDetector 混合语言与噪声', () {
    test('中文 + 少量英文不因 API 三个字母判为英文', () {
      expect(detect('第 3 个 API 请求失败。'), 'zh-CN');
      expect(detect('请检查 SDK 配置是否正确。'), 'zh-CN');
    });

    test('英文 + 少量中文仍判为英文', () {
      expect(detect('Hello world 世界'), 'en-US');
      expect(detect('The document contains 文档 content.'), 'en-US');
    });

    test('中英势均力敌时稳定偏向 Han（确定性）', () {
      // han == latin，命中 dominance 阈值边界，结果稳定且可复现。
      final first = detect('中文测试 abcd');
      final second = detect('中文测试 abcd');
      expect(first, second);
      expect(first, 'zh-CN');
    });

    test('数字 / Emoji / 标点 / 空白只有噪声 → 回退', () {
      expect(detect('1234567890'), 'zh-CN');
      expect(detect('😀🎉🚀'), 'zh-CN');
      expect(detect('！？。，、；：'), 'zh-CN');
      expect(detect('   \n\t  '), 'zh-CN');
      expect(detect('!!! 123 ??? 😀'), 'zh-CN');
    });

    test('空文本 → 回退', () {
      expect(detect(''), 'zh-CN');
      expect(detect('', fallback: 'en-US'), 'en-US');
    });

    test('仅 URL / 代码 → 拉丁字体（en-US）', () {
      expect(detect('https://example.com/api/v1?x=1'), 'en-US');
      expect(detect('final value = computeTotal(items);'), 'en-US');
    });

    test('共享 Han 无法判断简繁时回退用户中文 locale', () {
      // 山水明月 都是简繁同形，无特征字符。
      expect(detect('山水明月', fallback: 'zh-TW'), 'zh-TW');
      expect(detect('山水明月', fallback: 'zh-CN'), 'zh-CN');
      // 用户兜底不是中文时，仍收敛到中文默认，避免把中文念成外语。
      expect(detect('山水明月', fallback: 'en-US'), 'zh-CN');
    });

    test('fallback 也会被归一化', () {
      expect(detect('', fallback: 'zh_tw'), 'zh-TW');
      expect(detect('123', fallback: 'EN_us'), 'en-US');
    });

    test('极长文本仍稳定', () {
      final longText = List.filled(2000, '这是一段很长的中文正文。').join();
      expect(longText.length, greaterThan(10000));
      expect(detect(longText), 'zh-CN');

      final longEnglish =
          List.filled(2000, 'This is a long English body. ').join();
      expect(detect(longEnglish), 'en-US');
    });

    test('检测是纯函数且确定性（同样输入同样输出）', () {
      const samples = <String>[
        '第 3 个 API 请求失败。',
        'Hello 世界',
        'おかえりなさい。',
        '돌아온 것을 환영합니다.',
      ];
      for (final sample in samples) {
        expect(detect(sample), detect(sample));
      }
    });
  });

  group('ReadAloudLanguageDetector 特征字符表不变量', () {
    test('简繁特征字符互不污染，对照文本各自命中', () {
      // 若两个集合出现重叠字符，下面成对的简繁文本会同时命中而回退。
      expect(detect('这个说法对的来了'), 'zh-CN');
      expect(detect('這個說法對的來了'), 'zh-TW');
    });
  });
}
