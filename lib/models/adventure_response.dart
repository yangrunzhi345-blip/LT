import 'dart:convert';
import 'package:equatable/equatable.dart';

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

  /// Parse the split response: narrative text before ---JSON---, JSON after
  static AdventureResponse? tryParseSplit(String content) {
    final sepPattern = RegExp(r'\n?\s*---JSON---\s*\n?');
    final matches = sepPattern.allMatches(content).toList();
    if (matches.isEmpty) {
      return tryParse(content);
    }
    // A separator can occur in prose.  The final separator that yields a JSON
    // object wins; earlier text remains narrative instead of being discarded.
    for (final sepMatch in matches.reversed) {
      final json = _decodeObject(content.substring(sepMatch.end));
      if (json == null) continue;
      final narrative = content
          .substring(0, sepMatch.start)
          .trim()
          .split(RegExp(r'\n\s*\n'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && !_isSectionLabel(s))
          .toList();
      return AdventureResponse.fromJson(json, narrative: narrative);
    }
    final narrative = content.substring(0, matches.last.start).trim();
    return narrative.isEmpty
        ? null
        : AdventureResponse(
            scene: '',
            hp: 100,
            maxHp: 100,
            energy: 100,
            maxEnergy: 100,
            gold: 0,
            inventory: const [],
            narrative: [narrative],
            options: const []);
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

  /// Get streaming display text (hide JSON section)
  static String streamingDisplayText(String accumulated) {
    final sep = RegExp(r'\n?\s*---JSON---');
    final match = sep.firstMatch(accumulated);
    if (match == null) return accumulated;
    return accumulated.substring(0, match.start);
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
        options
      ];
}

/// P3-02: Isolate 兼容的顶层包装函数，供 compute() 调用
AdventureResponse? parseResponseInIsolate(String content) {
  return AdventureResponse.tryParseSplit(content);
}
