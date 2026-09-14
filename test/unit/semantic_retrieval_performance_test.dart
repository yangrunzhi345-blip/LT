import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/narrative/narrative_context.dart';
import 'package:lt_dialogue/application/narrative/world_semantic_retrieval.dart';
import 'package:lt_dialogue/models/world_entry.dart';
import 'package:lt_dialogue/services/embedding/semantic_embedding_service.dart';

void main() {
  group('P1.4 — Semantic Retrieval Performance Benchmark', () {
    test(
        'Cosine similarity mathematical throughput (10,000 vector comparisons)',
        () {
      final vecA = List.generate(64, (i) => (i * 0.05).clamp(-1.0, 1.0));
      final vecB = List.generate(64, (i) => ((63 - i) * 0.05).clamp(-1.0, 1.0));

      final stopwatch = Stopwatch()..start();
      var dummySum = 0.0;
      const iterations = 10000;
      for (var i = 0; i < iterations; i++) {
        dummySum += cosineSimilarity(vecA, vecB);
      }
      stopwatch.stop();

      final totalUs = stopwatch.elapsedMicroseconds;
      final avgUs = totalUs / iterations;

      // ignore: avoid_print
      print(
          '[Perf] 10,000 cosine similarity comparisons: ${stopwatch.elapsedMilliseconds}ms (avg ${avgUs.toStringAsFixed(2)} µs/op)');
      expect(stopwatch.elapsedMilliseconds, lessThan(500),
          reason: '10,000 vector dot products should complete in < 500ms');
      expect(dummySum, isNot(0.0));
    });

    for (final count in [100, 500, 1000, 2000]) {
      test('Candidate merge & re-ranking latency for $count WorldEntries', () {
        final entries = List.generate(
          count,
          (i) => WorldEntry(
            id: i + 1,
            keys: ['key_$i', if (i % 5 == 0) 'magic'],
            content:
                '【世界观/${i % 10 == 0 ? "rules" : "locations"}】这是第 $i 个测试条目，包含关于帝国历史与地理的说明。',
            sourceType: i % 10 == 0 ? 'rule' : 'location',
            sticky: i % 20 == 0 ? 1 : 0,
            insertionOrder: i,
          ),
        );

        const builder = WorldContextBuilder.hybrid(
          semanticRetriever: SemanticWorldRetriever(
            embeddingService: DeterministicFakeEmbeddingService(),
          ),
        );

        // Warm up
        builder.build(
          entries: entries.take(10).toList(),
          query: 'magic 帝国',
          location: '帝国',
          characterNames: const [],
          tokenBudget: 1024,
        );

        final stopwatch = Stopwatch()..start();
        final result = builder.build(
          entries: entries,
          query: 'magic 帝国',
          location: '帝国',
          characterNames: const [],
          tokenBudget: 2048,
        );
        stopwatch.stop();

        // ignore: avoid_print
        print(
            '[Perf] $count entries hybrid retrieval latency: ${stopwatch.elapsedMilliseconds}ms, recalled: ${result.all.length} items');

        // Latency bounds for offline/local CPU execution (tolerant of VM scheduling):
        final maxLatencyMs = switch (count) {
          100 => 200,
          500 => 500,
          1000 => 1000,
          _ => 2000,
        };

        expect(stopwatch.elapsedMilliseconds, lessThan(maxLatencyMs),
            reason:
                'Retrieval for $count entries must complete within ${maxLatencyMs}ms');
        expect(result.all, isNotEmpty);
      });
    }
  });
}
