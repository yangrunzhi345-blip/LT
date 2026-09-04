import 'dart:convert';

enum WorldviewEditingMode { simple, detailed }

enum WorldviewFactStatus { draft, confirmed, archived }

/// Versioned, portable detailed-worldview payload.  It deliberately stores
/// named modules rather than arbitrary model output so AI edits can be scoped
/// to one module and old presets remain readable.
class WorldviewDetails {
  static const currentFormatVersion = 2;
  static const moduleKeys = <String>[
    'overview',
    'world_rules',
    'world_state',
    'locations',
    'factions',
    'customs_and_life',
    'timeline',
    'glossary',
    'creative_constraints',
  ];

  final int formatVersion;
  final WorldviewEditingMode mode;
  final Map<String, dynamic> modules;

  const WorldviewDetails({
    this.formatVersion = currentFormatVersion,
    this.mode = WorldviewEditingMode.simple,
    this.modules = const {},
  });

  factory WorldviewDetails.simple(String description) => WorldviewDetails(
        modules: {
          'overview': {
            'summary': description.trim(),
            'status': WorldviewFactStatus.confirmed.name,
          },
        },
      );

  factory WorldviewDetails.fromJson(Map<String, dynamic>? json,
      {String fallbackDescription = ''}) {
    if (json == null || json.isEmpty) {
      return WorldviewDetails.simple(fallbackDescription);
    }
    final mode = json['mode'] == WorldviewEditingMode.detailed.name
        ? WorldviewEditingMode.detailed
        : WorldviewEditingMode.simple;
    final rawModules = json['modules'];
    final modules = <String, dynamic>{};
    if (rawModules is Map) {
      for (final key in moduleKeys) {
        final value = rawModules[key];
        if (value != null) {
          modules[key] = _sanitize(value);
        }
      }
    }
    modules.putIfAbsent(
        'overview',
        () => {
              'summary': fallbackDescription.trim(),
              'status': WorldviewFactStatus.confirmed.name,
            });
    return WorldviewDetails(
      formatVersion: (json['format_version'] as num?)?.toInt() ?? 1,
      mode: mode,
      modules: modules,
    );
  }

  static dynamic _sanitize(dynamic value) {
    // The generation coordinator enforces the 50,000-character worldview
    // budget. Do not silently truncate individual modules or list items here:
    // truncation would make a confirmed split impossible to resume faithfully.
    if (value is String) return value;
    if (value is List) return value.map(_sanitize).toList();
    if (value is Map) {
      final result = <String, dynamic>{};
      for (final entry in value.entries) {
        final key = entry.key.toString();
        result[key] = _sanitize(entry.value);
      }
      return result;
    }
    if (value is num || value is bool || value == null) return value;
    return value.toString();
  }

  Map<String, dynamic> toJson() => {
        'format_version': currentFormatVersion,
        'mode': mode.name,
        'modules': modules,
      };

  String encode() => jsonEncode(toJson());

  String get dialogueSummary {
    final overview = modules['overview'];
    if (overview is Map) {
      final summary = overview['summary']?.toString().trim() ?? '';
      if (summary.isNotEmpty) return summary;
    }
    return '';
  }

  /// Only confirmed facts become formal scene context. Drafts can be edited by
  /// the user but must not silently become canon.
  Map<String, dynamic> confirmedModules() {
    final result = <String, dynamic>{};
    for (final entry in modules.entries) {
      final value = _confirmedOnly(entry.value);
      if (value != null) {
        result[entry.key] = value;
      }
    }
    return result;
  }

  static dynamic _confirmedOnly(dynamic value) {
    if (value is Map) {
      final status = value['status']?.toString();
      if (status == WorldviewFactStatus.draft.name ||
          status == WorldviewFactStatus.archived.name) {
        return null;
      }
      final result = <String, dynamic>{};
      for (final entry in value.entries) {
        final child = _confirmedOnly(entry.value);
        if (child != null) result[entry.key.toString()] = child;
      }
      return result.isEmpty ? null : result;
    }
    if (value is List) {
      final result =
          value.map(_confirmedOnly).where((item) => item != null).toList();
      return result.isEmpty ? null : result;
    }
    return value;
  }

  WorldviewDetails copyWith({
    WorldviewEditingMode? mode,
    Map<String, dynamic>? modules,
  }) =>
      WorldviewDetails(
        formatVersion: currentFormatVersion,
        mode: mode ?? this.mode,
        modules: modules ?? this.modules,
      );

  /// Adds a user-visible library draft without making it scene canon.
  WorldviewDetails withDraft(String moduleKey, String summary) {
    if (!moduleKeys.contains(moduleKey) || summary.trim().isEmpty) return this;
    final next = Map<String, dynamic>.from(modules);
    next[moduleKey] = {
      'summary': summary.trim(),
      'status': WorldviewFactStatus.draft.name,
    };
    return copyWith(modules: next);
  }
}
