import 'package:equatable/equatable.dart';

import 'custom_attribute_item.dart';
import 'typed_runtime_state.dart';

/// A user- or AI-authored **monitoring definition**: what an entity wants the
/// narrative to keep track of.
///
/// A definition is deliberately *not* a runtime value. A character card may
/// declare「诅咒侵蚀 0..100」; the number 37 belongs to one adventure's runtime
/// overlay, never to the resource. The forbidden keys below are the structural
/// guarantee for that rule: [TrackedStateDefinition] has no `currentValue`/`value`
/// field at all, and [fromResourceJson] refuses to project them.
///
/// Field types are reused from existing registries on purpose:
/// * [RuntimeStateValueKind] is the same kind enum `typed_runtime_state.dart`
///   already validates runtime proposals with.
/// * [CustomAttributeImportance] carries the existing localized labels, colors
///   and icons, so the new system does not fork a parallel importance model.
final class TrackedStateDefinition with Equatable {
  /// Keys that describe a *runtime current value*, not a definition. They are
  /// rejected by [fromResourceJson] and never serialized by [toJson].
  static const Set<String> bannedCurrentStateKeys = {
    'currentValue',
    'current_value',
    'value',
    'currentState',
    'current_state',
  };

  /// Serialized field set. Kept small and forward-compatible; unknown keys are
  /// ignored on read so an older binary never fails on a newer resource.
  static const int maximumDefinitionsPerEntity = 12;

  final String id;
  final String name;
  final RuntimeStateValueKind valueKind;
  final String description;
  final CustomAttributeImportance importance;
  final num? minimum;
  final num? maximum;
  final Set<String> enumValues;
  final String? icon;

  const TrackedStateDefinition({
    required this.id,
    required this.name,
    this.valueKind = RuntimeStateValueKind.integer,
    this.description = '',
    this.importance = CustomAttributeImportance.reference,
    this.minimum,
    this.maximum,
    this.enumValues = const {},
    this.icon,
  });

  bool get isNumeric =>
      valueKind == RuntimeStateValueKind.integer ||
      valueKind == RuntimeStateValueKind.number;

  /// Stable, locale-neutral identifier. Falls back to a deterministic slug of
  /// the display name so a definition authored in Chinese still gets a stable
  /// ASCII id instead of an empty one.
  String get effectiveId {
    final clean = id.trim();
    return clean.isNotEmpty ? clean : slugify(name);
  }

  @override
  List<Object?> get props => [
        id,
        name,
        valueKind,
        description,
        importance,
        minimum,
        maximum,
        enumValues,
        icon,
      ];

  TrackedStateDefinition copyWith({
    String? id,
    String? name,
    RuntimeStateValueKind? valueKind,
    String? description,
    CustomAttributeImportance? importance,
    num? minimum,
    num? maximum,
    Set<String>? enumValues,
    String? icon,
  }) =>
      TrackedStateDefinition(
        id: id ?? this.id,
        name: name ?? this.name,
        valueKind: valueKind ?? this.valueKind,
        description: description ?? this.description,
        importance: importance ?? this.importance,
        minimum: minimum ?? this.minimum,
        maximum: maximum ?? this.maximum,
        enumValues: enumValues ?? this.enumValues,
        icon: icon ?? this.icon,
      );

  Map<String, dynamic> toJson() => {
        'id': effectiveId,
        'name': name.trim(),
        'value_kind': valueKind.name,
        'description': description.trim(),
        'importance': importance.name,
        if (minimum != null) 'minimum': minimum,
        if (maximum != null) 'maximum': maximum,
        if (enumValues.isNotEmpty) 'enum_values': enumValues.toList(),
        if (icon != null && icon!.trim().isNotEmpty) 'icon': icon!.trim(),
      };

  factory TrackedStateDefinition.fromJson(Map<String, dynamic> json) {
    final rawKind = json['value_kind'] ?? json['valueKind'];
    final valueKind = RuntimeStateValueKind.values
            .where((candidate) => candidate.name == rawKind?.toString())
            .firstOrNull ??
        RuntimeStateValueKind.integer;
    final rawEnum = json['enum_values'] ?? json['enumValues'];
    final enumValues = <String>{};
    if (rawEnum is Iterable) {
      for (final item in rawEnum) {
        final text = item?.toString().trim() ?? '';
        if (text.isNotEmpty) enumValues.add(text);
      }
    }
    return TrackedStateDefinition(
      id: (json['id'] ?? json['definition_id'] ?? '').toString().trim(),
      name: (json['name'] ?? json['label'] ?? '').toString().trim(),
      valueKind: valueKind,
      description:
          (json['description'] ?? json['rule'] ?? '').toString().trim(),
      importance: CustomAttributeImportance.fromString(
        (json['importance'] ?? json['weight']).toString(),
      ),
      minimum: _asNum(json['minimum'] ?? json['min']),
      maximum: _asNum(json['maximum'] ?? json['max']),
      enumValues: enumValues,
      icon: (json['icon'])?.toString(),
    );
  }

  /// Parses one definition from **resource** payload, explicitly refusing the
  /// banned current-state keys.
  ///
  /// A resource (character card / NPC / worldview) that carries
  /// `current_value` would be silently promoting runtime state into the frozen
  /// baseline, which the whole system is built to prevent. Returning `null`
  /// here (and recording a diagnostic) is the fail-closed response.
  static TrackedStateDefinition? fromResourceJson(
    Map<String, dynamic> json, {
    List<String>? diagnostics,
    String source = 'resource',
  }) {
    for (final key in bannedCurrentStateKeys) {
      if (json.containsKey(key)) {
        diagnostics?.add('tracked_state_definition:banned_key:$key:$source');
        return null;
      }
    }
    final definition = TrackedStateDefinition.fromJson(json);
    if (definition.name.trim().isEmpty &&
        definition.description.trim().isEmpty) {
      diagnostics?.add('tracked_state_definition:empty:$source');
      return null;
    }
    return definition;
  }

  /// Parses a persisted/streamed list of definitions.
  ///
  /// Tolerant of aliases used by generated payloads, strict about the banned
  /// current-state keys, and capped by [maximumDefinitionsPerEntity].
  static List<TrackedStateDefinition> parseList(
    Object? raw, {
    List<String>? diagnostics,
    String source = 'resource',
    bool fromResource = false,
  }) {
    if (raw == null) return const [];
    if (raw is! List) {
      diagnostics?.add('tracked_state_definitions:type:$source');
      return const [];
    }
    final result = <TrackedStateDefinition>[];
    final seen = <String>{};
    for (final item in raw) {
      if (item is! Map) {
        diagnostics?.add('tracked_state_definitions:item:$source');
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      final definition = fromResource
          ? fromResourceJson(map, diagnostics: diagnostics, source: source)
          : TrackedStateDefinition.fromJson(map);
      if (definition == null) continue;
      final problems = definition.validate();
      if (problems.isNotEmpty) {
        diagnostics
            ?.add('tracked_state_definition:invalid:$source:${problems.first}');
        continue;
      }
      if (!seen.add(definition.effectiveId)) {
        diagnostics?.add(
            'tracked_state_definition:duplicate:$source:${definition.effectiveId}');
        continue;
      }
      result.add(definition);
      if (result.length >= maximumDefinitionsPerEntity) break;
    }
    if (raw.length > maximumDefinitionsPerEntity) {
      diagnostics?.add('tracked_state_definitions:limit:$source');
    }
    return List.unmodifiable(result);
  }

  /// Structural problems that make a definition unusable. Empty when valid.
  List<String> validate() {
    final problems = <String>[];
    final id = effectiveId;
    if (id.isEmpty) {
      problems.add('id');
    } else if (!_idPattern.hasMatch(id)) {
      problems.add('id_charset');
    }
    if (name.trim().isEmpty) problems.add('name');
    if (isNumeric) {
      if (minimum != null && maximum != null && minimum! > maximum!) {
        problems.add('range');
      }
    } else if (valueKind == RuntimeStateValueKind.enumValue) {
      if (enumValues.isEmpty) problems.add('enum_empty');
    }
    return problems;
  }

  /// Whether [value] is legal for this definition's kind and bounds.
  bool accepts(Object? value) {
    if (value == null) return true;
    final valid = switch (valueKind) {
      RuntimeStateValueKind.integer => value is int,
      RuntimeStateValueKind.number => value is num && value.isFinite,
      RuntimeStateValueKind.boolean => value is bool,
      RuntimeStateValueKind.text => value is String && value.length <= 1000,
      RuntimeStateValueKind.enumValue =>
        value is String && enumValues.contains(value),
    };
    if (!valid) return false;
    if (value is num) {
      if (minimum != null && value < minimum!) return false;
      if (maximum != null && value > maximum!) return false;
    }
    return true;
  }

  /// Clamps a numeric value into the declared bounds. Returns [value] unchanged
  /// for non-numeric kinds.
  num clampNumeric(num value) {
    var result = value;
    if (minimum != null && result < minimum!) result = minimum!;
    if (maximum != null && result > maximum!) result = maximum!;
    return result;
  }

  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_.:-]+$');

  /// Deterministic, locale-neutral slug. Latin names become `snake_case`; names
  /// with no ASCII letters (e.g. pure CJK) fall back to a short stable hash so
  /// two different names never collide on an empty id.
  static String slugify(String name) {
    final buffer = StringBuffer();
    var lastUnderscore = false;
    for (final rune in name.trim().toLowerCase().runes) {
      final char = String.fromCharCode(rune);
      if (RegExp(r'[a-z0-9]').hasMatch(char)) {
        buffer.write(char);
        lastUnderscore = false;
      } else if (!lastUnderscore && buffer.isNotEmpty) {
        buffer.write('_');
        lastUnderscore = true;
      }
    }
    var slug = buffer.toString().replaceAll(RegExp(r'_+$'), '');
    if (slug.length > 48) slug = slug.substring(0, 48);
    if (slug.isEmpty) {
      slug = 'monitor_${_stableHash(name.trim())}';
    }
    return slug;
  }

  /// FNV-1a 32-bit hash rendered in base36 — deterministic across runs and
  /// platforms, unlike `String.hashCode` which is not stable across isolates.
  static String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(36);
  }

  static num? _asNum(Object? value) {
    if (value is num) return value;
    if (value == null) return null;
    return num.tryParse(value.toString().trim());
  }
}
