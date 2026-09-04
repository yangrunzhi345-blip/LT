import '../application/adventure/map_generation_use_case.dart';
import '../core/operations/operation_result.dart';
import '../managers/encounter_manager.dart';
import '../managers/inventory_manager.dart';
import '../models/equipment.dart';
import '../models/narrative_map.dart';
import '../services/narrative_map_service.dart';
import '../services/repositories/adventure_repository.dart';

/// 冒险游戏域控制器 — 收口 Widget 对 GameEngine 内部 Manager 与
/// NarrativeMapService 的直接访问。
///
/// 背包/装备为只读展示 + 简单物品添加，遭遇掷骰为无状态规则委托，
/// 地图初始化经 NarrativeMapService 持久化。UI 只允许经此控制器
/// （或 ChatProvider facade）访问这些能力，不再持有 Manager/Service 实例。
class AdventureGameController {
  final InventoryManager _inventory;
  final NarrativeMapService _mapService;
  final MapGenerationUseCase? _mapGenUseCase;
  final IAdventureRepository? _adventureRepo;

  AdventureGameController({
    required InventoryManager inventory,
    required NarrativeMapService mapService,
    MapGenerationUseCase? mapGenUseCase,
    IAdventureRepository? adventureRepo,
  })  : _inventory = inventory,
        _mapService = mapService,
        _mapGenUseCase = mapGenUseCase,
        _adventureRepo = adventureRepo;

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

  // ─── 遭遇掷骰（无状态规则委托） ───

  MapEncounter? rollMapEncounter({bool isExplored = false}) =>
      EncounterManager.rollEncounter(isExplored: isExplored);

  Map<String, dynamic> randomEnemy() => EncounterManager.getRandomEnemy();

  // ─── 地图 ───

  Future<NarrativeMapGraph> ensureMapInitialized({
    required int adventureId,
    required List<MapNodeSeed> seeds,
  }) {
    return _mapService.ensureInitialized(adventureId, seeds);
  }

  /// AI 生成冒险地图。失败时回退到简单默认节点。
  Future<OperationResult<NarrativeMapGraph>> generateAiMap({
    required int adventureId,
    required String worldviewSummary,
    required String worldviewDetail,
    required String openingScene,
  }) async {
    MapAiGenerationResult? result;
    final useCase = _mapGenUseCase;
    if (useCase != null) {
      result = await useCase.generateMap(
        worldviewSummary: worldviewSummary,
        worldviewDetail: worldviewDetail,
        openingScene: openingScene,
      );
    }

    final seeds = (result != null && result.nodes.isNotEmpty)
        ? result.nodes
        : _fallbackSeeds();

    await _mapService.ensureInitialized(adventureId, seeds);

    final repo = _adventureRepo;
    if (result != null && result.connections.isNotEmpty && repo != null) {
      await repo.saveAiConnections(adventureId, result.connections);
    }

    final graph = await _mapService.loadGraph(adventureId);
    return OperationResult.success(graph);
  }

  List<MapNodeSeed> _fallbackSeeds() {
    return const [
      MapNodeSeed(
        name: '起点',
        icon: '🏠',
        type: 'settlement',
        terrainType: MapTerrainType.village,
        description: '冒险的起点',
        positionX: 0.5,
        positionY: 0.5,
        isCurrent: true,
      ),
      MapNodeSeed(
        name: '荒野',
        icon: '🌲',
        type: 'wild',
        terrainType: MapTerrainType.forest,
        description: '周围的荒野',
        positionX: 0.3,
        positionY: 0.3,
      ),
      MapNodeSeed(
        name: '远方',
        icon: '⛰',
        type: 'mountain',
        terrainType: MapTerrainType.mountain,
        description: '远处的山地',
        positionX: 0.7,
        positionY: 0.7,
      ),
    ];
  }
}
