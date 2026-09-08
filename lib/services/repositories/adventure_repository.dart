import '../../models/adventure_config.dart';
import '../../models/game_state.dart';
import '../../models/message.dart';
import '../../models/narrative_map.dart';
import '../../models/scene_dialogue.dart';
import '../../models/scene_dialogue_effects.dart';
import '../../models/scene_state.dart';
import '../../models/world_entry.dart';

/// A complete, idempotent scene turn.  The repository owns the transaction so
/// a cancellation or process death can never leave only half a turn on disk.
class SceneDialogueCommit {
  final String requestId;
  final int adventureId;
  final int branchId;
  final Message userMessage;
  final Message assistantMessage;
  final GameState gameState;
  final String? contextSnapshotId;
  final Map<String, dynamic> diagnostics;
  final List<SceneSettingCandidate> candidates;
  final SceneDialogueEffects effects;
  final SceneState? sceneState;

  const SceneDialogueCommit({
    required this.requestId,
    required this.adventureId,
    required this.branchId,
    required this.userMessage,
    required this.assistantMessage,
    required this.gameState,
    this.contextSnapshotId,
    this.diagnostics = const {},
    this.candidates = const [],
    this.effects = const SceneDialogueEffects(),
    this.sceneState,
  });
}

/// 冒险核心数据仓库接口
/// 管理 adventures、messages、game_state、summaries、branches 表
/// 以及 quests、equipment、inventory_items、map_nodes、map_connections (v14-v15)
abstract class IAdventureRepository {
  // ─── Adventures ───
  Future<int> createAdventure(String title, AdventureConfig config);
  Future<List<Map<String, dynamic>>> getAdventures();
  Future<Map<String, dynamic>?> getAdventureById(int id);
  Future<void> updateAdventureConfig(int id, AdventureConfig config) =>
      throw UnimplementedError();
  Future<void> deleteAdventure(int id);

  // ─── Messages ───
  Future<int> insertMessage(int adventureId, Message msg, {int branchId = 0});
  Future<List<Message>> getMessages(int adventureId, {int branchId = 0});
  Future<List<Message>> getMessagesByBranch(int adventureId, int branchId);
  Future<void> updateMessageContent(
      int adventureId, String messageId, String newContent);
  Future<SceneDialogueCommitResult> commitSceneDialogueTurn(
      SceneDialogueCommit commit);

  Future<ScenePresence?> getScenePresence(int adventureId, int branchId) =>
      throw UnimplementedError();
  Future<void> saveScenePresence(ScenePresence presence) =>
      throw UnimplementedError();
  Future<SceneState?> getSceneState(int adventureId, int branchId) =>
      throw UnimplementedError();
  Future<void> saveSceneState(
    int adventureId,
    int branchId,
    SceneState state,
  ) =>
      throw UnimplementedError();
  Future<List<Map<String, dynamic>>> getSceneSettingCandidates(
          int adventureId, int branchId) =>
      throw UnimplementedError();
  Future<void> updateSceneSettingCandidateStatus(
          String id, SceneSettingCandidateStatus status) =>
      throw UnimplementedError();
  Future<bool> rejectSceneSettingCandidate(
          int adventureId, int branchId, String id) =>
      throw UnimplementedError();

  /// Applies NPC approval as one scoped transaction.  The candidate must still
  /// be pending in the supplied adventure and branch.
  Future<bool> approveSceneNpcCandidate({
    required int adventureId,
    required int branchId,
    required String candidateId,
    required AdventureConfig config,
    required ScenePresence presence,
  }) =>
      throw UnimplementedError();

  Future<int?> approveSceneWorldCandidate({
    required int adventureId,
    required int branchId,
    required String candidateId,
    required WorldEntry entry,
  }) =>
      throw UnimplementedError();

  // ─── Game State ───
  Future<void> saveGameState(GameState state);
  Future<GameState?> getGameState(int adventureId);

  // ─── Summaries ───
  Future<int> saveSummary(int adventureId, String content, int upToId,
      {int branchId = 0, String? stateSnapshot});
  Future<String?> getLatestSummary(int adventureId, {int branchId = 0});
  Future<int> getLatestSummaryUpToId(int adventureId, {int branchId = 0});
  Future<List<Map<String, dynamic>>> getSummaries(int adventureId);
  Future<void> cleanupOldSummaries(int adventureId,
      {int branchId = 0, int maxKeep = 5});

  /// v2.13: 获取最新摘要及其状态快照，用于对比追踪状态变更。
  Future<Map<String, dynamic>?> getLatestSummaryWithSnapshot(int adventureId,
      {int branchId = 0});

  // ─── Branches ───
  Future<int> createBranch({
    required int adventureId,
    int? parentId,
    required int forkAfterId,
    String name = '',
  });
  Future<List<Map<String, dynamic>>> getBranches(int adventureId);
  Future<void> deleteBranch(int id);

  // ─── Quests (v14) ───
  Future<List<Map<String, dynamic>>> getQuests(int adventureId);
  Future<void> saveQuest(Map<String, dynamic> quest);
  Future<void> deleteQuest(String id);
  Future<void> updateQuest(String id, Map<String, dynamic> updates);

  // ─── Equipment (v15) ───
  Future<List<Map<String, dynamic>>> getEquipment(int adventureId);
  Future<void> saveEquipment(Map<String, dynamic> equipment);
  Future<List<Map<String, dynamic>>> getEquippedItems(
      int adventureId, String charId);

  // ─── Inventory Items (v15) ───
  Future<List<Map<String, dynamic>>> getInventoryItems(int adventureId);

  /// v2.13: 按角色过滤背包物品。characterId=null 返回公共物品（owner_character_id 为空）。
  Future<List<Map<String, dynamic>>> getInventoryItemsByCharacter(
      int adventureId, String? characterId);
  Future<int> saveInventoryItem(Map<String, dynamic> item);
  Future<void> deleteInventoryItem(int id);
  Future<void> updateInventoryItem(int id, Map<String, dynamic> updates);

  // ─── Map (v15) ───
  Future<List<Map<String, dynamic>>> getMapNodes(int adventureId);
  Future<void> saveMapNode(Map<String, dynamic> node);
  Future<List<Map<String, dynamic>>> getMapConnections(int adventureId);
  Future<void> saveMapConnection(Map<String, dynamic> conn);
  Future<NarrativeMapGraph> getNarrativeMap(int adventureId);
  Future<void> bootstrapNarrativeMap(int adventureId, List<MapNodeSeed> seeds);
  Future<void> mergeNarrativeMapSeeds(int adventureId, List<MapNodeSeed> seeds);
  Future<void> ensureNarrativeMapState(int adventureId, String currentName);
  Future<NarrativeMapNode?> findMapNodeByName(
      int adventureId, String name, String? parentNodeId);
  Future<void> addMapNodeAlias(
      int adventureId, String nodeId, String alias, String sourceType);
  Future<MapMovementResult> applyMapMovement({
    required int adventureId,
    required String targetNodeId,
    required String operationId,
    required MapRoute route,
    required GameState gameState,
  });
  Future<void> saveAiConnections(
      int adventureId, List<MapConnectionSeed> connections);
}
