import '../../models/world_embedding.dart';

/// Repository interface for persisting and querying world entry embeddings.
abstract class IWorldEmbeddingRepository {
  Future<int> insertEmbedding(WorldEntryEmbedding embedding);
  Future<void> saveBatch(List<WorldEntryEmbedding> embeddings);
  Future<WorldEntryEmbedding?> getEmbeddingForEntry(
    int entryId, {
    required String modelId,
    required String contentHash,
  });
  Future<List<WorldEntryEmbedding>> getEmbeddingsForAdventure(
    int adventureId, {
    required String modelId,
  });
  Future<void> deleteByEntryId(int entryId);
  Future<void> deleteByAdventureId(int adventureId);
}
