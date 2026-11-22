import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/adventure/adventure_readiness_gate.dart';
import 'package:lt_dialogue/application/adventure/adventure_tracked_state_freezer.dart';
import 'package:lt_dialogue/application/adventure/opening_canon_context.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_adventure_snapshot.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_markdown_parser.dart';
import 'package:lt_dialogue/domain/setting_cards/setting_card.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:lt_dialogue/services/worldview_snapshot_service.dart';

import '../../helpers/setting_card_fakes.dart';

SettingCard _card(
  String id,
  SettingCardKind kind, {
  String name = '设定',
  String content = '正文',
  Map<String, Object?> metadata = const <String, Object?>{},
}) =>
    SettingCard(
      id: id,
      kind: kind,
      name: name,
      content: content,
      metadata: metadata,
      originWorldviewId: kind == SettingCardKind.npc ? 'w1' : '',
      createdAt: '2026-01-01T00:00:00.000',
      updatedAt: '2026-01-01T00:00:00.000',
    );

void main() {
  late MemorySettingCardRepository cards;
  late SettingCardAwareReadinessGate gate;

  setUp(() {
    cards = MemorySettingCardRepository();
    gate = SettingCardAwareReadinessGate(cards: cards);
  });

  test('card assets resolve ready without an assembly revision', () async {
    cards.cards['w1'] = _card('w1', SettingCardKind.worldview);

    final result = await gate.resolve(<String>['w1']);

    expect(result['w1']!.status, AdventureAssetGateStatus.ready);
    expect(result['w1']!.parameters['snapshot'], 'setting_card');
  });

  test('non-card asset id resolves as notManaged', () async {
    final result = await gate.resolve(<String>['missing']);

    expect(result['missing']!.status, AdventureAssetGateStatus.notManaged);
    expect(
      result['missing']!.issueCode,
      AdventureReadinessIssueCode.notManaged,
    );
  });

  test('worldview card is frozen as a single-document snapshot', () async {
    cards.cards['w1'] = _card(
      'w1',
      SettingCardKind.worldview,
      name: '银月大陆',
      content: '# 银月大陆\n\n被月光笼罩。',
    );
    final config = AdventureConfig(
      worldviewSnapshot: <String, dynamic>{'source_id': 'w1'},
    );

    final frozen = await gate.enforceAndFreeze(config);

    expect(frozen.worldviewSnapshot!['name'], '银月大陆');
    expect(frozen.worldviewSnapshot!['content'], contains('被月光笼罩'));
    expect(frozen.worldviewSnapshot!['snapshot_kind'], 'setting_card');
    expect(frozen.worldviewSnapshot!['source_id'], 'w1');
  });

  test('character card fills the selected character and protagonist name',
      () async {
    cards.cards['c1'] = _card(
      'c1',
      SettingCardKind.character,
      name: '林恩',
      content: '他是一名游侠',
    );
    final config = AdventureConfig(
      selectedCharacters: <AdventureSelectedCharacter>[
        AdventureSelectedCharacter(
          id: 'sel-1',
          characterId: 'c1',
          characterName: '旧名字',
          isProtagonist: true,
        ),
      ],
    );

    final frozen = await gate.enforceAndFreeze(config);

    final selected = frozen.selectedCharacters.single;
    expect(selected.characterName, '林恩');
    expect(selected.characterCardJson!['description'], '他是一名游侠');
    expect(frozen.name, '林恩');
  });

  test('npc card replaces the frozen npc snapshot', () async {
    cards.cards['n1'] = _card(
      'n1',
      SettingCardKind.npc,
      name: '北门守卫',
      content: '忠于银月城。',
    );
    final config = AdventureConfig(
      npcSnapshots: <AdventureNpcSnapshot>[
        AdventureNpcSnapshot(
          assetId: 'n1',
          name: '旧守卫',
          npcJson: <String, dynamic>{'old': true},
        ),
      ],
    );

    final frozen = await gate.enforceAndFreeze(config);

    final npc = frozen.npcSnapshots.single;
    expect(npc.name, '北门守卫');
    expect(npc.npcJson['content'], '忠于银月城。');
    expect(npc.npcJson.containsKey('old'), isFalse);
    expect(npc.originWorldviewId, 'w1');
  });

  test('character card restores fields, tracked state and canon entities',
      () async {
    cards.cards['c1'] = const SettingCard(
      id: 'c1',
      kind: SettingCardKind.character,
      name: '林恩',
      content: '''
## personality

沉默但可靠。

## world_profile

```json
{"faction": "银月城", "home_location": "北门"}
```

## custom_attributes

```json
[
  {
    "id": "attr-1",
    "name": "魔力",
    "value": "25/100",
    "importance": "重要参考",
    "current_value": 25,
    "max_value": 100
  }
]
```
''',
      createdAt: '2026-01-01T00:00:00.000',
      updatedAt: '2026-01-01T00:00:00.000',
    );
    final config = AdventureConfig(
      selectedCharacters: <AdventureSelectedCharacter>[
        AdventureSelectedCharacter(
          id: 'sel-1',
          characterId: 'c1',
          characterName: '旧名字',
          isProtagonist: true,
        ),
      ],
      supportingCharacters: <SupportingCharacter>[
        SupportingCharacter(id: 'c1', name: '旧名字'),
      ],
    );

    final frozen = await gate.enforceAndFreeze(config);

    final selected = frozen.selectedCharacters.single;
    expect(selected.characterCardJson!['personality'], '沉默但可靠。');
    expect(frozen.personality, '沉默但可靠。');
    expect(frozen.characterCard, isNotNull);
    expect(const AdventureTrackedStateFreezer().freeze(frozen), isNotEmpty);

    final canon = buildOpeningCanonContext(frozen);
    expect(
      canon.entities.any((entity) =>
          entity.type == CanonEntityType.organization && entity.name == '银月城'),
      isTrue,
    );
    expect(
      canon.entities.any((entity) =>
          entity.type == CanonEntityType.location && entity.name == '北门'),
      isTrue,
    );
  });

  test('worldview card restores modules and managed entries', () async {
    cards.cards['w1'] = const SettingCard(
      id: 'w1',
      kind: SettingCardKind.worldview,
      name: '银月大陆',
      content: '''
## world_rules

魔法需要代价。

## locations

```json
[{"name": "银月城", "summary": "被月光笼罩的城市"}]
```
''',
      createdAt: '2026-01-01T00:00:00.000',
      updatedAt: '2026-01-01T00:00:00.000',
    );
    final config = AdventureConfig(
      worldviewSnapshot: <String, dynamic>{'source_id': 'w1'},
    );

    final frozen = await gate.enforceAndFreeze(config);

    final snapshot = frozen.worldviewSnapshot!;
    final detail = snapshot['detail_json'] as Map<String, dynamic>;
    final modules = detail['modules'] as Map<String, dynamic>;
    expect((modules['world_rules'] as Map)['summary'], '魔法需要代价。');
    expect((modules['world_rules'] as Map)['status'], 'confirmed');
    final locations = modules['locations'] as List;
    expect((locations.single as Map)['name'], '银月城');
    expect((locations.single as Map)['status'], 'confirmed');

    final entries = WorldviewSnapshotService.buildManagedEntries(1, snapshot);
    expect(entries.length, greaterThanOrEqualTo(3));
    expect(snapshot['entries_json'], isNot('[]'));
    expect(jsonDecode(snapshot['entries_json'] as String), isNotEmpty);
  });

  test('plain-text worldview card still freezes an overview entry', () async {
    cards.cards['w1'] = const SettingCard(
      id: 'w1',
      kind: SettingCardKind.worldview,
      name: '银月大陆',
      content: '一个被月光笼罩的大陆。',
      createdAt: '2026-01-01T00:00:00.000',
      updatedAt: '2026-01-01T00:00:00.000',
    );
    final config = AdventureConfig(
      worldviewSnapshot: <String, dynamic>{'source_id': 'w1'},
    );

    final frozen = await gate.enforceAndFreeze(config);

    final entries = WorldviewSnapshotService.buildManagedEntries(
      1,
      frozen.worldviewSnapshot!,
    );
    expect(entries, isNotEmpty);
    expect(entries.first.content, contains('【世界观/概览】'));
  });

  test('a malformed detail payload degrades instead of failing the start',
      () async {
    cards.cards['w-bad'] = _card(
      'w-bad',
      SettingCardKind.worldview,
      name: '坏数据',
      content: '世界仍然可以开始。',
      metadata: <String, Object?>{
        SettingCardMarkdownParser.detailJsonKey: <String, Object?>{
          'format_version': '2',
          'modules': <String, Object?>{
            'overview': <String, Object?>{'summary': '概述'},
          },
        },
      },
    );
    final config = AdventureConfig(
      worldviewSnapshot: <String, dynamic>{'source_id': 'w-bad'},
    );

    final frozen = await gate.enforceAndFreeze(config);

    expect(frozen.worldviewSnapshot!['name'], '坏数据');
    expect(frozen.worldviewSnapshot!['detail_json'], isA<Map>());
  });

  test('migrated Chinese module titles survive freezing', () async {
    cards.cards['w-cn'] = _card(
      'w-cn',
      SettingCardKind.worldview,
      name: '银月大陆',
      content: '''
## 概览

月光大陆。

## 地点与地理

### 银月城

月光之城。

## 势力与组织

银月议会。
''',
    );
    final config = AdventureConfig(
      worldviewSnapshot: <String, dynamic>{'source_id': 'w-cn'},
    );

    final frozen = await gate.enforceAndFreeze(config);
    final detail = frozen.worldviewSnapshot!['detail_json'] as Map;
    final modules = detail['modules'] as Map;

    expect(modules['overview'], isNotNull);
    expect(modules['locations'], isNotNull);
    expect(modules['factions'], isNotNull);
    final entries = WorldviewSnapshotService.buildManagedEntries(
      1,
      frozen.worldviewSnapshot!,
    );
    expect(entries.length, greaterThan(2));
  });
}
