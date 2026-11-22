import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_trash.dart';

ResourceTrashEntry _entry({
  String trashId = 'trash_1',
  String nodeId = 'res_1',
  String? restoredAt,
  TrashReason reason = TrashReason.userDelete,
}) =>
    ResourceTrashEntry(
      trashId: trashId,
      resourceId: const ResourceId('res_1'),
      nodeId: nodeId,
      nodeKind: RevisionNodeKindRef.resource,
      originalTitle: '资源',
      reason: reason,
      deletedAtToken: '2026-09-17T00:00:00.000',
      expiresAtToken: '2026-10-17T00:00:00.000',
      restoredAtToken: restoredAt,
    );

void main() {
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
  });

  group('TrashOrigin', () {
    test('round-trips its storage value', () {
      expect(TrashOrigin.tree.storageValue, 'tree');
      expect(TrashOrigin.legacy.storageValue, 'legacy');
    });

    test('reads the origin from the entry metadata', () {
      final legacy = _entry().metadata;
      expect(TrashOrigin.fromMetadata(legacy), TrashOrigin.tree);
      expect(
        TrashOrigin.fromMetadata(<String, Object?>{
          TrashOrigin.metadataOriginKey: TrashOrigin.legacy.storageValue,
          TrashOrigin.metadataSourceTableKey: 'character_cards',
          TrashOrigin.metadataSourceIdKey: '7',
        }),
        TrashOrigin.legacy,
      );
      expect(TrashOrigin.fromMetadata(const <String, Object?>{}),
          TrashOrigin.tree);
    });
  });

  group('TrashDeleteResult', () {
    test('reports a first delete and an idempotent repeat', () {
      final entry = _entry();
      final first = TrashDeleteResult(entry: entry, alreadyDeleted: false);
      expect(first.entry, same(entry));
      expect(first.alreadyDeleted, isFalse);

      final repeat = TrashDeleteResult(entry: entry, alreadyDeleted: true);
      expect(repeat.entry.trashId, 'trash_1');
      expect(repeat.alreadyDeleted, isTrue);
      expect(entry.isRestored, isFalse);
    });
  });
}
