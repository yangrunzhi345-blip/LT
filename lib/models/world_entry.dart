import 'dart:convert';

enum WorldEntryPosition {
  beforePrompt,
  afterPrompt,
  inAuthorNote,
  beforeHistory,
  afterUser,
}

extension WorldEntryPositionExtension on WorldEntryPosition {
  String get storageCode => switch (this) {
        WorldEntryPosition.beforePrompt => 'before_prompt',
        WorldEntryPosition.afterPrompt => 'after_prompt',
        WorldEntryPosition.inAuthorNote => 'in_author_note',
        WorldEntryPosition.beforeHistory => 'before_history',
        WorldEntryPosition.afterUser => 'after_user',
      };

  String get displayName => switch (this) {
        WorldEntryPosition.beforePrompt => '系统提示之前',
        WorldEntryPosition.afterPrompt => '系统提示之后',
        WorldEntryPosition.inAuthorNote => '作者注释中',
        WorldEntryPosition.beforeHistory => '历史消息之前',
        WorldEntryPosition.afterUser => '用户消息之后',
      };

  static WorldEntryPosition decode(Object? value) => switch (value) {
        'before_prompt' || 'beforePrompt' => WorldEntryPosition.beforePrompt,
        'after_prompt' || 'afterPrompt' => WorldEntryPosition.afterPrompt,
        'in_author_note' || 'inAuthorNote' => WorldEntryPosition.inAuthorNote,
        'before_history' || 'beforeHistory' => WorldEntryPosition.beforeHistory,
        'after_user' || 'afterUser' => WorldEntryPosition.afterUser,
        0 => WorldEntryPosition.beforePrompt,
        1 => WorldEntryPosition.afterPrompt,
        2 => WorldEntryPosition.inAuthorNote,
        3 => WorldEntryPosition.beforeHistory,
        4 => WorldEntryPosition.afterUser,
        _ => throw const FormatException('unknown world entry position'),
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

  /// Assembly revision this entry's content was derived from (Phase 10).
  /// Empty for entries that do not come from a versioned resource assembly.
  String sourceRevisionId;

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
    this.sourceRevisionId = '',
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
        'insert_position': insertPosition.storageCode,
        'recursive': recursive,
        'enabled': enabled,
        'source_type': sourceType,
        'source_id': sourceId,
        'source_snapshot_hash': sourceSnapshotHash,
        'source_revision_id': sourceRevisionId,
      };

  factory WorldEntry.fromJson(
    Map<String, dynamic> json, {
    bool requirePersistedIdentity = false,
    void Function(String category)? onOptionalFallback,
  }) {
    List<String> parseKeys(dynamic keysVal) {
      if (keysVal is String) {
        try {
          final decoded = jsonDecode(keysVal);
          if (decoded is List && decoded.every((value) => value is String)) {
            return decoded.cast<String>();
          }
        } on FormatException {
          // The optional-field policy below records a payload-free diagnostic.
        }
        onOptionalFallback?.call('malformed_keys');
        return const [];
      }
      if (keysVal is List && keysVal.every((value) => value is String)) {
        return keysVal.cast<String>();
      }
      if (keysVal != null) {
        onOptionalFallback?.call('malformed_keys');
      }
      return [];
    }

    int optionalInt(String key, int fallback) {
      final value = json[key];
      if (value == null) return fallback;
      if (value is num) return value.toInt();
      onOptionalFallback?.call('malformed_$key');
      return fallback;
    }

    String optionalString(String key) {
      final value = json[key];
      if (value == null) return '';
      if (value is String) return value;
      onOptionalFallback?.call('malformed_$key');
      return '';
    }

    final rawId = json['id'];
    final id = rawId is num ? rawId.toInt() : null;
    final rawAdventureId = json['adventure_id'];
    final adventureId = rawAdventureId is num ? rawAdventureId.toInt() : null;
    if (requirePersistedIdentity && (id == null || adventureId == null)) {
      throw const FormatException('invalid persisted identity');
    }

    return WorldEntry(
      id: id,
      adventureId: adventureId ?? 0,
      keys: parseKeys(json['keys']),
      content: optionalString('content'),
      insertionOrder: optionalInt('insertion_order', 0),
      probability: optionalInt('probability', 100),
      cooldown: optionalInt('cooldown', 0),
      sticky: optionalInt('sticky', 0),
      useRegex: json['use_regex'] == 1 || json['use_regex'] == true,
      insertPosition: WorldEntryPositionExtension.decode(
        json['insert_position'] ?? 'after_prompt',
      ),
      recursive: json['recursive'] == 1,
      enabled: json['enabled'] == 1,
      sourceType: optionalString('source_type'),
      sourceId: optionalString('source_id'),
      sourceSnapshotHash: optionalString('source_snapshot_hash'),
      sourceRevisionId: optionalString('source_revision_id'),
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
    return WorldEntry.fromJson(map, requirePersistedIdentity: true);
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
    String? sourceRevisionId,
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
      sourceRevisionId: sourceRevisionId ?? this.sourceRevisionId,
    );
  }
}
