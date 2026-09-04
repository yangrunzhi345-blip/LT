import 'dart:ui' show Brightness;
import '../engines/chat_engine_host.dart';
import '../engines/game_engine.dart';
import '../models/adventure_config.dart';
import '../models/completion_params.dart';
import '../models/dialogue_level.dart';
import '../models/game_state.dart';
import '../models/message.dart';
import '../models/persona.dart';
import '../models/scene_dialogue.dart';
import '../models/world_entry.dart';
import '../services/llm_service.dart';
import '../services/tts_service.dart';

/// v2.7 P1-02: ChatDependencies 现在是 ChatEngineHost 的测试兼容实现。
/// 生产代码通过 MessagingProvider 直接实现 ChatEngineHost；
/// 测试代码可以继续构造 ChatDependencies 作为 mock。
class ChatDependencies implements ChatEngineHost {
  @override
  List<String> get sceneParticipantIds => const ['protagonist'];
  @override
  ScenePresence? get scenePresence => null;

  // ─── ChatEngineHost 实现（委托给闭包） ───

  final String Function() _getApiKey;
  @override
  String get apiKey => _getApiKey();
  String Function() get getApiKey => _getApiKey; // 向后兼容

  final String Function() _getApiBaseUrl;
  @override
  String get apiBaseUrl => _getApiBaseUrl();
  String Function() get getApiBaseUrl => _getApiBaseUrl;

  final LLMProvider Function() _getProviderType;
  @override
  LLMProvider get providerType => _getProviderType();
  LLMProvider Function() get getProviderType => _getProviderType;

  final String Function() _getModelName;
  @override
  String get modelName => _getModelName();
  String Function() get getModelName => _getModelName;

  final String Function() _getCustomSystemPrompt;
  @override
  String get customSystemPrompt => _getCustomSystemPrompt();
  String Function() get getCustomSystemPrompt => _getCustomSystemPrompt;

  final String Function() _getAuthorsNote;
  @override
  String get authorsNote => _getAuthorsNote();
  String Function() get getAuthorsNote => _getAuthorsNote;

  final int Function() _getAuthorsNoteDepth;
  @override
  int get authorsNoteDepth => _getAuthorsNoteDepth();
  int Function() get getAuthorsNoteDepth => _getAuthorsNoteDepth;

  final int Function() _getAuthorsNoteFrequency;
  @override
  int get authorsNoteFrequency => _getAuthorsNoteFrequency();
  int Function() get getAuthorsNoteFrequency => _getAuthorsNoteFrequency;

  final AdventureConfig? Function() _getAdventureConfig;
  @override
  AdventureConfig? get adventureConfig => _getAdventureConfig();
  AdventureConfig? Function() get getAdventureConfig => _getAdventureConfig;

  final List<WorldEntry> Function() _getWorldEntries;
  @override
  List<WorldEntry> get worldEntries => _getWorldEntries();
  List<WorldEntry> Function() get getWorldEntries => _getWorldEntries;

  final Brightness Function() _getBrightness;
  @override
  Brightness get brightness => _getBrightness();
  Brightness Function() get getBrightness => _getBrightness;

  final GameEngine? Function() _getGameEngine;
  @override
  GameEngine? get gameEngine => _getGameEngine();
  GameEngine? Function() get getGameEngine => _getGameEngine;

  final String Function() _getGameTopic;
  @override
  String get gameTopic => _getGameTopic();
  String Function() get getGameTopic => _getGameTopic;

  final String Function() _getGameDifficulty;
  @override
  String get gameDifficulty => _getGameDifficulty();
  String Function() get getGameDifficulty => _getGameDifficulty;

  final CompletionParams Function() _getCompletionParams;
  @override
  CompletionParams get completionParams => _getCompletionParams();
  CompletionParams Function() get getCompletionParams => _getCompletionParams;

  final int? Function() _getCurrentAdventureId;
  @override
  int? get currentAdventureId => _getCurrentAdventureId();
  int? Function() get getCurrentAdventureId => _getCurrentAdventureId;

  final int Function() _getCurrentBranchId;
  @override
  int get currentBranchId => _getCurrentBranchId();
  int Function() get getCurrentBranchId => _getCurrentBranchId;

  final Persona? Function() _getActivePersona;
  @override
  Persona? get activePersona => _getActivePersona();
  Persona? Function() get getActivePersona => _getActivePersona;

  final String? Function() _getSelectedCharacterName;
  @override
  String? get selectedCharacterName => _getSelectedCharacterName();
  String? Function() get getSelectedCharacterName => _getSelectedCharacterName;

  final TtsService? Function() _getTts;
  @override
  TtsService? get tts => _getTts();
  TtsService? Function() get getTts => _getTts;

  final LLMService Function() _getLLMService;
  @override
  LLMService get llmService => _getLLMService();
  LLMService Function() get getLLMService => _getLLMService;

  final Future<void> Function(LLMProvider) _setProvider;
  @override
  Future<void> changeProvider(LLMProvider p) => _setProvider(p);
  Future<void> Function(LLMProvider) get setProvider => _setProvider;

  final Future<void> Function(String) _setModel;
  @override
  Future<void> changeModel(String m) => _setModel(m);
  Future<void> Function(String) get setModel => _setModel;

  final bool Function() _getQuickMode;
  @override
  bool get quickMode => _getQuickMode();
  bool Function() get getQuickMode => _getQuickMode;

  final DialogueLevel Function() _getDialogueLevel;
  @override
  DialogueLevel get dialogueLevel => _getDialogueLevel();
  DialogueLevel Function() get getDialogueLevel => _getDialogueLevel;

  final GameState Function() _getGameState;
  @override
  GameState get gameState => _getGameState();
  GameState Function() get getGameState => _getGameState;

  final void Function() _advanceSelectedCharacterIfAutoEnabled;
  @override
  void advanceSelectedCharacterIfAutoEnabled() =>
      _advanceSelectedCharacterIfAutoEnabled();

  final void Function(GameState) _setGameState;
  @override
  void updateGameState(GameState gs) => _setGameState(gs);
  @override
  Future<void> applySceneDialogueCommitResult(
      SceneDialogueCommitResult result) async {
    _setGameState(result.gameState);
  }

  void Function(GameState) get setGameState => _setGameState;

  final List<Message> Function() _getMessages;
  @override
  List<Message> get messages => _getMessages();
  List<Message> Function() get getMessages => _getMessages;

  final void Function(List<Message>) _setMessages;
  @override
  void updateMessages(List<Message> msgs) => _setMessages(msgs);
  void Function(List<Message>) get setMessages => _setMessages;

  ChatDependencies({
    required String Function() getApiKey,
    required String Function() getApiBaseUrl,
    required LLMProvider Function() getProviderType,
    required String Function() getModelName,
    required String Function() getCustomSystemPrompt,
    required String Function() getAuthorsNote,
    required int Function() getAuthorsNoteDepth,
    required int Function() getAuthorsNoteFrequency,
    required AdventureConfig? Function() getAdventureConfig,
    required List<WorldEntry> Function() getWorldEntries,
    required Brightness Function() getBrightness,
    GameEngine? Function() getGameEngine = _defaultNullGameEngine,
    required String Function() getGameTopic,
    required String Function() getGameDifficulty,
    required CompletionParams Function() getCompletionParams,
    required int? Function() getCurrentAdventureId,
    required int Function() getCurrentBranchId,
    required Persona? Function() getActivePersona,
    required String? Function() getSelectedCharacterName,
    required TtsService? Function() getTts,
    required LLMService Function() getLLMService,
    required Future<void> Function(LLMProvider) setProvider,
    required Future<void> Function(String) setModel,
    required GameState Function() getGameState,
    required void Function(GameState) setGameState,
    required List<Message> Function() getMessages,
    required void Function(List<Message>) setMessages,
    void Function() advanceSelectedCharacterIfAutoEnabled = _noop,
    bool Function() getQuickMode = _defaultFalse,
    DialogueLevel Function() getDialogueLevel = _defaultDialogueLevel,
  })  : _getApiKey = getApiKey,
        _getApiBaseUrl = getApiBaseUrl,
        _getProviderType = getProviderType,
        _getModelName = getModelName,
        _getCustomSystemPrompt = getCustomSystemPrompt,
        _getAuthorsNote = getAuthorsNote,
        _getAuthorsNoteDepth = getAuthorsNoteDepth,
        _getAuthorsNoteFrequency = getAuthorsNoteFrequency,
        _getAdventureConfig = getAdventureConfig,
        _getWorldEntries = getWorldEntries,
        _getBrightness = getBrightness,
        _getGameEngine = getGameEngine,
        _getGameTopic = getGameTopic,
        _getGameDifficulty = getGameDifficulty,
        _getCompletionParams = getCompletionParams,
        _getCurrentAdventureId = getCurrentAdventureId,
        _getCurrentBranchId = getCurrentBranchId,
        _getActivePersona = getActivePersona,
        _getSelectedCharacterName = getSelectedCharacterName,
        _getTts = getTts,
        _getLLMService = getLLMService,
        _setProvider = setProvider,
        _setModel = setModel,
        _getQuickMode = getQuickMode,
        _getDialogueLevel = getDialogueLevel,
        _getGameState = getGameState,
        _setGameState = setGameState,
        _getMessages = getMessages,
        _setMessages = setMessages,
        _advanceSelectedCharacterIfAutoEnabled =
            advanceSelectedCharacterIfAutoEnabled;

  static bool _defaultFalse() => false;
  static DialogueLevel _defaultDialogueLevel() => DialogueLevel.defaultLevel;
  static GameEngine? _defaultNullGameEngine() => null;
  static void _noop() {}
}
