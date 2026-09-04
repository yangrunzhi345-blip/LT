import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/equipment.dart';
import '../../../providers/riverpod_providers.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  final int? adventureId;
  final List<String> legacyInventory;

  const InventoryScreen({
    super.key,
    required this.adventureId,
    this.legacyInventory = const [],
  });

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  late Future<void> _future;
  ItemType? _selectedType;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<void> _load() async {
    final adventureId = widget.adventureId;
    if (adventureId != null) {
      await ref
          .read(adventureGameControllerProvider)
          .loadInventory(adventureId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(adventureGameControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBackground : Colors.grey[50];
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(title: const Text('背包')),
      body: FutureBuilder<void>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      size: 42, color: AppColors.error),
                  const SizedBox(height: 12),
                  Text('背包加载失败：${snapshot.error}',
                      style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _future = _load()),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('重试'),
                  ),
                ],
              ),
            );
          }

          final allItems = controller.allItems;
          final filteredItems = _selectedType == null
              ? allItems
              : allItems
                  .where((item) => item.type == _selectedType)
                  .toList(growable: false);
          final equipment = controller.allEquipment;

          if (allItems.isEmpty &&
              equipment.isEmpty &&
              widget.legacyInventory.isEmpty) {
            return _EmptyInventory(isDark: isDark);
          }

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _future = _load();
              });
              await _future;
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _InventorySummary(
                  itemCount: allItems.length,
                  equipmentCount: equipment.length,
                  isDark: isDark,
                ),
                const SizedBox(height: 16),
                _TypeFilterBar(
                  selected: _selectedType,
                  isDark: isDark,
                  onSelected: (type) => setState(() => _selectedType = type),
                ),
                const SizedBox(height: 16),
                if (filteredItems.isNotEmpty) ...[
                  _SectionTitle(
                    icon: Icons.inventory_2_rounded,
                    title: '物品',
                    isDark: isDark,
                  ),
                  const SizedBox(height: 10),
                  ...filteredItems.map(
                    (item) => _ItemCard(item: item, isDark: isDark),
                  ),
                  const SizedBox(height: 16),
                ],
                if (equipment.isNotEmpty) ...[
                  _SectionTitle(
                    icon: Icons.shield_rounded,
                    title: '装备',
                    isDark: isDark,
                  ),
                  const SizedBox(height: 10),
                  ...equipment.map(
                    (item) => _EquipmentCard(equipment: item, isDark: isDark),
                  ),
                  const SizedBox(height: 16),
                ],
                if (widget.legacyInventory.isNotEmpty) ...[
                  _SectionTitle(
                    icon: Icons.backpack_rounded,
                    title: '旧版背包记录',
                    isDark: isDark,
                  ),
                  const SizedBox(height: 10),
                  ...widget.legacyInventory.map(
                    (item) => _LegacyItemCard(label: item, isDark: isDark),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _InventorySummary extends StatelessWidget {
  final int itemCount;
  final int equipmentCount;
  final bool isDark;

  const _InventorySummary({
    required this.itemCount,
    required this.equipmentCount,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(isDark),
      child: Row(
        children: [
          const Icon(Icons.backpack_rounded, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '物品 $itemCount 件，装备 $equipmentCount 件',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeFilterBar extends StatelessWidget {
  final ItemType? selected;
  final bool isDark;
  final ValueChanged<ItemType?> onSelected;

  const _TypeFilterBar({
    required this.selected,
    required this.isDark,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final entries = <({ItemType? type, String label})>[
      (type: null, label: '全部'),
      (type: ItemType.consumable, label: '消耗品'),
      (type: ItemType.equipment, label: '装备'),
      (type: ItemType.material, label: '材料'),
      (type: ItemType.quest, label: '任务'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: entries.map((entry) {
        final selectedNow = selected == entry.type;
        return ChoiceChip(
          label: Text(entry.label),
          selected: selectedNow,
          onSelected: (_) => onSelected(entry.type),
          selectedColor: AppColors.accent.withValues(alpha: 0.18),
          labelStyle: TextStyle(
            color: selectedNow
                ? AppColors.accent
                : (isDark ? Colors.white70 : Colors.black54),
            fontWeight: selectedNow ? FontWeight.w700 : FontWeight.w500,
          ),
          backgroundColor: isDark
              ? AppColors.darkSurface
              : Colors.white.withValues(alpha: 0.9),
        );
      }).toList(),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isDark;

  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.accent),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.accent,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ItemCard extends StatelessWidget {
  final InventoryItem item;
  final bool isDark;

  const _ItemCard({required this.item, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final description = item.data['description'] as String? ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(isDark),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.icon.isEmpty ? '📦' : item.icon,
              style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _typeLabel(item.type),
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black45,
                    fontSize: 12,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.black54,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '×${item.quantity}',
            style: const TextStyle(
              color: AppColors.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String _typeLabel(ItemType type) {
    return switch (type) {
      ItemType.consumable => '消耗品',
      ItemType.equipment => '装备物品',
      ItemType.material => '材料',
      ItemType.quest => '任务物品',
    };
  }
}

class _EquipmentCard extends StatelessWidget {
  final Equipment equipment;
  final bool isDark;

  const _EquipmentCard({required this.equipment, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(isDark),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(equipment.icon.isEmpty ? '🛡️' : equipment.icon,
              style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  equipment.name,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_slotLabel(equipment.slot)} · ${_qualityLabel(equipment.quality)}',
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black45,
                    fontSize: 12,
                  ),
                ),
                if (equipment.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    equipment.description,
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.black54,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _slotLabel(EquipmentSlot slot) {
    return switch (slot) {
      EquipmentSlot.weapon => '武器',
      EquipmentSlot.armor => '护甲',
      EquipmentSlot.accessory1 => '饰品',
      EquipmentSlot.accessory2 => '饰品',
      EquipmentSlot.special => '特殊',
    };
  }

  String _qualityLabel(EquipmentQuality quality) {
    return switch (quality) {
      EquipmentQuality.common => '普通',
      EquipmentQuality.uncommon => '优秀',
      EquipmentQuality.rare => '稀有',
      EquipmentQuality.epic => '史诗',
      EquipmentQuality.legendary => '传说',
    };
  }
}

class _LegacyItemCard extends StatelessWidget {
  final String label;
  final bool isDark;

  const _LegacyItemCard({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(isDark),
      child: Text(
        label,
        style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
      ),
    );
  }
}

class _EmptyInventory extends StatelessWidget {
  final bool isDark;

  const _EmptyInventory({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.backpack_outlined,
                size: 46, color: AppColors.accent),
            const SizedBox(height: 12),
            Text(
              '背包是空的',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '剧情中获得的物品会显示在这里。',
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.black54,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

BoxDecoration _cardDecoration(bool isDark) {
  return BoxDecoration(
    color: isDark ? AppColors.darkSurface : Colors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(
      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
    ),
  );
}
