import '../managers/encounter_manager.dart';
import '../managers/inventory_manager.dart';
import '../models/equipment.dart';

/// 冒险游戏域控制器 — 收口 Widget 对 GameEngine 内部 Manager 的直接访问。
///
/// 背包/装备为只读展示 + 简单物品添加，遭遇为无状态规则委托。
/// UI 只允许经此控制器（或 ChatProvider facade）访问这些能力，不再持有 Manager 实例。
class AdventureGameController {
  final InventoryManager _inventory;

  AdventureGameController({
    required InventoryManager inventory,
  }) : _inventory = inventory;

  // ─── 背包 / 装备 ───

  Future<void> loadInventory(int adventureId) => _inventory.load(adventureId);

  List<InventoryItem> get allItems => _inventory.allItems;

  List<Equipment> get allEquipment => _inventory.allEquipment;

  List<Equipment> equipmentFor(String? characterId) =>
      _inventory.getEquipmentForCharacter(characterId);

  List<InventoryItem> itemsFor(String? characterId) =>
      _inventory.getItemsForCharacter(characterId);

  Future<void> addSimpleItem({
    required int adventureId,
    required String name,
    String icon = '📦',
    ItemType type = ItemType.consumable,
    int quantity = 1,
    Map<String, dynamic>? data,
    String? ownerCharacterId,
  }) {
    return _inventory.addSimpleItem(
      adventureId: adventureId,
      name: name,
      icon: icon,
      type: type,
      quantity: quantity,
      data: data,
      ownerCharacterId: ownerCharacterId,
    );
  }

  // ─── 遭遇 ───

  Map<String, dynamic> randomEnemy() => EncounterManager.getRandomEnemy();
}
