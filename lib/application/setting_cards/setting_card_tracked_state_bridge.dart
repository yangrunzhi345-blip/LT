import 'dart:convert';

import '../../domain/setting_cards/setting_card.dart';
import '../../domain/setting_cards/setting_card_repository.dart';
import '../../models/tracked_state_definition.dart';
import 'setting_card_markdown_parser.dart';

/// Reads and writes the `tracked_state_definitions` block of a setting card.
///
/// Cards keep their definitions in two places on purpose:
/// * `metadata.structured_payload` (characters / NPCs) and
///   `metadata.detail_json` (worldviews) so generation and the adventure
///   snapshot keep typed fields, and
/// * a `## tracked_state_definitions` JSON section in the document body so the
///   definitions survive a plain-text export and are visible to the editor.
///
/// The bridge is the single writer for both surfaces; it never touches any
/// other card field beyond the `updated_at` stamp.
final class SettingCardTrackedStateBridge {
  const SettingCardTrackedStateBridge(
      {required SettingCardRepository repository})
      : _repository = repository;

  static const String trackedStateKey = 'tracked_state_definitions';

  static const SettingCardMarkdownParser _parser = SettingCardMarkdownParser();

  final SettingCardRepository _repository;

  /// Definitions declared by [cardId]; empty when the card is missing or
  /// declares none.
  Future<List<TrackedStateDefinition>> read(String cardId) async {
    final card = await _repository.findById(cardId);
    if (card == null) return const <TrackedStateDefinition>[];
    return readFromCard(card);
  }

  /// Same as [read] for a card the caller already loaded.
  ///
  /// Listing N owners must not become N additional reads, so batched callers
  /// pass the row they already hold.
  List<TrackedStateDefinition> readFromCard(SettingCard card) {
    final raw = switch (card.kind) {
      SettingCardKind.character ||
      SettingCardKind.npc =>
        _parser.resolveStructuredPayload(card)[trackedStateKey],
      SettingCardKind.worldview => _worldviewDetail(card)[trackedStateKey] ??
          _parser.resolveStructuredPayload(card)[trackedStateKey],
    };
    return TrackedStateDefinition.parseList(
      raw,
      source: 'setting_card_bridge',
      fromResource: true,
    );
  }

  /// Replaces the card's definitions and persists it.
  ///
  /// Returns the saved card, or null when [cardId] does not exist. Other body
  /// sections and every unrelated metadata key are preserved.
  Future<SettingCard?> write(
    String cardId,
    List<TrackedStateDefinition> definitions,
  ) async {
    final card = await _repository.findById(cardId);
    if (card == null) return null;
    final jsonList = <Map<String, dynamic>>[
      for (final definition in definitions) definition.toJson(),
    ];

    final metadata = <String, Object?>{
      for (final entry in card.metadata.entries)
        entry.key: _deepCopy(entry.value),
    };
    if (card.kind == SettingCardKind.worldview) {
      _putDefinitions(
          metadata, SettingCardMarkdownParser.detailJsonKey, jsonList);
    } else {
      _putDefinitions(metadata, 'structured_payload', jsonList);
    }

    // Only a sectioned document can take a new section. Appending one to a
    // whole-document JSON card or a plain-text card would make the parser treat
    // the body as sections and silently drop the original payload/prose.
    final hasSections = RegExp(r'^##\s+', multiLine: true)
        .hasMatch(card.content.replaceAll('\r\n', '\n'));
    final updated = card.copyWith(
      content:
          hasSections ? _upsertSection(card.content, jsonList) : card.content,
      metadata: metadata,
      updatedAt: DateTime.now().toIso8601String(),
    );
    await _repository.save(updated);
    return updated;
  }

  Map<String, dynamic> _worldviewDetail(SettingCard card) {
    final raw = _asMap(card.metadata[SettingCardMarkdownParser.detailJsonKey]);
    return raw;
  }

  /// Copies the payload object, sets the definitions list and writes it back.
  /// A payload stored as a JSON string is decoded first so both shapes work.
  void _putDefinitions(
    Map<String, Object?> metadata,
    String key,
    List<Map<String, dynamic>> definitions,
  ) {
    final payload = _asMap(metadata[key]);
    payload[trackedStateKey] = definitions;
    metadata[key] = payload;
  }

  /// Upserts the `## tracked_state_definitions` section with a fenced JSON
  /// block, leaving every other section untouched.
  String _upsertSection(
    String content,
    List<Map<String, dynamic>> definitions,
  ) {
    final normalized = content.replaceAll('\r\n', '\n');
    final lines = normalized.split('\n');
    final heading = RegExp(r'^##\s+' + trackedStateKey + r'\s*$');
    final anyHeading = RegExp(r'^##\s+');
    final block = <String>[
      '## $trackedStateKey',
      '',
      '```json',
      const JsonEncoder.withIndent('  ').convert(definitions),
      '```',
    ];

    int? start;
    var inFence = false;
    for (var index = 0; index < lines.length; index++) {
      final trimmed = lines[index].trimLeft();
      if (_togglesFence(trimmed)) {
        inFence = !inFence;
        continue;
      }
      if (!inFence && heading.hasMatch(lines[index].trimRight())) {
        start = index;
        break;
      }
    }

    if (start == null) {
      final base = normalized.trimRight();
      if (base.isEmpty) return '${block.join('\n')}\n';
      return '$base\n\n${block.join('\n')}\n';
    }

    var end = lines.length;
    inFence = false;
    for (var index = start + 1; index < lines.length; index++) {
      final trimmed = lines[index].trimLeft();
      if (_togglesFence(trimmed)) {
        inFence = !inFence;
        continue;
      }
      if (!inFence && anyHeading.hasMatch(lines[index])) {
        end = index;
        break;
      }
    }

    final merged = <String>[
      ...lines.sublist(0, start),
      ...block,
      if (end < lines.length) ...['', ...lines.sublist(end)],
    ];
    return '${merged.join('\n').trimRight()}\n';
  }

  /// True only for a fence line that opens or closes a multi-line block. A
  /// one-line ```json {...} ``` block does not toggle fence state.
  static bool _togglesFence(String trimmed) {
    if (!trimmed.startsWith('```')) return false;
    return trimmed.indexOf('```', 3) < 0;
  }

  static Map<String, dynamic> _asMap(Object? value) {
    Object? decoded = value;
    if (decoded is String) {
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        return <String, dynamic>{};
      }
    }
    if (decoded is! Map) return <String, dynamic>{};
    return <String, dynamic>{
      for (final entry in decoded.entries)
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
