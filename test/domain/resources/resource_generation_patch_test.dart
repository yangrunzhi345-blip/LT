import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_patch.dart';

void main() {
  group('ResourcePatchOp', () {
    test('wire values match protocol specification', () {
      expect(ResourcePatchOp.startPart.wireValue, 'start_part');
      expect(ResourcePatchOp.appendText.wireValue, 'append_text');
      expect(ResourcePatchOp.completePart.wireValue, 'complete_part');
      expect(ResourcePatchOp.failPart.wireValue, 'fail_part');
    });

    test('fromWire maps wire values correctly', () {
      expect(ResourcePatchOp.fromWire('start_part'), ResourcePatchOp.startPart);
      expect(
          ResourcePatchOp.fromWire('append_text'), ResourcePatchOp.appendText);
      expect(ResourcePatchOp.fromWire('complete_part'),
          ResourcePatchOp.completePart);
      expect(ResourcePatchOp.fromWire('fail_part'), ResourcePatchOp.failPart);
    });

    test('fromWire throws on unknown wire value', () {
      expect(
        () => ResourcePatchOp.fromWire('unknown_op'),
        throwsArgumentError,
      );
    });
  });

  group('ResourceGenerationPatch', () {
    test('constructs valid patch and validates equality', () {
      const patch1 = ResourceGenerationPatch(
        protocolVersion: 1,
        generationId: 'gen_1',
        resourceId: ResourceId('res_1'),
        sectionId: SectionId('sec_1'),
        partId: PartId('part_1'),
        attemptId: 'att_1',
        sequence: 0,
        op: ResourcePatchOp.startPart,
      );

      const patch2 = ResourceGenerationPatch(
        protocolVersion: 1,
        generationId: 'gen_1',
        resourceId: ResourceId('res_1'),
        sectionId: SectionId('sec_1'),
        partId: PartId('part_1'),
        attemptId: 'att_1',
        sequence: 0,
        op: ResourcePatchOp.startPart,
      );

      expect(patch1, equals(patch2));
      expect(patch1.hashCode, equals(patch2.hashCode));
      expect(patch1.toString(), contains('start_part'));
    });

    test('asserts protocolVersion == 1 and non-negative sequence and cursor',
        () {
      expect(
        () => ResourceGenerationPatch(
          protocolVersion: 2,
          generationId: 'gen_1',
          resourceId: const ResourceId('res_1'),
          sectionId: const SectionId('sec_1'),
          partId: const PartId('part_1'),
          attemptId: 'att_1',
          sequence: 0,
          op: ResourcePatchOp.startPart,
        ),
        throwsA(isA<AssertionError>()),
      );

      expect(
        () => ResourceGenerationPatch(
          protocolVersion: 1,
          generationId: 'gen_1',
          resourceId: const ResourceId('res_1'),
          sectionId: const SectionId('sec_1'),
          partId: const PartId('part_1'),
          attemptId: 'att_1',
          sequence: -1,
          op: ResourcePatchOp.startPart,
        ),
        throwsA(isA<AssertionError>()),
      );

      expect(
        () => ResourceGenerationPatch(
          protocolVersion: 1,
          generationId: 'gen_1',
          resourceId: const ResourceId('res_1'),
          sectionId: const SectionId('sec_1'),
          partId: const PartId('part_1'),
          attemptId: 'att_1',
          sequence: 0,
          op: ResourcePatchOp.startPart,
          cursor: -1,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
