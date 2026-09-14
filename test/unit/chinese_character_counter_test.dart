import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/engines/chat_engine.dart';
import 'package:lt_dialogue/engines/chat_engine_internals/response_length_guard.dart';
import 'package:lt_dialogue/utils/chinese_character_counter.dart';

String _cp(int codePoint) => String.fromCharCode(codePoint);

void main() {
  group('ChineseCharacterCounter canonical range', () {
    test('counts both CJK Extension A boundaries', () {
      expect(ChineseCharacterCounter.count(_cp(0x3400)), 1); // 㐀
      expect(ChineseCharacterCounter.count(_cp(0x4DBF)), 1); // 䶿
    });

    test('counts both CJK Unified Ideograph boundaries', () {
      expect(ChineseCharacterCounter.count(_cp(0x4E00)), 1); // 一
      expect(ChineseCharacterCounter.count(_cp(0x9FFF)), 1); // 鿿
    });

    test('rejects code units just outside both ranges', () {
      for (final codePoint in [0x33FF, 0x4DC0, 0x4DFF, 0xA000]) {
        expect(
          ChineseCharacterCounter.count(_cp(codePoint)),
          0,
          reason: 'U+${codePoint.toRadixString(16).toUpperCase()}',
        );
        expect(ChineseCharacterCounter.isChineseCodeUnit(codePoint), isFalse);
      }
    });

    test('counts mixed Basic + Extension A', () {
      final byCode = '${_cp(0x3400)}${_cp(0x4E00)}'
          '${_cp(0x4DBF)}${_cp(0x9FFF)}';
      expect(ChineseCharacterCounter.count(byCode), 4);
      // Literal sanity check: 㐀一䶿鿿
      expect(ChineseCharacterCounter.count('㐀一䶿鿿'), 4);
    });

    test('ignores English, digits, punctuation, whitespace, newlines, emoji',
        () {
      expect(ChineseCharacterCounter.count(''), 0);
      expect(ChineseCharacterCounter.count('English 123'), 0);
      expect(ChineseCharacterCounter.count('。！？；，、\n\t '), 0);
      expect(ChineseCharacterCounter.count('😀😀'), 0);
      expect(ChineseCharacterCounter.count('中a文1 b'), 2);
    });

    test('does not count surrogate halves', () {
      // 😀 is a surrogate pair; only 中 and 文 are canonical characters.
      expect(ChineseCharacterCounter.count('中😀文'), 2);
    });
  });

  group('counting definitions are unified', () {
    const guard = NarrativeLengthGuard();
    final samples = <String>[
      '',
      'English 123',
      '中文',
      '㐀䶿一鿿',
      '中㐀文䶿混合abc😀',
      '。！？；\n',
      '😀😀😀',
    ];

    test('ChatEngine == NarrativeLengthGuard == ChineseCharacterCounter', () {
      for (final sample in samples) {
        final canonical = ChineseCharacterCounter.count(sample);
        expect(ChatEngine.countChinese(sample), canonical, reason: sample);
        expect(guard.countChinese(sample), canonical, reason: sample);
      }
    });

    test('Extension A characters are no longer dropped by the guard', () {
      // Regression: the guard used to use a Basic-only regex.
      expect(guard.countChinese('㐀䶿'), 2);
      expect(ChatEngine.countChinese('㐀䶿'), 2);
    });
  });
}
