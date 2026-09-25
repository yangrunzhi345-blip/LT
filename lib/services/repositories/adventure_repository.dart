import '../../models/adventure_config.dart';
import '../../models/adventure_runtime_state.dart';
import '../../models/diagnostics/diagnostic_session_export.dart';
import '../../models/game_state.dart';
import '../../models/message.dart';
import '../../models/scene_dialogue.dart';
import '../../models/scene_dialogue_effects.dart';
import '../../models/scene_state.dart';
import '../../models/typed_runtime_state.dart';

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
  final SceneStateChangeProposal? sceneStateProposal;
  final RuntimeStateCommitDraft? runtimeStateDraft;

  /// 自定义检测状态结算的诊断，持久化到 `scene_dialogue_turns.diagnostics_json`。
  final List<String> statusDiagnostics;

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
    this.sceneStateProposal,
    this.runtimeStateDraft,
    this.statusDiagnostics = const [],
  });
}

/// 冒险核心数据仓库接口
/// 管理 adventures、messages、game_state、summaries、branches 表
/// 以及 equipment、inventory_items
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

  /// Updates one message and removes every later message in the same branch.
  ///
  /// Implementations must perform both mutations atomically. [messageId] may
  /// be either the database row id or the stable client message id.
  Future<void> updateMessageAndDeleteFollowing({
    required int adventureId,
    required int branchId,
    required String messageId,
    required String newContent,
  }) =>
      throw UnimplementedError();

  /// Removes message history relative to [messageId] in the same branch.
  ///
  /// When [inclusive] is true, the anchor message is removed as well.
  Future<void> deleteMessageHistory({
    required int adventureId,
    required int branchId,
    required String messageId,
    required bool inclusive,
  }) =>
      throw UnimplementedError();
  Future<SceneDialogueCommitResult> commitSceneDialogueTurn(
      SceneDialogueCommit commit);

  Future<RuntimeHead> getRuntimeHead(int adventureId, int branchId) =>
      throw UnimplementedError();

  Future<RuntimeStateMutationResult> commitRuntimeMutation(
          RuntimeStateMutation mutation) =>
      throw UnimplementedError();

  Future<RuntimeStateMutationResult> revertRuntimeState({
    required int adventureId,
    required int branchId,
    required int targetRevision,
    required int expectedRevision,
    required String requestId,
  }) =>
      throw UnimplementedError();
  Future<List<RuntimeEntityState>> getRuntimeEntities(
          int adventureId, int branchId,
          {int limit = 256}) =>
      throw UnimplementedError();
  Future<List<Map<String, dynamic>>> getRecentStateChangesForEntity(
          int adventureId,
          int branchId,
          RuntimeEntityType entityType,
          String entityId,
          {int limit = 5}) =>
      throw UnimplementedError();

  Future<List<RuntimeStateEvent>> getRuntimeStateEvents({
    required int adventureId,
    required int branchId,
    String? entityId,
    int limit = 50,
  }) =>
      throw UnimplementedError();

  Future<List<RuntimeStateDiff>> getRuntimeStateDiffs({
    required int adventureId,
    required int branchId,
    String? entityId,
    int limit = 100,
  }) =>
      throw UnimplementedError();

  Future<RuntimeStateSnapshot> getRuntimeStateAtRevision({
    required int adventureId,
    required int branchId,
    required int revision,
    RuntimeEntityType? entityType,
    String? entityId,
  }) =>
      throw UnimplementedError();

  Future<RuntimeStateSnapshot> getCurrentRuntimeState({
    required int adventureId,
    required int branchId,
    RuntimeEntityType? entityType,
    String? entityId,
  }) =>
      throw UnimplementedError();

  Future<List<RuntimeTimelineEntry>> getRuntimeTimeline({
    required int adventureId,
    required int branchId,
    int? beforeRevision,
    RuntimeEntityType? entityType,
    String? entityId,
    String? eventTypeId,
    int limit = 50,
  }) =>
      throw UnimplementedError();

  Future<List<RuntimeStateDiff>> getRuntimeStateDiffsForCommit({
    required int adventureId,
    required int branchId,
    required String commitId,
  }) =>
      throw UnimplementedError();

  /// Registers an entity from an explicit user-confirmed source. Narrative AI
  /// proposals may only modify entities that already exist through this flow.
  Future<void> seedRuntimeEntity({
    required int adventureId,
    required int branchId,
    required RuntimeEntityType entityType,
    required String entityId,
  }) =>
      throw UnimplementedError();

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

  /// 导出指定冒险与分支的诊断会话数据（纯只读聚合）
  Future<DiagnosticSessionExport> getDiagnosticSessionExport({
    required int adventureId,
    required int branchId,
    int? turnLimit,
    String appVersion = '1.1.11',
    String platformName = 'unknown',
  }) =>
      throw UnimplementedError();
  Future<List<Map<String, dynamic>>> getSceneSettingCandidates(
          int adventureId, int branchId) =>
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
}
