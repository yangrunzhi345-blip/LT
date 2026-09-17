import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_patch.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_protocol.dart';
import 'package:lt_dialogue/domain/resources/section_generation_binding.dart';

void main() {
  const resourceId = ResourceId('res_1');
  const sectionId = SectionId('sec_1');
  const partId = PartId('part_1');

  SectionGenerationBinding binding() => const SectionGenerationBinding(
        generationId: 'gen_1',
        resourceId: resourceId,
        sectionId: sectionId,
        partId: partId,
      );

  ResourceGenerationPatch patch({
    String generationId = 'gen_1',
    ResourceId resource = resourceId,
    SectionId section = sectionId,
    PartId part = partId,
  }) =>
      ResourceGenerationPatch(
        protocolVersion: 1,
        generationId: generationId,
        resourceId: resource,
        sectionId: section,
        partId: part,
        attemptId: 'attempt_1',
        sequence: 1,
        op: ResourcePatchOp.appendText,
        textDelta: '正文',
        cursor: 0,
      );

  group('SectionGenerationBinding.validatePatch', () {
    test('accepts a patch bound to this generation, resource, section and part',
        () {
      expect(() => binding().validatePatch(patch()), returnsNormally);
    });

    test('rejects a patch from another section', () {
      expect(
        () => binding().validatePatch(patch(section: const SectionId('sec_2'))),
        throwsA(
          isA<SectionGenerationBindingException>().having(
            (error) => error.field,
            'field',
            SectionBindingField.sectionId,
          ),
        ),
      );
    });

    test('rejects a patch from a stale generation', () {
      expect(
        () => binding().validatePatch(patch(generationId: 'gen_old')),
        throwsA(
          isA<SectionGenerationBindingException>().having(
            (error) => error.field,
            'field',
            SectionBindingField.generationId,
          ),
        ),
      );
    });

    test('rejects a patch from another resource', () {
      expect(
        () => binding().validatePatch(
          patch(resource: const ResourceId('res_2')),
        ),
        throwsA(
          isA<SectionGenerationBindingException>().having(
            (error) => error.field,
            'field',
            SectionBindingField.resourceId,
          ),
        ),
      );
    });

    test('rejects a patch for a sibling Part', () {
      expect(
        () => binding().validatePatch(patch(part: const PartId('part_2'))),
        throwsA(
          isA<SectionGenerationBindingException>().having(
            (error) => error.field,
            'field',
            SectionBindingField.partId,
          ),
        ),
      );
    });

    test('names the expected and actual value in the error', () {
      try {
        binding().validatePatch(patch(section: const SectionId('sec_2')));
        fail('应当拒绝 sectionId 不匹配的 patch');
      } on SectionGenerationBindingException catch (error) {
        expect(error.expected, 'sec_1');
        expect(error.actual, 'sec_2');
        expect(error.toString(), contains('sectionId'));
      }
    });
  });

  group('SectionGenerationBinding.validateResponse', () {
    PartGenerationResponse response({
      String generationId = 'gen_1',
      ResourceId resource = resourceId,
      SectionId section = sectionId,
      PartId part = partId,
    }) =>
        PartGenerationResponse(
          protocolVersion: 1,
          generationId: generationId,
          resourceId: resource,
          sectionId: section,
          partId: part,
          attemptId: 'attempt_1',
          content: '正文',
        );

    test('accepts a matching response', () {
      expect(() => binding().validateResponse(response()), returnsNormally);
    });

    test('rejects a response for another section', () {
      expect(
        () => binding().validateResponse(
          response(section: const SectionId('sec_2')),
        ),
        throwsA(isA<SectionGenerationBindingException>()),
      );
    });
  });

  group('SectionGenerationBinding identity', () {
    test('covers compares generation, resource and section only', () {
      const other = SectionGenerationBinding(
        generationId: 'gen_1',
        resourceId: resourceId,
        sectionId: sectionId,
        partId: PartId('part_2'),
      );
      expect(binding().covers(other), isTrue);
      expect(
        binding().covers(
          const SectionGenerationBinding(
            generationId: 'gen_2',
            resourceId: resourceId,
            sectionId: sectionId,
            partId: partId,
          ),
        ),
        isFalse,
      );
    });
  });
}
