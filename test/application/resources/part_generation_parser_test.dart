import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/part_generation_parser.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';

void main() {
  group('PartGenerationParser', () {
    test('parses valid canonical snake_case JSON response', () {
      const raw = '''
{
  "protocol_version": 1,
  "generation_id": "gen_123",
  "resource_id": "res_world_1",
  "section_id": "res_world_1_sec_1",
  "part_id": "res_world_1_part_1",
  "attempt_id": "att_1",
  "content": "### 第一章：创世之光\\n\\n在最初的虚空中，星光凝聚成实体...",
  "summary": "关于星渊世界起源的记载",
  "status": "completed"
}
''';

      final response = PartGenerationParser.parse(raw);
      expect(response.protocolVersion, 1);
      expect(response.generationId, 'gen_123');
      expect(response.resourceId, const ResourceId('res_world_1'));
      expect(response.sectionId, const SectionId('res_world_1_sec_1'));
      expect(response.partId, const PartId('res_world_1_part_1'));
      expect(response.attemptId, 'att_1');
      expect(response.content, contains('创世之光'));
      expect(response.summary, '关于星渊世界起源的记载');
      expect(response.status, 'completed');
    });

    test('parses valid camelCase JSON response', () {
      const raw = '''
{
  "protocolVersion": 1,
  "generationId": "gen_456",
  "resourceId": "res_char_1",
  "sectionId": "res_char_1_sec_1",
  "partId": "res_char_1_part_1",
  "attemptId": "att_2",
  "content": "艾瑟尔从小在边境森林长大...",
  "summary": "角色早年经历",
  "status": "completed"
}
''';

      final response = PartGenerationParser.parse(raw);
      expect(response.protocolVersion, 1);
      expect(response.generationId, 'gen_456');
      expect(response.resourceId, const ResourceId('res_char_1'));
      expect(response.sectionId, const SectionId('res_char_1_sec_1'));
      expect(response.partId, const PartId('res_char_1_part_1'));
      expect(response.attemptId, 'att_2');
      expect(response.content, contains('艾瑟尔'));
    });

    test('extracts JSON enclosed in markdown code fences', () {
      const raw = '''
以下是为您生成的部件正文：
```json
{
  "protocol_version": 1,
  "generation_id": "gen_123",
  "resource_id": "res_1",
  "section_id": "sec_1",
  "part_id": "part_1",
  "attempt_id": "att_1",
  "content": "正文内容",
  "summary": "摘要",
  "status": "completed"
}
```
希望对您有所帮助！
''';

      final response = PartGenerationParser.parse(raw);
      expect(response.content, '正文内容');
      expect(response.partId.value, 'part_1');
    });

    test('throws on empty or whitespace response', () {
      expect(
        () => PartGenerationParser.parse('   \n  '),
        throwsA(isA<PartGenerationParseException>()),
      );
    });

    test('throws on malformed JSON', () {
      expect(
        () => PartGenerationParser.parse(
            '{ "protocol_version": 1, unquoted: true }'),
        throwsA(isA<PartGenerationParseException>()),
      );
    });

    test('throws if top-level is not a JSON object', () {
      expect(
        () => PartGenerationParser.parse('[1, 2, 3]'),
        throwsA(isA<PartGenerationParseException>()),
      );
    });

    test('throws when required fields are missing', () {
      const noVersion = '''
{
  "generation_id": "gen_1",
  "resource_id": "res_1",
  "section_id": "sec_1",
  "part_id": "part_1",
  "attempt_id": "att_1",
  "content": "ok"
}
''';
      expect(
        () => PartGenerationParser.parse(noVersion),
        throwsA(predicate<PartGenerationParseException>(
          (e) => e.field == 'protocol_version',
        )),
      );

      const noPartId = '''
{
  "protocol_version": 1,
  "generation_id": "gen_1",
  "resource_id": "res_1",
  "section_id": "sec_1",
  "attempt_id": "att_1",
  "content": "ok"
}
''';
      expect(
        () => PartGenerationParser.parse(noPartId),
        throwsA(predicate<PartGenerationParseException>(
          (e) => e.field == 'part_id',
        )),
      );

      const noContent = '''
{
  "protocol_version": 1,
  "generation_id": "gen_1",
  "resource_id": "res_1",
  "section_id": "sec_1",
  "part_id": "part_1",
  "attempt_id": "att_1"
}
''';
      expect(
        () => PartGenerationParser.parse(noContent),
        throwsA(predicate<PartGenerationParseException>(
          (e) => e.field == 'content',
        )),
      );
    });

    test('rejects non-canonical protocol_version types', () {
      const raw = '''
{
  "protocol_version": "1",
  "generation_id": "gen_1",
  "resource_id": "res_1",
  "section_id": "sec_1",
  "part_id": "part_1",
  "attempt_id": "att_1",
  "content": "正文"
}
''';
      expect(
        () => PartGenerationParser.parse(raw),
        throwsA(isA<PartGenerationParseException>()),
      );
    });

    test('rejects unauthorized extra fields (allowlist guard)', () {
      const raw = '''
{
  "protocol_version": 1,
  "generation_id": "gen_1",
  "resource_id": "res_1",
  "section_id": "sec_1",
  "part_id": "part_1",
  "attempt_id": "att_1",
  "content": "正文",
  "parts": [{"part_id": "p2", "content": "inject"}]
}
''';
      expect(
        () => PartGenerationParser.parse(raw),
        throwsA(isA<PartGenerationParseException>()),
      );
    });

    test('rejects duplicate snake_case and camelCase semantic fields', () {
      const raw = '''
{
  "protocol_version": 1,
  "generation_id": "gen_1",
  "resource_id": "res_1",
  "section_id": "sec_1",
  "part_id": "part_1",
  "partId": "part_duplicate",
  "attempt_id": "att_1",
  "content": "正文"
}
''';
      expect(
        () => PartGenerationParser.parse(raw),
        throwsA(isA<PartGenerationParseException>()),
      );
    });
  });
}
