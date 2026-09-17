import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/resource_capacity.dart';
import 'package:lt_dialogue/domain/resources/resource_compression.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_limits.dart';

ResourceCapacitySnapshot capacity({
  required int total,
  ResourceType type = ResourceType.worldview,
  int sectionCount = 1,
  int partCount = 1,
}) {
  return ResourceCapacitySnapshot(
    resourceId: const ResourceId('res_1'),
    type: type,
    totalCharacters: total,
    activeCharacters: total,
    archivedCharacters: 0,
    estimatedTokens: ResourceCapacityMath.tokensForCharacters(total),
    sectionCount: sectionCount,
    partCount: partCount,
    historicalRevisionCount: 0,
    status: ResourceCapacityMath.statusFor(type, total),
  );
}

void main() {
  group('CompressionJobStateMachine', () {
    // Independent oracle: the expected edges are written literally here rather
    // than derived from the production table, so relaxing a production edge
    // cannot silently pass.
    const expected = <CompressionJobStatus, Set<CompressionJobStatus>>{
      CompressionJobStatus.queued: {
        CompressionJobStatus.queued,
        CompressionJobStatus.running,
        CompressionJobStatus.cancelled,
      },
      CompressionJobStatus.running: {
        CompressionJobStatus.running,
        CompressionJobStatus.succeeded,
        CompressionJobStatus.failed,
        CompressionJobStatus.cancelled,
      },
      CompressionJobStatus.failed: {
        CompressionJobStatus.failed,
        CompressionJobStatus.queued,
        CompressionJobStatus.cancelled,
      },
      CompressionJobStatus.cancelled: {
        CompressionJobStatus.cancelled,
        CompressionJobStatus.queued,
      },
      CompressionJobStatus.succeeded: {CompressionJobStatus.succeeded},
    };

    test('the production table equals the literal oracle', () {
      expect(CompressionJobStateMachine.transitions, expected);
    });

    test('accepts legal edges and rejects illegal ones', () {
      expect(
        CompressionJobStateMachine.canTransition(
          CompressionJobStatus.queued,
          CompressionJobStatus.running,
        ),
        isTrue,
      );
      expect(
        CompressionJobStateMachine.canTransition(
          CompressionJobStatus.succeeded,
          CompressionJobStatus.running,
        ),
        isFalse,
        reason: 'a succeeded job is terminal',
      );
      expect(
        () => CompressionJobStateMachine.advance(
          CompressionJobStatus.succeeded,
          CompressionJobStatus.running,
        ),
        throwsA(isA<ResourceStateTransitionException>()),
      );
    });

    test('a failed job only returns through queued', () {
      expect(
        CompressionJobStateMachine.canTransition(
          CompressionJobStatus.failed,
          CompressionJobStatus.running,
        ),
        isFalse,
        reason: 'retry must pass through the queue, never jump to running',
      );
      expect(
        CompressionJobStateMachine.canTransition(
          CompressionJobStatus.failed,
          CompressionJobStatus.queued,
        ),
        isTrue,
      );
    });
  });

  group('CompressionJob', () {
    CompressionJob job({
      CompressionJobStatus status = CompressionJobStatus.queued,
      int attempts = 0,
      int maxAttempts = ResourceLimits.maxCompressionAttempts,
    }) =>
        CompressionJob(
          jobId: 'job_1',
          resourceId: const ResourceId('res_1'),
          scope: CompressionScope.section,
          targetNodeId: 'sec_1',
          sourceToken: 'token_a',
          status: status,
          attempts: attempts,
          maxAttempts: maxAttempts,
        );

    test('dedup identity covers resource, scope, target and version', () {
      expect(job().dedupKey, 'res_1|section|sec_1|token_a');
    });

    test('canRetry is bounded by the attempt budget', () {
      expect(job(status: CompressionJobStatus.failed, attempts: 0).canRetry,
          isTrue);
      expect(
        job(
          status: CompressionJobStatus.failed,
          attempts: ResourceLimits.maxCompressionAttempts,
        ).canRetry,
        isFalse,
        reason: 'the retry budget is what prevents an infinite retry loop',
      );
    });

    test('a queued job is active and a succeeded job is terminal', () {
      expect(job().isActive, isTrue);
      expect(job(status: CompressionJobStatus.succeeded).isActive, isFalse);
      expect(
        job(status: CompressionJobStatus.succeeded).status.isTerminal,
        isTrue,
      );
    });
  });

  group('CompressionBudget', () {
    test('targets a fraction of the input and always stays smaller', () {
      expect(CompressionBudget.nodeTargetCharacters(1000), 600);
      expect(CompressionBudget.nodeTargetCharacters(1000), lessThan(1000));
    });

    test('never asks for an empty or unchanged result', () {
      expect(CompressionBudget.nodeTargetCharacters(0), 0);
      expect(CompressionBudget.nodeTargetCharacters(1), 1);
      expect(CompressionBudget.nodeTargetCharacters(2), 1);
    });
  });

  group('CompressionTriggers.evaluateResource', () {
    test('overflow triggers with the nominal budget as target', () {
      final decision = CompressionTriggers.evaluateResource(
        capacity: capacity(total: 60001),
      );
      expect(decision.shouldCompress, isTrue);
      expect(decision.reason, CompressionTriggerReason.capacityOverflow);
      expect(
          decision.targetCharacters, ResourceLimits.worldviewNominalCharacters);
    });

    test('the elastic band triggers opportunistically', () {
      final decision = CompressionTriggers.evaluateResource(
        capacity: capacity(total: 50001),
      );
      expect(decision.shouldCompress, isTrue);
      expect(decision.reason, CompressionTriggerReason.capacityElastic);
    });

    test('the exact nominal boundary does not trigger', () {
      final decision = CompressionTriggers.evaluateResource(
        capacity: capacity(total: 50000),
      );
      expect(decision.shouldCompress, isFalse);
      expect(decision.reason, CompressionTriggerReason.none);
    });

    test('thresholds are configurable', () {
      const tight = CompressionThresholds(fillRatio: 0.25);
      final decision = CompressionTriggers.evaluateResource(
        capacity: capacity(total: 20000),
        thresholds: tight,
      );
      expect(decision.shouldCompress, isTrue,
          reason: '20,000/60,000 exceeds a 0.25 fill ratio');
    });
  });

  group('CompressionTriggers.evaluateContext', () {
    test('triggers above the context token limit', () {
      final decision = CompressionTriggers.evaluateContext(
        contextTokens: ResourceLimits.compressionTriggerContextTokens + 1,
      );
      expect(decision.shouldCompress, isTrue);
      expect(decision.reason, CompressionTriggerReason.contextBudgetExceeded);
    });

    test('does not trigger at exactly the limit', () {
      expect(
        CompressionTriggers.evaluateContext(
          contextTokens: ResourceLimits.compressionTriggerContextTokens,
        ).shouldCompress,
        isFalse,
      );
    });
  });

  group('CompressionTriggers.selectSectionTargets', () {
    SectionCapacitySnapshot section(String id, int characters,
            {bool complete = true}) =>
        SectionCapacitySnapshot(
          sectionId: SectionId(id),
          title: id,
          characters: characters,
          partCount: 2,
          largestPartCharacters: characters,
          isComplete: complete,
        );

    test('ranks bigger sections first and skips small or incomplete ones', () {
      final targets = CompressionTriggers.selectSectionTargets(
        sections: [
          section(
              'sec_small', ResourceLimits.minCompressibleNodeCharacters - 1),
          section('sec_mid', 2000),
          section('sec_big', 9000),
          section('sec_incomplete', 9000, complete: false),
        ],
      );
      expect(targets.map((s) => s.sectionId.value), ['sec_big', 'sec_mid']);
    });

    test('caps the number of targets so one sweep stays bounded', () {
      final targets = CompressionTriggers.selectSectionTargets(
        sections: [
          for (var i = 0; i < 20; i++) section('sec_$i', 1000 + i),
        ],
        maxTargets: 3,
      );
      expect(targets, hasLength(3));
      expect(targets.first.sectionId.value, 'sec_19');
    });

    test('a non-positive cap yields no targets', () {
      expect(
        CompressionTriggers.selectSectionTargets(
          sections: [section('sec_a', 5000)],
          maxTargets: 0,
        ),
        isEmpty,
      );
    });
  });

  group('CompressionValidator', () {
    const original = '赤焰城的艾琳与黑铁团的卡尔在第三纪元 120 年结盟，'
        '共同守卫北境要塞。盟约规定双方每年互派三十名骑士。';

    test('passes when every declared item is present', () {
      final result = CompressionValidator.validate(
        originalContent: original,
        compressedContent: '第三纪元 120 年，艾琳与卡尔结盟，每年互派三十名骑士守卫北境要塞。',
        retention: const CompressionRetention(
          entities: ['艾琳', '卡尔', '北境要塞'],
          relationships: ['艾琳→卡尔'],
          timeline: ['第三纪元 120 年'],
        ),
        targetCharacters: 40,
      );
      expect(result.isValid, isTrue, reason: result.message);
    });

    test('fails on empty content', () {
      final result = CompressionValidator.validate(
        originalContent: original,
        compressedContent: '   ',
        retention: CompressionRetention.empty,
        targetCharacters: 40,
      );
      expect(result.isValid, isFalse);
      expect(result.issues.single.code, CompressionIssueCode.emptyResult);
    });

    test('fails when nothing was actually compressed', () {
      final result = CompressionValidator.validate(
        originalContent: original,
        compressedContent: original,
        retention: CompressionRetention.empty,
        targetCharacters: 40,
      );
      expect(
        result.issues.map((issue) => issue.code),
        contains(CompressionIssueCode.notCompressed),
      );
    });

    test('fails when the result exceeds its budget', () {
      final result = CompressionValidator.validate(
        originalContent: original,
        compressedContent: '这是一段足够长但依然超过预算的压缩结果文本',
        retention: CompressionRetention.empty,
        targetCharacters: 5,
      );
      expect(
        result.issues.map((issue) => issue.code),
        contains(CompressionIssueCode.overBudget),
      );
    });

    test('fails when a required name is lost', () {
      final result = CompressionValidator.validate(
        originalContent: original,
        compressedContent: '两位领袖在很久以前结盟，守卫要塞。',
        retention: CompressionRetention.empty,
        targetCharacters: 40,
        requiredTerms: const ['赤焰城'],
      );
      expect(
        result.issues.map((issue) => issue.code),
        contains(CompressionIssueCode.missingRequiredTerm),
      );
    });

    test('fails when a declared entity is lost', () {
      final result = CompressionValidator.validate(
        originalContent: original,
        compressedContent: '艾琳与卡尔结盟，守卫北境要塞。',
        retention: const CompressionRetention(entities: ['黑铁团']),
        targetCharacters: 40,
      );
      expect(
        result.issues.map((issue) => issue.code),
        contains(CompressionIssueCode.missingEntity),
      );
    });

    test('fails when one side of a relationship is lost', () {
      final result = CompressionValidator.validate(
        originalContent: original,
        compressedContent: '艾琳独自守卫北境要塞，第三纪元 120 年结盟。',
        retention: const CompressionRetention(relationships: ['艾琳→卡尔']),
        targetCharacters: 40,
      );
      final issue = result.issues.firstWhere(
        (issue) => issue.code == CompressionIssueCode.missingRelationship,
      );
      expect(issue.message, contains('卡尔'));
    });

    test('fails when a timeline fact loses its numeric marker', () {
      final result = CompressionValidator.validate(
        originalContent: original,
        compressedContent: '第三纪元，艾琳与卡尔结盟并守卫北境要塞。',
        retention: const CompressionRetention(timeline: ['第三纪元 120 年']),
        targetCharacters: 40,
      );
      expect(
        result.issues.map((issue) => issue.code),
        contains(CompressionIssueCode.missingTimelineFact),
      );
    });

    test('accepts a rephrased timeline fact when its numbers survive', () {
      final result = CompressionValidator.validate(
        originalContent: original,
        compressedContent: '纪元 120 年，艾琳与卡尔结盟守卫北境要塞。',
        retention: const CompressionRetention(timeline: ['第三纪元 120 年']),
        targetCharacters: 40,
      );
      expect(result.isValid, isTrue, reason: result.message);
    });
  });

  group('CompressionScope', () {
    test('parses known values and rejects unknown ones', () {
      expect(CompressionScope.fromStorage('part'), CompressionScope.part);
      expect(CompressionScope.fromStorage('section'), CompressionScope.section);
      expect(
        () => CompressionScope.fromStorage('whole-resource'),
        throwsA(isA<ResourceContractException>()),
      );
    });
  });

  group('CompressionCandidate', () {
    test('reports its ratio and savings and is never applied by Phase 8', () {
      const candidate = CompressionCandidate(
        candidateId: 'c1',
        jobId: 'j1',
        resourceId: ResourceId('res_1'),
        scope: CompressionScope.section,
        targetNodeId: 'sec_1',
        originalCharacters: 1000,
        compressedCharacters: 400,
        compressedContent: '压缩正文',
        retention: CompressionRetention.empty,
        isValidated: true,
      );
      expect(candidate.compressionRatio, 0.4);
      expect(candidate.savedCharacters, 600);
      expect(candidate.isCandidateOnly, isTrue);
    });
  });
}
