import '../../models/narrative_map.dart';
import '../../utils/ai_adventure_utils.dart';
import '../llm/llm_gateway.dart';

/// 根据世界观和开场场景，通过 LLM 生成冒险地图数据。
class MapGenerationUseCase {
  final LlmGateway _gateway;

  const MapGenerationUseCase(this._gateway);

  /// 调用 LLM 生成地图，最多重试 2 次。
  /// 解析失败返回 null（调用方应使用回退默认值）。
  Future<MapAiGenerationResult?> generateMap({
    required String worldviewSummary,
    required String worldviewDetail,
    required String openingScene,
  }) async {
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final raw = await _gateway.generateNarrativeMap(
          worldviewSummary: worldviewSummary,
          worldviewDetail: worldviewDetail,
          openingScene: openingScene,
        );
        final json = AiAdventureUtils.parseJson(raw);
        if (json == null) {
          if (attempt < 3) {
            await Future.delayed(Duration(seconds: attempt * 2));
            continue;
          }
          return null;
        }
        return _parseResult(json);
      } catch (_) {
        if (attempt < 3) {
          await Future.delayed(Duration(seconds: attempt * 2));
          continue;
        }
        return null;
      }
    }
    return null;
  }

  MapAiGenerationResult _parseResult(Map<String, dynamic> json) {
    final rawLocations = json['locations'] as List<dynamic>? ?? [];
    final rawConnections = json['connections'] as List<dynamic>? ?? [];

    final nodes = <MapNodeSeed>[];
    for (final loc in rawLocations) {
      if (loc is! Map<String, dynamic>) continue;
      final name = (loc['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      nodes.add(MapNodeSeed(
        name: name,
        icon: MapTerrainType.fromName(loc['terrain'] as String?).icon,
        type: (loc['nodeType'] as String? ?? 'unknown'),
        terrainType: MapTerrainType.fromName(loc['terrain'] as String?),
        description: (loc['description'] as String? ?? '').trim(),
        positionX: _clampDouble(loc['x'], 0.05, 0.95),
        positionY: _clampDouble(loc['y'], 0.05, 0.95),
        isCurrent: loc['isCurrent'] == true,
      ));
    }

    if (nodes.isNotEmpty && !nodes.any((n) => n.isCurrent)) {
      nodes[0] = MapNodeSeed(
        name: nodes[0].name,
        icon: nodes[0].icon,
        type: nodes[0].type,
        terrainType: nodes[0].terrainType,
        description: nodes[0].description,
        positionX: nodes[0].positionX,
        positionY: nodes[0].positionY,
        isCurrent: true,
      );
    }

    final connections = <MapConnectionSeed>[];
    for (final conn in rawConnections) {
      if (conn is! Map<String, dynamic>) continue;
      final from = (conn['from'] as String? ?? '').trim();
      final to = (conn['to'] as String? ?? '').trim();
      if (from.isEmpty || to.isEmpty) continue;
      connections.add(MapConnectionSeed(
        fromNodeName: from,
        toNodeName: to,
        type: _connectionType(conn['type'] as String?),
        isBidirectional: conn['bidirectional'] != false,
        travelTime: (conn['travelTime'] as num?)?.toInt() ?? 10,
        energyCost: (conn['energyCost'] as num?)?.toInt() ?? 5,
      ));
    }

    return MapAiGenerationResult(nodes: nodes, connections: connections);
  }

  double _clampDouble(Object? value, double min, double max) {
    final v = (value as num?)?.toDouble() ?? (min + max) / 2;
    return v.clamp(min, max);
  }

  MapConnectionType _connectionType(String? name) {
    if (name == null || name.isEmpty) return MapConnectionType.road;
    for (final type in MapConnectionType.values) {
      if (type.name == name) return type;
    }
    return MapConnectionType.road;
  }
}
