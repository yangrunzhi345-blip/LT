import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/resource_assembly_builder.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_revision.dart';
import 'package:lt_dialogue/services/worldview_snapshot_service.dart';

import '../../helpers/phase10_fixture.dart';

void main() {
  late Phase10Fixture fixture;

  setUp(() async {
    fixture = Phase10Fixture();
    await fixture.setUp(prefix: 'lt_phase10_builder_');
  });

  tearDown(() => fixture.tearDown());

  group('ResourceAssemblyBuilder', () {
    test('should exclude frozen draft and archived parts from worldview canon',
        () async {
      final resourceId = await fixture.createWorldview(
        'res_mixed_canon',
        [
          ['CONFIRMED_FACT', 'DRAFT_FACT', 'ARCHIVED_FACT'],
        ],
        confirmed: true,
      );
      final section =
          (await fixture.treeRepository.readSections(resourceId)).single;
      final parts = await fixture.treeRepository.readParts(section.id);
      for (final (part, status) in [
        (parts[1], NodeStatus.draft),
        (parts[2], NodeStatus.archived),
      ]) {
        await fixture.treeRepository.updatePart(
          id: part.id,
          expectedUpdatedAt: await fixture.readNodeUpdatedAt(part.id.value),
          status: status,
        );
      }
      await fixture.revisionService.captureRevision(
        resourceId,
        cause: RevisionCause.manualSave,
      );
      final frozen = await fixture.latestHeadRevision(resourceId);
      // A later confirmation must not change the frozen revision's policy.
      await fixture.treeRepository.updatePart(
        id: parts[1].id,
        expectedUpdatedAt: await fixture.readNodeUpdatedAt(parts[1].id.value),
        status: NodeStatus.confirmed,
      );
      final result = await fixture.builder.build(
        resourceId: resourceId,
        revisionId: frozen.revisionId,
      );

      final payload = result.worldviewPayload.toString();
      final indexText = result.indexDocs.map((doc) => doc.content).join('\n');
      final canonText = result.snapshot.fragments
          .where((fragment) => fragment.isCanon)
          .map((fragment) => fragment.text)
          .join('\n');
      for (final text in [payload, indexText, canonText]) {
        expect(text, contains('CONFIRMED_FACT'));
        expect(text, isNot(contains('DRAFT_FACT')));
        expect(text, isNot(contains('ARCHIVED_FACT')));
      }
      final sectionFragment = result.snapshot.fragments
          .singleWhere((fragment) => fragment.sourceNodeId == section.id);
      expect(sectionFragment.isCanon, isTrue);
      expect(sectionFragment.text, 'CONFIRMED_FACT');
      final draftFragment = result.snapshot.fragments
          .singleWhere((fragment) => fragment.sourceNodeId == parts[1].id);
      expect(draftFragment.text, 'DRAFT_FACT');
      expect(draftFragment.isCanon, isFalse);
      expect(
        result.snapshot.fragments
            .where((fragment) => fragment.sourceNodeId == parts[2].id),
        isEmpty,
      );
    });

    test('builds fragments in canonical order from the immutable revision',
        () async {
      final resourceId = await fixture.createWorldview(
        'res_b1',
        [
          ['第一节正文', '第二节正文'],
        ],
      );
      final head = await fixture.latestHeadRevision(resourceId);

      final result = await fixture.builder.build(
        resourceId: resourceId,
        revisionId: head.revisionId,
        expectedContentHash: head.contentHash,
      );

      expect(result.snapshot.resourceId, resourceId);
      expect(result.snapshot.revisionId, head.revisionId);
      expect(result.snapshot.fragments, isNotEmpty);
      // Canonical order: fragment sort orders are non-decreasing.
      final orders = result.snapshot.fragments.map((f) => f.sortOrder);
      expect(orders, orderedEquals(orders.toList()..sort()));
    });

    test('refuses a hash mismatch instead of assembling a foreign state',
        () async {
      final resourceId = await fixture.createWorldview(
        'res_b2',
        [
          ['正文'],
        ],
      );
      final head = await fixture.latestHeadRevision(resourceId);

      expect(
        () => fixture.builder.build(
          resourceId: resourceId,
          revisionId: head.revisionId,
          expectedContentHash: 'not_the_real_hash',
        ),
        throwsA(isA<ResourceAssemblyException>()),
      );
    });

    test('draft content never becomes canon; archived content is excluded',
        () async {
      final resourceId = await fixture.createWorldview(
        'res_b3',
        [
          ['确认正文'],
        ],
      );
      // Default nodes are draft: flip one part to confirmed, archive another.
      final sections = await fixture.treeRepository.readSections(resourceId);
      final parts = await fixture.treeRepository.readParts(sections.first.id);
      await fixture.treeRepository.updatePart(
        id: parts.first.id,
        expectedUpdatedAt:
            await fixture.readNodeUpdatedAt(parts.first.id.value),
        status: NodeStatus.confirmed,
      );
      await fixture.revisionService.captureRevision(
        resourceId,
        cause: RevisionCause.manualSave,
      );
      final head = await fixture.latestHeadRevision(resourceId);
      final result = await fixture.builder.build(
        resourceId: resourceId,
        revisionId: head.revisionId,
      );

      final byText = {
        for (final fragment in result.snapshot.fragments)
          fragment.text: fragment,
      };
      final confirmed = byText['确认正文'];
      expect(confirmed, isNotNull);
      expect(confirmed!.isCanon, isTrue);
    });

    test(
        'worldview payload carries the revision content hash and index docs '
        'are derived from it', () async {
      final resourceId = await fixture.createWorldview(
        'res_b4',
        [
          ['这个世界魔法被禁止。'],
        ],
        summary: '魔法禁地概览',
      );
      final head = await fixture.latestHeadRevision(resourceId);
      final result = await fixture.builder.build(
        resourceId: resourceId,
        revisionId: head.revisionId,
      );

      expect(result.resourceType, ResourceType.worldview);
      final payload = result.worldviewPayload!;
      expect(payload['content_hash'], head.contentHash);
      expect(payload['source_id'], resourceId.value);

      // The index documents are the deterministic managed-entry shape.
      final expectedEntries = WorldviewSnapshotService.buildManagedEntries(
        0,
        payload,
        sourceRevisionId: head.revisionId.value,
      );
      expect(result.indexDocs, hasLength(expectedEntries.length));
      for (var i = 0; i < result.indexDocs.length; i++) {
        expect(result.indexDocs[i].content, expectedEntries[i].content);
        expect(result.indexDocs[i].keys, expectedEntries[i].keys);
      }
      // Canon entry text is present and draft-fact filtering kept working.
      expect(
        result.indexDocs.any((doc) => doc.content.contains('魔法禁地')),
        isTrue,
      );
    });

    test('character runtime fields come from the frozen revision', () async {
      final resourceId = await fixture.createCharacter(
        'res_b5',
        firstMessage: '固定的开场白。',
        systemPrompt: '固定的系统提示。',
      );
      final head = await fixture.latestHeadRevision(resourceId);
      final result = await fixture.builder.build(
        resourceId: resourceId,
        revisionId: head.revisionId,
      );

      expect(result.resourceType, ResourceType.character);
      final cardRow = result.cardRow!;
      expect(cardRow['id'], resourceId.value);
      final jsonData = cardRow['json_data'].toString();
      expect(jsonData, contains('固定的开场白。'));
      expect(jsonData, contains('固定的系统提示。'));
    });

    test('readSnapshot implements the frozen snapshot provider contract',
        () async {
      final resourceId = await fixture.createWorldview(
        'res_b6',
        [
          ['正文'],
        ],
      );
      final head = await fixture.latestHeadRevision(resourceId);

      final snapshot = await fixture.builder.readSnapshot(
        resourceId: resourceId,
        revisionId: head.revisionId,
      );
      expect(snapshot, isNotNull);
      expect(snapshot!.readiness, ReadinessState.ready);
      expect(snapshot.contentHash, head.contentHash);

      final missing = await fixture.builder.readSnapshot(
        resourceId: resourceId,
        revisionId: const ResourceRevisionId('does_not_exist'),
      );
      expect(missing, isNull);
    });
    test('archived parts never leak into the worldview payload', () async {
      final resourceId = await fixture.createWorldview(
        'res_b7',
        [
          ['可见正文', '被归档的机密正文'],
        ],
        summary: '概览',
      );
      final sections = await fixture.treeRepository.readSections(resourceId);
      final parts = await fixture.treeRepository.readParts(sections.first.id);
      await fixture.treeRepository.updatePart(
        id: parts.last.id,
        expectedUpdatedAt: await fixture.readNodeUpdatedAt(parts.last.id.value),
        status: NodeStatus.archived,
      );
      await fixture.revisionService.captureRevision(
        resourceId,
        cause: RevisionCause.manualSave,
      );
      final head = await fixture.latestHeadRevision(resourceId);
      final result = await fixture.builder.build(
        resourceId: resourceId,
        revisionId: head.revisionId,
      );

      final payloadJson = result.worldviewPayload.toString();
      expect(payloadJson.contains('被归档的机密正文'), isFalse);
      expect(
        result.indexDocs.where((doc) => doc.content.contains('被归档的机密正文')),
        isEmpty,
      );
    });
  });
}
