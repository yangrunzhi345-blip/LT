import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_revision.dart';

RevisionNodeSnapshot _part({
  String id = 'part_1',
  String section = 'sec_1',
  String content = '正文',
  int sortOrder = 0,
  NodeStatus status = NodeStatus.draft,
}) =>
    RevisionNodeSnapshot(
      nodeId: id,
      kind: RevisionNodeKind.part,
      parentNodeId: section,
      title: '标题',
      content: content,
      contentHash: 'h_$content',
      sortOrder: sortOrder,
      status: status,
    );

RevisionNodeSnapshot _section({
  String id = 'sec_1',
  String resource = 'res_1',
  String title = '第一章',
  int sortOrder = 0,
}) =>
    RevisionNodeSnapshot(
      nodeId: id,
      kind: RevisionNodeKind.section,
      parentNodeId: resource,
      title: title,
      sortOrder: sortOrder,
    );

RevisionNodeSnapshot _resource({String id = 'res_1'}) => RevisionNodeSnapshot(
      nodeId: id,
      kind: RevisionNodeKind.resource,
      parentNodeId: '',
      title: '资源',
      sortOrder: 0,
      metadata: const <String, Object?>{'type': 'worldview'},
    );

void main() {
  group('RevisionCause', () {
    test('covers every lossy operation the phase must bound', () {
      // The set is the contract: a later phase adds a value here rather than
      // overloading an existing one.
      expect(
        RevisionCause.values.map((cause) => cause.storageValue).toSet(),
        containsAll(<String>[
          'manualSave',
          'generation',
          'regeneration',
          'compression',
          'restore',
          'migration',
          'deletion',
        ]),
      );
    });

    test('round-trips through storage and falls back safely', () {
      for (final cause in RevisionCause.values) {
        expect(
          RevisionCause.fromStorageValue(cause.storageValue),
          cause,
        );
      }
      expect(
        RevisionCause.fromStorageValue('not-a-cause'),
        RevisionCause.manualSave,
      );
      expect(RevisionCause.fromStorageValue(null), RevisionCause.manualSave);
    });

    test('every cause has a human label for the history panel', () {
      for (final cause in RevisionCause.values) {
        expect(cause.displayLabel.trim(), isNotEmpty);
      }
    });
  });

  group('ResourceRevisionMath.diff', () {
    test('reports only changed nodes, not the whole tree', () {
      final parent = <String, RevisionNodeSnapshot>{
        'res_1': _resource(),
        'sec_1': _section(),
        'part_1': _part(content: '旧正文'),
        'part_2': _part(id: 'part_2', content: '未变正文'),
      };
      final current = <String, RevisionNodeSnapshot>{
        'res_1': _resource(),
        'sec_1': _section(),
        'part_1': _part(content: '新正文'),
        'part_2': _part(id: 'part_2', content: '未变正文'),
      };

      final delta = ResourceRevisionMath.diff(parent: parent, current: current);

      expect(
        delta.map((node) => node.nodeId),
        <String>['part_1'],
        reason: 'a one-Part edit must not copy the untouched nodes',
      );
      expect(delta.single.content, '新正文');
      expect(delta.single.isRemoved, isFalse);
    });

    test('records a tombstone for a node the current state dropped', () {
      final parent = <String, RevisionNodeSnapshot>{
        'res_1': _resource(),
        'sec_1': _section(),
        'part_1': _part(content: '会被删掉'),
      };
      final current = <String, RevisionNodeSnapshot>{
        'res_1': _resource(),
        'sec_1': _section(),
      };

      final delta = ResourceRevisionMath.diff(parent: parent, current: current);

      expect(delta, hasLength(1));
      expect(delta.single.nodeId, 'part_1');
      expect(delta.single.isRemoved, isTrue);
      expect(
        delta.single.content,
        isEmpty,
        reason: 'a tombstone carries no body; restoring re-adds the node from '
            'the parent revision',
      );
    });

    test('is empty when nothing changed, so a capture is a no-op', () {
      final state = <String, RevisionNodeSnapshot>{
        'res_1': _resource(),
        'sec_1': _section(),
        'part_1': _part(),
      };
      expect(
        ResourceRevisionMath.diff(
          parent: state,
          current: Map<String, RevisionNodeSnapshot>.from(state),
        ),
        isEmpty,
      );
    });

    test('detects every persisted field, not just the body', () {
      final base = _part();
      expect(
        base.hasSameState(_part(sortOrder: 1)),
        isFalse,
        reason: 'reordering is a revision-worthy change',
      );
      expect(
        base.hasSameState(_part(status: NodeStatus.confirmed)),
        isFalse,
        reason: 'promoting canon is a revision-worthy change',
      );
      expect(
        base.hasSameState(_part(section: 'sec_2')),
        isFalse,
        reason: 'moving a Part is a revision-worthy change',
      );
      expect(base.hasSameState(_part()), isTrue);
    });

    test('orders the delta deterministically', () {
      final parent = <String, RevisionNodeSnapshot>{};
      final current = <String, RevisionNodeSnapshot>{
        'part_b': _part(id: 'part_b', sortOrder: 1),
        'part_a': _part(id: 'part_a', sortOrder: 0),
        'sec_1': _section(),
        'res_1': _resource(),
      };
      final first = ResourceRevisionMath.diff(parent: parent, current: current);
      // Same content, opposite insertion order: the delta must be identical.
      final reordered = <String, RevisionNodeSnapshot>{};
      for (final key in current.keys.toList().reversed) {
        reordered[key] = current[key]!;
      }
      final second = ResourceRevisionMath.diff(
        parent: parent,
        current: reordered,
      );
      expect(
        first.map((node) => node.nodeId).toList(),
        second.map((node) => node.nodeId).toList(),
      );
      // Resource, then section, then parts in sort order.
      expect(
        first.map((node) => node.nodeId).toList(),
        <String>['res_1', 'sec_1', 'part_a', 'part_b'],
      );
    });
  });

  group('ResourceRevisionMath.applyDelta', () {
    test('replays a delta chain back to an earlier state', () {
      final state0 = <String, RevisionNodeSnapshot>{
        'res_1': _resource(),
        'sec_1': _section(),
        'part_1': _part(content: '第一版'),
      };
      final delta1 = ResourceRevisionMath.diff(
        parent: state0,
        current: <String, RevisionNodeSnapshot>{
          'res_1': _resource(),
          'sec_1': _section(),
          'part_1': _part(content: '第二版'),
        },
      );
      final state1 = ResourceRevisionMath.applyDelta(state0, delta1);
      expect(state1['part_1']!.content, '第二版');

      final delta2 = ResourceRevisionMath.diff(
        parent: state1,
        current: <String, RevisionNodeSnapshot>{
          'res_1': _resource(),
          'sec_1': _section(),
        },
      );
      final state2 = ResourceRevisionMath.applyDelta(state1, delta2);
      expect(state2.containsKey('part_1'), isFalse);

      // Replaying forward from the root reproduces every state exactly.
      final replayed1 = ResourceRevisionMath.applyDelta(state0, delta1);
      final replayed2 = ResourceRevisionMath.applyDelta(replayed1, delta2);
      expect(replayed2.keys.toSet(), state2.keys.toSet());
    });

    test('does not mutate the state it is given', () {
      final state = <String, RevisionNodeSnapshot>{
        'res_1': _resource(),
        'part_1': _part(content: '旧'),
      };
      ResourceRevisionMath.applyDelta(state, <RevisionNodeSnapshot>[
        _part(content: '新'),
      ]);
      expect(
        state['part_1']!.content,
        '旧',
        reason: 'the input map is the caller\'s; replay must not alias it',
      );
    });

    test('re-adds a tombstoned node from its delta', () {
      final state = <String, RevisionNodeSnapshot>{'res_1': _resource()};
      final restored = ResourceRevisionMath.applyDelta(
        state,
        <RevisionNodeSnapshot>[_part(content: '恢复内容')],
      );
      expect(restored['part_1']!.content, '恢复内容');
    });
  });

  group('ResourceRevisionMath.encodeState', () {
    test('is independent of map iteration order', () {
      final a = <String, RevisionNodeSnapshot>{
        'res_1': _resource(),
        'sec_1': _section(),
        'part_1': _part(),
      };
      final b = <String, RevisionNodeSnapshot>{
        'part_1': _part(),
        'res_1': _resource(),
        'sec_1': _section(),
      };
      expect(
        ResourceRevisionMath.encodeState(a.values),
        ResourceRevisionMath.encodeState(b.values),
      );
    });

    test('changes when any persisted field changes', () {
      final base = ResourceRevisionMath.encodeState([_part()]);
      expect(
        ResourceRevisionMath.encodeState([_part(content: '别的')]),
        isNot(base),
      );
      expect(
        ResourceRevisionMath.encodeState([_part(sortOrder: 3)]),
        isNot(base),
      );
      expect(
        ResourceRevisionMath.encodeState([_part(status: NodeStatus.confirmed)]),
        isNot(base),
      );
    });
  });

  group('ResourceRevisionState', () {
    test('rebuilds the frozen tree value object', () {
      final state = ResourceRevisionState(
        revisionId: const ResourceRevisionId('rev_1'),
        contentHash: 'hash',
        nodes: <String, RevisionNodeSnapshot>{
          'res_1': _resource(),
          'sec_1': _section(),
          'part_1': _part(content: '正文'),
        },
      );

      final tree = state.toResourceTree();
      expect(tree, isNotNull);
      expect(tree!.resource.id, const ResourceId('res_1'));
      expect(tree.resource.type, ResourceType.worldview);
      expect(tree.sections.single.title, '第一章');
      expect(tree.parts.single.content, '正文');
      expect(tree.parts.single.sectionId, const SectionId('sec_1'));
      // The rebuilt tree must satisfy the frozen invariants.
      tree.validate();
    });

    test('returns null for a state with no resource root', () {
      final state = ResourceRevisionState(
        revisionId: const ResourceRevisionId('rev_1'),
        contentHash: 'hash',
        nodes: <String, RevisionNodeSnapshot>{'part_1': _part()},
      );
      expect(state.toResourceTree(), isNull);
    });

    test('counts only Part bodies as characters', () {
      final state = ResourceRevisionState(
        revisionId: const ResourceRevisionId('rev_1'),
        contentHash: 'hash',
        nodes: <String, RevisionNodeSnapshot>{
          'res_1': _resource(),
          'sec_1': _section(),
          'part_1': _part(content: '12345'),
          'part_2': _part(id: 'part_2', content: '678'),
        },
      );
      expect(state.charCount, 8);
    });
  });

  group('RevisionRetentionPolicy', () {
    test('keeps a bounded chain depth so replay cannot hang', () {
      expect(RevisionRetentionPolicy.maxChainDepth, greaterThan(0));
      expect(RevisionRetentionPolicy.defaultRetention.inDays, greaterThan(0));
    });
  });

  group('ResourceRevisionRecord / ResourceRevision', () {
    test('copyWith moves only the fields it is given', () {
      const revision = ResourceRevision(
        revisionId: ResourceRevisionId('rev_1'),
        resourceId: ResourceId('res_1'),
        kind: ResourceRevisionKind.latestHead,
        cause: RevisionCause.generation,
        isHead: true,
        createdAtToken: '2026-09-17T00:00:00.000',
        contentHash: 'h',
        nodeCount: 3,
        charCount: 120,
      );

      final demoted = revision.copyWith(isHead: false);
      expect(demoted.isHead, isFalse);
      expect(demoted.cause, RevisionCause.generation);
      expect(demoted.nodeCount, 3);
      expect(demoted.charCount, 120);
      expect(demoted.contentHash, 'h');
    });
  });
}
