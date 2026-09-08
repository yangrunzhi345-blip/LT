import 'dart:ui' show Brightness;
import '../models/adventure_config.dart';
import '../models/completion_params.dart';
import '../models/dialogue_level.dart';
import '../models/game_state.dart';
import '../models/message.dart';
import '../models/model_context_capability.dart';
import '../models/persona.dart';
import '../models/scene_dialogue.dart';
import '../models/scene_state.dart';
import '../models/world_entry.dart';
import '../services/llm_service.dart';
import '../services/tts_service.dart';
import 'game_engine.dart';

/// 聊天引擎宿主接口 — ChatEngine 通过此接口读取配置和状态，而非通过闭包链。
///
/// 替代 v2.6 的 ChatDependencies（35+ 个闭包 getter/setter）。
/// MessagingProvider 实现此接口，在构造 ChatEngine 时传入。
///
/// v2.7 P1-02: 每个 getter/setter 映射到对应的 Provider/Repository 字段。
abstract class ChatEngineHost {
  // ─── LLM 配置 ───
  String get apiKey;
  String get apiBaseUrl;
  LLMProvider get providerType;
  String get modelName;
  CompletionParams get completionParams;
  bool get quickMode;
  DialogueLevel get dialogueLevel;

  // ─── 作者注释 ───
  String get authorsNote;
  int get authorsNoteDepth;
  int get authorsNoteFrequency;
  String get customSystemPrompt;

  // ─── 冒险上下文 ───
  int? get currentAdventureId;
  int get currentBranchId;
  AdventureConfig? get adventureConfig;
  List<WorldEntry> get worldEntries;
  String get gameTopic;
  String get gameDifficulty;

  // ─── 游戏状态 ───
  List<Message> get messages;
  GameState get gameState;

  // ─── 人格化身 / 角色 ───
  Persona? get activePersona;
  String? get selectedCharacterName;

  /// Defaults preserve legacy hosts while scene-aware hosts provide the
  /// persisted branch-local presence list.
  List<String> get sceneParticipantIds => const ['protagonist'];
  ScenePresence? get scenePresence => null;
  SceneState get sceneState => const SceneState();
  ModelContextCapability get modelContextCapability =>
      ModelContextCapability.conservative(
        providerId: providerType.name,
        modelId: modelName,
      );

  // ─── 服务 ───
  TtsService? get tts;
  LLMService get llmService;

  // ─── 变更操作 ───
  void updateMessages(List<Message> messages);
  void updateGameState(GameState state);
  void updateAdventureConfig(AdventureConfig config);
  Future<void> applySceneDialogueCommitResult(
      SceneDialogueCommitResult result) async {
    updateGameState(result.gameState);
  }

  void advanceSelectedCharacterIfAutoEnabled();
  Future<void> changeProvider(LLMProvider provider);
  Future<void> changeModel(String model);

  // ─── 游戏引擎（v2.7 P0: DI 激活） ───
  GameEngine? get gameEngine;

  // ─── 亮度（硬编码为 light，历史原因） ───
  Brightness get brightness;
}
