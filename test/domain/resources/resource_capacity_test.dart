import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/resource_capacity.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_limits.dart';

void main() {
  group('ResourceCapacityPolicy boundaries — worldview 50,000 / 60,000', () {
    // The exact frozen boundaries. Written as literals on purpose so this test
    // is an independent oracle and cannot pass by reading ResourceLimits.
    const cases = <int, CapacityStatus>{
      0: CapacityStatus.normal,
      49999: CapacityStatus.normal,
      50000: CapacityStatus.normal,
      50001: CapacityStatus.elastic,
      59999: CapacityStatus.elastic,
      60000: CapacityStatus.elastic,
      60001: CapacityStatus.overflow,
    };

    cases.forEach((characters, expected) {
      test('worldview $characters characters is ${expected.name}', () {
        expect(
          ResourceCapacityMath.statusFor(ResourceType.worldview, characters),
          expected,
        );
      });
    });

    test('a negative count is rejected instead of classified', () {
      expect(
        () => ResourceCapacityMath.statusFor(ResourceType.worldview, -1),
        throwsArgumentError,
      );
    });
  });

  group('ResourceCapacityPolicy boundaries — character / NPC 20,000 / 24,000',
      () {
    const cases = <int, CapacityStatus>{
      19999: CapacityStatus.normal,
      20000: CapacityStatus.normal,
      20001: CapacityStatus.elastic,
      24000: CapacityStatus.elastic,
      24001: CapacityStatus.overflow,
    };

    for (final type in const [ResourceType.character, ResourceType.npc]) {
      cases.forEach((characters, expected) {
        test('${type.name} $characters characters is ${expected.name}', () {
          expect(ResourceCapacityMath.statusFor(type, characters), expected);
        });
      });
    }

    test('npc shares the character budget', () {
      expect(
        ResourceLimits.npcNominalCharacters,
        ResourceLimits.characterNominalCharacters,
      );
      expect(
        ResourceLimits.npcAbsoluteCharacters,
        ResourceLimits.characterAbsoluteCharacters,
      );
    });
  });

  group('ResourceCapacityMath', () {
    test('estimates tokens conservatively from an aggregate count', () {
      expect(ResourceCapacityMath.tokensForCharacters(0), 0);
      expect(ResourceCapacityMath.tokensForCharacters(1), 1);
      // 0.7 tokens per character, rounded up: never fewer than the real text
      // would produce under TokenEstimator's heaviest weight.
      expect(ResourceCapacityMath.tokensForCharacters(10), 7);
      expect(ResourceCapacityMath.tokensForCharacters(11), 8);
    });
  });

  group('ResourceCapacitySnapshot', () {
    ResourceCapacitySnapshot build({
      required int total,
      required ResourceType type,
      int archived = 0,
    }) {
      return ResourceCapacitySnapshot(
        resourceId: const ResourceId('res_1'),
        type: type,
        totalCharacters: total,
        activeCharacters: total - archived,
        archivedCharacters: archived,
        estimatedTokens: ResourceCapacityMath.tokensForCharacters(total),
        sectionCount: 3,
        partCount: 9,
        historicalRevisionCount: 4,
        status: ResourceCapacityMath.statusFor(type, total),
      );
    }

    test('reports archive size in the same unit as characters', () {
      final snapshot =
          build(total: 900, type: ResourceType.character, archived: 200);
      expect(snapshot.archiveSize, 200);
      expect(snapshot.activeCharacters, 700);
    });

    test('fill ratio is relative to the absolute budget', () {
      final snapshot = build(total: 30000, type: ResourceType.worldview);
      expect(snapshot.fillRatio, closeTo(0.5, 1e-9));
      expect(snapshot.status, CapacityStatus.normal);
      expect(snapshot.needsCompression, isFalse);
    });

    test('a resource above its nominal budget needs compression', () {
      final snapshot = build(total: 52000, type: ResourceType.worldview);
      expect(snapshot.fillRatio, closeTo(52000 / 60000, 1e-9));
      expect(snapshot.status, CapacityStatus.elastic);
      expect(snapshot.needsCompression, isTrue);
    });

    test('a normal resource does not need compression', () {
      final snapshot = build(total: 100, type: ResourceType.character);
      expect(snapshot.status, CapacityStatus.normal);
      expect(snapshot.needsCompression, isFalse);
    });

    test('overflow is still a fully measured, persisted state', () {
      final snapshot = build(total: 60001, type: ResourceType.worldview);
      expect(snapshot.status, CapacityStatus.overflow);
      expect(snapshot.totalCharacters, 60001,
          reason: 'overflow must never be represented by a truncated count');
    });
  });

  group('SectionCapacitySnapshot', () {
    SectionCapacitySnapshot build({
      required int characters,
      required int partCount,
      int largest = 0,
      bool complete = true,
    }) =>
        SectionCapacitySnapshot(
          sectionId: const SectionId('sec_1'),
          title: '第一章',
          characters: characters,
          partCount: partCount,
          largestPartCharacters: largest,
          isComplete: complete,
        );

    test('an empty section is never a compression target', () {
      expect(
          build(characters: 0, partCount: 0, complete: false)
              .isCompressionCandidate,
          isFalse);
    });

    test('a section below the minimum size is not a target', () {
      expect(
        build(
          characters: ResourceLimits.minCompressibleNodeCharacters - 1,
          partCount: 2,
        ).isCompressionCandidate,
        isFalse,
      );
    });

    test('a complete, large section is a target', () {
      expect(
        build(
          characters: ResourceLimits.minCompressibleNodeCharacters,
          partCount: 2,
        ).isCompressionCandidate,
        isTrue,
      );
    });

    test('average part size avoids a divide by zero', () {
      expect(build(characters: 0, partCount: 0).averagePartCharacters, 0);
      expect(build(characters: 900, partCount: 3).averagePartCharacters, 300);
    });
  });
}
