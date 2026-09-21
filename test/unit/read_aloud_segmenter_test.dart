import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/services/read_aloud/text_segmenter.dart';

String _stripWhitespace(String value) => value.replaceAll(RegExp(r'\s+'), '');

bool _hasLoneSurrogate(String value) {
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    final isHigh = unit >= 0xD800 && unit <= 0xDBFF;
    final isLow = unit >= 0xDC00 && unit <= 0xDFFF;
    if (isHigh) {
      if (i + 1 >= value.length) return true;
      final next = value.codeUnitAt(i + 1);
      if (next < 0xDC00 || next > 0xDFFF) return true;
      i++;
    } else if (isLow) {
      return true;
    }
  }
  return false;
}

void main() {
  group('TextSegmenter', () {
    const segmenter = TextSegmenter(maxLength: 40);

    test('空串与纯空白返回空列表', () {
      expect(segmenter.segment(''), isEmpty);
      expect(segmenter.segment('   \n  '), isEmpty);
    });

    test('按中文标点切分', () {
      // 上限调小以观察按句切分；上限内的句子会被合并（见下方合并测试）。
      const tight = TextSegmenter(maxLength: 5);
      const text = '第一句。第二句！第三句？';
      final segments = tight.segment(text);
      expect(segments, ['第一句。', '第二句！', '第三句？']);
    });

    test('上限内的相邻短句会被合并', () {
      const text = '第一句。第二句！';
      expect(segmenter.segment(text), ['第一句。 第二句！']);
    });

    test('按英文标点切分，但不切开小数', () {
      const tight = TextSegmenter(maxLength: 20);
      final segments = tight.segment('Pi is 3.14 exactly. Next one!');
      expect(segments.length, 2);
      expect(segments.first, contains('3.14'));
      expect(segments.last, 'Next one!');
    });

    test('超长无标点中文被硬切分且不超过上限', () {
      final text = '字' * 500;
      final segments = segmenter.segment(text);
      expect(segments.length, greaterThan(1));
      for (final segment in segments) {
        expect(segment.length, lessThanOrEqualTo(40));
      }
      expect(_stripWhitespace(segments.join()), _stripWhitespace(text));
    });

    test('emoji 与代理对不会被切开', () {
      final text = '😀' * 300;
      final segments = segmenter.segment(text);
      for (final segment in segments) {
        expect(_hasLoneSurrogate(segment), isFalse,
            reason: '段内出现孤立代理对: $segment');
        expect(segment.length, lessThanOrEqualTo(40));
      }
      expect(_stripWhitespace(segments.join()), _stripWhitespace(text));
    });

    test('不变式：拼接去掉空白后与输入一致（中英数emoji混排）', () {
      const text = '# 标题\n'
          '第一段文字，包含 English words 和数字 12345。\n'
          '第二段 😀😀😀，带 **Markdown** 与换行。';
      final segments = segmenter.segment(text);
      expect(_stripWhitespace(segments.join()), _stripWhitespace(text));
    });

    test('每段非空且不含首尾空白', () {
      final segments = segmenter.segment('  句子一。   句子二。  ');
      expect(segments, isNotEmpty);
      for (final segment in segments) {
        expect(segment.trim(), segment);
        expect(segment, isNotEmpty);
      }
    });

    test('可配置上限生效', () {
      const small = TextSegmenter(maxLength: 8);
      final segments = small.segment('这是一个比较长的中文句子需要被切开。');
      for (final segment in segments) {
        expect(segment.length, lessThanOrEqualTo(8));
      }
    });
  });
}
