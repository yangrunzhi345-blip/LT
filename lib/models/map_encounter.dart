/// 地图随机遭遇领域模型。
library;

/// 遭遇类型
enum MapEncounterType { item, combat, special }

/// 地图随机遭遇结果
class MapEncounter {
  final MapEncounterType type;
  final String? itemName;
  final String? itemIcon;
  final Map<String, dynamic>? itemData;
  final String? narrative;

  const MapEncounter._({
    required this.type,
    this.itemName,
    this.itemIcon,
    this.itemData,
    this.narrative,
  });

  factory MapEncounter.foundItem(
      String name, String icon, Map<String, dynamic> data) {
    return MapEncounter._(
        type: MapEncounterType.item,
        itemName: name,
        itemIcon: icon,
        itemData: data);
  }

  factory MapEncounter.combat() {
    return const MapEncounter._(type: MapEncounterType.combat);
  }

  factory MapEncounter.specialEvent() {
    return const MapEncounter._(
        type: MapEncounterType.special, narrative: '旅途中发生了意想不到的事情...');
  }

  bool get hasItem => type == MapEncounterType.item && itemName != null;
}
