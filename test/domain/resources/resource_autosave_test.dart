import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/resource_autosave.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';

ResourceAutosaveDraft _draft({
  String checkpointId = 'auto_1',
  String partId = 'part_1',
  String content = '草稿正文',
  String baseUpdatedAt = 'tok_0',
}) =>
    ResourceAutosaveDraft(
      checkpointId: checkpointId,
      resourceId: const ResourceId('res_1'),
      partId: PartId(partId),
      content: content,
      contentHash: 'hash_$content',
      baseUpdatedAt: baseUpdatedAt,
      createdAtToken: '2026-09-17T00:00:00.000',
      updatedAtToken: '2026-09-17T00:00:00.000',
    );

void main() {
  group('AutosavePolicy', () {
    test('debounces input instead of writing per keystroke', () {
      expect(
        AutosavePolicy.debounce,
        greaterThan(const Duration(milliseconds: 200)),
        reason: 'a debounce shorter than human typing would defeat the purpose',
      );
    });

    test('caps how long an edit may stay only in memory', () {
      expect(AutosavePolicy.maxBufferedAge, greaterThan(Duration.zero));
      expect(
        AutosavePolicy.maxBufferedAge,
        greaterThan(AutosavePolicy.debounce),
        reason: 'a continuous typist must still be checkpointed, but not so '
            'often that the debounce stops mattering',
      );
    });
  });

  group('ResourceAutosaveDraft', () {
    test('withContent keeps identity and base token', () {
      final original = _draft();
      final updated = original.withContent(
        content: '新的草稿正文',
        contentHash: 'hash_新的草稿正文',
        updatedAtToken: '2026-09-17T00:00:05.000',
      );

      expect(updated.checkpointId, original.checkpointId);
      expect(updated.partId, original.partId);
      expect(updated.resourceId, original.resourceId);
      expect(
        updated.baseUpdatedAt,
        original.baseUpdatedAt,
        reason: 'the token the edit was typed against must survive so a '
            'conflicting write can still be detected',
      );
      expect(updated.content, '新的草稿正文');
      expect(updated.createdAtToken, original.createdAtToken);
      expect(updated.updatedAtToken, '2026-09-17T00:00:05.000');
    });
  });

  group('AutosaveRecoveryDisposition', () {
    test('classifies an already-applied draft as resolved', () {
      const outcome = AutosaveRecoveryOutcome(
        draft: ResourceAutosaveDraft(
          checkpointId: 'auto_1',
          resourceId: ResourceId('res_1'),
          partId: PartId('part_1'),
          content: '正文',
          contentHash: 'h',
          baseUpdatedAt: 'tok',
        ),
        disposition: AutosaveRecoveryDisposition.alreadyApplied,
      );
      expect(outcome.isResolved, isTrue);
    });

    test('keeps a genuinely newer draft for the user to decide', () {
      const outcome = AutosaveRecoveryOutcome(
        draft: ResourceAutosaveDraft(
          checkpointId: 'auto_1',
          resourceId: ResourceId('res_1'),
          partId: PartId('part_1'),
          content: '正文',
          contentHash: 'h',
          baseUpdatedAt: 'tok',
        ),
        disposition: AutosaveRecoveryDisposition.needsUserDecision,
        liveContentHash: 'other',
      );
      expect(
        outcome.isResolved,
        isFalse,
        reason: 'dropping this would silently discard user text',
      );
    });

    test('drops a draft whose target is gone', () {
      const outcome = AutosaveRecoveryOutcome(
        draft: ResourceAutosaveDraft(
          checkpointId: 'auto_1',
          resourceId: ResourceId('res_1'),
          partId: PartId('part_1'),
          content: '正文',
          contentHash: 'h',
          baseUpdatedAt: 'tok',
        ),
        disposition: AutosaveRecoveryDisposition.orphaned,
      );
      expect(outcome.isResolved, isTrue);
    });

    test('every disposition has an explanation for the UI', () {
      for (final disposition in AutosaveRecoveryDisposition.values) {
        expect(disposition.displayLabel.trim(), isNotEmpty);
      }
    });
  });
}
