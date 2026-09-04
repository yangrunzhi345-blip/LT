import 'dart:convert';

import 'worldview_details.dart';

/// 世界观预设行条目的结构化视图 — detail_json 的**唯一解析点**。
class WorldviewPresetEntry {
  final String id;
  final String name;
  final String description;
  final WorldviewDetails details;

  WorldviewPresetEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.details,
  });

  factory WorldviewPresetEntry.fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString() ?? '';
    final name = row['name']?.toString() ?? '';
    final description = row['description']?.toString() ?? '';
    Map<String, dynamic>? detail;
    final raw = row['detail_json'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) detail = decoded;
      } catch (_) {}
    }
    return WorldviewPresetEntry(
      id: id,
      name: name,
      description: description,
      details:
          WorldviewDetails.fromJson(detail, fallbackDescription: description),
    );
  }
}
