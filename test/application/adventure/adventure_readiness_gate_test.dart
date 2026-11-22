import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/adventure/adventure_readiness_gate.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/setting_cards/setting_card.dart';
import 'package:lt_dialogue/models/adventure_config.dart';

import '../../helpers/phase10_fixture.dart';

AdventureConfig _configWithWorldview(String worldviewId) {
  return AdventureConfig(
    name: '测试冒险',
    worldview: '测试世界观',
    worldviewSnapshot: <String, dynamic>{
      'source_id': worldviewId,
      'name': '旧世界观',
      'description': '本地描述',
      'detail_json': <String, dynamic>{},
      'content_hash': 'stale_local_hash',
    },
    selectedCharacters: [
      AdventureSelectedCharacter(
        id: 'char_1',
        characterId: 'char_1',
        characterName: '测试角色',
        isProtagonist: true,
      ),
    ],
  );
}

void main() {
  late Phase10Fixture fixture;

  setUp(() async {
    fixture = Phase10Fixture();
    await fixture.setUp(prefix: 'lt_phase10_gate_');
  });

  tearDown(() => fixture.tearDown());

  group('card readiness gate', () {
    test('legacy ids are not managed and never block', () async {
      final statuses = await fixture.gate.resolve(['legacy_only_id']);

      expect(
        statuses['legacy_only_id']!.status,
        AdventureAssetGateStatus.notManaged,
      );
      expect(statuses['legacy_only_id']!.status.blocksStart, isFalse);
      expect(
        statuses['legacy_only_id']!.issueCode,
        AdventureReadinessIssueCode.notManaged,
      );
    });

    test('a card-backed asset is ready without an assembly revision', () async {
      await fixture.putCard(
        id: 'w1',
        kind: SettingCardKind.worldview,
        name: '银月大陆',
        content: '# 银月大陆\n\n被月光笼罩。',
      );

      final statuses = await fixture.gate.resolve(['w1']);

      expect(statuses['w1']!.status, AdventureAssetGateStatus.ready);
      expect(statuses['w1']!.status.blocksStart, isFalse);
      expect(statuses['w1']!.issueCode, AdventureReadinessIssueCode.ready);
      expect(statuses['w1']!.parameters['snapshot'], 'setting_card');
      expect(statuses['w1']!.parameters['name'], '银月大陆');
    });

    test('a deleted card resolves as notManaged instead of ready', () async {
      await fixture.putCard(
        id: 'gone',
        kind: SettingCardKind.character,
        name: '已删除',
        content: '旧正文',
        deleted: true,
      );

      final statuses = await fixture.gate.resolve(['gone']);

      expect(statuses['gone']!.status, AdventureAssetGateStatus.notManaged);
    });

    test('prepare is a no-op that reports a ready record', () async {
      final outcome = await fixture.gate.prepare('anything');

      expect(outcome.record.state, ReadinessState.ready);
      expect(outcome.record.resourceId, 'anything');
    });

    test('resolveConfig reads the ids the adventure actually references',
        () async {
      await fixture.putCard(
        id: 'w-cfg',
        kind: SettingCardKind.worldview,
        name: '世界观',
        content: '正文',
      );
      await fixture.putCard(
        id: 'c-cfg',
        kind: SettingCardKind.character,
        name: '角色',
        content: '角色正文',
      );
      final config = _configWithWorldview('w-cfg').copyWith(
        selectedCharacters: [
          AdventureSelectedCharacter(
            id: 'c-cfg',
            characterId: 'c-cfg',
            characterName: '角色',
            isProtagonist: true,
          ),
        ],
        npcSnapshots: [
          AdventureNpcSnapshot(
            assetId: 'n-missing',
            name: '无名',
            npcJson: const <String, dynamic>{},
          ),
        ],
      );

      final statuses = await fixture.gate.resolveConfig(config);

      expect(statuses['w-cfg']!.status, AdventureAssetGateStatus.ready);
      expect(statuses['c-cfg']!.status, AdventureAssetGateStatus.ready);
      expect(
        statuses['n-missing']!.status,
        AdventureAssetGateStatus.notManaged,
      );
    });
  });

  group('enforceAndFreeze', () {
    test('freezes the worldview from the card, not the stale local snapshot',
        () async {
      await fixture.putCard(
        id: 'g_wv1',
        kind: SettingCardKind.worldview,
        name: '魔法禁地',
        content: '这个世界的魔法被禁止。',
        summary: '魔法禁地概览',
      );

      final frozen = await fixture.gate.enforceAndFreeze(
        _configWithWorldview('g_wv1'),
      );

      expect(frozen.worldviewSnapshot!['name'], '魔法禁地');
      expect(
        frozen.worldviewSnapshot.toString(),
        contains('魔法被禁止'),
      );
      expect(frozen.worldviewSnapshot!['snapshot_kind'], 'setting_card');
      expect(frozen.worldviewSnapshot!['source_id'], 'g_wv1');
      // B3 freezes through WorldviewSnapshotService, which stamps a content
      // hash so world entries stay bound to the snapshot that produced them.
      expect(
        frozen.worldviewSnapshot!['content_hash']?.toString(),
        isNotEmpty,
      );
    });

    test('character cards fill the selected character and protagonist name',
        () async {
      await fixture.putCard(
        id: 'g_ch1',
        kind: SettingCardKind.character,
        name: '林恩',
        content: '他是一名游侠。',
      );
      final config = AdventureConfig(
        name: '旧名字',
        selectedCharacters: [
          AdventureSelectedCharacter(
            id: 'g_ch1',
            characterId: 'g_ch1',
            characterName: '旧名字',
            isProtagonist: true,
          ),
        ],
      );

      final frozen = await fixture.gate.enforceAndFreeze(config);

      final selected = frozen.selectedCharacters.single;
      expect(selected.characterName, '林恩');
      expect(selected.characterCardJson!['description'], '他是一名游侠。');
      expect(frozen.name, '林恩');
    });

    test('npc cards replace the frozen npc snapshot and supporting name',
        () async {
      await fixture.putCard(
        id: 'g_npc1',
        kind: SettingCardKind.npc,
        name: '北门守卫',
        content: '忠于银月城。',
        originWorldviewId: 'g_wv1',
      );
      final config = AdventureConfig(
        npcSnapshots: [
          AdventureNpcSnapshot(
            assetId: 'g_npc1',
            name: '旧守卫',
            npcJson: {'old': true},
          ),
        ],
      );

      final frozen = await fixture.gate.enforceAndFreeze(config);

      final npc = frozen.npcSnapshots.single;
      expect(npc.name, '北门守卫');
      expect(npc.npcJson['content'], '忠于银月城。');
      expect(npc.npcJson.containsKey('old'), isFalse);
      expect(npc.originWorldviewId, 'g_wv1');
    });

    test('editing a card later never changes an already frozen config',
        () async {
      final card = await fixture.putCard(
        id: 'g_wv2',
        kind: SettingCardKind.worldview,
        name: '初始',
        content: '初始世界观正文',
      );
      final frozen = await fixture.gate.enforceAndFreeze(
        _configWithWorldview(card.id),
      );
      final snapshotBefore = jsonEncode(frozen.worldviewSnapshot);

      await fixture.putCard(
        id: 'g_wv2',
        kind: SettingCardKind.worldview,
        name: '已修改',
        content: '后续编辑的正文',
      );

      expect(jsonEncode(frozen.worldviewSnapshot), snapshotBefore);
      expect(frozen.worldviewSnapshot.toString(), contains('初始世界观正文'));
      expect(frozen.worldviewSnapshot.toString(), isNot(contains('后续编辑')));
    });

    test('legacy-only configs pass through untouched', () async {
      final legacyJson = <String, dynamic>{
        'worldview': '旧冒险',
        'name': '旧冒险',
        'selectedCharacters': <Map<String, dynamic>>[
          {
            'id': 'legacy_protagonist',
            'characterId': 'legacy_protagonist',
            'characterName': '旧主角',
            'isProtagonist': true,
          },
        ],
      };
      final config = AdventureConfig.fromJson(legacyJson);
      expect(config.resourceBindings, isEmpty);

      final frozen = await fixture.gate.enforceAndFreeze(config);

      expect(frozen.resourceBindings, isEmpty);
      expect(frozen.selectedCharacters.single.characterName, '旧主角');
      expect(frozen.name, '旧冒险');
    });
  });
}
