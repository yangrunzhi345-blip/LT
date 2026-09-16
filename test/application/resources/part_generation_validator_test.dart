import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/part_generation_validator.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_protocol.dart';
import 'package:lt_dialogue/domain/resources/resource_limits.dart';

void main() {
  group('PartGenerationValidator', () {
    const defaultRequest = PartGenerationRequest(
      protocolVersion: 1,
      generationId: 'gen_100',
      resourceId: ResourceId('res_alpha'),
      sectionId: SectionId('sec_geo'),
      partId: PartId('part_terrain'),
      attemptId: 'att_1',
      targetBudget: 1200,
      promptGoal: '描述大陆的地形分布',
      context: PartGenerationContext(
        resourceName: '艾尔登',
        resourceType: ResourceType.worldview,
        resourceSummary: '高魔奇幻大陆',
        sectionTitle: '地理概貌',
        sectionSummary: '自然与地质',
        partTitle: '主要地形',
      ),
    );

    const defaultResponse = PartGenerationResponse(
      protocolVersion: 1,
      generationId: 'gen_100',
      resourceId: ResourceId('res_alpha'),
      sectionId: SectionId('sec_geo'),
      partId: PartId('part_terrain'),
      attemptId: 'att_1',
      content: '这片大陆中部由高耸入云的阿卡迪亚山脉横贯东西...',
      summary: '阿卡迪亚山脉地形',
      status: 'completed',
    );

    test('valid matching response passes validation', () {
      expect(
        () => PartGenerationValidator.validate(
          request: defaultRequest,
          response: defaultResponse,
        ),
        returnsNormally,
      );
    });

    test('rejects protocol version mismatch', () {
      final invalidResponse = PartGenerationResponse(
        protocolVersion: 2, // Mismatch
        generationId: defaultRequest.generationId,
        resourceId: defaultRequest.resourceId,
        sectionId: defaultRequest.sectionId,
        partId: defaultRequest.partId,
        attemptId: defaultRequest.attemptId,
        content: 'content',
      );

      expect(
        () => PartGenerationValidator.validate(
          request: defaultRequest,
          response: invalidResponse,
        ),
        throwsA(predicate<PartGenerationValidationException>(
          (e) => e.field == 'protocol_version',
        )),
      );
    });

    test('rejects generation ID mismatch', () {
      final invalidResponse = PartGenerationResponse(
        protocolVersion: 1,
        generationId: 'gen_different',
        resourceId: defaultRequest.resourceId,
        sectionId: defaultRequest.sectionId,
        partId: defaultRequest.partId,
        attemptId: defaultRequest.attemptId,
        content: 'content',
      );

      expect(
        () => PartGenerationValidator.validate(
          request: defaultRequest,
          response: invalidResponse,
        ),
        throwsA(predicate<PartGenerationValidationException>(
          (e) => e.field == 'generation_id',
        )),
      );
    });

    test('rejects cross-resource injection (resource_id mismatch)', () {
      final invalidResponse = PartGenerationResponse(
        protocolVersion: 1,
        generationId: defaultRequest.generationId,
        resourceId: const ResourceId('res_other_resource'),
        sectionId: defaultRequest.sectionId,
        partId: defaultRequest.partId,
        attemptId: defaultRequest.attemptId,
        content: 'content',
      );

      expect(
        () => PartGenerationValidator.validate(
          request: defaultRequest,
          response: invalidResponse,
        ),
        throwsA(predicate<PartGenerationValidationException>(
          (e) => e.field == 'resource_id',
        )),
      );
    });

    test('rejects section ID mismatch', () {
      final invalidResponse = PartGenerationResponse(
        protocolVersion: 1,
        generationId: defaultRequest.generationId,
        resourceId: defaultRequest.resourceId,
        sectionId: const SectionId('sec_wrong'),
        partId: defaultRequest.partId,
        attemptId: defaultRequest.attemptId,
        content: 'content',
      );

      expect(
        () => PartGenerationValidator.validate(
          request: defaultRequest,
          response: invalidResponse,
        ),
        throwsA(predicate<PartGenerationValidationException>(
          (e) => e.field == 'section_id',
        )),
      );
    });

    test('rejects unauthorized part ID (part_id mismatch)', () {
      final invalidResponse = PartGenerationResponse(
        protocolVersion: 1,
        generationId: defaultRequest.generationId,
        resourceId: defaultRequest.resourceId,
        sectionId: defaultRequest.sectionId,
        partId: const PartId('part_unauthorized_99'),
        attemptId: defaultRequest.attemptId,
        content: 'content',
      );

      expect(
        () => PartGenerationValidator.validate(
          request: defaultRequest,
          response: invalidResponse,
        ),
        throwsA(predicate<PartGenerationValidationException>(
          (e) => e.field == 'part_id',
        )),
      );
    });

    test('rejects attempt ID mismatch (race or stale response)', () {
      final invalidResponse = PartGenerationResponse(
        protocolVersion: 1,
        generationId: defaultRequest.generationId,
        resourceId: defaultRequest.resourceId,
        sectionId: defaultRequest.sectionId,
        partId: defaultRequest.partId,
        attemptId: 'att_stale_old',
        content: 'content',
      );

      expect(
        () => PartGenerationValidator.validate(
          request: defaultRequest,
          response: invalidResponse,
        ),
        throwsA(predicate<PartGenerationValidationException>(
          (e) => e.field == 'attempt_id',
        )),
      );
    });

    test('rejects empty or whitespace-only content', () {
      final emptyResponse = PartGenerationResponse(
        protocolVersion: 1,
        generationId: defaultRequest.generationId,
        resourceId: defaultRequest.resourceId,
        sectionId: defaultRequest.sectionId,
        partId: defaultRequest.partId,
        attemptId: defaultRequest.attemptId,
        content: '   \n\t  ',
      );

      expect(
        () => PartGenerationValidator.validate(
          request: defaultRequest,
          response: emptyResponse,
        ),
        throwsA(predicate<PartGenerationValidationException>(
          (e) => e.field == 'content',
        )),
      );
    });

    test('rejects content exceeding maximum part characters', () {
      final oversized = 'A' * (ResourceLimits.maxPartCharacters + 10);
      final oversizedResponse = PartGenerationResponse(
        protocolVersion: 1,
        generationId: defaultRequest.generationId,
        resourceId: defaultRequest.resourceId,
        sectionId: defaultRequest.sectionId,
        partId: defaultRequest.partId,
        attemptId: defaultRequest.attemptId,
        content: oversized,
      );

      expect(
        () => PartGenerationValidator.validate(
          request: defaultRequest,
          response: oversizedResponse,
        ),
        throwsA(predicate<PartGenerationValidationException>(
          (e) => e.field == 'content_length',
        )),
      );
    });

    test('rejects structural mutation keys in raw response', () {
      final illegalKeys = {
        'sections': [
          {'id': 'sec_2'}
        ],
        'parts': [
          {'id': 'part_2'}
        ],
        'chapters': ['chap_1'],
        'new_nodes': ['node_1'],
      };

      for (final entry in illegalKeys.entries) {
        expect(
          () => PartGenerationValidator.validate(
            request: defaultRequest,
            response: defaultResponse,
            rawDecodedMap: {
              'protocol_version': 1,
              'content': 'valid content',
              entry.key: entry.value,
            },
          ),
          throwsA(predicate<PartGenerationValidationException>(
            (e) => e.field == entry.key,
          )),
        );
      }
    });
  });
}
