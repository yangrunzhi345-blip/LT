import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/engines/chat_engine_internals/response_length_guard.dart';

/// Reference implementation mirroring the *old* 837d59c algorithm: Basic-only
/// Chinese counting and a no-boundary fallback that returns the whole
/// paragraph.
///
/// It is kept in the test only to prove the guard stays byte-identical on
/// inputs whose behaviour must not change. It intentionally re-scans the
/// growing candidate, and is not production code.
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

/// Inputs whose behaviour must not change: no Extension A, and every paragraph
/// ends with a sentence boundary so the hard-truncation fallback never fires.
String _randomCompatibleText(math.Random rng) {
  const chinese = '天地玄黄宇宙洪荒日月盈昃辰宿列张';
  const ascii = 'abcXYZ0123456789 ';
  const punct = '。！？；，、：""()';
  final paragraphs = <String>[];
  final paragraphCount = rng.nextInt(5) + 1;
  for (var p = 0; p < paragraphCount; p++) {
    final buf = StringBuffer();
    final chunks = rng.nextInt(20) + 1;
    for (var i = 0; i < chunks; i++) {
      switch (rng.nextInt(4)) {
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
          buf.write('😀');
          break;
      }
    }
    buf.write('。'); // guarantee a boundary so behaviour is unchanged
    paragraphs.add(buf.toString());
  }
  return paragraphs.join('\n\n');
}

/// Fully arbitrary inputs — Extension A, no-boundary paragraphs, emoji — used
/// to check the new invariants.
String _randomArbitraryText(math.Random rng) {
  const basic = '天地玄黄宇宙洪荒';
  const extA = '㐀㐁㐂䶿';
  const ascii = 'abcXYZ0123456789 ';
  const punct = '。！？；，、：""()';
  final buf = StringBuffer();
  final chunks = rng.nextInt(30) + 1;
  for (var i = 0; i < chunks; i++) {
    switch (rng.nextInt(7)) {
      case 0:
        buf.write(basic[rng.nextInt(basic.length)]);
        break;
      case 1:
        buf.write(extA[rng.nextInt(extA.length)]);
        break;
      case 2:
        buf.write(ascii[rng.nextInt(ascii.length)]);
        break;
      case 3:
        buf.write(punct[rng.nextInt(punct.length)]);
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

    test('over cap by one char with no boundary truncates at the cap', () {
      expect(guard.convergeToMaximum('一二三四', 3), '一二三');
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

    test('long paragraph with no sentence boundary is hard-truncated', () {
      expect(guard.convergeToMaximum('一二三四五六七八九十', 3), '一二三');
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

  group('Extension A participates in convergence', () {
    test('counts Extension A in the overflow budget', () {
      expect(guard.convergeToMaximum('㐀㐁㐂㐃', 3), '㐀㐁㐂');
      expect(guard.convergeToMaximum('㐀㐁。㐂㐃。', 2), '㐀㐁。');
    });
  });

  group('no-boundary overflow is hard-truncated to the maximum', () {
    test('200 Chinese chars / cap 120 -> exactly 120', () {
      final result = guard.convergeToMaximum('中' * 200, 120);
      expect(result, '中' * 120);
      expect(guard.countChinese(result), 120);
    });

    test('mixed Chinese/English / cap 120 -> exactly 120', () {
      final result = guard.convergeToMaximum('艾莉丝abc😀' * 60, 120);
      expect(guard.countChinese(result), 120);
    });

    test('Chinese + emoji never splits a surrogate pair', () {
      final result = guard.convergeToMaximum('中😀' * 100, 50);
      expect(result, '${'中😀' * 49}中');
      expect(guard.countChinese(result), 50);
      expect(result.contains('\uFFFD'), isFalse);
    });

    test('pure English without a boundary is preserved', () {
      expect(guard.convergeToMaximum('abcdefg', 0), 'abcdefg');
      expect(guard.convergeToMaximum('abcdefg', 3), 'abcdefg');
    });

    test('exactly at cap is preserved, cap+1 converges', () {
      expect(guard.convergeToMaximum('中' * 5, 5), '中' * 5);
      expect(guard.convergeToMaximum('中' * 6, 5), '中' * 5);
    });

    test('hard maximum is a true upper bound for no-boundary input', () {
      for (final cap in [0, 1, 7, 50, 120]) {
        final result = guard.convergeToMaximum('天地玄黄abc😀' * 40, cap);
        expect(guard.countChinese(result), lessThanOrEqualTo(cap));
      }
    });
  });

  group('settlement payload separation is untouched', () {
    test('split keeps narrative and payload byte-identical', () {
      const raw = '正文内容。\n---JSON---\n{"scene":"大厅","options":["走"]}';
      final parts = guard.split(raw);
      expect(parts.narrative, '正文内容。');
      expect(parts.payload, '---JSON---\n{"scene":"大厅","options":["走"]}');
      expect(parts.hasPayload, isTrue);
    });
  });

  group('differential vs old reference (unchanged behaviour)', () {
    test('byte-identical for inputs without Extension A or fallback', () {
      final rng = math.Random(20260911);
      for (var i = 0; i < 500; i++) {
        final text = _randomCompatibleText(rng);
        final cap = rng.nextInt(40) - 5; // -5 .. 34, exercising <= 0
        expect(
          guard.convergeToMaximum(text, cap),
          _refConverge(text, cap),
          reason: 'mismatch for cap=$cap text=${text.replaceAll('\n', '\\n')}',
        );
      }
    });

    test('normal sentence-boundary overflow matches the old result', () {
      for (final cap in [1, 2, 3, 5, 8]) {
        const text = '第一句。第二句！第三句？';
        expect(guard.convergeToMaximum(text, cap), _refConverge(text, cap));
      }
    });

    test('boundary only at the start with a long trailing run matches', () {
      final text = '开篇。${'天地玄黄' * 250}';
      for (final cap in [0, 1, 2, 3, 10, 500]) {
        expect(guard.convergeToMaximum(text, cap), _refConverge(text, cap));
      }
    });
  });

  group('new invariants over arbitrary inputs', () {
    test('result never exceeds the cap and never emits replacement chars', () {
      final rng = math.Random(424242);
      for (var i = 0; i < 800; i++) {
        final text = _randomArbitraryText(rng);
        final cap = rng.nextInt(60); // 0 .. 59
        final result = guard.convergeToMaximum(text, cap);
        expect(
          guard.countChinese(result),
          lessThanOrEqualTo(cap),
          reason: 'cap=$cap text=${text.replaceAll('\n', '\\n')}',
        );
        expect(
          result.contains('\uFFFD'),
          isFalse,
          reason: 'replacement char for text=${text.replaceAll('\n', '\\n')}',
        );
      }
    });
  });
}
