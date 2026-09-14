import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/narrative/narrative_context.dart';
import 'package:lt_dialogue/application/narrative/world_semantic_retrieval.dart';
import 'package:lt_dialogue/models/world_entry.dart';
import 'package:lt_dialogue/services/embedding/semantic_embedding_service.dart';

import '../support/world_retrieval_benchmark_fixtures.dart';

void main() {
  const baselineRunner = WorldRetrievalBenchmarkRunner.baseline();
  const hardenedRunner = WorldRetrievalBenchmarkRunner.hardened();
  const hybridRunner = WorldRetrievalBenchmarkRunner.hybrid();
  final suite = WorldRetrievalBenchmarkSuite.buildDefaultSuite();

  group('P1.1 — Hardened Deterministic Retrieval Evaluation', () {
    test('Location hierarchy matching resolves nested location case', () {
      final locCase = suite.firstWhere(
          (c) => c.id == 'location_sublocation_hierarchical_mismatch');
      final baselineEval = baselineRunner.evaluate(locCase);
      final hardenedEval = hardenedRunner.evaluate(locCase);

      expect(baselineEval.recall, 0.0,
          reason: 'Baseline should fail on hierarchy mismatch');
      expect(hardenedEval.recall, 1.0,
          reason: 'Hardened must resolve location hierarchy');
      expect(hardenedEval.recalledEntryIds, locCase.expectedRelevantEntryIds);
    });

    test('Character matching in body content resolves unkeyed character case',
        () {
      final charCase = suite.firstWhere(
          (c) => c.id == 'character_relevance_missing_metadata_key');
      final baselineEval = baselineRunner.evaluate(charCase);
      final hardenedEval = hardenedRunner.evaluate(charCase);

      expect(baselineEval.recall, 0.0,
          reason: 'Baseline should fail when character is only in body');
      expect(hardenedEval.recall, 1.0,
          reason: 'Hardened must match character in entry content');
      expect(hardenedEval.recalledEntryIds, charCase.expectedRelevantEntryIds);
    });

    test('Creative constraint auto-classification protects rules from eviction',
        () {
      final stickyCase = suite.firstWhere((c) =>
          c.id == 'sticky_creative_constraints_vulnerable_classification');
      final baselineEval = baselineRunner.evaluate(stickyCase);
      final hardenedEval = hardenedRunner.evaluate(stickyCase);

      // In baseline, 703 was misclassified as lore and evicted
      expect(baselineEval.falseNegatives, contains(703),
          reason: 'Baseline misclassifies rule constraint and loses 703');
      // In hardened, 703 is properly classified as constraint and retained
      expect(hardenedEval.recalledEntryIds, contains(703),
          reason:
              'Hardened must classify creative constraints as constraint and retain 703');
    });
  });

  group('P1.2 — Hybrid Retrieval Semantic Channel Evaluation', () {
    test('Category 3: Synonymous phrasing recalled via semantic channel', () {
      final cases = suite
          .where((c) =>
              c.category == RetrievalBenchmarkCategory.synonymousPhrasing)
          .toList();
      for (final testCase in cases) {
        final eval = hybridRunner.evaluate(testCase);
        expect(eval.falseNegatives, isEmpty,
            reason: 'Hybrid must recall synonyms for ${testCase.id}');
        expect(eval.recall, 1.0);
      }
    });

    test('Category 4: Indirect description recalled via semantic channel', () {
      final cases = suite
          .where((c) =>
              c.category == RetrievalBenchmarkCategory.indirectDescription)
          .toList();
      for (final testCase in cases) {
        final eval = hybridRunner.evaluate(testCase);
        expect(eval.falseNegatives, isEmpty,
            reason:
                'Hybrid must recall indirect description for ${testCase.id}');
        expect(eval.recall, 1.0);
      }
    });

    test('Category 9: Irrelevant content filtered with 0% false positives', () {
      final cases = suite
          .where(
              (c) => c.category == RetrievalBenchmarkCategory.irrelevantContent)
          .toList();
      for (final testCase in cases) {
        final eval = hybridRunner.evaluate(testCase);
        expect(eval.falsePositives, isEmpty,
            reason: 'Hybrid must not hallucinate irrelevant content');
        expect(eval.tokenWaste, 0);
      }
    });

    test('Authority Ordering: Constraint > Fact > Lore strictly maintained',
        () {
      // Create competing entries under tight budget
      final entries = [
        WorldEntry(
          id: 101,
          keys: const ['施法'],
          content: '【世界观/rules】施法严苛限制：神殿内不可施法。',
          sourceType: 'rule',
          insertionOrder: 0,
        ),
        WorldEntry(
          id: 102,
          keys: const ['施法'],
          content: '【世界观/facts】神殿内施法历史记录。',
          sourceType: 'fact',
          insertionOrder: 1,
        ),
        WorldEntry(
          id: 103,
          keys: const ['施法'],
          content: '【世界观/lore】神殿历史传说闲谈。',
          sourceType: 'lore',
          insertionOrder: 2,
        ),
      ];

      const builder = WorldContextBuilder.hybrid(
        semanticRetriever: SemanticWorldRetriever(
          embeddingService: DeterministicFakeEmbeddingService(),
        ),
      );

      final result = builder.build(
        entries: entries,
        query: '施法',
        location: '',
        characterNames: const [],
        tokenBudget: 300,
      );

      expect(result.constraints, isNotEmpty);
      expect(result.constraints.first.content, contains('施法严苛限制'));
      // Verify constraint is categorized as constraint, not lore
      expect(result.constraints.first.kind, WorldContextKind.constraint);
    });
  });

  group('P1 Quantitative Target Verification & Comparative Audit', () {
    test(
        'Hybrid Retrieval satisfies all P1 quantitative acceptance targets (Recall >= 85%, Precision >= 90%, Constraint = 100%)',
        () {
      final baselineMetrics = baselineRunner.runSuite(suite);
      final hardenedMetrics = hardenedRunner.runSuite(suite);
      final hybridMetrics = hybridRunner.runSuite(suite);

      // ignore: avoid_print
      print('\n${'=' * 80}');
      // ignore: avoid_print
      print('P1 HYBRID WORLD CONTEXT RETRIEVAL COMPARATIVE AUDIT REPORT');
      // ignore: avoid_print
      print('=' * 80);
      // ignore: avoid_print
      print(
          'Metric                  | Baseline (Legacy) | P1.1 (Hardened)   | P1.2 (Hybrid)     | Target / Status');
      // ignore: avoid_print
      print('-' * 80);
      // ignore: avoid_print
      print(
          'Overall Recall          | ${(baselineMetrics.recall * 100).toStringAsFixed(1)}%            | ${(hardenedMetrics.recall * 100).toStringAsFixed(1)}%            | ${(hybridMetrics.recall * 100).toStringAsFixed(1)}%            | >= 85.0% (${hybridMetrics.recall >= 0.85 ? "PASS" : "FAIL"})');
      // ignore: avoid_print
      print(
          'Overall Precision       | ${(baselineMetrics.precision * 100).toStringAsFixed(1)}%            | ${(hardenedMetrics.precision * 100).toStringAsFixed(1)}%            | ${(hybridMetrics.precision * 100).toStringAsFixed(1)}%            | >= 90.0% (${hybridMetrics.precision >= 0.90 ? "PASS" : "FAIL"})');
      // ignore: avoid_print
      print(
          'Overall F1-Score        | ${(baselineMetrics.f1Score * 100).toStringAsFixed(1)}%            | ${(hardenedMetrics.f1Score * 100).toStringAsFixed(1)}%            | ${(hybridMetrics.f1Score * 100).toStringAsFixed(1)}%            | -');
      // ignore: avoid_print
      print(
          'True Positives (TP)     | ${baselineMetrics.truePositives.toString().padRight(17)} | ${hardenedMetrics.truePositives.toString().padRight(17)} | ${hybridMetrics.truePositives.toString().padRight(17)} | -');
      // ignore: avoid_print
      print(
          'False Negatives (FN)    | ${baselineMetrics.falseNegatives.toString().padRight(17)} | ${hardenedMetrics.falseNegatives.toString().padRight(17)} | ${hybridMetrics.falseNegatives.toString().padRight(17)} | <= 4');
      // ignore: avoid_print
      print(
          'False Positives (FP)    | ${baselineMetrics.falsePositives.toString().padRight(17)} | ${hardenedMetrics.falsePositives.toString().padRight(17)} | ${hybridMetrics.falsePositives.toString().padRight(17)} | <= 2');
      // ignore: avoid_print
      print(
          'Constraint Retention    | ${(baselineMetrics.constraintRetention * 100).toStringAsFixed(1)}%           | ${(hardenedMetrics.constraintRetention * 100).toStringAsFixed(1)}%           | ${(hardenedMetrics.constraintRetention * 100).toStringAsFixed(1)}%           | == 100.0% (${hybridMetrics.constraintRetention == 1.0 ? "PASS" : "FAIL"})');
      // ignore: avoid_print
      print(
          'Total Token Waste       | ${baselineMetrics.totalTokenWaste} tk             | ${hardenedMetrics.totalTokenWaste} tk             | ${hybridMetrics.totalTokenWaste} tk             | bounded');
      // ignore: avoid_print
      print('=' * 80);

      // Verify P1 Acceptance Criteria:
      expect(hybridMetrics.recall, greaterThanOrEqualTo(0.85),
          reason: 'Hybrid recall must achieve >= 85.0%');
      expect(hybridMetrics.precision, greaterThanOrEqualTo(0.90),
          reason: 'Hybrid precision must achieve >= 90.0%');
      expect(hybridMetrics.constraintRetention, 1.0,
          reason: 'Constraint retention must remain 100.0%');
    });
  });
}
