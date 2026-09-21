import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/adventure/adventure_readiness_gate.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/worldview_details.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';

import '../../helpers/phase10_fixture.dart';

AdventureConfig _configWithWorldview(String worldviewResourceId) {
  return AdventureConfig(
    name: '测试冒险',
    worldview: '测试世界观',
    worldviewSnapshot: <String, dynamic>{
      'source_id': worldviewResourceId,
      'name': '测试世界观',
      'description': '本地描述',
      'format_version': WorldviewDetails.currentFormatVersion,
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

  group('resolve', () {
    test('legacy ids are not managed and never block', () async {
      final statuses = await fixture.gate.resolve(['legacy_only_id']);
      expect(
        statuses['legacy_only_id']!.status,
        AdventureAssetGateStatus.notManaged,
      );
      expect(statuses['legacy_only_id']!.status.blocksStart, isFalse);
    });

    test('resource without any revision reports noReadyRevision', () async {
      // A tree exists but no revision has ever been captured.
      final resourceId = await fixture.treeRepository.createResourceTree(
        const ResourceTreeDraft(
          id: ResourceId('g_norev'),
          type: ResourceType.worldview,
          name: '未捕获资源',
          sections: [
            ResourceTreeSectionDraft(
              title: '第一章',
              parts: [
                ResourceTreePartDraft(title: '部件0', content: '正文'),
              ],
            ),
          ],
        ),
      );
      final statuses = await fixture.gate.resolve([resourceId.value]);
      expect(
        statuses[resourceId.value]!.status,
        AdventureAssetGateStatus.noReadyRevision,
      );
    });
  });

  group('enforceAndFreeze', () {
    test('ready resources pass and payloads are frozen from the revision',
        () async {
      final wv = await fixture.createWorldview(
          'g_wv1',
          [
            ['这个世界魔法被禁止。'],
          ],
          summary: '魔法禁地概览',
          confirmed: true,
          name: '魔法禁地');
      await fixture.coordinator.prepare(wv);
      await fixture.createCharacter('g_ch1');
      final charOutcome =
          await fixture.coordinator.prepare(const ResourceId('g_ch1'));
      expect(charOutcome.record.state, ReadinessState.ready);

      final config = _configWithWorldview(wv.value).copyWith(
        selectedCharacters: [
          AdventureSelectedCharacter(
            id: 'g_ch1',
            characterId: 'g_ch1',
            characterName: '测试角色',
            isProtagonist: true,
          ),
        ],
      );

      final frozen = await fixture.gate.enforceAndFreeze(config);

      // Bindings were written for both managed resources.
      expect(frozen.resourceBindings, hasLength(2));
      final wvBinding =
          frozen.resourceBindings.firstWhere((b) => b.resourceId == wv.value);
      final head = await fixture.latestHeadRevision(wv);
      expect(wvBinding.revisionId, isNotEmpty);
      expect(wvBinding.contentHash, head.contentHash);
      expect(wvBinding.staleAllowed, isFalse);

      // The worldview snapshot was rebuilt from the revision: the local
      // content hash is replaced by the revision hash and canon text arrives.
      expect(frozen.worldviewSnapshot!['content_hash'], head.contentHash);
      expect(
        (frozen.worldviewSnapshot!['detail_json'] as Map).toString(),
        contains('魔法'),
      );

      // The character card JSON was rebuilt from the frozen revision.
      final selected = frozen.selectedCharacters.first;
      expect(selected.characterCardJson, isNotNull);
      expect(
        selected.characterCardJson.toString(),
        contains('你好，冒险者。'),
      );
    });

    test('editing the resource later never changes a frozen config', () async {
      final wv = await fixture.createWorldview(
          'g_wv2',
          [
            ['初始世界观正文'],
          ],
          summary: '概览');
      await fixture.coordinator.prepare(wv);
      final config = _configWithWorldview(wv.value);
      final frozen = await fixture.gate.enforceAndFreeze(config);
      final snapshotBefore = frozen.worldviewSnapshot.toString();

      await fixture.editResourceBody(wv, '后续编辑的正文');

      expect(frozen.worldviewSnapshot.toString(), snapshotBefore);
    });

    test('stale resource blocks start without an explicit choice', () async {
      final wv = await fixture.createWorldview(
          'g_wv3',
          [
            ['初版正文'],
          ],
          summary: '概览');
      await fixture.coordinator.prepare(wv);
      await fixture.editResourceBody(wv, '新版本正文');
      await fixture.coordinator.refresh(wv);

      final config = _configWithWorldview(wv.value);
      expect(
        () => fixture.gate.enforceAndFreeze(config),
        throwsA(isA<AdventureReadinessGateException>()),
      );
    });

    test('stale resource passes only with an explicit staleAllowed binding',
        () async {
      final wv = await fixture.createWorldview(
          'g_wv4',
          [
            ['初版正文'],
          ],
          confirmed: true,
          summary: '概览');
      await fixture.coordinator.prepare(wv);
      await fixture.editResourceBody(wv, '新版本正文');
      await fixture.coordinator.refresh(wv);
      final stale = (await fixture.gate.resolve([wv.value]))[wv.value]!;
      expect(
        stale.status,
        AdventureAssetGateStatus.staleWithPreviousReady,
      );

      // Without the binding: blocked.
      final blocked = _configWithWorldview(wv.value);
      expect(
        () => fixture.gate.enforceAndFreeze(blocked),
        throwsA(isA<AdventureReadinessGateException>()),
      );

      // With the explicit binding to the OLD revision: allowed, and the
      // frozen payload is the OLD revision's content.
      final allowed = blocked.copyWith(
        resourceBindings: [
          AdventureResourceBinding(
            resourceId: wv.value,
            revisionId: stale.assemblyRevisionId,
            contentHash: stale.assemblyContentHash,
            staleAllowed: true,
          ),
        ],
      );
      final frozen = await fixture.gate.enforceAndFreeze(allowed);
      expect(
          frozen.worldviewSnapshot!['content_hash'], stale.assemblyContentHash);
      expect(frozen.worldviewSnapshot.toString(), contains('初版正文'));
      expect(frozen.worldviewSnapshot.toString().contains('新版本正文'), isFalse);
    });

    test('missing readiness row is lazily backfilled from the latest head',
        () async {
      final wv = await fixture.createWorldview(
          'g_wv5',
          [
            ['正文'],
          ],
          summary: '概览');
      // No prepare run at all: a latest head exists but the readiness row is
      // absent. Gate resolution must converge it without rebuilding data.
      final config = _configWithWorldview(wv.value);
      final frozen = await fixture.gate.enforceAndFreeze(config);
      expect(frozen.resourceBindings, hasLength(1));
      expect(frozen.resourceBindings.single.resourceId, wv.value);
    });

    test('old configs without resourceBindings still load (backward compat)',
        () async {
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

      // Legacy ids do not resolve to managed resources → gate passes.
      final frozen = await fixture.gate.enforceAndFreeze(config);
      expect(frozen.resourceBindings, isEmpty);
      expect(frozen.selectedCharacters.first.characterName, '旧主角');
    });
  });
}
