import 'dart:convert';
import 'dart:typed_data';

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

  WorldEntryEmbedding({
    this.id,
    required this.entryId,
    this.adventureId = 0,
    required this.contentHash,
    required this.modelId,
    required this.dimensions,
    required List<double> vector,
    required this.createdAt,
  }) : vector = vector is Float32List ? vector : Float32List.fromList(vector);

  /// Compact byte representation of the float vector.
  Uint8List get toBinaryBlob {
    final f32 = vector is Float32List
        ? (vector as Float32List)
        : Float32List.fromList(vector);
    return f32.buffer.asUint8List(f32.offsetInBytes, f32.lengthInBytes);
  }

  /// Instantly converts a byte blob to [Float32List] without JSON decoding.
  static Float32List fromBinaryBlob(Uint8List blob) {
    final count = blob.lengthInBytes ~/ 4;
    if (blob.offsetInBytes % 4 != 0) {
      final copy = Uint8List.fromList(blob);
      return copy.buffer.asFloat32List(0, count);
    }
    return blob.buffer.asFloat32List(blob.offsetInBytes, count);
  }

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
        'embedding_blob': toBinaryBlob,
        'embedding_json': jsonEncode(vector),
        'created_at': createdAt.toIso8601String(),
      };

  factory WorldEntryEmbedding.fromDbMap(Map<String, dynamic> map) {
    List<double> parseVector() {
      final blob = map['embedding_blob'];
      if (blob is Uint8List && blob.isNotEmpty) {
        return fromBinaryBlob(blob);
      }
      final raw = map['embedding_json'] ?? map['vector'];
      if (raw is Uint8List && raw.isNotEmpty) {
        return fromBinaryBlob(raw);
      }
      if (raw is List) {
        final f32 = Float32List(raw.length);
        for (var i = 0; i < raw.length; i++) {
          f32[i] = (raw[i] as num).toDouble();
        }
        return f32;
      }
      if (raw is String && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final f32 = Float32List(decoded.length);
          for (var i = 0; i < decoded.length; i++) {
            f32[i] = (decoded[i] as num).toDouble();
          }
          return f32;
        }
      }
      return Float32List(0);
    }

    final createdAtStr = map['created_at']?.toString();
    final createdAt = createdAtStr != null
        ? DateTime.tryParse(createdAtStr) ?? DateTime.now()
        : DateTime.now();

    final parsedVector = parseVector();
    return WorldEntryEmbedding(
      id: map['id'] as int?,
      entryId: (map['entry_id'] as num?)?.toInt() ?? 0,
      adventureId: (map['adventure_id'] as num?)?.toInt() ?? 0,
      contentHash: map['content_hash']?.toString() ?? '',
      modelId: map['model_id']?.toString() ?? '',
      dimensions: (map['dimensions'] as num?)?.toInt() ?? parsedVector.length,
      vector: parsedVector,
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
