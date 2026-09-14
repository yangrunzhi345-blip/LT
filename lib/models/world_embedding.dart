import 'dart:convert';

/// Stored semantic vector representation for a [WorldEntry].
final class WorldEntryEmbedding {
  final int? id;
  final int entryId;
  final int adventureId;
  final String contentHash;
  final String modelId;
  final int dimensions;
  final List<double> vector;
  final DateTime createdAt;

  const WorldEntryEmbedding({
    this.id,
    required this.entryId,
    this.adventureId = 0,
    required this.contentHash,
    required this.modelId,
    required this.dimensions,
    required this.vector,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'entry_id': entryId,
        'adventure_id': adventureId,
        'content_hash': contentHash,
        'model_id': modelId,
        'dimensions': dimensions,
        'vector': vector,
        'created_at': createdAt.toIso8601String(),
      };

  Map<String, dynamic> toDbMap() => {
        if (id != null) 'id': id,
        'entry_id': entryId,
        'adventure_id': adventureId,
        'content_hash': contentHash,
        'model_id': modelId,
        'dimensions': dimensions,
        'embedding_json': jsonEncode(vector),
        'created_at': createdAt.toIso8601String(),
      };

  factory WorldEntryEmbedding.fromDbMap(Map<String, dynamic> map) {
    List<double> parseVector(dynamic raw) {
      if (raw is List) {
        return raw.map((e) => (e as num).toDouble()).toList(growable: false);
      }
      if (raw is String && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .map((e) => (e as num).toDouble())
              .toList(growable: false);
        }
      }
      return const <double>[];
    }

    final createdAtStr = map['created_at']?.toString();
    final createdAt = createdAtStr != null
        ? DateTime.tryParse(createdAtStr) ?? DateTime.now()
        : DateTime.now();

    final vector = parseVector(map['embedding_json'] ?? map['vector']);
    return WorldEntryEmbedding(
      id: map['id'] as int?,
      entryId: (map['entry_id'] as num?)?.toInt() ?? 0,
      adventureId: (map['adventure_id'] as num?)?.toInt() ?? 0,
      contentHash: map['content_hash']?.toString() ?? '',
      modelId: map['model_id']?.toString() ?? '',
      dimensions: (map['dimensions'] as num?)?.toInt() ?? vector.length,
      vector: vector,
      createdAt: createdAt,
    );
  }

  WorldEntryEmbedding copyWith({
    int? id,
    int? entryId,
    int? adventureId,
    String? contentHash,
    String? modelId,
    int? dimensions,
    List<double>? vector,
    DateTime? createdAt,
  }) {
    return WorldEntryEmbedding(
      id: id ?? this.id,
      entryId: entryId ?? this.entryId,
      adventureId: adventureId ?? this.adventureId,
      contentHash: contentHash ?? this.contentHash,
      modelId: modelId ?? this.modelId,
      dimensions: dimensions ?? this.dimensions,
      vector: vector ?? this.vector,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
