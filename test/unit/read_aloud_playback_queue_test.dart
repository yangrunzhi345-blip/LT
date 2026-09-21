import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/read_aloud/read_aloud_contracts.dart';
import 'package:lt_dialogue/services/read_aloud/playback_queue.dart';
import 'package:lt_dialogue/services/read_aloud/text_segmenter.dart';
import 'package:lt_dialogue/services/read_aloud/text_sanitizer.dart';

void main() {
  const sanitizer = TextSanitizer();
  const segmenter = TextSegmenter();

  PlaybackQueue build(
    List<ReadAloudSource> sources, {
    ReadAloudLanguageMode mode = ReadAloudLanguageMode.auto,
    String fixedLanguageTag = 'zh-CN',
  }) =>
      PlaybackQueue.build(
        sources: sources,
        sanitizer: sanitizer,
        segmenter: segmenter,
        languageMode: mode,
        fixedLanguageTag: fixedLanguageTag,
      );

  group('PlaybackQueue 自动语言', () {
    test('混合语言单来源按语言边界切成多个 Chunk', () {
      final queue = build(const [
        ReadAloudSource(
          id: 'mixed',
          text: '欢迎回来。\n'
              'Welcome home.\n'
              'おかえりなさい。\n'
              '돌아온 것을 환영합니다.',
        ),
      ]);

      expect(queue.length, 4);
      expect(
        List<String>.generate(
            queue.length, (i) => queue.chunkAt(i).languageTag),
        ['zh-CN', 'en-US', 'ja-JP', 'ko-KR'],
      );
      expect(
        List<String>.generate(queue.length, (i) => queue.chunkAt(i).text),
        ['欢迎回来。', 'Welcome home.', 'おかえりなさい。', '돌아온 것을 환영합니다.'],
      );
    });

    test('同语言连续句仍会被合并（不因语言回调拆分）', () {
      final queue = build(const [
        ReadAloudSource(id: 'zh', text: '第一句。第二句。第三句。'),
      ]);
      expect(queue.length, 1);
      expect(queue.chunkAt(0).languageTag, 'zh-CN');
    });

    test('中文夹少量英文不会被误判为英文', () {
      final queue = build(const [
        ReadAloudSource(id: 'cn', text: '第 3 个 API 请求失败。'),
      ]);
      expect(queue.length, 1);
      expect(queue.chunkAt(0).languageTag, 'zh-CN');
    });

    test('多来源连续朗读：每段携带自己的语言', () {
      final queue = build(const [
        ReadAloudSource(id: 'part-1', text: '这是中文。', label: 'Part 1'),
        ReadAloudSource(
            id: 'part-2', text: 'This is English.', label: 'Part 2'),
      ]);
      expect(queue.length, 2);
      expect(queue.chunkAt(0).sourceId, 'part-1');
      expect(queue.chunkAt(0).languageTag, 'zh-CN');
      expect(queue.chunkAt(1).sourceId, 'part-2');
      expect(queue.chunkAt(1).languageTag, 'en-US');
    });

    test('无法判断时使用 fallback languageTag', () {
      final queue = build(
        const [ReadAloudSource(id: 'noise', text: '12345 !!!')],
        fixedLanguageTag: 'zh-TW',
      );
      expect(queue.chunkAt(0).languageTag, 'zh-TW');
    });
  });

  group('PlaybackQueue 固定语言', () {
    test('所有 Chunk 统一使用固定语言', () {
      final queue = build(
        const [
          ReadAloudSource(
            id: 'mixed',
            text: '欢迎回来。\nWelcome home.\nおかえりなさい。',
          ),
        ],
        mode: ReadAloudLanguageMode.fixed,
        fixedLanguageTag: 'ja-JP',
      );
      expect(queue.length, greaterThanOrEqualTo(1));
      for (var i = 0; i < queue.length; i++) {
        expect(queue.chunkAt(i).languageTag, 'ja-JP');
      }
    });

    test('固定语言不做按语言断句（不同语言可合并）', () {
      final queue = build(
        const [
          ReadAloudSource(id: 'mixed', text: '欢迎回来。\nWelcome home.'),
        ],
        mode: ReadAloudLanguageMode.fixed,
        fixedLanguageTag: 'en-US',
      );
      expect(queue.length, 1);
      expect(queue.chunkAt(0).languageTag, 'en-US');
    });

    test('固定语言非法 tag 收敛到默认语言', () {
      final queue = build(
        const [ReadAloudSource(id: 'x', text: '内容。')],
        mode: ReadAloudLanguageMode.fixed,
        fixedLanguageTag: '!!!',
      );
      expect(queue.chunkAt(0).languageTag, 'zh-CN');
    });
  });
}
