import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/generation_patch_parser.dart';
import 'package:lt_dialogue/application/resources/model_generation_patch_decoder.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_patch.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_protocol.dart';

void main() {
  group('ModelGenerationPatchDecoder', () {
    const request = PartGenerationRequest(
      generationId: 'gen_current',
      resourceId: ResourceId('res_current'),
      sectionId: SectionId('sec_current'),
      partId: PartId('part_current'),
      attemptId: 'attempt_current',
      targetBudget: 500,
      promptGoal: '生成正文',
      context: PartGenerationContext(
        resourceName: '测试资源',
        resourceType: ResourceType.worldview,
        resourceSummary: '',
        sectionTitle: '章节',
        sectionSummary: '',
        partTitle: '部件',
      ),
    );
    late ModelGenerationPatchDecoder decoder;

    setUp(() {
      decoder = ModelGenerationPatchDecoder(request);
    });

    test('should bind a completely omitted immutable envelope', () {
      final patch = decoder.decodeLine(
        jsonEncode({
          'sequence': 0,
          'op': 'start_part',
        }),
      );

      expect(patch.protocolVersion, 1);
      expect(patch.generationId, request.generationId);
      expect(patch.resourceId, request.resourceId);
      expect(patch.sectionId, request.sectionId);
      expect(patch.partId, request.partId);
      expect(patch.attemptId, request.attemptId);
    });

    test('should accept matching legacy envelope assertions', () {
      final patch = decoder.decodeLine(
        jsonEncode({
          'protocol_version': 1,
          'generation_id': request.generationId,
          'resource_id': request.resourceId.value,
          'section_id': request.sectionId.value,
          'part_id': request.partId.value,
          'attempt_id': request.attemptId,
          'sequence': 0,
          'op': 'start_part',
        }),
      );

      expect(patch.op, ResourcePatchOp.startPart);
    });

    test('should reject a conflicting protocol version', () {
      expect(
        () => decoder.decodeLine(
          jsonEncode({
            'protocol_version': 2,
            'sequence': 0,
            'op': 'start_part',
          }),
        ),
        throwsA(
          isA<GenerationPatchParseException>().having(
            (error) => error.field,
            'field',
            'protocol_version',
          ),
        ),
      );
    });

    test('should report a safe Patch index and key-only shape', () {
      decoder.decodeLine(jsonEncode({'sequence': 0, 'op': 'start_part'}));

      try {
        decoder.decodeLine(
          jsonEncode({
            'sequence': 1,
            'op': 'append_text',
            'text_delta': '不得出现在诊断中的私密正文',
            'part_id': 'foreign_part',
          }),
        );
        fail('conflicting envelope should fail');
      } on GenerationPatchParseException catch (error) {
        expect(error.message, contains('模型 Patch #2'));
        expect(error.rawLine, startsWith('object keys='));
        expect(error.rawLine, contains('text_delta'));
        expect(error.rawLine, isNot(contains('私密正文')));
      }
    });

    for (final field in ['generation_id', 'part_id', 'attempt_id']) {
      test('should reject a conflicting $field assertion', () {
        expect(
          () => decoder.decodeLine(
            jsonEncode({
              field: 'stale_or_foreign',
              'sequence': 0,
              'op': 'start_part',
            }),
          ),
          throwsA(
            isA<GenerationPatchParseException>().having(
              (error) => error.field,
              'field',
              field,
            ),
          ),
        );
      });
    }

    test('should decode collected model-only NDJSON through one binder', () {
      final patches = decoder.decodeNdjson(
        [
          {'sequence': 0, 'op': 'start_part'},
          {
            'sequence': 1,
            'op': 'append_text',
            'text_delta': '中文，标点。Emoji 🧭\n第二行',
          },
          {'sequence': 2, 'op': 'complete_part'},
        ].map(jsonEncode).join('\n'),
      );

      final accumulator = GenerationPatchAccumulator(
        expectedGenerationId: request.generationId,
        expectedResourceId: request.resourceId,
        expectedSectionId: request.sectionId,
        expectedPartId: request.partId,
        expectedAttemptId: request.attemptId,
      );
      for (final patch in patches) {
        accumulator.applyPatch(patch);
      }

      const content = '中文，标点。Emoji 🧭\n第二行';
      expect(accumulator.currentLength, content.length);
      expect(accumulator.toResponse().content, content);
    });
  });
}
