import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_markdown_parser.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_tracked_state_bridge.dart';
import 'package:lt_dialogue/domain/setting_cards/setting_card.dart';
import 'package:lt_dialogue/models/custom_attribute_item.dart';
import 'package:lt_dialogue/models/tracked_state_definition.dart';

import '../../helpers/setting_card_fakes.dart';

TrackedStateDefinition _definition(String id, String name) =>
    TrackedStateDefinition(
      id: id,
      name: name,
      importance: CustomAttributeImportance.critical,
      minimum: 0,
      maximum: 100,
    );

SettingCard _card({
  required String id,
  required SettingCardKind kind,
  String name = '卡片',
  String summary = '',
  String content = '',
  Map<String, Object?> metadata = const <String, Object?>{},
}) =>
    SettingCard(
      id: id,
      kind: kind,
      name: name,
      summary: summary,
      content: content,
      mode: 'adventure',
      metadata: metadata,
      createdAt: '2026-01-01T00:00:00.000',
      updatedAt: '2026-01-01T00:00:00.000',
    );

String _trackedSection(List<TrackedStateDefinition> definitions) {
  final json = const JsonEncoder.withIndent('  ')
      .convert(definitions.map((d) => d.toJson()).toList());
  return '## tracked_state_definitions\n\n```json\n$json\n```';
}

void main() {
  late MemorySettingCardRepository repository;
  late SettingCardTrackedStateBridge bridge;

  setUp(() {
    repository = MemorySettingCardRepository();
    bridge = SettingCardTrackedStateBridge(repository: repository);
  });

  test('reads definitions from a plain-text card body section', () async {
    await repository.save(_card(
      id: 'sc_a',
      kind: SettingCardKind.character,
      content: '# 艾莉丝\n\n## overview\n游侠\n\n'
          '${_trackedSection([_definition('curse', '诅咒侵蚀')])}',
    ));

    final definitions = await bridge.read('sc_a');

    expect(definitions, hasLength(1));
    expect(definitions.single.id, 'curse');
    expect(definitions.single.name, '诅咒侵蚀');
  });

  test('reads definitions from a migrated whole-document JSON card', () async {
    await repository.save(_card(
      id: 'sc_legacy',
      kind: SettingCardKind.npc,
      content: jsonEncode({
        'spec': 'character_card',
        'spec_version': 2,
        'data': {
          'name': '守卫',
          'tracked_state_definitions': [
            _definition('alertness', '警戒').toJson()
          ],
        },
      }),
    ));

    final definitions = await bridge.read('sc_legacy');

    expect(definitions.map((d) => d.id), ['alertness']);
  });

  test('reads a worldview card from detail_json metadata', () async {
    await repository.save(_card(
      id: 'sc_world',
      kind: SettingCardKind.worldview,
      content: '一片动荡的大陆',
      metadata: {
        'detail_json': {
          'format_version': 1,
          'mode': 'detailed',
          'modules': {
            'overview': {'summary': '动荡', 'status': 'confirmed'},
          },
          'tracked_state_definitions': [_definition('war', '战争紧张度').toJson()],
        },
      },
    ));

    final definitions = await bridge.read('sc_world');

    expect(definitions.map((d) => d.id), ['war']);
  });

  test('returns no definitions for a missing card', () async {
    expect(await bridge.read('missing'), isEmpty);
    expect(
      await bridge.write('missing', [_definition('x', 'x')]),
      isNull,
    );
  });

  test('write then read round-trips while other sections survive', () async {
    await repository.save(_card(
      id: 'sc_a',
      kind: SettingCardKind.character,
      name: '艾莉丝',
      summary: '游侠',
      content: '# 艾莉丝\n\n## overview\n游侠\n\n## personality\n沉默',
      metadata: {
        'structured_payload': {
          'name': '艾莉丝',
          'profession': '游侠',
        },
      },
    ));

    final saved = await bridge.write('sc_a', [
      _definition('curse', '诅咒侵蚀'),
      _definition('sanity', '理智'),
    ]);

    expect(saved, isNotNull);
    expect(saved!.name, '艾莉丝');
    expect(saved.summary, '游侠');
    expect(saved.content, contains('## overview'));
    expect(saved.content, contains('沉默'));
    expect(saved.content, contains('## tracked_state_definitions'));

    final payload = saved.metadata['structured_payload'] as Map;
    expect(payload['profession'], '游侠');
    expect(
      (payload['tracked_state_definitions'] as List).length,
      2,
    );

    final reread = await bridge.read('sc_a');
    expect(reread.map((d) => d.id), ['curse', 'sanity']);
  });

  test('write replaces an existing definitions section instead of appending',
      () async {
    await repository.save(_card(
      id: 'sc_a',
      kind: SettingCardKind.character,
      content: '## overview\n游侠\n\n'
          '${_trackedSection([_definition('old', '旧定义')])}\n\n'
          '## personality\n沉默',
    ));

    final saved = await bridge.write('sc_a', [_definition('new', '新定义')]);

    expect(saved, isNotNull);
    final content = saved!.content;
    final occurrences =
        '## tracked_state_definitions'.allMatches(content).length;
    expect(occurrences, 1);
    expect(content, contains('沉默'));
    expect(content, isNot(contains('旧定义')));
    expect((await bridge.read('sc_a')).map((d) => d.id), ['new']);
  });

  test('write syncs worldview detail_json and keeps its modules', () async {
    await repository.save(_card(
      id: 'sc_world',
      kind: SettingCardKind.worldview,
      content: '普通正文',
      metadata: {
        'detail_json': {
          'modules': {
            'world_rules': {'summary': '魔法有限', 'status': 'confirmed'},
          },
        },
      },
    ));

    final saved = await bridge.write('sc_world', [_definition('war', '战争')]);

    expect(saved, isNotNull);
    final detail = saved!.metadata['detail_json'] as Map;
    expect(detail['modules'], isA<Map>());
    expect(
      ((detail['modules'] as Map)['world_rules'] as Map)['summary'],
      '魔法有限',
    );
    expect((detail['tracked_state_definitions'] as List).length, 1);
    expect((await bridge.read('sc_world')).map((d) => d.id), ['war']);
    // A worldview keeps its payload in detail_json; structured_payload belongs
    // to character/NPC cards only.
    expect(saved.metadata.containsKey('structured_payload'), isFalse);
  });

  test('write to a plain-text card keeps the prose and only updates metadata',
      () async {
    const body = '一个没有标题的角色正文。';
    await repository.save(_card(
      id: 'sc_plain',
      kind: SettingCardKind.character,
      content: body,
    ));

    final saved = await bridge.write('sc_plain', [_definition('mood', '心情')]);

    expect(saved, isNotNull);
    expect(saved!.content, body);
    expect(
      (saved.metadata['structured_payload']
          as Map)[SettingCardTrackedStateBridge.trackedStateKey],
      isA<List>(),
    );
    final payload = const SettingCardMarkdownParser().resolveStructuredPayload(
      saved,
    );
    expect(payload['description'], body);
    expect((await bridge.read('sc_plain')).map((d) => d.id), ['mood']);
  });

  test('write to a whole-document JSON card preserves its structured fields',
      () async {
    final document = jsonEncode({
      'spec': 'character_card_v2',
      'data': {
        'name': '守卫',
        'personality': '谨慎',
        'profession': '哨兵',
      },
    });
    await repository.save(_card(
      id: 'sc_json',
      kind: SettingCardKind.npc,
      content: document,
    ));

    final saved = await bridge.write('sc_json', [_definition('duty', '职责')]);

    expect(saved, isNotNull);
    expect(saved!.content, document);
    final payload = const SettingCardMarkdownParser().resolveStructuredPayload(
      saved,
    );
    expect(payload['personality'], '谨慎');
    expect(payload['profession'], '哨兵');
    expect((await bridge.read('sc_json')).map((d) => d.id), ['duty']);
  });
}
