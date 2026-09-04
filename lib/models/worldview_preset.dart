import 'dart:convert';
import 'worldview_details.dart';

/// 可复用的世界观预设 — 包含世界观描述和世界知识条目，支持 JSON 序列化
class WorldviewPreset {
  String id;
  String name;
  String description;
  List<Map<String, dynamic>> worldEntries;
  DateTime createdAt;
  DateTime updatedAt;
  WorldviewDetails details;

  WorldviewPreset({
    String? id,
    this.name = '',
    this.description = '',
    List<Map<String, dynamic>>? worldEntries,
    DateTime? createdAt,
    DateTime? updatedAt,
    WorldviewDetails? details,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        worldEntries = worldEntries ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        details = details ?? WorldviewDetails.simple(description);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'world_entries': worldEntries,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'detail_json': details.toJson(),
      };

  factory WorldviewPreset.fromJson(Map<String, dynamic> json) {
    return WorldviewPreset(
      id: json['id'] as String?,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      worldEntries: (json['world_entries'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ??
          [],
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
      details: WorldviewDetails.fromJson(
        json['detail_json'] is String
            ? _decodeDetails(json['detail_json'] as String)
            : json['detail_json'] as Map<String, dynamic>?,
        fallbackDescription: json['description'] as String? ?? '',
      ),
    );
  }

  WorldviewPreset copyWith({
    String? id,
    String? name,
    String? description,
    List<Map<String, dynamic>>? worldEntries,
    DateTime? createdAt,
    DateTime? updatedAt,
    WorldviewDetails? details,
  }) =>
      WorldviewPreset(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        worldEntries: worldEntries ?? this.worldEntries,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        details: details ?? this.details,
      );

  static Map<String, dynamic>? _decodeDetails(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static List<WorldviewPreset> listFromJson(String jsonStr) {
    final list = jsonDecode(jsonStr) as List<dynamic>;
    return list
        .map((e) => WorldviewPreset.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String listToJson(List<WorldviewPreset> presets) {
    return const JsonEncoder.withIndent('  ')
        .convert(presets.map((p) => p.toJson()).toList());
  }
}
