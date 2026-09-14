import 'package:sqflite/sqflite.dart';
import '../../models/world_embedding.dart';
import 'world_embedding_repository.dart';

class WorldEmbeddingRepositoryImpl implements IWorldEmbeddingRepository {
  final Future<Database> Function() _getDb;
  final Map<String, WorldEntryEmbedding> _memoryCache = {};

  WorldEmbeddingRepositoryImpl({required Future<Database> Function() getDb})
      : _getDb = getDb;

  String _cacheKey(int entryId, String modelId, String contentHash) =>
      '$entryId:$modelId:$contentHash';

  @override
  Future<int> insertEmbedding(WorldEntryEmbedding embedding) async {
    final db = await _getDb();
    // Replace any existing row for the same entry and model
    await db.delete(
      'world_entry_embeddings',
      where: 'entry_id = ? AND model_id = ?',
      whereArgs: [embedding.entryId, embedding.modelId],
    );
    final id = await db.insert('world_entry_embeddings', embedding.toDbMap());
    final saved = embedding.copyWith(id: id);
    _memoryCache[_cacheKey(
      embedding.entryId,
      embedding.modelId,
      embedding.contentHash,
    )] = saved;
    return id;
  }

  @override
  Future<void> saveBatch(List<WorldEntryEmbedding> embeddings) async {
    if (embeddings.isEmpty) return;
    final db = await _getDb();
    final batch = db.batch();
    for (final emb in embeddings) {
      batch.delete(
        'world_entry_embeddings',
        where: 'entry_id = ? AND model_id = ?',
        whereArgs: [emb.entryId, emb.modelId],
      );
      batch.insert('world_entry_embeddings', emb.toDbMap());
      _memoryCache[_cacheKey(
        emb.entryId,
        emb.modelId,
        emb.contentHash,
      )] = emb;
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<WorldEntryEmbedding?> getEmbeddingForEntry(
    int entryId, {
    required String modelId,
    required String contentHash,
  }) async {
    final key = _cacheKey(entryId, modelId, contentHash);
    if (_memoryCache.containsKey(key)) {
      return _memoryCache[key];
    }

    final db = await _getDb();
    final rows = await db.query(
      'world_entry_embeddings',
      where: 'entry_id = ? AND model_id = ? AND content_hash = ?',
      whereArgs: [entryId, modelId, contentHash],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    try {
      final embedding = WorldEntryEmbedding.fromDbMap(rows.first);
      _memoryCache[key] = embedding;
      return embedding;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<WorldEntryEmbedding>> getEmbeddingsForAdventure(
    int adventureId, {
    required String modelId,
  }) async {
    final db = await _getDb();
    final rows = await db.query(
      'world_entry_embeddings',
      where: 'adventure_id = ? AND model_id = ?',
      whereArgs: [adventureId, modelId],
    );
    final results = <WorldEntryEmbedding>[];
    for (final row in rows) {
      try {
        final emb = WorldEntryEmbedding.fromDbMap(row);
        _memoryCache[_cacheKey(emb.entryId, emb.modelId, emb.contentHash)] =
            emb;
        results.add(emb);
      } catch (_) {
        // Isolate malformed row
      }
    }
    return results;
  }

  @override
  Future<void> deleteByEntryId(int entryId) async {
    final db = await _getDb();
    await db.delete(
      'world_entry_embeddings',
      where: 'entry_id = ?',
      whereArgs: [entryId],
    );
    _memoryCache.removeWhere((key, val) => val.entryId == entryId);
  }

  @override
  Future<void> deleteByAdventureId(int adventureId) async {
    final db = await _getDb();
    await db.delete(
      'world_entry_embeddings',
      where: 'adventure_id = ?',
      whereArgs: [adventureId],
    );
    _memoryCache.removeWhere((key, val) => val.adventureId == adventureId);
  }
}
