import '../../domain/resources/resource_contracts.dart';
import '../../domain/setting_cards/setting_card.dart';
import '../../features/resource_library/application/use_cases/resource_library_runtime.dart';
import '../../features/resource_library/domain/models/resource_library_view_state.dart';
import '../../models/resource_library_mode.dart';
import 'setting_card_service.dart';

/// Card-only library surface.
///
/// Phase 5c retired the legacy/tree fallback: every item the library shows is a
/// lightweight setting card, so nothing here reads the resource tree.
final class SettingCardLibraryRuntime implements ResourceLibraryRuntime {
  SettingCardLibraryRuntime({required SettingCardService service})
      : _service = service;

  final SettingCardService _service;

  SettingCardService get cardService => _service;

  @override
  Future<List<ResourceLibraryItem>> load(ResourceLibraryMode mode) async {
    final cards = await _service.list(mode: mode.storageValue);
    final items = <ResourceLibraryItem>[
      for (final card in cards) _itemOf(card),
    ];
    items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items;
  }

  ResourceLibraryItem _itemOf(SettingCard card) => ResourceLibraryItem(
        id: card.id,
        type: _typeOf(card.kind),
        name: card.name,
        summary: card.summary,
        updatedAt: card.updatedAt,
        status: ResourceDisplayStatus.saved,
        isConsumable: card.content.trim().isNotEmpty,
        originWorldviewId: card.originWorldviewId,
      );

  static ResourceType _typeOf(SettingCardKind kind) => switch (kind) {
        SettingCardKind.worldview => ResourceType.worldview,
        SettingCardKind.character => ResourceType.character,
        SettingCardKind.npc => ResourceType.npc,
      };
}
