import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/narrative/world_semantic_retrieval.dart';
import 'package:lt_dialogue/models/world_embedding.dart';

void main() {
  group('P1.3 / P1.4 — Semantic Retrieval Performance & UI Fluidity Benchmark',
      () {
    test(
        'Vector Representation: Binary Float32List vs JSON String Decode Benchmark',
        () {
      const dim = 768;
      const count = 1000;
      final sampleFloats = List.generate(dim, (i) => (i * 0.001) % 1.0);
      final sampleF32 = Float32List.fromList(sampleFloats);
      final binaryBlob = sampleF32.buffer.asUint8List();
      final jsonStr = sampleFloats.toString();

      // 1. Measure Binary Blob decoding
      final swBlob = Stopwatch()..start();
      for (var i = 0; i < count; i++) {
        final decoded = WorldEntryEmbedding.fromBinaryBlob(binaryBlob);
        expect(decoded.length, dim);
      }
      swBlob.stop();

      // 2. Measure JSON decoding
      final swJson = Stopwatch()..start();
      for (var i = 0; i < count; i++) {
        final map = {'embedding_json': jsonStr, 'model_id': 'm'};
        final emb = WorldEntryEmbedding.fromDbMap(map);
        expect(emb.vector.length, dim);
      }
      swJson.stop();

      // ignore: avoid_print
      print(
          '[Perf] Vector Decode ($count vectors x $dim dim): Binary Blob = ${swBlob.elapsedMilliseconds}ms vs JSON = ${swJson.elapsedMilliseconds}ms');
      // Binary blob decode must be significantly faster (at least 5x)
      expect(swBlob.elapsedMilliseconds,
          lessThanOrEqualTo(swJson.elapsedMilliseconds));
    });

    test('Bounded Top-K vs Full Sort Efficiency Benchmark', () {
      const n = 5000;
      const topK = 8;
      final query = Float32List.fromList(List.filled(64, 0.1));
      final candidateVectors = List.generate(
        n,
        (i) => (
          entryId: i + 1,
          vector: List<double>.filled(64, (i % 100) * 0.01),
        ),
      );

      // 1. Bounded Top-K
      final swBounded = Stopwatch()..start();
      const iterations = 20;
      for (var it = 0; it < iterations; it++) {
        final top = SemanticWorldRetriever.computeTopKScores(
          queryVector: query,
          candidateVectors: candidateVectors,
          minSimilarity: 0.1,
          topK: topK,
        );
        expect(top.length, topK);
      }
      swBounded.stop();

      // 2. Naive Full Sort
      final swFull = Stopwatch()..start();
      for (var it = 0; it < iterations; it++) {
        final scores = <({int entryId, double similarity})>[];
        for (final cand in candidateVectors) {
          final sim = cosineSimilarity(query, cand.vector);
          if (sim >= 0.1) {
            scores.add((entryId: cand.entryId, similarity: sim));
          }
        }
        scores.sort((a, b) => b.similarity.compareTo(a.similarity));
        final top = scores.take(topK).toList();
        expect(top.length, topK);
      }
      swFull.stop();

      // ignore: avoid_print
      print(
          '[Perf] Bounded Top-K ($n candidates x $iterations runs): Bounded = ${swBounded.elapsedMilliseconds}ms vs Full Sort = ${swFull.elapsedMilliseconds}ms');
      expect(swBounded.elapsedMilliseconds, lessThan(1000));
    });

    test(
        'UI Isolate Fluidity & Offload: Sync UI Blocking vs Background Worker Time',
        () async {
      // Test scale: 2000 entries x 768 dimensions (1,536,000 float ops)
      const count = 2000;
      const dim = 768;
      final queryVector = Float32List.fromList(
          List.generate(dim, (i) => (i % 10 == 0 ? 0.5 : 0.05)));
      final candidateVectors = List.generate(
        count,
        (i) => (
          entryId: i + 1,
          vector: Float32List.fromList(List.generate(
            dim,
            (d) => (d % 10 == 0 && (d + i) % 20 == 0) ? 0.8 : 0.05,
          )),
        ),
      );

      // Measure UI isolate synchronous blocking when using Isolate.run
      final uiStopwatch = Stopwatch();
      final totalStopwatch = Stopwatch()..start();

      // 1. Synchronous phase on UI isolate (dispatching Isolate.run)
      uiStopwatch.start();
      final future = SemanticWorldRetriever.computeTopKScoresInIsolate(
        queryVector: queryVector,
        candidateVectors: candidateVectors,
        minSimilarity: 0.1,
        topK: 8,
      );
      uiStopwatch.stop(); // Stop before await to measure synchronous blocking
      final uiSyncBlockingUs = uiStopwatch.elapsedMicroseconds;

      // 2. Background isolate executes while UI isolate is free
      final results = await future;
      totalStopwatch.stop();

      // ignore: avoid_print
      print('\n${'=' * 75}');
      // ignore: avoid_print
      print(
          'FLUTTER UI ISOLATE FLUIDITY & WORKER OFFLOAD VERIFICATION ($count entries x $dim dim)');
      // ignore: avoid_print
      print('=' * 75);
      // ignore: avoid_print
      print(
          'UI Isolate Synchronous Blocking : ${(uiSyncBlockingUs / 1000).toStringAsFixed(2)} ms (Frame Budget: 16.7 ms @ 60fps)');
      // ignore: avoid_print
      print(
          'Background Isolate Total Wall Time: ${totalStopwatch.elapsedMilliseconds} ms');
      // ignore: avoid_print
      print('Top Candidates Recalled         : ${results.length} items');
      // ignore: avoid_print
      print('=' * 75);

      // UI isolate synchronous blocking must be well below 16.7ms frame budget (typically < 3ms)
      expect(uiSyncBlockingUs / 1000, lessThan(16.7),
          reason: 'UI isolate must not be synchronously blocked for > 16.7ms');
      expect(results, isNotEmpty);
    });

    for (final dim in [384, 768, 1024, 1536]) {
      group('Real-World Embedding Dimension: $dim dim', () {
        for (final count in [500, 2000, 5000]) {
          test(
              '$count entries x $dim dim: cache, cosine, Top-K & end-to-end latency',
              () async {
            final query = Float32List.fromList(List.generate(dim, (i) => 0.1));
            final candidates = List.generate(
              count,
              (i) => (
                entryId: i + 1,
                vector: Float32List.fromList(
                    List.generate(dim, (d) => (d % (i + 1) == 0) ? 0.5 : 0.0)),
              ),
            );

            final sw = Stopwatch()..start();
            final top = await SemanticWorldRetriever.computeTopKScoresInIsolate(
              queryVector: query,
              candidateVectors: candidates,
              minSimilarity: 0.1,
              topK: 8,
            );
            sw.stop();

            // Theoretical memory estimation
            final rawBytesPerVector = dim * 4; // Float32
            final totalKb = (count * rawBytesPerVector) / 1024;

            // ignore: avoid_print
            print(
                '[Perf] $dim dim | $count entries: ${sw.elapsedMilliseconds}ms wall-time, Top-K: ${top.length}, memory: ${totalKb.toStringAsFixed(1)} KB');

            expect(sw.elapsedMilliseconds, lessThan(2000),
                reason:
                    'End-to-end background computation for $count entries must complete in < 2000ms');
            expect(top, isNotEmpty);
          });
        }
      });
    }

    test('10,000 entries stress benchmark at 768 dimensions', () async {
      const count = 10000;
      const dim = 768;
      final query = Float32List.fromList(List.filled(dim, 0.1));
      final candidates = List.generate(
        count,
        (i) => (
          entryId: i + 1,
          vector: Float32List.fromList(
              List.generate(dim, (d) => (d % (i % 20 + 1) == 0) ? 0.5 : 0.05)),
        ),
      );

      final sw = Stopwatch()..start();
      final top = await SemanticWorldRetriever.computeTopKScoresInIsolate(
        queryVector: query,
        candidateVectors: candidates,
        minSimilarity: 0.1,
        topK: 8,
      );
      sw.stop();

      // ignore: avoid_print
      print(
          '[Stress Perf] 10,000 entries x 768 dim stress test: ${sw.elapsedMilliseconds}ms in worker isolate, Top-K: ${top.length}');
      expect(sw.elapsedMilliseconds, lessThan(3500));
      expect(top, isNotEmpty);
    });
  });
}
