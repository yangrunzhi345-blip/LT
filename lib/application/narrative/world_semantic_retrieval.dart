import 'dart:isolate';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../models/world_embedding.dart';
import '../../models/world_entry.dart';
import '../../services/embedding/semantic_embedding_service.dart';
import '../../services/repositories/world_embedding_repository.dart';
import '../../utils/content_hasher.dart';
import 'narrative_context.dart';

/// Computes the cosine similarity between two normalized or unnormalized vectors.
/// Returns 0.0 if vectors have different dimensions or are empty/zero.
double cosineSimilarity(List<double> a, List<double> b) {
  if (a.isEmpty || b.isEmpty || a.length != b.length) return 0.0;
  var dot = 0.0;
  var normA = 0.0;
  var normB = 0.0;
  for (var i = 0; i < a.length; i++) {
    final ai = a[i];
    final bi = b[i];
    dot += ai * bi;
    normA += ai * ai;
    normB += bi * bi;
  }
  if (normA <= 1e-12 || normB <= 1e-12) return 0.0;
  return (dot / (sqrt(normA) * sqrt(normB))).clamp(-1.0, 1.0);
}

/// A recalled candidate from the semantic vector channel.
final class SemanticCandidate {
  final WorldEntry entry;
  final double similarity;
  final WorldContextKind kind;

  const SemanticCandidate({
    required this.entry,
    required this.similarity,
    required this.kind,
  });
}

/// Coordinates semantic embedding retrieval for world entries.
///
/// Features:
/// - In-memory and SQLite caching of embeddings by content hash.
/// - Batch SQLite loading to eliminate N+1 queries.
/// - Bounded Top-K selection with min-heap complexity.
/// - Dynamic offload to worker isolate ([Isolate.run]) for large candidate sets.
/// - Graceful degradation on embedding failures or timeouts.
/// - Minimum similarity threshold filtering.
/// - Does not modify or evaluate Runtime HEAD, SceneState, or Player state.
final class SemanticWorldRetriever {
  final SemanticEmbeddingService embeddingService;
  final IWorldEmbeddingRepository? repository;

  /// Candidate threshold to trigger background isolate execution.
  static const int isolateCandidateThreshold = 100;

  /// Total float operations threshold (candidates * dimensions) to trigger isolate execution.
  static const int isolateOpsThreshold = 15000;

  const SemanticWorldRetriever({
    required this.embeddingService,
    this.repository,
  });

  /// Mathematical Top-K selection with bounded space and insertion order.
  static List<({int entryId, double similarity})> computeTopKScores({
    required List<double> queryVector,
    required List<({int entryId, List<double> vector})> candidateVectors,
    required double minSimilarity,
    required int topK,
  }) {
    if (candidateVectors.isEmpty || topK <= 0) return const [];

    final top = <({int entryId, double similarity})>[];
    for (var i = 0; i < candidateVectors.length; i++) {
      final cand = candidateVectors[i];
      final sim = cosineSimilarity(queryVector, cand.vector);
      if (sim < minSimilarity) continue;

      if (top.length < topK) {
        top.add((entryId: cand.entryId, similarity: sim));
        if (top.length == topK) {
          top.sort((a, b) => a.similarity.compareTo(b.similarity));
        }
      } else if (sim > top[0].similarity) {
        top[0] = (entryId: cand.entryId, similarity: sim);
        var j = 0;
        while (
            j + 1 < top.length && top[j].similarity > top[j + 1].similarity) {
          final temp = top[j];
          top[j] = top[j + 1];
          top[j + 1] = temp;
          j++;
        }
      }
    }

    if (top.length < topK) {
      top.sort((a, b) => b.similarity.compareTo(a.similarity));
      return top;
    }

    return top.reversed.toList(growable: false);
  }

  Future<List<SemanticCandidate>> retrieve({
    required String query,
    required List<WorldEntry> entries,
    int? adventureId,
    double minSimilarity = 0.35,
    int topK = 8,
    required WorldContextKind Function(WorldEntry entry) classifier,
  }) async {
    if (query.trim().isEmpty || entries.isEmpty) {
      return const [];
    }

    try {
      final queryVector = await embeddingService.embedText(query.trim());
      if (queryVector.isEmpty) return const [];

      // 1. Metadata pre-filter: active, non-empty, scoped entries only
      final validEntries = entries
          .where(
              (e) => e.enabled && e.content.trim().isNotEmpty && e.id != null)
          .where((e) =>
              adventureId == null ||
              e.adventureId == 0 ||
              e.adventureId == adventureId)
          .toList(growable: false);

      if (validEntries.isEmpty) return const [];

      // 2. Batch load embeddings from cache / SQLite repository (avoids N+1 queries)
      final validIds = validEntries.map((e) => e.id!).toList(growable: false);
      final cachedMap = repository != null
          ? await repository!.getEmbeddingsBatch(
              validIds,
              modelId: embeddingService.modelId,
            )
          : const <int, WorldEntryEmbedding>{};

      final entryVectors = <int, List<double>>{};
      final unindexedEntries = <WorldEntry>[];

      for (final entry in validEntries) {
        final entryId = entry.id!;
        final hash = ContentHasher.hash(entry.content);
        final cached = cachedMap[entryId];

        if (cached != null &&
            cached.contentHash == hash &&
            cached.vector.isNotEmpty) {
          entryVectors[entryId] = cached.vector;
        } else {
          unindexedEntries.add(entry);
        }
      }

      // 3. Compute missing embeddings in batch
      if (unindexedEntries.isNotEmpty) {
        try {
          final texts = unindexedEntries.map((e) => e.content.trim()).toList();
          final vectors = await embeddingService.embedBatch(texts);
          final toSave = <WorldEntryEmbedding>[];

          for (var i = 0; i < unindexedEntries.length; i++) {
            if (i >= vectors.length) break;
            final entry = unindexedEntries[i];
            final vec = vectors[i];
            if (vec.isNotEmpty) {
              if (entry.id != null) {
                entryVectors[entry.id!] = vec;
                toSave.add(WorldEntryEmbedding(
                  entryId: entry.id!,
                  adventureId: adventureId ?? entry.adventureId,
                  contentHash: ContentHasher.hash(entry.content),
                  modelId: embeddingService.modelId,
                  dimensions: embeddingService.dimensions,
                  vector: vec,
                  createdAt: DateTime.now(),
                ));
              }
            }
          }

          if (toSave.isNotEmpty && repository != null) {
            repository!.saveBatch(toSave).ignore();
          }
        } catch (batchError) {
          debugPrint('[SemanticRetriever] Batch embedding error: $batchError');
        }
      }

      // 4. Prepare candidate vectors for Top-K scoring
      final candidateList = <({int entryId, List<double> vector})>[];
      for (final entry in validEntries) {
        final vec = entryVectors[entry.id!];
        if (vec != null && vec.isNotEmpty) {
          candidateList.add((entryId: entry.id!, vector: vec));
        }
      }

      if (candidateList.isEmpty) return const [];

      // 5. Determine whether to offload to background isolate to protect UI fluidity
      final totalOps = candidateList.length * queryVector.length;
      final shouldOffload = candidateList.length >= isolateCandidateThreshold ||
          totalOps >= isolateOpsThreshold;

      List<({int entryId, double similarity})> topScores;
      if (shouldOffload) {
        try {
          topScores = await computeTopKScoresInIsolate(
            queryVector: queryVector,
            candidateVectors: candidateList,
            minSimilarity: minSimilarity,
            topK: topK,
          );
        } catch (isolateError) {
          debugPrint(
              '[SemanticRetriever] Isolate execution failed, falling back to local: $isolateError');
          topScores = computeTopKScores(
            queryVector: queryVector,
            candidateVectors: candidateList,
            minSimilarity: minSimilarity,
            topK: topK,
          );
        }
      } else {
        topScores = computeTopKScores(
          queryVector: queryVector,
          candidateVectors: candidateList,
          minSimilarity: minSimilarity,
          topK: topK,
        );
      }

      // 6. Map top scores back to WorldEntry entities
      final entryMap = {for (final e in validEntries) e.id!: e};
      final candidates = <SemanticCandidate>[];
      for (final score in topScores) {
        final entry = entryMap[score.entryId];
        if (entry != null) {
          candidates.add(SemanticCandidate(
            entry: entry,
            similarity: score.similarity,
            kind: classifier(entry),
          ));
        }
      }
      return candidates;
    } catch (e) {
      // Graceful fallback: semantic retrieval failure must never block or crash
      debugPrint('[SemanticRetriever] Retrieval failed gracefully: $e');
      return const [];
    }
  }

  /// Offload Top-K cosine calculation to a background worker isolate.
  static Future<List<({int entryId, double similarity})>>
      computeTopKScoresInIsolate({
    required List<double> queryVector,
    required List<({int entryId, List<double> vector})> candidateVectors,
    required double minSimilarity,
    required int topK,
  }) {
    return Isolate.run(() => computeTopKScores(
          queryVector: queryVector,
          candidateVectors: candidateVectors,
          minSimilarity: minSimilarity,
          topK: topK,
        ));
  }
}
