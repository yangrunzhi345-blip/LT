import 'dart:convert';
import 'package:flutter/widgets.dart';
import '../application/adventure/adventure_assembler.dart';
import '../models/adventure_config.dart';
import '../models/supporting_character.dart';
import '../models/game_state.dart';
import '../models/message.dart';
import '../models/world_entry.dart';
import '../models/quest.dart';
import '../models/skill.dart';
import '../models/equipment.dart';
import '../models/narrative_map.dart';
import '../models/scene_dialogue.dart';
import '../models/scene_state.dart';
import '../services/narrative_map_service.dart';
import '../services/repositories/adventure_repository.dart';
import '../services/repositories/world_entry_repository.dart';
import '../services/repositories/library_repository.dart';
import '../engines/world_engine.dart';
import '../services/worldview_snapshot_service.dart';
import '../engines/game_engine.dart';
import '../utils/sensitive_data_sanitizer.dart';

/// 冒险核心数据 Provider
/// 拥有：消息、冒险CRUD、游戏状态、世界条目、分支、角色切换、导入导出
class AdventureProvider extends ChangeNotifier {
  final IAdventureRepository _adventureRepo;
  final IWorldEntryRepository _worldEntryRepo;
  final ILibraryRepository _libraryRepo;

  final List<Message> _messages = [];
  int? _currentAdventureId;
  String _currentTitle = '';
  List<Map<String, dynamic>> _adventureList = [];
  AdventureConfig? _adventureConfig;
  bool _inGame = false;
  // ignore: avoid_setters_without_getters (used by ChatProvider facade)
  set inGame(bool v) {
    if (_inGame == v) return;
    _inGame = v;
    notifyListeners();
  }

  GameState _gameState = GameState();
  int _currentBranchId = 0;
  List<Map<String, dynamic>> _branches = [];
  // worldEntries 由 WorldEngine 统一管理（避免双份列表导致 export/import 失效）
  bool _scrollToBottomPending = false;
  bool _isOpeningAdventure = false;

  String _gameTopic = '';
  String _gameDifficulty = 'normal';

  int _selectedCharacterIndex = -1;
  bool _autoAdvanceCharacter = false;
  ScenePresence? _scenePresence;
  SceneState _sceneState = const SceneState();
  List<SceneSettingCandidate> _pendingSceneCandidates = const [];
  int _sceneGeneration = 0;

  int _builderReloadTrigger = 0;

  // Managers owned by AdventureProvider
  late final WorldEngine _worldMgr;
  WorldEngine get worldMgr => _worldMgr;

  /// v2.7 P0: GameEngine — 聚合 6 个游戏机制 Manager
  late final GameEngine _gameEngine;
  GameEngine get gameEngine => _gameEngine;
  late final NarrativeMapService _narrativeMapService;
  NarrativeMapService get narrativeMapService => _narrativeMapService;

  // ─── Getters ───
  List<Message> get messages => _messages;
  int? get currentAdventureId => _currentAdventureId;
  set currentAdventureId(int? id) {
    if (_currentAdventureId == id) return;
    _currentAdventureId = id;
    notifyListeners();
  }

  String get currentTitle => _currentTitle;
  List<Map<String, dynamic>> get adventureList => _adventureList;
  AdventureConfig? get adventureConfig => _adventureConfig;
  bool get inGame => _inGame;
  GameState get gameState => _gameState;
  int get currentBranchId => _currentBranchId;
  List<Map<String, dynamic>> get branches => _branches;
  List<WorldEntry> get worldEntries => _worldMgr.worldEntries;
  set worldEntries(List<WorldEntry> entries) => _worldMgr.setEntries(entries);
  bool get scrollToBottomPending => _scrollToBottomPending;
  bool get isOpeningAdventure => _isOpeningAdventure;
  String get gameTopic => _gameTopic;
  String get gameDifficulty => _gameDifficulty;
  int get selectedCharacterIndex => _selectedCharacterIndex;
  bool get autoAdvanceCharacter => _autoAdvanceCharacter;
  int get builderReloadTrigger => _builderReloadTrigger;
  ScenePresence? get scenePresence => _scenePresence;
  SceneState get sceneState => _sceneState;
  List<String> get sceneParticipantIds =>
      _scenePresence?.participantIds ?? const ['protagonist'];
  List<SceneSettingCandidate> get pendingSceneCandidates =>
      _pendingSceneCandidates;

  String? get selectedCharacterName {
    if (_adventureConfig == null) return null;
    if (_selectedCharacterIndex < 0) return _adventureConfig!.name;
    final chars = _adventureConfig!.supportingCharacters;
    if (_selectedCharacterIndex >= chars.length) return null;
    return chars[_selectedCharacterIndex].name;
  }

  AdventureProvider({
    required IAdventureRepository adventureRepo,
    required IWorldEntryRepository worldEntryRepo,
    required ILibraryRepository libraryRepo,
  })  : _adventureRepo = adventureRepo,
        _worldEntryRepo = worldEntryRepo,
        _libraryRepo = libraryRepo {
    _narrativeMapService = NarrativeMapService(repository: _adventureRepo);
    _worldMgr = WorldEngine(
      notifyParent: notifyListeners,
      worldEntryRepo: _worldEntryRepo,
      libraryRepo: _libraryRepo,
    );

    // v2.7 P0: GameEngine DI 激活 — 6 个 Manager 全部注入
    // Skill caches for CombatManager sync callbacks
    final List<Skill> cachedSkills = [];
    final Map<String, List<CharacterSkill>> cachedCharSkills = {};

    _gameEngine = GameEngine(
      combatMgr: CombatManager(
        getGameState: () => _gameState,
        setGameState: (gs) => setGameState(gs),
        getAllSkills: () => cachedSkills,
        getCharacterSkills: (charId) => cachedCharSkills[charId] ?? [],
        notifyUI: notifyListeners,
      ),
      questMgr: QuestManager(
        getQuests: (advId) => _adventureRepo.getQuests(advId),
        saveQuest: (q) => _adventureRepo.saveQuest(q),
        updateQuest: (id, updates) => _adventureRepo.updateQuest(id, updates),
        deleteQuest: (id) => _adventureRepo.deleteQuest(id),
        getGameState: () => _gameState,
        setGameState: (gs) => setGameState(gs),
        notifyUI: notifyListeners,
      ),
      skillMgr: SkillManager(
        getAllSkills: () async {
          final rows = await _libraryRepo.getAllSkills();
          final skills = rows.map((r) => Skill.fromRow(r)).toList();
          cachedSkills.clear();
          cachedSkills.addAll(skills);
          return skills;
        },
        getCharacterSkills: (charId) async {
          final rows = await _libraryRepo.getCharacterSkills(charId);
          return rows
              .map((r) => CharacterSkill(
                    id: r['id'] as int?,
                    characterId: r['character_id'] as String? ?? charId,
                    characterType: r['character_type'] as String? ?? 'player',
                    skillId: r['skill_id'] as String? ?? '',
                    currentLevel: r['current_level'] as int? ?? 1,
                    experience: r['experience'] as int? ?? 0,
                  ))
              .toList();
        },
        saveCharacterSkill: (cs) => _libraryRepo.saveCharacterSkill(cs.toRow()),
        updateCharacterSkill: (id, updates) =>
            _libraryRepo.updateCharacterSkill(id, updates),
        getGameState: () => _gameState,
        setGameState: (gs) => setGameState(gs),
        notifyUI: notifyListeners,
      ),
      affinityMgr: AffinityManager(),
      inventoryMgr: InventoryManager(
        getEquipment: (advId) async {
          final rows = await _adventureRepo.getEquipment(advId);
          return rows.map((r) => Equipment.fromRow(r)).toList();
        },
        saveEquipment: (eq) => _adventureRepo.saveEquipment(eq.toRow()),
        getInventoryItems: (advId) async {
          final rows = await _adventureRepo.getInventoryItems(advId);
          return rows.map((r) => InventoryItem.fromRow(r)).toList();
        },
        getInventoryItemsByCharacter: (advId, charId) async {
          final rows =
              await _adventureRepo.getInventoryItemsByCharacter(advId, charId);
          return rows.map((r) => InventoryItem.fromRow(r)).toList();
        },
        saveInventoryItem: (item) =>
            _adventureRepo.saveInventoryItem(item.toRow()),
        updateInventoryItem: (id, updates) =>
            _adventureRepo.updateInventoryItem(id, updates),
        deleteInventoryItem: (id) => _adventureRepo.deleteInventoryItem(id),
        getGameState: () => _gameState,
        setGameState: (gs) => setGameState(gs),
        notifyUI: notifyListeners,
      ),
    );
  }

  // ─── Adventure CRUD ───

  Future<void> loadAdventureList() async {
    _adventureList = await _adventureRepo.getAdventures();
    notifyListeners();
  }

  Future<int> createAdventure(String title, AdventureConfig config) async {
    final frozenConfig = const AdventureAssembler().assemble(config);
    final id = await _adventureRepo.createAdventure(title, frozenConfig);
    _currentAdventureId = id;
    _currentTitle = title;
    _adventureConfig = frozenConfig;
    _messages.clear();
    _gameState = GameState(adventureId: id);
    await _adventureRepo.saveGameState(_gameState);
    _scenePresence = ScenePresence(
        adventureId: id,
        branchId: 0,
        actorId: 'protagonist',
        participantIds: const ['protagonist']);
    await _adventureRepo.saveScenePresence(_scenePresence!);
    _sceneState = SceneState(
      location: frozenConfig.effectiveOpeningScene,
      presentCharacterIds: const ['protagonist'],
      recentChanges: frozenConfig.effectiveOpeningScene.isEmpty
          ? const []
          : [frozenConfig.effectiveOpeningScene],
    );
    await _adventureRepo.saveSceneState(id, 0, _sceneState);
    final snapshot = frozenConfig.worldviewSnapshot;
    if (snapshot != null) {
      for (final entry
          in WorldviewSnapshotService.buildManagedEntries(id, snapshot)) {
        await _worldMgr.addWorldEntry(entry);
      }
    }
    await loadAdventureList();
    return id;
  }

  Future<String?> loadAdventure(int id, {bool requestScroll = true}) async {
    if (_isOpeningAdventure) return null;
    _isOpeningAdventure = true;
    try {
      final adv = await _adventureRepo.getAdventureById(id);
      if (adv == null) {
        debugPrint('Adventure $id not found in list (may have been deleted)');
        if (_currentAdventureId == id) {
          _currentAdventureId = null;
          _currentTitle = '';
          _messages.clear();
          _gameState = GameState();
          _inGame = false;
          notifyListeners();
        }
        return null;
      }
      _currentAdventureId = id;
      final generation = ++_sceneGeneration;
      _currentTitle = adv['title'] as String? ?? '';
      if (adv['config'] != null) {
        _adventureConfig =
            AdventureConfig.fromJson(jsonDecode(adv['config'] as String));
      }
      _messages.clear();
      final msgs = await _adventureRepo.getMessages(id);
      _messages.addAll(deduplicateConsecutiveUserMessages(msgs));
      final summary = await _adventureRepo.getLatestSummary(id);
      final entries = await _worldEntryRepo.getWorldEntries(id);
      entries.addAll(await _worldEntryRepo.getGlobalWorldEntries());
      _worldMgr.setEntries(entries);
      _branches = await _adventureRepo.getBranches(id);
      _currentBranchId = 0;
      await _loadScenePresence(generation: generation);
      await refreshSceneCandidates(generation: generation);
      final state = await _adventureRepo.getGameState(id);
      _gameState = state ?? GameState(adventureId: id);
      await _loadSceneState(generation: generation);
      await _gameEngine.questMgr.loadQuests(id);
      // v2.13: 加载结构化背包数据到 InventoryManager
      await _gameEngine.inventoryMgr.load(id);
      _inGame = true;
      _scrollToBottomPending = requestScroll;
      notifyListeners();
      // Return summary for ChatManager to consume
      return summary;
    } catch (e) {
      debugPrint('Failed to load adventure $id: $e');
      _inGame = false;
      _messages.clear();
      notifyListeners();
      return null;
    } finally {
      _isOpeningAdventure = false;
    }
  }

  Future<void> updateAdventureConfig(AdventureConfig config) async {
    _adventureConfig = config;
    final id = _currentAdventureId;
    if (id != null) {
      await _adventureRepo.updateAdventureConfig(id, config);
    }
    notifyListeners();
  }

  void startNewAdventureConfig(AdventureConfig config) {
    _adventureConfig = config;
    _gameTopic = '';
    _messages.clear();
    _gameState = GameState();
    _sceneState = const SceneState();
    _currentAdventureId = null;
    _currentTitle = '';
    _inGame = false;
    notifyListeners();
  }

  void startAdventure(String topic, String difficulty) {
    _gameTopic = topic;
    _gameDifficulty = difficulty;
    _messages.clear();
    notifyListeners();
  }

  void restartAdventure() {
    _messages.clear();
    _adventureConfig = null;
    _gameState = GameState();
    _sceneState = const SceneState();
    _inGame = false;
    notifyListeners();
  }

  Future<void> deleteAdventure(int id) async {
    await _adventureRepo.deleteAdventure(id);
    if (_currentAdventureId == id) {
      _currentAdventureId = null;
      _currentTitle = '';
      _messages.clear();
      _gameState = GameState();
      _sceneState = const SceneState();
      _adventureConfig = null;
      _inGame = false;
      _currentBranchId = 0;
      _branches = [];
      _worldMgr.setEntries([]);
    }
    await loadAdventureList();
    // 帧后通知，避免在 Scaffold/Drawer 动画期间触发重建
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }

  Future<void> deleteCurrentAdventure() async {
    if (_currentAdventureId == null) return;
    await deleteAdventure(_currentAdventureId!);
  }

  // ─── Game State ───

  void setGameState(GameState state) {
    _gameState = state;
  }

  /// 公开状态更新入口（含通知），用于 UI 层地图移动等场景。
  /// GameEngine 内部回调应继续使用 setGameState + notifyUI 分离模式。
  void updateGameState(GameState state) {
    _gameState = state;
    notifyListeners();
  }

  Future<void> applySceneDialogueCommitResult(
      SceneDialogueCommitResult result) async {
    _gameState = result.gameState;
    if (result.adventureConfig != null) {
      _adventureConfig = result.adventureConfig;
    }
    if (result.sceneState != null) {
      _sceneState = result.sceneState!;
    }
    final adventureId = _currentAdventureId;
    if (adventureId != null) {
      await _gameEngine.questMgr.loadQuests(adventureId);
      await _gameEngine.inventoryMgr.load(adventureId);
    }
    notifyListeners();
  }

  Future<MapMovementResult> moveToMapNode({
    required String targetNodeId,
    required String operationId,
  }) async {
    final adventureId = _currentAdventureId;
    if (adventureId == null) {
      return MapMovementResult(
        applied: false,
        error: '当前没有已打开的冒险',
        remainingEnergy: _gameState.energy,
      );
    }
    final result = await _narrativeMapService.move(
      adventureId: adventureId,
      targetNodeId: targetNodeId,
      operationId: operationId,
      gameState: _gameState,
    );
    if (result.applied && !result.duplicate) {
      _gameState = _gameState.copyWith(
        energy: result.remainingEnergy,
        currentScene: result.targetName,
      );
      notifyListeners();
    }
    return result;
  }

  Future<List<Quest>> loadCurrentQuests() async {
    final adventureId = _currentAdventureId;
    if (adventureId == null) return const [];
    return _gameEngine.questMgr.loadQuests(adventureId);
  }

  Future<Quest?> createQuestFromCurrentPlot() async {
    final adventureId = _currentAdventureId;
    if (adventureId == null) return null;

    final latestNarrative = _latestAssistantNarrative();
    final scene = _gameState.currentScene.trim();
    final fallbackTitle =
        _currentTitle.trim().isNotEmpty ? _currentTitle.trim() : '当前剧情';
    final titleBasis = scene.isNotEmpty ? scene : fallbackTitle;
    final hasActiveQuest = _gameEngine.questMgr.activeQuests.isNotEmpty;

    final quest = await _gameEngine.questMgr.createQuest(
      adventureId: adventureId,
      title: hasActiveQuest ? '推进$titleBasis' : '探索$titleBasis',
      description: latestNarrative.isEmpty ? '根据当前剧情自动建立的目标。' : latestNarrative,
      type: hasActiveQuest ? QuestType.side : QuestType.main,
      objectives: [
        QuestObjective(
          description: '围绕当前剧情继续调查关键线索',
          targetCount: 1,
          type: ObjectiveType.reach,
        ),
      ],
    );
    notifyListeners();
    return quest;
  }

  String _latestAssistantNarrative() {
    for (final message in _messages.reversed) {
      if (message.isUser) continue;
      var text = message.content.trim();
      if (text.isEmpty) continue;
      final jsonIndex = text.indexOf(RegExp(r'\{[\s\S]*"'));
      if (jsonIndex > 0) {
        text = text.substring(0, jsonIndex).trim();
      }
      text = text.replaceAll(RegExp(r'\s+'), ' ');
      if (text.length > 120) {
        text = '${text.substring(0, 120)}…';
      }
      return text;
    }
    return '';
  }

  static List<Message> deduplicateConsecutiveUserMessages(List<Message> msgs) {
    if (msgs.length <= 1) return msgs;
    final cleaned = <Message>[];
    for (int i = 0; i < msgs.length; i++) {
      final current = msgs[i];
      if (current.isUser && cleaned.isNotEmpty && cleaned.last.isUser) {
        if (cleaned.last.content.trim() == current.content.trim()) {
          // 连续相同内容的用户消息属于重试产生的冗余副本，仅保留第一条
          continue;
        }
      }
      cleaned.add(current);
    }
    return cleaned;
  }

  void setMessages(List<Message> msgs) {
    _messages.clear();
    _messages.addAll(deduplicateConsecutiveUserMessages(msgs));
  }

  // ─── World Entries（委托给 WorldEngine，统一数据源） ───

  Future<void> addWorldEntry(WorldEntry entry) async {
    await _worldMgr.addWorldEntry(entry);
    notifyListeners();
  }

  Future<void> updateWorldEntry(WorldEntry entry) async {
    await _worldMgr.updateWorldEntry(entry);
    notifyListeners();
  }

  Future<void> deleteWorldEntry(int id) async {
    await _worldMgr.deleteWorldEntry(id);
    notifyListeners();
  }

  String exportWorldBookJson() => _worldMgr.exportWorldBookJson();

  Future<String> importWorldBookJson(String json, String strategy) =>
      _worldMgr.importWorldBookJson(json, strategy, _currentAdventureId ?? 0);

  // ─── Branching ───

  Future<void> forkAdventure(int messageIndex) async {
    if (_currentAdventureId == null) return;
    final forkMsg = _messages[messageIndex];
    final branchId = await _adventureRepo.createBranch(
      adventureId: _currentAdventureId!,
      parentId: _currentBranchId > 0 ? _currentBranchId : null,
      forkAfterId: int.tryParse(forkMsg.id) ?? 0,
      name: '分支 ${_branches.length + 1}',
    );
    _currentBranchId = branchId;
    await _loadScenePresence();
    await _loadSceneState();
    await refreshSceneCandidates();
    _branches = await _adventureRepo.getBranches(_currentAdventureId!);
    notifyListeners();
  }

  Future<void> switchBranch(int branchId) async {
    final adventureId = _currentAdventureId;
    if (adventureId == null) return;
    _currentBranchId = branchId;
    final generation = ++_sceneGeneration;
    final messages =
        await _adventureRepo.getMessagesByBranch(adventureId, branchId);
    if (generation != _sceneGeneration ||
        adventureId != _currentAdventureId ||
        branchId != _currentBranchId) {
      return;
    }
    // 使用 clear+addAll 保留列表引用，避免 ChatManager 持有的引用被孤立
    _messages.clear();
    _messages.addAll(deduplicateConsecutiveUserMessages(messages));
    await _loadScenePresence(generation: generation);
    await _loadSceneState(generation: generation);
    await refreshSceneCandidates(generation: generation);
    notifyListeners();
  }

  Future<void> switchToMainBranch() async {
    final adventureId = _currentAdventureId;
    if (adventureId == null) return;
    _currentBranchId = 0;
    final generation = ++_sceneGeneration;
    final messages = await _adventureRepo.getMessages(adventureId);
    if (generation != _sceneGeneration ||
        adventureId != _currentAdventureId ||
        _currentBranchId != 0) {
      return;
    }
    // 使用 clear+addAll 保留列表引用，避免 ChatManager 持有的引用被孤立
    _messages.clear();
    _messages.addAll(deduplicateConsecutiveUserMessages(messages));
    await _loadScenePresence(generation: generation);
    await _loadSceneState(generation: generation);
    await refreshSceneCandidates(generation: generation);
    notifyListeners();
  }

  // ─── Character Selection ───

  void selectCharacter(int index) {
    if (index < -1 ||
        (index >= 0 &&
            (_adventureConfig == null ||
                index >= _adventureConfig!.supportingCharacters.length))) {
      return;
    }
    if (index >= 0 && _adventureConfig != null) {
      final npc = _adventureConfig!.supportingCharacters[index];
      if (!sceneParticipantIds.contains(npc.id)) return;
    }
    _selectedCharacterIndex = index;
    final current = _scenePresence;
    if (current != null) {
      final actorId = index < 0
          ? 'protagonist'
          : _adventureConfig!.supportingCharacters[index].id;
      _scenePresence = ScenePresence(
          adventureId: current.adventureId,
          branchId: current.branchId,
          actorId: actorId,
          participantIds: current.participantIds);
      final generation = _sceneGeneration;
      _adventureRepo.saveScenePresence(_scenePresence!).then((_) {
        // A stale completion must never affect a newly opened branch.
        if (generation != _sceneGeneration) return;
      });
    }
    notifyListeners();
  }

  void toggleAutoAdvance() {
    _autoAdvanceCharacter = !_autoAdvanceCharacter;
    notifyListeners();
  }

  void advanceSelectedCharacterIfAutoEnabled() {
    if (!_autoAdvanceCharacter || _adventureConfig == null) return;
    final validIndices = <int>[
      if (_adventureConfig!.name.isNotEmpty) -1,
      for (var index = 0;
          index < _adventureConfig!.supportingCharacters.length;
          index++)
        if (_adventureConfig!.supportingCharacters[index].isAlive &&
            sceneParticipantIds
                .contains(_adventureConfig!.supportingCharacters[index].id) &&
            _adventureConfig!.supportingCharacters[index].name.isNotEmpty)
          index,
    ];
    if (validIndices.length <= 1) return;

    final currentPosition = validIndices.indexOf(_selectedCharacterIndex);
    final nextPosition =
        currentPosition < 0 ? 0 : (currentPosition + 1) % validIndices.length;
    _selectedCharacterIndex = validIndices[nextPosition];
    notifyListeners();
  }

  Future<void> _loadScenePresence({int? generation}) async {
    final id = _currentAdventureId;
    if (id == null) return;
    final branchId = _currentBranchId;
    final captured = generation ?? _sceneGeneration;
    final found = await _adventureRepo.getScenePresence(id, branchId);
    if (captured != _sceneGeneration ||
        id != _currentAdventureId ||
        branchId != _currentBranchId) {
      return;
    }
    _scenePresence = found ??
        ScenePresence(
          adventureId: id,
          branchId: branchId,
          actorId: 'protagonist',
          participantIds: const ['protagonist'],
        );
    if (found == null) {
      await _adventureRepo.saveScenePresence(_scenePresence!);
    }
    _selectedCharacterIndex = _scenePresence!.actorId == 'protagonist'
        ? -1
        : _adventureConfig?.supportingCharacters
                .indexWhere((npc) => npc.id == _scenePresence!.actorId) ??
            -1;
  }

  Future<void> _loadSceneState({int? generation}) async {
    final id = _currentAdventureId;
    if (id == null) return;
    final branchId = _currentBranchId;
    final captured = generation ?? _sceneGeneration;
    final found = await _adventureRepo.getSceneState(id, branchId);
    if (captured != _sceneGeneration ||
        id != _currentAdventureId ||
        branchId != _currentBranchId) {
      return;
    }
    if (found != null) {
      _sceneState = found;
      return;
    }
    // Historical adventures have already evolved. Bootstrap only from their
    // current persisted state; never reactivate AdventureConfig.openingScene.
    _sceneState = SceneState(
      location: _gameState.currentScene,
      presentCharacterIds:
          _scenePresence?.participantIds ?? const ['protagonist'],
    );
    await _adventureRepo.saveSceneState(id, branchId, _sceneState);
  }

  Future<void> refreshSceneCandidates({int? generation}) async {
    final id = _currentAdventureId;
    if (id == null) return;
    final branchId = _currentBranchId;
    final captured = generation ?? _sceneGeneration;
    final rows = await _adventureRepo.getSceneSettingCandidates(id, branchId);
    if (captured != _sceneGeneration ||
        id != _currentAdventureId ||
        branchId != _currentBranchId) {
      return;
    }
    _pendingSceneCandidates = List.unmodifiable(rows
        .where(
            (row) => row['status'] == SceneSettingCandidateStatus.pending.name)
        .map((row) => SceneSettingCandidate(
            id: row['id'].toString(),
            type: row['type'].toString(),
            content: row['content'].toString(),
            contentHash: row['content_hash'].toString())));
    notifyListeners();
  }

  Future<void> addCharacterToScene(String characterId) async {
    final current = _scenePresence;
    if (current == null || current.participantIds.contains(characterId)) return;
    _scenePresence = ScenePresence(
        adventureId: current.adventureId,
        branchId: current.branchId,
        actorId: current.actorId,
        participantIds: [...current.participantIds, characterId]);
    await _adventureRepo.saveScenePresence(_scenePresence!);
    _sceneState = _sceneState.copyWith(
      presentCharacterIds: _scenePresence!.participantIds,
    );
    await _adventureRepo.saveSceneState(
      current.adventureId,
      current.branchId,
      _sceneState,
    );
    notifyListeners();
  }

  Future<void> removeCharacterFromScene(String characterId) async {
    if (characterId == 'protagonist') return;
    final current = _scenePresence;
    if (current == null) return;
    final ids =
        current.participantIds.where((id) => id != characterId).toList();
    _scenePresence = ScenePresence(
        adventureId: current.adventureId,
        branchId: current.branchId,
        actorId:
            current.actorId == characterId ? 'protagonist' : current.actorId,
        participantIds: ids);
    if (current.actorId == characterId) _selectedCharacterIndex = -1;
    await _adventureRepo.saveScenePresence(_scenePresence!);
    _sceneState = _sceneState.copyWith(presentCharacterIds: ids);
    await _adventureRepo.saveSceneState(
      current.adventureId,
      current.branchId,
      _sceneState,
    );
    notifyListeners();
  }

  Future<void> approveSceneNpc(SceneSettingCandidate candidate,
      {required String name}) async {
    final config = _adventureConfig;
    final id = _currentAdventureId;
    if (config == null ||
        id == null ||
        candidate.type != 'npc' ||
        name.trim().isEmpty) {
      return;
    }
    if (!_pendingSceneCandidates.any((item) => item.id == candidate.id) ||
        config.supportingCharacters.any((item) =>
            item.name.trim().toLowerCase() == name.trim().toLowerCase())) {
      return;
    }
    final next = AdventureConfig.fromJson(config.toJson());
    final npc = SupportingCharacter(
        name: name.trim(), role: '新角色', personality: candidate.content);
    next.supportingCharacters.add(npc);
    final current = _scenePresence;
    if (current == null) return;
    final nextPresence = ScenePresence(
        adventureId: id,
        branchId: _currentBranchId,
        actorId: current.actorId,
        participantIds: [...current.participantIds, npc.id]);
    final applied = await _adventureRepo.approveSceneNpcCandidate(
        adventureId: id,
        branchId: _currentBranchId,
        candidateId: candidate.id,
        config: next,
        presence: nextPresence);
    if (!applied ||
        id != _currentAdventureId ||
        nextPresence.branchId != _currentBranchId) {
      return;
    }
    _adventureConfig = next;
    _scenePresence = nextPresence;
    await refreshSceneCandidates();
    notifyListeners();
  }

  Future<bool> approveSceneWorldCandidate(
      SceneSettingCandidate candidate) async {
    final adventureId = _currentAdventureId;
    if (adventureId == null ||
        !candidate.isWorldSetting ||
        !_pendingSceneCandidates.any((item) => item.id == candidate.id)) {
      return false;
    }
    final entry = WorldEntry(
      adventureId: adventureId,
      keys: [candidate.displayType],
      content: '【场景确认/${candidate.displayType}】${candidate.content}',
      insertionOrder: _worldMgr.worldEntries.length + 1,
      sticky: 1,
      insertPosition: WorldEntryPosition.beforePrompt,
      sourceType: candidate.type,
      sourceId: candidate.id,
      sourceSnapshotHash: candidate.contentHash,
    );
    final entryId = await _adventureRepo.approveSceneWorldCandidate(
      adventureId: adventureId,
      branchId: _currentBranchId,
      candidateId: candidate.id,
      entry: entry,
    );
    if (entryId == null || adventureId != _currentAdventureId) return false;
    entry.id = entryId;
    _worldMgr.setEntries([..._worldMgr.worldEntries, entry]);
    await refreshSceneCandidates();
    return true;
  }

  Future<void> rejectSceneCandidate(SceneSettingCandidate candidate) async {
    if (!_pendingSceneCandidates.any((item) => item.id == candidate.id)) return;
    final adventureId = _currentAdventureId;
    if (adventureId == null) return;
    final branchId = _currentBranchId;
    await _adventureRepo.rejectSceneSettingCandidate(
        adventureId, branchId, candidate.id);
    if (adventureId != _currentAdventureId || branchId != _currentBranchId) {
      return;
    }
    await refreshSceneCandidates();
    notifyListeners();
  }

  // ─── Messages ───

  void deleteMessage(Message msg) {
    // 用 ID 查找并删除（Message 无自定义 ==，不能用 remove(obj)）
    for (int i = 0; i < _messages.length; i++) {
      if (_messages[i].id == msg.id) {
        _messages.removeAt(i);
        notifyListeners();
        return;
      }
    }
  }

  void deleteMessagesAfter(int index) {
    if (index < 0 || index >= _messages.length) return;
    _messages.removeRange(index, _messages.length);
    notifyListeners();
  }

  void consumeScrollToBottom() => _scrollToBottomPending = false;
  void incrementBuilderReloadTrigger() {
    _builderReloadTrigger++;
    notifyListeners();
  }

  // ─── Import / Export ───

  Future<String> exportToJsonl() async {
    if (_currentAdventureId == null) return '';
    final msgs = await _adventureRepo.getMessages(_currentAdventureId!);
    final buf = StringBuffer();
    for (final m in msgs) {
      buf.writeln(jsonEncode({
        'role': m.isUser ? 'user' : 'assistant',
        'content': sanitizeSensitiveText(m.content),
      }));
    }
    return buf.toString();
  }

  String exportToTxt() {
    final buf = StringBuffer();
    for (final m in _messages) {
      final role = m.isUser ? (_adventureConfig?.name ?? '玩家') : 'AI助手';
      buf.writeln('【$role】');
      buf.writeln(m.content);
      buf.writeln();
    }
    return buf.toString();
  }

  String exportToMarkdown() {
    final buf = StringBuffer(
        '# ${_currentTitle.isNotEmpty ? _currentTitle : "冒险记录"}\n\n');
    for (final m in _messages) {
      final role = m.isUser ? (_adventureConfig?.name ?? '玩家') : 'AI助手';
      buf.writeln('### $role');
      buf.writeln();
      buf.writeln(m.content);
      buf.writeln();
    }
    return buf.toString();
  }

  String exportToHtml() {
    String escapeHtml(String value) => value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');

    final title = _currentTitle.isNotEmpty ? _currentTitle : '冒险记录';
    final buf = StringBuffer('''
<!DOCTYPE html>
<html><head><meta charset="utf-8">
<title>${escapeHtml(title)}</title>
<style>body{font-family:sans-serif;max-width:800px;margin:0 auto;padding:20px}
.user{color:#1565C0} .ai{color:#333}</style></head><body>
''');
    buf.writeln('<h1>${escapeHtml(title)}</h1>');
    for (final m in _messages) {
      final cls = m.isUser ? 'user' : 'ai';
      final content = escapeHtml(m.content).replaceAll('\n', '<br>');
      buf.writeln('<div class="$cls"><p>$content</p></div>');
    }
    buf.writeln('</body></html>');
    return buf.toString();
  }

  Future<int> importFromJsonl(String content, String title) async {
    final lines = const LineSplitter().convert(content);
    final records = <Map<String, dynamic>>[];
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index].trim();
      if (line.isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map<String, dynamic> ||
            (decoded['role'] != 'user' && decoded['role'] != 'assistant') ||
            decoded['content'] is! String) {
          throw const FormatException('缺少有效 role/content');
        }
        records.add(decoded);
      } on FormatException catch (e) {
        throw FormatException('第 ${index + 1} 行无效：${e.message}');
      } catch (_) {
        throw FormatException('第 ${index + 1} 行不是有效 JSON');
      }
    }

    final config = AdventureConfig(name: '导入角色');
    // JSONL here creates a new adventure from conversation records, rather
    // than restoring a complete runtime backup. It must therefore use the
    // same assembly and initial-state path as the wizard.
    final id = await createAdventure(
      title.isEmpty ? '导入的冒险' : title,
      config,
    );
    try {
      for (final obj in records) {
        final msg = Message(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          content: obj['content'] as String? ?? '',
          isUser: obj['role'] == 'user',
        );
        await _adventureRepo.insertMessage(id, msg);
      }
    } catch (error) {
      await _adventureRepo.deleteAdventure(id);
      throw StateError('导入失败，已回滚：$error');
    }
    await loadAdventureList();
    return id;
  }
}
