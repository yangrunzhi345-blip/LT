import 'dart:convert';

import '../../domain/setting_cards/setting_card.dart';
import '../../models/worldview_details.dart';

/// Reads the structured fields a lightweight setting card keeps inside its
/// single document body.
///
/// A card body is Markdown with `## <key>` sections. Structured values are
/// written as fenced `json` blocks so the editor stays readable while the
/// adventure snapshot can still recover the full-fidelity payload. Everything
/// here is fail-open on purpose: a malformed body must degrade to plain text
/// instead of aborting an adventure start.
final class SettingCardMarkdownParser {
  const SettingCardMarkdownParser();

  static const String structuredPayloadKey = 'structured_payload';
  static const String detailJsonKey = 'detail_json';

  static final RegExp _headingPattern = RegExp(r'^##\s+(.+)$');
  static final RegExp _languageTagPattern = RegExp(r'^[A-Za-z0-9_+.-]*$');

  static const String _fence = '```';
  static const String _archivedStatus = 'archived';
  static const String _confirmedStatus = 'confirmed';
  static const int _detailedFormatVersion = 2;

  /// Legacy tree migration renders sections with the product's Chinese module
  /// titles instead of the storage keys. Without this alias a migrated
  /// worldview would collapse back into one overview module.
  static const Map<String, String> _moduleTitleAliases = <String, String>{
    '概览': 'overview',
    '规则与边界': 'world_rules',
    '当前世界现状': 'world_state',
    '地点与地理': 'locations',
    '势力与组织': 'factions',
    '风俗与生活': 'customs_and_life',
    '历史与时间线': 'timeline',
    '术语表': 'glossary',
    '创作约束': 'creative_constraints',
  };

  /// Chinese character-card sections rendered by the document renderer.
  ///
  /// The renderer writes readable Markdown instead of a JSON document, so the
  /// parser has to turn those human-facing headings and bullet fields back into
  /// the flat/nested payload the adventure snapshot consumes.
  static const Map<String, String> _characterSectionKinds = <String, String>{
    '基础信息': 'basic',
    '性格与心理': 'personality',
    '外貌与体态': 'appearance',
    '背景经历': 'background',
    '世界定位与动机': 'world_profile',
    '能力与装备': 'ability',
    '扮演与对话风格': 'roleplay',
    '自定义属性': 'custom_attributes',
  };

  static const Map<String, String> _basicFieldAliases = <String, String>{
    '姓名': 'name',
    '性别': 'gender',
    '年龄': 'age',
    '职业': 'profession',
    '职业身份': 'profession',
    '身份': 'profession',
    '人物原型': 'archetype',
  };

  static const Map<String, String> _appearanceFieldAliases = <String, String>{
    '外貌': 'appearance',
    '体态': 'bodyDescription',
    '身材': 'bodyDescription',
  };

  static const Map<String, String> _abilityFieldAliases = <String, String>{
    '能力': 'ability',
    '弱点': 'weakness',
    '装备': 'equipment',
  };

  static const Map<String, String> _roleplayFieldAliases = <String, String>{
    '说话风格': 'speaking_style',
    '角色弧光': 'character_arc',
    '开场白': 'first_mes',
    '开场首句': 'first_mes',
    '对话示例': 'mes_example',
  };

  static const Map<String, String> _worldProfileFieldAliases = <String, String>{
    '所属势力': 'faction',
    '常驻地点': 'home_location',
    '公开目标': 'public_goal',
    '隐秘动机': 'hidden_motivation',
    '能力来源': 'ability_source',
    '能力代价': 'ability_cost',
    '禁忌': 'taboos',
    '关系备注': 'relationship_notes',
    '秘密': 'secrets',
  };

  static const List<String> _listProfileKeys = <String>['taboos', 'secrets'];

  static final RegExp _boldFieldPattern =
      RegExp(r'^[-*]\s*\*\*(.+?)\*\*\s*[：:]\s*(.*)$');
  static final RegExp _plainFieldPattern =
      RegExp(r'^[-*]\s*([^：:]{1,16})[：:]\s*(.*)$');
  static final RegExp _cjkPattern = RegExp(r'[\u4e00-\u9fff]');

  /// Parses `## <key>` sections into a flat map.
  ///
  /// A section body that is exactly one fenced `json` block is decoded into its
  /// original Map/List shape; a failed decode keeps the raw text so a broken
  /// block never loses the author's words. A body without any heading is first
  /// tried as a whole JSON document (legacy mirror shape), then falls back to
  /// `description`.
  Map<String, dynamic> parseSections(String content) {
    final text = content.replaceAll('\r\n', '\n');
    final sections = <String, dynamic>{};
    var currentKey = '';
    var inFence = false;
    final body = <String>[];

    void flush() {
      if (currentKey.isEmpty) {
        body.clear();
        return;
      }
      final raw = body.join('\n').trim();
      body.clear();
      sections[currentKey] = _decodeSectionBody(raw);
      currentKey = '';
    }

    for (final line in text.split('\n')) {
      final trimmed = line.trimLeft();
      if (inFence) {
        body.add(line);
        if (trimmed.startsWith(_fence)) inFence = false;
        continue;
      }
      if (trimmed.startsWith(_fence)) {
        // A one-line ```json {...} ``` block opens and closes in the same
        // line; treating it as an unterminated fence would swallow every
        // following section as body text.
        if (trimmed.indexOf(_fence, _fence.length) >= 0) {
          body.add(line);
          continue;
        }
        inFence = true;
        body.add(line);
        continue;
      }
      final match = _headingPattern.firstMatch(line);
      if (match != null) {
        flush();
        currentKey = match.group(1)!.trim();
        continue;
      }
      if (currentKey.isNotEmpty) body.add(line);
    }
    flush();

    if (sections.isNotEmpty) return sections;
    return _fromWholeDocument(text);
  }

  /// Merges the persisted payload with the (authoritative) document sections.
  ///
  /// Priority is content section > metadata payload, with identity fields
  /// falling back to the card row so a snapshot always has a name and body.
  Map<String, dynamic> resolveStructuredPayload(SettingCard card) {
    final payload = <String, dynamic>{};

    final declared = card.metadata[structuredPayloadKey];
    if (declared is Map) {
      for (final entry in declared.entries) {
        final key = entry.key.toString();
        if (key.isEmpty) continue;
        payload[key] = _deepCopy(entry.value);
      }
      _flattenDataEnvelope(payload);
    }

    final sections = _normalizeSections(parseSections(card.content));
    for (final entry in sections.entries) {
      if (!_hasValue(entry.value)) continue;
      _mergeSectionValue(payload, entry.key, entry.value);
    }

    final name = _text(payload['name']);
    if (name.isNotEmpty) {
      payload['name'] = name;
    } else if (card.name.trim().isNotEmpty) {
      payload['name'] = card.name.trim();
    }

    final description = _text(payload['description']);
    if (description.isNotEmpty) {
      payload['description'] = description;
    } else if (card.summary.trim().isNotEmpty) {
      payload['description'] = card.summary.trim();
    } else if (card.content.trim().isNotEmpty) {
      // A rendered document is Markdown, not prose: never let a heading or a
      // JSON document leak into the description the wizard displays.
      final prose = plainProseFromContent(card.content);
      if (prose.isNotEmpty) payload['description'] = prose;
    }

    return payload;
  }

  /// Strips Markdown headings and fenced blocks down to readable prose.
  ///
  /// Used wherever a plain-text description is required (adventure wizard rows,
  /// snapshot fallbacks). Returns '' rather than passing a JSON document through
  /// as prose, because callers persist this text as the user-facing summary.
  static String plainProseFromContent(String content) {
    final text = content.replaceAll('\r\n', '\n').trim();
    if (text.isEmpty || text.startsWith('{') || text.startsWith('[')) return '';
    final lines = <String>[];
    var inFence = false;
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.startsWith(_fence)) {
        inFence = !inFence;
        continue;
      }
      if (inFence || line.isEmpty) continue;
      if (line.startsWith('#')) continue;
      // Field bullets are structured values, not prose; they are re-read by
      // the section parser and must not masquerade as a description.
      if (_boldFieldPattern.hasMatch(line)) continue;
      lines.add(line);
    }
    return lines.join('\n');
  }

  /// Maps English keys through unchanged and Chinese character sections into
  /// structured payload fields.
  ///
  /// Unknown Chinese headings are skipped: they are display-only sections and
  /// must not become payload keys that downstream readers cannot interpret.
  Map<String, dynamic> _normalizeSections(Map<String, dynamic> sections) {
    final result = <String, dynamic>{};
    for (final entry in sections.entries) {
      final key = entry.key.trim();
      final kind = _characterSectionKinds[key];
      if (kind == null) {
        if (!_cjkPattern.hasMatch(key)) result[entry.key] = entry.value;
        continue;
      }
      _applyCharacterSection(kind, entry.value, result);
    }
    return result;
  }

  /// Merges one content section into the accumulated payload.
  ///
  /// A rendered document carries fewer fields than its stored payload (for
  /// example a custom attribute's importance/current value), so structured
  /// maps and lists merge instead of replacing the richer original.
  void _mergeSectionValue(
    Map<String, dynamic> payload,
    String key,
    Object? value,
  ) {
    if (key == 'world_profile' && value is Map) {
      final previous = payload[key];
      payload[key] = <String, dynamic>{
        if (previous is Map)
          for (final entry in previous.entries)
            entry.key.toString(): _deepCopy(entry.value),
        for (final entry in value.entries)
          entry.key.toString(): _deepCopy(entry.value),
      };
      return;
    }
    if (key == 'custom_attributes' && value is List) {
      payload[key] = _mergeCustomAttributes(payload[key], value);
      return;
    }
    payload[key] = value;
  }

  List<dynamic> _mergeCustomAttributes(Object? previous, List incoming) {
    final merged = <Map<String, dynamic>>[];
    final byName = <String, int>{};
    void add(Map<String, dynamic> item) {
      final name = _text(item['name']);
      if (name.isNotEmpty) byName[name] = merged.length;
      merged.add(item);
    }

    if (previous is List) {
      for (final item in previous) {
        if (item is Map) add(_mapCopy(item));
      }
    }
    for (final item in incoming) {
      if (item is! Map) continue;
      final copy = _mapCopy(item);
      final name = _text(copy['name']);
      final index = name.isEmpty ? null : byName[name];
      if (index == null) {
        add(copy);
        continue;
      }
      // The document is authoritative for the fields it renders; the stored
      // payload keeps everything else (importance, ranges, ids).
      merged[index] = <String, dynamic>{...merged[index], ...copy};
    }
    return merged;
  }

  void _applyCharacterSection(
    String kind,
    Object? value,
    Map<String, dynamic> out,
  ) {
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty) return;
      switch (kind) {
        case 'basic':
          _mergeAliasedFields(
              out, _parseFieldBullets(text), _basicFieldAliases);
        case 'personality':
          out['personality'] = text;
        case 'appearance':
          _mergeAliasedFields(
            out,
            _parseFieldBullets(text),
            _appearanceFieldAliases,
          );
        case 'background':
          out['description'] = text;
          // background mirrors description for every existing reader.
          out['background'] = text;
        case 'world_profile':
          final profile = _worldProfileFromBullets(_parseFieldBullets(text));
          if (profile.isNotEmpty) {
            final previous = out['world_profile'];
            out['world_profile'] = <String, dynamic>{
              if (previous is Map)
                for (final entry in previous.entries)
                  entry.key.toString(): entry.value,
              ...profile,
            };
          }
        case 'ability':
          _mergeAliasedFields(
              out, _parseFieldBullets(text), _abilityFieldAliases);
        case 'roleplay':
          _mergeAliasedFields(
            out,
            _parseFieldBullets(text),
            _roleplayFieldAliases,
          );
        case 'custom_attributes':
          final items = _parseCustomAttributes(text);
          if (items.isNotEmpty) out['custom_attributes'] = items;
      }
      return;
    }
    // A fenced JSON block under a Chinese heading is still structured data.
    if (kind == 'world_profile' && value is Map) {
      out['world_profile'] = _mapCopy(value);
    } else if (kind == 'custom_attributes' && value is List) {
      out['custom_attributes'] = _deepCopy(value);
    }
  }

  void _mergeAliasedFields(
    Map<String, dynamic> out,
    Map<String, String> fields,
    Map<String, String> aliases,
  ) {
    for (final entry in fields.entries) {
      final key = aliases[entry.key];
      if (key == null || entry.value.isEmpty) continue;
      out[key] = entry.value;
    }
  }

  Map<String, dynamic> _worldProfileFromBullets(Map<String, String> fields) {
    final profile = <String, dynamic>{};
    for (final entry in fields.entries) {
      final key = _worldProfileFieldAliases[entry.key];
      if (key == null || entry.value.isEmpty) continue;
      profile[key] = _listProfileKeys.contains(key)
          ? _splitList(entry.value)
          : entry.value;
    }
    return profile;
  }

  List<Map<String, String>> _parseCustomAttributes(String text) {
    final items = <Map<String, String>>[];
    for (final entry in _parseFieldBullets(text).entries) {
      items.add(<String, String>{'name': entry.key, 'value': entry.value});
    }
    return items;
  }

  /// Converts rendered `- **name**：description` bullets into item maps.
  ///
  /// Returns an empty list when the module is plain prose, so callers can keep
  /// the backwards-compatible summary map for non-list modules.
  List<Map<String, dynamic>> _bulletModuleItems(String text) {
    final items = <Map<String, dynamic>>[];
    for (final raw in text.split('\n')) {
      final match = _boldFieldPattern.firstMatch(raw.trim());
      if (match == null) continue;
      final name = match.group(1)!.trim();
      if (name.isEmpty) continue;
      final description = match.group(2)!.trim();
      items.add(<String, dynamic>{
        'name': name,
        if (description.isNotEmpty) 'summary': description,
      });
    }
    return items;
  }

  Map<String, String> _parseFieldBullets(String text) {
    final fields = <String, String>{};
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final bold = _boldFieldPattern.firstMatch(line);
      if (bold != null) {
        final label = bold.group(1)!.trim();
        if (label.isNotEmpty) fields[label] = bold.group(2)!.trim();
        continue;
      }
      final plain = _plainFieldPattern.firstMatch(line);
      if (plain != null) {
        final label = plain.group(1)!.trim();
        if (label.isNotEmpty) fields[label] = plain.group(2)!.trim();
      }
    }
    return fields;
  }

  /// Splits a readable list joined by a Chinese comma or semicolon.
  static List<String> _splitList(String value) => value
      .split(RegExp(r'[、；;]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);

  /// Flattens a legacy v2 `data` envelope so snapshot readers see one shape.
  ///
  /// Older cards were persisted as `{spec, spec_version, data: {...}}`. The
  /// nested fields are the authoritative ones, matching [CharacterCard.fromJson],
  /// so they replace the wrapper level instead of being merged under `data`.
  static void _flattenDataEnvelope(Map<String, dynamic> payload) {
    final data = payload['data'];
    if (data is! Map) return;
    final flat = <String, dynamic>{
      for (final entry in payload.entries)
        if (entry.key != 'data') entry.key: entry.value,
    };
    for (final entry in data.entries) {
      flat[entry.key.toString()] = _deepCopy(entry.value);
    }
    payload
      ..clear()
      ..addAll(flat);
  }

  /// Resolves the worldview `detail_json` with three decreasing priorities.
  ///
  /// 1. the document itself (`## detail` or the known `## <moduleKey>` sections),
  /// 2. `metadata[detail_json]` written by the generator,
  /// 3. [WorldviewDetails.simple] over the body.
  ///
  /// Every module that is not archived is normalized to `confirmed` so a
  /// generated draft cannot silently stay invisible to the adventure context.
  /// Normalization always works on a copy: the card's metadata is immutable.
  Map<String, dynamic> resolveWorldviewDetail(SettingCard card) {
    final fromContent = _detailFromContent(card.content);
    final fromMetadata = _detailFromMetadata(card);

    if (fromContent != null && fromMetadata != null) {
      // Section-level edits are authoritative for the modules they contain,
      // but modules the user did not touch must survive from the payload.
      final mergedModules = _mergeModuleMaps(
        _mapCopy(fromMetadata['modules']),
        _mapCopy(fromContent['modules']),
      );
      return <String, dynamic>{
        ...fromMetadata,
        ...fromContent,
        'modules': _normalizedModules(mergedModules),
      };
    }
    if (fromContent != null) return fromContent;
    if (fromMetadata != null) return fromMetadata;

    return WorldviewDetails.simple(card.content).toJson();
  }

  Map<String, dynamic>? _detailFromContent(String content) {
    final sections = parseSections(content);

    // `renderGeneratedDocument` writes the structured payload under its raw key
    // (`## detail_json`), while `LegacyCardMirror` writes `## detail`. Accept
    // both spellings so a generated card and a migrated one restore alike.
    final detail = sections['detail'] ?? sections['detail_json'];
    if (detail is Map) {
      final copy = _mapCopy(detail);
      copy['modules'] = _normalizedModules(copy['modules']);
      return copy;
    }

    final modules = <String, dynamic>{};
    for (final entry in sections.entries) {
      final key = _moduleKeyFor(entry.key);
      if (key == null) continue;
      final value = entry.value;
      if (value is String) {
        final text = value.trim();
        if (text.isEmpty) continue;
        // A rendered entry list is readable Markdown bullets; turning them back
        // into item maps keeps per-entry names available (keywords, entries).
        final items = _bulletModuleItems(text);
        modules[key] =
            items.isEmpty ? <String, dynamic>{'summary': text} : items;
        continue;
      }
      if (value is Map || value is List) {
        if (!_hasValue(value)) continue;
        modules[key] = value;
      }
    }
    if (modules.isEmpty) return null;
    return <String, dynamic>{
      'format_version': _detailedFormatVersion,
      'mode': 'detailed',
      'modules': _normalizedModules(modules),
    };
  }

  /// Resolves modules from a card body alone (no metadata), or null when the
  /// body carries no module sections. Used by generation to hand the context
  /// budgeter structured modules instead of unfiltered prose.
  Map<String, dynamic>? parseWorldviewDetailFromContent(String content) =>
      _detailFromContent(content);

  /// Merges a parsed document's modules over the stored payload.
  ///
  /// A rendered document only carries readable text, so replacing a stored
  /// module wholesale would drop structured fields the renderer never prints
  /// (terrain, ideology, per-entry metadata). Entries merge by name, with the
  /// document winning on the fields it does carry.
  static Map<String, dynamic> _mergeModuleMaps(
    Map<String, dynamic> stored,
    Map<String, dynamic> parsed,
  ) {
    final merged = <String, dynamic>{
      for (final entry in stored.entries) entry.key: _deepCopy(entry.value),
    };
    for (final entry in parsed.entries) {
      merged[entry.key] = _mergeModuleValue(merged[entry.key], entry.value);
    }
    return merged;
  }

  static dynamic _mergeModuleValue(dynamic current, dynamic next) {
    if (current is List && next is List) return _mergeEntryLists(current, next);
    if (current is Map && next is List) {
      // A generated module is a Map holding `content` + `items`; a later hand
      // edit turns its section into bullets. Merge into the stored items so the
      // structured fields the bullets do not print are not thrown away.
      final items = current['items'];
      return <String, dynamic>{
        for (final entry in current.entries)
          entry.key.toString(): _deepCopy(entry.value),
        'items':
            items is List ? _mergeEntryLists(items, next) : _deepCopy(next),
      };
    }
    if (current is Map && next is Map) {
      final result = <String, dynamic>{
        for (final entry in current.entries)
          entry.key.toString(): _deepCopy(entry.value),
      };
      for (final entry in next.entries) {
        final key = entry.key.toString();
        result[key] = _mergeModuleValue(result[key], entry.value);
      }
      return result;
    }
    return _deepCopy(next);
  }

  static List<dynamic> _mergeEntryLists(
    List<dynamic> current,
    List<dynamic> next,
  ) {
    final result = <dynamic>[for (final item in current) _deepCopy(item)];
    for (final item in next) {
      final name = _entryName(item);
      if (name.isNotEmpty) {
        final index =
            result.indexWhere((existing) => _entryName(existing) == name);
        if (index >= 0) {
          result[index] = _mergeModuleValue(result[index], item);
          continue;
        }
      }
      result.add(_deepCopy(item));
    }
    return result;
  }

  static String _entryName(dynamic item) {
    if (item is! Map) return '';
    for (final key in const <String>[
      'name',
      'title',
      'term',
      'event',
      'label'
    ]) {
      final value = item[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  static String? _moduleKeyFor(String rawKey) {
    final key = rawKey.trim();
    if (key.isEmpty) return null;
    if (WorldviewDetails.moduleKeys.contains(key)) return key;
    return _moduleTitleAliases[key];
  }

  Map<String, dynamic>? _detailFromMetadata(SettingCard card) {
    var raw = card.metadata[detailJsonKey];
    if (raw is String) raw = _tryDecodeJson(raw);
    if (raw is! Map || raw.isEmpty) return null;

    final copy = _mapCopy(raw);
    copy['modules'] = _normalizedModules(copy['modules']);
    return copy;
  }

  /// Deep-copies modules and promotes non-archived statuses to `confirmed`.
  Map<String, dynamic> _normalizedModules(Object? raw) {
    final modules = <String, dynamic>{};
    if (raw is! Map) return modules;
    for (final entry in raw.entries) {
      final key = entry.key.toString();
      if (key.isEmpty) continue;
      modules[key] = _normalizeModule(_deepCopy(entry.value));
    }
    return modules;
  }

  dynamic _normalizeModule(Object? value) {
    if (value is Map) {
      final copy = Map<String, dynamic>.from(value);
      if (copy['status'] != _archivedStatus) copy['status'] = _confirmedStatus;
      return copy;
    }
    if (value is List) {
      return [
        for (final item in value)
          if (item is Map)
            _withConfirmedStatus(Map<String, dynamic>.from(item))
          else
            item,
      ];
    }
    return value;
  }

  Map<String, dynamic> _withConfirmedStatus(Map<String, dynamic> item) {
    if (item['status'] != _archivedStatus) item['status'] = _confirmedStatus;
    return item;
  }

  Map<String, dynamic> _fromWholeDocument(String text) {
    final decoded = _tryDecodeJson(text.trim());
    if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);
      final data = map['data'];
      // A LegacyCardMirror row keeps a SillyTavern `data` envelope; unwrap it so
      // the flat card fields are reachable without a second special case.
      return data is Map ? Map<String, dynamic>.from(data) : map;
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) return <String, dynamic>{};
    return <String, dynamic>{'description': trimmed};
  }

  dynamic _decodeSectionBody(String raw) {
    if (raw.length < _fence.length * 2 ||
        !raw.startsWith(_fence) ||
        !raw.endsWith(_fence)) {
      return raw;
    }
    var inner = raw.substring(_fence.length, raw.length - _fence.length).trim();
    inner = _stripLanguageTag(inner);
    final decoded = _tryDecodeJson(inner);
    return decoded ?? raw;
  }

  String _stripLanguageTag(String inner) {
    final newline = inner.indexOf('\n');
    if (newline < 0) return inner;
    final first = inner.substring(0, newline).trim();
    if (_languageTagPattern.hasMatch(first)) {
      return inner.substring(newline + 1).trim();
    }
    return inner;
  }

  static Object? _tryDecodeJson(String source) {
    if (source.isEmpty) return null;
    try {
      return jsonDecode(source);
    } catch (_) {
      return null;
    }
  }

  static bool _hasValue(Object? value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    if (value is List) return value.isNotEmpty;
    return true;
  }

  static String _text(Object? value) {
    if (value is String) return value.trim();
    if (value is num || value is bool) return value.toString().trim();
    return '';
  }

  /// Deep-copies a map into a mutable `Map<String, dynamic>`.
  static Map<String, dynamic> _mapCopy(Object? value) {
    if (value is! Map) return <String, dynamic>{};
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _deepCopy(entry.value),
    };
  }

  static Object? _deepCopy(Object? value) {
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          entry.key.toString(): _deepCopy(entry.value),
      };
    }
    if (value is List) return [for (final item in value) _deepCopy(item)];
    return value;
  }
}
