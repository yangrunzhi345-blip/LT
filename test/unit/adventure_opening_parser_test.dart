import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/services/ai_generator_service.dart';

void main() {
  group('AiGeneratorService.parseOpeningResponse', () {
    test('accepts a scene with 3 valid options', () {
      const raw = '''
{
  "scene": "暴雨夜的旧城区，霓虹在水洼中碎成一片。",
  "options": ["推门进入酒馆", "绕到后巷查看", "拦下一辆出租车"]
}''';

      final parsed = AiGeneratorService.parseOpeningResponse(raw);
      expect(parsed, isNotNull);
      expect(parsed!['scene'], contains('暴雨夜的旧城区'));
      expect(parsed['options'], '1 推门进入酒馆\n2 绕到后巷查看\n3 拦下一辆出租车');
    });

    test('accepts options wrapped in a markdown fence', () {
      const raw = '''```json
{"scene":"晨雾笼罩的码头。","options":["登船","返回客栈"]}
```''';

      final parsed = AiGeneratorService.parseOpeningResponse(raw);
      expect(parsed, isNotNull);
      expect(parsed!['scene'], '晨雾笼罩的码头。');
      expect(parsed['options']!.split('\n'), hasLength(2));
    });

    test('rejects a response that lacks options', () {
      const raw = '{"scene":"你在一间空屋里醒来。"}';
      expect(AiGeneratorService.parseOpeningResponse(raw), isNull);
    });

    test('rejects a response with only one option', () {
      const raw = '{"scene":"你在一间空屋里醒来。","options":["走出去"]}';
      expect(AiGeneratorService.parseOpeningResponse(raw), isNull);
    });

    test('rejects more than four options', () {
      const raw = '{"scene":"你在一间空屋里醒来。",'
          '"options":["a","b","c","d","e"]}';
      expect(AiGeneratorService.parseOpeningResponse(raw), isNull);
    });

    test('rejects a missing or empty scene', () {
      expect(
        AiGeneratorService.parseOpeningResponse('{"options":["a","b"]}'),
        isNull,
      );
      expect(
        AiGeneratorService.parseOpeningResponse(
            '{"scene":"   ","options":["a","b"]}'),
        isNull,
      );
    });

    test('rejects a scene that is itself JSON', () {
      const raw = '{"scene":"{\\"options\\":[\\"a\\",\\"b\\"]}",'
          '"options":["a","b"]}';
      expect(AiGeneratorService.parseOpeningResponse(raw), isNull);
    });

    test('rejects truncated JSON instead of returning raw text', () {
      const raw = '{"scene":"你在一间空屋里醒来。","options":["走出去"';
      expect(AiGeneratorService.parseOpeningResponse(raw), isNull);
    });

    test('rejects a non-JSON response instead of returning raw text', () {
      const raw = '好的，这是为你设计的序章：你在一间空屋里醒来……';
      expect(AiGeneratorService.parseOpeningResponse(raw), isNull);
    });

    test('normalizes numbered, bulleted and map-shaped options', () {
      const raw = '''
{
  "scene": "古老图书馆的深处。",
  "options": ["1. 翻阅典籍", "- 点亮烛台", {"text": "3、推开暗门"}]
}''';

      final parsed = AiGeneratorService.parseOpeningResponse(raw);
      expect(parsed, isNotNull);
      expect(parsed!['options'], '1 翻阅典籍\n2 点亮烛台\n3 推开暗门');
    });
  });
}
