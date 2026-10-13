import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/generation_patch_parser.dart';
import 'package:lt_dialogue/application/resources/resource_generation_error.dart';
import 'package:lt_dialogue/domain/errors/app_error.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_patch.dart';

void main() {
  group('GenerationPatchAccumulator sequence integrity', () {
    late GenerationPatchAccumulator accumulator;
    setUp(() {
      accumulator = GenerationPatchAccumulator(
        expectedGenerationId: 'gen',
        expectedResourceId: const ResourceId('res'),
        expectedSectionId: const SectionId('sec'),
        expectedPartId: const PartId('part'),
        expectedAttemptId: 'attempt',
      );
    });
    ResourceGenerationPatch patch(
      int sequence,
      ResourcePatchOp op, {
      String text = '',
      String summary = '',
      String? error,
      int? cursor,
    }) =>
        ResourceGenerationPatch(
            protocolVersion: 1,
            generationId: 'gen',
            resourceId: const ResourceId('res'),
            sectionId: const SectionId('sec'),
            partId: const PartId('part'),
            attemptId: 'attempt',
            sequence: sequence,
            op: op,
            textDelta: text,
            summary: summary,
            errorMessage: error,
            cursor: cursor);

    test(
        'should reject conflicting text rather than silently complete truncated content',
        () {
      accumulator.applyPatch(patch(0, ResourcePatchOp.startPart));
      accumulator.applyPatch(patch(1, ResourcePatchOp.appendText, text: '荒'));
      expect(
          () => accumulator.applyPatch(
              patch(1, ResourcePatchOp.appendText, text: '经历' * 210)),
          throwsA(isA<PatchSequenceConflictException>()));
      expect(accumulator.toResponse, throwsStateError);
    });
    test(
        'should compare operation, summary and failure metadata on repeated sequences',
        () {
      for (final duplicate in [
        patch(0, ResourcePatchOp.appendText),
        patch(0, ResourcePatchOp.startPart, summary: 'changed'),
        patch(0, ResourcePatchOp.startPart, error: 'changed'),
        patch(0, ResourcePatchOp.startPart, text: 'changed'),
      ]) {
        final fresh = GenerationPatchAccumulator(
            expectedGenerationId: 'gen',
            expectedResourceId: const ResourceId('res'),
            expectedSectionId: const SectionId('sec'),
            expectedPartId: const PartId('part'),
            expectedAttemptId: 'attempt');
        fresh.applyPatch(patch(0, ResourcePatchOp.startPart));
        expect(() => fresh.applyPatch(duplicate),
            throwsA(isA<PatchSequenceConflictException>()));
      }
    });
    test('should canonicalize omitted cursor to its original applied offset',
        () {
      accumulator.applyPatch(patch(0, ResourcePatchOp.startPart));
      accumulator.applyPatch(patch(1, ResourcePatchOp.appendText, text: '🙂荒'));
      accumulator
          .applyPatch(patch(2, ResourcePatchOp.appendText, text: '\n导师'));
      accumulator.applyPatch(
          patch(1, ResourcePatchOp.appendText, text: '🙂荒', cursor: 0));
      accumulator.applyPatch(
          patch(2, ResourcePatchOp.appendText, text: '\n导师', cursor: 3));
      accumulator
          .applyPatch(patch(3, ResourcePatchOp.completePart, summary: '摘要'));
      accumulator.applyPatch(
          patch(3, ResourcePatchOp.completePart, summary: '摘要', cursor: 6));
      expect(accumulator.toResponse().content, '🙂荒\n导师');
      expect(accumulator.nextSequence, 4);
    });
    test('should reject a conflicting cursor in an old sequence', () {
      accumulator.applyPatch(patch(0, ResourcePatchOp.startPart));
      accumulator.applyPatch(patch(1, ResourcePatchOp.appendText, text: '正文'));
      expect(
          () => accumulator.applyPatch(
              patch(1, ResourcePatchOp.appendText, text: '正文', cursor: 2)),
          throwsA(isA<PatchSequenceConflictException>()));
    });
    test('should accept identical completed replay and reject changed summary',
        () {
      accumulator.applyPatch(patch(0, ResourcePatchOp.startPart));
      accumulator.applyPatch(patch(1, ResourcePatchOp.appendText, text: '正文'));
      accumulator
          .applyPatch(patch(2, ResourcePatchOp.completePart, summary: '摘要'));
      accumulator
          .applyPatch(patch(2, ResourcePatchOp.completePart, summary: '摘要'));
      expect(accumulator.toResponse().summary, '摘要');
      Object? caught;
      try {
        accumulator.applyPatch(
            patch(2, ResourcePatchOp.completePart, summary: '私密摘要'));
      } catch (error) {
        caught = error;
      }
      expect(caught, isNotNull);
      expect(caught.toString(), isNot(contains('私密摘要')));
      expect(resourceGenerationError(caught!).code,
          AppErrorCode.resourceParseFailed);
      expect(accumulator.toResponse, throwsStateError);
    });
    test(
        'should reject new operations after complete even when payload is identical',
        () {
      accumulator.applyPatch(patch(0, ResourcePatchOp.appendText, text: '正文'));
      accumulator.applyPatch(patch(1, ResourcePatchOp.completePart));
      expect(
          () => accumulator.applyPatch(patch(2, ResourcePatchOp.completePart)),
          throwsA(isA<GenerationPatchParseException>()));
      expect(accumulator.toResponse, throwsStateError);
    });
    test(
        'should bound empty event history while retaining old replay assertions',
        () {
      final bounded = GenerationPatchAccumulator(
          expectedGenerationId: 'gen',
          expectedResourceId: const ResourceId('res'),
          expectedSectionId: const SectionId('sec'),
          expectedPartId: const PartId('part'),
          expectedAttemptId: 'attempt',
          maxPatchEvents: 3);
      bounded.applyPatch(patch(0, ResourcePatchOp.startPart));
      bounded.applyPatch(patch(1, ResourcePatchOp.appendText));
      bounded.applyPatch(patch(2, ResourcePatchOp.appendText));
      bounded.applyPatch(patch(0, ResourcePatchOp.startPart, cursor: 0));
      expect(() => bounded.applyPatch(patch(3, ResourcePatchOp.completePart)),
          throwsA(isA<GenerationPatchParseException>()));
      expect(bounded.toResponse, throwsStateError);
      expect(bounded.nextSequence, 3);
    });
    test(
        'should preserve identical failure replay and reject changed fail details',
        () {
      final failure = patch(0, ResourcePatchOp.failPart, error: 'failure');
      accumulator.applyPatch(failure);
      accumulator.applyPatch(failure);
      expect(accumulator.nextSequence, 1);
      expect(accumulator.toResponse, throwsStateError);
      expect(
          () => accumulator.applyPatch(
              patch(0, ResourcePatchOp.failPart, error: 'different')),
          throwsA(isA<PatchSequenceConflictException>()));
    });
  });
}
