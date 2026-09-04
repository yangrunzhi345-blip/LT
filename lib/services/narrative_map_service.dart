import 'dart:math';

import '../models/game_state.dart';
import '../models/narrative_map.dart';
import 'repositories/adventure_repository.dart';

class NarrativeMapService {
  final IAdventureRepository _repository;

  const NarrativeMapService({required IAdventureRepository repository})
      : _repository = repository;

  Future<NarrativeMapGraph> loadGraph(int adventureId) =>
      _repository.getNarrativeMap(adventureId);

  Future<NarrativeMapGraph> ensureInitialized(
      int adventureId, List<MapNodeSeed> seeds) async {
    final existing = await loadGraph(adventureId);
    if (existing.nodes.isNotEmpty) {
      if (existing.currentNodeId == null) {
        final currentName =
            seeds.where((seed) => seed.isCurrent).firstOrNull?.name ?? '';
        await _repository.ensureNarrativeMapState(adventureId, currentName);
        await _repository.mergeNarrativeMapSeeds(adventureId, seeds);
        return loadGraph(adventureId);
      }
      await _repository.mergeNarrativeMapSeeds(adventureId, seeds);
      return loadGraph(adventureId);
    }
    if (seeds.isEmpty) {
      return existing;
    }
    await _repository.bootstrapNarrativeMap(adventureId, seeds);
    return loadGraph(adventureId);
  }

  Future<NarrativeMapNode?> resolveLocation(
          int adventureId, String name, String? parentNodeId) =>
      _repository.findMapNodeByName(adventureId, name, parentNodeId);

  Future<void> addAlias(int adventureId, String nodeId, String alias,
          {String sourceType = 'manual'}) =>
      _repository.addMapNodeAlias(adventureId, nodeId, alias, sourceType);

  MapRoute? findRoute(NarrativeMapGraph graph, String from, String to,
      {String preference = 'balanced'}) {
    if (from == to) {
      return MapRoute(nodeIds: [from], energyCost: 0, travelTime: 0, risk: 0);
    }
    final distances = <String, double>{from: 0};
    final previous = <String, String>{};
    final edgeTo = <String, NarrativeMapConnection>{};
    final pending = graph.nodes.map((node) => node.id).toSet();
    while (pending.isNotEmpty) {
      String? current;
      var best = double.infinity;
      for (final id in pending) {
        final value = distances[id] ?? double.infinity;
        if (value < best) {
          best = value;
          current = id;
        }
      }
      if (current == null || best == double.infinity) {
        break;
      }
      pending.remove(current);
      if (current == to) {
        break;
      }
      for (final edge in graph.connections) {
        if (edge.availabilityState != MapAvailabilityState.available &&
            edge.availabilityState != MapAvailabilityState.dangerous) {
          continue;
        }
        String? next;
        if (edge.fromNodeId == current) next = edge.toNodeId;
        if (edge.isBidirectional && edge.toNodeId == current) {
          next = edge.fromNodeId;
        }
        if (next == null || !pending.contains(next)) {
          continue;
        }
        final weight = switch (preference) {
          'fastest' => max(1, edge.travelTime).toDouble(),
          'safest' => max(1, edge.energyCost) + edge.riskLevel * 10.0,
          'energy' => max(1, edge.energyCost).toDouble(),
          _ => max(1, edge.travelTime) + edge.energyCost + edge.riskLevel * 3.0,
        };
        final candidate = best + weight;
        if (candidate < (distances[next] ?? double.infinity)) {
          distances[next] = candidate;
          previous[next] = current;
          edgeTo[next] = edge;
        }
      }
    }
    if (!previous.containsKey(to)) {
      return null;
    }
    final ids = <String>[to];
    var cursor = to;
    var energy = 0;
    var time = 0;
    var risk = 0;
    while (cursor != from) {
      final edge = edgeTo[cursor]!;
      energy += edge.energyCost;
      time += edge.travelTime;
      risk = max(risk, edge.riskLevel);
      cursor = previous[cursor]!;
      ids.add(cursor);
    }
    return MapRoute(
        nodeIds: ids.reversed.toList(growable: false),
        energyCost: energy,
        travelTime: time,
        risk: risk);
  }

  Future<MapMovementResult> move(
      {required int adventureId,
      required String targetNodeId,
      required String operationId,
      required GameState gameState}) async {
    final graph = await loadGraph(adventureId);
    final current = graph.currentNodeId;
    if (current == null) {
      return MapMovementResult(
          applied: false, error: '当前位置尚未确认', remainingEnergy: gameState.energy);
    }
    final route = findRoute(graph, current, targetNodeId);
    if (route == null) {
      return MapMovementResult(
          applied: false,
          error: '目标地点当前不可达',
          remainingEnergy: gameState.energy);
    }
    if (gameState.energy < route.energyCost) {
      return MapMovementResult(
          applied: false,
          error: '能量不足（需要 ${route.energyCost}）',
          remainingEnergy: gameState.energy);
    }
    return _repository.applyMapMovement(
        adventureId: adventureId,
        targetNodeId: targetNodeId,
        operationId: operationId,
        route: route,
        gameState: gameState);
  }
}
