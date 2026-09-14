import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/narrative/narrative_context.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/model_context_capability.dart';
import 'package:lt_dialogue/models/scene_state.dart';
import 'package:lt_dialogue/models/world_entry.dart';

import '../support/world_retrieval_benchmark_fixtures.dart';

void main() {
  const runner = WorldRetrievalBenchmarkRunner();
  final suite = WorldRetrievalBenchmarkSuite.buildDefaultSuite();

  group('World Context Retrieval Quality Benchmark (12 Categories)', () {
    test('Category 1: Exact keyword recall should be 100%', () {
      final cases = suite
          .where((c) => c.category == RetrievalBenchmarkCategory.exactKeyword)
          .toList();
      for (final testCase in cases) {
        final eval = runner.evaluate(testCase);
        expect(eval.falseNegatives, isEmpty,
            reason: 'Failed exact recall for ${testCase.id}');
        expect(eval.recall, 1.0);
      }
    });

    test('Category 2: Reordered keywords recall should be 100%', () {
      final cases = suite
          .where(
              (c) => c.category == RetrievalBenchmarkCategory.reorderedKeywords)
          .toList();
      for (final testCase in cases) {
        final eval = runner.evaluate(testCase);
        expect(eval.falseNegatives, isEmpty,
            reason: 'Failed reordered recall for ${testCase.id}');
        expect(eval.recall, 1.0);
      }
    });

    test('Category 3: Synonymous phrasing fails under current contains logic',
        () {
      final cases = suite
          .where((c) =>
              c.category == RetrievalBenchmarkCategory.synonymousPhrasing)
          .toList();
      for (final testCase in cases) {
        final eval = runner.evaluate(testCase);
        // Current algorithm does not support synonyms without metadata alias expansion.
        expect(eval.falseNegatives, isNotEmpty,
            reason:
                'Expected substring match to fail on synonym: ${testCase.id}');
        expect(eval.recall, 0.0);
        expect(eval.identifiedFailureReason,
            RetrievalFailureReason.substringMismatchSynonym);
        expect(eval.identifiedIssueType, RetrievalIssueType.algorithm);
      }
    });

    test(
        'Category 4: Indirect description fails due to semantic vocabulary gap',
        () {
      final cases = suite
          .where((c) =>
              c.category == RetrievalBenchmarkCategory.indirectDescription)
          .toList();
      for (final testCase in cases) {
        final eval = runner.evaluate(testCase);
        expect(eval.falseNegatives, isNotEmpty,
            reason:
                'Expected failure on indirect semantic description: ${testCase.id}');
        expect(eval.recall, 0.0);
        expect(eval.identifiedIssueType, RetrievalIssueType.algorithm);
      }
    });

    test('Category 5: Location relevance prioritizes current location', () {
      final matchCase =
          suite.firstWhere((c) => c.id == 'location_relevance_scene_match');
      final matchEval = runner.evaluate(matchCase);
      expect(matchEval.truePositives, contains(501));
      expect(matchEval.falseNegatives, isEmpty);

      // Verify sublocation hierarchy mismatch
      final mismatchCase = suite.firstWhere(
          (c) => c.id == 'location_sublocation_hierarchical_mismatch');
      final mismatchEval = runner.evaluate(mismatchCase);
      expect(mismatchEval.falseNegatives, contains(503));
      expect(mismatchEval.identifiedFailureReason,
          RetrievalFailureReason.locationMismatch);
    });

    test('Category 6: Character relevance requires keys modeling', () {
      final withKeyCase =
          suite.firstWhere((c) => c.id == 'character_relevance_with_key');
      final withKeyEval = runner.evaluate(withKeyCase);
      expect(withKeyEval.truePositives, contains(601));
      expect(withKeyEval.falseNegatives, isEmpty);

      final missingKeyCase = suite.firstWhere(
          (c) => c.id == 'character_relevance_missing_metadata_key');
      final missingKeyEval = runner.evaluate(missingKeyCase);
      expect(missingKeyEval.falseNegatives, contains(603));
      expect(missingKeyEval.identifiedFailureReason,
          RetrievalFailureReason.characterMetadataMissing);
      expect(
          missingKeyEval.identifiedIssueType, RetrievalIssueType.dataModeling);
    });

    test('Category 7: Sticky constraints are protected from token eviction',
        () {
      final severeCase = suite.firstWhere(
          (c) => c.id == 'sticky_constraint_under_severe_budget_pressure');
      final severeEval = runner.evaluate(severeCase);
      expect(severeEval.truePositives, contains(701));
      expect(severeEval.recalledEntryIds, isNot(contains(702)));

      final creativeConstraintCase = suite.firstWhere((c) =>
          c.id == 'sticky_creative_constraints_vulnerable_classification');
      final creativeEval = runner.evaluate(creativeConstraintCase);
      // Creative constraints without rule prefix are classified as lore and evicted
      expect(creativeEval.falseNegatives, contains(703));
      expect(creativeEval.identifiedFailureReason,
          RetrievalFailureReason.classificationMismatch);
    });

    test('Category 8: Facts take precedence over Lore under tight budget', () {
      final compCase =
          suite.firstWhere((c) => c.id == 'fact_lore_budget_competition');
      final compEval = runner.evaluate(compCase);
      expect(compEval.truePositives, contains(801));
      expect(compEval.recalledEntryIds, isNot(contains(802)));
      expect(compEval.result.filteredEntryReasons[802], 'token_budget');
    });

    test(
        'Category 9: Irrelevant content is reliably filtered (0% false positives)',
        () {
      final irrCase =
          suite.firstWhere((c) => c.id == 'irrelevant_content_filtering');
      final irrEval = runner.evaluate(irrCase);
      expect(irrEval.recalledEntryIds, isEmpty);
      expect(irrEval.falsePositives, isEmpty);
      expect(irrEval.tokenWaste, 0);
    });

    test('Category 10: Distractors with generic keys produce false positives',
        () {
      final isoCase = suite
          .firstWhere((c) => c.id == 'distractor_similar_factions_isolation');
      final isoEval = runner.evaluate(isoCase);
      expect(isoEval.truePositives, contains(1001));
      expect(isoEval.recalledEntryIds, isNot(contains(1002)));

      final genericCase = suite
          .firstWhere((c) => c.id == 'distractor_overly_generic_key_pollution');
      final genericEval = runner.evaluate(genericCase);
      expect(genericEval.falsePositives, contains(1004));
      expect(genericEval.tokenWaste, greaterThan(0));
    });

    test('Category 11: Aliases work if and only if modeled in metadata keys',
        () {
      final unmappedCase =
          suite.firstWhere((c) => c.id == 'alias_unmapped_in_keys');
      final unmappedEval = runner.evaluate(unmappedCase);
      expect(unmappedEval.falseNegatives, contains(1101));

      final mappedCase =
          suite.firstWhere((c) => c.id == 'alias_properly_mapped_in_keys');
      final mappedEval = runner.evaluate(mappedCase);
      expect(mappedEval.truePositives, contains(1102));
      expect(mappedEval.falseNegatives, isEmpty);
    });

    test('Category 12: Chinese linguistic variation coverage', () {
      final omittedCase =
          suite.firstWhere((c) => c.id == 'chinese_variation_omitted_subject');
      expect(runner.evaluate(omittedCase).truePositives, contains(1201));

      final pronounCase =
          suite.firstWhere((c) => c.id == 'chinese_variation_anaphora_pronoun');
      expect(runner.evaluate(pronounCase).falseNegatives, contains(1202));

      final colloquialCase =
          suite.firstWhere((c) => c.id == 'chinese_variation_colloquialism');
      expect(runner.evaluate(colloquialCase).falseNegatives, contains(1203));

      final shortCase = suite
          .firstWhere((c) => c.id == 'chinese_variation_ultra_short_query');
      expect(runner.evaluate(shortCase).truePositives, contains(1204));

      final longCase = suite
          .firstWhere((c) => c.id == 'chinese_variation_long_narrative_query');
      final longEval = runner.evaluate(longCase);
      expect(longEval.truePositives, containsAll([1205, 1206]));
    });
  });

  group('Suite Metrics Aggregation and Quantitative Reporting', () {
    test('should aggregate metrics across all 12 benchmark categories', () {
      final metrics = runner.runSuite(suite);

      // Verify aggregate metrics are valid mathematical proportions
      expect(metrics.totalCases, suite.length);
      expect(metrics.recall, inInclusiveRange(0.0, 1.0));
      expect(metrics.precision, inInclusiveRange(0.0, 1.0));
      expect(metrics.f1Score, inInclusiveRange(0.0, 1.0));
      expect(metrics.constraintRetention, inInclusiveRange(0.0, 1.0));
      expect(metrics.factRetention, inInclusiveRange(0.0, 1.0));
      expect(metrics.loreNoise, inInclusiveRange(0.0, 1.0));

      // Constraint retention for true rule constraints must be 100%
      expect(metrics.constraintRetention, 1.0);

      // Print structured summary report to stdout for audit capture
      // ignore: avoid_print
      print('\n${'=' * 80}');
      // ignore: avoid_print
      print('WORLD CONTEXT RETRIEVAL QUALITY BENCHMARK REPORT');
      // ignore: avoid_print
      print('=' * 80);
      // ignore: avoid_print
      print('Total Test Cases: ${metrics.totalCases}');
      // ignore: avoid_print
      print('Overall Recall: ${(metrics.recall * 100).toStringAsFixed(1)}% '
          '(${metrics.truePositives}/${metrics.totalExpectedPositives})');
      // ignore: avoid_print
      print(
          'Overall Precision: ${(metrics.precision * 100).toStringAsFixed(1)}% '
          '(${metrics.truePositives}/${metrics.totalRecalled})');
      // ignore: avoid_print
      print('Overall F1-Score: ${(metrics.f1Score * 100).toStringAsFixed(1)}%');
      // ignore: avoid_print
      print('True Positives (TP): ${metrics.truePositives}');
      // ignore: avoid_print
      print('False Negatives (FN): ${metrics.falseNegatives}');
      // ignore: avoid_print
      print('False Positives (FP): ${metrics.falsePositives}');
      // ignore: avoid_print
      print('True Negatives (TN): ${metrics.trueNegatives}');
      // ignore: avoid_print
      print('Total Token Waste: ${metrics.totalTokenWaste} tokens');
      // ignore: avoid_print
      print(
          'Constraint Retention: ${(metrics.constraintRetention * 100).toStringAsFixed(1)}%');
      // ignore: avoid_print
      print(
          'Fact Retention: ${(metrics.factRetention * 100).toStringAsFixed(1)}%');
      // ignore: avoid_print
      print('Lore Noise: ${(metrics.loreNoise * 100).toStringAsFixed(1)}%');
      // ignore: avoid_print
      print('-' * 80);
      // ignore: avoid_print
      print('CATEGORY BREAKDOWN:');
      for (final entry in metrics.categoryBreakdown.entries) {
        final cat = entry.key;
        final m = entry.value;
        // ignore: avoid_print
        print('  ${cat.displayName.padRight(28)} | '
            'Recall: ${(m.recall * 100).toStringAsFixed(1).padLeft(5)}% | '
            'Prec: ${(m.precision * 100).toStringAsFixed(1).padLeft(5)}% | '
            'TP: ${m.tp} FP: ${m.fp} FN: ${m.fn} | '
            'Waste: ${m.tokenWaste} tk');
      }
      // ignore: avoid_print
      print('-' * 80);
      // ignore: avoid_print
      print('FAILURE REASON TAXONOMY:');
      for (final entry in metrics.failureReasonCounts.entries) {
        // ignore: avoid_print
        print('  ${entry.key.description.padRight(40)}: ${entry.value} cases');
      }
      // ignore: avoid_print
      print('-' * 80);
      // ignore: avoid_print
      print('ISSUE TYPE CLASSIFICATION:');
      for (final entry in metrics.issueTypeCounts.entries) {
        // ignore: avoid_print
        print('  ${entry.key.label.padRight(32)}: ${entry.value} cases');
      }
      // ignore: avoid_print
      print('${'=' * 80}\n');
    });
  });

  group('ContextTrace Enhancement & Privacy Verification', () {
    test(
        'ContextTrace contains candidate audit details without leaking raw body text',
        () {
      const orchestrator = ContextOrchestrator();
      final context = orchestrator.build(
        rawInput: '银月城有什么特点？',
        config: AdventureConfig(name: '主角'),
        sceneState: const SceneState(location: '银月城'),
        worldEntries: [
          WorldEntry(
            id: 1,
            keys: ['银月城'],
            content: '【世界观/locations】银月城是北境最大的魔法研究中心，隐藏着禁忌历史。',
            sourceType: 'location',
          ),
          WorldEntry(
            id: 2,
            keys: ['铁岩堡'],
            content: '【世界观/locations】铁岩堡是遥远的矮人工坊，绝密商业机密不为人知。',
            sourceType: 'location',
          ),
        ],
        messages: const [],
        summary: null,
        persona: null,
        capability: const ModelContextCapability.conservative(),
        requestedResponseTokens: 1024,
      );

      final diagnostics = context.trace.toDiagnostics();
      expect(diagnostics['world_retrieval'], isNotNull);
      final worldRetrieval = diagnostics['world_retrieval'] as List<dynamic>;
      expect(worldRetrieval.length, 2);

      final candidate1 = worldRetrieval.firstWhere(
              (item) => (item as Map<String, dynamic>)['entry_id'] == 1)
          as Map<String, dynamic>;
      expect(candidate1['included'], isTrue);
      expect(candidate1['score'], greaterThan(0));
      expect(candidate1['matched_keys'], greaterThan(0));
      expect(candidate1['location_matched'], isTrue);
      expect(candidate1['classified_kind'], 'fact');

      final candidate2 = worldRetrieval.firstWhere(
              (item) => (item as Map<String, dynamic>)['entry_id'] == 2)
          as Map<String, dynamic>;
      expect(candidate2['included'], isFalse);
      expect(candidate2['filter_reason'], 'irrelevant');

      // Crucial privacy check: no raw text content in diagnostics!
      final serialized = diagnostics.toString();
      expect(serialized, isNot(contains('隐藏着禁忌历史')));
      expect(serialized, isNot(contains('绝密商业机密不为人知')));
    });
  });
}
