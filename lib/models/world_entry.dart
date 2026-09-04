import 'dart:convert';

enum WorldEntryPosition {
  beforePrompt,
  afterPrompt,
  inAuthorNote,
  beforeHistory,
  afterUser,
}

extension WorldEntryPositionExtension on WorldEntryPosition {
  String get displayName => switch (this) {
        WorldEntryPosition.beforePrompt => '系统提示之前',
        WorldEntryPosition.afterPrompt => '系统提示之后',
        WorldEntryPosition.inAuthorNote => '作者注释中',
        WorldEntryPosition.beforeHistory => '历史消息之前',
        WorldEntryPosition.afterUser => '用户消息之后',
      };
}

class WorldEntry {
  int? id;
  int adventureId;
  List<String> keys;
  String content;
  int insertionOrder;
  int probability;
  int cooldown;
  int sticky;
  bool useRegex;
  WorldEntryPosition insertPosition;
  bool recursive;
  bool enabled;
  String sourceType;
  String sourceId;
  String sourceSnapshotHash;

  WorldEntry({
    this.id,
    this.adventureId = 0,
    List<String>? keys,
    this.content = '',
    this.insertionOrder = 0,
    this.probability = 100,
    this.cooldown = 0,
    this.sticky = 0,
    this.useRegex = false,
    this.insertPosition = WorldEntryPosition.afterPrompt,
    this.recursive = false,
    this.enabled = true,
    this.sourceType = '',
    this.sourceId = '',
    this.sourceSnapshotHash = '',
  }) : keys = keys ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'adventure_id': adventureId,
        'keys': keys,
        'content': content,
        'insertion_order': insertionOrder,
        'probability': probability,
        'cooldown': cooldown,
        'sticky': sticky,
        'use_regex': useRegex,
        'insert_position': insertPosition.index,
        'recursive': recursive,
        'enabled': enabled,
        'source_type': sourceType,
        'source_id': sourceId,
        'source_snapshot_hash': sourceSnapshotHash,
      };

  factory WorldEntry.fromJson(Map<String, dynamic> json) {
    List<String> parseKeys(dynamic keysVal) {
      if (keysVal is String) {
        return (jsonDecode(keysVal) as List<dynamic>).cast<String>();
      }
      if (keysVal is List) {
        return keysVal.cast<String>();
      }
      return [];
    }

    return WorldEntry(
      id: json['id'] as int?,
      adventureId: json['adventure_id'] as int? ?? 0,
      keys: parseKeys(json['keys']),
      content: json['content'] as String? ?? '',
      insertionOrder: json['insertion_order'] as int? ?? 0,
      probability: json['probability'] as int? ?? 100,
      cooldown: json['cooldown'] as int? ?? 0,
      sticky: json['sticky'] as int? ?? 0,
      useRegex: json['use_regex'] == 1 || json['use_regex'] == true,
      insertPosition:
          WorldEntryPosition.values[(json['insert_position'] as int?) ?? 1],
      recursive: json['recursive'] == 1,
      enabled: json['enabled'] == 1,
      sourceType: json['source_type'] as String? ?? '',
      sourceId: json['source_id'] as String? ?? '',
      sourceSnapshotHash: json['source_snapshot_hash'] as String? ?? '',
    );
  }

  Map<String, dynamic> toDbMap() {
    final map = toJson();
    map['keys'] = jsonEncode(keys);
    map['enabled'] = enabled ? 1 : 0;
    map['recursive'] = recursive ? 1 : 0;
    map['use_regex'] = useRegex ? 1 : 0;
    return map;
  }

  factory WorldEntry.fromDbMap(Map<String, dynamic> map) {
    return WorldEntry.fromJson(map);
  }

  /// 检查给定的文本是否匹配任意关键词（不区分大小写）
  bool matches(String text) {
    final lower = text.toLowerCase();
    for (final key in keys.map((k) => k.trim()).where((k) => k.isNotEmpty)) {
      if (useRegex) {
        try {
          if (RegExp(key, caseSensitive: false).hasMatch(text)) return true;
        } catch (_) {
          if (lower.contains(key.toLowerCase())) return true;
        }
      } else {
        if (lower.contains(key.toLowerCase())) return true;
      }
    }
    return false;
  }

  WorldEntry copyWith({
    int? id,
    int? adventureId,
    List<String>? keys,
    String? content,
    int? insertionOrder,
    int? probability,
    int? cooldown,
    int? sticky,
    bool? recursive,
    bool? enabled,
    bool? useRegex,
    WorldEntryPosition? insertPosition,
    String? sourceType,
    String? sourceId,
    String? sourceSnapshotHash,
  }) {
    return WorldEntry(
      id: id ?? this.id,
      adventureId: adventureId ?? this.adventureId,
      keys: keys ?? this.keys,
      content: content ?? this.content,
      insertionOrder: insertionOrder ?? this.insertionOrder,
      probability: probability ?? this.probability,
      cooldown: cooldown ?? this.cooldown,
      sticky: sticky ?? this.sticky,
      recursive: recursive ?? this.recursive,
      enabled: enabled ?? this.enabled,
      useRegex: useRegex ?? this.useRegex,
      insertPosition: insertPosition ?? this.insertPosition,
      sourceType: sourceType ?? this.sourceType,
      sourceId: sourceId ?? this.sourceId,
      sourceSnapshotHash: sourceSnapshotHash ?? this.sourceSnapshotHash,
    );
  }
}
