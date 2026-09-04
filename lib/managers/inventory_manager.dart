import 'package:flutter/foundation.dart';
import '../models/equipment.dart';
import '../models/game_state.dart';

/// 物品使用结果
class ItemUseResult {
  final bool success;
  final String message;
  final Map<String, int>? effects;

  const ItemUseResult({required this.success, this.message = '', this.effects});
}

/// 装备结果
class EquipResult {
  final bool success;
  final String message;
  final Equipment? unequipped; // 被替换的旧装备

  const EquipResult(
      {required this.success, this.message = '', this.unequipped});
}

/// 背包/装备管理器
class InventoryManager {
  /// 获取装备列表
  final Future<List<Equipment>> Function(int adventureId) getEquipment;

  /// 保存装备
  final Future<void> Function(Equipment eq) saveEquipment;

  /// 获取背包物品
  final Future<List<InventoryItem>> Function(int adventureId) getInventoryItems;

  /// 保存背包物品
  final Future<int> Function(InventoryItem item) saveInventoryItem;

  /// 更新背包物品
  final Future<void> Function(int id, Map<String, dynamic> updates)
      updateInventoryItem;

  /// 删除背包物品
  final Future<void> Function(int id) deleteInventoryItem;

  /// 获取游戏状态
  final GameState Function() getGameState;

  /// 设置游戏状态
  final void Function(GameState) setGameState;

  /// 按角色过滤背包物品
  final Future<List<InventoryItem>> Function(
      int adventureId, String? characterId) getInventoryItemsByCharacter;

  /// 通知 UI
  final VoidCallback? notifyUI;

  /// 缓存
  List<Equipment> _equipment = [];
  List<InventoryItem> _inventory = [];

  InventoryManager({
    required this.getEquipment,
    required this.saveEquipment,
    required this.getInventoryItems,
    required this.getInventoryItemsByCharacter,
    required this.saveInventoryItem,
    required this.updateInventoryItem,
    required this.deleteInventoryItem,
    required this.getGameState,
    required this.setGameState,
    this.notifyUI,
  });

  VoidCallback get _notify => notifyUI ?? () {};

  // ─── v2.13: 角色感知方法 ───

  /// 获取指定角色的背包物品。null = 公共物品。
  List<InventoryItem> getItemsForCharacter(String? characterId) {
    if (characterId == null || characterId.isEmpty) {
      return _inventory
          .where((item) =>
              item.ownerCharacterId == null || item.ownerCharacterId!.isEmpty)
          .toList();
    }
    return _inventory
        .where((item) =>
            item.ownerCharacterId == characterId ||
            item.ownerCharacterId == null ||
            item.ownerCharacterId!.isEmpty)
        .toList();
  }

  /// 获取指定角色的已装备物品。null = 全部已装备。
  List<Equipment> getEquipmentForCharacter(String? characterId) {
    if (characterId == null || characterId.isEmpty) {
      return _equipment.where((e) => e.isEquipped).toList();
    }
    return _equipment
        .where((e) => e.isEquipped && e.ownerCharacterId == characterId)
        .toList();
  }

  /// 加载数据
  Future<void> load(int adventureId) async {
    _equipment = List<Equipment>.from(await getEquipment(adventureId));
    _inventory = List<InventoryItem>.from(await getInventoryItems(adventureId));
  }

  /// 获取所有装备
  List<Equipment> get allEquipment => _equipment;

  /// 获取已装备物品
  List<Equipment> get equippedItems =>
      _equipment.where((e) => e.isEquipped).toList();

  /// 获取指定槽位的装备
  Equipment? getEquippedInSlot(EquipmentSlot slot) {
    try {
      return _equipment.firstWhere(
        (e) => e.isEquipped && e.slot == slot,
      );
    } catch (_) {
      return null;
    }
  }

  /// 获取所有背包物品
  List<InventoryItem> get allItems => _inventory;

  /// 按分类筛选
  List<InventoryItem> getByCategory(ItemType type) {
    return _inventory.where((item) => item.type == type).toList();
  }

  /// 使用消耗品
  Future<ItemUseResult> useItem(String itemId,
      {String charId = 'player'}) async {
    final item = _inventory.cast<InventoryItem?>().firstWhere(
          (i) => i!.itemId == itemId,
          orElse: () => null,
        );
    if (item == null) {
      return const ItemUseResult(success: false, message: '物品不存在');
    }

    if (item.quantity <= 0) {
      return const ItemUseResult(success: false, message: '物品数量不足');
    }

    final gameState = getGameState();
    final effects = <String, int>{};

    // 根据物品数据应用效果
    final data = item.data;
    if (data.containsKey('heal_hp')) {
      final healAmount = data['heal_hp'] as int;
      final newHp = (gameState.hp + healAmount).clamp(0, gameState.maxHp);
      setGameState(gameState.copyWith(hp: newHp));
      effects['hp'] = newHp - gameState.hp;
    }
    if (data.containsKey('heal_mp')) {
      final healAmount = data['heal_mp'] as int;
      final newMp = (gameState.mp + healAmount).clamp(0, gameState.maxMp);
      setGameState(gameState.copyWith(mp: newMp));
      effects['mp'] = newMp - gameState.mp;
    }
    if (data.containsKey('restore_energy')) {
      final restoreAmount = data['restore_energy'] as int;
      final newEnergy =
          (gameState.energy + restoreAmount).clamp(0, gameState.maxEnergy);
      setGameState(gameState.copyWith(energy: newEnergy));
      effects['energy'] = newEnergy - gameState.energy;
    }

    // 减少数量
    item.quantity--;
    if (item.quantity <= 0 && item.id != null) {
      await deleteInventoryItem(item.id!);
      _inventory.removeWhere((i) => i.itemId == itemId);
    } else if (item.id != null) {
      await updateInventoryItem(item.id!, {'quantity': item.quantity});
    }

    _notify();
    return ItemUseResult(
      success: true,
      message: '使用 ${item.name}',
      effects: effects,
    );
  }

  /// 装备物品
  Future<EquipResult> equipItem(String itemId,
      {String charId = 'player'}) async {
    final item = _inventory.cast<InventoryItem?>().firstWhere(
          (i) => i!.itemId == itemId && i.type == ItemType.equipment,
          orElse: () => null,
        );
    if (item == null) {
      return const EquipResult(success: false, message: '不是可装备的物品');
    }

    // 从物品数据创建装备
    final slot = EquipmentSlot.values.firstWhere(
      (e) => e.name == (item.data['slot'] as String? ?? 'weapon'),
      orElse: () => EquipmentSlot.weapon,
    );

    final eq = Equipment(
      id: item.itemId,
      name: item.name,
      icon: item.icon,
      slot: slot,
      quality: EquipmentQuality.values.firstWhere(
        (e) => e.name == (item.data['quality'] as String? ?? 'common'),
        orElse: () => EquipmentQuality.common,
      ),
      stats: (item.data['stats'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v as num).toInt())) ??
          {},
      description: item.data['description'] as String? ?? '',
      ownerCharacterId: charId,
      adventureId: item.adventureId,
    );

    // 检查同槽位冲突
    final old = getEquippedInSlot(slot);
    if (old != null) {
      // 卸下旧装备
      final oldUpdated = Equipment(
        id: old.id,
        name: old.name,
        icon: old.icon,
        slot: old.slot,
        quality: old.quality,
        stats: old.stats,
        description: old.description,
        ownerCharacterId: null,
        adventureId: old.adventureId,
      );
      await saveEquipment(oldUpdated);
    }

    // 保存新装备
    await saveEquipment(eq);
    _equipment
        .removeWhere((e) => e.id == itemId || (old != null && e.id == old.id));
    _equipment.add(eq);

    // 从背包移除
    item.quantity--;
    if (item.quantity <= 0 && item.id != null) {
      await deleteInventoryItem(item.id!);
      _inventory.removeWhere((i) => i.itemId == itemId);
    }

    // 应用属性加成
    _applyEquipmentStats();

    _notify();
    return EquipResult(
      success: true,
      message: '装备 ${eq.name}',
      unequipped: old,
    );
  }

  /// 卸下装备
  Future<EquipResult> unequipItem(String equipmentId) async {
    final eq = _equipment.cast<Equipment?>().firstWhere(
          (e) => e!.id == equipmentId && e.isEquipped,
          orElse: () => null,
        );
    if (eq == null) {
      return const EquipResult(success: false, message: '未装备此物品');
    }

    final unequipped = Equipment(
      id: eq.id,
      name: eq.name,
      icon: eq.icon,
      slot: eq.slot,
      quality: eq.quality,
      stats: eq.stats,
      description: eq.description,
      ownerCharacterId: null,
      adventureId: eq.adventureId,
    );
    await saveEquipment(unequipped);
    _equipment.removeWhere((e) => e.id == equipmentId);
    _equipment.add(unequipped);

    // 移除属性加成
    _applyEquipmentStats();

    _notify();
    return EquipResult(success: true, message: '卸下 ${eq.name}');
  }

  /// 应用所有装备属性到 GameState
  void _applyEquipmentStats() {
    final gameState = getGameState();
    int atkBonus = 0;
    int defBonus = 0;
    int spdBonus = 0;

    for (final eq in _equipment.where((e) => e.isEquipped)) {
      atkBonus += eq.stats['atk'] ?? 0;
      defBonus += eq.stats['def'] ?? 0;
      spdBonus += eq.stats['speed'] ?? 0;
    }

    setGameState(gameState.copyWith(
      baseAtk: 5 + atkBonus, // 5 is base
      baseDef: 3 + defBonus, // 3 is base
      baseSpeed: 5 + spdBonus, // 5 is base
    ));
  }

  /// 添加物品到背包
  Future<void> addItem(InventoryItem item) async {
    final id = await saveInventoryItem(item);
    // Reload to get correct state
    final existing = _inventory.cast<InventoryItem?>().firstWhere(
          (i) => i!.itemId == item.itemId,
          orElse: () => null,
        );
    if (existing != null && existing.id != null) {
      existing.quantity += item.quantity;
    } else {
      _inventory.add(InventoryItem(
        id: id,
        itemId: item.itemId,
        type: item.type,
        name: item.name,
        icon: item.icon,
        quantity: item.quantity,
        data: item.data,
        adventureId: item.adventureId,
        ownerCharacterId: item.ownerCharacterId,
      ));
    }
    _notify();
  }

  /// 创建并添加一个简单物品
  /// [ownerCharacterId] v2.13: 物品归属角色。null=公共。
  Future<void> addSimpleItem({
    required int adventureId,
    required String name,
    String icon = '📦',
    ItemType type = ItemType.consumable,
    int quantity = 1,
    Map<String, dynamic>? data,
    String? ownerCharacterId,
  }) async {
    final item = InventoryItem(
      itemId: 'item_${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      name: name,
      icon: icon,
      quantity: quantity,
      data: data ?? {},
      adventureId: adventureId,
      ownerCharacterId: ownerCharacterId,
    );
    await addItem(item);
  }
}
