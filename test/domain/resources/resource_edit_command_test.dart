import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_edit_command.dart';

void main() {
  const resourceId = ResourceId('res_1');
  const sectionId = SectionId('sec_1');
  const partId = PartId('part_1');
  const token = '2026-09-17T00:00:00.000';

  group('ResourceEditCommandValidator', () {
    test('accepts well-formed commands', () {
      expect(
        () => ResourceEditCommandValidator.validate(
          const CreateSectionCommand(resourceId: resourceId, title: '新章节'),
        ),
        returnsNormally,
      );
      expect(
        () => ResourceEditCommandValidator.validate(
          const RenameSectionCommand(
            sectionId: sectionId,
            title: '改名',
            expectedUpdatedAt: token,
          ),
        ),
        returnsNormally,
      );
      expect(
        () => ResourceEditCommandValidator.validate(
          const UpdateSectionCommand(
            sectionId: sectionId,
            summary: '摘要',
            expectedUpdatedAt: token,
          ),
        ),
        returnsNormally,
      );
      expect(
        () => ResourceEditCommandValidator.validate(
          const MoveSectionCommand(
            resourceId: resourceId,
            sectionId: sectionId,
            targetIndex: 0,
            expectedUpdatedAt: token,
          ),
        ),
        returnsNormally,
      );
      expect(
        () => ResourceEditCommandValidator.validate(
          const DeleteSectionCommand(
            sectionId: sectionId,
            expectedUpdatedAt: token,
          ),
        ),
        returnsNormally,
      );
      expect(
        () => ResourceEditCommandValidator.validate(
          const UpdatePartCommand(
            sectionId: sectionId,
            partId: partId,
            content: '正文',
            expectedUpdatedAt: token,
          ),
        ),
        returnsNormally,
      );
      expect(
        () => ResourceEditCommandValidator.validate(
          const RegenerateSectionCommand(
            sectionId: sectionId,
            instruction: '更口语化',
          ),
        ),
        returnsNormally,
      );
    });

    test('rejects blank titles', () {
      expect(
        () => ResourceEditCommandValidator.validate(
          const CreateSectionCommand(resourceId: resourceId, title: '   '),
        ),
        throwsA(
          isA<ResourceEditCommandException>()
              .having((error) => error.field, 'field', 'title'),
        ),
      );
    });

    test('rejects titles over the navigation-label limit', () {
      expect(
        () => ResourceEditCommandValidator.validate(
          CreateSectionCommand(
            resourceId: resourceId,
            title: 'x' * (ResourceEditCommandValidator.maxTitleLength + 1),
          ),
        ),
        throwsA(isA<ResourceEditCommandException>()),
      );
    });

    test('requires an optimistic token for every mutating command', () {
      expect(
        () => ResourceEditCommandValidator.validate(
          const RenameSectionCommand(
            sectionId: sectionId,
            title: '改名',
            expectedUpdatedAt: '',
          ),
        ),
        throwsA(
          isA<ResourceEditCommandException>().having(
            (error) => error.field,
            'field',
            'expectedUpdatedAt',
          ),
        ),
      );
      expect(
        () => ResourceEditCommandValidator.validate(
          const DeleteSectionCommand(
            sectionId: sectionId,
            expectedUpdatedAt: '',
          ),
        ),
        throwsA(isA<ResourceEditCommandException>()),
      );
    });

    test('rejects negative move indexes', () {
      expect(
        () => ResourceEditCommandValidator.validate(
          const MoveSectionCommand(
            resourceId: resourceId,
            sectionId: sectionId,
            targetIndex: -1,
            expectedUpdatedAt: token,
          ),
        ),
        throwsA(isA<ResourceEditCommandException>()),
      );
    });

    test('requires at least one field for an update', () {
      expect(
        () => ResourceEditCommandValidator.validate(
          const UpdateSectionCommand(
            sectionId: sectionId,
            expectedUpdatedAt: token,
          ),
        ),
        throwsA(isA<ResourceEditCommandException>()),
      );
      expect(
        () => ResourceEditCommandValidator.validate(
          const UpdatePartCommand(
            sectionId: sectionId,
            partId: partId,
            expectedUpdatedAt: token,
          ),
        ),
        throwsA(isA<ResourceEditCommandException>()),
      );
    });

    test('bounds Part content by the frozen Part budget', () {
      expect(
        () => ResourceEditCommandValidator.validate(
          UpdatePartCommand(
            sectionId: sectionId,
            partId: partId,
            content: 'x' * 3001,
            expectedUpdatedAt: token,
          ),
        ),
        throwsA(
          isA<ResourceEditCommandException>()
              .having((error) => error.field, 'field', 'content'),
        ),
      );
    });

    test('bounds AI instructions', () {
      expect(
        () => ResourceEditCommandValidator.validate(
          RegenerateSectionCommand(
            sectionId: sectionId,
            instruction:
                'x' * (ResourceEditCommandValidator.maxInstructionLength + 1),
          ),
        ),
        throwsA(
          isA<ResourceEditCommandException>()
              .having((error) => error.field, 'field', 'instruction'),
        ),
      );
    });
  });

  group('AiRewriteMode', () {
    test('exposes a storage value and a prompt directive', () {
      expect(AiRewriteMode.regenerate.directive, isEmpty);
      for (final mode in AiRewriteMode.values) {
        expect(mode.storageValue, isNotEmpty);
      }
      expect(AiRewriteMode.rewrite.directive, isNotEmpty);
      expect(AiRewriteMode.expand.directive, isNotEmpty);
      expect(AiRewriteMode.condense.directive, isNotEmpty);
      expect(AiRewriteMode.regenerate.replacesContent, isTrue);
      expect(AiRewriteMode.expand.replacesContent, isFalse);
    });
  });
}
