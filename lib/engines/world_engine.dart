import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/world_entry.dart';
import '../models/worldview_preset.dart';
import '../models/worldview_details.dart';
import '../utils/content_hasher.dart';
import '../services/database_service.dart';
import '../services/repositories/world_entry_repository.dart';
import '../services/repositories/library_repository.dart';
import '../services/resource_integrity_validator.dart';

class WorldEngine {
  final VoidCallback notifyParent;
  final IWorldEntryRepository _worldEntryRepo;
  final ILibraryRepository _libraryRepo;

  List<WorldEntry> _worldEntries = [];
  List<WorldviewPreset> _worldviewPresets = [];
  static const int _worldScanDepth = 4;

  List<WorldEntry> get worldEntries => _worldEntries;
  List<WorldviewPreset> get worldviewPresets => _worldviewPresets;
  static int get worldScanDepth => _worldScanDepth;

  /// 替换整个 worldEntries 列表（用于加载冒险时批量设置）
  void setEntries(List<WorldEntry> entries) {
    _worldEntries = List<WorldEntry>.from(entries);
    notifyParent();
  }

  WorldEngine({
    required this.notifyParent,
    required IWorldEntryRepository worldEntryRepo,
    required ILibraryRepository libraryRepo,
  })  : _worldEntryRepo = worldEntryRepo,
        _libraryRepo = libraryRepo;

  Future<void> addWorldEntry(WorldEntry entry) async {
    try {
      final id = await _worldEntryRepo.insertWorldEntry(entry);
      entry.id = id;
    } catch (e) {
      debugPrint('[WorldEngine] addWorldEntry 写入失败: $e');
    }
    _worldEntries.add(entry);
    notifyParent();
  }

  Future<void> updateWorldEntry(WorldEntry entry) async {
    try {
      await _worldEntryRepo.updateWorldEntry(entry);
    } catch (e) {
      debugPrint('[WorldEngine] updateWorldEntry 写入失败: $e');
    }
    final idx = _worldEntries.indexWhere((e) => e.id == entry.id);
    if (idx >= 0) _worldEntries[idx] = entry;
    notifyParent();
  }

  Future<void> deleteWorldEntry(int id) async {
    try {
      await _worldEntryRepo.deleteWorldEntry(id);
    } catch (e) {
      debugPrint('[WorldEngine] deleteWorldEntry 删除失败: $e');
    }
    _worldEntries.removeWhere((e) => e.id == id);
    notifyParent();
  }

  String exportWorldBookJson() {
    final entries = _worldEntries
        .map((e) => <String, dynamic>{
              'uid': e.id ?? 0,
              'comment': '',
              'content': e.content,
              'keys': e.keys,
              'secondary_keys': <String>[],
              'constant': false,
              'selective': true,
              'insertion_order': e.insertionOrder,
              'enabled': e.enabled,
              'position': e.insertPosition.index,
              'use_regex': e.useRegex,
              'extensions': {
                'probability': e.probability,
                'cooldown': e.cooldown,
                'sticky': e.sticky,
                'recursive': e.recursive,
              },
            })
        .toList();
    final json = {'entries': entries};
    return const JsonEncoder.withIndent('  ').convert(json);
  }

  Future<String> importWorldBookJson(
      String jsonStr, String strategy, int currentAdventureId) async {
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;
    final rawEntries =
        (json['entries'] as List<dynamic>?) ?? <dynamic>[jsonStr];

    final importEntries = <WorldEntry>[];
    int skipped = 0;
    for (final raw in rawEntries) {
      if (raw is! Map<String, dynamic>) {
        skipped++;
        continue;
      }
      final keys =
          (raw['keys'] as List<dynamic>?)?.map((k) => k.toString()).toList() ??
              <String>[];
      final content = (raw['content'] as String?) ?? '';
      if (keys.isEmpty || content.isEmpty) {
        skipped++;
        continue;
      }
      final ext = raw['extensions'] as Map<String, dynamic>?;
      importEntries.add(WorldEntry(
        adventureId: currentAdventureId,
        keys: keys,
        content: content,
        insertionOrder: (raw['insertion_order'] as int?) ?? 0,
        probability:
            ext?['probability'] as int? ?? (raw['probability'] as int?) ?? 100,
        cooldown: ext?['cooldown'] as int? ?? (raw['cooldown'] as int?) ?? 0,
        sticky: ext?['sticky'] as int? ?? (raw['sticky'] as int?) ?? 0,
        useRegex: raw['use_regex'] == true || raw['use_regex'] == 1,
        insertPosition: WorldEntryPosition.values[
            ((raw['position'] as int?) ?? 1)
                .clamp(0, WorldEntryPosition.values.length - 1)],
        recursive: ext?['recursive'] == true,
        enabled: raw['enabled'] != false,
      ));
    }

    if (importEntries.isEmpty) {
      return '导入失败：未找到有效条目（跳过 $skipped 条）';
    }

    if (strategy == 'replace') {
      try {
        await _worldEntryRepo.deleteWorldEntriesByAdventure(currentAdventureId);
      } catch (e) {
        debugPrint('[WorldEngine] deleteWorldEntriesByAdventure 失败: $e');
      }
      _worldEntries.clear();
    }

    for (final entry in importEntries) {
      try {
        final id = await _worldEntryRepo.insertWorldEntry(entry);
        entry.id = id;
      } catch (e) {
        debugPrint('[WorldEngine] insertWorldEntry(import) 失败: $e');
      }
      _worldEntries.add(entry);
    }

    notifyParent();
    return '成功导入 ${importEntries.length} 条${skipped > 0 ? '，跳过 $skipped 条（字段缺失）' : ''}';
  }

  Future<void> saveWorldviewPreset(String name, String description,
      {WorldviewDetails? details}) async {
    final preset = WorldviewPreset(
      name: name,
      description: description,
      details: details ?? WorldviewDetails.simple(description),
      worldEntries: _worldEntries
          .map((e) => e.toJson())
          .toList()
          .cast<Map<String, dynamic>>(),
    );
    ResourceIntegrityValidator.validateWorldview(
      name: name,
      description: description,
      details: preset.details,
    );
    final entriesJson = const JsonEncoder().convert(preset.worldEntries);
    final contentHash = ContentHasher.hash({
      'name': name,
      'description': description,
      'entries_json': entriesJson,
      'detail_json': preset.details.toJson(),
    });
    // 内容去重检查（DB不可用时降级跳过检查）
    try {
      if (await DatabaseService.contentHashExists(
          'worldview_presets', contentHash)) {
        return;
      }
    } catch (_) {/* DB unavailable — skip dedup */}
    final now = DateTime.now().toIso8601String();
    await _libraryRepo.saveWorldviewPreset(
      id: preset.id,
      name: name,
      description: description,
      entriesJson: entriesJson,
      now: now,
      contentHash: contentHash,
      detailJson: preset.details.encode(),
    );
    _worldviewPresets.removeWhere((p) => p.id == preset.id);
    _worldviewPresets.insert(0, preset);
    notifyParent();
  }

  Future<void> loadWorldviewPreset(WorldviewPreset preset,
      {required int currentAdventureId,
      required void Function(String worldview) onSetWorldview}) async {
    onSetWorldview(preset.description);
    _worldEntries.clear();
    for (final entryMap in preset.worldEntries) {
      final entry = WorldEntry.fromJson({
        ...entryMap,
        'adventure_id': currentAdventureId,
      });
      try {
        final id = await _worldEntryRepo.insertWorldEntry(entry);
        entry.id = id;
      } catch (e) {
        debugPrint('[WorldEngine] loadWorldviewPreset insert 失败: $e');
      }
      _worldEntries.add(entry);
    }
    notifyParent();
  }

  Future<void> deleteWorldviewPreset(String id) async {
    await _libraryRepo.deleteWorldviewPreset(id);
    _worldviewPresets.removeWhere((p) => p.id == id);
    notifyParent();
  }

  Future<void> loadWorldviewPresets() async {
    try {
      final rows = await _libraryRepo.getWorldviewPresets();
      final loaded = <WorldviewPreset>[];
      for (final r in rows) {
        try {
          final entries =
              (jsonDecode(r['entries_json'] as String) as List<dynamic>)
                  .cast<Map<String, dynamic>>();
          loaded.add(WorldviewPreset(
            id: r['id'] as String,
            name: r['name'] as String,
            description: r['description'] as String,
            worldEntries: entries,
            createdAt: DateTime.tryParse(r['created_at'] as String),
            updatedAt: DateTime.tryParse(r['updated_at'] as String),
            details: WorldviewDetails.fromJson(
              _decodeDetailJson(r['detail_json']),
              fallbackDescription: r['description'] as String? ?? '',
            ),
          ));
        } catch (error) {
          debugPrint('[WorldEngine] 跳过损坏的世界观 ${r['id']}: $error');
        }
      }
      _worldviewPresets = loaded;

      // 首次启动：从旧 SharedPreferences 迁移到数据库
      if (_worldviewPresets.isEmpty) {
        await _migrateFromPrefs();
      }
    } catch (error) {
      debugPrint('[WorldEngine] 加载世界观失败，保留现有内存数据: $error');
    }
    notifyParent();
  }

  Map<String, dynamic>? _decodeDetailJson(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _migrateFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('worldview_presets');
    if (json != null && json.isNotEmpty) {
      try {
        final presets = WorldviewPreset.listFromJson(json);
        _worldviewPresets = presets;
        final now = DateTime.now().toIso8601String();
        for (final p in presets) {
          try {
            await _libraryRepo.saveWorldviewPreset(
              id: p.id,
              name: p.name,
              description: p.description,
              entriesJson: const JsonEncoder().convert(p.worldEntries),
              now: now,
              detailJson: p.details.encode(),
            );
          } catch (e) {
            debugPrint('[WorldEngine] _migrateFromPrefs 保存失败: $e');
          }
        }
        await prefs.remove('worldview_presets');
      } catch (_) {}
    }
  }
}
