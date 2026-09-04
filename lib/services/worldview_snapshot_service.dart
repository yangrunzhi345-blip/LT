import 'dart:convert';

import '../models/world_entry.dart';
import '../models/worldview_details.dart';
import '../models/worldview_preset.dart';
import '../utils/content_hasher.dart';

/// Freezes a library worldview for an adventure and derives controlled context
/// entries.  The resource library is never read again for that adventure.
class WorldviewSnapshotService {
  static Map<String, dynamic> snapshot(WorldviewPreset preset) {
    final details = preset.details;
    final payload = <String, dynamic>{
      'source_id': preset.id,
      'name': preset.name,
      'description': preset.description,
      'format_version': WorldviewDetails.currentFormatVersion,
      'detail_json': details.toJson(),
      'created_at': DateTime.now().toIso8601String(),
    };
    payload['content_hash'] = ContentHasher.hash(payload);
    return payload;
  }

  static List<WorldEntry> buildManagedEntries(
    int adventureId,
    Map<String, dynamic> snapshot,
  ) {
    final details = WorldviewDetails.fromJson(
      snapshot['detail_json'] as Map<String, dynamic>?,
      fallbackDescription: snapshot['description']?.toString() ?? '',
    );
    final hash =
        snapshot['content_hash']?.toString() ?? ContentHasher.hash(snapshot);
    final sourceId = snapshot['source_id']?.toString() ?? '';
    final entries = <WorldEntry>[];
    void add(String module, dynamic value, {bool hardRule = false}) {
      final text = _text(value);
      if (text.isEmpty) return;
      entries.add(WorldEntry(
        adventureId: adventureId,
        keys: hardRule ? const ['_worldview_core_'] : _keywords(module, value),
        content: '【世界观/$module】$text',
        insertionOrder: hardRule ? -100 : 10 + entries.length,
        sticky: hardRule ? 1 : 0,
        insertPosition: WorldEntryPosition.beforePrompt,
        sourceType: 'worldview_snapshot',
        sourceId: sourceId,
        sourceSnapshotHash: hash,
      ));
    }

    final confirmed = details.confirmedModules();
    add('概览', confirmed['overview'] ?? snapshot['description'], hardRule: true);
    add('世界规则', confirmed['world_rules'], hardRule: true);
    add('当前世界状态', confirmed['world_state'], hardRule: true);
    add('创作约束', confirmed['creative_constraints'], hardRule: true);
    for (final key in const [
      'locations',
      'factions',
      'customs_and_life',
      'timeline',
      'glossary'
    ]) {
      add(key, confirmed[key]);
    }
    return entries;
  }

  static List<String> _keywords(String module, dynamic value) {
    final found = <String>{module};
    void visit(dynamic item) {
      if (item is Map) {
        for (final key in const ['name', 'title', 'aliases', 'keyword']) {
          final value = item[key];
          if (value is String && value.trim().isNotEmpty) {
            found.add(value.trim());
          }
          if (value is List) {
            for (final item in value.whereType<String>()) {
              found.add(item.trim());
            }
          }
        }
        item.values.forEach(visit);
      } else if (item is List) {
        item.forEach(visit);
      }
    }

    visit(value);
    return found.where((item) => item.isNotEmpty).take(12).toList();
  }

  static String _text(dynamic value) {
    if (value == null) return '';
    if (value is String) return value.trim();
    if (value is Map && value['status'] == WorldviewFactStatus.draft.name) {
      return '';
    }
    final encoded = jsonEncode(value);
    return encoded.length > 3000 ? encoded.substring(0, 3000) : encoded;
  }
}
