import 'dart:convert';

/// 装备数据模型
class Equipment {
  final String id;
  final String name;
  final String icon;
  final EquipmentSlot slot;
  final EquipmentQuality quality;
  Map<String, int> stats;
  final String? skillGranted;
  final String description;
  String? ownerCharacterId;
  final int adventureId;

  Equipment({
    required this.id,
    required this.name,
    this.icon = '',
    required this.slot,
    this.quality = EquipmentQuality.common,
    Map<String, int>? stats,
    this.skillGranted,
    this.description = '',
    this.ownerCharacterId,
    required this.adventureId,
  }) : stats = stats ?? {};

  bool get isEquipped => ownerCharacterId != null;

  int getStat(String key) => stats[key] ?? 0;

  Map<String, dynamic> toRow() => {
        'id': id,
        'name': name,
        'icon': icon,
        'slot': slot.name,
        'quality': quality.name,
        'stats_json': jsonEncode(stats),
        'skill_granted': skillGranted,
        'description': description,
        'owner_character_id': ownerCharacterId,
        'adventure_id': adventureId,
      };

  factory Equipment.fromRow(Map<String, dynamic> row) {
    Map<String, int> parseStats(String? json) {
      if (json == null || json.isEmpty) return {};
      try {
        return (jsonDecode(json) as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, (v as num).toInt()));
      } catch (_) {
        return {};
      }
    }

    return Equipment(
      id: row['id'] as String,
      name: row['name'] as String? ?? '',
      icon: row['icon'] as String? ?? '',
      slot: EquipmentSlot.values.firstWhere((e) => e.name == row['slot'],
          orElse: () => EquipmentSlot.weapon),
      quality: EquipmentQuality.values.firstWhere(
          (e) => e.name == row['quality'],
          orElse: () => EquipmentQuality.common),
      stats: parseStats(row['stats_json'] as String?),
      skillGranted: row['skill_granted'] as String?,
      description: row['description'] as String? ?? '',
      ownerCharacterId: row['owner_character_id'] as String?,
      adventureId: row['adventure_id'] as int? ?? 0,
    );
  }

  Equipment copyWith({String? ownerCharacterId, bool clearOwner = false}) =>
      Equipment(
        id: id,
        name: name,
        icon: icon,
        slot: slot,
        quality: quality,
        stats: stats,
        skillGranted: skillGranted,
        description: description,
        ownerCharacterId:
            clearOwner ? null : ownerCharacterId ?? this.ownerCharacterId,
        adventureId: adventureId,
      );
}

enum EquipmentSlot { weapon, armor, accessory1, accessory2, special }

enum EquipmentQuality { common, uncommon, rare, epic, legendary }

/// 背包物品
class InventoryItem {
  final int? id;
  final String itemId;
  final ItemType type;
  final String name;
  final String icon;
  int quantity;
  Map<String, dynamic> data;
  final int adventureId;

  /// v2.13: 物品归属角色。null 或空字符串 = 公共/共享物品。
  final String? ownerCharacterId;

  InventoryItem({
    this.id,
    required this.itemId,
    required this.type,
    required this.name,
    this.icon = '',
    this.quantity = 1,
    Map<String, dynamic>? data,
    required this.adventureId,
    this.ownerCharacterId,
  }) : data = data ?? {};

  Map<String, dynamic> toRow() => {
        if (id != null) 'id': id,
        'item_id': itemId,
        'item_type': type.name,
        'name': name,
        'icon': icon,
        'quantity': quantity,
        'data_json': jsonEncode(data),
        'adventure_id': adventureId,
        'owner_character_id': ownerCharacterId,
      };

  factory InventoryItem.fromRow(Map<String, dynamic> row) {
    Map<String, dynamic> parseData(String? json) {
      if (json == null || json.isEmpty) return {};
      try {
        return jsonDecode(json) as Map<String, dynamic>;
      } catch (_) {
        return {};
      }
    }

    return InventoryItem(
      id: row['id'] as int?,
      itemId: row['item_id'] as String? ?? '',
      type: ItemType.values.firstWhere((e) => e.name == row['item_type'],
          orElse: () => ItemType.consumable),
      name: row['name'] as String? ?? '',
      icon: row['icon'] as String? ?? '',
      quantity: row['quantity'] as int? ?? 1,
      data: parseData(row['data_json'] as String?),
      adventureId: row['adventure_id'] as int? ?? 0,
      ownerCharacterId: row['owner_character_id'] as String?,
    );
  }

  InventoryItem copyWith({int? quantity}) => InventoryItem(
        id: id,
        itemId: itemId,
        type: type,
        name: name,
        icon: icon,
        quantity: quantity ?? this.quantity,
        data: data,
        adventureId: adventureId,
        ownerCharacterId: ownerCharacterId,
      );
}

enum ItemType { consumable, equipment, material, quest }
