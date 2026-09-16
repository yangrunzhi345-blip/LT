import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/core/config/generation_limits.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_limits.dart';
import 'package:lt_dialogue/models/resource_provenance.dart';

/// Phase 0 freezes the semantics every later phase must implement. These tests
/// are the executable half of ADR-0001; changing a meaning here means
/// re-reviewing Phase 0, not editing the expectation.
void main() {
  group('ResourceType', () {
    test('exposes the three frozen values and stable storage strings', () {
      expect(
        ResourceType.values.map((type) => type.storageValue),
        ['worldview', 'character', 'npc'],
      );
    });

    test('round-trips storage values and rejects unknown input', () {
      for (final type in ResourceType.values) {
        expect(ResourceType.fromStorageValue(type.storageValue), type);
      }
      expect(
        () => ResourceType.fromStorageValue('world'),
        throwsA(isA<ResourceContractException>()),
      );
      expect(
        () => ResourceType.fromStorageValue(null),
        throwsA(isA<ResourceContractException>()),
      );
    });
  });

  group('CreationMethod', () {
    test('does not drift from the existing authoring method vocabulary', () {
      expect(
        CreationMethod.values.map((method) => method.storageValue),
        ResourceAuthoringMethod.values.map((method) => method.name),
      );
    });
  });

  group('NodeId', () {
    test('compares by kind and value, not by identity', () {
      expect(const ResourceId('a'), const ResourceId('a'));
      expect(const ResourceId('a').hashCode, const ResourceId('a').hashCode);
      expect(const ResourceId('a'), isNot(const ResourceId('b')));
      // The same string in two levels is a different identity.
      expect(const ResourceId('a'), isNot(const SectionId('a')));
      expect(const SectionId('a'), isNot(const PartId('a')));
    });

    test('rejects an empty id and reports its kind', () {
      expect(() => ResourceId(''), throwsA(isA<AssertionError>()));
      expect(() => SectionId(''), throwsA(isA<AssertionError>()));
      expect(() => PartId(''), throwsA(isA<AssertionError>()));
      expect(const PartId('p1').toString(), 'part(p1)');
    });
  });

  group('Resource tree invariants', () {
    const resource = Resource(
      id: ResourceId('rw'),
      type: ResourceType.worldview,
      name: 'World',
    );
    const otherResource = Resource(
      id: ResourceId('other'),
      type: ResourceType.character,
      name: 'Other',
    );

    ResourceTree treeOf({
      List<ResourceSection> sections = const [],
      List<ResourcePart> parts = const [],
    }) =>
        ResourceTree(resource: resource, sections: sections, parts: parts);

    test('accepts a well formed tree', () {
      final tree = treeOf(
        sections: [
          ResourceSection(
            id: const SectionId('s1'),
            resourceId: resource.id,
            title: 'Overview',
            sortOrder: 0,
          ),
        ],
        parts: [
          const ResourcePart(
            id: PartId('p1'),
            sectionId: SectionId('s1'),
            title: 'Intro',
            content: 'body',
            sortOrder: 0,
          ),
        ],
      );

      expect(tree.validate, returnsNormally);
    });

    test('a section must belong directly to its resource', () {
      final tree = treeOf(
        sections: [
          ResourceSection(
            id: const SectionId('s1'),
            resourceId: otherResource.id,
            title: 'Stray',
            sortOrder: 0,
          ),
        ],
      );

      expect(
        tree.validate,
        throwsA(isA<ResourceContractException>()),
      );
    });

    test('a part must belong directly to a known section', () {
      final tree = treeOf(
        parts: [
          const ResourcePart(
            id: PartId('p1'),
            sectionId: SectionId('missing'),
            title: 'Orphan',
            content: 'body',
            sortOrder: 0,
          ),
        ],
      );

      expect(
        tree.validate,
        throwsA(isA<ResourceContractException>()),
      );
    });

    test('rejects duplicate node ids', () {
      final duplicatedSections = treeOf(
        sections: [
          ResourceSection(
            id: const SectionId('s1'),
            resourceId: resource.id,
            title: 'A',
            sortOrder: 0,
          ),
          ResourceSection(
            id: const SectionId('s1'),
            resourceId: resource.id,
            title: 'B',
            sortOrder: 1,
          ),
        ],
      );
      expect(
        duplicatedSections.validate,
        throwsA(isA<ResourceContractException>()),
      );

      final duplicatedParts = treeOf(
        sections: [
          ResourceSection(
            id: const SectionId('s1'),
            resourceId: resource.id,
            title: 'A',
            sortOrder: 0,
          ),
        ],
        parts: [
          const ResourcePart(
            id: PartId('p1'),
            sectionId: SectionId('s1'),
            title: 'A',
            content: '',
            sortOrder: 0,
          ),
          const ResourcePart(
            id: PartId('p1'),
            sectionId: SectionId('s1'),
            title: 'B',
            content: '',
            sortOrder: 1,
          ),
        ],
      );
      expect(
        duplicatedParts.validate,
        throwsA(isA<ResourceContractException>()),
      );
    });

    test('orders siblings by sortOrder then id, even when orders tie', () {
      final tree = treeOf(
        sections: [
          ResourceSection(
            id: const SectionId('s-b'),
            resourceId: resource.id,
            title: 'B',
            sortOrder: 1,
          ),
          ResourceSection(
            id: const SectionId('s-a'),
            resourceId: resource.id,
            title: 'A',
            sortOrder: 1,
          ),
          ResourceSection(
            id: const SectionId('s-first'),
            resourceId: resource.id,
            title: 'First',
            sortOrder: 0,
          ),
        ],
      );

      expect(
        tree.orderedSections.map((section) => section.id),
        [
          const SectionId('s-first'),
          const SectionId('s-a'),
          const SectionId('s-b')
        ],
      );
    });

    test('returns the ordered parts of one section only', () {
      final tree = treeOf(
        sections: [
          ResourceSection(
            id: const SectionId('s1'),
            resourceId: resource.id,
            title: 'A',
            sortOrder: 0,
          ),
          ResourceSection(
            id: const SectionId('s2'),
            resourceId: resource.id,
            title: 'B',
            sortOrder: 1,
          ),
        ],
        parts: [
          const ResourcePart(
            id: PartId('p2'),
            sectionId: SectionId('s1'),
            title: 'second',
            content: '',
            sortOrder: 1,
          ),
          const ResourcePart(
            id: PartId('p1'),
            sectionId: SectionId('s1'),
            title: 'first',
            content: '',
            sortOrder: 0,
          ),
          const ResourcePart(
            id: PartId('p-other'),
            sectionId: SectionId('s2'),
            title: 'elsewhere',
            content: '',
            sortOrder: 0,
          ),
        ],
      );

      expect(
        tree.orderedPartsOf(const SectionId('s1')).map((part) => part.id),
        [const PartId('p1'), const PartId('p2')],
      );
    });

    test('node identity is immutable: copyWith never rewrites an id', () {
      final section = ResourceSection(
        id: const SectionId('s1'),
        resourceId: resource.id,
        title: 'Before',
        sortOrder: 0,
      );
      final renamed = section.copyWith(title: 'After', sortOrder: 4);
      expect(renamed.id, section.id);
      expect(renamed.resourceId, resource.id);
      expect(renamed.title, 'After');
      expect(section.title, 'Before');

      const part = ResourcePart(
        id: PartId('p1'),
        sectionId: SectionId('s1'),
        title: 'Before',
        content: 'a',
        sortOrder: 0,
      );
      final edited = part.copyWith(content: 'b', contentHash: 'h');
      expect(edited.id, part.id);
      expect(edited.sectionId, part.sectionId);
      expect(edited.content, 'b');
      expect(part.content, 'a');
    });
  });

  group('Node-scoped mount patches', () {
    const resourceId = ResourceId('rw');
    const sectionId = SectionId('s1');
    const partId = PartId('p1');

    test('every patch targets exactly one node', () {
      final patches = <ResourceNodePatch>[
        const AppendSectionPatch(resourceId: resourceId, title: 'S'),
        const AppendPartPatch(
            sectionId: sectionId, title: 'P', content: 'body'),
        const UpdatePartContentPatch(partId: partId, content: 'body'),
        const RenameNodePatch(nodeId: partId, title: 'Renamed'),
        const ReorderNodePatch(nodeId: partId, sortOrder: 2),
        const ArchiveNodePatch(nodeId: partId),
      ];

      expect(patches, hasLength(6));
      expect(
        patches.map((patch) => patch.targetNodeId),
        [resourceId, sectionId, partId, partId, partId, partId],
      );
    });

    test('appends are scoped to the parent, updates to the node itself', () {
      expect(
        const AppendSectionPatch(resourceId: resourceId, title: 'S')
            .targetNodeId,
        resourceId,
      );
      expect(
        const AppendPartPatch(sectionId: sectionId, title: 'P').targetNodeId,
        sectionId,
      );
      expect(
        const UpdatePartContentPatch(partId: partId, content: 'x').targetNodeId,
        partId,
      );
      expect(
        const ReorderNodePatch(nodeId: sectionId, sortOrder: 1).targetNodeId,
        sectionId,
      );
    });

    test('rejects a negative sibling position', () {
      expect(
        () => ReorderNodePatch(nodeId: partId, sortOrder: -1),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => ResourceSection(
          id: sectionId,
          resourceId: resourceId,
          title: 'S',
          sortOrder: -1,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('GenerationStatus transitions', () {
    test('follows the frozen table and rejects every other edge', () {
      _expectStateMachine<GenerationStatus>(
        domain: 'generation',
        values: GenerationStatus.values,
        table: ResourceStateMachines.generation,
        canTransition: ResourceStateMachines.canTransitionGeneration,
        advance: ResourceStateMachines.advanceGeneration,
      );
    });

    test('a finished task must plan again before generating', () {
      expect(
        ResourceStateMachines.canTransitionGeneration(
          GenerationStatus.completed,
          GenerationStatus.generating,
        ),
        isFalse,
      );
      expect(
        ResourceStateMachines.canTransitionGeneration(
          GenerationStatus.idle,
          GenerationStatus.generating,
        ),
        isFalse,
      );
      expect(
        ResourceStateMachines.canTransitionGeneration(
          GenerationStatus.generating,
          GenerationStatus.planning,
        ),
        isFalse,
      );
      expect(
        ResourceStateMachines.canTransitionGeneration(
          GenerationStatus.failed,
          GenerationStatus.completed,
        ),
        isFalse,
      );
    });

    test('reports the rejected edge in the exception', () {
      try {
        ResourceStateMachines.advanceGeneration(
          GenerationStatus.idle,
          GenerationStatus.generating,
        );
        fail('illegal transition was accepted');
      } on ResourceStateTransitionException catch (error) {
        expect(error.domain, 'generation');
        expect(error.from, 'idle');
        expect(error.to, 'generating');
      }
    });
  });

  group('NodeStatus transitions', () {
    test('follows the frozen table and rejects every other edge', () {
      _expectStateMachine<NodeStatus>(
        domain: 'nodeStatus',
        values: NodeStatus.values,
        table: ResourceStateMachines.nodeStatus,
        canTransition: ResourceStateMachines.canTransitionNodeStatus,
        advance: ResourceStateMachines.advanceNodeStatus,
      );
    });

    test('archived content returns to draft, never straight to confirmed', () {
      expect(
        ResourceStateMachines.canTransitionNodeStatus(
          NodeStatus.archived,
          NodeStatus.draft,
        ),
        isTrue,
      );
      expect(
        ResourceStateMachines.canTransitionNodeStatus(
          NodeStatus.archived,
          NodeStatus.confirmed,
        ),
        isFalse,
      );
    });
  });

  group('ReadinessState transitions', () {
    test('follows the frozen table and rejects every other edge', () {
      _expectStateMachine<ReadinessState>(
        domain: 'readiness',
        values: ReadinessState.values,
        table: ResourceStateMachines.readiness,
        canTransition: ResourceStateMachines.canTransitionReadiness,
        advance: ResourceStateMachines.advanceReadiness,
      );
    });

    test('a ready revision is invalidated or rebuilt, never failed in place',
        () {
      expect(
        ResourceStateMachines.canTransitionReadiness(
          ReadinessState.ready,
          ReadinessState.failed,
        ),
        isFalse,
      );
      expect(
        ResourceStateMachines.canTransitionReadiness(
          ReadinessState.failed,
          ReadinessState.ready,
        ),
        isFalse,
      );
    });
  });

  group('Capacity policy', () {
    test('worldview boundaries are exclusive above each budget', () {
      const policy = ResourceLimits.worldview;
      expect(policy.statusFor(0), CapacityStatus.normal);
      expect(policy.statusFor(49999), CapacityStatus.normal);
      expect(policy.statusFor(50000), CapacityStatus.normal);
      expect(policy.statusFor(50001), CapacityStatus.elastic);
      expect(policy.statusFor(60000), CapacityStatus.elastic);
      expect(policy.statusFor(60001), CapacityStatus.overflow);
      expect(policy.statusFor(600000), CapacityStatus.overflow);
    });

    test('character and npc boundaries are exclusive above each budget', () {
      for (final policy in [ResourceLimits.character, ResourceLimits.npc]) {
        expect(policy.statusFor(4999), CapacityStatus.normal);
        expect(policy.statusFor(5000), CapacityStatus.normal);
        expect(policy.statusFor(5001), CapacityStatus.elastic);
        expect(policy.statusFor(6000), CapacityStatus.elastic);
        expect(policy.statusFor(6001), CapacityStatus.overflow);
      }
    });

    test('rejects a negative measurement', () {
      expect(
        () => ResourceLimits.worldview.statusFor(-1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('every resource type maps to its frozen budget', () {
      expect(ResourceLimits.policyFor(ResourceType.worldview).nominalCharacters,
          ResourceLimits.worldviewNominalCharacters);
      expect(
          ResourceLimits.policyFor(ResourceType.worldview).absoluteCharacters,
          ResourceLimits.worldviewAbsoluteCharacters);
      expect(ResourceLimits.policyFor(ResourceType.character).nominalCharacters,
          ResourceLimits.characterNominalCharacters);
      expect(
          ResourceLimits.policyFor(ResourceType.character).absoluteCharacters,
          ResourceLimits.characterAbsoluteCharacters);
      expect(ResourceLimits.policyFor(ResourceType.npc).nominalCharacters,
          ResourceLimits.characterNominalCharacters);
      expect(ResourceLimits.policyFor(ResourceType.npc).absoluteCharacters,
          ResourceLimits.characterAbsoluteCharacters);
    });

    test('rejects an inverted policy', () {
      expect(
        () => ResourceCapacityPolicy(
          nominalCharacters: 10,
          absoluteCharacters: 5,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('the legacy generation budget still agrees with the capacity source',
        () {
      // Guarded so the two can never drift silently before Phase 8/12 unify
      // them. Phase 0 deliberately does not edit the legacy config.
      expect(
        GenerationLimits.detailedWorldviewMaximumCharacters,
        ResourceLimits.worldviewNominalCharacters,
      );
      expect(
        GenerationLimits.detailedCharacterMaximumCharacters,
        ResourceLimits.characterNominalCharacters,
      );
    });
  });

  group('Revision and assembly selection', () {
    const resourceId = ResourceId('rw');
    const head = ResourceRevisionRef(
      resourceId: resourceId,
      revisionId: ResourceRevisionId('r3'),
      kind: ResourceRevisionKind.latestHead,
    );
    const assembly = ResourceRevisionRef(
      resourceId: resourceId,
      revisionId: ResourceRevisionId('r2'),
      kind: ResourceRevisionKind.assembly,
    );

    test('head and assembly revision may diverge', () {
      const selection = ResourceRevisionSelection(
        resourceId: resourceId,
        readiness: ReadinessState.ready,
        latestHead: head,
        assemblyRevision: assembly,
      );

      expect(selection.hasLatestHead, isTrue);
      expect(selection.hasAssemblyRevision, isTrue);
      expect(selection.canAssemble, isTrue);
      expect(selection.latestHead!.revisionId, isNot(assembly.revisionId));
    });

    test('runtime may not assemble without a ready published revision', () {
      const preparing = ResourceRevisionSelection(
        resourceId: resourceId,
        readiness: ReadinessState.preparing,
        latestHead: head,
        assemblyRevision: assembly,
      );
      const unpublished = ResourceRevisionSelection(
        resourceId: resourceId,
        readiness: ReadinessState.ready,
        latestHead: head,
      );

      expect(preparing.canAssemble, isFalse);
      expect(unpublished.canAssemble, isFalse);
      expect(unpublished.hasAssemblyRevision, isFalse);
    });

    test('a fresh resource may have no head yet', () {
      const selection = ResourceRevisionSelection(
        resourceId: ResourceId('rw'),
        readiness: ReadinessState.preparing,
      );
      expect(selection.hasLatestHead, isFalse);
      expect(selection.canAssemble, isFalse);
    });
  });
}

/// Walks every ordered pair of [values] and asserts the transition table, the
/// boolean probe and the throwing `advance` helper all agree.
void _expectStateMachine<T>({
  required String domain,
  required List<T> values,
  required Map<T, Set<T>> table,
  required bool Function(T from, T to) canTransition,
  required T Function(T from, T to) advance,
}) {
  expect(table.keys.toSet(), values.toSet());

  for (final from in values) {
    for (final to in values) {
      final expected = table[from]!.contains(to);
      final label = '$domain: $from -> $to';

      expect(canTransition(from, to), expected, reason: label);
      if (expected) {
        expect(advance(from, to), to, reason: label);
      } else {
        expect(
          () => advance(from, to),
          throwsA(isA<ResourceStateTransitionException>()),
          reason: label,
        );
      }
    }
  }
}
