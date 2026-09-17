import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/section_control.dart';

void main() {
  group('SectionGenerationState', () {
    test('parses every stored value and rejects unknown input', () {
      for (final state in SectionGenerationState.values) {
        expect(
          SectionGenerationState.fromStorage(state.storageValue),
          state,
        );
      }
      expect(
        () => SectionGenerationState.fromStorage('bogus'),
        throwsA(isA<SectionControlException>()),
      );
      expect(
        () => SectionGenerationState.fromStorage(null),
        throwsA(isA<SectionControlException>()),
      );
    });

    test('classifies terminal, active and attention states', () {
      expect(SectionGenerationState.completed.isTerminal, isTrue);
      expect(SectionGenerationState.failed.isTerminal, isTrue);
      expect(SectionGenerationState.cancelled.isTerminal, isTrue);
      expect(SectionGenerationState.generating.isTerminal, isFalse);

      expect(SectionGenerationState.generating.isActive, isTrue);
      expect(SectionGenerationState.validating.isActive, isTrue);
      expect(SectionGenerationState.pending.isActive, isFalse);

      expect(SectionGenerationState.failed.needsAttention, isTrue);
      expect(SectionGenerationState.cancelled.needsAttention, isTrue);
      expect(SectionGenerationState.completed.needsAttention, isFalse);
    });
  });

  group('SectionValidationState', () {
    test('unknown stored values fall back to unvalidated', () {
      expect(
        SectionValidationState.fromStorage('valid'),
        SectionValidationState.valid,
      );
      expect(
        SectionValidationState.fromStorage('anything'),
        SectionValidationState.unvalidated,
      );
      expect(
        SectionValidationState.fromStorage(null),
        SectionValidationState.unvalidated,
      );
    });
  });

  group('SectionGenerationStateMachine', () {
    test('allows the documented lifecycle edges', () {
      expect(
        SectionGenerationStateMachine.canTransition(
          SectionGenerationState.pending,
          SectionGenerationState.generating,
        ),
        isTrue,
      );
      expect(
        SectionGenerationStateMachine.canTransition(
          SectionGenerationState.generating,
          SectionGenerationState.validating,
        ),
        isTrue,
      );
      expect(
        SectionGenerationStateMachine.canTransition(
          SectionGenerationState.validating,
          SectionGenerationState.completed,
        ),
        isTrue,
      );
      expect(
        SectionGenerationStateMachine.canTransition(
          SectionGenerationState.completed,
          SectionGenerationState.generating,
        ),
        isTrue,
        reason: '重新生成必须从 completed 回到 generating',
      );
      expect(
        SectionGenerationStateMachine.canTransition(
          SectionGenerationState.failed,
          SectionGenerationState.pending,
        ),
        isTrue,
      );
    });

    test('rejects illegal edges instead of silently coercing', () {
      expect(
        SectionGenerationStateMachine.canTransition(
          SectionGenerationState.pending,
          SectionGenerationState.completed,
        ),
        isFalse,
      );
      expect(
        () => SectionGenerationStateMachine.advance(
          SectionGenerationState.pending,
          SectionGenerationState.completed,
        ),
        throwsA(isA<SectionStateTransitionException>()),
      );
      expect(
        SectionGenerationStateMachine.canTransition(
          SectionGenerationState.completed,
          SectionGenerationState.failed,
        ),
        isFalse,
      );
    });

    test('self transitions stay idempotent', () {
      for (final state in SectionGenerationState.values) {
        expect(
          SectionGenerationStateMachine.advance(state, state),
          state,
        );
      }
    });
  });

  group('SectionGenerationRollup', () {
    test('returns pending when there is no task and no content', () {
      expect(
        SectionGenerationRollup.fromTaskStatuses(
          const <String>[],
          hasContent: false,
        ),
        SectionGenerationState.pending,
      );
    });

    test('returns generated for hand-authored content without tasks', () {
      expect(
        SectionGenerationRollup.fromTaskStatuses(
          const <String>[],
          hasContent: true,
        ),
        SectionGenerationState.generated,
      );
    });

    test('prioritises active work over failures', () {
      expect(
        SectionGenerationRollup.fromTaskStatuses(
          const ['failed', 'generating'],
          hasContent: true,
        ),
        SectionGenerationState.generating,
      );
      expect(
        SectionGenerationRollup.fromTaskStatuses(
          const ['failed', 'validating'],
          hasContent: true,
        ),
        SectionGenerationState.validating,
      );
    });

    test('reports failure, cancellation, pending and completion', () {
      expect(
        SectionGenerationRollup.fromTaskStatuses(
          const ['completed', 'failed'],
          hasContent: true,
        ),
        SectionGenerationState.failed,
      );
      expect(
        SectionGenerationRollup.fromTaskStatuses(
          const ['completed', 'cancelled'],
          hasContent: true,
        ),
        SectionGenerationState.cancelled,
      );
      expect(
        SectionGenerationRollup.fromTaskStatuses(
          const ['completed', 'ready'],
          hasContent: true,
        ),
        SectionGenerationState.pending,
      );
      expect(
        SectionGenerationRollup.fromTaskStatuses(
          const ['completed', 'completed'],
          hasContent: true,
        ),
        SectionGenerationState.completed,
      );
    });
  });

  group('SectionContentValidator', () {
    const sectionId = SectionId('sec_1');

    test('rejects a section with no Parts', () {
      final result = SectionContentValidator.validate(
        sectionId: sectionId,
        parts: const [],
      );
      expect(result.state, SectionValidationState.invalid);
      expect(result.issues, hasLength(1));
      expect(result.isValid, isFalse);
    });

    test('rejects Parts that have no body yet', () {
      final result = SectionContentValidator.validate(
        sectionId: sectionId,
        parts: const [
          SectionValidationPart(
            partId: PartId('p1'),
            title: '开头',
            content: '',
          ),
          SectionValidationPart(
            partId: PartId('p2'),
            title: '结尾',
            content: '有内容',
          ),
        ],
      );
      expect(result.state, SectionValidationState.invalid);
      expect(result.issues.single.partId, const PartId('p1'));
      expect(result.characterCount, '有内容'.length);
    });

    test('flags Part bodies over the frozen character budget', () {
      final result = SectionContentValidator.validate(
        sectionId: sectionId,
        parts: [
          SectionValidationPart(
            partId: const PartId('p1'),
            title: '过长',
            content: 'x' * 3001,
          ),
        ],
      );
      expect(result.state, SectionValidationState.invalid);
      expect(result.issues.single.tooLong, isTrue);
    });

    test('accepts a complete section', () {
      final result = SectionContentValidator.validate(
        sectionId: sectionId,
        parts: const [
          SectionValidationPart(
            partId: PartId('p1'),
            title: '开头',
            content: '完整正文',
          ),
        ],
      );
      expect(result.state, SectionValidationState.valid);
      expect(result.isValid, isTrue);
      expect(result.characterCount, 4);
    });
  });

  group('SectionControlEntry', () {
    test('exposes derived flags and preserves the locking token', () {
      const entry = SectionControlEntry(
        id: SectionId('sec_1'),
        resourceId: ResourceId('res_1'),
        title: '章节',
        orderIndex: 0,
        content: '正文',
        partCount: 1,
        updatedAtToken: 'token-1',
        generationState: SectionGenerationState.generating,
      );
      expect(entry.hasContent, isTrue);
      expect(entry.isBusy, isTrue);
      expect(entry.needsAttention, isFalse);

      final renamed = entry.copyWith(title: '新章节');
      expect(renamed.title, '新章节');
      expect(renamed.updatedAtToken, 'token-1');
      expect(renamed.id, entry.id);
    });

    test('page reports bounded progress', () {
      const page = SectionControlPage(
        entries: [],
        totalCount: 42,
        offset: 20,
      );
      expect(page.isEmpty, isTrue);
      expect(page.loadedThrough, 20);
      expect(page.hasMore, isTrue);
    });
  });
}
