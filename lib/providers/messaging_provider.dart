import 'package:flutter/foundation.dart';
import '../models/message.dart';
import '../models/game_state.dart';
import '../models/world_entry.dart';
import '../models/persona.dart';
import '../models/adventure_config.dart';
import '../models/completion_params.dart';
import '../models/dialogue_level.dart';
import '../models/scene_dialogue.dart';
import '../services/llm_service.dart';
import '../services/tts_service.dart';
import '../services/repositories/adventure_repository.dart';
import '../services/repositories/settings_repository.dart';
import '../engines/chat_engine_host.dart';
import '../engines/chat_engine.dart';
import '../engines/game_engine.dart';
import '../managers/token_manager.dart';
import '../managers/search_manager.dart';
import '../managers/bookmark_manager.dart';
import '../managers/emotion_manager.dart';
import '../managers/multi_char_manager.dart';
import 'settings_provider.dart';
import 'adventure_provider.dart';
import 'library_provider.dart';

/// 消息与对话 Provider — v2.7 P1-02 实现 ChatEngineHost 接口
///
/// 直接持有对 Settings/Adventure/Library Provider 的引用，
/// ChatEngineHost 的 getter/setter 直接委托给这些引用。
/// 消除了 v2.6 的 35+ 闭包 getter/setter（ChatDependencies）。
class MessagingProvider extends ChangeNotifier implements ChatEngineHost {
  final IAdventureRepository _adventureRepo;
  final ISettingsRepository _settingsRepo;

  late final ChatEngine _chatMgr;
  late final TokenManager _tokenMgr;
  late final SearchManager _searchMgr;
  late final BookmarkManager _bookmarkMgr;
  late final EmotionManager _emotionMgr;
  late final MultiCharManager _multiCharMgr;

  List<SceneSettingCandidate> get lastSceneCandidates =>
      _chatMgr.lastSceneCandidates;

  // ─── P1-02: 直接引用外部 Provider，消除闭包桥接 ───
  // 这些字段在 ChatProvider 构造时通过 setHostProviders() 注入

  // ChatProvider 构造时经 setHostProviders() 注入，先于任何使用。
  late SettingsProvider _settingsProv;
  late AdventureProvider _adventureProv;
  late LibraryProvider _libraryProv;

  /// v2.7 P0: GameEngine reference, set by AdventureProvider after construction
  GameEngine? _gameEngine;

  void setHostProviders(SettingsProvider settings, AdventureProvider adventure,
      LibraryProvider library) {
    _settingsProv = settings;
    _adventureProv = adventure;
    _libraryProv = library;
  }

  /// v2.7 P0: Set GameEngine after it's created by AdventureProvider
  void setGameEngine(GameEngine engine) => _gameEngine = engine;

  // ─── ChatEngineHost 实现（委托给外部 Provider） ───

  @override
  String get apiKey => _settingsProv.apiKey;
  @override
  String get apiBaseUrl => _settingsProv.apiBaseUrl;
  @override
  LLMProvider get providerType => _settingsProv.providerType;
  @override
  String get modelName => _settingsProv.modelName;
  @override
  CompletionParams get completionParams => _settingsProv.completionParams;
  @override
  bool get quickMode => _settingsProv.quickMode;
  @override
  DialogueLevel get dialogueLevel => _settingsProv.dialogueLevel;

  @override
  String get authorsNote => _settingsProv.authorsNote;
  @override
  int get authorsNoteDepth => _settingsProv.authorsNoteDepth;
  @override
  int get authorsNoteFrequency => _settingsProv.authorsNoteFrequency;
  @override
  String get customSystemPrompt => _settingsProv.customSystemPrompt;

  @override
  int? get currentAdventureId => _adventureProv.currentAdventureId;
  @override
  int get currentBranchId => _adventureProv.currentBranchId;
  @override
  AdventureConfig? get adventureConfig => _adventureProv.adventureConfig;
  @override
  List<WorldEntry> get worldEntries => _adventureProv.worldEntries;
  @override
  String get gameTopic => _adventureProv.gameTopic;
  @override
  String get gameDifficulty => _adventureProv.gameDifficulty;

  @override
  List<Message> get messages => _adventureProv.messages;
  @override
  void updateMessages(List<Message> msgs) => _adventureProv.setMessages(msgs);
  @override
  GameState get gameState => _adventureProv.gameState;
  @override
  void updateGameState(GameState gs) => _adventureProv.setGameState(gs);
  @override
  Future<void> applySceneDialogueCommitResult(
          SceneDialogueCommitResult result) =>
      _adventureProv.applySceneDialogueCommitResult(result);
  @override
  void advanceSelectedCharacterIfAutoEnabled() =>
      _adventureProv.advanceSelectedCharacterIfAutoEnabled();

  @override
  Persona? get activePersona => _libraryProv.activePersona;
  @override
  String? get selectedCharacterName => _adventureProv.selectedCharacterName;
  @override
  ScenePresence? get scenePresence => _adventureProv.scenePresence;
  @override
  List<String> get sceneParticipantIds => _adventureProv.sceneParticipantIds;

  @override
  LLMService get llmService => _settingsProv.getOrCreateLlm();
  @override
  TtsService? get tts => _settingsProv.tts;

  @override
  Brightness get brightness => _settingsProv.brightness;

  @override
  Future<void> changeProvider(LLMProvider provider) =>
      _settingsProv.setProvider(provider);
  @override
  Future<void> changeModel(String model) => _settingsProv.setModel(model);

  @override
  GameEngine? get gameEngine => _gameEngine;

  // ─── Getters ───
  bool get isLoading => _chatMgr.isLoading;
  bool get isStreaming => _chatMgr.isStreaming;
  bool get isRepairingOptions => _chatMgr.isRepairingOptions;
  String get streamingContent => _chatMgr.streamingContent;
  String get reasoningContent => _chatMgr.reasoningContent;
  ValueNotifier<String> get streamNotifier => _chatMgr.streamNotifier;
  ValueNotifier<String> get reasoningStreamNotifier =>
      _chatMgr.reasoningStreamNotifier;
  ValueNotifier<bool> get isThinkingNotifier => _chatMgr.isThinkingNotifier;
  String? get chatSummary => _chatMgr.chatSummary;
  set chatSummary(String? v) => _chatMgr.chatSummary = v;
  List<String> get parsedOptions => _chatMgr.parsedOptions;
  String? get lastErrorType => _chatMgr.lastErrorType;
  String? get lastErrorDetail => _chatMgr.lastErrorDetail;
  bool get canRetry => _chatMgr.canRetry;

  int get sessionTokens => _tokenMgr.sessionTokens;
  int get totalTokens => _tokenMgr.totalTokens;
  List<int> get messageTokens => _tokenMgr.messageTokens;

  List<int> get searchResults => _searchMgr.searchResults;
  int get currentSearchIndex => _searchMgr.currentSearchIndex;
  String get searchQuery => _searchMgr.searchQuery;

  List<String> get bookmarkedMessageIds => _bookmarkMgr.bookmarkedMessageIds;
  List<Message> bookmarkedMessages(List<Message> messages) =>
      _bookmarkMgr.bookmarkedMessages(messages);

  String get lastEmotion => _emotionMgr.lastEmotion;

  bool get multiCharacterMode => _multiCharMgr.multiCharacterMode;
  List<String> get characterQueue => _multiCharMgr.characterQueue;
  int get currentCharacterRound => _multiCharMgr.currentCharacterRound;
  String? get currentCharacterSpeaker => _multiCharMgr.currentCharacterSpeaker;

  static const errorTypeNetwork = ChatEngine.errorTypeNetwork;
  static const errorTypeApi = ChatEngine.errorTypeApi;
  static const errorTypeTimeout = ChatEngine.errorTypeTimeout;
  static const errorTypeAuth = ChatEngine.errorTypeAuth;
  static const errorTypeRate = ChatEngine.errorTypeRate;

  MessagingProvider({
    required IAdventureRepository adventureRepo,
    required ISettingsRepository settingsRepo,
  })  : _adventureRepo = adventureRepo,
        _settingsRepo = settingsRepo {
    _tokenMgr = TokenManager(
      notifyParent: notifyListeners,
      settingsRepo: _settingsRepo,
    );
    _searchMgr = SearchManager(notifyParent: notifyListeners);
    _bookmarkMgr = BookmarkManager(
      notifyParent: notifyListeners,
      settingsRepo: _settingsRepo,
    );
    _emotionMgr = EmotionManager(notifyParent: notifyListeners);
    _multiCharMgr = MultiCharManager(notifyParent: notifyListeners);
  }

  /// P1-01: 设置 Token 专用通知回调（高频：每个流式 chunk 触发一次）
  /// ChatProvider 在构造完成后调用，绑定 tokenVersion 增量。
  void setTokenNotifier(VoidCallback cb) => _tokenMgr.setNotifyToken(cb);

  /// P1-02: ChatEngineHost 接口消除 ChatDependencies 闭包上帝类。
  /// ChatEngine 直接通过 this（MessagingProvider 实现 ChatEngineHost）读取配置。
  void initChatEngine(Future<void> Function(LLMProvider) setProviderFn,
      Future<void> Function(String) setModelFn) {
    _chatMgr = ChatEngine(
      host: this,
      notifyParent: notifyListeners,
      adventureRepo: _adventureRepo,
    );
    _bookmarkMgr.setAdventureIdProvider(() => currentAdventureId);
  }

  /// 设置 ChatEngine 的直达 ChatProvider 通知回调。
  void setChatEngineRootNotifier(VoidCallback cb) {
    _chatMgr.setNotifyRoot(cb);
  }

  // ─── Messaging ───
  Future<void> sendMessage(
    String content, {
    Future<String> Function(String content)? promptTransformer,
  }) async {
    if (content.trim().isEmpty) return;
    await _chatMgr.sendMessage(
      content,
      promptTransformer: promptTransformer,
    );
  }

  Future<void> retryLast(
          {LLMProvider? overrideProvider, String? overrideModel}) =>
      _chatMgr.retryLast(
          overrideProvider: overrideProvider, overrideModel: overrideModel);

  void cancelStreaming() => _chatMgr.cancelStreaming();
  void chatManagerResetState() => _chatMgr.resetState();
  void clearError() => _chatMgr.clearError();
  void removeLastIfError() => _chatMgr.removeLastIfError();
  void clearParsedOptions() => _chatMgr.clearParsedOptions();

  List<Map<String, String>> getFullPromptPreview() =>
      _chatMgr.getFullPromptPreview();

  Future<void> editMessage(int index, String newContent,
          {int? adventureId}) async =>
      _chatMgr.editMessage(index, newContent);

  // ─── Token ───
  Future<void> loadPersistedTokenTotal() =>
      _tokenMgr.loadPersistedTotalTokens();

  void trackTokens(int tokens) => _tokenMgr.trackTokens(tokens, modelName);
  void resetSessionTokens() => _tokenMgr.resetSessionTokens();
  Map<String, dynamic> getTokenSummary() => _tokenMgr.getTokenSummary();

  // ─── Search ───
  void searchMessages(String query, List<Message> messages,
          {Set<String>? bookmarkedIds}) =>
      _searchMgr.searchMessages(query, messages, bookmarkedIds: bookmarkedIds);
  void clearSearch() => _searchMgr.clearSearch();

  // ─── Bookmarks ───
  void toggleBookmark(String id) => _bookmarkMgr.toggleBookmark(id);
  Future<void> loadBookmarks() => _bookmarkMgr.loadBookmarks();

  // ─── Emotion ───
  String detectEmotion(String content) => _emotionMgr.detectEmotion(content);

  // ─── Multi-Character ───
  void toggleMultiCharacterMode(bool v,
          {required AdventureConfig? adventureConfig}) =>
      _multiCharMgr.toggleMultiCharacterMode(v,
          adventureConfig: adventureConfig);
  void advanceCharacterRound() => _multiCharMgr.advanceCharacterRound();
  String buildMultiCharacterPrompt() =>
      _multiCharMgr.buildMultiCharacterPrompt();

  @override
  void dispose() {
    _chatMgr.dispose();
    super.dispose();
  }
}
