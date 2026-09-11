import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'custom_attribute_item.dart';
import 'custom_status_change.dart';

/// The four shapes a model response can take.  Keeping them explicit lets the
/// engine, widgets and tests agree on what may be shown as narrative.
enum AdventureResponseKind {
  /// Prose plus a decodable settlement payload.
  narrativeWithPayload,

  /// A decodable payload with no prose (pure JSON).  Must never be displayed
  /// as narrative; the engine keeps the payload and may request a supplement.
  payloadOnly,

  /// Ordinary prose without a payload.
  plainNarrative,

  /// A structured-looking but undecodable payload (truncated / corrupted).
  malformedStructured,
}

/// Result of [AdventureResponse.parse].
class AdventureResponseParse {
  final AdventureResponseKind kind;
  final List<String> narrative;
  final Map<String, dynamic>? payload;

  const AdventureResponseParse({
    required this.kind,
    this.narrative = const [],
    this.payload,
  });

  bool get hasPayload => payload != null;
  bool get hasNarrative =>
      narrative.any((paragraph) => paragraph.trim().isNotEmpty);
}

/// Only fields explicitly accepted from the model are present.  Missing or
/// malformed values must never reset a player's state to a parser default.
class AdventureStatePatch {
  final int? hp, maxHp, energy, maxEnergy, gold;
  final String? scene;
  final List<String>? inventory;
  const AdventureStatePatch(
      {this.hp,
      this.maxHp,
      this.energy,
      this.maxEnergy,
      this.gold,
      this.scene,
      this.inventory});
}

class AdventureResponse with Equatable {
  final String scene;
  final int hp;
  final int maxHp;
  final int energy;
  final int maxEnergy;
  final int gold;
  final List<String> inventory;
  final List<String> narrative;
  final List<String> options;
  final List<CustomAttributeItem> customStatus;
  final List<CustomStatusChange> customStatusChanges;
  final AdventureStatePatch patch;

  const AdventureResponse({
    required this.scene,
    required this.hp,
    required this.maxHp,
    required this.energy,
    required this.maxEnergy,
    required this.gold,
    required this.inventory,
    required this.narrative,
    required this.options,
    this.customStatus = const [],
    this.customStatusChanges = const [],
    this.patch = const AdventureStatePatch(),
  });

  factory AdventureResponse.fromJson(Map<String, dynamic> json,
      {List<String> narrative = const []}) {
    return AdventureResponse(
      scene: _text(json['scene']) ?? '',
      hp: _number(json['hp']) ?? 100,
      maxHp: _number(json['max_hp']) ?? 100,
      energy: _number(json['energy']) ?? 100,
      maxEnergy: _number(json['max_energy']) ?? 100,
      gold: _number(json['gold']) ?? 0,
      inventory: _strings(json['inventory']),
      narrative: narrative,
      options: _strings(json['options'], max: 6),
      customStatus: _parseCustomStatus(
          json['custom_status'] ?? json['custom_attributes']),
      customStatusChanges:
          parseCustomStatusChanges(json['custom_status_changes']),
      patch: AdventureStatePatch(
        scene: _text(json['scene']),
        hp: _number(json['hp']),
        maxHp: _number(json['max_hp']),
        energy: _number(json['energy']),
        maxEnergy: _number(json['max_energy']),
        gold: _number(json['gold']),
        inventory:
            json['inventory'] is List ? _strings(json['inventory']) : null,
      ),
    );
  }

  /// Canonical separator between human narrative and the settlement payload.
  static const jsonSeparator = '---JSON---';

  /// Tolerates the separator variants models actually emit: `---JSON---`,
  /// `--- JSON ---`, `---\nJSON---`, plus arbitrary surrounding whitespace.
  static final RegExp _separatorPattern =
      RegExp(r'\n?\s*---\s*JSON\s*---\s*\n?');

  /// Shared accessor so the engine never re-implements its own separator scan.
  static RegExp get separatorPattern => _separatorPattern;

  /// Keys that identify a model settlement payload.  Requiring at least one of
  /// them prevents random prose braces from being mistaken for structured data.
  static const _payloadKeys = <String>{
    'scene',
    'options',
    'hp',
    'max_hp',
    'maxHp',
    'energy',
    'max_energy',
    'maxEnergy',
    'gold',
    'inventory',
    'custom_status',
    'custom_attributes',
    'custom_status_changes',
    'narrative',
    'scene_candidates',
    'runtime_state_changes',
  };

  static final RegExp _payloadKeyPattern = RegExp(
      r'"(scene|options|hp|max_hp|maxHp|energy|max_energy|maxEnergy|gold|'
      r'inventory|custom_status|custom_attributes|custom_status_changes|'
      r'narrative|scene_candidates|runtime_state_changes)"\s*:');

  /// Protocol-level classification of a model response.
  ///
  /// The engine must never show raw structured data as narrative, so every
  /// caller works from one of these four explicit kinds instead of guessing
  /// with string heuristics at the UI layer.
  static AdventureResponseParse parse(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      return const AdventureResponseParse(
          kind: AdventureResponseKind.plainNarrative);
    }

    // 1. Explicit `---JSON---` block (possibly repeated).  The last separator
    //    that yields a decodable object wins; earlier text stays narrative.
    final matches = _separatorPattern.allMatches(trimmed).toList();
    if (matches.isNotEmpty) {
      for (final sepMatch in matches.reversed) {
        final payload = _decodeObject(trimmed.substring(sepMatch.end));
        if (payload == null) continue;
        final narrative = _paragraphs(trimmed.substring(0, sepMatch.start));
        final embedded = _mapNarrative(payload);
        if (narrative.isEmpty && embedded.isEmpty) {
          return AdventureResponseParse(
            kind: AdventureResponseKind.payloadOnly,
            payload: payload,
          );
        }
        return AdventureResponseParse(
          kind: AdventureResponseKind.narrativeWithPayload,
          narrative: narrative.isNotEmpty ? narrative : embedded,
          payload: payload,
        );
      }
      final leading = _paragraphs(trimmed.substring(0, matches.last.start));
      if (leading.isNotEmpty) {
        return AdventureResponseParse(
            kind: AdventureResponseKind.plainNarrative, narrative: leading);
      }
      return const AdventureResponseParse(
          kind: AdventureResponseKind.malformedStructured);
    }

    // 2. The whole response is a single JSON object (pure JSON).
    final whole = _decodeObject(trimmed);
    if (whole != null && _isPayloadLike(whole)) {
      final embedded = _mapNarrative(whole);
      return AdventureResponseParse(
        kind: embedded.isEmpty
            ? AdventureResponseKind.payloadOnly
            : AdventureResponseKind.narrativeWithPayload,
        narrative: embedded,
        payload: whole,
      );
    }

    // 3. A structured payload embedded at the tail of prose without the
    //    separator.  This is the common real-world leak source.
    final inline = _splitEmbeddedPayload(trimmed);
    if (inline != null) {
      final (leading, payload) = inline;
      final embedded = _mapNarrative(payload);
      if (leading.isEmpty) {
        return AdventureResponseParse(
          kind: AdventureResponseKind.payloadOnly,
          narrative: embedded,
          payload: payload,
        );
      }
      return AdventureResponseParse(
        kind: AdventureResponseKind.narrativeWithPayload,
        narrative: _paragraphs(leading),
        payload: payload,
      );
    }

    // 4. Structured-looking but undecodable (truncated / corrupted JSON).
    if (_looksStructured(trimmed)) {
      return const AdventureResponseParse(
          kind: AdventureResponseKind.malformedStructured);
    }

    return AdventureResponseParse(
      kind: AdventureResponseKind.plainNarrative,
      narrative: _paragraphs(trimmed),
    );
  }

  /// Rewrites any response into the canonical `narrative + ---JSON--- + payload`
  /// (or payload-only) form.  Malformed structured tails are stripped so raw
  /// JSON can never survive into the displayed narrative.
  static String canonicalize(String content) {
    final parsed = parse(content);
    switch (parsed.kind) {
      case AdventureResponseKind.narrativeWithPayload:
        final narrative = parsed.narrative.join('\n\n').trim();
        final payload = jsonEncode(parsed.payload);
        return narrative.isEmpty
            ? '$jsonSeparator\n$payload'
            : '$narrative\n$jsonSeparator\n$payload';
      case AdventureResponseKind.payloadOnly:
        return '$jsonSeparator\n${jsonEncode(parsed.payload)}';
      case AdventureResponseKind.malformedStructured:
        return _proseBeforeStructured(content);
      case AdventureResponseKind.plainNarrative:
        // `parse` already dropped any structured/undecodable tail; use its
        // paragraphs so a damaged payload cannot ride along as prose.
        return parsed.narrative.isEmpty
            ? _proseBeforeStructured(content)
            : parsed.narrative.join('\n\n').trim();
    }
  }

  /// Projects a persisted assistant message into the narrative-only form that
  /// is sent back to the LLM as history.
  ///
  /// The settlement payload (`custom_status` full snapshot, already-applied
  /// `custom_status_changes`, `hp/gold/inventory/scene`, options, and other
  /// locally-maintained machine state) must never be re-fed to the model.
  /// Re-sending the full snapshot is what lets the model imitate and re-inflate
  /// the JSON round after round. Local state is injected separately by the
  /// runtime, so history only needs the narrative for continuity.
  static String llmHistoryProjection(String content) {
    final parsed = parse(content);
    switch (parsed.kind) {
      case AdventureResponseKind.narrativeWithPayload:
      case AdventureResponseKind.plainNarrative:
        return parsed.narrative.join('\n\n').trim();
      case AdventureResponseKind.payloadOnly:
      case AdventureResponseKind.malformedStructured:
        return '';
    }
  }

  /// Parse the split response: narrative text before ---JSON---, JSON after.
  static AdventureResponse? tryParseSplit(String content) {
    final parsed = parse(content);
    final payload = parsed.payload;
    if (payload == null) return null;
    return AdventureResponse.fromJson(payload, narrative: parsed.narrative);
  }

  static List<String> _mapNarrative(Map<String, dynamic> map) {
    final value = map['narrative'];
    if (value is List) {
      return value
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (value is String && value.trim().isNotEmpty) return [value.trim()];
    return const [];
  }

  static List<String> _paragraphs(String text) => text
      .trim()
      .split(RegExp(r'\n\s*\n'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty && !_isSectionLabel(s))
      .toList();

  static bool _isPayloadLike(Map<String, dynamic> map) =>
      map.keys.any(_payloadKeys.contains);

  /// Finds a decodable, payload-shaped JSON object at the tail of prose.
  static (String, Map<String, dynamic>)? _splitEmbeddedPayload(String text) {
    for (var index = 0; index < text.length; index++) {
      if (text.codeUnitAt(index) != 0x7B /* { */) continue;
      final suffix = text.substring(index).trimRight();
      if (!_startsJsonObject(suffix)) continue;
      final decoded = _decodeObject(suffix);
      if (decoded == null || !_isPayloadLike(decoded)) continue;
      return (text.substring(0, index).trim(), decoded);
    }
    return null;
  }

  static String _proseBeforeStructured(String content) {
    final index = content.indexOf('{');
    final bracket = content.indexOf('[');
    final structuredAt = switch ((index < 0, bracket < 0)) {
      (true, true) => -1,
      (false, true) => index,
      (true, false) => bracket,
      (false, false) => index < bracket ? index : bracket,
    };
    if (structuredAt < 0) return '';
    return content.substring(0, structuredAt).trim();
  }

  static bool _looksStructured(String text) {
    final cleaned = cleanJsonBlock(text);
    final trimmed = cleaned.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) return true;
    return trimmed.contains('{') && _payloadKeyPattern.hasMatch(trimmed);
  }

  static bool _startsJsonObject(String text) {
    final trimmed = text.trimLeft();
    if (!trimmed.startsWith('{')) return false;
    final after = trimmed.substring(1).trimLeft();
    return after.startsWith('"') || after.startsWith('}');
  }

  /// Try to parse pure JSON response
  static AdventureResponse? tryParse(String jsonString) {
    try {
      final map = _decodeObject(jsonString);
      if (map == null) return null;
      final narrative = (map['narrative'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      return AdventureResponse.fromJson(map, narrative: narrative);
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _decodeObject(String text) {
    final cleaned = cleanJsonBlock(text);
    try {
      final value = jsonDecode(cleaned);
      return value is Map<String, dynamic> ? value : null;
    } catch (_) {
      try {
        final value = jsonDecode(repairJson(cleaned));
        return value is Map<String, dynamic> ? value : null;
      } catch (_) {
        return null;
      }
    }
  }

  static int? _number(dynamic value) {
    final n = value is num ? value.toInt() : null;
    return n != null && n >= 0 && n <= 100000000 ? n : null;
  }

  static String? _text(dynamic value) {
    final text = value is String ? value.trim() : '';
    return text.isEmpty || text.length > 500 ? null : text;
  }

  static List<String> _strings(dynamic value, {int max = 100}) {
    if (value is! List) return const [];
    final seen = <String>{};
    return value
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty && e.length <= 200)
        .where((e) => seen.add(e.replaceAll(RegExp(r'\s+'), '')))
        .take(max)
        .toList();
  }

  /// Get streaming display text.  Hides both a completed `---JSON---` section
  /// and a payload that is still being streamed (including pure JSON), so a
  /// partially received settlement never flashes into the narrative bubble.
  static String streamingDisplayText(String accumulated) {
    if (accumulated.isEmpty) return accumulated;
    final match = RegExp(r'\n?\s*---JSON---').firstMatch(accumulated);
    if (match != null) return accumulated.substring(0, match.start);
    final structuredStart = _streamingStructuredStart(accumulated);
    if (structuredStart >= 0) {
      return accumulated.substring(0, structuredStart);
    }
    return accumulated;
  }

  /// Index where a trailing/embedded settlement payload begins, if any.
  static int _streamingStructuredStart(String text) {
    if (!text.contains('{')) return -1;
    for (var index = 0; index < text.length; index++) {
      if (text.codeUnitAt(index) != 0x7B /* { */) continue;
      final suffix = text.substring(index);
      if (!_startsJsonObject(suffix.trimRight())) continue;
      final decoded = _decodeObject(suffix);
      if (decoded != null && _isPayloadLike(decoded)) return index;
      if (_payloadKeyPattern.hasMatch(suffix)) return index;
      // A line-leading `{"` is the start of an in-progress payload even before
      // its first key has fully streamed.
      if (_isLineStart(text, index) &&
          RegExp(r'^\{\s*"').hasMatch(suffix.trimLeft())) {
        return index;
      }
    }
    return -1;
  }

  static bool _isLineStart(String text, int index) {
    if (index == 0) return true;
    final previous = text.codeUnitAt(index - 1);
    return previous == 0x0A /* \n */ || previous == 0x0D /* \r */;
  }

  /// 清理 JSON 代码块标记
  static String cleanJsonBlock(String text) {
    var cleaned = text.trim();
    if (cleaned.startsWith('```json')) {
      cleaned = cleaned.substring(7);
    } else if (cleaned.startsWith('```')) {
      cleaned = cleaned.substring(3);
    }
    if (cleaned.endsWith('```')) {
      cleaned = cleaned.substring(0, cleaned.length - 3);
    }
    return cleaned.trim();
  }

  /// 判断段落是否为分段标签（如"第一段"、"第二段：xxx"等，≤30字过滤不显示）
  static final _sectionLabelRe = RegExp(r'^第[一二三四五六七八九十\d]+段');

  static bool _isSectionLabel(String paragraph) {
    if (paragraph.length > 30) return false;
    return _sectionLabelRe.hasMatch(paragraph);
  }

  /// 修复常见 JSON 语法问题
  static String repairJson(String text) {
    var repaired = cleanJsonBlock(text);
    // 移除尾部逗号
    repaired = repaired.replaceAll(RegExp(r',\s*}'), '}');
    repaired = repaired.replaceAll(RegExp(r',\s*]'), ']');
    // 移除单行注释
    repaired = repaired.replaceAll(RegExp(r'//.*', multiLine: false), '');
    // 修复单引号为双引号（key 和 value）
    repaired = repaired.replaceAll("'", '"');
    return repaired;
  }

  /// 将任意格式的自定义状态数据统一解析为 List<CustomAttributeItem>
  static List<CustomAttributeItem> parseCustomStatus(dynamic value) =>
      _parseCustomStatus(value);

  /// 解析 `custom_status_changes`（Delta 增量协议），非法项被丢弃。
  static List<CustomStatusChange> parseCustomStatusChanges(dynamic value) {
    final diagnostics = <String>[];
    return CustomStatusChange.parse(value, diagnostics: diagnostics);
  }

  static List<CustomAttributeItem> _parseCustomStatus(dynamic value) {
    if (value == null) return const [];
    if (value is List) {
      final items = <CustomAttributeItem>[];
      for (final item in value) {
        if (item is Map<String, dynamic>) {
          items.add(CustomAttributeItem.fromJson(item));
        } else if (item is Map) {
          items.add(
              CustomAttributeItem.fromJson(Map<String, dynamic>.from(item)));
        } else if (item is String && item.trim().isNotEmpty) {
          items.add(CustomAttributeItem(
            id: item.trim(),
            name: item.trim(),
            value: '',
          ));
        }
      }
      return items;
    }
    if (value is Map) {
      final items = <CustomAttributeItem>[];
      for (final entry in value.entries) {
        final key = entry.key.toString().trim();
        if (key.isEmpty) continue;
        final val = entry.value;
        if (val is num) {
          items.add(CustomAttributeItem(
            id: key,
            name: key,
            value: val.toString(),
            currentValue: val.toInt(),
          ));
        } else if (val is Map) {
          final m = Map<String, dynamic>.from(val);
          final isSingleAttr = m.containsKey('name') ||
              m.containsKey('value') ||
              m.containsKey('currentValue') ||
              m.containsKey('current_value') ||
              m.containsKey('maxValue') ||
              m.containsKey('max_value') ||
              m.containsKey('importance');
          if (isSingleAttr) {
            items.add(CustomAttributeItem.fromJson({
              'id': key,
              'name': m['name'] ?? key,
              ...m,
            }));
          } else {
            // 支持以角色名称作为分类外层 key 的结构
            for (final subEntry in m.entries) {
              final subKey = subEntry.key.toString().trim();
              if (subKey.isEmpty) continue;
              final subVal = subEntry.value;
              if (subVal is num) {
                items.add(CustomAttributeItem(
                  id: '${key}_$subKey',
                  name: subKey,
                  value: subVal.toString(),
                  currentValue: subVal.toInt(),
                  characterName: key,
                ));
              } else if (subVal is Map) {
                final sm = Map<String, dynamic>.from(subVal);
                items.add(CustomAttributeItem.fromJson({
                  'id': '${key}_$subKey',
                  'name': sm['name'] ?? subKey,
                  'characterName': key,
                  ...sm,
                }));
              } else {
                items.add(CustomAttributeItem(
                  id: '${key}_$subKey',
                  name: subKey,
                  value: subVal?.toString() ?? '',
                  characterName: key,
                ));
              }
            }
          }
        } else {
          items.add(CustomAttributeItem(
            id: key,
            name: key,
            value: val?.toString() ?? '',
          ));
        }
      }
      return items;
    }
    return const [];
  }

  /// 合并多个 JSON 段的状态（取最后一次有效值）
  static void mergeState(
    AdventureResponse existing,
    AdventureResponse incoming,
  ) {
    if (incoming.scene.isNotEmpty) {
      existing = AdventureResponse(
        scene: incoming.scene,
        hp: incoming.hp,
        maxHp: incoming.maxHp,
        energy: incoming.energy,
        maxEnergy: incoming.maxEnergy,
        gold: incoming.gold,
        inventory: incoming.inventory,
        narrative: [...existing.narrative, ...incoming.narrative],
        options:
            incoming.options.isNotEmpty ? incoming.options : existing.options,
        customStatus: incoming.customStatus.isNotEmpty
            ? incoming.customStatus
            : existing.customStatus,
      );
    }
  }

  /// 检查响应是否至少包含有效叙事
  bool get hasContent =>
      narrative.isNotEmpty || scene.isNotEmpty || options.isNotEmpty;

  @override
  List<Object?> get props => [
        scene,
        hp,
        maxHp,
        energy,
        maxEnergy,
        gold,
        inventory,
        narrative,
        options,
        customStatus,
        customStatusChanges,
      ];
}

/// P3-02: Isolate 兼容的顶层包装函数，供 compute() 调用
AdventureResponse? parseResponseInIsolate(String content) {
  return AdventureResponse.tryParseSplit(content);
}
