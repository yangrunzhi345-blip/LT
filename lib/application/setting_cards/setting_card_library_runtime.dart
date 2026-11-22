import '../../controllers/resource_crud_controller.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../domain/setting_cards/setting_card.dart';
import '../../features/resource_library/application/use_cases/resource_library_runtime.dart';
import '../../features/resource_library/domain/models/resource_library_view_state.dart';
import '../../models/resource_library_mode.dart';
import 'setting_card_service.dart';

/// Library surface that prefers lightweight cards and falls back to the
/// legacy library for rows that have not been migrated yet.
///
/// The fallback keeps old databases readable while the compatibility migration
/// converges them; a card always wins for the same logical item.
final class SettingCardLibraryRuntime implements ResourceLibraryRuntime {
  SettingCardLibraryRuntime({
    required SettingCardService service,
    required ResourceLibraryRuntime fallback,
  })  : _service = service,
        _fallback = fallback;

  final SettingCardService _service;
  final ResourceLibraryRuntime _fallback;

  SettingCardService get cardService => _service;

  @override
  Future<List<ResourceLibraryItem>> load(ResourceLibraryMode mode) async {
    final legacy = await _fallback.load(mode);
    final cards = await _service.list(mode: mode.storageValue);

    final cardIds = cards.map((card) => card.id).toSet();
    final cardLegacyIds = <String>{
      for (final card in cards)
        if (card.legacyId != null && card.legacyId!.isNotEmpty) card.legacyId!,
    };
    final items = <ResourceLibraryItem>[
      for (final card in cards) _itemOf(card),
      ...legacy.where((item) =>
          !cardIds.contains(item.id) && !cardLegacyIds.contains(item.id)),
    ];
    items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items;
  }

  @override
  Future<ResourceOperationResult> moveToTrash({
    required ResourceLibraryItem item,
    required ResourceLibraryMode mode,
  }) async {
    final card = await _service.find(item.id);
    if (card == null) {
      return _fallback.moveToTrash(item: item, mode: mode);
    }
    await _service.delete(card.id);
    return const ResourceOperationResult.success(resourceId: null);
  }

  @override
  Future<String> createManual({
    required ResourceType type,
    required String name,
    required String summary,
    required ResourceLibraryMode mode,
  }) async {
    final card = await _service.create(
      kind: _kindOf(type),
      name: name,
      summary: summary,
      mode: mode.storageValue,
    );
    return card.id;
  }

  ResourceLibraryItem _itemOf(SettingCard card) => ResourceLibraryItem(
        id: card.id,
        type: _typeOf(card.kind),
        name: card.name,
        summary: card.summary,
        updatedAt: card.updatedAt,
        status: ResourceDisplayStatus.saved,
        isStudioAvailable: false,
        isConsumable: card.content.trim().isNotEmpty,
        originWorldviewId: card.originWorldviewId,
        isSettingCard: true,
      );

  static ResourceType _typeOf(SettingCardKind kind) => switch (kind) {
        SettingCardKind.worldview => ResourceType.worldview,
        SettingCardKind.character => ResourceType.character,
        SettingCardKind.npc => ResourceType.npc,
      };

  static SettingCardKind _kindOf(ResourceType type) => switch (type) {
        ResourceType.worldview => SettingCardKind.worldview,
        ResourceType.character => SettingCardKind.character,
        ResourceType.npc => SettingCardKind.npc,
      };
}
