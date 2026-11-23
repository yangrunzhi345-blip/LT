import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/adventure/adventure_setup_use_case.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_markdown_parser.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_service.dart';
import 'package:lt_dialogue/domain/setting_cards/setting_card.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/services/repositories/library_repository.dart';

import '../../helpers/setting_card_fakes.dart';

final class _EmptyLibrary implements ILibraryRepository {
  @override
  Future<List<Map<String, dynamic>>> getCharacterCards({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async =>
      const <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> getNpcCards({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async =>
      const <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> getWorldviewPresets({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async =>
      const <Map<String, dynamic>>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

SettingCard _card(
  SettingCardKind kind, {
  String name = '设定',
  String summary = '',
  String content = '',
}) =>
    SettingCard(
      id: 'c1',
      kind: kind,
      name: name,
      summary: summary,
      content: content,
      createdAt: '2026-01-01T00:00:00.000',
      updatedAt: '2026-01-01T00:00:00.000',
    );

void main() {
  late MemorySettingCardRepository cards;
  late AdventureSetupUseCase useCase;

  setUp(() {
    cards = MemorySettingCardRepository();
    useCase = AdventureSetupUseCase(_EmptyLibrary(), cards: cards);
  });

  test('worldview row description is the summary, never the document',
      () async {
    await cards.save(_card(
      SettingCardKind.worldview,
      name: '银月大陆',
      summary: '月光笼罩的大陆',
      content: '''
## 概览

模块概览正文。

## 地点与地理

- **银月城**：月光之城
''',
    ));

    final rows = await useCase.loadWorldviewPresets();

    final row = rows.single;
    expect(row['description'], '月光笼罩的大陆');
    expect(row['description'], isNot(contains('##')));
    final detail = jsonDecode(row['detail_json'] as String) as Map;
    final modules = detail['modules'] as Map;
    expect((modules['overview'] as Map)['summary'], contains('模块概览正文'));
    expect(modules['locations'], isNotNull);
  });

  test('worldview row falls back to the overview text when summary is empty',
      () async {
    await cards.save(_card(
      SettingCardKind.worldview,
      name: '银月大陆',
      content: '''
## 概览

月光下的世界。
''',
    ));

    final rows = await useCase.loadWorldviewPresets();

    expect(rows.single['description'], '月光下的世界。');
    expect(rows.single['description'], isNot(contains('##')));
  });

  test('character row resolves structured fields from the rendered document',
      () async {
    final data = <String, Object?>{
      'name': '林恩',
      'gender': '男',
      'age': '24',
      'profession': '游侠',
      'personality': '沉默但可靠。',
      'appearance': '黑发灰眼。',
      'bodyDescription': '高瘦。',
      'description': '来自北境。',
      'background': '来自北境。',
      'world_profile': <String, dynamic>{'faction': '银月城'},
      'custom_attributes': <dynamic>[
        <String, dynamic>{'name': '魔力', 'value': '25/100'},
      ],
    };
    final content = SettingCardService.renderGeneratedDocument(
      data,
      kind: SettingCardKind.character,
    );
    await cards.save(_card(
      SettingCardKind.character,
      name: '林恩',
      content: content,
    ));

    final rows = await useCase.loadCharacterCards();

    final payload =
        jsonDecode(rows.single['json_data'] as String) as Map<String, dynamic>;
    expect(payload['gender'], '男');
    expect(payload['age'], '24');
    expect(payload['profession'], '游侠');
    expect(payload['personality'], '沉默但可靠。');
    expect(payload['appearance'], '黑发灰眼。');
    expect(payload['bodyDescription'], '高瘦。');
    expect(payload['description'], '来自北境。');
    expect(payload['description'], isNot(contains('##')));
    expect((payload['world_profile'] as Map)['faction'], '银月城');
    expect(payload['custom_attributes'], isA<List>());
  });

  test('plain prose character row never carries Markdown or JSON', () async {
    await cards.save(_card(
      SettingCardKind.character,
      name: '林恩',
      content: SettingCardService.renderGeneratedDocument(
        <String, Object?>{'name': '林恩'},
        kind: SettingCardKind.character,
      ),
    ));

    final rows = await useCase.loadCharacterCards();

    final payload =
        jsonDecode(rows.single['json_data'] as String) as Map<String, dynamic>;
    // A prose-only card carries the legacy data envelope.
    final data = payload['data'] as Map<String, dynamic>;
    final description = data['description'] as String;
    expect(description, isNot(contains('##')));
    expect(description, isNot(startsWith('{')));
    expect(data['name'], '林恩');
  });

  test('the parser resolves the same payload the row carries', () async {
    const parser = SettingCardMarkdownParser();
    final card = _card(
      SettingCardKind.character,
      name: '林恩',
      content: '''
## 基础信息

- **姓名**：林恩
- **性别**：女

## 背景经历

游历四方。
''',
    );
    await cards.save(card);

    final rows = await useCase.loadCharacterCards();
    final fromRow =
        jsonDecode(rows.single['json_data'] as String) as Map<String, dynamic>;
    final fromParser = parser.resolveStructuredPayload(card);

    expect(fromRow['gender'], fromParser['gender']);
    expect(fromRow['description'], fromParser['description']);
  });
}
