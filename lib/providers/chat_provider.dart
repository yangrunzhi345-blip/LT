import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/adventure_config.dart';
import '../models/app_section.dart';
import '../models/game_state.dart';
import '../models/message.dart';
import '../models/resource_library_mode.dart';
import '../models/world_entry.dart';
import '../models/persona.dart';
import '../models/prompt_preset.dart';
import '../models/completion_params.dart';
import '../models/dialogue_level.dart';
import '../models/character_card.dart';
import '../models/scene_dialogue.dart';
import '../models/quest.dart';
import '../models/worldview_preset.dart';
import '../services/database_service.dart';
import '../services/adventure_start_guard.dart';
import '../services/llm_service.dart';
import '../services/tts_service.dart';
import '../services/translation_service.dart';
import '../services/repositories/adventure_repository.dart';
import '../services/repositories/adventure_repository_impl.dart';
import '../services/repositories/world_entry_repository.dart';
import '../services/repositories/world_entry_repository_impl.dart';
import '../services/repositories/library_repository.dart';
import '../services/repositories/library_repository_impl.dart';
import '../services/repositories/settings_repository.dart';
import '../services/repositories/settings_repository_impl.dart';
import 'settings_provider.dart';
import 'adventure_provider.dart';
import 'library_provider.dart';
import 'messaging_provider.dart';

/// 全局状态中心 — 外观（Facade）
///
/// 内部委托给：
/// - SettingsProvider  （API配置、模型、主题、字体、系统提示词等）
/// - AdventureProvider （冒险CRUD、消息、游戏状态、世界条目、分支、导入导出）
/// - LibraryProvider   （角色卡、提示词预设、人格化身、世界观预设）
/// - MessagingProvider （聊天引擎、Token、搜索、书签、情绪、多角色）
///
/// 所有公开 API 保持不变，UI 层无需修改。
class ChatProvider extends ChangeNotifier {
  // ─── 子 Provider ───
  late final SettingsProvider _settings;
  late final AdventureProvider _adventure;
  late final LibraryProvider _library;
  late final MessagingProvider _messaging;
  final AdventureStartGuard _adventureStartGuard = AdventureStartGuard();

  /// P1-01: 细粒度 ValueNotifier 替代单一 rebuildVersion。
  /// 每个 notifier 仅在其对应数据域变更时递增，消除流式输出期间的冗余 Widget 重建。
  /// 流式输出期间：仅 tokenVersion 高频递增（每 chunk）；其他 notifier 保持静止。

  /// Token 计数变更（每流式 chunk）→ Token 进度条
  final ValueNotifier<int> tokenVersion = ValueNotifier<int>(0);

  /// 加载/流式状态变更 → 发送按钮、TextField enable、选项面板显示
  final ValueNotifier<int> stateVersion = ValueNotifier<int>(0);

  /// 向后兼容：聚合所有细粒度 notifier，供尚未迁移的旧代码使用。
  /// 语义等价于 messageVersion + stateVersion 的合并。
  final ValueNotifier<int> rebuildVersion = ValueNotifier<int>(0);

  /// AppBar 标题栏专用触发器 — 仅当 title / model / provider 变更时递增。
  final ValueNotifier<int> titleBarVersion = ValueNotifier<int>(0);

  /// MaterialApp 级别重建触发器 — 仅当 themeMode / colorSeed 等主题相关数据变更时递增。
  final ValueNotifier<int> themeVersion = ValueNotifier<int>(0);

  /// 标记 ChatProvider 是否已销毁
  bool _disposed = false;

  /// P1-01: 向后兼容 — 触发所有细粒度 notifier + 聚合 rebuildVersion
  void triggerRebuild() {
    rebuildVersion.value++;
  }

  /// Token 有变更时调用（流式输出期间高频触发，仅影响 tokenVersion + rebuildVersion）
  void _triggerTokenRebuild() {
    tokenVersion.value++;
    rebuildVersion.value++; // 向后兼容
  }

  /// 加载/流式状态变更时调用
  void _triggerStateRebuild() {
    stateVersion.value++;
    rebuildVersion.value++;
  }

  /// 仅触发 AppBar 标题栏重建
  void _triggerTitleBarRebuild() {
    titleBarVersion.value++;
  }

  // ─── 当前章节（跨 Settings/Adventure 边界） ───
  String _currentChapter = '';

  // ─── 导航状态 ───
  AppSection _currentSection = AppSection.home;
  bool _isMainSidebarExpanded = false;
  static const _sidebarExpandedPreferenceKey = 'main_sidebar_expanded';
  bool _isAdventureChatOpen = false;
  bool _isOpeningAdventure = false;
  int? _currentCreationProjectId;
  int _creationProjectListVersion = 0;
  ResourceLibraryMode _resourceLibraryMode = ResourceLibraryMode.conversation;

  AppSection get currentSection => _currentSection;
  bool get isMainSidebarExpanded => _isMainSidebarExpanded;
  bool get isAdventureChatOpen => _isAdventureChatOpen;
  int? get currentCreationProjectId => _currentCreationProjectId;
  int get creationProjectListVersion => _creationProjectListVersion;
  ResourceLibraryMode get resourceLibraryMode => _resourceLibraryMode;

  /// 加载侧边栏 UI 偏好。没有旧值时保留收起默认值。
  Future<void> loadMainSidebarPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final expanded = prefs.getBool(_sidebarExpandedPreferenceKey);
    if (expanded == null || _disposed || _isMainSidebarExpanded == expanded) {
      return;
    }
    _isMainSidebarExpanded = expanded;
    notifyListeners();
  }

  /// 切换到指定区域。页面切换不改变全局侧边栏展开状态。
  void setCurrentSection(AppSection section) {
    if (_currentSection == section) return;
    final previousSection = _currentSection;
    _currentSection = section;
    if (section == AppSection.resources &&
        _resourceLibraryMode == ResourceLibraryMode.creation) {
      _resourceLibraryMode = ResourceLibraryMode.adventure;
    } else if (section == AppSection.resources &&
        _resourceLibraryMode != ResourceLibraryMode.creation) {
      _resourceLibraryMode = previousSection == AppSection.home
          ? ResourceLibraryMode.conversation
          : ResourceLibraryMode.adventure;
    }
    notifyListeners();
  }

  void openResourceLibrary(ResourceLibraryMode mode) {
    final changed =
        _currentSection != AppSection.resources || _resourceLibraryMode != mode;
    _currentSection = AppSection.resources;
    _resourceLibraryMode = mode;
    if (changed) notifyListeners();
  }

  void toggleMainSidebarExpanded() {
    _isMainSidebarExpanded = !_isMainSidebarExpanded;
    notifyListeners();
    unawaited(SharedPreferences.getInstance().then((prefs) {
      prefs.setBool(_sidebarExpandedPreferenceKey, _isMainSidebarExpanded);
    }));
  }

  set currentCreationProjectId(int? id) {
    if (_currentCreationProjectId == id) return;
    _currentCreationProjectId = id;
    notifyListeners();
  }

  /// 导航到冒险首页（卸载当前冒险，显示 LandingScreen）
  void navigateToAdventureHome() {
    _currentSection = AppSection.adventure;
    _isAdventureChatOpen = false;
    notifyListeners();
  }

  /// 导航到创作首页（作品中心）
  void navigateToCreationHome() {
    _currentSection = AppSection.creation;
    _currentCreationProjectId = null;
    notifyListeners();
  }

  /// 导航到指定创作项目工作区
  void openCreationProject(int projectId) {
    _currentSection = AppSection.creation;
    _currentCreationProjectId = projectId;
    notifyListeners();
  }

  /// 通知侧边栏等轻量 UI 重新加载创作项目列表。
  void refreshCreationProjectList() {
    _creationProjectListVersion++;
    notifyListeners();
  }

  // ─── 子 Provider 访问器（供 ProxyProvider 和外部使用） ───
  SettingsProvider get settingsProvider => _settings;
  AdventureProvider get adventureProvider => _adventure;
  LibraryProvider get libraryProvider => _library;
  MessagingProvider get messagingProvider => _messaging;

  LLMService get llmService => _settings.llmService;

  /// 默认构造函数 — 内部创建 Repository 实例（向后兼容）
  ChatProvider()
      : this.withRepos(
          adventureRepo:
              AdventureRepositoryImpl(getDb: () => DatabaseService.database),
          worldEntryRepo:
              WorldEntryRepositoryImpl(getDb: () => DatabaseService.database),
          libraryRepo:
              LibraryRepositoryImpl(getDb: () => DatabaseService.database),
          settingsRepo:
              SettingsRepositoryImpl(getDb: () => DatabaseService.database),
        );

  /// DI 构造函数 — 接受外部 Repository 实例
  ChatProvider.withRepos({
    required IAdventureRepository adventureRepo,
    required IWorldEntryRepository worldEntryRepo,
    required ILibraryRepository libraryRepo,
    required ISettingsRepository settingsRepo,
  }) {
    // ─── 创建子 Provider（使用传入的 Repository） ───
    _settings = SettingsProvider(settingsRepo: settingsRepo);
    _adventure = AdventureProvider(
      adventureRepo: adventureRepo,
      worldEntryRepo: worldEntryRepo,
      libraryRepo: libraryRepo,
    );
    _library = LibraryProvider(libraryRepo: libraryRepo);
    _messaging = MessagingProvider(
      adventureRepo: adventureRepo,
      settingsRepo: settingsRepo,
    );

    // ─── P1-02: 直接引用注入，替代 35+ 闭包 getter/setter ───
    _messaging.setHostProviders(_settings, _adventure, _library);
    // v2.7 P0: GameEngine DI 激活 — 注入 GameEngine 到 ChatEngine
    _messaging.setGameEngine(_adventure.gameEngine);
    _messaging.initChatEngine(_settings.setProvider, _settings.setModel);
    // P1-01: Token 专用通知 → 仅重建 Token 进度条，不影响其他 Widget
    _messaging.setTokenNotifier(_triggerTokenRebuild);

    // ─── 直达通知链路：ChatManager 内部状态变更 → 直接触发 UI 刷新 ───
    // notifyListeners() 触发：
    //   1. Provider 的 InheritedWidget 依赖链（Consumer/context.watch）
    //   2. triggerRebuild()（通过 _messaging.addListener(triggerRebuild) 自动调用）
    // 注意：这里只调用 notifyListeners()，不调用 triggerRebuild()。
    // triggerRebuild() 已通过 _messaging.addListener(triggerRebuild) 在 notifyParent()
    // → MessagingProvider.notifyListeners() 时自动触发。若此处再调用，会导致
    // _notifyAll() 中 rebuildVersion 被递增两次（第一次来自 addListener 链，
    // 第二次来自此闭包），在 Android 16 / OriginOS 6 上双次 ValueNotifier 通知
    // 可能干扰 ListView.builder 的关键帧元素匹配。
    _messaging.setChatEngineRootNotifier(() {
      notifyListeners();
      _triggerStateRebuild(); // P1-01: ChatEngine 状态变更（发送开始/结束）→ UI 状态重建
    });

    // ─── 转发子 Provider 的 notifyListeners ───
    _settings.addListener(notifyListeners);
    _adventure.addListener(notifyListeners);
    _library.addListener(notifyListeners);
    _messaging.addListener(notifyListeners);
    // 同时触发 ValueNotifier 链（ListenableBuilder 依赖），
    // 确保 release 模式下即使 InheritedWidget 链失效也能重建 UI
    _settings.addListener(triggerRebuild);
    _adventure.addListener(triggerRebuild);
    _library.addListener(triggerRebuild);
    _messaging.addListener(triggerRebuild);

    // ─── 主题变更同步：当 SettingsProvider 中主题/色彩/字号变更时，自动触发 MaterialApp 重建 ───
    ThemeMode lastThemeMode = _settings.themeMode;
    Color? lastColorSeed = _settings.colorSeed;
    double lastChatFontSize = _settings.chatFontSize;
    _settings.addListener(() {
      final themeChanged = _settings.themeMode != lastThemeMode ||
          _settings.colorSeed != lastColorSeed ||
          _settings.chatFontSize != lastChatFontSize;
      if (themeChanged) {
        lastThemeMode = _settings.themeMode;
        lastColorSeed = _settings.colorSeed;
        lastChatFontSize = _settings.chatFontSize;
        themeVersion.value++;
      }
    });

    // ─── 初始化 ───
    _init();
  }

  Future<void> _init() async {
    _settings.tts.init();
    await loadApiKey();
    await _messaging.loadPersistedTokenTotal();
    if (_disposed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_disposed) return; // 防止在 provider 销毁后操作
      _adventure
          .loadAdventureList()
          .catchError((e) => debugPrint('[ChatProvider] 加载冒险列表失败: $e'));
      await DatabaseService.seedDefaultWorldviews();
      await DatabaseService.seedDefaultCharacterCards();
      await DatabaseService.seedDefaultSkills();
      await _adventure.worldMgr.loadWorldviewPresets();
      await _library.loadCharacterCards();
      _library
          .loadPersonas()
          .catchError((e) => debugPrint('[ChatProvider] 加载角色卡失败: $e'));
      _library
          .loadPresets()
          .catchError((e) => debugPrint('[ChatProvider] 加载预设失败: $e'));
      _messaging
          .loadBookmarks()
          .catchError((e) => debugPrint('[ChatProvider] 加载书签失败: $e'));
      notifyListeners();
    });
    if (_settings.isKeyConfigured) {
      _adventure
          .loadAdventureList()
          .catchError((e) => debugPrint('[ChatProvider] 加载冒险列表失败: $e'));
    }
  }

  /// 公开的 loadApiKey（供 main.dart 调用并保持向后兼容）
  Future<void> loadApiKey() async {
    await _settings.loadApiKey();
    if (_disposed) return;
    themeVersion.value++;
  }

  // ═══════════════════════════════════════════════════════════
  // Settings — 委托给 SettingsProvider
  // ═══════════════════════════════════════════════════════════

  LLMService getOrCreateLlm() => _settings.getOrCreateLlm();

  @Deprecated(
      'Use settingsProvider.testCurrentLlmConnection instead. Will be removed in a future release')
  Future<bool> testCurrentLlmConnection() =>
      _settings.testCurrentLlmConnection();

  String get apiKey => _settings.apiKey;
  String get apiBaseUrl => _settings.apiBaseUrl;
  bool get isKeyConfigured => _settings.isKeyConfigured;
  LLMProvider get providerType => _settings.providerType;
  String get modelName => _settings.modelName;
  Brightness get brightness => _settings.brightness;
  ThemeMode get themeMode => _settings.themeMode;

  @Deprecated(
      'Use settingsProvider.searchVisible instead. Will be removed in a future release')
  bool get searchVisible => _settings.searchVisible;
  Color? get colorSeed => _settings.colorSeed;
  Future<void> setColorSeed(Color seed) async {
    await _settings.setColorSeed(seed);
    themeVersion.value++;
  }

  @Deprecated(
      'Use settingsProvider.quickMode instead. Will be removed in a future release')
  bool get quickMode => _settings.quickMode;
  @Deprecated(
      'Use settingsProvider.setQuickMode instead. Will be removed in a future release')
  Future<void> setQuickMode(bool v) => _settings.setQuickMode(v);
  @Deprecated(
      'Use settingsProvider.dialogueLevel instead. Will be removed in a future release')
  DialogueLevel get dialogueLevel => _settings.dialogueLevel;
  @Deprecated(
      'Use settingsProvider.setDialogueLevel instead. Will be removed in a future release')
  Future<void> setDialogueLevel(DialogueLevel level) =>
      _settings.setDialogueLevel(level);
  @Deprecated(
      'Use settingsProvider.customSystemPrompt instead. Will be removed in a future release')
  String get customSystemPrompt => _settings.customSystemPrompt;
  @Deprecated(
      'Use settingsProvider.authorsNote instead. Will be removed in a future release')
  String get authorsNote => _settings.authorsNote;
  int get authorsNoteDepth => _settings.authorsNoteDepth;
  int get authorsNoteFrequency => _settings.authorsNoteFrequency;
  double get chatFontSize => _settings.chatFontSize;
  double get textScaleFactor => chatFontSize / 14.0;
  @Deprecated(
      'Use settingsProvider.isOnline instead. Will be removed in a future release')
  bool get isOnline => _settings.isOnline;
  @Deprecated(
      'Use settingsProvider.recentModels instead. Will be removed in a future release')
  List<String> get recentModels => _settings.recentModels;
  CompletionParams get completionParams => _settings.completionParams;
  // TTS 和 Translation 使用 SettingsProvider 的实例（避免双实例问题）
  @Deprecated(
      'Use settingsProvider.tts instead. Will be removed in a future release')
  TtsService get tts => _settings.tts;
  @Deprecated(
      'Use settingsProvider.translator instead. Will be removed in a future release')
  TranslationService get translator => _settings.translator;
  TextEditingController get searchController => _settings.searchController;

  @Deprecated(
      'Use settingsProvider.setApiKey instead. Will be removed in a future release')
  Future<void> setApiKey(String key) => _settings.setApiKey(key);
  @Deprecated(
      'Use settingsProvider.setApiBaseUrl instead. Will be removed in a future release')
  Future<void> setApiBaseUrl(String url) => _settings.setApiBaseUrl(url);

  /// 获取指定提供商的已保存 Key（可能为空）
  @Deprecated(
      'Use settingsProvider.getProviderKey instead. Will be removed in a future release')
  String? getProviderKey(LLMProvider p) => _settings.getProviderKey(p);

  /// 获取指定提供商的已保存模型（可能为空）
  @Deprecated(
      'Use settingsProvider.getProviderModel instead. Will be removed in a future release')
  String? getProviderModel(LLMProvider p) => _settings.getProviderModel(p);

  /// 获取指定提供商的有效端点；内置服务商始终返回官方端点。
  @Deprecated(
      'Use settingsProvider.getProviderBaseUrl instead. Will be removed in a future release')
  String getProviderBaseUrl(LLMProvider p) => _settings.getProviderBaseUrl(p);

  /// 切换 LLM 提供商。若新提供商无已配置 Key，返回 false 供 UI 提示。
  Future<bool> setProvider(LLMProvider p) async {
    await _settings.setProvider(p);
    _triggerTitleBarRebuild();
    return _settings.isKeyConfigured;
  }

  Future<void> setModel(String m) async {
    await _settings.setModel(m);
    _triggerTitleBarRebuild();
  }

  @Deprecated(
      'Use settingsProvider.setCustomSystemPrompt instead. Will be removed in a future release')
  Future<void> setCustomSystemPrompt(String p) =>
      _settings.setCustomSystemPrompt(p);
  @Deprecated(
      'Use settingsProvider.setAuthorsNote instead. Will be removed in a future release')
  Future<void> setAuthorsNote(String n) => _settings.setAuthorsNote(n);
  @Deprecated(
      'Use settingsProvider.setAuthorsNoteConfig instead. Will be removed in a future release')
  Future<void> setAuthorsNoteConfig(int d, int f) =>
      _settings.setAuthorsNoteConfig(d, f);
  @Deprecated(
      'Use settingsProvider.updateBrightness instead. Will be removed in a future release')
  void updateBrightness(Brightness v) => _settings.updateBrightness(v);
  Future<void> updateThemeMode(ThemeMode m) async {
    await _settings.updateThemeMode(m);
    themeVersion.value++;
  }

  Future<void> setChatFontSize(double s) async {
    await _settings.setChatFontSize(s);
    themeVersion.value++;
  }

  Future<void> resetTheme() async {
    await _settings.resetTheme();
    themeVersion.value++;
  }

  @Deprecated(
      'Use settingsProvider.setCompletionParams instead. Will be removed in a future release')
  Future<void> setCompletionParams(CompletionParams p) =>
      _settings.setCompletionParams(p);

  bool get enableThinking => _settings.enableThinking;
  String get reasoningEffort => _settings.reasoningEffort;
  Future<void> setEnableThinking(bool v) => _settings.setEnableThinking(v);
  Future<void> setReasoningEffort(String v) => _settings.setReasoningEffort(v);

  void toggleSearch() {
    _settings.toggleSearch();
    if (!_settings.searchVisible) _messaging.clearSearch();
  }

  // ═══════════════════════════════════════════════════════════
  // Adventure — 委托给 AdventureProvider
  // ═══════════════════════════════════════════════════════════

  List<Message> get messages => _adventure.messages;
  int? get currentAdventureId => _adventure.currentAdventureId;
  String get currentTitle => _adventure.currentTitle;
  List<Map<String, dynamic>> get adventureList => _adventure.adventureList;
  AdventureConfig? get adventureConfig => _adventure.adventureConfig;
  Future<void> updateAdventureConfig(AdventureConfig config) =>
      _adventure.updateAdventureConfig(config);
  bool get inGame => _adventure.inGame;
  GameState get gameState => _adventure.gameState;
  int get currentBranchId => _adventure.currentBranchId;
  List<WorldEntry> get worldEntries => _adventure.worldEntries;
  bool get scrollToBottomPending => _adventure.scrollToBottomPending;
  int get selectedCharacterIndex => _adventure.selectedCharacterIndex;
  bool get autoAdvanceCharacter => _adventure.autoAdvanceCharacter;
  String? get selectedCharacterName => _adventure.selectedCharacterName;
  ScenePresence? get scenePresence => _adventure.scenePresence;
  List<String> get sceneParticipantIds => _adventure.sceneParticipantIds;

  List<WorldviewPreset> get worldviewPresets =>
      _adventure.worldMgr.worldviewPresets;
  List<SceneSettingCandidate> get lastSceneCandidates =>
      _messaging.lastSceneCandidates;
  List<SceneSettingCandidate> get pendingSceneCandidates =>
      _adventure.pendingSceneCandidates;

  @Deprecated(
      'Use adventureProvider.createAdventure instead. Will be removed in a future release')
  Future<int> createAdventure(String t, AdventureConfig c) =>
      _adventure.createAdventure(t, c);

  Future<void> loadAdventureList() => _adventure.loadAdventureList();
  Future<void> addCharacterToScene(String id) =>
      _adventure.addCharacterToScene(id);
  Future<void> removeCharacterFromScene(String id) =>
      _adventure.removeCharacterFromScene(id);
  Future<void> approveSceneNpc(SceneSettingCandidate candidate,
          {required String name}) =>
      _adventure.approveSceneNpc(candidate, name: name);
  Future<bool> approveSceneWorldCandidate(SceneSettingCandidate candidate) =>
      _adventure.approveSceneWorldCandidate(candidate);
  Future<void> rejectSceneCandidate(SceneSettingCandidate candidate) =>
      _adventure.rejectSceneCandidate(candidate);
  Future<void> refreshSceneCandidates() => _adventure.refreshSceneCandidates();

  Future<void> loadAdventure(int id) async {
    await openAdventure(id);
  }

  /// 只重读当前冒险的数据，不改变导航、不会取消流式消息，也不要求聊天页滚底。
  Future<bool> refreshCurrentAdventure() async {
    final id = _adventure.currentAdventureId;
    if (id == null || _messaging.isLoading || _messaging.isStreaming) {
      return false;
    }
    final summary = await _adventure.loadAdventure(id, requestScroll: false);
    if (_adventure.currentAdventureId != id) return false;
    _messaging.chatSummary = summary;
    await _messaging.loadBookmarks();
    notifyListeners();
    return true;
  }

  Future<void> openAdventure(int id) async {
    if (_isOpeningAdventure) return;
    if (_adventure.currentAdventureId == id && _isAdventureChatOpen) {
      _currentSection = AppSection.adventure;
      notifyListeners();
      return;
    }

    _isOpeningAdventure = true;
    _messaging.cancelStreaming();
    _messaging.chatManagerResetState();
    _currentSection = AppSection.adventure;
    notifyListeners();

    try {
      final summary = await _adventure.loadAdventure(id);
      if (_adventure.currentAdventureId != id) {
        debugPrint('[ChatProvider] 冒险 $id 不存在或已删除，打开失败');
        return;
      }
      _messaging.chatSummary = summary;
      // Ensure any stale parsed options from previous adventure are cleared
      _messaging.clearParsedOptions();
      await _messaging.loadBookmarks();
      _isAdventureChatOpen = true;
      _triggerTitleBarRebuild(); // title 已变更
      notifyListeners();
    } finally {
      _isOpeningAdventure = false;
      notifyListeners();
    }
  }

  @Deprecated(
      'Use adventureProvider.startNewAdventureConfig instead. Will be removed in a future release')
  void startNewAdventureConfig(AdventureConfig c) =>
      _adventure.startNewAdventureConfig(c);
  void startAdventure(String t, String d) => _adventure.startAdventure(t, d);
  void restartAdventure() {
    _adventure.restartAdventure();
    _messaging.clearParsedOptions();
    _isAdventureChatOpen = false;
    _currentSection = AppSection.home;
    _triggerTitleBarRebuild(); // title 可能已重置
  }

  Future<int> startAdventureWithConfig(AdventureConfig c) {
    final presetKey = AdventureStartGuard.keyForConfig(c);
    return _adventureStartGuard.run(
      presetKey: presetKey,
      create: () => _startAdventureWithConfigUnlocked(c),
    );
  }

  Future<int> _startAdventureWithConfigUnlocked(AdventureConfig c) async {
    // 设置加载状态，防止用户在初始化期间发送消息
    _adventure.startNewAdventureConfig(c);
    _adventure.inGame = true;
    _currentSection = AppSection.adventure;
    _isAdventureChatOpen = false;
    notifyListeners(); // 确保 UI 感知到 inGame 状态变化

    try {
      await _adventure.loadAdventureList();
      final baseTitle = c.name.isNotEmpty ? '${c.name}的冒险' : '文字冒险';
      final title = _uniqueTitle(baseTitle, _adventure.adventureList);
      final adventureId = await _adventure.createAdventure(title, c);
      _isAdventureChatOpen = true;
      _triggerTitleBarRebuild(); // title 已创建

      final openingOptionsText = c.openingOptions
          .asMap()
          .entries
          .map((e) => '${e.key + 1}. ${e.value}')
          .join('\n');
      final initialMessage = [
        '【开场场景】',
        if (c.effectiveOpeningScene.isNotEmpty) c.effectiveOpeningScene,
        '',
        '【可用行动】',
        openingOptionsText,
      ].join('\n');
      notifyListeners();
      // 冒险记录创建后立即切换到对话页。开场请求在后台继续执行，
      // 让对话页直接承接 ChatEngine 的流式气泡，而不是等待整段首幕生成完。
      unawaited(sendMessage(initialMessage).catchError((error, stackTrace) {
        debugPrint('生成开场场景失败: $error');
      }));
      return adventureId;
    } catch (e) {
      _adventure.inGame = false;
      _adventure.messages.add(Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: '创建场景失败：${e.toString()}',
        isUser: false,
      ));
      _adventure.notifyListeners();
      notifyListeners();
      rethrow;
    }
  }

  /// 生成唯一标题：如果 [baseTitle] 已存在，追加递增数字后缀
  /// 例如 "星辰的冒险" → "星辰的冒险1" → "星辰的冒险2" ...
  String _uniqueTitle(
      String baseTitle, List<Map<String, dynamic>> existingList) {
    final existingTitles =
        existingList.map((e) => e['title'] as String? ?? '').toSet();
    if (!existingTitles.contains(baseTitle)) return baseTitle;
    int counter = 1;
    while (existingTitles.contains('$baseTitle$counter')) {
      counter++;
    }
    return '$baseTitle$counter';
  }

  Future<void> deleteAdventure(int id) async {
    _messaging.cancelStreaming();
    if (_adventure.currentAdventureId == id) {
      _messaging.chatManagerResetState();
    }
    await _adventure.deleteAdventure(id);
    if (_adventure.currentAdventureId == null) {
      _isAdventureChatOpen = false;
      _triggerTitleBarRebuild(); // 当前冒险被删除，title 已清除
    }
  }

  void selectCharacter(int i) => _adventure.selectCharacter(i);
  void toggleAutoAdvance() => _adventure.toggleAutoAdvance();
  void advanceSelectedCharacterIfAutoEnabled() =>
      _adventure.advanceSelectedCharacterIfAutoEnabled();
  Future<List<Quest>> loadCurrentQuests() => _adventure.loadCurrentQuests();
  Future<Quest?> createQuestFromCurrentPlot() =>
      _adventure.createQuestFromCurrentPlot();

  void consumeScrollToBottom() => _adventure.consumeScrollToBottom();

  void deleteMessage(Message m) => _adventure.deleteMessage(m);
  void deleteMessagesAfter(int i) => _adventure.deleteMessagesAfter(i);

  @Deprecated(
      'Use adventureProvider.addWorldEntry instead. Will be removed in a future release')
  Future<void> addWorldEntry(WorldEntry e) => _adventure.addWorldEntry(e);
  @Deprecated(
      'Use adventureProvider.updateWorldEntry instead. Will be removed in a future release')
  Future<void> updateWorldEntry(WorldEntry e) => _adventure.updateWorldEntry(e);
  @Deprecated(
      'Use adventureProvider.deleteWorldEntry instead. Will be removed in a future release')
  Future<void> deleteWorldEntry(int id) => _adventure.deleteWorldEntry(id);
  @Deprecated(
      'Use adventureProvider.exportWorldBookJson instead. Will be removed in a future release')
  String exportWorldBookJson() => _adventure.exportWorldBookJson();
  @Deprecated(
      'Use adventureProvider.importWorldBookJson instead. Will be removed in a future release')
  Future<String> importWorldBookJson(String j, String s) =>
      _adventure.importWorldBookJson(j, s);

  Future<void> forkAdventure(int i) => _adventure.forkAdventure(i);
  @Deprecated(
      'Use adventureProvider.switchBranch instead. Will be removed in a future release')
  Future<void> switchBranch(int id) async {
    _messaging.cancelStreaming();
    _messaging.chatManagerResetState();
    await _adventure.switchBranch(id);
  }

  Future<String> exportToJsonl() => _adventure.exportToJsonl();
  String exportToTxt() => _adventure.exportToTxt();
  String exportToMarkdown() => _adventure.exportToMarkdown();
  String exportToHtml() => _adventure.exportToHtml();
  Future<int> importFromJsonl(String c, String t) =>
      _adventure.importFromJsonl(c, t);

  // ═══════════════════════════════════════════════════════════
  // Library — 委托给 LibraryProvider
  // ═══════════════════════════════════════════════════════════

  @Deprecated(
      'Use libraryProvider.presets instead. Will be removed in a future release')
  List<PromptPreset> get presets => _library.presets;
  @Deprecated(
      'Use libraryProvider.activePresetId instead. Will be removed in a future release')
  String? get activePresetId => _library.activePresetId;
  @Deprecated(
      'Use libraryProvider.personas instead. Will be removed in a future release')
  List<Persona> get personas => _library.personas;
  Persona? get activePersona => _library.activePersona;

  @Deprecated(
      'Use libraryProvider.loadPersonas instead. Will be removed in a future release')
  Future<void> loadPersonas() => _library.loadPersonas();
  @Deprecated(
      'Use libraryProvider.addPersona instead. Will be removed in a future release')
  Future<void> addPersona(Persona p) => _library.addPersona(p);
  @Deprecated(
      'Use libraryProvider.updatePersona instead. Will be removed in a future release')
  Future<void> updatePersona(Persona p) => _library.updatePersona(p);
  @Deprecated(
      'Use libraryProvider.deletePersona instead. Will be removed in a future release')
  Future<void> deletePersona(String id) => _library.deletePersona(id);
  @Deprecated(
      'Use libraryProvider.setActivePersona instead. Will be removed in a future release')
  Future<void> setActivePersona(String? id) => _library.setActivePersona(id);

  @Deprecated(
      'Use libraryProvider.importCharacterCardJson instead. Will be removed in a future release')
  Future<String> importCharacterCardJson(String j) =>
      _library.importCharacterCardJson(j);
  @Deprecated(
      'Use libraryProvider.buildConfigFromCard instead. Will be removed in a future release')
  AdventureConfig buildConfigFromCard(CharacterCard c) =>
      _library.buildConfigFromCard(c);
  @Deprecated(
      'Use libraryProvider.saveCharacterCard instead. Will be removed in a future release')
  Future<void> saveCharacterCard(CharacterCard c) =>
      _library.saveCharacterCard(c);
  @Deprecated(
      'Use libraryProvider.deleteCharacterCard instead. Will be removed in a future release')
  Future<void> deleteCharacterCard(int id) => _library.deleteCharacterCard(id);
  @Deprecated(
      'Use libraryProvider.deleteCharacterCardById instead. Will be removed in a future release')
  Future<void> deleteCharacterCardById(String id) =>
      _library.deleteCharacterCardById(id);
  @Deprecated(
      'Use libraryProvider.loadCharacterCards instead. Will be removed in a future release')
  Future<void> loadCharacterCards() => _library.loadCharacterCards();

  @Deprecated(
      'Use libraryProvider.loadPresets instead. Will be removed in a future release')
  Future<void> loadPresets() => _library.loadPresets();
  @Deprecated(
      'Use libraryProvider.savePresets instead. Will be removed in a future release')
  Future<void> savePresets() => _library.savePresets();
  @Deprecated(
      'Use libraryProvider.addPreset instead. Will be removed in a future release')
  Future<void> addPreset(PromptPreset p) => _library.addPreset(p);
  @Deprecated(
      'Use libraryProvider.updatePreset instead. Will be removed in a future release')
  Future<void> updatePreset(PromptPreset p) => _library.updatePreset(p);
  @Deprecated(
      'Use libraryProvider.deletePreset instead. Will be removed in a future release')
  Future<void> deletePreset(String id) => _library.deletePreset(id);
  @Deprecated(
      'Use libraryProvider.presetMgr.applyPreset instead. Will be removed in a future release')
  Future<void> applyPreset(PromptPreset p) async {
    await _library.presetMgr.applyPreset(
      p,
      setSystemPrompt: _settings.setCustomSystemPrompt,
      setAuthorsNote: _settings.setAuthorsNote,
      setAuthorsNoteConfig: _settings.setAuthorsNoteConfig,
      setTranslationMode: (_) {}, // translator mode handled externally
      setProvider: _settings.setProvider,
      setModel: _settings.setModel,
      onSetCompletionParams: _settings.setCompletionParams,
    );
  }

  @Deprecated(
      'Use libraryProvider.importPresetsFromJson instead. Will be removed in a future release')
  String importPresetsFromJson(String j) => _library.importPresetsFromJson(j);
  @Deprecated(
      'Use libraryProvider.exportPresetsToJson instead. Will be removed in a future release')
  String exportPresetsToJson() => _library.exportPresetsToJson();

  @Deprecated(
      'Use adventureProvider.worldMgr.saveWorldviewPreset instead. Will be removed in a future release')
  Future<void> saveWorldviewPreset(String n, String d) =>
      _adventure.worldMgr.saveWorldviewPreset(n, d);
  @Deprecated(
      'Use adventureProvider.worldMgr.loadWorldviewPresets instead. Will be removed in a future release')
  Future<void> loadWorldviewPresets() =>
      _adventure.worldMgr.loadWorldviewPresets();

  // ═══════════════════════════════════════════════════════════
  // Messaging — 委托给 MessagingProvider
  // ═══════════════════════════════════════════════════════════

  bool get isLoading => _messaging.isLoading;
  bool get isStreaming => _messaging.isStreaming;
  @Deprecated(
      'Use messagingProvider.streamingContent instead. Will be removed in a future release')
  String get streamingContent => _messaging.streamingContent;
  ValueNotifier<String> get streamNotifier => _messaging.streamNotifier;
  ValueNotifier<String> get reasoningStreamNotifier =>
      _messaging.reasoningStreamNotifier;
  ValueNotifier<bool> get isThinkingNotifier => _messaging.isThinkingNotifier;
  String get reasoningContent => _messaging.reasoningContent;
  @Deprecated(
      'Use messagingProvider.parsedOptions instead. Will be removed in a future release')
  List<String> get parsedOptions => _messaging.parsedOptions;
  @Deprecated(
      'Use messagingProvider.lastErrorType instead. Will be removed in a future release')
  String? get lastErrorType => _messaging.lastErrorType;
  @Deprecated(
      'Use messagingProvider.canRetry instead. Will be removed in a future release')
  bool get canRetry => _messaging.canRetry;

  int get sessionTokens => _messaging.sessionTokens;
  int get totalTokens => _messaging.totalTokens;
  @Deprecated(
      'Use messagingProvider.messageTokens instead. Will be removed in a future release')
  List<int> get messageTokens => _messaging.messageTokens;

  List<int> get searchResults => _messaging.searchResults;
  int get currentSearchIndex => _messaging.currentSearchIndex;
  String get searchQuery => _messaging.searchQuery;

  List<String> get bookmarkedMessageIds => _messaging.bookmarkedMessageIds;

  bool get multiCharacterMode => _messaging.multiCharacterMode;
  @Deprecated(
      'Use messagingProvider.characterQueue instead. Will be removed in a future release')
  List<String> get characterQueue => _messaging.characterQueue;
  int get currentCharacterRound => _messaging.currentCharacterRound;
  String? get currentCharacterSpeaker => _messaging.currentCharacterSpeaker;

  String get currentChapter => _currentChapter;

  void cancelStreaming() => _messaging.cancelStreaming();
  Future<void> sendMessage(String c) async {
    final content = c.trim();
    if (content.isEmpty) return;
    notifyListeners();
    triggerRebuild();
    await _messaging.sendMessage(content);
    notifyListeners();
    triggerRebuild();
  }

  Future<void> retryLast(
          {LLMProvider? overrideProvider, String? overrideModel}) =>
      _messaging.retryLast(
          overrideProvider: overrideProvider, overrideModel: overrideModel);
  void clearError() => _messaging.clearError();
  void removeLastIfError() => _messaging.removeLastIfError();
  Future<void> editMessage(int i, String c) => _messaging.editMessage(i, c);
  List<Map<String, String>> getFullPromptPreview() =>
      _messaging.getFullPromptPreview();

  @Deprecated(
      'Use messagingProvider.trackTokens instead. Will be removed in a future release')
  void trackTokens(int t) => _messaging.trackTokens(t);
  void resetSessionTokens() => _messaging.resetSessionTokens();
  Map<String, dynamic> getTokenSummary() => _messaging.getTokenSummary();

  void searchMessages(String q) =>
      _messaging.searchMessages(q, _adventure.messages);
  void clearSearch() => _messaging.clearSearch();

  void toggleBookmark(String id) => _messaging.toggleBookmark(id);

  @Deprecated(
      'Use messagingProvider.detectEmotion instead. Will be removed in a future release')
  String detectEmotion(String c) => _messaging.detectEmotion(c);

  void toggleMultiCharacterMode(bool v) => _messaging
      .toggleMultiCharacterMode(v, adventureConfig: _adventure.adventureConfig);
  @Deprecated(
      'Use messagingProvider.advanceCharacterRound instead. Will be removed in a future release')
  void advanceCharacterRound() => _messaging.advanceCharacterRound();
  @Deprecated(
      'Use messagingProvider.buildMultiCharacterPrompt instead. Will be removed in a future release')
  String buildMultiCharacterPrompt() => _messaging.buildMultiCharacterPrompt();

  void setChapter(String chapter) {
    _currentChapter = chapter;
    notifyListeners();
    triggerRebuild();
  }

  // ═══════════════════════════════════════════════════════════
  // Lifecycle
  // ═══════════════════════════════════════════════════════════

  @override
  void dispose() {
    _disposed = true;
    _settings.removeListener(notifyListeners);
    _adventure.removeListener(notifyListeners);
    _library.removeListener(notifyListeners);
    _messaging.removeListener(notifyListeners);
    _settings.removeListener(triggerRebuild);
    _adventure.removeListener(triggerRebuild);
    _library.removeListener(triggerRebuild);
    _messaging.removeListener(triggerRebuild);
    _settings.dispose();
    _adventure.dispose();
    _library.dispose();
    _messaging.dispose();
    rebuildVersion.dispose();
    tokenVersion.dispose();
    stateVersion.dispose();
    titleBarVersion.dispose();
    themeVersion.dispose();
    super.dispose();
  }
}
