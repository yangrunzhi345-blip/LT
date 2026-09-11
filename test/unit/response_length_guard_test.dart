import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/engines/chat_engine_internals/response_length_guard.dart';

/// Reference implementations mirroring the *old* (pre-optimisation) algorithm.
///
/// These are kept in the test only to prove the optimised
/// `NarrativeLengthGuard.convergeToMaximum` stays byte-identical across random
/// inputs. They intentionally re-scan the growing candidate on every step, and
/// are not part of production code.
int _refCountChinese(String text) =>
    RegExp(r'[\u4e00-\u9fff]').allMatches(text).length;

String _refTrimToSentenceBoundary(String text, int maxChars) {
  if (maxChars <= 0) return '';
  if (_refCountChinese(text) <= maxChars) return text.trim();
  final sentences = RegExp(r'[^。！？；\n]*[。！？；\n]')
      .allMatches(text)
      .map((match) => match.group(0)!)
      .toList();
  if (sentences.isEmpty) return text.trim();
  final kept = StringBuffer();
  for (final sentence in sentences) {
    final candidate = '$kept$sentence';
    if (_refCountChinese(candidate) > maxChars) break;
    kept.write(sentence);
  }
  return kept.toString().trim();
}

String _refConverge(String narrative, int hardMaximum) {
  if (_refCountChinese(narrative) <= hardMaximum) return narrative;
  final paragraphs = narrative
      .split(RegExp(r'\n\s*\n'))
      .map((paragraph) => paragraph.trim())
      .where((paragraph) => paragraph.isNotEmpty)
      .toList();
  final kept = <String>[];
  for (final paragraph in paragraphs) {
    final candidate = [...kept, paragraph].join('\n\n');
    if (_refCountChinese(candidate) <= hardMaximum) {
      kept.add(paragraph);
      continue;
    }
    final remainingBudget = hardMaximum - _refCountChinese(kept.join('\n\n'));
    final trimmed = _refTrimToSentenceBoundary(paragraph, remainingBudget);
    if (trimmed.isNotEmpty) kept.add(trimmed);
    break;
  }
  return kept.join('\n\n');
}

String _randomText(math.Random rng) {
  const chinese = '天地玄黄宇宙洪荒日月盈昃辰宿列张';
  const ascii = 'abcXYZ0123456789 ';
  const punct = '。！？；，、：""()';
  final buf = StringBuffer();
  final chunks = rng.nextInt(20) + 1;
  for (var i = 0; i < chunks; i++) {
    switch (rng.nextInt(7)) {
      case 0:
        buf.write(chinese[rng.nextInt(chinese.length)]);
        break;
      case 1:
        buf.write(ascii[rng.nextInt(ascii.length)]);
        break;
      case 2:
        buf.write(punct[rng.nextInt(punct.length)]);
        break;
      case 3:
        buf.write('。');
        break;
      case 4:
        buf.write('\n');
        break;
      case 5:
        buf.write('\n\n');
        break;
      case 6:
        buf.write('😀');
        break;
    }
  }
  return buf.toString();
}

void main() {
  const guard = NarrativeLengthGuard();

  group('countChinese', () {
    test('counts canonical BMP CJK (Extension A + Unified Ideographs)', () {
      expect(guard.countChinese(''), 0);
      expect(guard.countChinese('English 123'), 0);
      expect(guard.countChinese('中文'), 2);
      expect(guard.countChinese('中a文1 b'), 2);
      expect(guard.countChinese('。！？；\n，、'), 0);
      expect(guard.countChinese('😀😀'), 0);
      expect(guard.countChinese('你好😀世界'), 4);
      // Extension A is now counted (regression: it used to be dropped).
      expect(guard.countChinese('㐀䶿'), 2);
      expect(guard.countChinese('中㐀文䶿'), 4);
    });
  });

  group('convergeToMaximum', () {
    test('empty string returns empty', () {
      expect(guard.convergeToMaximum('', 100), '');
    });

    test('pure English is within cap and returned unchanged', () {
      expect(guard.convergeToMaximum('Hello world.', 100), 'Hello world.');
    });

    test('pure Chinese within cap returned unchanged', () {
      expect(guard.convergeToMaximum('这是中文。', 100), '这是中文。');
    });

    test('mixed Chinese/English within cap returned unchanged', () {
      expect(guard.convergeToMaximum('艾莉丝 Alice 500 coins。', 100),
          '艾莉丝 Alice 500 coins。');
    });

    test('exactly equal to hard maximum returned unchanged', () {
      expect(guard.convergeToMaximum('一二三', 3), '一二三');
    });

    test('over cap by one char with no boundary keeps whole paragraph', () {
      expect(guard.convergeToMaximum('一二三四', 3), '一二三四');
    });

    test('converges overflow at the last fitting sentence boundary', () {
      expect(guard.convergeToMaximum('第一句。第二句。第三句。', 5), '第一句。');
    });

    test('keeps whole paragraphs until a paragraph no longer fits', () {
      expect(guard.convergeToMaximum('第一段内容。\n\n第二段内容。', 5), '第一段内容。');
    });

    test('。！？ each act as sentence boundaries', () {
      expect(guard.convergeToMaximum('甲乙。丙丁。', 2), '甲乙。');
      expect(guard.convergeToMaximum('甲乙！丙丁。', 2), '甲乙！');
      expect(guard.convergeToMaximum('甲乙？丙丁。', 2), '甲乙？');
    });

    test('； acts as a sentence boundary', () {
      expect(guard.convergeToMaximum('甲乙；丙丁。', 2), '甲乙；');
    });

    test('newline acts as a sentence boundary (trailing newline trimmed)', () {
      expect(guard.convergeToMaximum('甲乙\n丙丁。', 2), '甲乙');
    });

    test('paragraph separator \n\n is preserved in the overflow path', () {
      expect(
        guard.convergeToMaximum('第一段内容。\n\n第二段内容。\n\n第三段内容。', 10),
        '第一段内容。\n\n第二段内容。',
      );
    });

    test('emoji is not counted as Chinese', () {
      expect(guard.convergeToMaximum('😀😀😀', 0), '😀😀😀');
      expect(guard.convergeToMaximum('你好😀世界。', 100), '你好😀世界。');
    });

    test('long paragraph with no sentence boundary is kept intact', () {
      const text = '一二三四五六七八九十';
      expect(guard.convergeToMaximum(text, 3), text);
    });

    test('first full sentence already over budget yields empty', () {
      expect(guard.convergeToMaximum('一二三四五。六七八。', 3), '');
    });

    test('hardMaximum <= 0 keeps only boundary-free / zero-chinese content',
        () {
      expect(guard.convergeToMaximum('', 0), '');
      expect(guard.convergeToMaximum('中文', 0), '');
      expect(guard.convergeToMaximum('中文', -1), '');
      expect(guard.convergeToMaximum('English', -5), '');
      // Pure English has zero Chinese, so it stays within a zero cap.
      expect(guard.convergeToMaximum('English', 0), 'English');
    });

    test('100K synthetic narrative converges to a bounded result', () {
      final narrative = '第一句完整结束。' * 20000; // 6 chinese × 20000
      final converged = guard.convergeToMaximum(narrative, 120);
      expect(guard.countChinese(converged), lessThanOrEqualTo(120));
      expect(converged, endsWith('。'));
    });
  });

  group('differential vs old reference implementation', () {
    test('byte-identical across random inputs', () {
      final rng = math.Random(20260911);
      for (var i = 0; i < 500; i++) {
        final text = _randomText(rng);
        final cap = rng.nextInt(40) - 5; // -5 .. 34, exercising <= 0
        expect(
          guard.convergeToMaximum(text, cap),
          _refConverge(text, cap),
          reason: 'mismatch for cap=$cap text=${text.replaceAll('\n', '\\n')}',
        );
      }
    });
  });
}
