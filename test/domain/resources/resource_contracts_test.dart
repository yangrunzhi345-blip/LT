import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/models/resource_provenance.dart';

/// Phase 0 froze the semantics every later phase must implement. Phase 5c
/// retired the tree / revision / assembly pipeline, so only the value contracts
/// the card-backed library, migration and tombstone store still use remain.
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
      expect(const ResourceId('r1').toString(), 'resource(r1)');
      expect(const SectionId('s1').toString(), 'section(s1)');
      expect(const PartId('p1').toString(), 'part(p1)');
    });
  });

  group('NodeStatus', () {
    test('keeps the frozen editorial values', () {
      expect(NodeStatus.values.map((status) => status.storageValue),
          ['draft', 'confirmed', 'archived']);
    });
  });

  group('CapacityStatus', () {
    test('classifies without implying truncation', () {
      expect(CapacityStatus.values.map((status) => status.storageValue),
          ['normal', 'elastic', 'overflow']);
    });
  });

  group('ReadinessState', () {
    test('keeps the four readiness values', () {
      expect(ReadinessState.values.map((state) => state.storageValue),
          ['preparing', 'ready', 'failed', 'stale']);
    });
  });

  group('ResourceContractException', () {
    test('carries its message in the string form', () {
      const error = ResourceContractException('bad input');
      expect(error.message, 'bad input');
      expect(error.toString(), contains('bad input'));
    });
  });
}
