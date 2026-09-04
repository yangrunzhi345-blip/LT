import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../widgets/sheet_handle.dart';
import '../../../models/equipment.dart';
import '../../../models/game_state.dart';

/// 商店商品
class ShopItem {
  final String id;
  final String name;
  final String icon;
  final int price;
  final ItemType type;
  final Map<String, dynamic> data;
  final EquipmentQuality? quality;

  const ShopItem({
    required this.id,
    required this.name,
    required this.icon,
    required this.price,
    this.type = ItemType.consumable,
    this.data = const {},
    this.quality,
  });

  int get sellPrice => (price / 2).round();
}

/// 商店对话框
class ShopDialog extends StatelessWidget {
  final List<ShopItem> shopItems;
  final List<InventoryItem> playerInventory;
  final int playerGold;
  final bool isDark;
  final void Function(ShopItem item)? onBuy;
  final void Function(InventoryItem item)? onSell;

  const ShopDialog({
    super.key,
    required this.shopItems,
    required this.playerInventory,
    required this.playerGold,
    this.isDark = false,
    this.onBuy,
    this.onSell,
  });

  /// 根据节点类型和玩家等级生成商品
  static List<ShopItem> generateShopItems(String nodeType, int playerLevel) {
    final random = Random();
    final items = <ShopItem>[];

    // 基础商品（总是有）
    items.addAll([
      const ShopItem(
          id: 'potion',
          name: '回复药',
          icon: '🧪',
          price: 30,
          type: ItemType.consumable,
          data: {'heal_hp': 30}),
      const ShopItem(
          id: 'mana_potion',
          name: '魔力药水',
          icon: '💧',
          price: 45,
          type: ItemType.consumable,
          data: {'heal_mp': 20}),
      const ShopItem(
          id: 'ration',
          name: '干粮',
          icon: '🍞',
          price: 15,
          type: ItemType.consumable,
          data: {'restore_energy': 15}),
    ]);

    // 等级解锁
    if (playerLevel >= 3) {
      items.addAll([
        const ShopItem(
            id: 'elixir',
            name: '大回复药',
            icon: '🧪',
            price: 80,
            type: ItemType.consumable,
            data: {'heal_hp': 60}),
        const ShopItem(
            id: 'antidote',
            name: '解毒草',
            icon: '🥬',
            price: 25,
            type: ItemType.consumable,
            data: {'cure_poison': 1}),
      ]);
    }

    if (playerLevel >= 5) {
      items.addAll([
        const ShopItem(
            id: 'super_elixir',
            name: '超级回复药',
            icon: '💖',
            price: 150,
            type: ItemType.consumable,
            data: {'heal_hp': 100}),
      ]);
    }

    // 装备（城镇更大几率）
    if (nodeType == 'town') {
      final weaponPool = [
        const ShopItem(
            id: 'iron_sword',
            name: '铁剑',
            icon: '🗡️',
            price: 200,
            type: ItemType.equipment,
            quality: EquipmentQuality.common,
            data: {
              'slot': 'weapon',
              'quality': 'common',
              'stats': {'atk': 8}
            }),
        const ShopItem(
            id: 'steel_sword',
            name: '钢剑',
            icon: '🗡️',
            price: 500,
            type: ItemType.equipment,
            quality: EquipmentQuality.uncommon,
            data: {
              'slot': 'weapon',
              'quality': 'uncommon',
              'stats': {'atk': 14}
            }),
        const ShopItem(
            id: 'leather_armor',
            name: '皮甲',
            icon: '🛡️',
            price: 180,
            type: ItemType.equipment,
            quality: EquipmentQuality.common,
            data: {
              'slot': 'armor',
              'quality': 'common',
              'stats': {'def': 5}
            }),
      ];
      if (playerLevel >= 3) {
        weaponPool.addAll([
          const ShopItem(
              id: 'chain_mail',
              name: '锁子甲',
              icon: '🛡️',
              price: 450,
              type: ItemType.equipment,
              quality: EquipmentQuality.uncommon,
              data: {
                'slot': 'armor',
                'quality': 'uncommon',
                'stats': {'def': 9}
              }),
        ]);
      }
      // Pick 2-3 random equipment
      weaponPool.shuffle(random);
      items.addAll(weaponPool.take(2 + random.nextInt(2)));
    }

    return items;
  }

  /// 显示商店
  static void show({
    required BuildContext context,
    required int playerGold,
    required List<InventoryItem> playerInventory,
    required GameState gameState,
    String nodeType = 'town',
    bool isDark = false,
    void Function(ShopItem)? onBuy,
    void Function(InventoryItem)? onSell,
  }) {
    final items = generateShopItems(nodeType, gameState.level);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (ctx, scrollCtrl) => ShopDialog(
          shopItems: items,
          playerInventory: playerInventory,
          playerGold: playerGold,
          isDark: isDark,
          onBuy: onBuy,
          onSell: onSell,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white54 : Colors.grey;

    return ListView(
      controller: null,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        const SheetHandle(),
        const SizedBox(height: 16),
        Row(children: [
          const Icon(Icons.storefront_outlined, size: 22),
          const SizedBox(width: 8),
          Text('商店',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700, color: textColor)),
          const Spacer(),
          Text('💰 $playerGold',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.amber)),
        ]),
        const SizedBox(height: 16),

        // Buy section
        Text('— 购买 —',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: subColor)),
        const SizedBox(height: 8),
        ...shopItems.map((item) => _ShopItemTile(
              item: item,
              canAfford: playerGold >= item.price,
              isDark: isDark,
              onTap: () {
                if (playerGold >= item.price) {
                  onBuy?.call(item);
                  Navigator.of(context).pop();
                }
              },
            )),

        const SizedBox(height: 16),
        // Sell section
        if (playerInventory.isNotEmpty) ...[
          Text('— 卖出（半价回收）—',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: subColor)),
          const SizedBox(height: 8),
          ...playerInventory.map((inv) => _SellItemTile(
                item: inv,
                sellPrice: 10, // base sell price
                isDark: isDark,
                onTap: () {
                  onSell?.call(inv);
                  Navigator.of(context).pop();
                },
              )),
        ],
      ],
    );
  }
}

class _ShopItemTile extends StatelessWidget {
  final ShopItem item;
  final bool canAfford;
  final bool isDark;
  final VoidCallback onTap;

  const _ShopItemTile({
    required this.item,
    required this.canAfford,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white70 : Colors.black87;
    final qualityColor = switch (item.quality) {
      EquipmentQuality.rare => Colors.blue,
      EquipmentQuality.epic => Colors.purple,
      EquipmentQuality.legendary => Colors.amber,
      _ => null,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      color: isDark ? AppColors.darkSurfaceElevated : Colors.grey[50],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        dense: true,
        leading: Text(item.icon, style: const TextStyle(fontSize: 22)),
        title: Text(
          item.name,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: qualityColor ?? textColor,
          ),
        ),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${item.price}💰',
              style: TextStyle(
                  fontSize: 12, color: canAfford ? Colors.amber : Colors.red)),
          const SizedBox(width: 4),
          TextButton(
            onPressed: canAfford ? onTap : null,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text('购买',
                style: TextStyle(
                    fontSize: 12,
                    color: canAfford ? AppColors.accent : Colors.grey)),
          ),
        ]),
      ),
    );
  }
}

class _SellItemTile extends StatelessWidget {
  final InventoryItem item;
  final int sellPrice;
  final bool isDark;
  final VoidCallback onTap;

  const _SellItemTile({
    required this.item,
    required this.sellPrice,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white70 : Colors.black87;
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      color: isDark ? AppColors.darkSurfaceElevated : Colors.grey[50],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        dense: true,
        leading: Text(item.icon, style: const TextStyle(fontSize: 18)),
        title: Text('${item.name} x${item.quantity}',
            style: TextStyle(fontSize: 12, color: textColor)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('+$sellPrice💰',
              style: const TextStyle(fontSize: 12, color: Colors.amber)),
          const SizedBox(width: 4),
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
            ),
            child: const Text('卖出', style: TextStyle(fontSize: 12)),
          ),
        ]),
      ),
    );
  }
}
