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
/// - Graceful degradation on embedding failures or timeouts.
/// - Minimum similarity threshold filtering.
/// - Does not modify or evaluate Runtime HEAD, SceneState, or Player state.
final class SemanticWorldRetriever {
  final SemanticEmbeddingService embeddingService;
  final IWorldEmbeddingRepository? repository;

  const SemanticWorldRetriever({
    required this.embeddingService,
    this.repository,
  });

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

      final candidates = <SemanticCandidate>[];
      final unindexedEntries = <WorldEntry>[];
      final entryVectors = <int, List<double>>{};

      // 1. Resolve embeddings from cache/repository where possible
      for (final entry in entries) {
        if (!entry.enabled || entry.content.trim().isEmpty) continue;
        final entryId = entry.id;
        final hash = ContentHasher.hash(entry.content);

        List<double>? vector;
        if (entryId != null && repository != null) {
          final cached = await repository!.getEmbeddingForEntry(
            entryId,
            modelId: embeddingService.modelId,
            contentHash: hash,
          );
          vector = cached?.vector;
        }

        if (vector != null && vector.isNotEmpty) {
          if (entryId != null) {
            entryVectors[entryId] = vector;
          }
        } else {
          unindexedEntries.add(entry);
        }
      }

      // 2. Compute missing embeddings in batch
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

      // 3. Compute cosine similarity for all available vectors
      for (final entry in entries) {
        if (!entry.enabled || entry.content.trim().isEmpty) continue;
        final entryId = entry.id;
        final vector = entryId != null ? entryVectors[entryId] : null;
        if (vector == null || vector.isEmpty) continue;

        final sim = cosineSimilarity(queryVector, vector);
        if (sim >= minSimilarity) {
          candidates.add(SemanticCandidate(
            entry: entry,
            similarity: sim,
            kind: classifier(entry),
          ));
        }
      }

      // 4. Sort by similarity descending, take Top-K
      candidates.sort((a, b) => b.similarity.compareTo(a.similarity));
      if (candidates.length > topK) {
        return candidates.sublist(0, topK);
      }
      return candidates;
    } catch (e) {
      // Graceful fallback: semantic retrieval failure must never block or crash
      debugPrint('[SemanticRetriever] Retrieval failed gracefully: $e');
      return const [];
    }
  }
}
