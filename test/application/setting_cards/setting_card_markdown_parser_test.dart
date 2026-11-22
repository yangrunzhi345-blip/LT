import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_markdown_parser.dart';
import 'package:lt_dialogue/domain/setting_cards/setting_card.dart';

const SettingCardMarkdownParser _parser = SettingCardMarkdownParser();

SettingCard _card({
  String content = '',
  String name = '林恩',
  String summary = '',
  Map<String, Object?> metadata = const <String, Object?>{},
}) =>
    SettingCard(
      id: 'c1',
      kind: SettingCardKind.character,
      name: name,
      summary: summary,
      content: content,
      metadata: metadata,
      createdAt: '2026-01-01T00:00:00.000',
      updatedAt: '2026-01-01T00:00:00.000',
    );

void main() {
  group('parseSections', () {
    test('reads prose sections', () {
      final sections = _parser.parseSections('''
## personality

沉默但可靠。

## background

来自北境。
''');

      expect(sections['personality'], '沉默但可靠。');
      expect(sections['background'], '来自北境。');
    });

    test('decodes a fenced json section into its Map shape', () {
      final sections = _parser.parseSections('''
## world_profile

```json
{"faction": "银月城", "home_location": "北门"}
```
''');

      final profile = sections['world_profile'] as Map<String, dynamic>;
      expect(profile['faction'], '银月城');
      expect(profile['home_location'], '北门');
    });

    test('keeps a broken json fence as raw text', () {
      final sections = _parser.parseSections('''
## custom_attributes

```json
{not json}
```
''');

      expect(sections['custom_attributes'], contains('{not json}'));
    });

    test('does not treat headings inside a fence as sections', () {
      final sections = _parser.parseSections('''
## world_rules

```json
{"summary": "## not a heading"}
```
''');

      expect(sections.keys, <String>['world_rules']);
      expect(
        (sections['world_rules'] as Map<String, dynamic>)['summary'],
        '## not a heading',
      );
    });

    test('unwraps a whole-document JSON payload with a data envelope', () {
      final sections = _parser.parseSections(
        '{"data": {"name": "林恩", "personality": "冷静"}}',
      );

      expect(sections, <String, dynamic>{'name': '林恩', 'personality': '冷静'});
    });

    test('accepts a whole-document JSON payload without a data envelope', () {
      final sections = _parser.parseSections('{"name": "林恩"}');

      expect(sections['name'], '林恩');
    });

    test('falls back to description for plain text', () {
      final sections = _parser.parseSections('他是一名游侠');

      expect(sections, <String, dynamic>{'description': '他是一名游侠'});
    });

    test('returns an empty map for empty content', () {
      expect(_parser.parseSections('   '), isEmpty);
      expect(_parser.parseSections(''), isEmpty);
    });
  });

  group('resolveStructuredPayload', () {
    test('content sections override the metadata payload', () {
      final card = _card(
        content: '''
## personality

新的性格

## age

20
''',
        metadata: <String, Object?>{
          SettingCardMarkdownParser.structuredPayloadKey: <String, Object?>{
            'personality': '旧性格',
            'archetype': '游侠',
          },
        },
      );

      final payload = _parser.resolveStructuredPayload(card);

      expect(payload['personality'], '新的性格');
      expect(payload['archetype'], '游侠');
      expect(payload['age'], '20');
    });

    test('empty content sections never clear the metadata payload', () {
      final card = _card(
        content: '## personality\n\n',
        metadata: <String, Object?>{
          SettingCardMarkdownParser.structuredPayloadKey: <String, Object?>{
            'personality': '旧性格',
          },
        },
      );

      final payload = _parser.resolveStructuredPayload(card);

      expect(payload['personality'], '旧性格');
    });

    test('falls back to card name and summary', () {
      final payload = _parser.resolveStructuredPayload(
        _card(name: '林恩', summary: '北境游侠'),
      );

      expect(payload['name'], '林恩');
      expect(payload['description'], '北境游侠');
    });

    test('falls back to card content when no summary exists', () {
      final payload = _parser.resolveStructuredPayload(
        _card(
          name: '林恩',
          content: '他是一名游侠',
          metadata: <String, Object?>{
            SettingCardMarkdownParser.structuredPayloadKey: <String, Object?>{
              'name': ' '
            },
          },
        ),
      );

      expect(payload['name'], '林恩');
      expect(payload['description'], '他是一名游侠');
    });

    test('unwraps a legacy v2 data envelope from metadata', () {
      final payload = _parser.resolveStructuredPayload(
        _card(
          name: '林恩',
          metadata: <String, Object?>{
            SettingCardMarkdownParser.structuredPayloadKey: <String, Object?>{
              'spec': 'chara_card_v2',
              'data': <String, Object?>{'personality': '冷静', 'age': '20'},
            },
          },
        ),
      );

      expect(payload['personality'], '冷静');
      expect(payload['age'], '20');
      expect(payload.containsKey('data'), isFalse);
    });
  });

  group('resolveWorldviewDetail', () {
    test('uses a ## detail Map and normalizes draft to confirmed', () {
      final card = _card(
        content: '''
## detail

```json
{
  "format_version": 2,
  "mode": "detailed",
  "modules": {
    "world_rules": {"summary": "规则", "status": "draft"},
    "locations": {"summary": "银月城", "status": "archived"}
  }
}
```
''',
      );

      final detail = _parser.resolveWorldviewDetail(card);
      final modules = detail['modules'] as Map<String, dynamic>;

      expect((modules['world_rules'] as Map)['status'], 'confirmed');
      expect((modules['locations'] as Map)['status'], 'archived');
    });

    test('collects ## moduleKey sections as detailed modules', () {
      final card = _card(
        content: '''
## world_rules

魔法需要代价。

## locations

```json
[{"name": "银月城"}]
```
''',
      );

      final detail = _parser.resolveWorldviewDetail(card);
      final modules = detail['modules'] as Map<String, dynamic>;

      expect(detail['mode'], 'detailed');
      expect(detail['format_version'], 2);
      expect(
        (modules['world_rules'] as Map)['summary'],
        '魔法需要代价。',
      );
      expect((modules['world_rules'] as Map)['status'], 'confirmed');
      final locations = modules['locations'] as List;
      expect((locations.single as Map)['name'], '银月城');
      expect((locations.single as Map)['status'], 'confirmed');
    });

    test('falls back to metadata detail_json', () {
      final card = _card(
        content: '被月光笼罩的大陆。',
        metadata: <String, Object?>{
          SettingCardMarkdownParser.detailJsonKey: <String, Object?>{
            'format_version': 2,
            'mode': 'detailed',
            'modules': <String, Object?>{
              'world_rules': <String, Object?>{
                'summary': '元数据规则',
                'status': 'draft',
              },
            },
          },
        },
      );

      final detail = _parser.resolveWorldviewDetail(card);
      final modules = detail['modules'] as Map<String, dynamic>;

      expect((modules['world_rules'] as Map)['summary'], '元数据规则');
      expect((modules['world_rules'] as Map)['status'], 'confirmed');
    });

    test('decodes a detail_json persisted as text', () {
      final card = _card(
        content: '被月光笼罩的大陆。',
        metadata: <String, Object?>{
          SettingCardMarkdownParser.detailJsonKey:
              '{"format_version":2,"mode":"detailed","modules":{"world_rules":{"summary":"文本规则"}}}',
        },
      );

      final detail = _parser.resolveWorldviewDetail(card);
      final modules = detail['modules'] as Map<String, dynamic>;

      expect((modules['world_rules'] as Map)['summary'], '文本规则');
    });

    test('falls back to a simple overview for plain text', () {
      final detail = _parser.resolveWorldviewDetail(
        _card(content: '被月光笼罩的大陆。'),
      );
      final modules = detail['modules'] as Map<String, dynamic>;

      expect((modules['overview'] as Map)['summary'], '被月光笼罩的大陆。');
      expect((modules['overview'] as Map)['status'], 'confirmed');
    });

    test('never mutates the original card metadata', () {
      final metadata = <String, Object?>{
        SettingCardMarkdownParser.detailJsonKey: <String, Object?>{
          'modules': <String, Object?>{
            'world_rules': <String, Object?>{
              'summary': '元数据规则',
              'status': 'draft',
            },
          },
        },
      };
      final card = _card(content: '正文', metadata: metadata);

      final detail = _parser.resolveWorldviewDetail(card);
      final normalized =
          ((detail['modules'] as Map)['world_rules'] as Map)['status'];
      final source = (((metadata[SettingCardMarkdownParser.detailJsonKey]
          as Map)['modules'] as Map)['world_rules'] as Map)['status'];

      expect(normalized, 'confirmed');
      expect(source, 'draft');
    });

    test('content sections win over metadata detail_json', () {
      final card = _card(
        content: '## world_rules\n\n正文规则',
        metadata: <String, Object?>{
          SettingCardMarkdownParser.detailJsonKey: <String, Object?>{
            'modules': <String, Object?>{
              'world_rules': <String, Object?>{'summary': '元数据规则'},
            },
          },
        },
      );

      final detail = _parser.resolveWorldviewDetail(card);
      final modules = detail['modules'] as Map<String, dynamic>;

      expect((modules['world_rules'] as Map)['summary'], '正文规则');
    });

    test('restores modules from migrated Chinese section titles', () {
      final card = _card(content: '''
## 概览

被月光笼罩的大陆。

## 地点与地理

### 银月城

月光之城。

## 规则与边界

魔法需要月辉。
''');

      final detail = _parser.resolveWorldviewDetail(card);
      final modules = detail['modules'] as Map<String, dynamic>;

      expect(modules['overview'], isNotNull);
      expect(modules['locations'], isNotNull);
      expect(modules['world_rules'], isNotNull);
      expect(
        (modules['locations'] as Map)['summary'].toString(),
        contains('银月城'),
      );
    });

    test('keeps metadata modules that the body does not mention', () {
      final card = _card(
        content: '## world_rules\n\n正文规则',
        metadata: <String, Object?>{
          SettingCardMarkdownParser.detailJsonKey: <String, Object?>{
            'modules': <String, Object?>{
              'locations': <String, Object?>{
                'summary': '元数据地点',
                'status': 'draft',
              },
            },
          },
        },
      );

      final detail = _parser.resolveWorldviewDetail(card);
      final modules = detail['modules'] as Map<String, dynamic>;

      expect((modules['world_rules'] as Map)['summary'], '正文规则');
      expect((modules['locations'] as Map)['summary'], '元数据地点');
      expect((modules['locations'] as Map)['status'], 'confirmed');
    });
  });

  group('fence handling', () {
    test('a one-line fence does not swallow the following sections', () {
      final sections = _parser.parseSections('''
## world_profile
\u0060\u0060\u0060json {"faction":"北境"} \u0060\u0060\u0060
## personality

冷静。
''');

      expect(sections['personality'], '冷静。');
      expect(sections.containsKey('world_profile'), isTrue);
    });
  });
}
