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

    for (final entry in parseSections(card.content).entries) {
      if (!_hasValue(entry.value)) continue;
      payload[entry.key] = entry.value;
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
      payload['description'] = card.content.trim();
    }

    return payload;
  }

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
      final mergedModules = <String, dynamic>{
        ..._mapCopy(fromMetadata['modules']),
        ..._mapCopy(fromContent['modules']),
      };
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
        if (text.isNotEmpty) modules[key] = <String, dynamic>{'summary': text};
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
