import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_trash.dart';

ResourceTrashEntry _entry({
  String trashId = 'trash_1',
  String nodeId = 'part_1',
  RevisionNodeKindRef nodeKind = RevisionNodeKindRef.part,
  String parentNodeId = 'sec_1',
  String deletedAt = '2026-09-17T00:00:00.000',
  String expiresAt = '2026-10-17T00:00:00.000',
  String? restoredAt,
  TrashReason reason = TrashReason.userDelete,
}) =>
    ResourceTrashEntry(
      trashId: trashId,
      resourceId: const ResourceId('res_1'),
      nodeId: nodeId,
      nodeKind: nodeKind,
      parentNodeId: parentNodeId,
      originalSortOrder: 3,
      originalStatus: NodeStatus.confirmed,
      originalTitle: '开场',
      reason: reason,
      deletedAtToken: deletedAt,
      expiresAtToken: expiresAt,
      restoredAtToken: restoredAt,
    );

void main() {
  group('RevisionNodeKindRef', () {
    test('maps each node identity to its storage kind', () {
      expect(
        RevisionNodeKindRef.of(const ResourceId('res_1')),
        RevisionNodeKindRef.resource,
      );
      expect(
        RevisionNodeKindRef.of(const SectionId('sec_1')),
        RevisionNodeKindRef.section,
      );
      expect(
        RevisionNodeKindRef.of(const PartId('part_1')),
        RevisionNodeKindRef.part,
      );
    });

    test('round-trips and rejects an unknown value instead of guessing', () {
      for (final kind in RevisionNodeKindRef.values) {
        expect(
          RevisionNodeKindRef.fromStorageValue(kind.storageValue),
          kind,
        );
      }
      expect(
        () => RevisionNodeKindRef.fromStorageValue('chapter'),
        throwsA(isA<ResourceTrashException>()),
      );
    });
  });

  group('TrashReason', () {
    test('round-trips and falls back to the user delete', () {
      for (final reason in TrashReason.values) {
        expect(TrashReason.fromStorageValue(reason.storageValue), reason);
      }
      expect(TrashReason.fromStorageValue(null), TrashReason.userDelete);
      expect(
        TrashReason.fromStorageValue('something-else'),
        TrashReason.userDelete,
      );
    });

    test('has a human label for the bin list', () {
      for (final reason in TrashReason.values) {
        expect(reason.displayLabel.trim(), isNotEmpty);
      }
    });
  });

  group('ResourceTrashEntry', () {
    test('resolves the stored node id back into a typed identity', () {
      expect(_entry().identity, const PartId('part_1'));
      expect(
        _entry(nodeId: 'sec_1', nodeKind: RevisionNodeKindRef.section).identity,
        const SectionId('sec_1'),
      );
      expect(
        _entry(nodeId: 'res_1', nodeKind: RevisionNodeKindRef.resource)
            .identity,
        const ResourceId('res_1'),
      );
    });

    test('reports whether it was already restored', () {
      expect(_entry().isRestored, isFalse);
      expect(_entry(restoredAt: '2026-09-18T00:00:00.000').isRestored, isTrue);
    });
  });

  group('TrashRestorePlacement', () {
    test('marks exactly the recreated-section case as a fallback', () {
      expect(TrashRestorePlacement.original.isFallback, isFalse);
      expect(TrashRestorePlacement.alreadyRestored.isFallback, isFalse);
      expect(
        TrashRestorePlacement.recreatedSectionUnderRoot.isFallback,
        isTrue,
        reason: 'the user must be told when content did not return home',
      );
    });

    test('every placement carries a user-facing message', () {
      for (final placement in TrashRestorePlacement.values) {
        expect(placement.displayLabel.trim(), isNotEmpty);
      }
    });
  });

  group('TrashRestoreResult', () {
    test('labels an idempotent repeat', () {
      final result = TrashRestoreResult(
        entry: _entry(restoredAt: '2026-09-18T00:00:00.000'),
        placement: TrashRestorePlacement.alreadyRestored,
        restoredNodeId: 'part_1',
      );
      expect(result.isIdempotentRepeat, isTrue);
      expect(result.userMessage.trim(), isNotEmpty);
    });

    test('carries the created section id only for a fallback', () {
      final fallback = TrashRestoreResult(
        entry: _entry(),
        placement: TrashRestorePlacement.recreatedSectionUnderRoot,
        restoredNodeId: 'part_1',
        createdSectionId: 'sec_new',
      );
      expect(fallback.createdSectionId, 'sec_new');
      expect(fallback.userMessage.trim(), isNotEmpty);
    });
  });

  group('TrashRetentionPolicy', () {
    test('computes an expiry exactly one retention period out', () {
      final from = DateTime(2026, 9, 17, 12, 0);
      final expires = TrashRetentionPolicy.expiresAt(from);
      expect(
        expires.difference(from),
        TrashRetentionPolicy.retentionPeriod,
      );
    });

    test('only expires once the deadline has passed', () {
      final now = DateTime(2026, 9, 20, 0, 0);
      expect(
        TrashRetentionPolicy.isExpired('2026-09-19T23:59:59.000', now),
        isTrue,
      );
      expect(
        TrashRetentionPolicy.isExpired('2026-09-20T00:00:00.000', now),
        isTrue,
        reason: 'the deadline is inclusive: reaching it ends the window',
      );
      expect(
        TrashRetentionPolicy.isExpired('2026-09-20T00:00:01.000', now),
        isFalse,
      );
    });

    test('refuses to guess at an unparseable deadline', () {
      expect(
        () => TrashRetentionPolicy.isExpired('not-a-date', DateTime(2026)),
        throwsA(isA<ResourceTrashException>()),
      );
    });

    test('keeps a retention window long enough to be a real undo', () {
      expect(
        TrashRetentionPolicy.retentionPeriod.inDays,
        greaterThanOrEqualTo(7),
      );
    });
  });

  group('TrashPurgeResult', () {
    test('treats an already-gone entry as a success', () {
      const result = TrashPurgeResult(
        trashId: 'trash_1',
        deletedNodeIds: <String>[],
        alreadyGone: true,
      );
      expect(result.alreadyGone, isTrue);
      expect(result.deletedNodeIds, isEmpty);
    });
  });
}
