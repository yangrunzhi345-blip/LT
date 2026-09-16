import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/generation_patch_parser.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_patch.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_protocol.dart';

void main() {
  group('GenerationPatchParser', () {
    const validStartLine = '''
{"protocol_version": 1, "generation_id": "gen_1", "resource_id": "res_1", "section_id": "sec_1", "part_id": "part_1", "attempt_id": "att_1", "sequence": 0, "op": "start_part", "cursor": 0}
''';

    const validAppendLine = '''
{"protocol_version": 1, "generation_id": "gen_1", "resource_id": "res_1", "section_id": "sec_1", "part_id": "part_1", "attempt_id": "att_1", "sequence": 1, "op": "append_text", "text_delta": "Hello World", "cursor": 0}
''';

    const validCompleteLine = '''
{"protocol_version": 1, "generation_id": "gen_1", "resource_id": "res_1", "section_id": "sec_1", "part_id": "part_1", "attempt_id": "att_1", "sequence": 2, "op": "complete_part", "cursor": 11, "summary": "summary"}
''';

    test('parses valid single patch line', () {
      final patch = GenerationPatchParser.parsePatchLine(validStartLine);
      expect(patch.op, ResourcePatchOp.startPart);
      expect(patch.sequence, 0);
      expect(patch.generationId, 'gen_1');
      expect(patch.partId.value, 'part_1');
    });

    test('parses NDJSON into ordered list of patches', () {
      const ndjson = '$validStartLine\n$validAppendLine\n$validCompleteLine';
      final patches = GenerationPatchParser.parseNdjson(ndjson);
      expect(patches.length, 3);
      expect(patches[0].op, ResourcePatchOp.startPart);
      expect(patches[1].op, ResourcePatchOp.appendText);
      expect(patches[1].textDelta, 'Hello World');
      expect(patches[2].op, ResourcePatchOp.completePart);
    });

    test('rejects unauthorized fields (allowlist guard)', () {
      const lineWithExtra = '''
{"protocol_version": 1, "generation_id": "gen_1", "resource_id": "res_1", "section_id": "sec_1", "part_id": "part_1", "attempt_id": "att_1", "sequence": 0, "op": "start_part", "cursor": 0, "parts": []}
''';
      expect(
        () => GenerationPatchParser.parsePatchLine(lineWithExtra),
        throwsA(isA<GenerationPatchParseException>()),
      );
    });

    test('rejects non-canonical wire types for protocol_version', () {
      final lineWithStringVer = validStartLine.replaceFirst('1,', '"1",');
      expect(
        () => GenerationPatchParser.parsePatchLine(lineWithStringVer),
        throwsA(isA<GenerationPatchParseException>()),
      );
    });

    test('rejects invalid or unknown op', () {
      final lineWithUnknownOp =
          validStartLine.replaceFirst('"start_part"', '"mutate_part"');
      expect(
        () => GenerationPatchParser.parsePatchLine(lineWithUnknownOp),
        throwsA(isA<GenerationPatchParseException>()),
      );
    });

    test('responseToPatches produces valid 3-patch sequence', () {
      const response = PartGenerationResponse(
        protocolVersion: 1,
        generationId: 'gen_1',
        resourceId: ResourceId('res_1'),
        sectionId: SectionId('sec_1'),
        partId: PartId('part_1'),
        attemptId: 'att_1',
        content: 'Alpha Beta',
        summary: 'sum',
      );

      final patches = GenerationPatchParser.responseToPatches(response);
      expect(patches.length, 3);
      expect(patches[0].op, ResourcePatchOp.startPart);
      expect(patches[0].sequence, 0);
      expect(patches[1].op, ResourcePatchOp.appendText);
      expect(patches[1].sequence, 1);
      expect(patches[1].textDelta, 'Alpha Beta');
      expect(patches[2].op, ResourcePatchOp.completePart);
      expect(patches[2].sequence, 2);
      expect(patches[2].cursor, 10);
    });
  });

  group('GenerationPatchAccumulator', () {
    late GenerationPatchAccumulator accumulator;

    setUp(() {
      accumulator = GenerationPatchAccumulator(
        expectedGenerationId: 'gen_1',
        expectedResourceId: const ResourceId('res_1'),
        expectedSectionId: const SectionId('sec_1'),
        expectedPartId: const PartId('part_1'),
        expectedAttemptId: 'att_1',
      );
    });

    test('accumulates valid sequence to completion', () {
      accumulator.applyPatch(const ResourceGenerationPatch(
        protocolVersion: 1,
        generationId: 'gen_1',
        resourceId: ResourceId('res_1'),
        sectionId: SectionId('sec_1'),
        partId: PartId('part_1'),
        attemptId: 'att_1',
        sequence: 0,
        op: ResourcePatchOp.startPart,
      ));
      expect(accumulator.isStarted, isTrue);

      accumulator.applyPatch(const ResourceGenerationPatch(
        protocolVersion: 1,
        generationId: 'gen_1',
        resourceId: ResourceId('res_1'),
        sectionId: SectionId('sec_1'),
        partId: PartId('part_1'),
        attemptId: 'att_1',
        sequence: 1,
        op: ResourcePatchOp.appendText,
        textDelta: 'Chunk 1. ',
        cursor: 0,
      ));
      expect(accumulator.currentLength, 9);

      accumulator.applyPatch(const ResourceGenerationPatch(
        protocolVersion: 1,
        generationId: 'gen_1',
        resourceId: ResourceId('res_1'),
        sectionId: SectionId('sec_1'),
        partId: PartId('part_1'),
        attemptId: 'att_1',
        sequence: 2,
        op: ResourcePatchOp.appendText,
        textDelta: 'Chunk 2.',
        cursor: 9,
      ));
      expect(accumulator.currentLength, 17);

      accumulator.applyPatch(const ResourceGenerationPatch(
        protocolVersion: 1,
        generationId: 'gen_1',
        resourceId: ResourceId('res_1'),
        sectionId: SectionId('sec_1'),
        partId: PartId('part_1'),
        attemptId: 'att_1',
        sequence: 3,
        op: ResourcePatchOp.completePart,
        cursor: 17,
        summary: 'Chunk 1 and 2',
      ));
      expect(accumulator.isCompleted, isTrue);

      final response = accumulator.toResponse();
      expect(response.content, 'Chunk 1. Chunk 2.');
      expect(response.summary, 'Chunk 1 and 2');
    });

    test('idempotently ignores duplicate sequence without re-appending', () {
      accumulator.applyPatch(const ResourceGenerationPatch(
        protocolVersion: 1,
        generationId: 'gen_1',
        resourceId: ResourceId('res_1'),
        sectionId: SectionId('sec_1'),
        partId: PartId('part_1'),
        attemptId: 'att_1',
        sequence: 0,
        op: ResourcePatchOp.startPart,
      ));

      accumulator.applyPatch(const ResourceGenerationPatch(
        protocolVersion: 1,
        generationId: 'gen_1',
        resourceId: ResourceId('res_1'),
        sectionId: SectionId('sec_1'),
        partId: PartId('part_1'),
        attemptId: 'att_1',
        sequence: 1,
        op: ResourcePatchOp.appendText,
        textDelta: 'First',
        cursor: 0,
      ));

      // Re-apply sequence 1 (duplicate delivery)
      accumulator.applyPatch(const ResourceGenerationPatch(
        protocolVersion: 1,
        generationId: 'gen_1',
        resourceId: ResourceId('res_1'),
        sectionId: SectionId('sec_1'),
        partId: PartId('part_1'),
        attemptId: 'att_1',
        sequence: 1,
        op: ResourcePatchOp.appendText,
        textDelta: 'First',
        cursor: 0,
      ));

      expect(accumulator.currentText, 'First');
      expect(accumulator.currentLength, 5);
    });

    test('throws PatchSequenceGapException if sequence is skipped', () {
      accumulator.applyPatch(const ResourceGenerationPatch(
        protocolVersion: 1,
        generationId: 'gen_1',
        resourceId: ResourceId('res_1'),
        sectionId: SectionId('sec_1'),
        partId: PartId('part_1'),
        attemptId: 'att_1',
        sequence: 0,
        op: ResourcePatchOp.startPart,
      ));

      // Skip sequence 1 and send sequence 2 directly
      expect(
        () => accumulator.applyPatch(const ResourceGenerationPatch(
          protocolVersion: 1,
          generationId: 'gen_1',
          resourceId: ResourceId('res_1'),
          sectionId: SectionId('sec_1'),
          partId: PartId('part_1'),
          attemptId: 'att_1',
          sequence: 2,
          op: ResourcePatchOp.appendText,
          textDelta: 'Skipped',
          cursor: 0,
        )),
        throwsA(isA<PatchSequenceGapException>()),
      );
    });

    test('throws PatchCursorMismatchException if cursor does not match length',
        () {
      accumulator.applyPatch(const ResourceGenerationPatch(
        protocolVersion: 1,
        generationId: 'gen_1',
        resourceId: ResourceId('res_1'),
        sectionId: SectionId('sec_1'),
        partId: PartId('part_1'),
        attemptId: 'att_1',
        sequence: 0,
        op: ResourcePatchOp.startPart,
      ));

      // cursor says 5 but current buffer length is 0
      expect(
        () => accumulator.applyPatch(const ResourceGenerationPatch(
          protocolVersion: 1,
          generationId: 'gen_1',
          resourceId: ResourceId('res_1'),
          sectionId: SectionId('sec_1'),
          partId: PartId('part_1'),
          attemptId: 'att_1',
          sequence: 1,
          op: ResourcePatchOp.appendText,
          textDelta: 'Text',
          cursor: 5,
        )),
        throwsA(isA<PatchCursorMismatchException>()),
      );
    });

    test('handles failPart and throws on toResponse', () {
      accumulator.applyPatch(const ResourceGenerationPatch(
        protocolVersion: 1,
        generationId: 'gen_1',
        resourceId: ResourceId('res_1'),
        sectionId: SectionId('sec_1'),
        partId: PartId('part_1'),
        attemptId: 'att_1',
        sequence: 0,
        op: ResourcePatchOp.startPart,
      ));

      accumulator.applyPatch(const ResourceGenerationPatch(
        protocolVersion: 1,
        generationId: 'gen_1',
        resourceId: ResourceId('res_1'),
        sectionId: SectionId('sec_1'),
        partId: PartId('part_1'),
        attemptId: 'att_1',
        sequence: 1,
        op: ResourcePatchOp.failPart,
        errorMessage: '模型上下文溢出',
      ));

      expect(accumulator.isFailed, isTrue);
      expect(
        () => accumulator.toResponse(),
        throwsA(isA<StateError>()),
      );
    });
  });
}
