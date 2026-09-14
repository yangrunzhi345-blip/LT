import 'dart:convert';

enum MapNodeType {
  world,
  continent,
  country,
  province,
  city,
  district,
  settlement,
  building,
  room,
  road,
  wild,
  forest,
  mountain,
  water,
  dungeon,
  ruin,
  portal,
  camp,
  shop,
  factionBase,
  eventLocation,
  vehicle,
  dreamSpace,
  unknown,
}

enum MapDiscoveryState {
  unknown,
  rumored,
  discovered,
  seen,
  visited,
  explored,
  mastered
}

enum MapAvailabilityState {
  available,
  locked,
  blocked,
  closed,
  dangerous,
  destroyed,
  temporary,
  expired
}

enum MapConnectionType {
  road,
  path,
  door,
  stairs,
  river,
  seaRoute,
  railway,
  portal,
  teleport,
  hiddenPassage,
  temporaryRoute,
  unknown
}

enum MapTerrainType {
  plains,
  forest,
  ocean,
  river,
  mountain,
  snowMountain,
  desert,
  swamp,
  city,
  village,
  kingdom,
  ruins,
  volcano,
  grassland,
  tundra;

  static MapTerrainType fromName(String? name) {
    if (name == null || name.isEmpty) return plains;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return plains;
  }
}

extension MapTerrainTypeExt on MapTerrainType {
  String get icon {
    return switch (this) {
      MapTerrainType.plains => '\u{1F33E}',
      MapTerrainType.forest => '\u{1F332}',
      MapTerrainType.ocean => '\u{1F30A}',
      MapTerrainType.river => '\u{1F3DE}',
      MapTerrainType.mountain => '\u{26F0}',
      MapTerrainType.snowMountain => '\u{1F3D4}',
      MapTerrainType.desert => '\u{1F3DC}',
      MapTerrainType.swamp => '\u{1F33F}',
      MapTerrainType.city => '\u{1F3F0}',
      MapTerrainType.village => '\u{1F3D8}',
      MapTerrainType.kingdom => '\u{1F451}',
      MapTerrainType.ruins => '\u{1F3DA}',
      MapTerrainType.volcano => '\u{1F30B}',
      MapTerrainType.grassland => '\u{1F331}',
      MapTerrainType.tundra => '\u{2744}',
    };
  }

  String get label {
    return switch (this) {
      MapTerrainType.plains => '平原',
      MapTerrainType.forest => '森林',
      MapTerrainType.ocean => '海洋',
      MapTerrainType.river => '河流',
      MapTerrainType.mountain => '山地',
      MapTerrainType.snowMountain => '雪山',
      MapTerrainType.desert => '沙漠',
      MapTerrainType.swamp => '沼泽',
      MapTerrainType.city => '城市',
      MapTerrainType.village => '村庄',
      MapTerrainType.kingdom => '王国',
      MapTerrainType.ruins => '遗迹',
      MapTerrainType.volcano => '火山',
      MapTerrainType.grassland => '草原',
      MapTerrainType.tundra => '冻土',
    };
  }
}

T _enumValue<T extends Enum>(Iterable<T> values, Object? value, T fallback) {
  final text = value?.toString();
  return values.where((item) => item.name == text).firstOrNull ?? fallback;
}

class NarrativeMapNode {
  final String id;
  final int adventureId;
  final String? parentNodeId;
  final String canonicalName;
  final String displayName;
  final String description;
  final String icon;
  final MapNodeType nodeType;
  final MapTerrainType terrainType;
  final int mapLevel;
  final double positionX;
  final double positionY;
  final bool positionLocked;
  final MapDiscoveryState discoveryState;
  final MapAvailabilityState availabilityState;
  final String sourceType;
  final String confidence;

  const NarrativeMapNode({
    required this.id,
    required this.adventureId,
    this.parentNodeId,
    required this.canonicalName,
    required this.displayName,
    this.description = '',
    this.icon = '',
    this.nodeType = MapNodeType.unknown,
    this.terrainType = MapTerrainType.plains,
    this.mapLevel = 1,
    required this.positionX,
    required this.positionY,
    this.positionLocked = false,
    this.discoveryState = MapDiscoveryState.discovered,
    this.availabilityState = MapAvailabilityState.available,
    this.sourceType = 'narrativeExtraction',
    this.confidence = 'probable',
  });

  factory NarrativeMapNode.fromRow(Map<String, Object?> row) =>
      NarrativeMapNode(
        id: row['id']! as String,
        adventureId: row['adventure_id']! as int,
        parentNodeId: row['parent_node_id'] as String?,
        canonicalName: (row['canonical_name'] ?? row['name'] ?? '').toString(),
        displayName: (row['display_name'] ?? row['name'] ?? '').toString(),
        description: (row['description'] ?? '').toString(),
        icon: (row['icon'] ?? '').toString(),
        nodeType: _enumValue(
            MapNodeType.values, row['node_type'], MapNodeType.unknown),
        terrainType: MapTerrainType.fromName(row['terrain_type'] as String?),
        mapLevel: row['map_level'] as int? ?? 1,
        positionX: (row['x'] as num?)?.toDouble() ?? 0.5,
        positionY: (row['y'] as num?)?.toDouble() ?? 0.5,
        positionLocked: (row['position_locked'] as int? ?? 0) == 1,
        discoveryState: _enumValue(MapDiscoveryState.values,
            row['discovery_state'], MapDiscoveryState.discovered),
        availabilityState: _enumValue(MapAvailabilityState.values,
            row['availability_state'], MapAvailabilityState.available),
        sourceType: (row['source_type'] ?? 'narrativeExtraction').toString(),
        confidence: (row['confidence'] ?? 'probable').toString(),
      );
}

class NarrativeMapConnection {
  final int id;
  final String fromNodeId;
  final String toNodeId;
  final MapConnectionType type;
  final bool isBidirectional;
  final int travelTime;
  final int energyCost;
  final int riskLevel;
  final MapAvailabilityState availabilityState;

  const NarrativeMapConnection(
      {required this.id,
      required this.fromNodeId,
      required this.toNodeId,
      this.type = MapConnectionType.unknown,
      this.isBidirectional = true,
      this.travelTime = 0,
      this.energyCost = 5,
      this.riskLevel = 0,
      this.availabilityState = MapAvailabilityState.available});

  factory NarrativeMapConnection.fromRow(Map<String, Object?> row) =>
      NarrativeMapConnection(
        id: row['id']! as int,
        fromNodeId: row['node_a_id']! as String,
        toNodeId: row['node_b_id']! as String,
        type: _enumValue(MapConnectionType.values, row['connection_type'],
            MapConnectionType.unknown),
        isBidirectional: (row['is_bidirectional'] as int? ?? 1) == 1,
        travelTime: row['travel_time'] as int? ?? 0,
        energyCost:
            row['energy_cost'] as int? ?? row['travel_cost'] as int? ?? 5,
        riskLevel: row['risk_level'] as int? ?? 0,
        availabilityState: _enumValue(MapAvailabilityState.values,
            row['availability_state'], MapAvailabilityState.available),
      );
}

class NarrativeMapGraph {
  final List<NarrativeMapNode> nodes;
  final List<NarrativeMapConnection> connections;
  final String? currentNodeId;

  const NarrativeMapGraph(
      {required this.nodes, required this.connections, this.currentNodeId});
}

class MapNodeSeed {
  final String name;
  final String icon;
  final String type;
  final MapTerrainType terrainType;
  final String description;
  final double positionX;
  final double positionY;
  final bool isCurrent;

  const MapNodeSeed({
    required this.name,
    required this.icon,
    required this.type,
    this.terrainType = MapTerrainType.plains,
    required this.description,
    required this.positionX,
    required this.positionY,
    this.isCurrent = false,
  });
}

class MapConnectionSeed {
  final String fromNodeName;
  final String toNodeName;
  final MapConnectionType type;
  final bool isBidirectional;
  final int travelTime;
  final int energyCost;

  const MapConnectionSeed({
    required this.fromNodeName,
    required this.toNodeName,
    this.type = MapConnectionType.road,
    this.isBidirectional = true,
    this.travelTime = 10,
    this.energyCost = 5,
  });
}

class MapAiGenerationResult {
  final List<MapNodeSeed> nodes;
  final List<MapConnectionSeed> connections;

  const MapAiGenerationResult({
    required this.nodes,
    this.connections = const [],
  });
}

class MapRoute {
  final List<String> nodeIds;
  final int energyCost;
  final int travelTime;
  final int risk;

  const MapRoute(
      {required this.nodeIds,
      required this.energyCost,
      required this.travelTime,
      required this.risk});
}

class MapMovementResult {
  final bool applied;
  final bool duplicate;
  final String? error;
  final String? targetName;
  final int remainingEnergy;

  const MapMovementResult(
      {required this.applied,
      this.duplicate = false,
      this.error,
      this.targetName,
      required this.remainingEnergy});
}

String encodeMapJson(Object value) => jsonEncode(value);
