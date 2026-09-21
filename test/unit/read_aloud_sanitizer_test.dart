import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/services/read_aloud/text_sanitizer.dart';

void main() {
  const sanitizer = TextSanitizer();

  group('TextSanitizer', () {
    test('空输入与纯空白返回空串', () {
      expect(sanitizer.sanitize(''), '');
      expect(sanitizer.sanitize('   \n\t  '), '');
    });

    test('剔除 ---JSON--- 之后的双段协议数据', () {
      const raw = '雾港的灯塔亮了。\n---JSON---\n{"hp": 10, "options": ["前进"]}';
      final clean = sanitizer.sanitize(raw);
      expect(clean, '雾港的灯塔亮了。');
      expect(clean, isNot(contains('hp')));
      expect(clean, isNot(contains('options')));
    });

    test('剔除代码围栏，包括未闭合围栏', () {
      final closed = sanitizer.sanitize('前文\n```json\n{"a":1}\n```\n后文');
      expect(closed, contains('前文'));
      expect(closed, contains('后文'));
      expect(closed, isNot(contains('json')));
      expect(closed, isNot(contains('"a"')));

      final unclosed = sanitizer.sanitize('前文\n```dart\nvoid main() {}');
      expect(unclosed, '前文');
    });

    test('剔除 HTML 标签与注释', () {
      expect(
        sanitizer.sanitize('<p>正文</p><!-- 隐藏注释 -->结尾'),
        '正文结尾',
      );
    });

    test('剔除思维链块而不是只剔除标签', () {
      const raw = '结论在此。<thinking>内部推理，不应朗读。</thinking>';
      final clean = sanitizer.sanitize(raw);
      expect(clean, '结论在此。');
      expect(clean, isNot(contains('内部推理')));
    });

    test('Markdown 标题/列表/引用/强调/链接标记被移除但保留文字', () {
      const raw = '# 标题\n'
          '- 第一项\n'
          '> 引用内容\n'
          '这是 **加粗** 与 *斜体* 与 [链接文字](https://example.com)';
      final clean = sanitizer.sanitize(raw);
      expect(clean, isNot(contains('#')));
      expect(clean, isNot(contains('**')));
      expect(clean, isNot(contains('https://')));
      expect(clean, contains('标题'));
      expect(clean, contains('第一项'));
      expect(clean, contains('引用内容'));
      expect(clean, contains('加粗'));
      expect(clean, contains('斜体'));
      expect(clean, contains('链接文字'));
    });

    test('图片整体剔除', () {
      expect(sanitizer.sanitize('看图 ![插图](a.png) 结束'), '看图 结束');
    });

    test('空白与异常换行被归一化', () {
      final clean = sanitizer.sanitize('a\r\n\r\n\r\n  b\t\tc  ');
      expect(clean, 'a\n\nb c');
    });

    test('emoji 与中文原样保留', () {
      const raw = '她笑了 😀，然后说：「好呀。」';
      expect(sanitizer.sanitize(raw), raw);
    });

    test('确定性：相同输入得到相同输出', () {
      const raw = '**粗体**\n---JSON---\n{"x":1}';
      expect(sanitizer.sanitize(raw), sanitizer.sanitize(raw));
    });
  });
}
