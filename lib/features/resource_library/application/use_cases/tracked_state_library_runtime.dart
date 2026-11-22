import 'dart:convert';

import '../../../../application/resource_library/edit_drafts.dart';
import '../../../../application/setting_cards/setting_card_markdown_parser.dart';
import '../../../../application/setting_cards/setting_card_tracked_state_bridge.dart';
import '../../../../domain/resources/resource_contracts.dart';
import '../../../../domain/setting_cards/setting_card.dart';
import '../../../../domain/setting_cards/setting_card_repository.dart';
import '../../../../models/resource_library_mode.dart';
import '../../../../models/tracked_state_definition.dart';
import '../../../../services/repositories/library_repository.dart';
import '../../domain/models/tracked_state_library_view_state.dart';

/// Read-only projection source for the Resource Library「检测项目」surface.
///
/// It flattens the monitoring **definitions** already stored on character, NPC
/// and worldview resources, plus the same definitions when they live on a
/// lightweight setting card. It never creates a definition, never persists
/// anything and never reads adventure runtime state.
abstract interface class TrackedStateLibraryRuntime {
  /// Owner resources (character / NPC / worldview) that declare definitions.
  Future<List<TrackedStateLibraryEntry>> load(ResourceLibraryMode mode);

  /// The raw stored row of one owner resource, for the focused definition
  /// editor. It returns the row the projection itself reads, so editing never
  /// needs a second storage path. Null when the resource cannot be found.
  ///
  /// A setting-card owner yields a synthetic row carrying `setting_card_id`, so
  /// the editor knows to persist through the card bridge instead of the legacy
  /// draft path.
  Future<Map<String, dynamic>?> loadOwnerRow({
    required ResourceType type,
    required String resourceId,
    required ResourceLibraryMode mode,
  });
}

/// Production projection backed by the legacy library repository plus the
/// lightweight card store.
///
/// Legacy rows are read in three batched queries (the same lists the library
/// itself loads) and decoded through the shared draft parsers. Card owners are
/// read once through [SettingCardRepository] and decoded through
/// [SettingCardTrackedStateBridge]. Legacy rows win when both surfaces carry
/// the same id, because a migrated card keeps the id of the row it replaced and
/// must not appear twice.
final class ProductionTrackedStateLibraryRuntime
    implements TrackedStateLibraryRuntime {
  ProductionTrackedStateLibraryRuntime({
    required ILibraryRepository repository,
    required SettingCardRepository cards,
  })  : _repository = repository,
        _cards = cards,
        _bridge = SettingCardTrackedStateBridge(repository: cards);

  static const SettingCardMarkdownParser _parser = SettingCardMarkdownParser();

  final ILibraryRepository _repository;
  final SettingCardRepository _cards;
  final SettingCardTrackedStateBridge _bridge;

  @override
  Future<List<TrackedStateLibraryEntry>> load(ResourceLibraryMode mode) async {
    final rows = await _loadRows(mode);

    final entries = <TrackedStateLibraryEntry>[];
    final seen = <String>{};
    for (final group in rows) {
      for (final row in group.$2) {
        final id = row['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final definitions = _definitions(group.$1, row);
        if (definitions.isEmpty) continue;
        if (!seen.add(id)) continue;
        entries.add(TrackedStateLibraryEntry(
          resourceId: id,
          ownerType: group.$1,
          ownerName: row['name']?.toString().trim() ?? '',
          updatedAt: row['updated_at']?.toString() ?? '',
          definitions: List<TrackedStateDefinition>.unmodifiable(definitions),
        ));
      }
    }

    for (final card in await _cards.list()) {
      if (!_modeMatches(card.mode, mode)) continue;
      final definitions = _bridge.readFromCard(card);
      if (definitions.isEmpty) continue;
      // A migrated card keeps the legacy row id in legacyId, not in id.
      // Check both so the row is not listed twice with two editors.
      final legacyId = card.legacyId;
      if (legacyId != null && seen.contains(legacyId)) continue;
      if (!seen.add(card.id)) continue;
      entries.add(TrackedStateLibraryEntry(
        resourceId: card.id,
        ownerType: _ownerTypeOf(card.kind),
        ownerName: card.name.trim(),
        updatedAt: card.updatedAt,
        definitions: List<TrackedStateDefinition>.unmodifiable(definitions),
      ));
    }
    return entries;
  }

  @override
  Future<Map<String, dynamic>?> loadOwnerRow({
    required ResourceType type,
    required String resourceId,
    required ResourceLibraryMode mode,
  }) async {
    final rows = await _loadRows(mode);
    for (final group in rows) {
      if (group.$1 != type) continue;
      for (final row in group.$2) {
        if (row['id']?.toString() == resourceId) {
          return Map<String, dynamic>.from(row);
        }
      }
    }

    final card = await _cards.findById(resourceId);
    if (card == null) return null;
    if (_ownerTypeOf(card.kind) != type) return null;
    if (!_modeMatches(card.mode, mode)) return null;
    return _cardOwnerRow(card);
  }

  /// Synthetic row for a card owner. `json_data` mirrors the payload the draft
  /// parsers read, so a caller that inspects the row sees the same definitions
  /// the card declares; `setting_card_id` tells the editor to write back
  /// through the bridge.
  Map<String, dynamic> _cardOwnerRow(SettingCard card) {
    final definitions = _bridge.readFromCard(card);
    final payload = <String, dynamic>{
      ..._parser.resolveStructuredPayload(card),
      'tracked_state_definitions':
          definitions.map((definition) => definition.toJson()).toList(),
    };
    payload.putIfAbsent('custom_attributes', () => const <dynamic>[]);
    return <String, dynamic>{
      'id': card.id,
      'name': card.name,
      'setting_card_id': card.id,
      'mode': card.mode,
      'json_data': jsonEncode(payload),
      'updated_at': card.updatedAt,
    };
  }

  static bool _modeMatches(String cardMode, ResourceLibraryMode mode) =>
      cardMode.isEmpty || cardMode == mode.storageValue;

  static ResourceType _ownerTypeOf(SettingCardKind kind) => switch (kind) {
        SettingCardKind.worldview => ResourceType.worldview,
        SettingCardKind.character => ResourceType.character,
        SettingCardKind.npc => ResourceType.npc,
      };

  /// One batched read per resource type, so listing N owners never becomes N
  /// queries.
  Future<List<(ResourceType, List<Map<String, dynamic>>)>> _loadRows(
    ResourceLibraryMode mode,
  ) async {
    final results = await Future.wait(<Future<List<Map<String, dynamic>>>>[
      _repository.getCharacterCards(mode: mode),
      _repository.getNpcCards(mode: mode),
      _repository.getWorldviewPresets(mode: mode),
    ]);
    return [
      (ResourceType.character, results[0]),
      (ResourceType.npc, results[1]),
      (ResourceType.worldview, results[2]),
    ];
  }

  List<TrackedStateDefinition> _definitions(
    ResourceType type,
    Map<String, dynamic> row,
  ) {
    final map = Map<String, dynamic>.from(row);
    return switch (type) {
      ResourceType.character =>
        CharacterCardEditDraft.fromExisting(map).trackedStateDefinitions,
      ResourceType.npc =>
        NpcEditDraft.fromExisting(map).trackedStateDefinitions,
      ResourceType.worldview =>
        WorldviewEditDraft.fromExisting(map).trackedStateDefinitions,
    };
  }
}
