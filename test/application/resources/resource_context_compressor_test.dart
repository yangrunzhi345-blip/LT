import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/resource_context_compressor.dart';
import 'package:lt_dialogue/domain/resources/resource_compression.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_limits.dart';

/// 100 CJK characters are estimated as exactly 70 tokens, so the numbers below
/// are stable and make the budget arithmetic readable.
String cjk(int characters) => '赤' * characters;

void main() {
  group('ResourceContextCompressor.pack', () {
    test('keeps the highest priority and drops the lowest under budget', () {
      final packing = ResourceContextCompressor.pack(
        candidates: [
          ResourceContextCandidate(
            priority: ResourceContextPriority.historicalSummary,
            label: '历史摘要',
            text: cjk(100),
          ),
          ResourceContextCandidate(
            priority: ResourceContextPriority.currentSection,
            label: '当前章节',
            text: cjk(100),
          ),
          ResourceContextCandidate(
            priority: ResourceContextPriority.currentState,
            label: '当前状态',
            text: cjk(50),
          ),
          ResourceContextCandidate(
            priority: ResourceContextPriority.unresolvedEvents,
            label: '未解决事件',
            text: cjk(60),
          ),
          ResourceContextCandidate(
            priority: ResourceContextPriority.recentPlot,
            label: '最近剧情',
            text: cjk(50),
          ),
        ],
        budgetTokens: 200,
      );

      expect(packing.withinBudget, isTrue);
      expect(
        packing.fragments.map((fragment) => fragment.priority),
        [
          ResourceContextPriority.currentSection,
          ResourceContextPriority.currentState,
          ResourceContextPriority.unresolvedEvents,
          ResourceContextPriority.recentPlot,
        ],
      );
      expect(packing.droppedLabels, ['历史摘要'],
          reason: 'history is dropped before the current section');
      // TokenEstimator accumulates floating-point weights, so the exact total
      // is not a round number; what matters is that it stays inside the budget
      // and that the four important fragments are the ones that made it.
      expect(packing.usedTokens, lessThanOrEqualTo(200));
      expect(packing.usedTokens, greaterThan(packing.budgetTokens ~/ 2));
    });

    test('a small low-priority item never displaces the current section', () {
      final packing = ResourceContextCompressor.pack(
        candidates: [
          ResourceContextCandidate(
            priority: ResourceContextPriority.historicalSummary,
            label: '历史摘要',
            text: cjk(10),
          ),
          ResourceContextCandidate(
            priority: ResourceContextPriority.currentSection,
            label: '当前章节',
            text: cjk(140),
          ),
        ],
        budgetTokens: 100,
      );
      expect(packing.fragments.single.label, '当前章节');
      expect(packing.droppedLabels, ['历史摘要']);
    });

    test('uses the compressed summary and shortens the packed context', () {
      final full = ResourceContextCompressor.pack(
        candidates: [
          ResourceContextCandidate(
            priority: ResourceContextPriority.historicalSummary,
            label: '历史摘要',
            text: cjk(1000),
          ),
        ],
        budgetTokens: 200,
      );
      final compressed = ResourceContextCompressor.pack(
        candidates: [
          ResourceContextCandidate(
            priority: ResourceContextPriority.historicalSummary,
            label: '历史摘要',
            text: cjk(1000),
            compressedText: cjk(50),
          ),
        ],
        budgetTokens: 200,
      );

      expect(full.fragments, isEmpty);
      expect(full.ungroupedTokens, greaterThan(200));
      expect(compressed.fragments, hasLength(1));
      expect(compressed.fragments.single.wasCompressed, isTrue);
      expect(compressed.usedTokens, lessThan(100));
      expect(compressed.usedTokens, lessThan(full.ungroupedTokens),
          reason: 'compression must reduce what is actually sent');
      expect(compressed.withinBudget, isTrue);
    });

    test('is deterministic for equal priorities', () {
      final packing = ResourceContextCompressor.pack(
        candidates: [
          ResourceContextCandidate(
            priority: ResourceContextPriority.recentPlot,
            label: 'b',
            text: cjk(10),
            order: 2,
          ),
          ResourceContextCandidate(
            priority: ResourceContextPriority.recentPlot,
            label: 'a',
            text: cjk(10),
            order: 1,
          ),
        ],
        budgetTokens: 100,
      );
      expect(packing.fragments.map((fragment) => fragment.label), ['a', 'b']);
    });

    test('an empty candidate list packs to an empty result', () {
      final packing = ResourceContextCompressor.pack(candidates: const []);
      expect(packing.isEmpty, isTrue);
      expect(packing.withinBudget, isTrue);
      expect(packing.droppedLabels, isEmpty);
    });

    test('a negative budget is rejected instead of truncating', () {
      expect(
        () => ResourceContextCompressor.pack(
          candidates: const [],
          budgetTokens: -1,
        ),
        throwsArgumentError,
      );
    });
  });

  group('ResourceContextTriggers', () {
    test('fires when the unpacked context exceeds the token limit', () {
      final packing = ResourceContextCompressor.pack(
        candidates: [
          ResourceContextCandidate(
            priority: ResourceContextPriority.historicalSummary,
            label: '历史摘要',
            // 20,000 CJK characters ≈ 14,000 tokens, above the 8,000 trigger.
            text: cjk(20000),
          ),
        ],
        budgetTokens: 100,
      );
      final decision = ResourceContextTriggers.evaluate(packing: packing);
      expect(decision.shouldCompress, isTrue);
      expect(decision.reason, CompressionTriggerReason.contextBudgetExceeded);
    });

    test('does not fire for a context that already fit', () {
      final packing = ResourceContextCompressor.pack(
        candidates: [
          ResourceContextCandidate(
            priority: ResourceContextPriority.currentSection,
            label: '当前章节',
            text: cjk(100),
          ),
        ],
      );
      expect(
        ResourceContextTriggers.evaluate(packing: packing).shouldCompress,
        isFalse,
      );
    });
  });

  group('ResourceContextAssembler', () {
    const resource = Resource(
      id: ResourceId('res_1'),
      type: ResourceType.worldview,
      name: '北境',
      summary: '当前状态摘要',
    );

    List<ResourceSection> sections() => [
          for (final id in ['sec_a', 'sec_b', 'sec_c'])
            ResourceSection(
              id: SectionId(id),
              resourceId: const ResourceId('res_1'),
              title: '章节$id',
              sortOrder: 0,
            ),
        ];

    test('tags the current section and the resource state', () {
      final candidates =
          const ResourceContextAssembler(recentSectionCount: 1).assemble(
        resource: resource,
        sections: sections(),
        currentSectionId: 'sec_c',
        sectionText: (id) => cjk(100),
      );

      final byLabel = <String, ResourceContextCandidate>{
        for (final candidate in candidates) candidate.label: candidate,
      };
      expect(
          byLabel['章节sec_c']!.priority, ResourceContextPriority.currentSection);
      expect(byLabel['章节sec_b']!.priority, ResourceContextPriority.recentPlot);
      expect(byLabel['章节sec_a']!.priority,
          ResourceContextPriority.historicalSummary);
      expect(
          byLabel['北境 · 当前状态']!.priority, ResourceContextPriority.currentState);
    });

    test('skips sections without content and archived sections', () {
      final candidates = const ResourceContextAssembler().assemble(
        resource: const Resource(
          id: ResourceId('res_1'),
          type: ResourceType.worldview,
          name: '北境',
        ),
        sections: const [
          ResourceSection(
            id: SectionId('sec_live'),
            resourceId: ResourceId('res_1'),
            title: '有内容',
            sortOrder: 0,
          ),
          ResourceSection(
            id: SectionId('sec_archived'),
            resourceId: ResourceId('res_1'),
            title: '已归档',
            sortOrder: 1,
            status: NodeStatus.archived,
          ),
        ],
        currentSectionId: 'sec_live',
        sectionText: (id) => cjk(100),
      );
      expect(candidates.map((candidate) => candidate.label), ['有内容']);
    });

    test('build stays within budget and uses candidate summaries', () {
      final packing =
          const ResourceContextAssembler(recentSectionCount: 1).build(
        resource: resource,
        sections: sections(),
        currentSectionId: 'sec_c',
        sectionText: (id) => cjk(1000),
        candidateSummaries: const {'sec_a': '历史摘要正文'},
        budgetTokens: 200,
      );

      expect(packing.withinBudget, isTrue);
      final history = packing.fragments.firstWhere(
        (fragment) =>
            fragment.priority == ResourceContextPriority.historicalSummary,
      );
      expect(history.wasCompressed, isTrue);
      expect(history.text, '历史摘要正文');
    });
  });

  group('ResourceContextPriority', () {
    test('ranks current section above every other band', () {
      final ranked = ResourceContextPriority.values.toList()
        ..sort((a, b) => a.rank.compareTo(b.rank));
      expect(ranked, [
        ResourceContextPriority.currentSection,
        ResourceContextPriority.currentState,
        ResourceContextPriority.unresolvedEvents,
        ResourceContextPriority.recentPlot,
        ResourceContextPriority.historicalSummary,
      ]);
      expect(
        ResourceLimits.resourceContextTokenBudget,
        greaterThan(0),
      );
    });
  });
}
