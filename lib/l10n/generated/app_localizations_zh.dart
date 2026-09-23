// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'LT 灵境';

  @override
  String get pageLoadError => '页面加载出错';

  @override
  String get reloadAction => '重新加载';

  @override
  String get loadingEnvironment => '环境加载中...';

  @override
  String testingProviderConnection(String provider) {
    return '测试 $provider...';
  }

  @override
  String get modelConnectionFailed => '模型连接失败，请检查设置';

  @override
  String get apiKeyNotConfiguredPrompt => '尚未配置 API 密钥，可在设置中完成配置';

  @override
  String get goToSettings => '前往设置';

  @override
  String get createAdventureFailed => '创建场景失败，请稍后重试';

  @override
  String get navExplore => '探索';

  @override
  String get navLibrary => '资料库';

  @override
  String get navSettings => '设置';

  @override
  String get sidebarNewAdventure => '新建冒险';

  @override
  String get sidebarRecent => '最近';

  @override
  String get sidebarManageConversations => '批量管理历史对话';

  @override
  String get sidebarEmptyConversations => '暂无历史对话';

  @override
  String get sidebarUnnamedScene => '未命名场景';

  @override
  String get sidebarDeleteDialogTitle => '删除场景对话';

  @override
  String sidebarDeleteDialogMessage(String title) {
    return '确定删除「$title」吗？\n删除后历史对话与演变剧情将无法恢复。';
  }

  @override
  String get sidebarReturnHome => '返回探索大厅';

  @override
  String get sidebarExpand => '展开侧边栏';

  @override
  String get sidebarCollapse => '收起侧边栏';

  @override
  String get sidebarClose => '关闭侧边栏';

  @override
  String get brandSubtitle => '叙事与世界演变工坊';

  @override
  String get serviceConnected => '官方在服';

  @override
  String get serviceNotConfigured => '未配置密钥';

  @override
  String get officialOnline => '在服';

  @override
  String get languageSetupTitle => '选择语言';

  @override
  String get languageSetupSubtitle => '请选择应用显示语言';

  @override
  String get languageSettingTitle => '语言';

  @override
  String get languageSettingSubtitle => '应用显示语言';

  @override
  String get confirmAction => '确定';

  @override
  String get cancelAction => '取消';

  @override
  String get deleteAction => '删除';

  @override
  String get saveAction => '保存';

  @override
  String get continueAction => '继续';

  @override
  String get closeAction => '关闭';

  @override
  String get doneAction => '完成';

  @override
  String get editAction => '编辑';

  @override
  String get retryAction => '重试';

  @override
  String get copyAction => '复制';

  @override
  String get settingsCenter => '设置中心';

  @override
  String get settingsSystemConfig => '系统配置';

  @override
  String get settingsReturnHome => '返回大厅';

  @override
  String get settingsReturnList => '返回设置列表';

  @override
  String get settingsPreferencesCategory => '偏好分类';

  @override
  String get settingsCoreEngine => '灵境核心引擎';

  @override
  String get settingsStorageType => 'SQLite · 本地加密优先';

  @override
  String get tabModelApi => '模型与 API';

  @override
  String get tabModelApiSubtitle => '服务商与密钥配置';

  @override
  String get tabSessionParams => '会话参数';

  @override
  String get tabSessionParamsSubtitle => '采样率与深度思考';

  @override
  String get tabThemeAppearance => '主题配色';

  @override
  String get tabThemeAppearanceSubtitle => '深浅与主题色彩';

  @override
  String get tabDataManagement => '数据管理';

  @override
  String get tabDataManagementSubtitle => 'Token 统计与存储';

  @override
  String get configCategory => '配置分类';

  @override
  String get apiServiceConnected => '大模型服务已连接';

  @override
  String get apiServiceConnectedDesc => '点击管理服务商、模型与端点';

  @override
  String get apiServiceDisconnectedDesc => '点击配置 API 密钥以启动推演';

  @override
  String get providerConfigTitle => '模型提供商与 API 配置';

  @override
  String get providerConfigSubtitle => '配置大模型提供商、端点地址与安全密钥';

  @override
  String get testConnection => '测试连接';

  @override
  String get testingConnection => '正在测试...';

  @override
  String get inputApiKeyHint => '请先输入有效的 API 密钥';

  @override
  String connectionSuccess(int time) {
    return '连接成功！耗时 ${time}ms，服务状态极佳。';
  }

  @override
  String get connectionFailed => '连接失败，请核对密钥是否正确及网络是否通畅。';

  @override
  String connectionFailedWithReason(String error) {
    return '连接失败: $error';
  }

  @override
  String get apiKeyLabel => 'API 密钥 (API Key)';

  @override
  String get apiKeyPlaceholder => '请输入 API 密钥';

  @override
  String get customEndpointLabel => '自定义端点 (Base URL)';

  @override
  String get customEndpointPlaceholder => '自定义端点 URL';

  @override
  String get modelLabel => '模型名称';

  @override
  String get modelPlaceholder => '输入模型名称';

  @override
  String get customModelNote => '使用自定义模型端点';

  @override
  String get modelParamsSectionTitle => '会话模型参数';

  @override
  String get modelParamsSectionSubtitle => '精细调优内容生成采样温度、上下文预算与深度思考推理模式';

  @override
  String get systemPromptLabel => '自定义系统提示词';

  @override
  String get systemPromptPlaceholder => '输入系统提示词以指导 AI 扮演角色与行为风格...';

  @override
  String get authorsNoteLabel => '作者注释 (Author\'s Note)';

  @override
  String get authorsNotePlaceholder => '在最近回合中注入强效上下文提醒...';

  @override
  String authorsNoteDepthLabel(int depth) {
    return '插入深度：距底 $depth 回合';
  }

  @override
  String authorsNoteFrequencyLabel(int freq) {
    return '生效频率：每 $freq 回合触发一次';
  }

  @override
  String get dialogueLevelLabel => '文学修辞风格与深度';

  @override
  String temperatureLabel(String value) {
    return '采样温度 (发散度): $value';
  }

  @override
  String get enableThinkingLabel => '启用深度思考模式 (Deep Thinking)';

  @override
  String get enableThinkingSubtitle => '开启后模型在生成剧情前输出可折叠的思维链推演过程';

  @override
  String get reasoningEffortLabel => '思考强度 (Reasoning Effort)';

  @override
  String get quickModeLabel => '极速模式';

  @override
  String get quickModeSubtitle => '跳过打字机流式动画，快速呈现完整回复';

  @override
  String get appearanceSectionTitle => '外观与视觉主题';

  @override
  String get appearanceSectionSubtitle => '定制界面的色彩主题、深浅模式与阅读字号';

  @override
  String get themeModeLabel => '主题模式';

  @override
  String get themeLight => '明亮';

  @override
  String get themeDark => '暗黑';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get themeColorPalette => '主题色盘';

  @override
  String get themeColorPaletteHint => '点击即时换肤';

  @override
  String chatFontSizeLabel(int size) {
    return '叙事文本字号: $size pt';
  }

  @override
  String get chatFontCompact => '小巧精炼';

  @override
  String get chatFontStandard => '标准阅读';

  @override
  String get chatFontSpacious => '宽适大字';

  @override
  String get previewTypographyTitle => '阅读排版实时效果';

  @override
  String get previewTypographySample =>
      '「灵境叙事」—— 在浩瀚无垠的世界线交织中，你的每一个抉择都将掀起命运的波澜。暗流涌动的地下城、悬浮天际的机械遗迹，一切传奇皆自此启程。';

  @override
  String get readingScrollTitle => '阅读与滚动控制';

  @override
  String get readingScrollSubtitle => '控制文本生成与阅读时的屏幕滚动体验';

  @override
  String get autoScrollLabel => '生成时自动跟随滚动';

  @override
  String get autoScrollSubtitleOn => '开启状态：生成新内容时屏幕持续自动滚到底部最新字句。';

  @override
  String get autoScrollSubtitleOff =>
      '默认推荐（阅读优先）：生成新内容时屏幕保持平稳，方便您从开头不受打扰地读完；滑动完全受您控制。';

  @override
  String get dataManagementTitle => '数据管理与用量统计';

  @override
  String get dataManagementSubtitle => '查看 Token 消耗、语音 TTS 播报设置与存储管理';

  @override
  String get tokenUsageTitle => '本地 Token 消耗估算';

  @override
  String get sessionTokensLabel => '本次会话消耗';

  @override
  String get totalTokensLabel => '历史累计持久化';

  @override
  String get readAloudSectionTitle => '语音消息朗读 (TTS)';

  @override
  String get readAloudSupportedPlatform => '当前平台支持系统语音朗读，可在对话与创作工作台中使用。';

  @override
  String get readAloudUnsupportedPlatform => '当前平台不支持语音朗读。';

  @override
  String get readAloudEnable => '启用语音朗读';

  @override
  String get readAloudEnableSubtitle => '支持在对话、创作工作台与组装预览中朗读正文';

  @override
  String get readAloudAutoRead => '完成时自动朗读';

  @override
  String get readAloudAutoReadSubtitle => '当 AI 生成完完整剧情后自动进行语音播报';

  @override
  String get readAloudRate => '语速';

  @override
  String get readAloudPitch => '音调';

  @override
  String get readAloudVolume => '音量';

  @override
  String get readAloudLanguage => '朗读语言';

  @override
  String get readAloudAutoDetect => '自动检测';

  @override
  String get readAloudAutoDetectHint => '根据每段正文自动选择可用的系统语音语言。';

  @override
  String get readAloudFixedHint => '所有正文都使用所选语言朗读。';

  @override
  String get readAloudUnsupportedLanguage => '（不支持）';

  @override
  String readAloudAvailableLanguagesCount(int count) {
    return '系统可用语言：$count 种';
  }

  @override
  String get readAloudDisabledInSettings => '语音朗读已在设置中关闭';

  @override
  String get readAloudStop => '停止朗读';

  @override
  String get readAloudStart => '朗读';

  @override
  String get diagnosticExportTitle => '诊断数据导出';

  @override
  String get diagnosticExportSubtitle => '仅导出当前冒险分支最近 30 回合；API 凭证与隐藏推理不会写入文件。';

  @override
  String get exportDiagnosticJson => '导出诊断会话 JSON';

  @override
  String get cacheStorageTitle => '缓存与存储管理';

  @override
  String get clearCache => '清空临时缓存';

  @override
  String get clearCacheSuccess => '已清空会话临时缓存与重置计数器';

  @override
  String get clearAllData => '清空全部本地数据';

  @override
  String get clearDataDialogTitle => '重置所有本地数据';

  @override
  String get clearDataDialogMessage => '确定要清空所有本地冒险、卡片与缓存数据吗？\n此操作不可恢复。';

  @override
  String get exportChatTitle => '导出聊天';

  @override
  String get importChatTitle => '导入聊天';

  @override
  String get dashboardHeroTitle => '灵境 · 探索与叙事工坊';

  @override
  String get dashboardHeroSubtitle => '交互小说与沉浸式 RPG 叙事空间';

  @override
  String get dashboardWizardCardTitle => '四步向导定制';

  @override
  String get dashboardWizardCardDesc => '白板起步，自主设定世界观、角色卡、序章与初始行动。';

  @override
  String get dashboardWizardCardAction => '启动向导';

  @override
  String get dashboardPresetCardTitle => '预存场景工坊';

  @override
  String get dashboardPresetCardDesc => '浏览已构建的预设冒险剧本，支持一键启程或微调。';

  @override
  String get dashboardPresetCardAction => '查看预存场景';

  @override
  String get dashboardLibraryCardTitle => '资料库';

  @override
  String get dashboardLibraryCardDesc => '查阅与管理你构想的世界观预设、角色卡与 NPC 档案。';

  @override
  String get dashboardLibraryCardAction => '管理资料库';

  @override
  String get dashboardSettingsCardTitle => '系统设置中心';

  @override
  String get dashboardSettingsCardDesc => '配置大模型连接参数、外观主题与历史数据管理。';

  @override
  String get dashboardSettingsCardAction => '进入设置';

  @override
  String get recentAdventuresTitle => '最近冒险';

  @override
  String get noRecentAdventures => '暂无历史冒险，点击启动向导开启新的征途';

  @override
  String get continueAdventure => '继续冒险';

  @override
  String get featuredWorldviews => '精选世界观';

  @override
  String get featuredCharacters => '精选角色';

  @override
  String get resourceLibraryTitle => '资料库';

  @override
  String get resourceLibrarySubtitle => '浏览与管理你的世界观、角色卡与剧情模版';

  @override
  String get createResourceAction => '新建资源';

  @override
  String get searchResources => '搜索资源...';

  @override
  String get allResources => '全部';

  @override
  String get worldviewsTab => '世界观';

  @override
  String get charactersTab => '角色';

  @override
  String get templatesTab => '模版';

  @override
  String get recycleBinTitle => '回收站';

  @override
  String get emptyRecycleBin => '回收站是空的';

  @override
  String get restoreAction => '恢复';

  @override
  String get permanentlyDelete => '永久删除';

  @override
  String get resourceStudioTitle => '创作工作台';

  @override
  String get resourceStudioSubtitle => '多小节渐进式创作与容量管理';

  @override
  String get outlineTab => '大纲';

  @override
  String get capacityTab => '容量';

  @override
  String get historyTab => '版本';

  @override
  String get generatePart => '生成内容';

  @override
  String get regeneratePart => '重新生成';

  @override
  String get partSaved => '修改已保存';

  @override
  String get partSaving => '保存中...';

  @override
  String get assemblyWizardTitle => '场景装配与就绪检查';

  @override
  String get wizardWorldviewAiSummary =>
      '输入题材风格或核心构思，AI 可在此起草世界观，也可在资料库中创作完整的多模块世界。';

  @override
  String get adventureWizardTitle => '定制冒险向导';

  @override
  String get assemblyStepWorld => '1. 世界观';

  @override
  String get assemblyStepCharacters => '2. 角色设定';

  @override
  String get assemblyStepNpcs => '3. NPC 阵营';

  @override
  String get assemblyStepConfig => '4. 规则与序章';

  @override
  String get assemblyPreviewTitle => '装配预览';

  @override
  String get startAdventureAction => '开启冒险';

  @override
  String get readinessChecking => '检查资源就绪状态...';

  @override
  String get readinessPassed => '全部资源已就绪';

  @override
  String get readinessFailed => '资源需要装配就绪或压缩处理';

  @override
  String get adventureSessionTitle => '冒险进行中';

  @override
  String get inputActionHint => '你的下一步行动是？输入行动或对白...';

  @override
  String get sendAction => '发送';

  @override
  String get aiThinking => 'AI 正在思考...';

  @override
  String get aiWriting => 'AI 正在撰写...';

  @override
  String get diceCheckTitle => '骰点检定';

  @override
  String get turnSettling => '正在结算当前回合选项...';

  @override
  String get bookmarkAdded => '已添加书签';

  @override
  String get bookmarkRemoved => '已移除书签';

  @override
  String get messageCopied => '消息已复制到剪贴板';

  @override
  String get messageEdited => '消息已编辑';

  @override
  String get chatEditMessage => '编辑消息';

  @override
  String get chatReadAloudUnsupported => '当前平台不支持朗读';

  @override
  String get chatCopyReasoning => '复制思考过程（思维链）';

  @override
  String get chatReasoningCopied => '思维链已复制到剪贴板';

  @override
  String get chatRetryWithModel => '用其他模型重试';

  @override
  String get chatFork => '从此处分叉';

  @override
  String chatBranchCreated(Object branch) {
    return '已创建分支 $branch';
  }

  @override
  String get chatDeleteMessage => '删除';

  @override
  String get chatSearchHint => '搜索对话内容…';

  @override
  String get chatBookmarksOnly => '仅书签';

  @override
  String get chatMoreActions => '更多操作';

  @override
  String get chatEditStatus => '编辑状态';

  @override
  String get chatDeleteStatus => '删除状态';

  @override
  String get readAloudPause => '暂停';

  @override
  String get readAloudPauseRestart => '暂停（将从本段开头继续）';

  @override
  String get readAloudResume => '继续朗读';

  @override
  String get readAloudPreparing => '准备朗读';

  @override
  String get readAloudPrevious => '上一段';

  @override
  String get readAloudNext => '下一段';

  @override
  String get tokenCurrentScene => '本次场景 Token';

  @override
  String get tokenHistoryTotal => '累计 Token';

  @override
  String get tokenCurrentSceneDescription => '当前场景消耗 Tokens';

  @override
  String get tokenHistoryDescription => '本地记录历史累计 Tokens';

  @override
  String get readAloudPlatformSupportedMessage => '当前平台支持系统语音朗读，可在对话与创作工作台中使用。';

  @override
  String get diagnosticExportFailed => '诊断导出失败，请稍后重试。';

  @override
  String diagnosticExported(Object path) {
    return '诊断会话已导出：$path';
  }

  @override
  String get clearHistoryTitle => '清空历史对话记录';

  @override
  String get clearHistoryMessage =>
      '确定要清空所有过去的对话存档吗？\n世界观与角色卡资产将保留，但场景聊天历史将无法恢复。';

  @override
  String get clearHistoryConfirm => '确认清空';

  @override
  String get clearHistorySuccess => '已成功清理所有历史会话记录';

  @override
  String get readAloudRateLabel => '语速';

  @override
  String get readAloudPitchLabel => '音调';

  @override
  String get readAloudLanguageHintAuto => '根据每段正文自动选择可用的系统语音语言。';

  @override
  String get readAloudLanguageHintFixed => '所有正文都使用所选语言朗读。';

  @override
  String readAloudSupportedCount(Object count) {
    return '系统可用语言：$count 种';
  }

  @override
  String get generationWaiting => '等待生成内容…';

  @override
  String get errorTimeoutTitle => '请求超时';

  @override
  String get errorTimeoutSuggestion => '请检查网络连接后重试';

  @override
  String get errorAuthTitle => '认证失败';

  @override
  String get errorAuthSuggestion => '请检查 API Key 是否有效';

  @override
  String get errorRateTitle => '请求过于频繁';

  @override
  String get errorRateSuggestion => '请稍等片刻后重试';

  @override
  String get errorApiTitle => 'API 错误';

  @override
  String get errorApiSuggestion => '请检查 API 配置或稍后重试';

  @override
  String get errorNetworkTitle => '网络错误';

  @override
  String get errorNetworkSuggestion => '请检查网络连接和 API 设置后重试';

  @override
  String get switchModelRetry => '切换模型重试';

  @override
  String get resourceTrashTooltip => '回收站';

  @override
  String get resourceCreateShort => '新建';

  @override
  String get resourceNpcTab => 'NPC';

  @override
  String get resourceRetryLoad => '重试';

  @override
  String get resourceEmptyTitle => '还没有资源';

  @override
  String get resourceNoMatches => '没有找到匹配的资源';

  @override
  String get resourceNoSummary => '暂无简介';

  @override
  String get resourceMovedToTrash => '已移入回收站';

  @override
  String get refreshRecycleBin => '刷新回收站';

  @override
  String permanentDeleteMessage(Object title) {
    return '「$title」及其内容将被彻底删除，无法恢复。\n确定要继续吗？';
  }

  @override
  String get readinessBlockedTitle => '暂时无法开始冒险';

  @override
  String get acknowledgeAction => '知道了';

  @override
  String get staleResourceTitle => '资源已修改';

  @override
  String get staleResourceMessage => '以下资源在最近一次就绪后又发生了修改：';

  @override
  String get usePreviousReady => '是否使用上一个已就绪版本开始冒险？';

  @override
  String get chatImportFormat => '格式';

  @override
  String get chatImportLabel => '聊天内容';

  @override
  String get chatImportHint => '在此粘贴聊天内容...';

  @override
  String get chatImportSuccess => '导入成功';

  @override
  String get chatImportParsing => '解析中...';

  @override
  String get chatImportAction => '导入';

  @override
  String get chatImportEmpty => '请先粘贴聊天内容';

  @override
  String chatImportFailed(Object error) {
    return '导入失败：$error';
  }

  @override
  String get chatExportWarning => '导出内容可能包含对话和用户输入，请妥善保管。';

  @override
  String get chatSaveFailed => '保存失败';

  @override
  String chatSavedPath(Object path) {
    return '已保存：$path';
  }

  @override
  String get chatSaving => '保存中...';

  @override
  String get chatLoadFailedRetry => '加载失败，重试';

  @override
  String chatCharacterCount(Object count) {
    return '$count 字符';
  }

  @override
  String get resourceDetailTitle => '资源详情';

  @override
  String get resourceEnterStudio => '进入创作工作台';

  @override
  String get resourceLegacyNoStudio => '旧资源暂不支持高级创作';

  @override
  String get resourceActions => '资源操作';

  @override
  String get moveToTrashAction => '移入回收站';

  @override
  String moveToTrashMessage(Object name) {
    return '将「$name」移入回收站？之后可在回收站中恢复。';
  }

  @override
  String get moveToTrashFailed => '移入回收站失败，请重试';

  @override
  String get thinkingEngineTitle => '深度思考引擎';

  @override
  String get thinkingEngineBadge => 'V4.1 原生思考';

  @override
  String get thinkingEngineDescription =>
      '针对复杂多支线冒险与世界观逻辑推演，开启 DeepSeek V4.1 原生思维链的前置规划。';

  @override
  String get worldviewDeepThinkingLabel => '世界观深度推演生成';

  @override
  String get worldviewDeepThinkingSubtitle =>
      '世界观 AI 导入允许使用 V4.1 深度推演；默认关闭以降低首 Token 延迟';

  @override
  String get characterDeepThinkingLabel => '角色卡深度推演生成';

  @override
  String get characterDeepThinkingSubtitle =>
      '角色卡 AI 导入允许使用 V4.1 深度推演；默认关闭以优先快速生成';

  @override
  String get reasoningEffortLow => '轻度推演 · 极速响应';

  @override
  String get reasoningEffortMedium => '平衡推演 · 推荐日常';

  @override
  String get reasoningEffortHigh => '深度思考 · 丰富细节';

  @override
  String get reasoningEffortMax => '极致演算 · 严谨逻辑';

  @override
  String get restoreRecommended => '恢复默认推荐';

  @override
  String get recommendedDefaultsRestored => '已恢复官方推荐默认参数';

  @override
  String get revisionHistoryTitle => '历史记录';

  @override
  String revisionCount(Object count) {
    return '$count 条记录';
  }

  @override
  String get refreshRevisionHistory => '刷新版本历史';

  @override
  String get noRestorableRevisions => '还没有可恢复的历史记录';

  @override
  String get currentRevision => '当前';

  @override
  String get restoreRevision => '恢复此记录';

  @override
  String get presetParseError => '剧本数据解析失败或格式不完整';

  @override
  String get presetWorldviewTitle => '世界观设定';

  @override
  String get presetCharacterTitle => '主角档案';

  @override
  String get presetOpeningTitle => '开场序章';

  @override
  String get presetOptionsTitle => '初始行动分支';

  @override
  String get presetNpcTitle => '登场配角（NPC）';

  @override
  String get presetCustomizeAction => '向导载入微调';

  @override
  String get presetDetailsAction => '详情';

  @override
  String get sidebarEmptyConversationsSubtitle => '点击上方按钮开启新冒险';

  @override
  String get sidebarDeleteTooltip => '删除对话';

  @override
  String get sidebarSettingsNotConfigured => '系统设置（未配置密钥）';

  @override
  String get characterFallbackName => '角色A';

  @override
  String get monitoredStatus => '监测状态';

  @override
  String get expandAction => '展开 ▼';

  @override
  String get collapseAction => '收起 ▲';

  @override
  String statusItemsCount(int count) {
    return '$count项';
  }

  @override
  String optionsSectionTitle(int count) {
    return '选项 ($count 个选项)';
  }

  @override
  String get selectPrompt => '请选择';

  @override
  String get noOptionsAvailable => '暂无可选项';

  @override
  String get notSpecified => '不指定';

  @override
  String itemsSelectedCount(int count) {
    return '已选 $count 项';
  }

  @override
  String get backAction => '返回';

  @override
  String get showPassword => '显示明文';

  @override
  String get hidePassword => '隐藏明文';

  @override
  String get actionMenuTitle => '操作';

  @override
  String get actionMenuSemanticLabel => '操作菜单';

  @override
  String get menuTooltip => '菜单';

  @override
  String get switchLibrary => '切换资料库';

  @override
  String get customAttributesTitle => '自添加项';

  @override
  String get customAttributesSubtitle => '支持自主为角色/NPC扩展任意专属设定，可单独命名并设置推演重要程度';

  @override
  String get addCustomAttributeAction => '添加项';

  @override
  String get noCustomAttributes => '暂无自添加项（纯净白板）';

  @override
  String get customAttributesEmptyHint => '点击右上角「添加项」可自主定义专属武器、隐秘禁忌、弱点或特质';

  @override
  String get customAttributeNameLabel => '项名称 *';

  @override
  String get customAttributeNameHint => '如: 随身佩剑、致命弱点、施法习惯';

  @override
  String get deleteAttributeTooltip => '删除该项';

  @override
  String get customAttributeContentLabel => '项内容 / 设定描述';

  @override
  String get customAttributeContentHint => '描述该项具体效果、起源或限制（LLM 推演时将遵从对应重要程度）';

  @override
  String get customAttributeImportanceReference => '参考';

  @override
  String get customAttributeImportanceImportant => '重要参考';

  @override
  String get customAttributeImportanceVeryImportant => '很重要参考';

  @override
  String get customAttributeImportanceCritical => '不可忽略项';

  @override
  String get feedbackSuccess => '成功';

  @override
  String get feedbackError => '错误';

  @override
  String get feedbackWarning => '提醒';

  @override
  String get feedbackInfo => '提示';

  @override
  String get refreshFailed => '刷新失败，请稍后重试';

  @override
  String get noRefreshNeeded => '当前页面无需刷新';

  @override
  String get fontSizeDialogTitle => '字号调节';

  @override
  String get fontSizeSmall => 'A小';

  @override
  String get fontSizeLarge => 'A大';

  @override
  String get fontSizePreview => '预览: 中文 123\n字号大小示例';

  @override
  String get applyAction => '应用';

  @override
  String appliedPresetNotice(String preset) {
    return '已应用：$preset';
  }

  @override
  String get dialogueParamsTitle => '对话参数';

  @override
  String get paramsPresetLabel => '参数预设';

  @override
  String get customPreset => '自定义';

  @override
  String get frequencyPenalty => '频惩罚';

  @override
  String get presencePenalty => '存惩罚';

  @override
  String get saveWorldviewTitle => '保存世界观';

  @override
  String get worldviewInfoSection => '世界观信息';

  @override
  String worldviewSavedSuccess(String name) {
    return '已保存世界观「$name」';
  }

  @override
  String saveFailedPrefix(String error) {
    return '保存失败：$error';
  }

  @override
  String get importCardDialogTitle => '导入角色卡';

  @override
  String get pasteCardJsonHeader => '粘贴 SillyTavern / Chub 角色卡 JSON';

  @override
  String get pasteCardJsonHint => '在此粘贴角色卡 JSON 内容...';

  @override
  String get newDialoguePersonaTitle => '新建对话角色卡';

  @override
  String get editDialoguePersonaTitle => '编辑对话角色卡';

  @override
  String get dialoguePersonaSettingHeader => '对话角色设定';

  @override
  String get dialoguePersonaScopeNotice => '这里的角色只用于对话模式，可以完全不使用奈拉。';

  @override
  String get personaNameLabel => '角色名称 *';

  @override
  String get personaNameHint => '例如：奈拉、顾问、我的写作搭档';

  @override
  String get personaRoleLabel => '身份定位';

  @override
  String get personaRoleHint => '例如：通用 AI 助手、语言教练、世界观顾问';

  @override
  String get personaUserAddressLabel => '如何称呼用户';

  @override
  String get personaUserAddressHint => '例如：用户、创作者、指挥官、老师';

  @override
  String get personaPersonalityLabel => '性格与行为特点';

  @override
  String get personaPersonalityHint => '描述角色的性格、价值观和处理问题的方式';

  @override
  String get personaSpeakingStyleLabel => '说话方式';

  @override
  String get personaSpeakingStyleHint => '例如：简洁、温柔，必要时用步骤和示例解释';

  @override
  String get personaBackgroundLabel => '背景设定';

  @override
  String get personaBackgroundHint => '角色从哪里来，以及它了解什么';

  @override
  String get personaContextLabel => '对话情境';

  @override
  String get personaContextHint => '描述角色与用户通常在哪种情境下交流';

  @override
  String get personaDirectivesLabel => '额外行为指令';

  @override
  String get personaDirectivesHint => '可选：补充角色必须遵守的行为规则';

  @override
  String get deleteDialoguePersonaTitle => '删除对话角色卡？';

  @override
  String deleteDialoguePersonaMessage(String name) {
    return '确定要删除“$name”吗？';
  }

  @override
  String deleteCharacterCardFailed(String error) {
    return '删除角色卡失败: $error';
  }

  @override
  String get nameRequired => '请填写角色名称';

  @override
  String get manualCreatedSource => '手动创建';

  @override
  String get createAction => '创建';

  @override
  String get nameLabel => '名称';

  @override
  String get descriptionOptionalLabel => '描述（可选）';

  @override
  String get fontSizeAdjustment => '字号调节';

  @override
  String get fontSizeSmallA => 'A小';

  @override
  String get fontSizeLargeA => 'A大';

  @override
  String get dialogueParams => '对话参数';

  @override
  String get parameterPresets => '参数预设';

  @override
  String get presetDeepThinking => '深度思考 (V4.1 复杂推演)';

  @override
  String get presetFastNarrative => '极速叙事 (默认体验)';

  @override
  String get presetDeepReasoning => '极限推理 (长考解谜)';

  @override
  String get presetLightweightDaily => '轻量日常 (极速低延迟)';

  @override
  String appliedPreset(String preset) {
    return '已应用：$preset';
  }

  @override
  String get saveWorldview => '保存世界观';

  @override
  String get worldviewInfo => '世界观信息';

  @override
  String get name => '名称';

  @override
  String get descriptionOptional => '描述（可选）';

  @override
  String worldviewSaved(String name) {
    return '已保存世界观「$name」';
  }

  @override
  String saveFailed(String error) {
    return '保存失败：$error';
  }

  @override
  String get unknownError => '未知错误';

  @override
  String get importCharacterCard => '导入角色卡';

  @override
  String get pasteCharacterCardJson => '粘贴 SillyTavern / Chub 角色卡 JSON';

  @override
  String get pasteCharacterCardJsonHint => '在此粘贴角色卡 JSON 内容...';

  @override
  String get importAction => '导入';

  @override
  String get editDialoguePersonaCard => '编辑对话角色卡';

  @override
  String get newDialoguePersonaCard => '新建对话角色卡';

  @override
  String get dialoguePersonaSettings => '对话角色设定';

  @override
  String get dialoguePersonaSettingsDesc => '这里的角色只用于对话模式，可以完全不使用奈拉。';

  @override
  String get personaNameRequired => '角色名称 *';

  @override
  String get personaRole => '身份定位';

  @override
  String get personaUserCallName => '如何称呼用户';

  @override
  String get personaUserCallNameHint => '例如：用户、创作者、指挥官、老师';

  @override
  String get personaPersonality => '性格与行为特点';

  @override
  String get personaSpeakingStyle => '说话方式';

  @override
  String get personaBackground => '背景设定';

  @override
  String get personaScenario => '对话情境';

  @override
  String get personaScenarioHint => '描述角色与用户通常在哪种情境下交流';

  @override
  String get personaSystemPrompt => '额外行为指令';

  @override
  String get personaSystemPromptHint => '可选：补充角色必须遵守的行为规则';

  @override
  String deleteDialoguePersonaPrompt(String name) {
    return '确定要删除“$name”吗？';
  }

  @override
  String get pleaseEnterPersonaName => '请填写角色名称';

  @override
  String get manuallyCreated => '手动创建';

  @override
  String get sidebarSystemSettings => '系统设置';

  @override
  String get settingsTabModelAndApi => '模型与 API';

  @override
  String get settingsTabModelAndApiSubtitle => '服务商与密钥配置';

  @override
  String get settingsTabSessionParams => '会话参数';

  @override
  String get settingsTabSessionParamsSubtitle => '采样率与深度思考';

  @override
  String get settingsTabAppearance => '主题配色';

  @override
  String get settingsTabAppearanceSubtitle => '深浅与主题色彩';

  @override
  String get settingsTabStorage => '数据管理';

  @override
  String get settingsTabStorageSubtitle => 'Token 统计与存储';

  @override
  String get settingsCustomProvider => '自定义';

  @override
  String get settingsReturnToLobby => '返回大厅';

  @override
  String get settingsReturnToSettingsList => '返回设置列表';

  @override
  String get settingsConfigsCategory => '配置分类';

  @override
  String settingsOfficialInService(String provider) {
    return '$provider 官方在服';
  }

  @override
  String get settingsKeyNotConfigured => '未配置密钥';

  @override
  String get settingsLlmConnected => '大模型服务已连接';

  @override
  String get settingsLlmDisconnected => '未配置 API 密钥';

  @override
  String get settingsLlmConnectedSubtitle => '点击管理服务商、模型与端点';

  @override
  String get settingsLlmDisconnectedSubtitle => '点击配置 API 密钥以启动推演';

  @override
  String get settingsEngineTitle => '灵境核心引擎';

  @override
  String get settingsEngineSubtitle => 'SQLite · 本地加密优先';

  @override
  String get settingsSystemConfigBadge => '系统配置';

  @override
  String get inferenceParamsTitle => '推理超参与采样调节';

  @override
  String get inferenceParamsSubtitle => '调整温度、采样阈值与深度思考强度以平衡文采与逻辑一致性';

  @override
  String get deepseekThinkingHint =>
      '💡 提示：DeepSeek V4.1 思考模式下采样超参由模型自适应管理；非思考模式固定 top_p=1.0，仅温度可调。';

  @override
  String get temperatureTitle => '生成温度 (Temperature)';

  @override
  String get temperatureDescription => '0.0 绝对严谨精确 ↔ 2.0 天马行空丰富';

  @override
  String get topPTitle => '核采样概率 (Top-P)';

  @override
  String get topPDescription => '累积概率截断阈值，推荐保持 0.90 ~ 0.95';

  @override
  String get maxTokensTitle => '单次最大生成长度 (Max Tokens)';

  @override
  String get maxTokensDescription => '限制单回合对话的最大 Token 预算';

  @override
  String get paramsRealtimeNotice => '提示：参数变动实时生效，无需手动保存';

  @override
  String testConnectionSuccess(int elapsed) {
    return '连接成功！耗时 ${elapsed}ms，服务状态极佳。';
  }

  @override
  String get testConnectionFailure => '连接失败，请核对密钥是否正确及网络是否通畅。';

  @override
  String testConnectionFailureDetail(String error) {
    return '连接失败: $error';
  }

  @override
  String get statusReady => '已就绪';

  @override
  String get statusNotReady => '未就绪';

  @override
  String modelEndpointSummary(String model, String endpoint) {
    return '模型: $model · 端点: $endpoint';
  }

  @override
  String get quickTesting => '检测中';

  @override
  String get quickTest => '快速测通';

  @override
  String get llmProviderSectionTitle => 'LLM 服务提供商';

  @override
  String get llmProviderSectionSubtitle => '选择并配置场景对话与推理使用的核心语言模型服务';

  @override
  String get modelProviderLabel => '模型提供商';

  @override
  String get selectInServiceModal => '选择在服模型';

  @override
  String get customModelNameLabel => '自定义模型名称';

  @override
  String get customModelNameHint => '如 gpt-4o, llama-3.3-70b, qwen-max';

  @override
  String get apiEndpointLabel => 'API 服务端点 (Base URL)';

  @override
  String get apiSecurityNotice => '密钥加密存储于本地设备 SQLite 数据库，永远不会经由中间服务器转存';

  @override
  String get promptSettingsTitle => '提示词与推演编排';

  @override
  String get importPresets => '导入预设';

  @override
  String get exportPresets => '导出预设';

  @override
  String get previewPromptAction => '预览';

  @override
  String get importPresetTitle => '导入提示词预设';

  @override
  String get exportPresetTitle => '导出提示词预设';

  @override
  String get presetJsonLabel => '提示词预设 JSON';

  @override
  String get presetJsonEmptyError => '请输入预设 JSON';

  @override
  String presetImportFailed(String error) {
    return '导入失败：$error';
  }

  @override
  String get presetJsonCopied => '已复制预设 JSON';

  @override
  String get copyAllAction => '复制全部';

  @override
  String get dialogueLevelSectionTitle => '对话模式分级 (Dialogue Level)';

  @override
  String get dialogueLevelSectionSubtitle => '选择模型在单轮对话中的字数输出预算与描摹细节密度。';

  @override
  String get systemPromptSectionTitle => '全局系统提示词 (System Prompt)';

  @override
  String get systemPromptSectionSubtitle => '纯净初始状态。留空时系统将采用极简通用的推演规范。';

  @override
  String get systemPromptHint => '在此编写自定义系统设定、世界规则或角色推演守则（留空使用纯净默认规则）...';

  @override
  String charCountLabel(int count) {
    return '已写 $count 字符';
  }

  @override
  String get clearAction => '清空';

  @override
  String get systemPromptSaved => '全局系统提示词已保存';

  @override
  String get savePromptAction => '保存提示词';

  @override
  String get authorsNoteSectionTitle => '作者注释 (Author\'s Note)';

  @override
  String get authorsNoteSectionSubtitle => '在会话上下文中指定轮数深度注入高权重指示。';

  @override
  String get authorsNoteHint => '例如：聚焦于主角行动的细致刻画，保持环境氛围神秘悬疑...';

  @override
  String get injectionDepth => '注入深度';

  @override
  String get depthFollowSystem => '紧跟系统设定';

  @override
  String depthBeforeRound(int depth) {
    return '第 $depth 轮前';
  }

  @override
  String get injectionFrequency => '注入频率';

  @override
  String freqEveryRound(int freq) {
    return '每 $freq 轮';
  }

  @override
  String get authorsNoteSaved => '作者注释设置已保存';

  @override
  String get saveNoteConfigAction => '保存注释配置';

  @override
  String get promptPreviewTitle => '实时 Prompt 装配预览';

  @override
  String get copyFullPrompt => '复制完整 Prompt';

  @override
  String get fullPromptCopied => '已复制完整装配 Prompt 到剪贴板';

  @override
  String promptPreviewStats(int chars, int tokens) {
    return '共约 $chars 字符 · 预估 $tokens tokens';
  }

  @override
  String get resourceTypeWorldview => '世界观';

  @override
  String get resourceTypeCharacter => '角色';

  @override
  String get resourceTypeNpc => 'NPC';

  @override
  String get resourceStatusGenerating => '生成中';

  @override
  String get resourceStatusSaved => '已保存';

  @override
  String get resourceStatusOptimizationSuggested => '建议优化';

  @override
  String get resourceStatusOptimizing => '正在优化';

  @override
  String get resourceStatusReady => '已准备完成';

  @override
  String get resourceStatusOptimizationFailed => '优化失败';

  @override
  String get resourceUnknownTime => '未知时间';

  @override
  String get resourceCreateTitle => '新建资源';

  @override
  String get resourceTypeSectionTitle => '资源类型';

  @override
  String get resourceTypeSectionDescription => '选择所要构建的内容载体类型';

  @override
  String get resourcePreselectedType => '预选类型';

  @override
  String get resourceCreationMethodSectionTitle => '创建方式';

  @override
  String get resourceCreationMethodSectionDescription =>
      '根据创作需要选择由 AI 辅助推演或手动纯文本编写';

  @override
  String get resourceAiCreationTitle => 'AI 创建';

  @override
  String get resourceAiCreationDescription =>
      '基于参考资料、小说文本或现有资产，由 AI 自动推演章节大纲与正文内容。';

  @override
  String get resourceRecommendBadge => '推荐';

  @override
  String get resourceManualCreationTitle => '手动创建';

  @override
  String get resourceManualCreationDescription => '自定义名称与简介，建立空白资源后自由编排章节与内容。';

  @override
  String get resourceManualCreateTitle => '手动创建资源';

  @override
  String get resourceBasicInfoTitle => '基本信息';

  @override
  String get resourceManualBasicInfoDescription =>
      '填写资源的类型、名称与简要介绍，创建后即可在工作室中自由编排正文';

  @override
  String get resourceNameLabel => '名称';

  @override
  String get resourceManualNameHint => '输入清晰明确的名称';

  @override
  String get resourceSummaryOptionalLabel => '简介（可选）';

  @override
  String get resourceManualSummaryHint => '简要介绍该资源的定位与背景设定';

  @override
  String get resourceCreateAction => '创建';

  @override
  String get resourceInputNameError => '请输入资源名称';

  @override
  String get resourceAiCreateTitle => 'AI 智能创建资源';

  @override
  String get resourceAiBasicInfoDescription => '定义即将生成的资源载体类型与标题';

  @override
  String get resourceAiNameHint => '输入将要生成的设定或角色名称';

  @override
  String get resourceAssociateWorldviewTitle => '关联世界观（可选）';

  @override
  String get resourceAssociateWorldviewDescription =>
      '为角色或 NPC 指定其所属的原生世界观，作为生成时的补充上下文';

  @override
  String get resourceNoAvailableWorldview => '暂无可关联的世界观';

  @override
  String get resourceNotSpecified => '不指定';

  @override
  String get resourceReferenceSourceTitle => '参考资料来源';

  @override
  String get resourceReferenceSourceDescription =>
      '提供世界观背景、小说设定或关联资源，AI 将提取精髓并推演章节架构';

  @override
  String get resourceTabPaste => '粘贴';

  @override
  String get resourceTabFile => '文件';

  @override
  String get resourceTabExistingResource => '已有资源';

  @override
  String get resourcePasteReferenceLabel => '粘贴参考内容';

  @override
  String get resourcePasteReferenceHint => '输入或粘贴小说大纲、设定集草稿或背景描述...';

  @override
  String get resourceFileNameLabel => '文件名';

  @override
  String get resourceFileNameHint => '例如: world_notes.md';

  @override
  String get resourceFileContentLabel => '文件文本内容';

  @override
  String get resourceFileContentHint => '粘贴或输入文件内的原始文本...';

  @override
  String get resourceNoExistingInLibrary => '资料库中暂无可关联的已就绪资源，请切换至「粘贴」或「文件」输入。';

  @override
  String get resourceSelectExistingLabel => '选择已有资源';

  @override
  String get resourceSelectExistingHint => '点击选取参考的既有资源';

  @override
  String get resourceGenerationLengthTitle => '生成长度';

  @override
  String get resourceGenerationLengthDescription => '控制 AI 生成资源正文的大致目标字数';

  @override
  String get resourceTargetCharactersLabel => '目标字数';

  @override
  String resourceTargetCharactersValue(Object count) {
    return '$count 字';
  }

  @override
  String get resourceLengthShort => '短篇';

  @override
  String get resourceLengthLong => '长篇';

  @override
  String get resourceStartCreateAction => '开始创建';

  @override
  String get resourceInputOrPasteReferenceError => '请输入或粘贴参考资料正文';

  @override
  String get resourceInputFileNameError => '请输入文件名';

  @override
  String get resourceInputFileContentError => '请输入文件内容';

  @override
  String get resourceSelectExistingError => '请选择一个已有的资源作为参考';

  @override
  String get resourcePastedContentLabel => '粘贴内容';

  @override
  String get resourceLoadFailedRetry => '资源库加载失败，请重试';

  @override
  String get resourceCreationFailedRetry => '资源创建失败，请重试';

  @override
  String get resourceUnnamed => '未命名资源';

  @override
  String get resourceRevisionResourceKind => '资源';

  @override
  String get resourceRevisionSectionKind => '章节';

  @override
  String get resourceRevisionPartKind => '段落';

  @override
  String resourceTrashSubtitle(
      Object deletedAt, Object expiresAt, Object kind, Object reason) {
    return '$kind · $reason · 删除于 $deletedAt · 保留至 $expiresAt';
  }

  @override
  String resourceTrashRestoreFailed(Object error) {
    return '恢复失败：$error';
  }

  @override
  String get resourceTrashPermanentDeleteSuccess => '已永久删除';

  @override
  String resourceTrashPermanentDeleteFailed(Object error) {
    return '永久删除失败：$error';
  }

  @override
  String get modeTitleConversation => '对话资料库';

  @override
  String get modeTitleAdventure => '场景资料库';

  @override
  String get modeTitleCreation => '创作资料库';

  @override
  String get modeEmptyTitleConversation => '暂无对话角色卡';

  @override
  String get modeEmptyTitleAdventure => '暂无场景资料';

  @override
  String get modeEmptyTitleCreation => '暂无创作资料';

  @override
  String get modeEmptySubtitleConversation => '创建自定义角色卡，或查看过去的聊天记录。';

  @override
  String get modeEmptySubtitleAdventure => '导入角色、地点、规则或剧情资料，用于场景对话。';

  @override
  String get modeEmptySubtitleCreation => '导入世界观、角色设定、章节参考或写作资料，用于创作模式。';

  @override
  String get resourceStudioRefreshTooltip => '刷新';

  @override
  String get resourceStudioTocTitle => '目录';

  @override
  String get resourceStudioNoContent => '当前资源还没有可展示的内容。';

  @override
  String get resourceStudioReadAloudAll => '连续朗读全文';

  @override
  String get resourceStudioEditPart => '编辑正文';

  @override
  String get resourceStudioDeletePart => '删除段落';

  @override
  String get resourceStudioPartNotExistCannotEdit => '该段落已不存在，无法编辑';

  @override
  String get resourceStudioPublishCompressionTitle => '发布压缩结果';

  @override
  String get resourceStudioPublishCompressionMessage =>
      '压缩后的正文会替换当前内容，替换前的正文会记录为历史版本，可随时恢复。\n确定要发布吗？';

  @override
  String get resourceStudioPublishCompressionAction => '发布';

  @override
  String get resourceStudioRestoreRevisionTitle => '恢复历史版本';

  @override
  String get resourceStudioRestoreRevisionMessage =>
      '当前内容会被该历史版本替换，替换前的内容也会保留在版本历史中。\n确定要恢复吗？';

  @override
  String get resourceStudioRestoreRevisionAction => '恢复';

  @override
  String get resourceStudioDeletePartTitle => '删除段落';

  @override
  String resourceStudioDeletePartMessage(Object title) {
    return '「$title」会被移入回收站，可在「回收站」中恢复。\n确定要删除吗？';
  }

  @override
  String get resourceStudioDeletePartAction => '删除';

  @override
  String get resourceStudioPartNotExistCannotDelete => '该段落已不存在，无法删除';

  @override
  String get resourceStudioMovedToTrash => '已移入回收站，可在「回收站」中恢复';

  @override
  String resourceStudioDeletePartFailed(Object error) {
    return '删除段落失败：$error';
  }

  @override
  String get resourceStudioContinueGenerating => '继续生成';

  @override
  String get resourceStudioPauseGenerating => '暂停';

  @override
  String get resourceStudioCancelGenerating => '取消';

  @override
  String get resourceStudioRetryGenerating => '重试';

  @override
  String get resourceStudioCreatingAndStarting => '正在创建资源并启动生成';

  @override
  String resourceStudioTargetCharacters(Object count) {
    return '目标约 $count 字';
  }

  @override
  String get resourceStudioCreationFailed => '资源创建失败';

  @override
  String get resourceStudioPleaseRetryLater => '请稍后重试';

  @override
  String get resourceStudioRetryCreation => '重试创建';

  @override
  String get resourceStudioSelectResourceOrSession => '选择资源或生成会话';

  @override
  String get resourceStudioSelectSession => '选择生成会话';

  @override
  String get resourceStudioCreateAndStart => '创建并开始生成';

  @override
  String get resourceStudioPendingAiPlan => '待确认的 AI 规划';

  @override
  String get resourceStudioConfirmAndStart => '继续确认并开始生成';

  @override
  String resourceStudioUnfinishedTask(Object index) {
    return '未完成的生成任务 $index';
  }

  @override
  String get resourceStudioGeneratingStatus => '生成中';

  @override
  String get resourceStudioResourceLabel => '资源';

  @override
  String get resourceStudioNoResourceOrSession => '暂无资源或可恢复的生成会话。';

  @override
  String get resourceStudioAddSectionTitle => '新增章节';

  @override
  String get resourceStudioSectionTitleField => '章节标题';

  @override
  String get sectionControlsTitle => '章节控制';

  @override
  String sectionControlsCount(Object count) {
    return '$count 个章节';
  }

  @override
  String get sectionControlsAdd => '新增章节';

  @override
  String get sectionControlsEmpty => '该资源还没有章节。';

  @override
  String sectionControlsLoadMore(Object shown, Object total) {
    return '加载更多（已显示 $shown/$total）';
  }

  @override
  String get sectionControlsUnnamed => '（未命名章节）';

  @override
  String sectionControlsOrderIndex(Object index) {
    return '序号 $index';
  }

  @override
  String sectionControlsUpdated(Object time) {
    return '更新 $time';
  }

  @override
  String get sectionControlsValidate => '验证';

  @override
  String get sectionControlsMoreActions => '更多操作';

  @override
  String get sectionControlsRename => '重命名';

  @override
  String get sectionControlsMoveUp => '上移';

  @override
  String get sectionControlsMoveDown => '下移';

  @override
  String get sectionControlsDelete => '删除';

  @override
  String get sectionControlsDeleteTitle => '删除章节';

  @override
  String sectionControlsDeleteMessage(Object title) {
    return '确定删除「$title」及其所有内容吗？';
  }

  @override
  String get sectionControlsGenerate => '生成';

  @override
  String get sectionControlsRegenerate => '重新生成';

  @override
  String get sectionControlsNoTasksTooltip => '该章节没有生成任务（非 AI 蓝图创建），无法生成';

  @override
  String get sectionControlsRegenerateTooltip =>
      '重新运行该章节的生成任务；当前内容会先记录为历史版本，可随时恢复';

  @override
  String get sectionControlsRerunTooltip => '重新运行该章节的生成任务';

  @override
  String get sectionControlsRenameDialogTitle => '重命名章节';

  @override
  String get partEditorUnsavedDraftFound => '发现未保存的草稿';

  @override
  String get partEditorUnsavedDraftDesc => '上次编辑未写入正文。可以载入草稿继续编辑，或丢弃它。';

  @override
  String get partEditorLoadDraft => '载入草稿';

  @override
  String get partEditorDiscardDraft => '丢弃草稿';

  @override
  String get partEditorConflictDetected => '检测到内容冲突';

  @override
  String get partEditorConflictDesc =>
      '其他操作（如生成或恢复）修改了此段落。自动保存已暂停，你的文本仍保留在草稿中。请选择保留哪个版本：';

  @override
  String get partEditorUseMyText => '使用我的文本';

  @override
  String get partEditorDiscardMyText => '放弃我的文本';

  @override
  String get partEditorHint => '在这里编辑正文，停止输入后会自动保存';

  @override
  String get partEditorSaveNow => '立即保存';

  @override
  String get partEditorFinishEditing => '完成编辑';

  @override
  String get partEditorDraftLoaded => '已载入草稿，保存后写入正文';

  @override
  String get partEditorDraftDiscarded => '草稿已丢弃';

  @override
  String get partEditorEditing => '编辑中…';

  @override
  String get partEditorConflictOtherSaved => '保存冲突：其他操作修改了此段落，请选择保留哪个版本';

  @override
  String get partEditorConflictDraftRetained => '保存冲突：内容仍保留在草稿中，未覆盖较新的版本';

  @override
  String partEditorAutoSaved(Object label) {
    return '已自动保存 ($label)';
  }

  @override
  String get partEditorTargetPartMissing => '目标内容已不存在，草稿已丢弃';

  @override
  String get partEditorKeptMyTextAndSaved => '已保留我的文本并保存';

  @override
  String get partEditorConflictStillUnresolved => '冲突仍未解决：段落又被修改了一次，请重新选择';

  @override
  String partEditorResolveConflictFailed(Object error) {
    return '解决冲突失败：$error';
  }

  @override
  String partEditorSaving(Object label) {
    return '正在保存 ($label)…';
  }

  @override
  String get capacityPanelTitle => '容量';

  @override
  String capacityLatestFailureReason(Object reason) {
    return '最近一次压缩失败原因：$reason';
  }

  @override
  String get capacityRefresh => '刷新容量';

  @override
  String get capacityCompressing => '压缩中';

  @override
  String get capacityGenerateCandidates => '生成压缩候选';

  @override
  String capacityRetryFailedWithCount(Object count) {
    return '重试失败压缩（$count）';
  }

  @override
  String get capacityRetryFailed => '重试失败压缩';

  @override
  String capacityPublishWithCount(Object count) {
    return '发布压缩结果（$count）';
  }

  @override
  String get capacityPublish => '发布压缩结果';

  @override
  String get capacityOptimizationTip => '优化会先生成预览，确认后才会替换当前内容，原内容仍可恢复。';

  @override
  String get capacityPreparingState => '正在准备资源状态。';

  @override
  String capacityTextCharacters(Object count) {
    return '正文 $count 字';
  }

  @override
  String capacitySectionsCount(Object count) {
    return '章节 $count';
  }

  @override
  String capacityPartsCount(Object count) {
    return '内容块 $count';
  }

  @override
  String capacityRevisionsCount(Object count) {
    return '历史记录 $count';
  }

  @override
  String capacityArchivedSize(Object count) {
    return '已归档 $count 字';
  }

  @override
  String capacityQueuedJobs(Object count) {
    return '待优化 $count';
  }

  @override
  String capacityPotentialSavings(Object count) {
    return '采纳候选后约可减少 $count 字。';
  }

  @override
  String get capacityStatusNormal => '正常';

  @override
  String get capacityStatusElastic => '弹性';

  @override
  String get capacityStatusOverflow => '超出预算';

  @override
  String get outlinePartPending => '待生成';

  @override
  String get outlinePartGenerated => '已生成';

  @override
  String get operationFailedRetry => '操作失败，请重试';

  @override
  String get resourceImportReturnToEdit => '返回修改';

  @override
  String get resourceImportConfirmSave => '确认保存';

  @override
  String get characterCardEditTitle => '编辑角色卡';

  @override
  String get characterCardCreateTitle => '新建角色卡';

  @override
  String get characterCardConfirmDeleteTitle => '确认删除';

  @override
  String characterCardConfirmDeleteMessage(Object name) {
    return '确定要删除角色卡「$name」吗？';
  }

  @override
  String characterCardDeleteFailed(Object error) {
    return '删除角色卡失败: $error';
  }

  @override
  String get characterCardNameRequired => '请至少填写姓名';

  @override
  String characterCardSaveFailed(Object error) {
    return '保存失败：$error';
  }

  @override
  String get characterCardInfoSection => '角色卡信息';

  @override
  String get characterCardWorldviewOptional => '契合世界观（可选）';

  @override
  String get noneOption => '无';

  @override
  String get characterCardAiAssistedCreation => 'AI 智能辅助编写角色卡';

  @override
  String get detailedMode => '详细模式';

  @override
  String get conciseMode => '简约模式';

  @override
  String get simpleMode => '简洁模式';

  @override
  String characterCardTargetValidChars(Object count, Object max) {
    return '目标有效内容 $count 字（最多 $max 字）';
  }

  @override
  String get characterCardSavedInStudioTip => '生成将在资源工作室中持续保存，可恢复并可追踪修改记录';

  @override
  String get characterCardRelateCharacterOptional => '关联已有角色（可选）';

  @override
  String get characterCardRelateCharacterHint => '点击选择要建立关系的已有角色（留空为独立角色）';

  @override
  String get characterCardNoOtherCharacters => '暂无其他角色';

  @override
  String get characterCardIndependentRole => '不关联（作为独立新角色构思）';

  @override
  String characterCardRelatedCount(Object count) {
    return '已关联 $count 位角色';
  }

  @override
  String get characterCardUnnamed => '未命名角色';

  @override
  String get characterCardBondRelation => '羁绊关系：';

  @override
  String get relationCompanion => '同伴 / 队友';

  @override
  String get relationChildhoodFriend => '青梅竹马';

  @override
  String get relationLover => '恋人 / 命定伴侣';

  @override
  String get relationMentor => '师徒 (师承/弟子)';

  @override
  String get relationRival => '宿敌 / 竞争对手';

  @override
  String get relationKin => '家族亲人';

  @override
  String get relationBenefactor => '救命恩人 / 报恩';

  @override
  String get relationEmployment => '雇佣关系';

  @override
  String get relationCustom => '自定义关系...';

  @override
  String get relationCustomDescLabel => '自定义关系描述';

  @override
  String get relationCustomDescHint => '例如：指腹为婚的未婚妻、异界灵魂共生者...';

  @override
  String get characterCardCoreKeywordHint =>
      '输入角色核心词或设定要求（如：冷傲银发女剑圣、背叛教会的流浪学者），留空则自由发挥...';

  @override
  String get opening => '正在打开...';

  @override
  String get aiRegenerate => 'AI 重新生成';

  @override
  String get aiFillIn => 'AI 填入';

  @override
  String get genderLabel => '性别';

  @override
  String get genderMale => '男';

  @override
  String get genderFemale => '女';

  @override
  String get genderOther => '其他';

  @override
  String get ageLabel => '年龄';

  @override
  String get customGenderLabel => '自定义性别';

  @override
  String get occupationLabel => '职业/身份';

  @override
  String get personalityLabel => '性格';

  @override
  String get backgroundStoryLabel => '背景故事';

  @override
  String get appearanceLabel => '外貌描述';

  @override
  String get physiqueFeaturesLabel => '身材体态与生理特征';

  @override
  String get inWorldSettingSection => '世界内设定';

  @override
  String get factionLabel => '所属势力';

  @override
  String get locationLabel => '活动地点 / 家乡';

  @override
  String get publicGoalLabel => '公开目标';

  @override
  String get hiddenMotiveLabel => '隐藏动机（供叙事使用）';

  @override
  String get abilitySourceLabel => '能力来源';

  @override
  String get abilityCostLabel => '能力代价 / 限制';

  @override
  String get taboosLabel => '禁忌（用“、”分隔）';

  @override
  String get relationsNoteLabel => '关系网络备注';

  @override
  String get characterCardDetailTitle => '角色卡详情';

  @override
  String get characterPersonalityTraits => '性格特征';

  @override
  String get characterDescription => '角色描述';

  @override
  String get characterCustomFields => '自添加项';

  @override
  String get characterAiAssistantCreateTitle => 'AI 助手创作角色卡';

  @override
  String get characterCreateAction => '创建角色卡';

  @override
  String characterMatchWorldview(Object name) {
    return '契合：$name';
  }

  @override
  String get worldviewCreateTitle => '新建世界观';

  @override
  String get worldviewEditTitle => '编辑世界观';

  @override
  String get worldviewDetailedTitle => '详细世界观';

  @override
  String get worldviewConciseTitle => '简洁世界观';

  @override
  String get worldviewOverviewDetailed => '世界观概述（计入详细设定总字数）';

  @override
  String get worldviewOverviewConcise => '世界观描述 (200~500字)';

  @override
  String worldviewDetailedLimitTip(Object count) {
    return '详细设定（总字数上限 $count 字，已确认内容会进入场景对话）';
  }

  @override
  String worldviewConfirmDeleteMessage(Object name) {
    return '确定要删除世界观「$name」吗？';
  }

  @override
  String get worldviewDeleteFailed => '删除世界观失败，请重试';

  @override
  String get worldviewAiAssistantTitle => 'AI 助手创作世界观';

  @override
  String get worldviewCreateAction => '创建世界观';

  @override
  String get originalTextContent => '原文内容';

  @override
  String get worldviewAiImportTip =>
      '粘贴任意文字（txt / md / HTML / 小说片段），AI 将自动提取并整合为世界观';

  @override
  String get pasteOriginalTextHint => '在此粘贴原文内容...';

  @override
  String get importModeLabel => '导入模式';

  @override
  String get preparingDeduction => '正在准备推演…';

  @override
  String deductionProgressChars(Object current, Object partial, Object target) {
    return '当前有效字数 $current / $target\n$partial';
  }

  @override
  String deductionProgressStage(Object current, Object partial, Object total) {
    return '正在推演第 $current/$total 阶段：$partial';
  }

  @override
  String get autoSaveToLibrary => '自动保存到资料库';

  @override
  String get expectedTotalCharacters => '期望总字数';

  @override
  String get adaptiveStageHelperText => '自适应分阶段高并发推演全套9大模块，提速数倍并自动保存';

  @override
  String get aiAnalyzeAction => 'AI 解析';

  @override
  String get selectImportModeTitle => '选择导入模式';

  @override
  String get selectImportModeDesc => '请选择本次角色资料的整理粒度。该选择会直接传给 AI。';

  @override
  String get conciseModeDesc => '使用简洁模式：保留身份、性格、外貌、核心经历和必要关系，避免扩写。';

  @override
  String get detailedModeDesc => '使用详细模式：在原文事实范围内完整整理身份、性格、外貌、经历、动机、信息与人物关系。';

  @override
  String batchImportTitle(Object kind) {
    return '批量 AI 导入$kind';
  }

  @override
  String get provideCharacterDataTitle => '提供角色资料';

  @override
  String get batchAiRecognitionTip => 'AI 会先识别人名，经你确认后逐个生成角色。';

  @override
  String get pleaseSelectWorldviewFirst => '请先选择世界观';

  @override
  String get selectRelatedCharacters => '选择关联角色';

  @override
  String relatedCharactersCount(Object count) {
    return '已关联 $count 个角色';
  }

  @override
  String get minTotalCharactersLabel => '最少总字数';

  @override
  String get maxTotalCharactersLabel => '最多总字数';

  @override
  String characterDataLabel(Object label) {
    return '$label资料';
  }

  @override
  String characterDataHint(Object label) {
    return '粘贴包含多个$label的章节、设定或人物小传……';
  }

  @override
  String get planningAction => '正在规划…';

  @override
  String get enterAiStudioAction => '进入 AI Studio';

  @override
  String selectCandidatesToImportTitle(Object count) {
    return '选择导入角色（$count）';
  }

  @override
  String importSelectedCharactersAction(Object count) {
    return '导入 $count 个角色';
  }

  @override
  String get selectCandidatesMultiTitle => '选择对象（可多选）';

  @override
  String get candidatesRelationTip => '生成资料会依据原文和这些已有角色建立可验证的关系。';

  @override
  String confirmRelateCharactersAction(Object count) {
    return '确认关联 $count 个角色';
  }

  @override
  String get pasteCharacterRawTextHint => '在此粘贴角色或 NPC 原文……';

  @override
  String get stagedDeepGenerationTip => '分阶段深度生成，并自动补全至目标完整度';

  @override
  String get worldviewModuleRules => '规则与边界';

  @override
  String get worldviewModuleState => '当前世界现状';

  @override
  String get worldviewModuleLocations => '地点与地理';

  @override
  String get worldviewModuleFactions => '势力与组织';

  @override
  String get worldviewModuleCustoms => '风俗与生活';

  @override
  String get worldviewModuleTimeline => '历史与时间线';

  @override
  String get worldviewModuleGlossary => '术语表';

  @override
  String get worldviewModuleConstraints => '创作约束';

  @override
  String get notSpecifiedOption => '不指定';

  @override
  String get unnamedWorldview => '未命名世界观';

  @override
  String get noExistingCharacterCards => '暂无已有角色卡';

  @override
  String selectedCharactersCount(int count) {
    return '已选 $count 个角色';
  }

  @override
  String get generatingEllipsis => '正在生成…';

  @override
  String get aiImportCharacterTitle => 'AI 导入角色';

  @override
  String get aiImportNpcTitle => 'AI 导入 NPC';

  @override
  String get relateExistingCharactersTitle => '关联已有角色';

  @override
  String get sceneBatchImportCharacterTitle => '场景角色批量导入';

  @override
  String get sceneBatchImportNpcTitle => '场景 NPC 批量导入';

  @override
  String get belongingWorldviewOptional => '所属世界观（可选）';

  @override
  String get relateCharactersOptional => '关联角色（可选）';

  @override
  String get associateWorldviewOptional => '关联世界观（可选）';

  @override
  String get resourceStatusCancelled => '已取消';

  @override
  String get dashboardWizardBadge => '向导定制';

  @override
  String get dashboardPresetBadge => '完整剧本';

  @override
  String get dashboardLibraryBadge => '全景资产';

  @override
  String get dashboardSettingsBadge => '模型配置';

  @override
  String get dashboardMyCharacterCards => '我的角色卡档案';

  @override
  String get dashboardNoCharacterCardsTitle => '暂无角色卡档案';

  @override
  String get dashboardNoCharacterCardsDesc =>
      '当前未创建任何角色。你可以在资料库中塑造你的主角或同伴人设，并在冒险时选择他们出战。';

  @override
  String get dashboardGoToCharacterLibrary => '前往角色卡库';

  @override
  String get dashboardDefaultProfession => '探险者';

  @override
  String get dashboardNoBackgroundDesc => '暂无背景描述';

  @override
  String get dashboardStartWithCharacter => '以此角色启程';

  @override
  String get dashboardMyWorldSettings => '我的世界设定';

  @override
  String get dashboardNoCustomWorldsTitle => '暂无自定义世界';

  @override
  String get dashboardNoCustomWorldsDesc =>
      '当前处于纯净白板状态，无任何预设世界。你可以在资料库中构想专属世界，或使用向导直接开启探索。';

  @override
  String get dashboardGoToLibrary => '前往资料库';

  @override
  String get dashboardNoWorldDesc => '暂无设定描述';

  @override
  String get dashboardStartWithWorld => '以此世界启程';

  @override
  String get dashboardToggleSidebar => '切换导航栏';

  @override
  String get dashboardConfigureApiKey => '配置密钥';

  @override
  String get dashboardSystemSettings => '系统设置';

  @override
  String get dashboardNoAdventuresTitle => '尚未开始任何场景冒险';

  @override
  String get dashboardNoAdventuresDesc => '选择上方的「向导定制」开启属于你的首部传奇';

  @override
  String get dashboardContinueAdventures => '继续未尽的冒险';

  @override
  String get dashboardUnnamedAdventure => '未命名冒险';

  @override
  String get dashboardDeleteAdventureTooltip => '删除冒险记录';

  @override
  String dashboardSavedAt(Object time) {
    return '存档于 $time';
  }

  @override
  String get dashboardContinueExploring => '继续探索';

  @override
  String get dashboardDeleteAdventureTitle => '删除冒险记录';

  @override
  String dashboardDeleteAdventureMessage(Object title) {
    return '确定要删除场景「$title」及其全部对话记录吗？此操作无法撤销。';
  }

  @override
  String dashboardAdventureDeleted(Object title) {
    return '已删除场景「$title」';
  }

  @override
  String get characterNameLabel => '姓名';

  @override
  String get presetScenesTitle => '预存场景工坊';

  @override
  String get presetScenesSubtitle => '开箱即用的完整冒险场景设定 · 一键启程开局';

  @override
  String get returnToDashboard => '返回大厅';

  @override
  String presetScriptCount(int count) {
    return '$count 个剧本';
  }

  @override
  String get presetWizardNewScene => '向导新建场景';

  @override
  String get presetRefreshList => '刷新列表';

  @override
  String get presetSearchHint => '搜索场景剧本、世界观或主角...';

  @override
  String get presetStatusReady => '已就绪';

  @override
  String get presetStatusDraft => '草稿';

  @override
  String get presetDefaultSceneName => '预存场景';

  @override
  String get presetNoMatchingScenes => '没有找到符合条件的预存场景';

  @override
  String get presetNoScenes => '暂无预存场景剧本';

  @override
  String get presetNoMatchingScenesHint => '请尝试更换搜索关键字或重置筛选';

  @override
  String get presetNoScenesHint => '通过四步向导可以一键生成包含世界观、主角、序章与行动分支的完整剧本预设';

  @override
  String get presetStartWizardAction => '启动向导新建场景';

  @override
  String get presetScriptDetail => '剧本详情';

  @override
  String get presetUnnamedScene => '未命名场景';

  @override
  String presetWorldviewLabel(Object name) {
    return '世界观：$name';
  }

  @override
  String get presetPreviewFullSetting => '完整设定预览';

  @override
  String get presetLoadIntoWizard => '载入向导微调';

  @override
  String get presetDeleteAction => '删除预存场景';

  @override
  String get presetDeleteTitle => '删除预存场景';

  @override
  String presetDeleteMessage(Object name) {
    return '确定要删除预存场景「$name」吗？\n删除后此剧本预设将无法恢复。';
  }

  @override
  String presetDeletedSuccess(Object name) {
    return '已删除场景「$name」';
  }

  @override
  String presetDeleteFailed(Object error) {
    return '删除失败: $error';
  }

  @override
  String presetLoadFailed(Object error) {
    return '加载预存场景失败：$error';
  }

  @override
  String get presetStartFailed => '启动预设场景失败，请稍后重试';

  @override
  String presetProtagonistSummary(
      Object name, Object gender, Object profession) {
    return '主角：$name ($gender · $profession)';
  }

  @override
  String get presetNoPlotSummary => '暂无剧情描述摘要';

  @override
  String get presetDataSimplifying => '数据结构精简中';

  @override
  String get presetQuickStartAction => '一键启程';

  @override
  String get presetMenuSemantic => '场景操作菜单';

  @override
  String get worldSelectionTitle => '选择世界观设定';

  @override
  String get worldSelectionSubtitle => '从资料库已构想的世界中挑选本次冒险的世界法则与背景设定';

  @override
  String get worldSelectionSearchHint => '搜索世界观名称、地理风貌或设定规则...';

  @override
  String get worldSelectionNoDesc => '暂无详细背景描述';

  @override
  String get worldSelectionTag => '世界设定';

  @override
  String get worldSelectionEmptyTitle => '暂无保存的世界观';

  @override
  String get worldSelectionEmptyDesc => '可在资料库中创建或在向导中直接输入自定义世界观';

  @override
  String get characterSelectionTitle => '选择冒险角色';

  @override
  String get characterSelectionSubtitle => '从资料库角色档案中挑选主角与队伍同伴';

  @override
  String get characterSelectionSearchHint => '搜索角色姓名、职业、性格或背景...';

  @override
  String get characterCompatNative => '当前世界';

  @override
  String get characterCompatUnbound => '未绑定';

  @override
  String get characterCompatCrossWorld => '来自其他世界';

  @override
  String characterAgeYears(Object age) {
    return '$age岁';
  }

  @override
  String characterPersonalityPrefix(Object personality) {
    return '性格: $personality';
  }

  @override
  String get characterSelectionEmptyTitle => '暂无可用的角色档案';

  @override
  String get characterSelectionEmptyDesc => '可在资料库中创建新角色，或在向导中使用 AI 自动构思';

  @override
  String get npcSelectionTitle => '选择初始 NPC';

  @override
  String get npcSelectionSubtitle => '挑选本次冒险登场的常驻 NPC（资料将独立冻结至当前冒险快照）';

  @override
  String get npcSelectionSearchHint => '搜索 NPC 姓名、身份或简述...';

  @override
  String get npcSelectionEmptyTitle => '资料库暂无 NPC';

  @override
  String get npcSelectionEmptyDesc => '可在资料库中添加 NPC，或直接跳过此步骤';

  @override
  String get unnamedNpc => '未命名 NPC';

  @override
  String resourceSelectedCount(int count) {
    return '已选择 $count 项';
  }

  @override
  String get resourceNoneSelected => '未选择任何项';

  @override
  String get resourceOneSelected => '已选定 1 项';

  @override
  String get confirmSelection => '确认选择';

  @override
  String get finishSelection => '完成选定';

  @override
  String get loadingResources => '正在加载可用资源...';

  @override
  String noMatchingResourceForQuery(Object query) {
    return '未找到包含「$query」的资源';
  }

  @override
  String get clearSearch => '清空搜索';

  @override
  String get configureApiKeyFirstForAi => '请先配置 API Key 以使用 AI 自动生成功能';

  @override
  String get aiGenerationNoValidContent => '生成未返回有效内容，请检查网络或重试';

  @override
  String get aiOpeningGeneratedSuccess => 'AI 序章与初始行动分支已自动生成并填入！';

  @override
  String aiGenerationFailed(Object error) {
    return '生成失败：$error';
  }

  @override
  String get openingPromptLabel => '序章要求 / 引导提示词 (可选)';

  @override
  String get openingPromptHint => '例如：以雨夜码头的悬疑氛围开场，让主角先察觉到异样…';

  @override
  String get aiGenerateOpeningAndBranches => 'AI 生成序章与分支';

  @override
  String get aiOpeningGeneratingProgress => 'AI 正在结合世界观与角色设定构思序章与行动分支…';

  @override
  String assemblyWorldviewSubtitle(Object worldview) {
    return '世界: $worldview';
  }

  @override
  String assemblyProtagonistSubtitle(Object name) {
    return '主角: $name';
  }

  @override
  String get assemblyConfigPageTitle => '序章剧情与分支配置';

  @override
  String get saveConfigAndContinue => '保存配置并继续';

  @override
  String get openingFirstSceneTitle => '开场第一幕剧情';

  @override
  String get openingFirstSceneDesc => '设定玩家进入冒险后的第一幕情境描述、遭遇或开篇转折。';

  @override
  String get openingFirstSceneHint => '描述冒险启程时的时刻、环境与突发危机...';

  @override
  String get pleaseEnterOpeningScene => '请输入开场剧情设定';

  @override
  String get initialActionBranchesTitle => '初始行动抉择分支 (可选)';

  @override
  String get initialActionBranchesDesc => '供玩家在开局时做出的三个行动分支，若留空将在进入后由 AI 动态生成。';

  @override
  String get actionBranch1 => '抉择分支 1';

  @override
  String get actionBranch1Hint => '例如：拔剑迎击袭来的黑影';

  @override
  String get actionBranch2 => '抉择分支 2';

  @override
  String get actionBranch2Hint => '例如：寻找掩体并呼唤同伴掩护';

  @override
  String get actionBranch3 => '抉择分支 3';

  @override
  String get actionBranch3Hint => '例如：仔细观察四周环境寻找逃生通道';

  @override
  String get difficultyAndGuidanceTitle => '推演难度与自定义指引';

  @override
  String get difficultyAndGuidanceDesc => '控制游戏运行的难度倾向与自定义提示词。';

  @override
  String get narrativeDifficulty => '叙事难度';

  @override
  String get difficultyNormalDesc => '普通 (标准叙事与平衡挑战)';

  @override
  String get difficultyCasualDesc => '休闲 (注重剧情与轻松沉浸)';

  @override
  String get difficultyHardDesc => '困难 (严苛规则与硬核抉择)';

  @override
  String get customGuidancePromptOptional => '自定义引导提示词 (可选)';

  @override
  String get customGuidancePromptHint => '例如：侧重悬疑侦探氛围、多增加环境感官细节描摹...';

  @override
  String get worldviewBoundRules => '已绑定世界观规则与地理法则';

  @override
  String get defaultContinentRules => '使用默认大陆规则';

  @override
  String readinessReadError(Object error) {
    return '无法读取资源就绪状态：$error';
  }

  @override
  String readinessRetryError(Object error) {
    return '资源重新准备失败：$error';
  }

  @override
  String startAdventureFailed(Object error) {
    return '启动冒险失败：$error';
  }

  @override
  String get unnamedHero => '无名勇者';

  @override
  String get adventurerRole => '冒险者';

  @override
  String get assemblyPreviewSubtitle => '全面检查世界观、角色阵容、NPC 与序章推演设定';

  @override
  String get enterAdventureAction => '踏入冒险';

  @override
  String get readinessCheckingTitle => '正在检查资源装配状态';

  @override
  String get readinessUnconfirmedTitle => '无法确认资源装配状态';

  @override
  String get readinessReadyTitle => '冒险要素装配完毕';

  @override
  String get readinessNotReadyTitle => '仍有资源未完成装配';

  @override
  String get readinessCheckingDesc => '正在读取世界观与角色的可用版本。';

  @override
  String get readinessUnconfirmedDesc => '资源状态读取失败，为安全起见暂不能确认可启动。';

  @override
  String get readinessReadyDesc => '点击下方「踏入冒险」即可冻结快照并开启全新旅程。';

  @override
  String get readinessNotReadyDesc => '缺少可用版本时无法踏入冒险，请先完成资源组装准备。';

  @override
  String get readinessRetrying => '正在重新准备…';

  @override
  String get readinessRetry => '重新准备';

  @override
  String worldviewSettingLabel(Object name) {
    return '世界设定: $name';
  }

  @override
  String get worldviewSettingTitle => '世界设定';

  @override
  String get readAloudWorldview => '朗读世界设定';

  @override
  String protagonistLeadLabel(Object name, Object className) {
    return '主控主角: $name ($className)';
  }

  @override
  String get mainProtagonistTitle => '主控主角';

  @override
  String personalityFeatureLabel(Object personality) {
    return '性格特点: $personality';
  }

  @override
  String backgroundStoryPrefix(Object background) {
    return '背景身世: $background';
  }

  @override
  String accompanyingCharactersCount(int count) {
    return '同行角色 ($count 位):';
  }

  @override
  String characterBondsCount(int count) {
    return '羁绊关系 ($count 条):';
  }

  @override
  String residentNpcsCount(int count) {
    return '常驻 NPC ($count 位)';
  }

  @override
  String get openingSceneAndDecisionsTitle => '序章开场与行动决策';

  @override
  String get openingSceneTitle => '序章开场';

  @override
  String get readAloudOpeningScene => '朗读序章开场';

  @override
  String get aiDynamicOpeningPlaceholder => '（由 AI 结合世界观与角色背景动态构思开场剧情）';

  @override
  String get initialActionDecisionsTitle => '初始行动决策分支:';

  @override
  String get noMatchingResourceTitle => '暂无匹配资源';

  @override
  String get noMatchingResourceDesc => '尝试输入其他搜索词或清除筛选条件';

  @override
  String get searchResourceNameOrDesc => '搜索资源名称或描述...';

  @override
  String get aiOpeningPanelTitle => 'AI 自动编写序章';

  @override
  String get aiOpeningPanelDesc =>
      '填写你的序章要求，AI 会结合世界观、主角与同伴角色卡、角色羁绊与 NPC 生成序章正文和初始行动分支；生成结果仍可手动修改。';

  @override
  String get regenerate => '重新生成';

  @override
  String get assemblyPipelineTitle => '冒险装配流水线';

  @override
  String get assemblyPipelineSubtitle => '步骤推进 · 页面化资源组装 · 零弹窗约束';

  @override
  String get phaseWorldview => '世界设定';

  @override
  String get phaseCharacters => '角色阵容';

  @override
  String get phaseOpening => '序章分支';

  @override
  String get phasePreview => '装配总览';

  @override
  String nextPhaseLabel(Object phase) {
    return '下一步：$phase';
  }

  @override
  String get previousStepAction => '上一步';

  @override
  String get pleaseSetWorldviewName => '请设定世界观名称';

  @override
  String get pleaseAddAtLeastOneCharacter => '请至少添加一个角色';

  @override
  String worldviewSelectedSuccess(Object name) {
    return '已选定世界观「$name」';
  }

  @override
  String get rosterUpdatedSuccess => '已更新阵容角色';

  @override
  String npcsSelectedCountSuccess(int count) {
    return '已选定 $count 位 NPC';
  }

  @override
  String get openingConfigSavedSuccess => '序章配置已保存';

  @override
  String characterJoinedPartySuccess(Object name) {
    return '角色「$name」已加入队伍';
  }

  @override
  String get worldviewLibraryLinkTitle => '世界观资料库关联';

  @override
  String get selectFromLibrary => '从资料库选择';

  @override
  String boundLibraryWorldviewId(Object id) {
    return '已绑定资料库世界观 ID: $id';
  }

  @override
  String get notBoundPresetHint => '未绑定预设，亦可直接在下方填写自定义世界设定。';

  @override
  String get worldviewDetailsSectionTitle => '世界观设定详情';

  @override
  String get worldviewDetailsSectionDesc => '设定大陆法则、地理背景、文明程度与势力格局。';

  @override
  String get worldNameRequiredLabel => '世界名称 *';

  @override
  String get worldNameHint => '例如：艾尔登大陆、赛博新都 2099、修真古界...';

  @override
  String get pleaseEnterWorldName => '请输入世界名称';

  @override
  String get lawsAndBackgroundLabel => '法则与背景设定';

  @override
  String get lawsAndBackgroundHint => '描述世界的魔法与科技体系、天体气候、阵营势力格局...';

  @override
  String get charactersAndNpcAssemblyTitle => '角色与 NPC 装配';

  @override
  String get selectCharactersFromLibrary => '从资料库选择角色';

  @override
  String selectNpcCountLabel(int count) {
    return '选择 NPC ($count)';
  }

  @override
  String get newCharacterAction => '新建角色';

  @override
  String rosterSectionTitle(int count) {
    return '登场角色阵容 ($count)';
  }

  @override
  String get rosterSectionDesc => '必须勾选 1 位作为主控主角；其他角色可赋予同伴、反派、导师等身份定位。';

  @override
  String get noCharactersAddedYet => '尚未添加登场角色';

  @override
  String get clickAboveToAddCharactersHint => '点击上方「从资料库选择角色」或「新建角色」';

  @override
  String get setAsMainProtagonist => '设为主控主角';

  @override
  String get scriptRoleOrientation => '剧本身份定位';

  @override
  String get openingAndRulesAdvancedConfigTitle => '序章与规则高级配置';

  @override
  String get fullscreenAdvancedConfig => '全屏高级配置';

  @override
  String get openingSceneContentTitle => '序章剧情内容';

  @override
  String get openingSceneContentDesc => '冒险开始的第一幕场景描写。';

  @override
  String get openingSceneContentHint => '描述主角登场时刻的环境与转折...';

  @override
  String get openingBranchesDesc => '供玩家在序章结束时选择的行动方向。';

  @override
  String branchNumberLabel(Object number) {
    return '分支 $number';
  }

  @override
  String actionOptionHint(Object number) {
    return '行动选项 $number...';
  }

  @override
  String get enterStandaloneFullscreenPreview => '进入独立全屏大预览';

  @override
  String get fullscreenPreviewButton => '全屏预览';

  @override
  String get customUnnamedWorld => '自定义未命名世界';

  @override
  String get unspecifiedProtagonist => '未指定主角';

  @override
  String companionRosterSummary(Object roster) {
    return '同伴阵容: $roster';
  }

  @override
  String selectedInitialNpcCount(int count) {
    return '已选定 $count 位初始 NPC';
  }

  @override
  String get firstSceneOpeningPlotTitle => '序章第一幕';

  @override
  String get aiDynamicOpeningSummary => '由 AI 结合背景自动展开';

  @override
  String get wizardWorldviewQuickBadge => '快速构思与资料库创作';

  @override
  String get wizardWorldviewPromptLabel => '世界观创意要求 / 题材偏好（可选）';

  @override
  String get wizardWorldviewPromptHint =>
      '例如：蒸汽朋克浮空城与古神低语、克苏鲁异界修真、深海末日城邦；留空则由 AI 自由发挥……';

  @override
  String get generationModeLabel => '生成模式';

  @override
  String get clearSettingsAction => '清空设定';

  @override
  String get wizardGenerateWorldviewAction => '开始 AI 自动编写';

  @override
  String get wizardRegenerateWorldviewAction => '重新生成世界观';

  @override
  String get wizardWorldviewGeneratingBrief => '正在构思世界观…';

  @override
  String get wizardWorldviewGeneratingDetailed => '正在分阶段推演…';

  @override
  String get saveToLibraryNow => '立即保存到资料库';

  @override
  String get wizardReusableBadge => '可随时复用';

  @override
  String get wizardWorldviewSaveDescription => '将此设定自动保存到世界观资料库，方便未来冒险随时调用和扩展。';

  @override
  String charactersSavedCount(int count) {
    return '已将 $count 个角色设定保存至资料库';
  }

  @override
  String characterCardSavedSuccess(String name) {
    return '角色「$name」已保存至资料库';
  }

  @override
  String get fullscreenSelectionAction => '全屏选择';

  @override
  String wizardCharacterAiSummary(String worldview) {
    return '描述角色性格或定位偏好。AI 会结合当前世界观「$worldview」构思主角或队伍成员并加入阵容；资料库创作可提供更完整的设定。';
  }

  @override
  String get wizardCharacterPromptLabel => '角色创意要求 / 人设偏好（可选）';

  @override
  String get wizardCharacterPromptHint =>
      '例如：沉稳的退魔剑士、活泼的白发治愈法师、冷酷的机械游侠；留空则由 AI 自由发挥……';

  @override
  String get wizardGenerateMainCharacterAction => '开始 AI 自动生成主角';

  @override
  String get wizardAddCharacterToRosterAction => '使用 AI 增添阵容角色';

  @override
  String get currentWorldviewLabel => '当前世界';

  @override
  String get removeRosterCharacter => '从阵容移除';

  @override
  String get clearRelatedCharacters => '清空关联';

  @override
  String wizardRelatedCharactersSummary(int count, String names) {
    return '已关联 $count 位角色：$names';
  }

  @override
  String get wizardRelationAssociationSummary => '新角色会与所选角色建立故事羁绊。';

  @override
  String charactersAddedToRoster(int count) {
    return 'AI 创作的 $count 个角色已加入冒险队伍';
  }

  @override
  String get roleMaleLead => '男主';

  @override
  String get roleFemaleLead => '女主';

  @override
  String get roleMaleOne => '男一';

  @override
  String get roleFemaleOne => '女一';

  @override
  String get roleMaleTwo => '男二';

  @override
  String get roleFemaleTwo => '女二';

  @override
  String get roleSupporting => '重要配角';

  @override
  String get roleVillain => '反派';

  @override
  String get roleMentor => '导师';

  @override
  String get roleFamily => '亲友';

  @override
  String get relationFriend => '朋友';

  @override
  String get relationEnemy => '敌人';

  @override
  String get relationStranger => '陌生人';

  @override
  String get mainProtagonistDescription => '主控主角（掌控行动与关键抉择）';

  @override
  String get protagonistShortTag => '主角';

  @override
  String get relationshipNetworkDescription =>
      '标明角色之间的羁绊、阵营立场与过往恩怨，AI 推演时会遵循这些关系。';

  @override
  String relationAssetReference(String suggestion) {
    return '关联资料：$suggestion（本次冒险可另行设定）';
  }

  @override
  String get relationDetailsHint => '描述两人的关系渊源或羁绊线索（可选）。';

  @override
  String get relationshipNetworkTitle => '角色羁绊与关系网';

  @override
  String get adventureReadyToEnterTitle => '准备就绪，踏入世界';

  @override
  String get worldviewSnapshotBoundSummary => '已完整绑定资料库世界观快照与规则法则';

  @override
  String get characterCardSnapshotBoundSummary => '已完整绑定资料库角色卡档案';

  @override
  String get characterCustomDesignedSummary => '已定制主角设定';

  @override
  String get unnamedCharacterA => '角色 A';

  @override
  String get unnamedCharacterB => '角色 B';

  @override
  String get savePreviewAction => '保存预览';

  @override
  String get previewTemplateNoStartHint => '仅保存为可恢复的预览模板，不会启动冒险。';

  @override
  String adventurePreviewName(String worldview) {
    return '$worldview · 冒险预览';
  }

  @override
  String adventurePreviewSavedMessage(String name) {
    return '已保存预览「$name」，可在预存场景工坊中恢复';
  }

  @override
  String get adventurePreviewExistsMessage => '已存在相同的冒险预览';

  @override
  String adventurePreviewSaveFailed(String error) {
    return '保存预览失败：$error';
  }

  @override
  String get wizardCharacterSaveDescription => '自动将阵容角色设定保存到角色资料库，方便在未来的冒险中复用。';

  @override
  String wizardMalformedCharacterCards(int count) {
    return '有 $count 张角色卡无法加载。';
  }

  @override
  String get conversationDeleteTitle => '删除场景对话';

  @override
  String conversationDeleteConfirm(int count) {
    return '确定删除选中的 $count 段场景对话吗？删除后历史对话与演变剧情将无法恢复。';
  }

  @override
  String conversationDeleteInterrupted(String error) {
    return '删除中断，请检查剩余会话后重试：$error';
  }

  @override
  String get conversationManageTitle => '管理过去的对话';

  @override
  String selectedItemsCount(int count) {
    return '已选 $count 项';
  }

  @override
  String get deletingAction => '删除中…';

  @override
  String get batchDeleteAction => '批量删除';

  @override
  String get noManagedConversations => '暂无可管理的场景对话';

  @override
  String get selectAllAction => '全选';

  @override
  String get sceneConversationLabel => '场景对话';

  @override
  String get messageEditUserTitle => '编辑你的消息';

  @override
  String get messageEditAssistantTitle => '编辑 AI 回复';

  @override
  String get messageEditUserSubtitle => '修改后将从该消息开始重新生成后续剧情';

  @override
  String get messageEditAssistantSubtitle => '编辑此条剧情文本，便于调整叙事或纠正细节';

  @override
  String get messageEditUserWarning => '注意：保存后该消息之后的所有历史推进将自动清除并根据新输入重新构思。';

  @override
  String get messageBodyLabel => '消息正文';

  @override
  String get messageEditDescription => '支持长文本自由编辑，可任意换行与排版';

  @override
  String get messageContentHint => '输入消息内容…';

  @override
  String get saveAndRegenerateAction => '修改并重新生成';

  @override
  String get saveChangesAction => '保存修改';

  @override
  String get messageContentRequired => '消息内容不能为空';

  @override
  String get messageUnchanged => '内容未作修改';

  @override
  String get messageNoLongerCurrent => '消息已不在当前对话中，请返回刷新';

  @override
  String get messageSavedAndRegenerated => '已保存并重新生成';

  @override
  String get messageChangesSaved => '已保存修改';

  @override
  String get messageSaveRetry => '保存失败，请重试';

  @override
  String get inventoryTitle => '背包';

  @override
  String get inventoryItemsTitle => '物品';

  @override
  String get equipmentTitle => '装备';

  @override
  String get legacyInventoryTitle => '旧版背包记录';

  @override
  String inventorySummary(int itemCount, int equipmentCount) {
    return '物品 $itemCount 件，装备 $equipmentCount 件';
  }

  @override
  String get quickMenuTooltip => '快捷菜单';

  @override
  String get characterStatusTitle => '角色状态';

  @override
  String get wordCountSettings => '字数设置';

  @override
  String get backToLobby => '返回大厅';

  @override
  String get restartAdventureTitle => '确认重开冒险';

  @override
  String get restartAdventureMessage => '将重置当前会话与冒险进度并返回主页。';

  @override
  String get restartAdventureAction => '重开';

  @override
  String get stopGenerationAction => '停止生成';

  @override
  String get textAdventureTitle => '文字冒险';

  @override
  String get searchConversationAction => '搜索对话';

  @override
  String get historyAndSidebarAction => '历史场景与侧栏';

  @override
  String get moreOptionsAction => '更多选项';

  @override
  String get replyLengthSetting => '回复长度';

  @override
  String get switchModelAction => '切换模型';

  @override
  String get promptSettingsAction => '提示词设置';

  @override
  String get wordCountAndDensitySettings => '字数与对话密度设置';

  @override
  String get reasoningCopiedToast => '思维链已复制到剪贴板';

  @override
  String get editedBadge => '（已编辑）';

  @override
  String get deleteMessageConfirmation => '删除后无法恢复，确定要删除吗？';

  @override
  String get removeBookmarkAction => '取消书签';

  @override
  String get addBookmarkAction => '添加书签';

  @override
  String get editMessageAction => '修改';

  @override
  String get regenerateMessageAction => '重新生成';

  @override
  String get assistantReplyLabel => 'AI 回复';

  @override
  String get selectModelForRegeneration => '选择模型重新生成';

  @override
  String get selectLanguageModel => '选择语言模型';

  @override
  String currentModelSummary(String model, String provider) {
    return '当前：$model（$provider）';
  }

  @override
  String get selectedModelLabel => '已选模型';

  @override
  String get defaultModelPlaceholder => '未选定（使用默认）';

  @override
  String get confirmApplyAction => '确认应用';

  @override
  String get selectValidModelError => '请选择或输入有效的模型名称';

  @override
  String get messageNoLongerCurrentError => '消息已不在当前对话中，请返回刷新';

  @override
  String get regenerationUserMessageMissingError => '无法重新生成：未找到有效的用户消息';

  @override
  String get regenerationTargetMissingError => '无法重新生成：未找到对应的用户消息';

  @override
  String get modelRegenerationStarting => '正在重新生成…';

  @override
  String modelSwitchedSuccess(String model) {
    return '已切换至模型：$model';
  }

  @override
  String get modelSwitchFailed => '模型切换失败，请重试';

  @override
  String get serviceProviderSection => '服务提供商';

  @override
  String get serviceProviderDescription => '选择官方 API 服务商或本地/第三方兼容服务';

  @override
  String get llmProviderLabel => 'LLM 提供商';

  @override
  String get recentModelsSection => '最近使用';

  @override
  String get recentModelsDescription => '快速切换此前在此设备使用过的模型';

  @override
  String get recommendedModelsSection => '推荐在服模型';

  @override
  String get recommendedModelsDescription => '针对文学创作与角色扮演优化的核心在服模型';

  @override
  String get customModelSection => '自定义模型名称';

  @override
  String get deepseekCustomModelDescription => '如需调用 DeepSeek 其他专属模型，可在此手动输入';

  @override
  String get otherCustomModelDescription =>
      '输入第三方兼容端点支持的模型标识（例如 gpt-4o、claude-3-5-sonnet 等）';

  @override
  String get modelNamePlaceholder => '请输入模型名称…';

  @override
  String customModelSelected(String model) {
    return '已选定自定义模型：$model';
  }

  @override
  String get adventureBlankSlateTitle => '纯净冒险白板';

  @override
  String get adventureBlankSlateDescription =>
      '当前场景尚未产生任何对话或行动记录。\n在下方输入你的行动、提出一个探索方向，开始这段冒险。';

  @override
  String get beginAdventureAction => '启程行动';

  @override
  String get deepSeekFlashModelSubtitle =>
      'DeepSeek V4.1 Flash 最新推荐 · 多模态 · 支持深度思考';

  @override
  String get deepSeekLegacyModelSubtitle => '旧版模型，建议迁移到 DeepSeek V4.1 Flash';

  @override
  String get deleteDetectedStatusTitle => '删除检测状态';

  @override
  String confirmDeleteDetectedStatus(String name) {
    return '确定要删除「$name」该检测状态吗？';
  }

  @override
  String get statusNameLabel => '检测状态名称 *';

  @override
  String get statusNameExamples => '例如：理智值(SAN)、好感度、精神污染、饱食度';

  @override
  String get measurementModeLabel => '计量模式：';

  @override
  String get numericGaugeMode => '数值进度槽 (0~100)';

  @override
  String get phaseDescriptionMode => '阶段描述型';

  @override
  String get currentValueLabel => '当前数值';

  @override
  String get maxValueLabel => '最大上限';

  @override
  String get currentPhaseLabel => '当前阶段/描述';

  @override
  String get currentPhaseExamples => '例如：正常、轻度侵蚀、微醺、狂化中';

  @override
  String get chooseStatusIcon => '选择状态图标：';

  @override
  String get statusRuleLabel => '检测规则 / 剧情判定说明 (可选)';

  @override
  String get statusRuleHint => '例如：低于20时陷入恐慌；投骰成功保持理智，失败触发疯狂幻觉';

  @override
  String get storyImportanceLabel => '剧情重要度：';

  @override
  String get statusNameRequiredError => '请输入检测状态名称';

  @override
  String get addDetectedStatusAction => '添加检测状态';

  @override
  String detectedStatusesCount(int count) {
    return '自定义检测状态 ($count)';
  }

  @override
  String get combatAdventureMatrix => '战斗与探险能力矩阵';

  @override
  String get physicalAttackStat => '物理攻击 (ATK)';

  @override
  String get baseDefenseStat => '基础防御 (DEF)';

  @override
  String get agilitySpeedStat => '机敏速度 (SPD)';

  @override
  String get goldStat => '持有金币 (Gold)';

  @override
  String get availableSkillPointsStat => '可用技能点';

  @override
  String get currentSceneCoordinatesStat => '当前场景坐标';

  @override
  String get openInventoryAction => '打开背包仓库';

  @override
  String get profileIdentityTitle => '📜 身份与职业定位';

  @override
  String get profileBackgroundTitle => '📖 背景经历与渊源';

  @override
  String get profileWorldviewTitle => '🌍 所处世界观';

  @override
  String get profilePersonalityTitle => '🎭 性格特质';

  @override
  String get profileRelationshipsTitle => '🤝 羁绊与关系';

  @override
  String get profileAppearanceTitle => '✨ 外貌与体态特征';

  @override
  String get checkAction => '检定';

  @override
  String levelRoleSummary(int level, String role) {
    return 'Lv.$level · $role';
  }

  @override
  String get editDetectedStatusTitle => '编辑检测状态';

  @override
  String get noCustomDetectedStatuses => '暂无自定义检测状态';

  @override
  String get detectedStatusesEmptyDescription =>
      '支持自定义理智值(SAN)、好感度、精神污染、饱食度、魔力过载等任意冒险状态。';

  @override
  String get energyLabel => '能量';

  @override
  String get combatStatsTitle => '战斗属性';

  @override
  String get currentValuePrefix => '当前值：';

  @override
  String get currentPhaseWithThoughtsLabel => '当前状态阶段 / 心里想法';

  @override
  String get phaseNotTriggered => '（尚未触发阶段判定）';

  @override
  String statusRulePrefix(String rule) {
    return '📌 规则判定：$rule';
  }

  @override
  String get companionsTab => '核心状态';

  @override
  String get equipmentTab => '装备随身';

  @override
  String get profileTab => '身世羁绊';

  @override
  String currentExplorationRegion(String scene) {
    return '当前探索区域：$scene';
  }

  @override
  String mainStoryChapter(int chapter) {
    return '主线冒险者 · 第 $chapter 篇章';
  }

  @override
  String relationshipLabel(String relation) {
    return '关系：$relation';
  }

  @override
  String affinityScoreLabel(int affinity) {
    return '❤️ 好感度：$affinity';
  }

  @override
  String get healthPointsLabel => '生命值 (HP)';

  @override
  String get lifeForceLabel => '生命活力';

  @override
  String get magicPointsLabel => '精神魔法 (MP)';

  @override
  String get focusLabel => '专注力';

  @override
  String get actionEnergyLabel => '行动能量 (Energy)';

  @override
  String get tiredStatus => '⚠️ 疲惫';

  @override
  String get goodStatus => '良好';

  @override
  String get experienceLabel => '升级经验 (EXP)';

  @override
  String nextLevelExperience(int count) {
    return '下一级需 $count';
  }

  @override
  String skillPointsValue(int count) {
    return '$count 点';
  }

  @override
  String equippedGearCount(int count) {
    return '⚔️ 当前穿戴装备 ($count)';
  }

  @override
  String get noEquippedGear => '暂未穿戴专属装备，可在背包或商店中获取装备提升战力。';

  @override
  String gearSlotQuality(String slot, String quality) {
    return '部位：$slot · 品质：$quality';
  }

  @override
  String get carriedItemsTitle => '🎒 随身物品与材料';

  @override
  String get noCarriedItems => '当前随身行囊无特殊物品。';

  @override
  String get sharedPartyInventory => '📦 公共队伍行囊：';

  @override
  String get detectedStatusFormDescription =>
      '自定义在冒险故事中持续检测与判定的状态（支持进度槽、判定规则与投骰检定）';

  @override
  String get statusPresetsHeading => '💡 快捷预设灵感（点击一键填入）：';

  @override
  String get explorerRole => '探险者';

  @override
  String get startingTown => '起点城镇';

  @override
  String get defaultProtagonistProfile => '独自探索未知边界的冒险者，具备机变行动与剧情决策权。';

  @override
  String get defaultProtagonistBackground => '在风起云涌的世界中踏上征程，经历未知的命运齿轮推演。';

  @override
  String get defaultWorldviewDescription => '沉浸式角色扮演叙事空间，随剧情发展实时推演环境演变。';

  @override
  String get defaultCompanionPersonality => '性格深沉，在历险旅程中逐步展现内心真正的渴望。';

  @override
  String genderTag(String value) {
    return '性别：$value';
  }

  @override
  String heightTag(String value) {
    return '身高：$value';
  }

  @override
  String hairstyleTag(String value) {
    return '发型：$value';
  }

  @override
  String skinToneTag(String value) {
    return '肤色：$value';
  }

  @override
  String facialFeaturesTag(String value) {
    return '面部：$value';
  }

  @override
  String get aliveStatus => '💚 状态正常';

  @override
  String get incapacitatedStatus => '💀 失去行动力';

  @override
  String companionRelationshipSummary(String relation, int affinity) {
    return '与主角设定为【$relation】关系。当前好感度评分：$affinity/100。';
  }

  @override
  String get diceCriticalSuccess => '大成功！判定完美达成！';

  @override
  String get diceCriticalFailure => '大失败！遭遇严重失误或异常反噬！';

  @override
  String get diceSuccess => '检定成功！成功抵抗异常并维持状态稳定。';

  @override
  String get diceFailure => '检定失败！受到状态影响或负面效果侵扰。';

  @override
  String get diceCheckCriticalSuccess => '大成功 (暴击)！极限突破达成！';

  @override
  String get diceCheckCriticalFailure => '大失败！判定彻底失败！';

  @override
  String get diceCheckPassed => '检定通过！状态运转顺利。';

  @override
  String get diceCheckFailed => '检定未通过！受到阻碍或负面波及。';

  @override
  String diceTargetValue(int current, int maximum) {
    return '检定目标值：$current / $maximum';
  }

  @override
  String diceCurrentStatus(String status) {
    return '当前状态：$status';
  }

  @override
  String diceRuleDescription(String rule) {
    return '判定规则：$rule';
  }

  @override
  String get d100PercentileDie => 'D100 百分比骰';

  @override
  String get d20Die => 'D20 骰';

  @override
  String get rollCheckAction => '投掷检定骰';

  @override
  String get rerollAction => '重新投掷';

  @override
  String get syncResultToAdventure => '同步至冒险剧情';

  @override
  String diceResultPoints(String icon, int value, String denominator) {
    return '$icon 掷出点数：$value $denominator';
  }

  @override
  String get diceResultWillBeSent => '检定结果将作为一条用户消息发送。';

  @override
  String diceResultMessage(String status, String rule, String character,
      int roll, String target, String verdict) {
    return '【状态检测】$character 进行了「$status」检定：🎲 掷出 $roll ($target) → 【$verdict】！$rule';
  }

  @override
  String get allItemsFilter => '全部';

  @override
  String get consumableItemType => '消耗品';

  @override
  String get equipmentItemType => '装备物品';

  @override
  String get materialItemType => '材料';

  @override
  String get questItemType => '任务物品';

  @override
  String get weaponSlot => '武器';

  @override
  String get armorSlot => '护甲';

  @override
  String get accessorySlot => '饰品';

  @override
  String get specialSlot => '特殊';

  @override
  String get commonQuality => '普通';

  @override
  String get uncommonQuality => '优秀';

  @override
  String get rareQuality => '稀有';

  @override
  String get epicQuality => '史诗';

  @override
  String get legendaryQuality => '传说';

  @override
  String get emptyInventoryTitle => '背包是空的';

  @override
  String get emptyInventoryDescription => '剧情中获得的物品会显示在这里。';

  @override
  String get deepThinkingStatus => '正在深度思考…';

  @override
  String get reasoningExpandedLabel => '思考过程 (点击收起)';

  @override
  String get reasoningCollapsedLabel => '已深度思考 (点击展开思维链)';

  @override
  String get thinkingInProgressStatus => '正在思考中…';

  @override
  String get reasoningUnavailableLabel => '（无记录）';

  @override
  String get copyReasoningAction => '复制思考过程';

  @override
  String get writingStoryStatus => '正在撰写剧情…';

  @override
  String get dialogueReplyLengthSettingsTitle => '调整场景对话回复长度';

  @override
  String dialogueCurrentSelection(String id, String name, String range) {
    return '当前选择：$id · $name ($range)';
  }

  @override
  String dialogueWordsAbove(int minWords) {
    return '$minWords 字以上';
  }

  @override
  String get dialogueLevelFast => '极速';

  @override
  String get dialogueLevelConcise => '简洁';

  @override
  String get dialogueLevelStandard => '标准';

  @override
  String get dialogueLevelDetailed => '详细';

  @override
  String get dialogueLevelDeep => '深度';

  @override
  String get dialogueLevelProduction => '生产';

  @override
  String get dialogueLevelFastDesc => '只保留关键反馈，适合快速确认。';

  @override
  String get dialogueLevelConciseDesc => '简短推进，适合轻量互动。';

  @override
  String get dialogueLevelStandardDesc => '默认模式，兼顾速度和沉浸感。';

  @override
  String get dialogueLevelDetailedDesc => '提供更完整的描写和互动。';

  @override
  String get dialogueLevelDeepDesc => '强调铺垫、心理和场景层次。';

  @override
  String get dialogueLevelProductionDesc => '长文本生成，适合严肃写作。';

  @override
  String get adventureRefreshUnavailable => '生成中或场景不可用，暂不能刷新';

  @override
  String get sessionOfflineHint => '离线 — 网络连接不可用';

  @override
  String get sessionInputHint => '描述你的行动或对话…';

  @override
  String get messageGestureHint => '右滑消息可重试 · 左滑可删除 · 长按可编辑或收藏';

  @override
  String get adventureAssistantName => '冒险助手';

  @override
  String get currentUserDisplayName => '我';

  @override
  String get unknownRegion => '未知地域';

  @override
  String get deepThinkingBadge => '深度思考';

  @override
  String get supportingCharacterRole => '配角';

  @override
  String get autoSwitchCharacterTooltip => '自动切换角色';

  @override
  String get sessionSettlingStatus => '正在生成选项与结算状态…';

  @override
  String get aiReplyLabel => 'AI 回复';

  @override
  String sectionValidationPassed(String title) {
    return '「$title」校验通过';
  }

  @override
  String sectionValidationFailed(String title, int count) {
    return '「$title」校验未通过：$count 项问题';
  }

  @override
  String get sectionValidationComplete => '校验完成';

  @override
  String sectionRegenerated(String title, int completed, int total) {
    return '「$title」已重新生成 $completed/$total 个段落';
  }

  @override
  String sectionRegenerationFailed(String title, String error) {
    return '「$title」生成中止：$error';
  }

  @override
  String get sectionGenerationComplete => '生成完成';

  @override
  String get capacityNoCompressionNeeded => '没有需要压缩的章节。';

  @override
  String get capacityCompressionAlreadyPublished => '该压缩候选已发布，未重复改动正文。';

  @override
  String capacityCompressionPublished(int savedCharacters) {
    return '已发布压缩候选，约节省 $savedCharacters 字；压缩前的正文保留在历史版本中。';
  }

  @override
  String capacityRetryBlockedByActiveTarget(int count) {
    return '$count 个失败任务的目标已有进行中的压缩，因此已跳过。';
  }

  @override
  String capacityRetryBudgetExhausted(int count) {
    return '没有可重试的压缩任务；$count 个任务已达到重试上限。';
  }

  @override
  String get capacityRetryUnavailable => '没有可重试的压缩任务。';

  @override
  String capacityCompressionRunSummary(int succeeded, int failed, int requeued,
      int activeSkipped, int exhaustedSkipped) {
    return '生成候选 $succeeded 个；失败任务 $failed 个；重试入队 $requeued 个；因目标已有压缩而跳过 $activeSkipped 个；达到重试上限而跳过 $exhaustedSkipped 个。候选需确认后才会替换正文；失败任务不会修改原文。';
  }

  @override
  String get revisionCauseManualSave => '手动保存';

  @override
  String get revisionCauseGeneration => 'AI 生成';

  @override
  String get revisionCausePlanning => '大纲规划';

  @override
  String get revisionCauseRegeneration => '重新生成';

  @override
  String get revisionCauseCompression => '语义压缩';

  @override
  String get revisionCauseRestore => '版本恢复';

  @override
  String get revisionCauseMigration => '数据迁移';

  @override
  String get revisionCauseDeletion => '删除前快照';

  @override
  String get revisionUnknownDate => '日期未知';

  @override
  String get revisionAlreadyCurrent => '当前内容已经是该版本。';

  @override
  String revisionRestored(String sourceCause) {
    return '已恢复到「$sourceCause」版本。';
  }

  @override
  String revisionItemSubtitle(String date, int nodeCount, int charCount) {
    return '$date · $nodeCount 个节点 · $charCount 字';
  }

  @override
  String resourceRevisionOperationFailed(String error) {
    return '版本操作失败：$error';
  }
}

/// The translations for Chinese, using the Han script (`zh_Hans`).
class AppLocalizationsZhHans extends AppLocalizationsZh {
  AppLocalizationsZhHans() : super('zh_Hans');

  @override
  String get appTitle => 'LT 灵境';

  @override
  String get pageLoadError => '页面加载出错';

  @override
  String get reloadAction => '重新加载';

  @override
  String get loadingEnvironment => '环境加载中...';

  @override
  String testingProviderConnection(String provider) {
    return '测试 $provider...';
  }

  @override
  String get modelConnectionFailed => '模型连接失败，请检查设置';

  @override
  String get apiKeyNotConfiguredPrompt => '尚未配置 API 密钥，可在设置中完成配置';

  @override
  String get goToSettings => '前往设置';

  @override
  String get createAdventureFailed => '创建场景失败，请稍后重试';

  @override
  String get navExplore => '探索';

  @override
  String get navLibrary => '资料库';

  @override
  String get navSettings => '设置';

  @override
  String get sidebarNewAdventure => '新建冒险';

  @override
  String get sidebarRecent => '最近';

  @override
  String get sidebarManageConversations => '批量管理历史对话';

  @override
  String get sidebarEmptyConversations => '暂无历史对话';

  @override
  String get sidebarUnnamedScene => '未命名场景';

  @override
  String get sidebarDeleteDialogTitle => '删除场景对话';

  @override
  String sidebarDeleteDialogMessage(String title) {
    return '确定删除「$title」吗？\n删除后历史对话与演变剧情将无法恢复。';
  }

  @override
  String get sidebarReturnHome => '返回探索大厅';

  @override
  String get sidebarExpand => '展开侧边栏';

  @override
  String get sidebarCollapse => '收起侧边栏';

  @override
  String get sidebarClose => '关闭侧边栏';

  @override
  String get brandSubtitle => '叙事与世界演变工坊';

  @override
  String get serviceConnected => '官方在服';

  @override
  String get serviceNotConfigured => '未配置密钥';

  @override
  String get officialOnline => '在服';

  @override
  String get languageSetupTitle => '选择语言';

  @override
  String get languageSetupSubtitle => '请选择应用显示语言';

  @override
  String get languageSettingTitle => '语言';

  @override
  String get languageSettingSubtitle => '应用显示语言';

  @override
  String get confirmAction => '确定';

  @override
  String get cancelAction => '取消';

  @override
  String get deleteAction => '删除';

  @override
  String get saveAction => '保存';

  @override
  String get continueAction => '继续';

  @override
  String get closeAction => '关闭';

  @override
  String get doneAction => '完成';

  @override
  String get editAction => '编辑';

  @override
  String get retryAction => '重试';

  @override
  String get copyAction => '复制';

  @override
  String get settingsCenter => '设置中心';

  @override
  String get settingsSystemConfig => '系统配置';

  @override
  String get settingsReturnHome => '返回大厅';

  @override
  String get settingsReturnList => '返回设置列表';

  @override
  String get settingsPreferencesCategory => '偏好分类';

  @override
  String get settingsCoreEngine => '灵境核心引擎';

  @override
  String get settingsStorageType => 'SQLite · 本地加密优先';

  @override
  String get tabModelApi => '模型与 API';

  @override
  String get tabModelApiSubtitle => '服务商与密钥配置';

  @override
  String get tabSessionParams => '会话参数';

  @override
  String get tabSessionParamsSubtitle => '采样率与深度思考';

  @override
  String get tabThemeAppearance => '主题配色';

  @override
  String get tabThemeAppearanceSubtitle => '深浅与主题色彩';

  @override
  String get tabDataManagement => '数据管理';

  @override
  String get tabDataManagementSubtitle => 'Token 统计与存储';

  @override
  String get configCategory => '配置分类';

  @override
  String get apiServiceConnected => '大模型服务已连接';

  @override
  String get apiServiceConnectedDesc => '点击管理服务商、模型与端点';

  @override
  String get apiServiceDisconnectedDesc => '点击配置 API 密钥以启动推演';

  @override
  String get providerConfigTitle => '模型提供商与 API 配置';

  @override
  String get providerConfigSubtitle => '配置大模型提供商、端点地址与安全密钥';

  @override
  String get testConnection => '测试连接';

  @override
  String get testingConnection => '正在测试...';

  @override
  String get inputApiKeyHint => '请先输入有效的 API 密钥';

  @override
  String connectionSuccess(int time) {
    return '连接成功！耗时 ${time}ms，服务状态极佳。';
  }

  @override
  String get connectionFailed => '连接失败，请核对密钥是否正确及网络是否通畅。';

  @override
  String connectionFailedWithReason(String error) {
    return '连接失败: $error';
  }

  @override
  String get apiKeyLabel => 'API 密钥 (API Key)';

  @override
  String get apiKeyPlaceholder => '请输入 API 密钥';

  @override
  String get customEndpointLabel => '自定义端点 (Base URL)';

  @override
  String get customEndpointPlaceholder => '自定义端点 URL';

  @override
  String get modelLabel => '模型名称';

  @override
  String get modelPlaceholder => '输入模型名称';

  @override
  String get customModelNote => '使用自定义模型端点';

  @override
  String get modelParamsSectionTitle => '会话模型参数';

  @override
  String get modelParamsSectionSubtitle => '精细调优内容生成采样温度、上下文预算与深度思考推理模式';

  @override
  String get systemPromptLabel => '自定义系统提示词';

  @override
  String get systemPromptPlaceholder => '输入系统提示词以指导 AI 扮演角色与行为风格...';

  @override
  String get authorsNoteLabel => '作者注释 (Author\'s Note)';

  @override
  String get authorsNotePlaceholder => '在最近回合中注入强效上下文提醒...';

  @override
  String authorsNoteDepthLabel(int depth) {
    return '插入深度：距底 $depth 回合';
  }

  @override
  String authorsNoteFrequencyLabel(int freq) {
    return '生效频率：每 $freq 回合触发一次';
  }

  @override
  String get dialogueLevelLabel => '文学修辞风格与深度';

  @override
  String temperatureLabel(String value) {
    return '采样温度 (发散度): $value';
  }

  @override
  String get enableThinkingLabel => '启用深度思考模式 (Deep Thinking)';

  @override
  String get enableThinkingSubtitle => '开启后模型在生成剧情前输出可折叠的思维链推演过程';

  @override
  String get reasoningEffortLabel => '思考强度 (Reasoning Effort)';

  @override
  String get quickModeLabel => '极速模式';

  @override
  String get quickModeSubtitle => '跳过打字机流式动画，快速呈现完整回复';

  @override
  String get appearanceSectionTitle => '外观与视觉主题';

  @override
  String get appearanceSectionSubtitle => '定制界面的色彩主题、深浅模式与阅读字号';

  @override
  String get themeModeLabel => '主题模式';

  @override
  String get themeLight => '明亮';

  @override
  String get themeDark => '暗黑';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get themeColorPalette => '主题色盘';

  @override
  String get themeColorPaletteHint => '点击即时换肤';

  @override
  String chatFontSizeLabel(int size) {
    return '叙事文本字号: $size pt';
  }

  @override
  String get chatFontCompact => '小巧精炼';

  @override
  String get chatFontStandard => '标准阅读';

  @override
  String get chatFontSpacious => '宽适大字';

  @override
  String get previewTypographyTitle => '阅读排版实时效果';

  @override
  String get previewTypographySample =>
      '「灵境叙事」—— 在浩瀚无垠的世界线交织中，你的每一个抉择都将掀起命运的波澜。暗流涌动的地下城、悬浮天际的机械遗迹，一切传奇皆自此启程。';

  @override
  String get readingScrollTitle => '阅读与滚动控制';

  @override
  String get readingScrollSubtitle => '控制文本生成与阅读时的屏幕滚动体验';

  @override
  String get autoScrollLabel => '生成时自动跟随滚动';

  @override
  String get autoScrollSubtitleOn => '开启状态：生成新内容时屏幕持续自动滚到底部最新字句。';

  @override
  String get autoScrollSubtitleOff =>
      '默认推荐（阅读优先）：生成新内容时屏幕保持平稳，方便您从开头不受打扰地读完；滑动完全受您控制。';

  @override
  String get dataManagementTitle => '数据管理与用量统计';

  @override
  String get dataManagementSubtitle => '查看 Token 消耗、语音 TTS 播报设置与存储管理';

  @override
  String get tokenUsageTitle => '本地 Token 消耗估算';

  @override
  String get sessionTokensLabel => '本次会话消耗';

  @override
  String get totalTokensLabel => '历史累计持久化';

  @override
  String get readAloudSectionTitle => '语音消息朗读 (TTS)';

  @override
  String get readAloudSupportedPlatform => '当前平台支持系统语音朗读，可在对话与创作工作台中使用。';

  @override
  String get readAloudUnsupportedPlatform => '当前平台不支持语音朗读。';

  @override
  String get readAloudEnable => '启用语音朗读';

  @override
  String get readAloudEnableSubtitle => '支持在对话、创作工作台与组装预览中朗读正文';

  @override
  String get readAloudAutoRead => '完成时自动朗读';

  @override
  String get readAloudAutoReadSubtitle => '当 AI 生成完完整剧情后自动进行语音播报';

  @override
  String get readAloudRate => '语速';

  @override
  String get readAloudPitch => '音调';

  @override
  String get readAloudVolume => '音量';

  @override
  String get readAloudLanguage => '朗读语言';

  @override
  String get readAloudAutoDetect => '自动检测';

  @override
  String get readAloudAutoDetectHint => '根据每段正文自动选择可用的系统语音语言。';

  @override
  String get readAloudFixedHint => '所有正文都使用所选语言朗读。';

  @override
  String get readAloudUnsupportedLanguage => '（不支持）';

  @override
  String readAloudAvailableLanguagesCount(int count) {
    return '系统可用语言：$count 种';
  }

  @override
  String get readAloudDisabledInSettings => '语音朗读已在设置中关闭';

  @override
  String get readAloudStop => '停止朗读';

  @override
  String get readAloudStart => '朗读';

  @override
  String get diagnosticExportTitle => '诊断数据导出';

  @override
  String get diagnosticExportSubtitle => '仅导出当前冒险分支最近 30 回合；API 凭证与隐藏推理不会写入文件。';

  @override
  String get exportDiagnosticJson => '导出诊断会话 JSON';

  @override
  String get cacheStorageTitle => '缓存与存储管理';

  @override
  String get clearCache => '清空临时缓存';

  @override
  String get clearCacheSuccess => '已清空会话临时缓存与重置计数器';

  @override
  String get clearAllData => '清空全部本地数据';

  @override
  String get clearDataDialogTitle => '重置所有本地数据';

  @override
  String get clearDataDialogMessage => '确定要清空所有本地冒险、卡片与缓存数据吗？\n此操作不可恢复。';

  @override
  String get exportChatTitle => '导出聊天';

  @override
  String get importChatTitle => '导入聊天';

  @override
  String get dashboardHeroTitle => '灵境 · 探索与叙事工坊';

  @override
  String get dashboardHeroSubtitle => '交互小说与沉浸式 RPG 叙事空间';

  @override
  String get dashboardWizardCardTitle => '四步向导定制';

  @override
  String get dashboardWizardCardDesc => '白板起步，自主设定世界观、角色卡、序章与初始行动。';

  @override
  String get dashboardWizardCardAction => '启动向导';

  @override
  String get dashboardPresetCardTitle => '预存场景工坊';

  @override
  String get dashboardPresetCardDesc => '浏览已构建的预设冒险剧本，支持一键启程或微调。';

  @override
  String get dashboardPresetCardAction => '查看预存场景';

  @override
  String get dashboardLibraryCardTitle => '资料库';

  @override
  String get dashboardLibraryCardDesc => '查阅与管理你构想的世界观预设、角色卡与 NPC 档案。';

  @override
  String get dashboardLibraryCardAction => '管理资料库';

  @override
  String get dashboardSettingsCardTitle => '系统设置中心';

  @override
  String get dashboardSettingsCardDesc => '配置大模型连接参数、外观主题与历史数据管理。';

  @override
  String get dashboardSettingsCardAction => '进入设置';

  @override
  String get recentAdventuresTitle => '最近冒险';

  @override
  String get noRecentAdventures => '暂无历史冒险，点击启动向导开启新的征途';

  @override
  String get continueAdventure => '继续冒险';

  @override
  String get featuredWorldviews => '精选世界观';

  @override
  String get featuredCharacters => '精选角色';

  @override
  String get resourceLibraryTitle => '资料库';

  @override
  String get resourceLibrarySubtitle => '浏览与管理你的世界观、角色卡与剧情模版';

  @override
  String get createResourceAction => '新建资源';

  @override
  String get searchResources => '搜索资源...';

  @override
  String get allResources => '全部';

  @override
  String get worldviewsTab => '世界观';

  @override
  String get charactersTab => '角色';

  @override
  String get templatesTab => '模版';

  @override
  String get recycleBinTitle => '回收站';

  @override
  String get emptyRecycleBin => '回收站是空的';

  @override
  String get restoreAction => '恢复';

  @override
  String get permanentlyDelete => '永久删除';

  @override
  String get resourceStudioTitle => '创作工作台';

  @override
  String get resourceStudioSubtitle => '多小节渐进式创作与容量管理';

  @override
  String get outlineTab => '大纲';

  @override
  String get capacityTab => '容量';

  @override
  String get historyTab => '版本';

  @override
  String get generatePart => '生成内容';

  @override
  String get regeneratePart => '重新生成';

  @override
  String get partSaved => '修改已保存';

  @override
  String get partSaving => '保存中...';

  @override
  String get assemblyWizardTitle => '场景装配与就绪检查';

  @override
  String get wizardWorldviewAiSummary =>
      '输入题材风格或核心构思，AI 可在此起草世界观，也可在资料库中创作完整的多模块世界。';

  @override
  String get adventureWizardTitle => '定制冒险向导';

  @override
  String get assemblyStepWorld => '1. 世界观';

  @override
  String get assemblyStepCharacters => '2. 角色设定';

  @override
  String get assemblyStepNpcs => '3. NPC 阵营';

  @override
  String get assemblyStepConfig => '4. 规则与序章';

  @override
  String get assemblyPreviewTitle => '装配预览';

  @override
  String get startAdventureAction => '开启冒险';

  @override
  String get readinessChecking => '检查资源就绪状态...';

  @override
  String get readinessPassed => '全部资源已就绪';

  @override
  String get readinessFailed => '资源需要装配就绪或压缩处理';

  @override
  String get adventureSessionTitle => '冒险进行中';

  @override
  String get inputActionHint => '你的下一步行动是？输入行动或对白...';

  @override
  String get sendAction => '发送';

  @override
  String get aiThinking => 'AI 正在思考...';

  @override
  String get aiWriting => 'AI 正在撰写...';

  @override
  String get diceCheckTitle => '骰点检定';

  @override
  String get turnSettling => '正在结算当前回合选项...';

  @override
  String get bookmarkAdded => '已添加书签';

  @override
  String get bookmarkRemoved => '已移除书签';

  @override
  String get messageCopied => '消息已复制到剪贴板';

  @override
  String get messageEdited => '消息已编辑';

  @override
  String get chatEditMessage => '编辑消息';

  @override
  String get chatReadAloudUnsupported => '当前平台不支持朗读';

  @override
  String get chatCopyReasoning => '复制思考过程（思维链）';

  @override
  String get chatReasoningCopied => '思维链已复制到剪贴板';

  @override
  String get chatRetryWithModel => '用其他模型重试';

  @override
  String get chatFork => '从此处分叉';

  @override
  String chatBranchCreated(Object branch) {
    return '已创建分支 $branch';
  }

  @override
  String get chatDeleteMessage => '删除';

  @override
  String get chatSearchHint => '搜索对话内容…';

  @override
  String get chatBookmarksOnly => '仅书签';

  @override
  String get chatMoreActions => '更多操作';

  @override
  String get chatEditStatus => '编辑状态';

  @override
  String get chatDeleteStatus => '删除状态';

  @override
  String get readAloudPause => '暂停';

  @override
  String get readAloudPauseRestart => '暂停（将从本段开头继续）';

  @override
  String get readAloudResume => '继续朗读';

  @override
  String get readAloudPreparing => '准备朗读';

  @override
  String get readAloudPrevious => '上一段';

  @override
  String get readAloudNext => '下一段';

  @override
  String get tokenCurrentScene => '本次场景 Token';

  @override
  String get tokenHistoryTotal => '累计 Token';

  @override
  String get tokenCurrentSceneDescription => '当前场景消耗 Tokens';

  @override
  String get tokenHistoryDescription => '本地记录历史累计 Tokens';

  @override
  String get readAloudPlatformSupportedMessage => '当前平台支持系统语音朗读，可在对话与创作工作台中使用。';

  @override
  String get diagnosticExportFailed => '诊断导出失败，请稍后重试。';

  @override
  String diagnosticExported(Object path) {
    return '诊断会话已导出：$path';
  }

  @override
  String get clearHistoryTitle => '清空历史对话记录';

  @override
  String get clearHistoryMessage =>
      '确定要清空所有过去的对话存档吗？\n世界观与角色卡资产将保留，但场景聊天历史将无法恢复。';

  @override
  String get clearHistoryConfirm => '确认清空';

  @override
  String get clearHistorySuccess => '已成功清理所有历史会话记录';

  @override
  String get readAloudRateLabel => '语速';

  @override
  String get readAloudPitchLabel => '音调';

  @override
  String get readAloudLanguageHintAuto => '根据每段正文自动选择可用的系统语音语言。';

  @override
  String get readAloudLanguageHintFixed => '所有正文都使用所选语言朗读。';

  @override
  String readAloudSupportedCount(Object count) {
    return '系统可用语言：$count 种';
  }

  @override
  String get generationWaiting => '等待生成内容…';

  @override
  String get errorTimeoutTitle => '请求超时';

  @override
  String get errorTimeoutSuggestion => '请检查网络连接后重试';

  @override
  String get errorAuthTitle => '认证失败';

  @override
  String get errorAuthSuggestion => '请检查 API Key 是否有效';

  @override
  String get errorRateTitle => '请求过于频繁';

  @override
  String get errorRateSuggestion => '请稍等片刻后重试';

  @override
  String get errorApiTitle => 'API 错误';

  @override
  String get errorApiSuggestion => '请检查 API 配置或稍后重试';

  @override
  String get errorNetworkTitle => '网络错误';

  @override
  String get errorNetworkSuggestion => '请检查网络连接和 API 设置后重试';

  @override
  String get switchModelRetry => '切换模型重试';

  @override
  String get resourceTrashTooltip => '回收站';

  @override
  String get resourceCreateShort => '新建';

  @override
  String get resourceNpcTab => 'NPC';

  @override
  String get resourceRetryLoad => '重试';

  @override
  String get resourceEmptyTitle => '还没有资源';

  @override
  String get resourceNoMatches => '没有找到匹配的资源';

  @override
  String get resourceNoSummary => '暂无简介';

  @override
  String get resourceMovedToTrash => '已移入回收站';

  @override
  String get refreshRecycleBin => '刷新回收站';

  @override
  String permanentDeleteMessage(Object title) {
    return '「$title」及其内容将被彻底删除，无法恢复。\n确定要继续吗？';
  }

  @override
  String get readinessBlockedTitle => '暂时无法开始冒险';

  @override
  String get acknowledgeAction => '知道了';

  @override
  String get staleResourceTitle => '资源已修改';

  @override
  String get staleResourceMessage => '以下资源在最近一次就绪后又发生了修改：';

  @override
  String get usePreviousReady => '是否使用上一个已就绪版本开始冒险？';

  @override
  String get chatImportFormat => '格式';

  @override
  String get chatImportLabel => '聊天内容';

  @override
  String get chatImportHint => '在此粘贴聊天内容...';

  @override
  String get chatImportSuccess => '导入成功';

  @override
  String get chatImportParsing => '解析中...';

  @override
  String get chatImportAction => '导入';

  @override
  String get chatImportEmpty => '请先粘贴聊天内容';

  @override
  String chatImportFailed(Object error) {
    return '导入失败：$error';
  }

  @override
  String get chatExportWarning => '导出内容可能包含对话和用户输入，请妥善保管。';

  @override
  String get chatSaveFailed => '保存失败';

  @override
  String chatSavedPath(Object path) {
    return '已保存：$path';
  }

  @override
  String get chatSaving => '保存中...';

  @override
  String get chatLoadFailedRetry => '加载失败，重试';

  @override
  String chatCharacterCount(Object count) {
    return '$count 字符';
  }

  @override
  String get resourceDetailTitle => '资源详情';

  @override
  String get resourceEnterStudio => '进入创作工作台';

  @override
  String get resourceLegacyNoStudio => '旧资源暂不支持高级创作';

  @override
  String get resourceActions => '资源操作';

  @override
  String get moveToTrashAction => '移入回收站';

  @override
  String moveToTrashMessage(Object name) {
    return '将「$name」移入回收站？之后可在回收站中恢复。';
  }

  @override
  String get moveToTrashFailed => '移入回收站失败，请重试';

  @override
  String get thinkingEngineTitle => '深度思考引擎';

  @override
  String get thinkingEngineBadge => 'V4.1 原生思考';

  @override
  String get thinkingEngineDescription =>
      '针对复杂多支线冒险与世界观逻辑推演，开启 DeepSeek V4.1 原生思维链的前置规划。';

  @override
  String get worldviewDeepThinkingLabel => '世界观深度推演生成';

  @override
  String get worldviewDeepThinkingSubtitle =>
      '世界观 AI 导入允许使用 V4.1 深度推演；默认关闭以降低首 Token 延迟';

  @override
  String get characterDeepThinkingLabel => '角色卡深度推演生成';

  @override
  String get characterDeepThinkingSubtitle =>
      '角色卡 AI 导入允许使用 V4.1 深度推演；默认关闭以优先快速生成';

  @override
  String get reasoningEffortLow => '轻度推演 · 极速响应';

  @override
  String get reasoningEffortMedium => '平衡推演 · 推荐日常';

  @override
  String get reasoningEffortHigh => '深度思考 · 丰富细节';

  @override
  String get reasoningEffortMax => '极致演算 · 严谨逻辑';

  @override
  String get restoreRecommended => '恢复默认推荐';

  @override
  String get recommendedDefaultsRestored => '已恢复官方推荐默认参数';

  @override
  String get revisionHistoryTitle => '历史记录';

  @override
  String revisionCount(Object count) {
    return '$count 条记录';
  }

  @override
  String get refreshRevisionHistory => '刷新版本历史';

  @override
  String get noRestorableRevisions => '还没有可恢复的历史记录';

  @override
  String get currentRevision => '当前';

  @override
  String get restoreRevision => '恢复此记录';

  @override
  String get presetParseError => '剧本数据解析失败或格式不完整';

  @override
  String get presetWorldviewTitle => '世界观设定';

  @override
  String get presetCharacterTitle => '主角档案';

  @override
  String get presetOpeningTitle => '开场序章';

  @override
  String get presetOptionsTitle => '初始行动分支';

  @override
  String get presetNpcTitle => '登场配角（NPC）';

  @override
  String get presetCustomizeAction => '向导载入微调';

  @override
  String get presetDetailsAction => '详情';

  @override
  String get sidebarEmptyConversationsSubtitle => '点击上方按钮开启新冒险';

  @override
  String get sidebarDeleteTooltip => '删除对话';

  @override
  String get sidebarSettingsNotConfigured => '系统设置（未配置密钥）';

  @override
  String get characterFallbackName => '角色A';

  @override
  String get monitoredStatus => '监测状态';

  @override
  String get expandAction => '展开 ▼';

  @override
  String get collapseAction => '收起 ▲';

  @override
  String statusItemsCount(int count) {
    return '$count项';
  }

  @override
  String optionsSectionTitle(int count) {
    return '选项 ($count 个选项)';
  }

  @override
  String get selectPrompt => '请选择';

  @override
  String get noOptionsAvailable => '暂无可选项';

  @override
  String get notSpecified => '不指定';

  @override
  String itemsSelectedCount(int count) {
    return '已选 $count 项';
  }

  @override
  String get backAction => '返回';

  @override
  String get showPassword => '显示明文';

  @override
  String get hidePassword => '隐藏明文';

  @override
  String get actionMenuTitle => '操作';

  @override
  String get actionMenuSemanticLabel => '操作菜单';

  @override
  String get menuTooltip => '菜单';

  @override
  String get switchLibrary => '切换资料库';

  @override
  String get customAttributesTitle => '自添加项';

  @override
  String get customAttributesSubtitle => '支持自主为角色/NPC扩展任意专属设定，可单独命名并设置推演重要程度';

  @override
  String get addCustomAttributeAction => '添加项';

  @override
  String get noCustomAttributes => '暂无自添加项（纯净白板）';

  @override
  String get customAttributesEmptyHint => '点击右上角「添加项」可自主定义专属武器、隐秘禁忌、弱点或特质';

  @override
  String get customAttributeNameLabel => '项名称 *';

  @override
  String get customAttributeNameHint => '如: 随身佩剑、致命弱点、施法习惯';

  @override
  String get deleteAttributeTooltip => '删除该项';

  @override
  String get customAttributeContentLabel => '项内容 / 设定描述';

  @override
  String get customAttributeContentHint => '描述该项具体效果、起源或限制（LLM 推演时将遵从对应重要程度）';

  @override
  String get customAttributeImportanceReference => '参考';

  @override
  String get customAttributeImportanceImportant => '重要参考';

  @override
  String get customAttributeImportanceVeryImportant => '很重要参考';

  @override
  String get customAttributeImportanceCritical => '不可忽略项';

  @override
  String get feedbackSuccess => '成功';

  @override
  String get feedbackError => '错误';

  @override
  String get feedbackWarning => '提醒';

  @override
  String get feedbackInfo => '提示';

  @override
  String get refreshFailed => '刷新失败，请稍后重试';

  @override
  String get noRefreshNeeded => '当前页面无需刷新';

  @override
  String get fontSizeDialogTitle => '字号调节';

  @override
  String get fontSizeSmall => 'A小';

  @override
  String get fontSizeLarge => 'A大';

  @override
  String get fontSizePreview => '预览: 中文 123\n字号大小示例';

  @override
  String get applyAction => '应用';

  @override
  String appliedPresetNotice(String preset) {
    return '已应用：$preset';
  }

  @override
  String get dialogueParamsTitle => '对话参数';

  @override
  String get paramsPresetLabel => '参数预设';

  @override
  String get customPreset => '自定义';

  @override
  String get frequencyPenalty => '频惩罚';

  @override
  String get presencePenalty => '存惩罚';

  @override
  String get saveWorldviewTitle => '保存世界观';

  @override
  String get worldviewInfoSection => '世界观信息';

  @override
  String worldviewSavedSuccess(String name) {
    return '已保存世界观「$name」';
  }

  @override
  String saveFailedPrefix(String error) {
    return '保存失败：$error';
  }

  @override
  String get importCardDialogTitle => '导入角色卡';

  @override
  String get pasteCardJsonHeader => '粘贴 SillyTavern / Chub 角色卡 JSON';

  @override
  String get pasteCardJsonHint => '在此粘贴角色卡 JSON 内容...';

  @override
  String get newDialoguePersonaTitle => '新建对话角色卡';

  @override
  String get editDialoguePersonaTitle => '编辑对话角色卡';

  @override
  String get dialoguePersonaSettingHeader => '对话角色设定';

  @override
  String get dialoguePersonaScopeNotice => '这里的角色只用于对话模式，可以完全不使用奈拉。';

  @override
  String get personaNameLabel => '角色名称 *';

  @override
  String get personaNameHint => '例如：奈拉、顾问、我的写作搭档';

  @override
  String get personaRoleLabel => '身份定位';

  @override
  String get personaRoleHint => '例如：通用 AI 助手、语言教练、世界观顾问';

  @override
  String get personaUserAddressLabel => '如何称呼用户';

  @override
  String get personaUserAddressHint => '例如：用户、创作者、指挥官、老师';

  @override
  String get personaPersonalityLabel => '性格与行为特点';

  @override
  String get personaPersonalityHint => '描述角色的性格、价值观和处理问题的方式';

  @override
  String get personaSpeakingStyleLabel => '说话方式';

  @override
  String get personaSpeakingStyleHint => '例如：简洁、温柔，必要时用步骤和示例解释';

  @override
  String get personaBackgroundLabel => '背景设定';

  @override
  String get personaBackgroundHint => '角色从哪里来，以及它了解什么';

  @override
  String get personaContextLabel => '对话情境';

  @override
  String get personaContextHint => '描述角色与用户通常在哪种情境下交流';

  @override
  String get personaDirectivesLabel => '额外行为指令';

  @override
  String get personaDirectivesHint => '可选：补充角色必须遵守的行为规则';

  @override
  String get deleteDialoguePersonaTitle => '删除对话角色卡？';

  @override
  String deleteDialoguePersonaMessage(String name) {
    return '确定要删除“$name”吗？';
  }

  @override
  String deleteCharacterCardFailed(String error) {
    return '删除角色卡失败: $error';
  }

  @override
  String get nameRequired => '请填写角色名称';

  @override
  String get manualCreatedSource => '手动创建';

  @override
  String get createAction => '创建';

  @override
  String get nameLabel => '名称';

  @override
  String get descriptionOptionalLabel => '描述（可选）';

  @override
  String get fontSizeAdjustment => '字号调节';

  @override
  String get fontSizeSmallA => 'A小';

  @override
  String get fontSizeLargeA => 'A大';

  @override
  String get dialogueParams => '对话参数';

  @override
  String get parameterPresets => '参数预设';

  @override
  String get presetDeepThinking => '深度思考 (V4.1 复杂推演)';

  @override
  String get presetFastNarrative => '极速叙事 (默认体验)';

  @override
  String get presetDeepReasoning => '极限推理 (长考解谜)';

  @override
  String get presetLightweightDaily => '轻量日常 (极速低延迟)';

  @override
  String appliedPreset(String preset) {
    return '已应用：$preset';
  }

  @override
  String get saveWorldview => '保存世界观';

  @override
  String get worldviewInfo => '世界观信息';

  @override
  String get name => '名称';

  @override
  String get descriptionOptional => '描述（可选）';

  @override
  String worldviewSaved(String name) {
    return '已保存世界观「$name」';
  }

  @override
  String saveFailed(String error) {
    return '保存失败：$error';
  }

  @override
  String get unknownError => '未知错误';

  @override
  String get importCharacterCard => '导入角色卡';

  @override
  String get pasteCharacterCardJson => '粘贴 SillyTavern / Chub 角色卡 JSON';

  @override
  String get pasteCharacterCardJsonHint => '在此粘贴角色卡 JSON 内容...';

  @override
  String get importAction => '导入';

  @override
  String get editDialoguePersonaCard => '编辑对话角色卡';

  @override
  String get newDialoguePersonaCard => '新建对话角色卡';

  @override
  String get dialoguePersonaSettings => '对话角色设定';

  @override
  String get dialoguePersonaSettingsDesc => '这里的角色只用于对话模式，可以完全不使用奈拉。';

  @override
  String get personaNameRequired => '角色名称 *';

  @override
  String get personaRole => '身份定位';

  @override
  String get personaUserCallName => '如何称呼用户';

  @override
  String get personaUserCallNameHint => '例如：用户、创作者、指挥官、老师';

  @override
  String get personaPersonality => '性格与行为特点';

  @override
  String get personaSpeakingStyle => '说话方式';

  @override
  String get personaBackground => '背景设定';

  @override
  String get personaScenario => '对话情境';

  @override
  String get personaScenarioHint => '描述角色与用户通常在哪种情境下交流';

  @override
  String get personaSystemPrompt => '额外行为指令';

  @override
  String get personaSystemPromptHint => '可选：补充角色必须遵守的行为规则';

  @override
  String deleteDialoguePersonaPrompt(String name) {
    return '确定要删除“$name”吗？';
  }

  @override
  String get pleaseEnterPersonaName => '请填写角色名称';

  @override
  String get manuallyCreated => '手动创建';

  @override
  String get sidebarSystemSettings => '系统设置';

  @override
  String get settingsTabModelAndApi => '模型与 API';

  @override
  String get settingsTabModelAndApiSubtitle => '服务商与密钥配置';

  @override
  String get settingsTabSessionParams => '会话参数';

  @override
  String get settingsTabSessionParamsSubtitle => '采样率与深度思考';

  @override
  String get settingsTabAppearance => '主题配色';

  @override
  String get settingsTabAppearanceSubtitle => '深浅与主题色彩';

  @override
  String get settingsTabStorage => '数据管理';

  @override
  String get settingsTabStorageSubtitle => 'Token 统计与存储';

  @override
  String get settingsCustomProvider => '自定义';

  @override
  String get settingsReturnToLobby => '返回大厅';

  @override
  String get settingsReturnToSettingsList => '返回设置列表';

  @override
  String get settingsConfigsCategory => '配置分类';

  @override
  String settingsOfficialInService(String provider) {
    return '$provider 官方在服';
  }

  @override
  String get settingsKeyNotConfigured => '未配置密钥';

  @override
  String get settingsLlmConnected => '大模型服务已连接';

  @override
  String get settingsLlmDisconnected => '未配置 API 密钥';

  @override
  String get settingsLlmConnectedSubtitle => '点击管理服务商、模型与端点';

  @override
  String get settingsLlmDisconnectedSubtitle => '点击配置 API 密钥以启动推演';

  @override
  String get settingsEngineTitle => '灵境核心引擎';

  @override
  String get settingsEngineSubtitle => 'SQLite · 本地加密优先';

  @override
  String get settingsSystemConfigBadge => '系统配置';

  @override
  String get inferenceParamsTitle => '推理超参与采样调节';

  @override
  String get inferenceParamsSubtitle => '调整温度、采样阈值与深度思考强度以平衡文采与逻辑一致性';

  @override
  String get deepseekThinkingHint =>
      '💡 提示：DeepSeek V4.1 思考模式下采样超参由模型自适应管理；非思考模式固定 top_p=1.0，仅温度可调。';

  @override
  String get temperatureTitle => '生成温度 (Temperature)';

  @override
  String get temperatureDescription => '0.0 绝对严谨精确 ↔ 2.0 天马行空丰富';

  @override
  String get topPTitle => '核采样概率 (Top-P)';

  @override
  String get topPDescription => '累积概率截断阈值，推荐保持 0.90 ~ 0.95';

  @override
  String get maxTokensTitle => '单次最大生成长度 (Max Tokens)';

  @override
  String get maxTokensDescription => '限制单回合对话的最大 Token 预算';

  @override
  String get paramsRealtimeNotice => '提示：参数变动实时生效，无需手动保存';

  @override
  String testConnectionSuccess(int elapsed) {
    return '连接成功！耗时 ${elapsed}ms，服务状态极佳。';
  }

  @override
  String get testConnectionFailure => '连接失败，请核对密钥是否正确及网络是否通畅。';

  @override
  String testConnectionFailureDetail(String error) {
    return '连接失败: $error';
  }

  @override
  String get statusReady => '已就绪';

  @override
  String get statusNotReady => '未就绪';

  @override
  String modelEndpointSummary(String model, String endpoint) {
    return '模型: $model · 端点: $endpoint';
  }

  @override
  String get quickTesting => '检测中';

  @override
  String get quickTest => '快速测通';

  @override
  String get llmProviderSectionTitle => 'LLM 服务提供商';

  @override
  String get llmProviderSectionSubtitle => '选择并配置场景对话与推理使用的核心语言模型服务';

  @override
  String get modelProviderLabel => '模型提供商';

  @override
  String get selectInServiceModal => '选择在服模型';

  @override
  String get customModelNameLabel => '自定义模型名称';

  @override
  String get customModelNameHint => '如 gpt-4o, llama-3.3-70b, qwen-max';

  @override
  String get apiEndpointLabel => 'API 服务端点 (Base URL)';

  @override
  String get apiSecurityNotice => '密钥加密存储于本地设备 SQLite 数据库，永远不会经由中间服务器转存';

  @override
  String get promptSettingsTitle => '提示词与推演编排';

  @override
  String get importPresets => '导入预设';

  @override
  String get exportPresets => '导出预设';

  @override
  String get previewPromptAction => '预览';

  @override
  String get importPresetTitle => '导入提示词预设';

  @override
  String get exportPresetTitle => '导出提示词预设';

  @override
  String get presetJsonLabel => '提示词预设 JSON';

  @override
  String get presetJsonEmptyError => '请输入预设 JSON';

  @override
  String presetImportFailed(String error) {
    return '导入失败：$error';
  }

  @override
  String get presetJsonCopied => '已复制预设 JSON';

  @override
  String get copyAllAction => '复制全部';

  @override
  String get dialogueLevelSectionTitle => '对话模式分级 (Dialogue Level)';

  @override
  String get dialogueLevelSectionSubtitle => '选择模型在单轮对话中的字数输出预算与描摹细节密度。';

  @override
  String get systemPromptSectionTitle => '全局系统提示词 (System Prompt)';

  @override
  String get systemPromptSectionSubtitle => '纯净初始状态。留空时系统将采用极简通用的推演规范。';

  @override
  String get systemPromptHint => '在此编写自定义系统设定、世界规则或角色推演守则（留空使用纯净默认规则）...';

  @override
  String charCountLabel(int count) {
    return '已写 $count 字符';
  }

  @override
  String get clearAction => '清空';

  @override
  String get systemPromptSaved => '全局系统提示词已保存';

  @override
  String get savePromptAction => '保存提示词';

  @override
  String get authorsNoteSectionTitle => '作者注释 (Author\'s Note)';

  @override
  String get authorsNoteSectionSubtitle => '在会话上下文中指定轮数深度注入高权重指示。';

  @override
  String get authorsNoteHint => '例如：聚焦于主角行动的细致刻画，保持环境氛围神秘悬疑...';

  @override
  String get injectionDepth => '注入深度';

  @override
  String get depthFollowSystem => '紧跟系统设定';

  @override
  String depthBeforeRound(int depth) {
    return '第 $depth 轮前';
  }

  @override
  String get injectionFrequency => '注入频率';

  @override
  String freqEveryRound(int freq) {
    return '每 $freq 轮';
  }

  @override
  String get authorsNoteSaved => '作者注释设置已保存';

  @override
  String get saveNoteConfigAction => '保存注释配置';

  @override
  String get promptPreviewTitle => '实时 Prompt 装配预览';

  @override
  String get copyFullPrompt => '复制完整 Prompt';

  @override
  String get fullPromptCopied => '已复制完整装配 Prompt 到剪贴板';

  @override
  String promptPreviewStats(int chars, int tokens) {
    return '共约 $chars 字符 · 预估 $tokens tokens';
  }

  @override
  String get resourceTypeWorldview => '世界观';

  @override
  String get resourceTypeCharacter => '角色';

  @override
  String get resourceTypeNpc => 'NPC';

  @override
  String get resourceStatusGenerating => '生成中';

  @override
  String get resourceStatusSaved => '已保存';

  @override
  String get resourceStatusOptimizationSuggested => '建议优化';

  @override
  String get resourceStatusOptimizing => '正在优化';

  @override
  String get resourceStatusReady => '已准备完成';

  @override
  String get resourceStatusOptimizationFailed => '优化失败';

  @override
  String get resourceUnknownTime => '未知时间';

  @override
  String get resourceCreateTitle => '新建资源';

  @override
  String get resourceTypeSectionTitle => '资源类型';

  @override
  String get resourceTypeSectionDescription => '选择所要构建的内容载体类型';

  @override
  String get resourcePreselectedType => '预选类型';

  @override
  String get resourceCreationMethodSectionTitle => '创建方式';

  @override
  String get resourceCreationMethodSectionDescription =>
      '根据创作需要选择由 AI 辅助推演或手动纯文本编写';

  @override
  String get resourceAiCreationTitle => 'AI 创建';

  @override
  String get resourceAiCreationDescription =>
      '基于参考资料、小说文本或现有资产，由 AI 自动推演章节大纲与正文内容。';

  @override
  String get resourceRecommendBadge => '推荐';

  @override
  String get resourceManualCreationTitle => '手动创建';

  @override
  String get resourceManualCreationDescription => '自定义名称与简介，建立空白资源后自由编排章节与内容。';

  @override
  String get resourceManualCreateTitle => '手动创建资源';

  @override
  String get resourceBasicInfoTitle => '基本信息';

  @override
  String get resourceManualBasicInfoDescription =>
      '填写资源的类型、名称与简要介绍，创建后即可在工作室中自由编排正文';

  @override
  String get resourceNameLabel => '名称';

  @override
  String get resourceManualNameHint => '输入清晰明确的名称';

  @override
  String get resourceSummaryOptionalLabel => '简介（可选）';

  @override
  String get resourceManualSummaryHint => '简要介绍该资源的定位与背景设定';

  @override
  String get resourceCreateAction => '创建';

  @override
  String get resourceInputNameError => '请输入资源名称';

  @override
  String get resourceAiCreateTitle => 'AI 智能创建资源';

  @override
  String get resourceAiBasicInfoDescription => '定义即将生成的资源载体类型与标题';

  @override
  String get resourceAiNameHint => '输入将要生成的设定或角色名称';

  @override
  String get resourceAssociateWorldviewTitle => '关联世界观（可选）';

  @override
  String get resourceAssociateWorldviewDescription =>
      '为角色或 NPC 指定其所属的原生世界观，作为生成时的补充上下文';

  @override
  String get resourceNoAvailableWorldview => '暂无可关联的世界观';

  @override
  String get resourceNotSpecified => '不指定';

  @override
  String get resourceReferenceSourceTitle => '参考资料来源';

  @override
  String get resourceReferenceSourceDescription =>
      '提供世界观背景、小说设定或关联资源，AI 将提取精髓并推演章节架构';

  @override
  String get resourceTabPaste => '粘贴';

  @override
  String get resourceTabFile => '文件';

  @override
  String get resourceTabExistingResource => '已有资源';

  @override
  String get resourcePasteReferenceLabel => '粘贴参考内容';

  @override
  String get resourcePasteReferenceHint => '输入或粘贴小说大纲、设定集草稿或背景描述...';

  @override
  String get resourceFileNameLabel => '文件名';

  @override
  String get resourceFileNameHint => '例如: world_notes.md';

  @override
  String get resourceFileContentLabel => '文件文本内容';

  @override
  String get resourceFileContentHint => '粘贴或输入文件内的原始文本...';

  @override
  String get resourceNoExistingInLibrary => '资料库中暂无可关联的已就绪资源，请切换至「粘贴」或「文件」输入。';

  @override
  String get resourceSelectExistingLabel => '选择已有资源';

  @override
  String get resourceSelectExistingHint => '点击选取参考的既有资源';

  @override
  String get resourceGenerationLengthTitle => '生成长度';

  @override
  String get resourceGenerationLengthDescription => '控制 AI 生成资源正文的大致目标字数';

  @override
  String get resourceTargetCharactersLabel => '目标字数';

  @override
  String resourceTargetCharactersValue(Object count) {
    return '$count 字';
  }

  @override
  String get resourceLengthShort => '短篇';

  @override
  String get resourceLengthLong => '长篇';

  @override
  String get resourceStartCreateAction => '开始创建';

  @override
  String get resourceInputOrPasteReferenceError => '请输入或粘贴参考资料正文';

  @override
  String get resourceInputFileNameError => '请输入文件名';

  @override
  String get resourceInputFileContentError => '请输入文件内容';

  @override
  String get resourceSelectExistingError => '请选择一个已有的资源作为参考';

  @override
  String get resourcePastedContentLabel => '粘贴内容';

  @override
  String get resourceLoadFailedRetry => '资源库加载失败，请重试';

  @override
  String get resourceCreationFailedRetry => '资源创建失败，请重试';

  @override
  String get resourceUnnamed => '未命名资源';

  @override
  String get resourceRevisionResourceKind => '资源';

  @override
  String get resourceRevisionSectionKind => '章节';

  @override
  String get resourceRevisionPartKind => '段落';

  @override
  String resourceTrashSubtitle(
      Object deletedAt, Object expiresAt, Object kind, Object reason) {
    return '$kind · $reason · 删除于 $deletedAt · 保留至 $expiresAt';
  }

  @override
  String resourceTrashRestoreFailed(Object error) {
    return '恢复失败：$error';
  }

  @override
  String get resourceTrashPermanentDeleteSuccess => '已永久删除';

  @override
  String resourceTrashPermanentDeleteFailed(Object error) {
    return '永久删除失败：$error';
  }

  @override
  String get modeTitleConversation => '对话资料库';

  @override
  String get modeTitleAdventure => '场景资料库';

  @override
  String get modeTitleCreation => '创作资料库';

  @override
  String get modeEmptyTitleConversation => '暂无对话角色卡';

  @override
  String get modeEmptyTitleAdventure => '暂无场景资料';

  @override
  String get modeEmptyTitleCreation => '暂无创作资料';

  @override
  String get modeEmptySubtitleConversation => '创建自定义角色卡，或查看过去的聊天记录。';

  @override
  String get modeEmptySubtitleAdventure => '导入角色、地点、规则或剧情资料，用于场景对话。';

  @override
  String get modeEmptySubtitleCreation => '导入世界观、角色设定、章节参考或写作资料，用于创作模式。';

  @override
  String get resourceStudioRefreshTooltip => '刷新';

  @override
  String get resourceStudioTocTitle => '目录';

  @override
  String get resourceStudioNoContent => '当前资源还没有可展示的内容。';

  @override
  String get resourceStudioReadAloudAll => '连续朗读全文';

  @override
  String get resourceStudioEditPart => '编辑正文';

  @override
  String get resourceStudioDeletePart => '删除段落';

  @override
  String get resourceStudioPartNotExistCannotEdit => '该段落已不存在，无法编辑';

  @override
  String get resourceStudioPublishCompressionTitle => '发布压缩结果';

  @override
  String get resourceStudioPublishCompressionMessage =>
      '压缩后的正文会替换当前内容，替换前的正文会记录为历史版本，可随时恢复。\n确定要发布吗？';

  @override
  String get resourceStudioPublishCompressionAction => '发布';

  @override
  String get resourceStudioRestoreRevisionTitle => '恢复历史版本';

  @override
  String get resourceStudioRestoreRevisionMessage =>
      '当前内容会被该历史版本替换，替换前的内容也会保留在版本历史中。\n确定要恢复吗？';

  @override
  String get resourceStudioRestoreRevisionAction => '恢复';

  @override
  String get resourceStudioDeletePartTitle => '删除段落';

  @override
  String resourceStudioDeletePartMessage(Object title) {
    return '「$title」会被移入回收站，可在「回收站」中恢复。\n确定要删除吗？';
  }

  @override
  String get resourceStudioDeletePartAction => '删除';

  @override
  String get resourceStudioPartNotExistCannotDelete => '该段落已不存在，无法删除';

  @override
  String get resourceStudioMovedToTrash => '已移入回收站，可在「回收站」中恢复';

  @override
  String resourceStudioDeletePartFailed(Object error) {
    return '删除段落失败：$error';
  }

  @override
  String get resourceStudioContinueGenerating => '继续生成';

  @override
  String get resourceStudioPauseGenerating => '暂停';

  @override
  String get resourceStudioCancelGenerating => '取消';

  @override
  String get resourceStudioRetryGenerating => '重试';

  @override
  String get resourceStudioCreatingAndStarting => '正在创建资源并启动生成';

  @override
  String resourceStudioTargetCharacters(Object count) {
    return '目标约 $count 字';
  }

  @override
  String get resourceStudioCreationFailed => '资源创建失败';

  @override
  String get resourceStudioPleaseRetryLater => '请稍后重试';

  @override
  String get resourceStudioRetryCreation => '重试创建';

  @override
  String get resourceStudioSelectResourceOrSession => '选择资源或生成会话';

  @override
  String get resourceStudioSelectSession => '选择生成会话';

  @override
  String get resourceStudioCreateAndStart => '创建并开始生成';

  @override
  String get resourceStudioPendingAiPlan => '待确认的 AI 规划';

  @override
  String get resourceStudioConfirmAndStart => '继续确认并开始生成';

  @override
  String resourceStudioUnfinishedTask(Object index) {
    return '未完成的生成任务 $index';
  }

  @override
  String get resourceStudioGeneratingStatus => '生成中';

  @override
  String get resourceStudioResourceLabel => '资源';

  @override
  String get resourceStudioNoResourceOrSession => '暂无资源或可恢复的生成会话。';

  @override
  String get resourceStudioAddSectionTitle => '新增章节';

  @override
  String get resourceStudioSectionTitleField => '章节标题';

  @override
  String get sectionControlsTitle => '章节控制';

  @override
  String sectionControlsCount(Object count) {
    return '$count 个章节';
  }

  @override
  String get sectionControlsAdd => '新增章节';

  @override
  String get sectionControlsEmpty => '该资源还没有章节。';

  @override
  String sectionControlsLoadMore(Object shown, Object total) {
    return '加载更多（已显示 $shown/$total）';
  }

  @override
  String get sectionControlsUnnamed => '（未命名章节）';

  @override
  String sectionControlsOrderIndex(Object index) {
    return '序号 $index';
  }

  @override
  String sectionControlsUpdated(Object time) {
    return '更新 $time';
  }

  @override
  String get sectionControlsValidate => '验证';

  @override
  String get sectionControlsMoreActions => '更多操作';

  @override
  String get sectionControlsRename => '重命名';

  @override
  String get sectionControlsMoveUp => '上移';

  @override
  String get sectionControlsMoveDown => '下移';

  @override
  String get sectionControlsDelete => '删除';

  @override
  String get sectionControlsDeleteTitle => '删除章节';

  @override
  String sectionControlsDeleteMessage(Object title) {
    return '确定删除「$title」及其所有内容吗？';
  }

  @override
  String get sectionControlsGenerate => '生成';

  @override
  String get sectionControlsRegenerate => '重新生成';

  @override
  String get sectionControlsNoTasksTooltip => '该章节没有生成任务（非 AI 蓝图创建），无法生成';

  @override
  String get sectionControlsRegenerateTooltip =>
      '重新运行该章节的生成任务；当前内容会先记录为历史版本，可随时恢复';

  @override
  String get sectionControlsRerunTooltip => '重新运行该章节的生成任务';

  @override
  String get sectionControlsRenameDialogTitle => '重命名章节';

  @override
  String get partEditorUnsavedDraftFound => '发现未保存的草稿';

  @override
  String get partEditorUnsavedDraftDesc => '上次编辑未写入正文。可以载入草稿继续编辑，或丢弃它。';

  @override
  String get partEditorLoadDraft => '载入草稿';

  @override
  String get partEditorDiscardDraft => '丢弃草稿';

  @override
  String get partEditorConflictDetected => '检测到内容冲突';

  @override
  String get partEditorConflictDesc =>
      '其他操作（如生成或恢复）修改了此段落。自动保存已暂停，你的文本仍保留在草稿中。请选择保留哪个版本：';

  @override
  String get partEditorUseMyText => '使用我的文本';

  @override
  String get partEditorDiscardMyText => '放弃我的文本';

  @override
  String get partEditorHint => '在这里编辑正文，停止输入后会自动保存';

  @override
  String get partEditorSaveNow => '立即保存';

  @override
  String get partEditorFinishEditing => '完成编辑';

  @override
  String get partEditorDraftLoaded => '已载入草稿，保存后写入正文';

  @override
  String get partEditorDraftDiscarded => '草稿已丢弃';

  @override
  String get partEditorEditing => '编辑中…';

  @override
  String get partEditorConflictOtherSaved => '保存冲突：其他操作修改了此段落，请选择保留哪个版本';

  @override
  String get partEditorConflictDraftRetained => '保存冲突：内容仍保留在草稿中，未覆盖较新的版本';

  @override
  String partEditorAutoSaved(Object label) {
    return '已自动保存 ($label)';
  }

  @override
  String get partEditorTargetPartMissing => '目标内容已不存在，草稿已丢弃';

  @override
  String get partEditorKeptMyTextAndSaved => '已保留我的文本并保存';

  @override
  String get partEditorConflictStillUnresolved => '冲突仍未解决：段落又被修改了一次，请重新选择';

  @override
  String partEditorResolveConflictFailed(Object error) {
    return '解决冲突失败：$error';
  }

  @override
  String partEditorSaving(Object label) {
    return '正在保存 ($label)…';
  }

  @override
  String get capacityPanelTitle => '容量';

  @override
  String capacityLatestFailureReason(Object reason) {
    return '最近一次压缩失败原因：$reason';
  }

  @override
  String get capacityRefresh => '刷新容量';

  @override
  String get capacityCompressing => '压缩中';

  @override
  String get capacityGenerateCandidates => '生成压缩候选';

  @override
  String capacityRetryFailedWithCount(Object count) {
    return '重试失败压缩（$count）';
  }

  @override
  String get capacityRetryFailed => '重试失败压缩';

  @override
  String capacityPublishWithCount(Object count) {
    return '发布压缩结果（$count）';
  }

  @override
  String get capacityPublish => '发布压缩结果';

  @override
  String get capacityOptimizationTip => '优化会先生成预览，确认后才会替换当前内容，原内容仍可恢复。';

  @override
  String get capacityPreparingState => '正在准备资源状态。';

  @override
  String capacityTextCharacters(Object count) {
    return '正文 $count 字';
  }

  @override
  String capacitySectionsCount(Object count) {
    return '章节 $count';
  }

  @override
  String capacityPartsCount(Object count) {
    return '内容块 $count';
  }

  @override
  String capacityRevisionsCount(Object count) {
    return '历史记录 $count';
  }

  @override
  String capacityArchivedSize(Object count) {
    return '已归档 $count 字';
  }

  @override
  String capacityQueuedJobs(Object count) {
    return '待优化 $count';
  }

  @override
  String capacityPotentialSavings(Object count) {
    return '采纳候选后约可减少 $count 字。';
  }

  @override
  String get capacityStatusNormal => '正常';

  @override
  String get capacityStatusElastic => '弹性';

  @override
  String get capacityStatusOverflow => '超出预算';

  @override
  String get outlinePartPending => '待生成';

  @override
  String get outlinePartGenerated => '已生成';

  @override
  String get operationFailedRetry => '操作失败，请重试';

  @override
  String get resourceImportReturnToEdit => '返回修改';

  @override
  String get resourceImportConfirmSave => '确认保存';

  @override
  String get characterCardEditTitle => '编辑角色卡';

  @override
  String get characterCardCreateTitle => '新建角色卡';

  @override
  String get characterCardConfirmDeleteTitle => '确认删除';

  @override
  String characterCardConfirmDeleteMessage(Object name) {
    return '确定要删除角色卡「$name」吗？';
  }

  @override
  String characterCardDeleteFailed(Object error) {
    return '删除角色卡失败: $error';
  }

  @override
  String get characterCardNameRequired => '请至少填写姓名';

  @override
  String characterCardSaveFailed(Object error) {
    return '保存失败：$error';
  }

  @override
  String get characterCardInfoSection => '角色卡信息';

  @override
  String get characterCardWorldviewOptional => '契合世界观（可选）';

  @override
  String get noneOption => '无';

  @override
  String get characterCardAiAssistedCreation => 'AI 智能辅助编写角色卡';

  @override
  String get detailedMode => '详细模式';

  @override
  String get conciseMode => '简约模式';

  @override
  String get simpleMode => '简洁模式';

  @override
  String characterCardTargetValidChars(Object count, Object max) {
    return '目标有效内容 $count 字（最多 $max 字）';
  }

  @override
  String get characterCardSavedInStudioTip => '生成将在资源工作室中持续保存，可恢复并可追踪修改记录';

  @override
  String get characterCardRelateCharacterOptional => '关联已有角色（可选）';

  @override
  String get characterCardRelateCharacterHint => '点击选择要建立关系的已有角色（留空为独立角色）';

  @override
  String get characterCardNoOtherCharacters => '暂无其他角色';

  @override
  String get characterCardIndependentRole => '不关联（作为独立新角色构思）';

  @override
  String characterCardRelatedCount(Object count) {
    return '已关联 $count 位角色';
  }

  @override
  String get characterCardUnnamed => '未命名角色';

  @override
  String get characterCardBondRelation => '羁绊关系：';

  @override
  String get relationCompanion => '同伴 / 队友';

  @override
  String get relationChildhoodFriend => '青梅竹马';

  @override
  String get relationLover => '恋人 / 命定伴侣';

  @override
  String get relationMentor => '师徒 (师承/弟子)';

  @override
  String get relationRival => '宿敌 / 竞争对手';

  @override
  String get relationKin => '家族亲人';

  @override
  String get relationBenefactor => '救命恩人 / 报恩';

  @override
  String get relationEmployment => '雇佣关系';

  @override
  String get relationCustom => '自定义关系...';

  @override
  String get relationCustomDescLabel => '自定义关系描述';

  @override
  String get relationCustomDescHint => '例如：指腹为婚的未婚妻、异界灵魂共生者...';

  @override
  String get characterCardCoreKeywordHint =>
      '输入角色核心词或设定要求（如：冷傲银发女剑圣、背叛教会的流浪学者），留空则自由发挥...';

  @override
  String get opening => '正在打开...';

  @override
  String get aiRegenerate => 'AI 重新生成';

  @override
  String get aiFillIn => 'AI 填入';

  @override
  String get genderLabel => '性别';

  @override
  String get genderMale => '男';

  @override
  String get genderFemale => '女';

  @override
  String get genderOther => '其他';

  @override
  String get ageLabel => '年龄';

  @override
  String get customGenderLabel => '自定义性别';

  @override
  String get occupationLabel => '职业/身份';

  @override
  String get personalityLabel => '性格';

  @override
  String get backgroundStoryLabel => '背景故事';

  @override
  String get appearanceLabel => '外貌描述';

  @override
  String get physiqueFeaturesLabel => '身材体态与生理特征';

  @override
  String get inWorldSettingSection => '世界内设定';

  @override
  String get factionLabel => '所属势力';

  @override
  String get locationLabel => '活动地点 / 家乡';

  @override
  String get publicGoalLabel => '公开目标';

  @override
  String get hiddenMotiveLabel => '隐藏动机（供叙事使用）';

  @override
  String get abilitySourceLabel => '能力来源';

  @override
  String get abilityCostLabel => '能力代价 / 限制';

  @override
  String get taboosLabel => '禁忌（用“、”分隔）';

  @override
  String get relationsNoteLabel => '关系网络备注';

  @override
  String get characterCardDetailTitle => '角色卡详情';

  @override
  String get characterPersonalityTraits => '性格特征';

  @override
  String get characterDescription => '角色描述';

  @override
  String get characterCustomFields => '自添加项';

  @override
  String get characterAiAssistantCreateTitle => 'AI 助手创作角色卡';

  @override
  String get characterCreateAction => '创建角色卡';

  @override
  String characterMatchWorldview(Object name) {
    return '契合：$name';
  }

  @override
  String get worldviewCreateTitle => '新建世界观';

  @override
  String get worldviewEditTitle => '编辑世界观';

  @override
  String get worldviewDetailedTitle => '详细世界观';

  @override
  String get worldviewConciseTitle => '简洁世界观';

  @override
  String get worldviewOverviewDetailed => '世界观概述（计入详细设定总字数）';

  @override
  String get worldviewOverviewConcise => '世界观描述 (200~500字)';

  @override
  String worldviewDetailedLimitTip(Object count) {
    return '详细设定（总字数上限 $count 字，已确认内容会进入场景对话）';
  }

  @override
  String worldviewConfirmDeleteMessage(Object name) {
    return '确定要删除世界观「$name」吗？';
  }

  @override
  String get worldviewDeleteFailed => '删除世界观失败，请重试';

  @override
  String get worldviewAiAssistantTitle => 'AI 助手创作世界观';

  @override
  String get worldviewCreateAction => '创建世界观';

  @override
  String get originalTextContent => '原文内容';

  @override
  String get worldviewAiImportTip =>
      '粘贴任意文字（txt / md / HTML / 小说片段），AI 将自动提取并整合为世界观';

  @override
  String get pasteOriginalTextHint => '在此粘贴原文内容...';

  @override
  String get importModeLabel => '导入模式';

  @override
  String get preparingDeduction => '正在准备推演…';

  @override
  String deductionProgressChars(Object current, Object partial, Object target) {
    return '当前有效字数 $current / $target\n$partial';
  }

  @override
  String deductionProgressStage(Object current, Object partial, Object total) {
    return '正在推演第 $current/$total 阶段：$partial';
  }

  @override
  String get autoSaveToLibrary => '自动保存到资料库';

  @override
  String get expectedTotalCharacters => '期望总字数';

  @override
  String get adaptiveStageHelperText => '自适应分阶段高并发推演全套9大模块，提速数倍并自动保存';

  @override
  String get aiAnalyzeAction => 'AI 解析';

  @override
  String get selectImportModeTitle => '选择导入模式';

  @override
  String get selectImportModeDesc => '请选择本次角色资料的整理粒度。该选择会直接传给 AI。';

  @override
  String get conciseModeDesc => '使用简洁模式：保留身份、性格、外貌、核心经历和必要关系，避免扩写。';

  @override
  String get detailedModeDesc => '使用详细模式：在原文事实范围内完整整理身份、性格、外貌、经历、动机、信息与人物关系。';

  @override
  String batchImportTitle(Object kind) {
    return '批量 AI 导入$kind';
  }

  @override
  String get provideCharacterDataTitle => '提供角色资料';

  @override
  String get batchAiRecognitionTip => 'AI 会先识别人名，经你确认后逐个生成角色。';

  @override
  String get pleaseSelectWorldviewFirst => '请先选择世界观';

  @override
  String get selectRelatedCharacters => '选择关联角色';

  @override
  String relatedCharactersCount(Object count) {
    return '已关联 $count 个角色';
  }

  @override
  String get minTotalCharactersLabel => '最少总字数';

  @override
  String get maxTotalCharactersLabel => '最多总字数';

  @override
  String characterDataLabel(Object label) {
    return '$label资料';
  }

  @override
  String characterDataHint(Object label) {
    return '粘贴包含多个$label的章节、设定或人物小传……';
  }

  @override
  String get planningAction => '正在规划…';

  @override
  String get enterAiStudioAction => '进入 AI Studio';

  @override
  String selectCandidatesToImportTitle(Object count) {
    return '选择导入角色（$count）';
  }

  @override
  String importSelectedCharactersAction(Object count) {
    return '导入 $count 个角色';
  }

  @override
  String get selectCandidatesMultiTitle => '选择对象（可多选）';

  @override
  String get candidatesRelationTip => '生成资料会依据原文和这些已有角色建立可验证的关系。';

  @override
  String confirmRelateCharactersAction(Object count) {
    return '确认关联 $count 个角色';
  }

  @override
  String get pasteCharacterRawTextHint => '在此粘贴角色或 NPC 原文……';

  @override
  String get stagedDeepGenerationTip => '分阶段深度生成，并自动补全至目标完整度';

  @override
  String get worldviewModuleRules => '规则与边界';

  @override
  String get worldviewModuleState => '当前世界现状';

  @override
  String get worldviewModuleLocations => '地点与地理';

  @override
  String get worldviewModuleFactions => '势力与组织';

  @override
  String get worldviewModuleCustoms => '风俗与生活';

  @override
  String get worldviewModuleTimeline => '历史与时间线';

  @override
  String get worldviewModuleGlossary => '术语表';

  @override
  String get worldviewModuleConstraints => '创作约束';

  @override
  String get notSpecifiedOption => '不指定';

  @override
  String get unnamedWorldview => '未命名世界观';

  @override
  String get noExistingCharacterCards => '暂无已有角色卡';

  @override
  String selectedCharactersCount(int count) {
    return '已选 $count 个角色';
  }

  @override
  String get generatingEllipsis => '正在生成…';

  @override
  String get aiImportCharacterTitle => 'AI 导入角色';

  @override
  String get aiImportNpcTitle => 'AI 导入 NPC';

  @override
  String get relateExistingCharactersTitle => '关联已有角色';

  @override
  String get sceneBatchImportCharacterTitle => '场景角色批量导入';

  @override
  String get sceneBatchImportNpcTitle => '场景 NPC 批量导入';

  @override
  String get belongingWorldviewOptional => '所属世界观（可选）';

  @override
  String get relateCharactersOptional => '关联角色（可选）';

  @override
  String get associateWorldviewOptional => '关联世界观（可选）';

  @override
  String get resourceStatusCancelled => '已取消';

  @override
  String get dashboardWizardBadge => '向导定制';

  @override
  String get dashboardPresetBadge => '完整剧本';

  @override
  String get dashboardLibraryBadge => '全景资产';

  @override
  String get dashboardSettingsBadge => '模型配置';

  @override
  String get dashboardMyCharacterCards => '我的角色卡档案';

  @override
  String get dashboardNoCharacterCardsTitle => '暂无角色卡档案';

  @override
  String get dashboardNoCharacterCardsDesc =>
      '当前未创建任何角色。你可以在资料库中塑造你的主角或同伴人设，并在冒险时选择他们出战。';

  @override
  String get dashboardGoToCharacterLibrary => '前往角色卡库';

  @override
  String get dashboardDefaultProfession => '探险者';

  @override
  String get dashboardNoBackgroundDesc => '暂无背景描述';

  @override
  String get dashboardStartWithCharacter => '以此角色启程';

  @override
  String get dashboardMyWorldSettings => '我的世界设定';

  @override
  String get dashboardNoCustomWorldsTitle => '暂无自定义世界';

  @override
  String get dashboardNoCustomWorldsDesc =>
      '当前处于纯净白板状态，无任何预设世界。你可以在资料库中构想专属世界，或使用向导直接开启探索。';

  @override
  String get dashboardGoToLibrary => '前往资料库';

  @override
  String get dashboardNoWorldDesc => '暂无设定描述';

  @override
  String get dashboardStartWithWorld => '以此世界启程';

  @override
  String get dashboardToggleSidebar => '切换导航栏';

  @override
  String get dashboardConfigureApiKey => '配置密钥';

  @override
  String get dashboardSystemSettings => '系统设置';

  @override
  String get dashboardNoAdventuresTitle => '尚未开始任何场景冒险';

  @override
  String get dashboardNoAdventuresDesc => '选择上方的「向导定制」开启属于你的首部传奇';

  @override
  String get dashboardContinueAdventures => '继续未尽的冒险';

  @override
  String get dashboardUnnamedAdventure => '未命名冒险';

  @override
  String get dashboardDeleteAdventureTooltip => '删除冒险记录';

  @override
  String dashboardSavedAt(Object time) {
    return '存档于 $time';
  }

  @override
  String get dashboardContinueExploring => '继续探索';

  @override
  String get dashboardDeleteAdventureTitle => '删除冒险记录';

  @override
  String dashboardDeleteAdventureMessage(Object title) {
    return '确定要删除场景「$title」及其全部对话记录吗？此操作无法撤销。';
  }

  @override
  String dashboardAdventureDeleted(Object title) {
    return '已删除场景「$title」';
  }

  @override
  String get characterNameLabel => '姓名';

  @override
  String get presetScenesTitle => '预存场景工坊';

  @override
  String get presetScenesSubtitle => '开箱即用的完整冒险场景设定 · 一键启程开局';

  @override
  String get returnToDashboard => '返回大厅';

  @override
  String presetScriptCount(int count) {
    return '$count 个剧本';
  }

  @override
  String get presetWizardNewScene => '向导新建场景';

  @override
  String get presetRefreshList => '刷新列表';

  @override
  String get presetSearchHint => '搜索场景剧本、世界观或主角...';

  @override
  String get presetStatusReady => '已就绪';

  @override
  String get presetStatusDraft => '草稿';

  @override
  String get presetDefaultSceneName => '预存场景';

  @override
  String get presetNoMatchingScenes => '没有找到符合条件的预存场景';

  @override
  String get presetNoScenes => '暂无预存场景剧本';

  @override
  String get presetNoMatchingScenesHint => '请尝试更换搜索关键字或重置筛选';

  @override
  String get presetNoScenesHint => '通过四步向导可以一键生成包含世界观、主角、序章与行动分支的完整剧本预设';

  @override
  String get presetStartWizardAction => '启动向导新建场景';

  @override
  String get presetScriptDetail => '剧本详情';

  @override
  String get presetUnnamedScene => '未命名场景';

  @override
  String presetWorldviewLabel(Object name) {
    return '世界观：$name';
  }

  @override
  String get presetPreviewFullSetting => '完整设定预览';

  @override
  String get presetLoadIntoWizard => '载入向导微调';

  @override
  String get presetDeleteAction => '删除预存场景';

  @override
  String get presetDeleteTitle => '删除预存场景';

  @override
  String presetDeleteMessage(Object name) {
    return '确定要删除预存场景「$name」吗？\n删除后此剧本预设将无法恢复。';
  }

  @override
  String presetDeletedSuccess(Object name) {
    return '已删除场景「$name」';
  }

  @override
  String presetDeleteFailed(Object error) {
    return '删除失败: $error';
  }

  @override
  String presetLoadFailed(Object error) {
    return '加载预存场景失败：$error';
  }

  @override
  String get presetStartFailed => '启动预设场景失败，请稍后重试';

  @override
  String presetProtagonistSummary(
      Object name, Object gender, Object profession) {
    return '主角：$name ($gender · $profession)';
  }

  @override
  String get presetNoPlotSummary => '暂无剧情描述摘要';

  @override
  String get presetDataSimplifying => '数据结构精简中';

  @override
  String get presetQuickStartAction => '一键启程';

  @override
  String get presetMenuSemantic => '场景操作菜单';

  @override
  String get worldSelectionTitle => '选择世界观设定';

  @override
  String get worldSelectionSubtitle => '从资料库已构想的世界中挑选本次冒险的世界法则与背景设定';

  @override
  String get worldSelectionSearchHint => '搜索世界观名称、地理风貌或设定规则...';

  @override
  String get worldSelectionNoDesc => '暂无详细背景描述';

  @override
  String get worldSelectionTag => '世界设定';

  @override
  String get worldSelectionEmptyTitle => '暂无保存的世界观';

  @override
  String get worldSelectionEmptyDesc => '可在资料库中创建或在向导中直接输入自定义世界观';

  @override
  String get characterSelectionTitle => '选择冒险角色';

  @override
  String get characterSelectionSubtitle => '从资料库角色档案中挑选主角与队伍同伴';

  @override
  String get characterSelectionSearchHint => '搜索角色姓名、职业、性格或背景...';

  @override
  String get characterCompatNative => '当前世界';

  @override
  String get characterCompatUnbound => '未绑定';

  @override
  String get characterCompatCrossWorld => '来自其他世界';

  @override
  String characterAgeYears(Object age) {
    return '$age岁';
  }

  @override
  String characterPersonalityPrefix(Object personality) {
    return '性格: $personality';
  }

  @override
  String get characterSelectionEmptyTitle => '暂无可用的角色档案';

  @override
  String get characterSelectionEmptyDesc => '可在资料库中创建新角色，或在向导中使用 AI 自动构思';

  @override
  String get npcSelectionTitle => '选择初始 NPC';

  @override
  String get npcSelectionSubtitle => '挑选本次冒险登场的常驻 NPC（资料将独立冻结至当前冒险快照）';

  @override
  String get npcSelectionSearchHint => '搜索 NPC 姓名、身份或简述...';

  @override
  String get npcSelectionEmptyTitle => '资料库暂无 NPC';

  @override
  String get npcSelectionEmptyDesc => '可在资料库中添加 NPC，或直接跳过此步骤';

  @override
  String get unnamedNpc => '未命名 NPC';

  @override
  String resourceSelectedCount(int count) {
    return '已选择 $count 项';
  }

  @override
  String get resourceNoneSelected => '未选择任何项';

  @override
  String get resourceOneSelected => '已选定 1 项';

  @override
  String get confirmSelection => '确认选择';

  @override
  String get finishSelection => '完成选定';

  @override
  String get loadingResources => '正在加载可用资源...';

  @override
  String noMatchingResourceForQuery(Object query) {
    return '未找到包含「$query」的资源';
  }

  @override
  String get clearSearch => '清空搜索';

  @override
  String get configureApiKeyFirstForAi => '请先配置 API Key 以使用 AI 自动生成功能';

  @override
  String get aiGenerationNoValidContent => '生成未返回有效内容，请检查网络或重试';

  @override
  String get aiOpeningGeneratedSuccess => 'AI 序章与初始行动分支已自动生成并填入！';

  @override
  String aiGenerationFailed(Object error) {
    return '生成失败：$error';
  }

  @override
  String get openingPromptLabel => '序章要求 / 引导提示词 (可选)';

  @override
  String get openingPromptHint => '例如：以雨夜码头的悬疑氛围开场，让主角先察觉到异样…';

  @override
  String get aiGenerateOpeningAndBranches => 'AI 生成序章与分支';

  @override
  String get aiOpeningGeneratingProgress => 'AI 正在结合世界观与角色设定构思序章与行动分支…';

  @override
  String assemblyWorldviewSubtitle(Object worldview) {
    return '世界: $worldview';
  }

  @override
  String assemblyProtagonistSubtitle(Object name) {
    return '主角: $name';
  }

  @override
  String get assemblyConfigPageTitle => '序章剧情与分支配置';

  @override
  String get saveConfigAndContinue => '保存配置并继续';

  @override
  String get openingFirstSceneTitle => '开场第一幕剧情';

  @override
  String get openingFirstSceneDesc => '设定玩家进入冒险后的第一幕情境描述、遭遇或开篇转折。';

  @override
  String get openingFirstSceneHint => '描述冒险启程时的时刻、环境与突发危机...';

  @override
  String get pleaseEnterOpeningScene => '请输入开场剧情设定';

  @override
  String get initialActionBranchesTitle => '初始行动抉择分支 (可选)';

  @override
  String get initialActionBranchesDesc => '供玩家在开局时做出的三个行动分支，若留空将在进入后由 AI 动态生成。';

  @override
  String get actionBranch1 => '抉择分支 1';

  @override
  String get actionBranch1Hint => '例如：拔剑迎击袭来的黑影';

  @override
  String get actionBranch2 => '抉择分支 2';

  @override
  String get actionBranch2Hint => '例如：寻找掩体并呼唤同伴掩护';

  @override
  String get actionBranch3 => '抉择分支 3';

  @override
  String get actionBranch3Hint => '例如：仔细观察四周环境寻找逃生通道';

  @override
  String get difficultyAndGuidanceTitle => '推演难度与自定义指引';

  @override
  String get difficultyAndGuidanceDesc => '控制游戏运行的难度倾向与自定义提示词。';

  @override
  String get narrativeDifficulty => '叙事难度';

  @override
  String get difficultyNormalDesc => '普通 (标准叙事与平衡挑战)';

  @override
  String get difficultyCasualDesc => '休闲 (注重剧情与轻松沉浸)';

  @override
  String get difficultyHardDesc => '困难 (严苛规则与硬核抉择)';

  @override
  String get customGuidancePromptOptional => '自定义引导提示词 (可选)';

  @override
  String get customGuidancePromptHint => '例如：侧重悬疑侦探氛围、多增加环境感官细节描摹...';

  @override
  String get worldviewBoundRules => '已绑定世界观规则与地理法则';

  @override
  String get defaultContinentRules => '使用默认大陆规则';

  @override
  String readinessReadError(Object error) {
    return '无法读取资源就绪状态：$error';
  }

  @override
  String readinessRetryError(Object error) {
    return '资源重新准备失败：$error';
  }

  @override
  String startAdventureFailed(Object error) {
    return '启动冒险失败：$error';
  }

  @override
  String get unnamedHero => '无名勇者';

  @override
  String get adventurerRole => '冒险者';

  @override
  String get assemblyPreviewSubtitle => '全面检查世界观、角色阵容、NPC 与序章推演设定';

  @override
  String get enterAdventureAction => '踏入冒险';

  @override
  String get readinessCheckingTitle => '正在检查资源装配状态';

  @override
  String get readinessUnconfirmedTitle => '无法确认资源装配状态';

  @override
  String get readinessReadyTitle => '冒险要素装配完毕';

  @override
  String get readinessNotReadyTitle => '仍有资源未完成装配';

  @override
  String get readinessCheckingDesc => '正在读取世界观与角色的可用版本。';

  @override
  String get readinessUnconfirmedDesc => '资源状态读取失败，为安全起见暂不能确认可启动。';

  @override
  String get readinessReadyDesc => '点击下方「踏入冒险」即可冻结快照并开启全新旅程。';

  @override
  String get readinessNotReadyDesc => '缺少可用版本时无法踏入冒险，请先完成资源组装准备。';

  @override
  String get readinessRetrying => '正在重新准备…';

  @override
  String get readinessRetry => '重新准备';

  @override
  String worldviewSettingLabel(Object name) {
    return '世界设定: $name';
  }

  @override
  String get worldviewSettingTitle => '世界设定';

  @override
  String get readAloudWorldview => '朗读世界设定';

  @override
  String protagonistLeadLabel(Object name, Object className) {
    return '主控主角: $name ($className)';
  }

  @override
  String get mainProtagonistTitle => '主控主角';

  @override
  String personalityFeatureLabel(Object personality) {
    return '性格特点: $personality';
  }

  @override
  String backgroundStoryPrefix(Object background) {
    return '背景身世: $background';
  }

  @override
  String accompanyingCharactersCount(int count) {
    return '同行角色 ($count 位):';
  }

  @override
  String characterBondsCount(int count) {
    return '羁绊关系 ($count 条):';
  }

  @override
  String residentNpcsCount(int count) {
    return '常驻 NPC ($count 位)';
  }

  @override
  String get openingSceneAndDecisionsTitle => '序章开场与行动决策';

  @override
  String get openingSceneTitle => '序章开场';

  @override
  String get readAloudOpeningScene => '朗读序章开场';

  @override
  String get aiDynamicOpeningPlaceholder => '（由 AI 结合世界观与角色背景动态构思开场剧情）';

  @override
  String get initialActionDecisionsTitle => '初始行动决策分支:';

  @override
  String get noMatchingResourceTitle => '暂无匹配资源';

  @override
  String get noMatchingResourceDesc => '尝试输入其他搜索词或清除筛选条件';

  @override
  String get searchResourceNameOrDesc => '搜索资源名称或描述...';

  @override
  String get aiOpeningPanelTitle => 'AI 自动编写序章';

  @override
  String get aiOpeningPanelDesc =>
      '填写你的序章要求，AI 会结合世界观、主角与同伴角色卡、角色羁绊与 NPC 生成序章正文和初始行动分支；生成结果仍可手动修改。';

  @override
  String get regenerate => '重新生成';

  @override
  String get assemblyPipelineTitle => '冒险装配流水线';

  @override
  String get assemblyPipelineSubtitle => '步骤推进 · 页面化资源组装 · 零弹窗约束';

  @override
  String get phaseWorldview => '世界设定';

  @override
  String get phaseCharacters => '角色阵容';

  @override
  String get phaseOpening => '序章分支';

  @override
  String get phasePreview => '装配总览';

  @override
  String nextPhaseLabel(Object phase) {
    return '下一步：$phase';
  }

  @override
  String get previousStepAction => '上一步';

  @override
  String get pleaseSetWorldviewName => '请设定世界观名称';

  @override
  String get pleaseAddAtLeastOneCharacter => '请至少添加一个角色';

  @override
  String worldviewSelectedSuccess(Object name) {
    return '已选定世界观「$name」';
  }

  @override
  String get rosterUpdatedSuccess => '已更新阵容角色';

  @override
  String npcsSelectedCountSuccess(int count) {
    return '已选定 $count 位 NPC';
  }

  @override
  String get openingConfigSavedSuccess => '序章配置已保存';

  @override
  String characterJoinedPartySuccess(Object name) {
    return '角色「$name」已加入队伍';
  }

  @override
  String get worldviewLibraryLinkTitle => '世界观资料库关联';

  @override
  String get selectFromLibrary => '从资料库选择';

  @override
  String boundLibraryWorldviewId(Object id) {
    return '已绑定资料库世界观 ID: $id';
  }

  @override
  String get notBoundPresetHint => '未绑定预设，亦可直接在下方填写自定义世界设定。';

  @override
  String get worldviewDetailsSectionTitle => '世界观设定详情';

  @override
  String get worldviewDetailsSectionDesc => '设定大陆法则、地理背景、文明程度与势力格局。';

  @override
  String get worldNameRequiredLabel => '世界名称 *';

  @override
  String get worldNameHint => '例如：艾尔登大陆、赛博新都 2099、修真古界...';

  @override
  String get pleaseEnterWorldName => '请输入世界名称';

  @override
  String get lawsAndBackgroundLabel => '法则与背景设定';

  @override
  String get lawsAndBackgroundHint => '描述世界的魔法与科技体系、天体气候、阵营势力格局...';

  @override
  String get charactersAndNpcAssemblyTitle => '角色与 NPC 装配';

  @override
  String get selectCharactersFromLibrary => '从资料库选择角色';

  @override
  String selectNpcCountLabel(int count) {
    return '选择 NPC ($count)';
  }

  @override
  String get newCharacterAction => '新建角色';

  @override
  String rosterSectionTitle(int count) {
    return '登场角色阵容 ($count)';
  }

  @override
  String get rosterSectionDesc => '必须勾选 1 位作为主控主角；其他角色可赋予同伴、反派、导师等身份定位。';

  @override
  String get noCharactersAddedYet => '尚未添加登场角色';

  @override
  String get clickAboveToAddCharactersHint => '点击上方「从资料库选择角色」或「新建角色」';

  @override
  String get setAsMainProtagonist => '设为主控主角';

  @override
  String get scriptRoleOrientation => '剧本身份定位';

  @override
  String get openingAndRulesAdvancedConfigTitle => '序章与规则高级配置';

  @override
  String get fullscreenAdvancedConfig => '全屏高级配置';

  @override
  String get openingSceneContentTitle => '序章剧情内容';

  @override
  String get openingSceneContentDesc => '冒险开始的第一幕场景描写。';

  @override
  String get openingSceneContentHint => '描述主角登场时刻的环境与转折...';

  @override
  String get openingBranchesDesc => '供玩家在序章结束时选择的行动方向。';

  @override
  String branchNumberLabel(Object number) {
    return '分支 $number';
  }

  @override
  String actionOptionHint(Object number) {
    return '行动选项 $number...';
  }

  @override
  String get enterStandaloneFullscreenPreview => '进入独立全屏大预览';

  @override
  String get fullscreenPreviewButton => '全屏预览';

  @override
  String get customUnnamedWorld => '自定义未命名世界';

  @override
  String get unspecifiedProtagonist => '未指定主角';

  @override
  String companionRosterSummary(Object roster) {
    return '同伴阵容: $roster';
  }

  @override
  String selectedInitialNpcCount(int count) {
    return '已选定 $count 位初始 NPC';
  }

  @override
  String get firstSceneOpeningPlotTitle => '序章第一幕';

  @override
  String get aiDynamicOpeningSummary => '由 AI 结合背景自动展开';

  @override
  String get wizardWorldviewQuickBadge => '快速构思与资料库创作';

  @override
  String get wizardWorldviewPromptLabel => '世界观创意要求 / 题材偏好（可选）';

  @override
  String get wizardWorldviewPromptHint =>
      '例如：蒸汽朋克浮空城与古神低语、克苏鲁异界修真、深海末日城邦；留空则由 AI 自由发挥……';

  @override
  String get generationModeLabel => '生成模式';

  @override
  String get clearSettingsAction => '清空设定';

  @override
  String get wizardGenerateWorldviewAction => '开始 AI 自动编写';

  @override
  String get wizardRegenerateWorldviewAction => '重新生成世界观';

  @override
  String get wizardWorldviewGeneratingBrief => '正在构思世界观…';

  @override
  String get wizardWorldviewGeneratingDetailed => '正在分阶段推演…';

  @override
  String get saveToLibraryNow => '立即保存到资料库';

  @override
  String get wizardReusableBadge => '可随时复用';

  @override
  String get wizardWorldviewSaveDescription => '将此设定自动保存到世界观资料库，方便未来冒险随时调用和扩展。';

  @override
  String charactersSavedCount(int count) {
    return '已将 $count 个角色设定保存至资料库';
  }

  @override
  String characterCardSavedSuccess(String name) {
    return '角色「$name」已保存至资料库';
  }

  @override
  String get fullscreenSelectionAction => '全屏选择';

  @override
  String wizardCharacterAiSummary(String worldview) {
    return '描述角色性格或定位偏好。AI 会结合当前世界观「$worldview」构思主角或队伍成员并加入阵容；资料库创作可提供更完整的设定。';
  }

  @override
  String get wizardCharacterPromptLabel => '角色创意要求 / 人设偏好（可选）';

  @override
  String get wizardCharacterPromptHint =>
      '例如：沉稳的退魔剑士、活泼的白发治愈法师、冷酷的机械游侠；留空则由 AI 自由发挥……';

  @override
  String get wizardGenerateMainCharacterAction => '开始 AI 自动生成主角';

  @override
  String get wizardAddCharacterToRosterAction => '使用 AI 增添阵容角色';

  @override
  String get currentWorldviewLabel => '当前世界';

  @override
  String get removeRosterCharacter => '从阵容移除';

  @override
  String get clearRelatedCharacters => '清空关联';

  @override
  String wizardRelatedCharactersSummary(int count, String names) {
    return '已关联 $count 位角色：$names';
  }

  @override
  String get wizardRelationAssociationSummary => '新角色会与所选角色建立故事羁绊。';

  @override
  String charactersAddedToRoster(int count) {
    return 'AI 创作的 $count 个角色已加入冒险队伍';
  }

  @override
  String get roleMaleLead => '男主';

  @override
  String get roleFemaleLead => '女主';

  @override
  String get roleMaleOne => '男一';

  @override
  String get roleFemaleOne => '女一';

  @override
  String get roleMaleTwo => '男二';

  @override
  String get roleFemaleTwo => '女二';

  @override
  String get roleSupporting => '重要配角';

  @override
  String get roleVillain => '反派';

  @override
  String get roleMentor => '导师';

  @override
  String get roleFamily => '亲友';

  @override
  String get relationFriend => '朋友';

  @override
  String get relationEnemy => '敌人';

  @override
  String get relationStranger => '陌生人';

  @override
  String get mainProtagonistDescription => '主控主角（掌控行动与关键抉择）';

  @override
  String get protagonistShortTag => '主角';

  @override
  String get relationshipNetworkDescription =>
      '标明角色之间的羁绊、阵营立场与过往恩怨，AI 推演时会遵循这些关系。';

  @override
  String relationAssetReference(String suggestion) {
    return '关联资料：$suggestion（本次冒险可另行设定）';
  }

  @override
  String get relationDetailsHint => '描述两人的关系渊源或羁绊线索（可选）。';

  @override
  String get relationshipNetworkTitle => '角色羁绊与关系网';

  @override
  String get adventureReadyToEnterTitle => '准备就绪，踏入世界';

  @override
  String get worldviewSnapshotBoundSummary => '已完整绑定资料库世界观快照与规则法则';

  @override
  String get characterCardSnapshotBoundSummary => '已完整绑定资料库角色卡档案';

  @override
  String get characterCustomDesignedSummary => '已定制主角设定';

  @override
  String get unnamedCharacterA => '角色 A';

  @override
  String get unnamedCharacterB => '角色 B';

  @override
  String get savePreviewAction => '保存预览';

  @override
  String get previewTemplateNoStartHint => '仅保存为可恢复的预览模板，不会启动冒险。';

  @override
  String adventurePreviewName(String worldview) {
    return '$worldview · 冒险预览';
  }

  @override
  String adventurePreviewSavedMessage(String name) {
    return '已保存预览「$name」，可在预存场景工坊中恢复';
  }

  @override
  String get adventurePreviewExistsMessage => '已存在相同的冒险预览';

  @override
  String adventurePreviewSaveFailed(String error) {
    return '保存预览失败：$error';
  }

  @override
  String get wizardCharacterSaveDescription => '自动将阵容角色设定保存到角色资料库，方便在未来的冒险中复用。';

  @override
  String wizardMalformedCharacterCards(int count) {
    return '有 $count 张角色卡无法加载。';
  }

  @override
  String get conversationDeleteTitle => '删除场景对话';

  @override
  String conversationDeleteConfirm(int count) {
    return '确定删除选中的 $count 段场景对话吗？删除后历史对话与演变剧情将无法恢复。';
  }

  @override
  String conversationDeleteInterrupted(String error) {
    return '删除中断，请检查剩余会话后重试：$error';
  }

  @override
  String get conversationManageTitle => '管理过去的对话';

  @override
  String selectedItemsCount(int count) {
    return '已选 $count 项';
  }

  @override
  String get deletingAction => '删除中…';

  @override
  String get batchDeleteAction => '批量删除';

  @override
  String get noManagedConversations => '暂无可管理的场景对话';

  @override
  String get selectAllAction => '全选';

  @override
  String get sceneConversationLabel => '场景对话';

  @override
  String get messageEditUserTitle => '编辑你的消息';

  @override
  String get messageEditAssistantTitle => '编辑 AI 回复';

  @override
  String get messageEditUserSubtitle => '修改后将从该消息开始重新生成后续剧情';

  @override
  String get messageEditAssistantSubtitle => '编辑此条剧情文本，便于调整叙事或纠正细节';

  @override
  String get messageEditUserWarning => '注意：保存后该消息之后的所有历史推进将自动清除并根据新输入重新构思。';

  @override
  String get messageBodyLabel => '消息正文';

  @override
  String get messageEditDescription => '支持长文本自由编辑，可任意换行与排版';

  @override
  String get messageContentHint => '输入消息内容…';

  @override
  String get saveAndRegenerateAction => '修改并重新生成';

  @override
  String get saveChangesAction => '保存修改';

  @override
  String get messageContentRequired => '消息内容不能为空';

  @override
  String get messageUnchanged => '内容未作修改';

  @override
  String get messageNoLongerCurrent => '消息已不在当前对话中，请返回刷新';

  @override
  String get messageSavedAndRegenerated => '已保存并重新生成';

  @override
  String get messageChangesSaved => '已保存修改';

  @override
  String get messageSaveRetry => '保存失败，请重试';

  @override
  String get inventoryTitle => '背包';

  @override
  String get inventoryItemsTitle => '物品';

  @override
  String get equipmentTitle => '装备';

  @override
  String get legacyInventoryTitle => '旧版背包记录';

  @override
  String inventorySummary(int itemCount, int equipmentCount) {
    return '物品 $itemCount 件，装备 $equipmentCount 件';
  }

  @override
  String get quickMenuTooltip => '快捷菜单';

  @override
  String get characterStatusTitle => '角色状态';

  @override
  String get wordCountSettings => '字数设置';

  @override
  String get backToLobby => '返回大厅';

  @override
  String get restartAdventureTitle => '确认重开冒险';

  @override
  String get restartAdventureMessage => '将重置当前会话与冒险进度并返回主页。';

  @override
  String get restartAdventureAction => '重开';

  @override
  String get stopGenerationAction => '停止生成';

  @override
  String get textAdventureTitle => '文字冒险';

  @override
  String get searchConversationAction => '搜索对话';

  @override
  String get historyAndSidebarAction => '历史场景与侧栏';

  @override
  String get moreOptionsAction => '更多选项';

  @override
  String get replyLengthSetting => '回复长度';

  @override
  String get switchModelAction => '切换模型';

  @override
  String get promptSettingsAction => '提示词设置';

  @override
  String get wordCountAndDensitySettings => '字数与对话密度设置';

  @override
  String get reasoningCopiedToast => '思维链已复制到剪贴板';

  @override
  String get editedBadge => '（已编辑）';

  @override
  String get deleteMessageConfirmation => '删除后无法恢复，确定要删除吗？';

  @override
  String get removeBookmarkAction => '取消书签';

  @override
  String get addBookmarkAction => '添加书签';

  @override
  String get editMessageAction => '修改';

  @override
  String get regenerateMessageAction => '重新生成';

  @override
  String get assistantReplyLabel => 'AI 回复';

  @override
  String get selectModelForRegeneration => '选择模型重新生成';

  @override
  String get selectLanguageModel => '选择语言模型';

  @override
  String currentModelSummary(String model, String provider) {
    return '当前：$model（$provider）';
  }

  @override
  String get selectedModelLabel => '已选模型';

  @override
  String get defaultModelPlaceholder => '未选定（使用默认）';

  @override
  String get confirmApplyAction => '确认应用';

  @override
  String get selectValidModelError => '请选择或输入有效的模型名称';

  @override
  String get messageNoLongerCurrentError => '消息已不在当前对话中，请返回刷新';

  @override
  String get regenerationUserMessageMissingError => '无法重新生成：未找到有效的用户消息';

  @override
  String get regenerationTargetMissingError => '无法重新生成：未找到对应的用户消息';

  @override
  String get modelRegenerationStarting => '正在重新生成…';

  @override
  String modelSwitchedSuccess(String model) {
    return '已切换至模型：$model';
  }

  @override
  String get modelSwitchFailed => '模型切换失败，请重试';

  @override
  String get serviceProviderSection => '服务提供商';

  @override
  String get serviceProviderDescription => '选择官方 API 服务商或本地/第三方兼容服务';

  @override
  String get llmProviderLabel => 'LLM 提供商';

  @override
  String get recentModelsSection => '最近使用';

  @override
  String get recentModelsDescription => '快速切换此前在此设备使用过的模型';

  @override
  String get recommendedModelsSection => '推荐在服模型';

  @override
  String get recommendedModelsDescription => '针对文学创作与角色扮演优化的核心在服模型';

  @override
  String get customModelSection => '自定义模型名称';

  @override
  String get deepseekCustomModelDescription => '如需调用 DeepSeek 其他专属模型，可在此手动输入';

  @override
  String get otherCustomModelDescription =>
      '输入第三方兼容端点支持的模型标识（例如 gpt-4o、claude-3-5-sonnet 等）';

  @override
  String get modelNamePlaceholder => '请输入模型名称…';

  @override
  String customModelSelected(String model) {
    return '已选定自定义模型：$model';
  }

  @override
  String get adventureBlankSlateTitle => '纯净冒险白板';

  @override
  String get adventureBlankSlateDescription =>
      '当前场景尚未产生任何对话或行动记录。\n在下方输入你的行动、提出一个探索方向，开始这段冒险。';

  @override
  String get beginAdventureAction => '启程行动';

  @override
  String get deepSeekFlashModelSubtitle =>
      'DeepSeek V4.1 Flash 最新推荐 · 多模态 · 支持深度思考';

  @override
  String get deepSeekLegacyModelSubtitle => '旧版模型，建议迁移到 DeepSeek V4.1 Flash';

  @override
  String get deleteDetectedStatusTitle => '删除检测状态';

  @override
  String confirmDeleteDetectedStatus(String name) {
    return '确定要删除「$name」该检测状态吗？';
  }

  @override
  String get statusNameLabel => '检测状态名称 *';

  @override
  String get statusNameExamples => '例如：理智值(SAN)、好感度、精神污染、饱食度';

  @override
  String get measurementModeLabel => '计量模式：';

  @override
  String get numericGaugeMode => '数值进度槽 (0~100)';

  @override
  String get phaseDescriptionMode => '阶段描述型';

  @override
  String get currentValueLabel => '当前数值';

  @override
  String get maxValueLabel => '最大上限';

  @override
  String get currentPhaseLabel => '当前阶段/描述';

  @override
  String get currentPhaseExamples => '例如：正常、轻度侵蚀、微醺、狂化中';

  @override
  String get chooseStatusIcon => '选择状态图标：';

  @override
  String get statusRuleLabel => '检测规则 / 剧情判定说明 (可选)';

  @override
  String get statusRuleHint => '例如：低于20时陷入恐慌；投骰成功保持理智，失败触发疯狂幻觉';

  @override
  String get storyImportanceLabel => '剧情重要度：';

  @override
  String get statusNameRequiredError => '请输入检测状态名称';

  @override
  String get addDetectedStatusAction => '添加检测状态';

  @override
  String detectedStatusesCount(int count) {
    return '自定义检测状态 ($count)';
  }

  @override
  String get combatAdventureMatrix => '战斗与探险能力矩阵';

  @override
  String get physicalAttackStat => '物理攻击 (ATK)';

  @override
  String get baseDefenseStat => '基础防御 (DEF)';

  @override
  String get agilitySpeedStat => '机敏速度 (SPD)';

  @override
  String get goldStat => '持有金币 (Gold)';

  @override
  String get availableSkillPointsStat => '可用技能点';

  @override
  String get currentSceneCoordinatesStat => '当前场景坐标';

  @override
  String get openInventoryAction => '打开背包仓库';

  @override
  String get profileIdentityTitle => '📜 身份与职业定位';

  @override
  String get profileBackgroundTitle => '📖 背景经历与渊源';

  @override
  String get profileWorldviewTitle => '🌍 所处世界观';

  @override
  String get profilePersonalityTitle => '🎭 性格特质';

  @override
  String get profileRelationshipsTitle => '🤝 羁绊与关系';

  @override
  String get profileAppearanceTitle => '✨ 外貌与体态特征';

  @override
  String get checkAction => '检定';

  @override
  String levelRoleSummary(int level, String role) {
    return 'Lv.$level · $role';
  }

  @override
  String get editDetectedStatusTitle => '编辑检测状态';

  @override
  String get noCustomDetectedStatuses => '暂无自定义检测状态';

  @override
  String get detectedStatusesEmptyDescription =>
      '支持自定义理智值(SAN)、好感度、精神污染、饱食度、魔力过载等任意冒险状态。';

  @override
  String get energyLabel => '能量';

  @override
  String get combatStatsTitle => '战斗属性';

  @override
  String get currentValuePrefix => '当前值：';

  @override
  String get currentPhaseWithThoughtsLabel => '当前状态阶段 / 心里想法';

  @override
  String get phaseNotTriggered => '（尚未触发阶段判定）';

  @override
  String statusRulePrefix(String rule) {
    return '📌 规则判定：$rule';
  }

  @override
  String get companionsTab => '核心状态';

  @override
  String get equipmentTab => '装备随身';

  @override
  String get profileTab => '身世羁绊';

  @override
  String currentExplorationRegion(String scene) {
    return '当前探索区域：$scene';
  }

  @override
  String mainStoryChapter(int chapter) {
    return '主线冒险者 · 第 $chapter 篇章';
  }

  @override
  String relationshipLabel(String relation) {
    return '关系：$relation';
  }

  @override
  String affinityScoreLabel(int affinity) {
    return '❤️ 好感度：$affinity';
  }

  @override
  String get healthPointsLabel => '生命值 (HP)';

  @override
  String get lifeForceLabel => '生命活力';

  @override
  String get magicPointsLabel => '精神魔法 (MP)';

  @override
  String get focusLabel => '专注力';

  @override
  String get actionEnergyLabel => '行动能量 (Energy)';

  @override
  String get tiredStatus => '⚠️ 疲惫';

  @override
  String get goodStatus => '良好';

  @override
  String get experienceLabel => '升级经验 (EXP)';

  @override
  String nextLevelExperience(int count) {
    return '下一级需 $count';
  }

  @override
  String skillPointsValue(int count) {
    return '$count 点';
  }

  @override
  String equippedGearCount(int count) {
    return '⚔️ 当前穿戴装备 ($count)';
  }

  @override
  String get noEquippedGear => '暂未穿戴专属装备，可在背包或商店中获取装备提升战力。';

  @override
  String gearSlotQuality(String slot, String quality) {
    return '部位：$slot · 品质：$quality';
  }

  @override
  String get carriedItemsTitle => '🎒 随身物品与材料';

  @override
  String get noCarriedItems => '当前随身行囊无特殊物品。';

  @override
  String get sharedPartyInventory => '📦 公共队伍行囊：';

  @override
  String get detectedStatusFormDescription =>
      '自定义在冒险故事中持续检测与判定的状态（支持进度槽、判定规则与投骰检定）';

  @override
  String get statusPresetsHeading => '💡 快捷预设灵感（点击一键填入）：';

  @override
  String get explorerRole => '探险者';

  @override
  String get startingTown => '起点城镇';

  @override
  String get defaultProtagonistProfile => '独自探索未知边界的冒险者，具备机变行动与剧情决策权。';

  @override
  String get defaultProtagonistBackground => '在风起云涌的世界中踏上征程，经历未知的命运齿轮推演。';

  @override
  String get defaultWorldviewDescription => '沉浸式角色扮演叙事空间，随剧情发展实时推演环境演变。';

  @override
  String get defaultCompanionPersonality => '性格深沉，在历险旅程中逐步展现内心真正的渴望。';

  @override
  String genderTag(String value) {
    return '性别：$value';
  }

  @override
  String heightTag(String value) {
    return '身高：$value';
  }

  @override
  String hairstyleTag(String value) {
    return '发型：$value';
  }

  @override
  String skinToneTag(String value) {
    return '肤色：$value';
  }

  @override
  String facialFeaturesTag(String value) {
    return '面部：$value';
  }

  @override
  String get aliveStatus => '💚 状态正常';

  @override
  String get incapacitatedStatus => '💀 失去行动力';

  @override
  String companionRelationshipSummary(String relation, int affinity) {
    return '与主角设定为【$relation】关系。当前好感度评分：$affinity/100。';
  }

  @override
  String get diceCriticalSuccess => '大成功！判定完美达成！';

  @override
  String get diceCriticalFailure => '大失败！遭遇严重失误或异常反噬！';

  @override
  String get diceSuccess => '检定成功！成功抵抗异常并维持状态稳定。';

  @override
  String get diceFailure => '检定失败！受到状态影响或负面效果侵扰。';

  @override
  String get diceCheckCriticalSuccess => '大成功 (暴击)！极限突破达成！';

  @override
  String get diceCheckCriticalFailure => '大失败！判定彻底失败！';

  @override
  String get diceCheckPassed => '检定通过！状态运转顺利。';

  @override
  String get diceCheckFailed => '检定未通过！受到阻碍或负面波及。';

  @override
  String diceTargetValue(int current, int maximum) {
    return '检定目标值：$current / $maximum';
  }

  @override
  String diceCurrentStatus(String status) {
    return '当前状态：$status';
  }

  @override
  String diceRuleDescription(String rule) {
    return '判定规则：$rule';
  }

  @override
  String get d100PercentileDie => 'D100 百分比骰';

  @override
  String get d20Die => 'D20 骰';

  @override
  String get rollCheckAction => '投掷检定骰';

  @override
  String get rerollAction => '重新投掷';

  @override
  String get syncResultToAdventure => '同步至冒险剧情';

  @override
  String diceResultPoints(String icon, int value, String denominator) {
    return '$icon 掷出点数：$value $denominator';
  }

  @override
  String get diceResultWillBeSent => '检定结果将作为一条用户消息发送。';

  @override
  String diceResultMessage(String status, String rule, String character,
      int roll, String target, String verdict) {
    return '【状态检测】$character 进行了「$status」检定：🎲 掷出 $roll ($target) → 【$verdict】！$rule';
  }

  @override
  String get allItemsFilter => '全部';

  @override
  String get consumableItemType => '消耗品';

  @override
  String get equipmentItemType => '装备物品';

  @override
  String get materialItemType => '材料';

  @override
  String get questItemType => '任务物品';

  @override
  String get weaponSlot => '武器';

  @override
  String get armorSlot => '护甲';

  @override
  String get accessorySlot => '饰品';

  @override
  String get specialSlot => '特殊';

  @override
  String get commonQuality => '普通';

  @override
  String get uncommonQuality => '优秀';

  @override
  String get rareQuality => '稀有';

  @override
  String get epicQuality => '史诗';

  @override
  String get legendaryQuality => '传说';

  @override
  String get emptyInventoryTitle => '背包是空的';

  @override
  String get emptyInventoryDescription => '剧情中获得的物品会显示在这里。';

  @override
  String get deepThinkingStatus => '正在深度思考…';

  @override
  String get reasoningExpandedLabel => '思考过程 (点击收起)';

  @override
  String get reasoningCollapsedLabel => '已深度思考 (点击展开思维链)';

  @override
  String get thinkingInProgressStatus => '正在思考中…';

  @override
  String get reasoningUnavailableLabel => '（无记录）';

  @override
  String get copyReasoningAction => '复制思考过程';

  @override
  String get writingStoryStatus => '正在撰写剧情…';

  @override
  String get dialogueReplyLengthSettingsTitle => '调整场景对话回复长度';

  @override
  String dialogueCurrentSelection(String id, String name, String range) {
    return '当前选择：$id · $name ($range)';
  }

  @override
  String dialogueWordsAbove(int minWords) {
    return '$minWords 字以上';
  }

  @override
  String get dialogueLevelFast => '极速';

  @override
  String get dialogueLevelConcise => '简洁';

  @override
  String get dialogueLevelStandard => '标准';

  @override
  String get dialogueLevelDetailed => '详细';

  @override
  String get dialogueLevelDeep => '深度';

  @override
  String get dialogueLevelProduction => '生产';

  @override
  String get dialogueLevelFastDesc => '只保留关键反馈，适合快速确认。';

  @override
  String get dialogueLevelConciseDesc => '简短推进，适合轻量互动。';

  @override
  String get dialogueLevelStandardDesc => '默认模式，兼顾速度和沉浸感。';

  @override
  String get dialogueLevelDetailedDesc => '提供更完整的描写和互动。';

  @override
  String get dialogueLevelDeepDesc => '强调铺垫、心理和场景层次。';

  @override
  String get dialogueLevelProductionDesc => '长文本生成，适合严肃写作。';

  @override
  String get adventureRefreshUnavailable => '生成中或场景不可用，暂不能刷新';

  @override
  String get sessionOfflineHint => '离线 — 网络连接不可用';

  @override
  String get sessionInputHint => '描述你的行动或对话…';

  @override
  String get messageGestureHint => '右滑消息可重试 · 左滑可删除 · 长按可编辑或收藏';

  @override
  String get adventureAssistantName => '冒险助手';

  @override
  String get currentUserDisplayName => '我';

  @override
  String get unknownRegion => '未知地域';

  @override
  String get deepThinkingBadge => '深度思考';

  @override
  String get supportingCharacterRole => '配角';

  @override
  String get autoSwitchCharacterTooltip => '自动切换角色';

  @override
  String get sessionSettlingStatus => '正在生成选项与结算状态…';

  @override
  String get aiReplyLabel => 'AI 回复';

  @override
  String sectionValidationPassed(String title) {
    return '「$title」校验通过';
  }

  @override
  String sectionValidationFailed(String title, int count) {
    return '「$title」校验未通过：$count 项问题';
  }

  @override
  String get sectionValidationComplete => '校验完成';

  @override
  String sectionRegenerated(String title, int completed, int total) {
    return '「$title」已重新生成 $completed/$total 个段落';
  }

  @override
  String sectionRegenerationFailed(String title, String error) {
    return '「$title」生成中止：$error';
  }

  @override
  String get sectionGenerationComplete => '生成完成';

  @override
  String get capacityNoCompressionNeeded => '没有需要压缩的章节。';

  @override
  String get capacityCompressionAlreadyPublished => '该压缩候选已发布，未重复改动正文。';

  @override
  String capacityCompressionPublished(int savedCharacters) {
    return '已发布压缩候选，约节省 $savedCharacters 字；压缩前的正文保留在历史版本中。';
  }

  @override
  String capacityRetryBlockedByActiveTarget(int count) {
    return '$count 个失败任务的目标已有进行中的压缩，因此已跳过。';
  }

  @override
  String capacityRetryBudgetExhausted(int count) {
    return '没有可重试的压缩任务；$count 个任务已达到重试上限。';
  }

  @override
  String get capacityRetryUnavailable => '没有可重试的压缩任务。';

  @override
  String capacityCompressionRunSummary(int succeeded, int failed, int requeued,
      int activeSkipped, int exhaustedSkipped) {
    return '生成候选 $succeeded 个；失败任务 $failed 个；重试入队 $requeued 个；因目标已有压缩而跳过 $activeSkipped 个；达到重试上限而跳过 $exhaustedSkipped 个。候选需确认后才会替换正文；失败任务不会修改原文。';
  }

  @override
  String get revisionCauseManualSave => '手动保存';

  @override
  String get revisionCauseGeneration => 'AI 生成';

  @override
  String get revisionCausePlanning => '大纲规划';

  @override
  String get revisionCauseRegeneration => '重新生成';

  @override
  String get revisionCauseCompression => '语义压缩';

  @override
  String get revisionCauseRestore => '版本恢复';

  @override
  String get revisionCauseMigration => '数据迁移';

  @override
  String get revisionCauseDeletion => '删除前快照';

  @override
  String get revisionUnknownDate => '日期未知';

  @override
  String get revisionAlreadyCurrent => '当前内容已经是该版本。';

  @override
  String revisionRestored(String sourceCause) {
    return '已恢复到「$sourceCause」版本。';
  }

  @override
  String revisionItemSubtitle(String date, int nodeCount, int charCount) {
    return '$date · $nodeCount 个节点 · $charCount 字';
  }

  @override
  String resourceRevisionOperationFailed(String error) {
    return '版本操作失败：$error';
  }
}

/// The translations for Chinese, using the Han script (`zh_Hant`).
class AppLocalizationsZhHant extends AppLocalizationsZh {
  AppLocalizationsZhHant() : super('zh_Hant');

  @override
  String get appTitle => 'LT 靈境';

  @override
  String get pageLoadError => '頁面載入出錯';

  @override
  String get reloadAction => '重新載入';

  @override
  String get loadingEnvironment => '環境載入中...';

  @override
  String testingProviderConnection(String provider) {
    return '測試 $provider...';
  }

  @override
  String get modelConnectionFailed => '模型連線失敗，請檢查設定';

  @override
  String get apiKeyNotConfiguredPrompt => '尚未配置 API 金鑰，可在設定中完成配置';

  @override
  String get goToSettings => '前往設定';

  @override
  String get createAdventureFailed => '建立場景失敗，請稍後重試';

  @override
  String get navExplore => '探索';

  @override
  String get navLibrary => '資料庫';

  @override
  String get navSettings => '設定';

  @override
  String get sidebarNewAdventure => '新建冒險';

  @override
  String get sidebarRecent => '最近';

  @override
  String get sidebarManageConversations => '批次管理歷史對話';

  @override
  String get sidebarEmptyConversations => '暫無歷史對話';

  @override
  String get sidebarUnnamedScene => '未命名場景';

  @override
  String get sidebarDeleteDialogTitle => '刪除場景對話';

  @override
  String sidebarDeleteDialogMessage(String title) {
    return '確定刪除「$title」嗎？\n刪除後歷史對話與演變劇情將無法復原。';
  }

  @override
  String get sidebarReturnHome => '返回探索大廳';

  @override
  String get sidebarExpand => '展開側邊欄';

  @override
  String get sidebarCollapse => '收起側邊欄';

  @override
  String get sidebarClose => '關閉側邊欄';

  @override
  String get brandSubtitle => '敘事與世界演變工坊';

  @override
  String get serviceConnected => '官方在線';

  @override
  String get serviceNotConfigured => '未配置金鑰';

  @override
  String get officialOnline => '在線';

  @override
  String get languageSetupTitle => '選擇語言';

  @override
  String get languageSetupSubtitle => '請選擇應用程式顯示語言';

  @override
  String get languageSettingTitle => '語言';

  @override
  String get languageSettingSubtitle => '應用程式顯示語言';

  @override
  String get confirmAction => '確定';

  @override
  String get cancelAction => '取消';

  @override
  String get deleteAction => '刪除';

  @override
  String get saveAction => '儲存';

  @override
  String get continueAction => '繼續';

  @override
  String get closeAction => '關閉';

  @override
  String get doneAction => '完成';

  @override
  String get editAction => '編輯';

  @override
  String get retryAction => '重試';

  @override
  String get copyAction => '複製';

  @override
  String get settingsCenter => '設定中心';

  @override
  String get settingsSystemConfig => '系統配置';

  @override
  String get settingsReturnHome => '返回大廳';

  @override
  String get settingsReturnList => '返回設定列表';

  @override
  String get settingsPreferencesCategory => '偏好分類';

  @override
  String get settingsCoreEngine => '靈境核心引擎';

  @override
  String get settingsStorageType => 'SQLite · 本地加密優先';

  @override
  String get tabModelApi => '模型與 API';

  @override
  String get tabModelApiSubtitle => '服務商與金鑰配置';

  @override
  String get tabSessionParams => '對話參數';

  @override
  String get tabSessionParamsSubtitle => '取樣率與深度思考';

  @override
  String get tabThemeAppearance => '主題配色';

  @override
  String get tabThemeAppearanceSubtitle => '深淺與主題色彩';

  @override
  String get tabDataManagement => '資料管理';

  @override
  String get tabDataManagementSubtitle => 'Token 統計與儲存';

  @override
  String get configCategory => '配置分類';

  @override
  String get apiServiceConnected => '大模型服務已連線';

  @override
  String get apiServiceConnectedDesc => '點選管理服務商、模型與端點';

  @override
  String get apiServiceDisconnectedDesc => '點選配置 API 金鑰以啟動推演';

  @override
  String get providerConfigTitle => '模型提供商與 API 配置';

  @override
  String get providerConfigSubtitle => '配置大模型提供商、端點位址與安全金鑰';

  @override
  String get testConnection => '測試連線';

  @override
  String get testingConnection => '正在測試...';

  @override
  String get inputApiKeyHint => '請先輸入有效的 API 金鑰';

  @override
  String connectionSuccess(int time) {
    return '連線成功！耗時 ${time}ms，服務狀態極佳。';
  }

  @override
  String get connectionFailed => '連線失敗，請檢查金鑰是否正確及網路是否暢通。';

  @override
  String connectionFailedWithReason(String error) {
    return '連線失敗: $error';
  }

  @override
  String get apiKeyLabel => 'API 金鑰 (API Key)';

  @override
  String get apiKeyPlaceholder => '請輸入 API 金鑰';

  @override
  String get customEndpointLabel => '自訂端點 (Base URL)';

  @override
  String get customEndpointPlaceholder => '自訂端點 URL';

  @override
  String get modelLabel => '模型名稱';

  @override
  String get modelPlaceholder => '輸入模型名稱';

  @override
  String get customModelNote => '使用自訂模型端點';

  @override
  String get modelParamsSectionTitle => '對話模型參數';

  @override
  String get modelParamsSectionSubtitle => '精細微調內容生成取樣溫度、上下文預算與深度思考推理模式';

  @override
  String get systemPromptLabel => '自訂系統提示詞';

  @override
  String get systemPromptPlaceholder => '輸入系統提示詞以指導 AI 扮演角色與行為風格...';

  @override
  String get authorsNoteLabel => '作者註釋 (Author\'s Note)';

  @override
  String get authorsNotePlaceholder => '在最近回合中注入強效上下文提醒...';

  @override
  String authorsNoteDepthLabel(int depth) {
    return '插入深度：距底 $depth 回合';
  }

  @override
  String authorsNoteFrequencyLabel(int freq) {
    return '生效頻率：每 $freq 回合觸發一次';
  }

  @override
  String get dialogueLevelLabel => '文學修辭風格與深度';

  @override
  String temperatureLabel(String value) {
    return '取樣溫度 (隨機度): $value';
  }

  @override
  String get enableThinkingLabel => '啟用深度思考模式 (Deep Thinking)';

  @override
  String get enableThinkingSubtitle => '開啟後模型在生成劇情前輸出可摺疊的思維鏈推演過程';

  @override
  String get reasoningEffortLabel => '思考強度 (Reasoning Effort)';

  @override
  String get quickModeLabel => '極速模式';

  @override
  String get quickModeSubtitle => '跳過打字機流式動畫，快速呈現完整回覆';

  @override
  String get appearanceSectionTitle => '外觀與視覺主題';

  @override
  String get appearanceSectionSubtitle => '自訂介面的色彩主題、深淺模式與閱讀字號';

  @override
  String get themeModeLabel => '主題模式';

  @override
  String get themeLight => '明亮';

  @override
  String get themeDark => '暗黑';

  @override
  String get themeSystem => '跟隨系統';

  @override
  String get themeColorPalette => '主題色盤';

  @override
  String get themeColorPaletteHint => '點選即時換膚';

  @override
  String chatFontSizeLabel(int size) {
    return '敘事文字字號: $size pt';
  }

  @override
  String get chatFontCompact => '小巧精煉';

  @override
  String get chatFontStandard => '標準閱讀';

  @override
  String get chatFontSpacious => '寬適大字';

  @override
  String get previewTypographyTitle => '閱讀排版即時效果';

  @override
  String get previewTypographySample =>
      '「靈境敘事」—— 在浩瀚無垠的世界線交織中，你的每一個抉擇都將掀起命運的波瀾。暗流湧動的地下城、懸浮天際的機械遺跡，一切傳奇皆自此啟程。';

  @override
  String get readingScrollTitle => '閱讀與捲動控制';

  @override
  String get readingScrollSubtitle => '控制文字生成與閱讀時的螢幕捲動體驗';

  @override
  String get autoScrollLabel => '生成時自動跟隨捲動';

  @override
  String get autoScrollSubtitleOn => '開啟狀態：生成新內容時螢幕持續自動捲到底部最新語句。';

  @override
  String get autoScrollSubtitleOff =>
      '預設推薦（閱讀優先）：生成新內容時螢幕保持平穩，方便您從開頭不受打擾地讀完；滑動完全受您控制。';

  @override
  String get dataManagementTitle => '資料管理與用量統計';

  @override
  String get dataManagementSubtitle => '查看 Token 消耗、語音 TTS 播報設定與儲存管理';

  @override
  String get tokenUsageTitle => '本地 Token 消耗估算';

  @override
  String get sessionTokensLabel => '本次對話消耗';

  @override
  String get totalTokensLabel => '歷史累計持久化';

  @override
  String get readAloudSectionTitle => '語音訊息朗讀 (TTS)';

  @override
  String get readAloudSupportedPlatform => '目前平台支援系統語音朗讀，可在對話與創作工作台中使用。';

  @override
  String get readAloudUnsupportedPlatform => '目前平台不支援語音朗讀。';

  @override
  String get readAloudEnable => '啟用語音朗读';

  @override
  String get readAloudEnableSubtitle => '支援在對話、創作工作台與組裝預覽中朗讀內文';

  @override
  String get readAloudAutoRead => '完成時自動朗讀';

  @override
  String get readAloudAutoReadSubtitle => '當 AI 生成完完整劇情後自動進行語音播報';

  @override
  String get readAloudRate => '語速';

  @override
  String get readAloudPitch => '音調';

  @override
  String get readAloudVolume => '音量';

  @override
  String get readAloudLanguage => '朗讀語言';

  @override
  String get readAloudAutoDetect => '自動偵測';

  @override
  String get readAloudAutoDetectHint => '根據每段內文自動選擇可用的系統語音語言。';

  @override
  String get readAloudFixedHint => '所有內文都使用所選語言朗讀。';

  @override
  String get readAloudUnsupportedLanguage => '（不支援）';

  @override
  String readAloudAvailableLanguagesCount(int count) {
    return '系統可用語言：$count 種';
  }

  @override
  String get readAloudDisabledInSettings => '語音朗讀已在設定中關閉';

  @override
  String get readAloudStop => '停止朗讀';

  @override
  String get readAloudStart => '朗讀';

  @override
  String get diagnosticExportTitle => '診斷資料匯出';

  @override
  String get diagnosticExportSubtitle => '僅匯出目前冒險分支最近 30 回合；API 憑證與隱藏推理不會寫入檔案。';

  @override
  String get exportDiagnosticJson => '匯出診斷對話 JSON';

  @override
  String get cacheStorageTitle => '快取與儲存管理';

  @override
  String get clearCache => '清除臨時快取';

  @override
  String get clearCacheSuccess => '已清除對話臨時快取與重置計數器';

  @override
  String get clearAllData => '清除全部本地資料';

  @override
  String get clearDataDialogTitle => '重設所有本地資料';

  @override
  String get clearDataDialogMessage => '確定要清除所有本地冒險、卡片與快取資料嗎？\n此操作不可復原。';

  @override
  String get exportChatTitle => '匯出對話';

  @override
  String get importChatTitle => '匯入對話';

  @override
  String get dashboardHeroTitle => '靈境 · 探索與敘事工坊';

  @override
  String get dashboardHeroSubtitle => '互動小說與沉浸式 RPG 敘事空間';

  @override
  String get dashboardWizardCardTitle => '四步精靈自訂';

  @override
  String get dashboardWizardCardDesc => '白板起步，自主設定世界觀、角色卡、序章與初始行動。';

  @override
  String get dashboardWizardCardAction => '啟動精靈';

  @override
  String get dashboardPresetCardTitle => '預存場景工坊';

  @override
  String get dashboardPresetCardDesc => '瀏覽已構建的預設冒險劇本，支援一鍵啟程或微調。';

  @override
  String get dashboardPresetCardAction => '查看預存場景';

  @override
  String get dashboardLibraryCardTitle => '資料庫';

  @override
  String get dashboardLibraryCardDesc => '查閱與管理你構想的世界觀預設、角色卡與 NPC 檔案。';

  @override
  String get dashboardLibraryCardAction => '管理資料庫';

  @override
  String get dashboardSettingsCardTitle => '系統設定中心';

  @override
  String get dashboardSettingsCardDesc => '配置大模型連線參數、外觀主題與歷史資料管理。';

  @override
  String get dashboardSettingsCardAction => '進入設定';

  @override
  String get recentAdventuresTitle => '最近冒險';

  @override
  String get noRecentAdventures => '暫無歷史冒險，點選啟動精靈開啟新的征程';

  @override
  String get continueAdventure => '繼續冒險';

  @override
  String get featuredWorldviews => '精選世界觀';

  @override
  String get featuredCharacters => '精選角色';

  @override
  String get resourceLibraryTitle => '資料庫';

  @override
  String get resourceLibrarySubtitle => '瀏覽與管理你的世界觀、角色卡與劇情範本';

  @override
  String get createResourceAction => '新建資源';

  @override
  String get searchResources => '搜尋資源...';

  @override
  String get allResources => '全部';

  @override
  String get worldviewsTab => '世界觀';

  @override
  String get charactersTab => '角色';

  @override
  String get templatesTab => '範本';

  @override
  String get recycleBinTitle => '資源回收筒';

  @override
  String get emptyRecycleBin => '回收站是空的';

  @override
  String get restoreAction => '恢復';

  @override
  String get permanentlyDelete => '永久刪除';

  @override
  String get resourceStudioTitle => '創作工作台';

  @override
  String get resourceStudioSubtitle => '多小節漸進式創作與容量管理';

  @override
  String get outlineTab => '大綱';

  @override
  String get capacityTab => '容量';

  @override
  String get historyTab => '版本';

  @override
  String get generatePart => '生成內容';

  @override
  String get regeneratePart => '重新生成';

  @override
  String get partSaved => '修改已儲存';

  @override
  String get partSaving => '儲存中...';

  @override
  String get assemblyWizardTitle => '場景裝配與就緒檢查';

  @override
  String get wizardWorldviewAiSummary =>
      '輸入題材風格或核心構想，AI 可在此草擬世界觀，也可在資料庫中創作完整的多模組世界。';

  @override
  String get adventureWizardTitle => '自訂冒險精靈';

  @override
  String get assemblyStepWorld => '1. 世界觀';

  @override
  String get assemblyStepCharacters => '2. 角色設定';

  @override
  String get assemblyStepNpcs => '3. NPC 陣營';

  @override
  String get assemblyStepConfig => '4. 規則與序章';

  @override
  String get assemblyPreviewTitle => '裝配預覽';

  @override
  String get startAdventureAction => '開啟冒險';

  @override
  String get readinessChecking => '檢查資源就緒狀態...';

  @override
  String get readinessPassed => '全部資源已就緒';

  @override
  String get readinessFailed => '資源需要裝配就緒或壓縮處理';

  @override
  String get adventureSessionTitle => '冒險進行中';

  @override
  String get inputActionHint => '你的下一步行動是？輸入行動或對白...';

  @override
  String get sendAction => '傳送';

  @override
  String get aiThinking => 'AI 正在思考...';

  @override
  String get aiWriting => 'AI 正在撰寫...';

  @override
  String get diceCheckTitle => '擲骰判定';

  @override
  String get turnSettling => '正在結算當前回合選項...';

  @override
  String get bookmarkAdded => '已新增書籤';

  @override
  String get bookmarkRemoved => '已移除書籤';

  @override
  String get messageCopied => '訊息已複製到剪貼簿';

  @override
  String get messageEdited => '訊息已編輯';

  @override
  String get chatEditMessage => '編輯訊息';

  @override
  String get chatReadAloudUnsupported => '目前平台不支援朗讀';

  @override
  String get chatCopyReasoning => '複製思考過程（思維鏈）';

  @override
  String get chatReasoningCopied => '思維鏈已複製到剪貼簿';

  @override
  String get chatRetryWithModel => '使用其他模型重試';

  @override
  String get chatFork => '從此處分支';

  @override
  String chatBranchCreated(Object branch) {
    return '已建立分支 $branch';
  }

  @override
  String get chatDeleteMessage => '刪除';

  @override
  String get chatSearchHint => '搜尋對話內容…';

  @override
  String get chatBookmarksOnly => '僅書籤';

  @override
  String get chatMoreActions => '更多操作';

  @override
  String get chatEditStatus => '編輯狀態';

  @override
  String get chatDeleteStatus => '刪除狀態';

  @override
  String get readAloudPause => '暫停';

  @override
  String get readAloudPauseRestart => '暫停（將從本段開頭繼續）';

  @override
  String get readAloudResume => '繼續朗讀';

  @override
  String get readAloudPreparing => '準備朗讀';

  @override
  String get readAloudPrevious => '上一段';

  @override
  String get readAloudNext => '下一段';

  @override
  String get tokenCurrentScene => '本次場景 Token';

  @override
  String get tokenHistoryTotal => '累計 Token';

  @override
  String get tokenCurrentSceneDescription => '目前場景消耗 Tokens';

  @override
  String get tokenHistoryDescription => '本機記錄歷史累計 Tokens';

  @override
  String get readAloudPlatformSupportedMessage => '目前平台支援系統語音朗讀，可在對話與創作工作台中使用。';

  @override
  String get diagnosticExportFailed => '診斷匯出失敗，請稍後重試。';

  @override
  String diagnosticExported(Object path) {
    return '診斷工作階段已匯出：$path';
  }

  @override
  String get clearHistoryTitle => '清空歷史對話記錄';

  @override
  String get clearHistoryMessage =>
      '確定要清空所有過去的對話存檔嗎？\n世界觀與角色卡資產將保留，但場景聊天歷史將無法恢復。';

  @override
  String get clearHistoryConfirm => '確認清空';

  @override
  String get clearHistorySuccess => '已成功清理所有歷史工作階段記錄';

  @override
  String get readAloudRateLabel => '語速';

  @override
  String get readAloudPitchLabel => '音調';

  @override
  String get readAloudLanguageHintAuto => '根據每段正文自動選擇可用的系統語音語言。';

  @override
  String get readAloudLanguageHintFixed => '所有正文都使用所選語言朗讀。';

  @override
  String readAloudSupportedCount(Object count) {
    return '系統可用語言：$count 種';
  }

  @override
  String get generationWaiting => '等待生成內容…';

  @override
  String get errorTimeoutTitle => '請求逾時';

  @override
  String get errorTimeoutSuggestion => '請檢查網路連線後重試';

  @override
  String get errorAuthTitle => '驗證失敗';

  @override
  String get errorAuthSuggestion => '請檢查 API Key 是否有效';

  @override
  String get errorRateTitle => '請求過於頻繁';

  @override
  String get errorRateSuggestion => '請稍候片刻後重試';

  @override
  String get errorApiTitle => 'API 錯誤';

  @override
  String get errorApiSuggestion => '請檢查 API 設定或稍後重試';

  @override
  String get errorNetworkTitle => '網路錯誤';

  @override
  String get errorNetworkSuggestion => '請檢查網路連線和 API 設定後重試';

  @override
  String get switchModelRetry => '切換模型重試';

  @override
  String get resourceTrashTooltip => '回收站';

  @override
  String get resourceCreateShort => '新建';

  @override
  String get resourceNpcTab => 'NPC';

  @override
  String get resourceRetryLoad => '重試';

  @override
  String get resourceEmptyTitle => '尚無資源';

  @override
  String get resourceNoMatches => '找不到符合的資源';

  @override
  String get resourceNoSummary => '暫無簡介';

  @override
  String get resourceMovedToTrash => '已移入回收站';

  @override
  String get refreshRecycleBin => '重新整理回收站';

  @override
  String permanentDeleteMessage(Object title) {
    return '「$title」及其內容將被徹底刪除，無法復原。\n確定要繼續嗎？';
  }

  @override
  String get readinessBlockedTitle => '暫時無法開始冒險';

  @override
  String get acknowledgeAction => '知道了';

  @override
  String get staleResourceTitle => '資源已修改';

  @override
  String get staleResourceMessage => '以下資源在最近一次就緒後又發生了修改：';

  @override
  String get usePreviousReady => '是否使用上一個已就緒版本開始冒險？';

  @override
  String get chatImportFormat => '格式';

  @override
  String get chatImportLabel => '聊天內容';

  @override
  String get chatImportHint => '在此貼上聊天內容…';

  @override
  String get chatImportSuccess => '匯入成功';

  @override
  String get chatImportParsing => '解析中…';

  @override
  String get chatImportAction => '匯入';

  @override
  String get chatImportEmpty => '請先貼上聊天內容';

  @override
  String chatImportFailed(Object error) {
    return '匯入失敗：$error';
  }

  @override
  String get chatExportWarning => '匯出內容可能包含對話和使用者輸入，請妥善保管。';

  @override
  String get chatSaveFailed => '儲存失敗';

  @override
  String chatSavedPath(Object path) {
    return '已儲存：$path';
  }

  @override
  String get chatSaving => '儲存中…';

  @override
  String get chatLoadFailedRetry => '載入失敗，重試';

  @override
  String chatCharacterCount(Object count) {
    return '$count 字元';
  }

  @override
  String get resourceDetailTitle => '資源詳情';

  @override
  String get resourceEnterStudio => '進入創作工作台';

  @override
  String get resourceLegacyNoStudio => '舊資源暫不支援進階創作';

  @override
  String get resourceActions => '資源操作';

  @override
  String get moveToTrashAction => '移入回收站';

  @override
  String moveToTrashMessage(Object name) {
    return '將「$name」移入回收站？之後可在回收站中復原。';
  }

  @override
  String get moveToTrashFailed => '移入回收站失敗，請重試';

  @override
  String get thinkingEngineTitle => '深度思考引擎';

  @override
  String get thinkingEngineBadge => 'V4.1 原生思考';

  @override
  String get thinkingEngineDescription =>
      '針對複雜多支線冒險與世界觀邏輯推演，開啟 DeepSeek V4.1 原生思維鏈的前置規劃。';

  @override
  String get worldviewDeepThinkingLabel => '世界觀深度推演生成';

  @override
  String get worldviewDeepThinkingSubtitle =>
      '世界觀 AI 匯入允許使用 V4.1 深度推演；預設關閉以降低首 Token 延遲';

  @override
  String get characterDeepThinkingLabel => '角色卡深度推演生成';

  @override
  String get characterDeepThinkingSubtitle =>
      '角色卡 AI 匯入允許使用 V4.1 深度推演；預設關閉以優先快速生成';

  @override
  String get reasoningEffortLow => '輕度推演 · 极速回應';

  @override
  String get reasoningEffortMedium => '平衡推演 · 日常推薦';

  @override
  String get reasoningEffortHigh => '深度思考 · 豐富細節';

  @override
  String get reasoningEffortMax => '極致演算 · 嚴謹邏輯';

  @override
  String get restoreRecommended => '恢復預設推薦';

  @override
  String get recommendedDefaultsRestored => '已恢復官方推薦參數';

  @override
  String get revisionHistoryTitle => '歷史記錄';

  @override
  String revisionCount(Object count) {
    return '$count 筆記錄';
  }

  @override
  String get refreshRevisionHistory => '重新整理版本歷史';

  @override
  String get noRestorableRevisions => '尚無可復原的歷史記錄';

  @override
  String get currentRevision => '目前';

  @override
  String get restoreRevision => '復原此記錄';

  @override
  String get presetParseError => '劇本資料解析失敗或格式不完整';

  @override
  String get presetWorldviewTitle => '世界觀設定';

  @override
  String get presetCharacterTitle => '主角檔案';

  @override
  String get presetOpeningTitle => '開場序章';

  @override
  String get presetOptionsTitle => '初始行動分支';

  @override
  String get presetNpcTitle => '登場配角（NPC）';

  @override
  String get presetCustomizeAction => '向導載入微調';

  @override
  String get presetDetailsAction => '詳情';

  @override
  String get sidebarEmptyConversationsSubtitle => '點擊上方按鈕開啟新冒險';

  @override
  String get sidebarDeleteTooltip => '刪除對話';

  @override
  String get sidebarSettingsNotConfigured => '系統設定（未設定金鑰）';

  @override
  String get characterFallbackName => '角色A';

  @override
  String get monitoredStatus => '監測狀態';

  @override
  String get expandAction => '展開 ▼';

  @override
  String get collapseAction => '收起 ▲';

  @override
  String statusItemsCount(int count) {
    return '$count項';
  }

  @override
  String optionsSectionTitle(int count) {
    return '選項 ($count 個選項)';
  }

  @override
  String get selectPrompt => '請選擇';

  @override
  String get noOptionsAvailable => '暫無可選項';

  @override
  String get notSpecified => '不指定';

  @override
  String itemsSelectedCount(int count) {
    return '已選 $count 項';
  }

  @override
  String get backAction => '返回';

  @override
  String get showPassword => '顯示明文';

  @override
  String get hidePassword => '隱藏明文';

  @override
  String get actionMenuTitle => '操作';

  @override
  String get actionMenuSemanticLabel => '操作選單';

  @override
  String get menuTooltip => '選單';

  @override
  String get switchLibrary => '切換資料庫';

  @override
  String get customAttributesTitle => '自添加項';

  @override
  String get customAttributesSubtitle => '支援自主為角色/NPC擴充任意專屬設定，可單獨命名並設定推演重要程度';

  @override
  String get addCustomAttributeAction => '新增項目';

  @override
  String get noCustomAttributes => '暫無自添加項（純淨白板）';

  @override
  String get customAttributesEmptyHint => '點擊右上角「新增項目」可自定義專屬武器、隱秘禁忌、弱點或特質';

  @override
  String get customAttributeNameLabel => '項目名稱 *';

  @override
  String get customAttributeNameHint => '如: 隨身佩劍、致命弱點、施法習慣';

  @override
  String get deleteAttributeTooltip => '刪除該項';

  @override
  String get customAttributeContentLabel => '項目內容 / 設定描述';

  @override
  String get customAttributeContentHint => '描述該項具體效果、起源或限制（LLM 推演時將遵從對應重要程度）';

  @override
  String get customAttributeImportanceReference => '參考';

  @override
  String get customAttributeImportanceImportant => '重要參考';

  @override
  String get customAttributeImportanceVeryImportant => '很重要參考';

  @override
  String get customAttributeImportanceCritical => '不可忽略項';

  @override
  String get feedbackSuccess => '成功';

  @override
  String get feedbackError => '錯誤';

  @override
  String get feedbackWarning => '提醒';

  @override
  String get feedbackInfo => '提示';

  @override
  String get refreshFailed => '重新整理失敗，請稍後重試';

  @override
  String get noRefreshNeeded => '目前頁面無需重新整理';

  @override
  String get fontSizeDialogTitle => '字號調節';

  @override
  String get fontSizeSmall => 'A小';

  @override
  String get fontSizeLarge => 'A大';

  @override
  String get fontSizePreview => '預覽: 中文 123\n字號大小範例';

  @override
  String get applyAction => '套用';

  @override
  String appliedPresetNotice(String preset) {
    return '已套用：$preset';
  }

  @override
  String get dialogueParamsTitle => '對話參數';

  @override
  String get paramsPresetLabel => '參數預設';

  @override
  String get customPreset => '自訂';

  @override
  String get frequencyPenalty => '頻率懲罰';

  @override
  String get presencePenalty => '存在懲罰';

  @override
  String get saveWorldviewTitle => '儲存世界觀';

  @override
  String get worldviewInfoSection => '世界觀資訊';

  @override
  String worldviewSavedSuccess(String name) {
    return '已儲存世界觀「$name」';
  }

  @override
  String saveFailedPrefix(String error) {
    return '儲存失敗：$error';
  }

  @override
  String get importCardDialogTitle => '匯入角色卡';

  @override
  String get pasteCardJsonHeader => '貼上 SillyTavern / Chub 角色卡 JSON';

  @override
  String get pasteCardJsonHint => '在此貼上角色卡 JSON 內容...';

  @override
  String get newDialoguePersonaTitle => '新建對話角色卡';

  @override
  String get editDialoguePersonaTitle => '編輯對話角色卡';

  @override
  String get dialoguePersonaSettingHeader => '對話角色設定';

  @override
  String get dialoguePersonaScopeNotice => '這裡的角色只用於對話模式，可以完全不使用奈拉。';

  @override
  String get personaNameLabel => '角色名稱 *';

  @override
  String get personaNameHint => '例如：奈拉、顧問、我的寫作搭檔';

  @override
  String get personaRoleLabel => '身份定位';

  @override
  String get personaRoleHint => '例如：通用 AI 助手、語言教練、世界觀顧問';

  @override
  String get personaUserAddressLabel => '如何稱呼使用者';

  @override
  String get personaUserAddressHint => '例如：使用者、創作者、指揮官、老師';

  @override
  String get personaPersonalityLabel => '性格與行為特點';

  @override
  String get personaPersonalityHint => '描述角色的性格、價值觀和處理問題的方式';

  @override
  String get personaSpeakingStyleLabel => '說話方式';

  @override
  String get personaSpeakingStyleHint => '例如：簡潔、溫柔，必要時用步驟和範例解釋';

  @override
  String get personaBackgroundLabel => '背景設定';

  @override
  String get personaBackgroundHint => '角色從哪裡來，以及它了解什麼';

  @override
  String get personaContextLabel => '對話情境';

  @override
  String get personaContextHint => '描述角色與使用者通常在哪種情境下交流';

  @override
  String get personaDirectivesLabel => '額外行為指令';

  @override
  String get personaDirectivesHint => '可選：補充角色必須遵守的行為規則';

  @override
  String get deleteDialoguePersonaTitle => '刪除對話角色卡？';

  @override
  String deleteDialoguePersonaMessage(String name) {
    return '確定要刪除「$name」嗎？';
  }

  @override
  String deleteCharacterCardFailed(String error) {
    return '刪除角色卡失敗: $error';
  }

  @override
  String get nameRequired => '請填寫角色名稱';

  @override
  String get manualCreatedSource => '手動建立';

  @override
  String get createAction => '建立';

  @override
  String get nameLabel => '名稱';

  @override
  String get descriptionOptionalLabel => '描述（可選）';

  @override
  String get fontSizeAdjustment => '字型大小調整';

  @override
  String get fontSizeSmallA => 'A小';

  @override
  String get fontSizeLargeA => 'A大';

  @override
  String get dialogueParams => '對話參數';

  @override
  String get parameterPresets => '參數預設';

  @override
  String get presetDeepThinking => '深度思考 (V4.1 複雜推演)';

  @override
  String get presetFastNarrative => '極速敘事 (預設體驗)';

  @override
  String get presetDeepReasoning => '極限推理 (長考解謎)';

  @override
  String get presetLightweightDaily => '輕量日常 (極速低延遲)';

  @override
  String appliedPreset(String preset) {
    return '已套用：$preset';
  }

  @override
  String get saveWorldview => '儲存世界觀';

  @override
  String get worldviewInfo => '世界觀資訊';

  @override
  String get name => '名稱';

  @override
  String get descriptionOptional => '描述（選填）';

  @override
  String worldviewSaved(String name) {
    return '已儲存世界觀「$name」';
  }

  @override
  String saveFailed(String error) {
    return '儲存失敗：$error';
  }

  @override
  String get unknownError => '未知錯誤';

  @override
  String get importCharacterCard => '匯入角色卡';

  @override
  String get pasteCharacterCardJson => '貼上 SillyTavern / Chub 角色卡 JSON';

  @override
  String get pasteCharacterCardJsonHint => '在此貼上角色卡 JSON 內容...';

  @override
  String get importAction => '匯入';

  @override
  String get editDialoguePersonaCard => '編輯對話角色卡';

  @override
  String get newDialoguePersonaCard => '新增對話角色卡';

  @override
  String get dialoguePersonaSettings => '對話角色設定';

  @override
  String get dialoguePersonaSettingsDesc => '這裡的角色只用於對話模式，可以完全不使用奈拉。';

  @override
  String get personaNameRequired => '角色名稱 *';

  @override
  String get personaRole => '身分定位';

  @override
  String get personaUserCallName => '如何稱呼使用者';

  @override
  String get personaUserCallNameHint => '例如：使用者、創作者、指揮官、老師';

  @override
  String get personaPersonality => '性格與行為特點';

  @override
  String get personaSpeakingStyle => '說話方式';

  @override
  String get personaBackground => '背景設定';

  @override
  String get personaScenario => '對話情境';

  @override
  String get personaScenarioHint => '描述角色與使用者通常在哪種情境下交流';

  @override
  String get personaSystemPrompt => '額外行為指令';

  @override
  String get personaSystemPromptHint => '選填：補充角色必須遵守的行為規則';

  @override
  String deleteDialoguePersonaPrompt(String name) {
    return '確定要刪除「$name」嗎？';
  }

  @override
  String get pleaseEnterPersonaName => '請填寫角色名稱';

  @override
  String get manuallyCreated => '手動建立';

  @override
  String get sidebarSystemSettings => '系統設定';

  @override
  String get settingsTabModelAndApi => '模型與 API';

  @override
  String get settingsTabModelAndApiSubtitle => '服務商與金鑰配置';

  @override
  String get settingsTabSessionParams => '會話參數';

  @override
  String get settingsTabSessionParamsSubtitle => '採樣率與深度思考';

  @override
  String get settingsTabAppearance => '主題配色';

  @override
  String get settingsTabAppearanceSubtitle => '深淺與主題色彩';

  @override
  String get settingsTabStorage => '資料管理';

  @override
  String get settingsTabStorageSubtitle => 'Token 統計與儲存';

  @override
  String get settingsCustomProvider => '自訂';

  @override
  String get settingsReturnToLobby => '返回大廳';

  @override
  String get settingsReturnToSettingsList => '返回設定列表';

  @override
  String get settingsConfigsCategory => '配置分類';

  @override
  String settingsOfficialInService(String provider) {
    return '$provider 官方在服';
  }

  @override
  String get settingsKeyNotConfigured => '未配置金鑰';

  @override
  String get settingsLlmConnected => '大模型服務已連線';

  @override
  String get settingsLlmDisconnected => '未配置 API 金鑰';

  @override
  String get settingsLlmConnectedSubtitle => '點選管理服務商、模型與端點';

  @override
  String get settingsLlmDisconnectedSubtitle => '點選配置 API 金鑰以啟動推演';

  @override
  String get settingsEngineTitle => '靈境核心引擎';

  @override
  String get settingsEngineSubtitle => 'SQLite · 本地加密優先';

  @override
  String get settingsSystemConfigBadge => '系統配置';

  @override
  String get inferenceParamsTitle => '推理超參與採樣調節';

  @override
  String get inferenceParamsSubtitle => '調整溫度、採樣閾值與深度思考強度以平衡文采與邏輯一致性';

  @override
  String get deepseekThinkingHint =>
      '💡 提示：DeepSeek V4.1 思考模式下採樣超參由模型自適應管理；非思考模式固定 top_p=1.0，僅溫度可調。';

  @override
  String get temperatureTitle => '生成溫度 (Temperature)';

  @override
  String get temperatureDescription => '0.0 絕對嚴謹精確 ↔ 2.0 天馬行空豐富';

  @override
  String get topPTitle => '核採樣概率 (Top-P)';

  @override
  String get topPDescription => '累積概率截斷閾值，推薦保持 0.90 ~ 0.95';

  @override
  String get maxTokensTitle => '單次最大生成長度 (Max Tokens)';

  @override
  String get maxTokensDescription => '限制單回合對話的最大 Token 預算';

  @override
  String get paramsRealtimeNotice => '提示：參數變動即時生效，無需手動儲存';

  @override
  String testConnectionSuccess(int elapsed) {
    return '連線成功！耗時 ${elapsed}ms，服務狀態極佳。';
  }

  @override
  String get testConnectionFailure => '連線失敗，請核對金鑰是否正確及網路是否順暢。';

  @override
  String testConnectionFailureDetail(String error) {
    return '連線失敗: $error';
  }

  @override
  String get statusReady => '已就緒';

  @override
  String get statusNotReady => '未就緒';

  @override
  String modelEndpointSummary(String model, String endpoint) {
    return '模型: $model · 端點: $endpoint';
  }

  @override
  String get quickTesting => '檢測中';

  @override
  String get quickTest => '快速測通';

  @override
  String get llmProviderSectionTitle => 'LLM 服務提供商';

  @override
  String get llmProviderSectionSubtitle => '選擇並配置場景對話與推理使用的核心語言模型服務';

  @override
  String get modelProviderLabel => '模型提供商';

  @override
  String get selectInServiceModal => '選擇在服模型';

  @override
  String get customModelNameLabel => '自訂模型名稱';

  @override
  String get customModelNameHint => '如 gpt-4o, llama-3.3-70b, qwen-max';

  @override
  String get apiEndpointLabel => 'API 服務端點 (Base URL)';

  @override
  String get apiSecurityNotice => '金鑰加密儲存於本機裝置 SQLite 資料庫，絕不經由中繼伺服器轉存';

  @override
  String get promptSettingsTitle => '提示詞與推演編排';

  @override
  String get importPresets => '匯入預設';

  @override
  String get exportPresets => '匯出預設';

  @override
  String get previewPromptAction => '預覽';

  @override
  String get importPresetTitle => '匯入提示詞預設';

  @override
  String get exportPresetTitle => '匯出提示詞預設';

  @override
  String get presetJsonLabel => '提示詞預設 JSON';

  @override
  String get presetJsonEmptyError => '請輸入預設 JSON';

  @override
  String presetImportFailed(String error) {
    return '匯入失敗：$error';
  }

  @override
  String get presetJsonCopied => '已複製預設 JSON';

  @override
  String get copyAllAction => '複製全部';

  @override
  String get dialogueLevelSectionTitle => '對話模式分級 (Dialogue Level)';

  @override
  String get dialogueLevelSectionSubtitle => '選擇模型在單輪對話中的字數預算與描摹細節密度。';

  @override
  String get systemPromptSectionTitle => '全域系統提示詞 (System Prompt)';

  @override
  String get systemPromptSectionSubtitle => '純淨初始狀態。留空時系統將採用極簡通用的推演規範。';

  @override
  String get systemPromptHint => '在此編寫自訂系統設定、世界規則或角色推演守則（留空使用純淨預設規則）...';

  @override
  String charCountLabel(int count) {
    return '已寫 $count 字元';
  }

  @override
  String get clearAction => '清空';

  @override
  String get systemPromptSaved => '全域系統提示詞已儲存';

  @override
  String get savePromptAction => '儲存提示詞';

  @override
  String get authorsNoteSectionTitle => '作者註釋 (Author\'s Note)';

  @override
  String get authorsNoteSectionSubtitle => '在會話上下文中指定輪數深度注入高權重指示。';

  @override
  String get authorsNoteHint => '例如：聚焦於主角行動的細緻刻畫，保持環境氛圍神秘懸疑...';

  @override
  String get injectionDepth => '注入深度';

  @override
  String get depthFollowSystem => '緊跟系統設定';

  @override
  String depthBeforeRound(int depth) {
    return '第 $depth 輪前';
  }

  @override
  String get injectionFrequency => '注入頻率';

  @override
  String freqEveryRound(int freq) {
    return '每 $freq 輪';
  }

  @override
  String get authorsNoteSaved => '作者註釋設定已儲存';

  @override
  String get saveNoteConfigAction => '儲存註釋配置';

  @override
  String get promptPreviewTitle => '即時 Prompt 裝配預覽';

  @override
  String get copyFullPrompt => '複製完整 Prompt';

  @override
  String get fullPromptCopied => '已複製完整裝配 Prompt 至剪貼簿';

  @override
  String promptPreviewStats(int chars, int tokens) {
    return '共約 $chars 字元 · 預估 $tokens tokens';
  }

  @override
  String get resourceTypeWorldview => '世界觀';

  @override
  String get resourceTypeCharacter => '角色';

  @override
  String get resourceTypeNpc => 'NPC';

  @override
  String get resourceStatusGenerating => '生成中';

  @override
  String get resourceStatusSaved => '已儲存';

  @override
  String get resourceStatusOptimizationSuggested => '建議最佳化';

  @override
  String get resourceStatusOptimizing => '正在最佳化';

  @override
  String get resourceStatusReady => '已準備完成';

  @override
  String get resourceStatusOptimizationFailed => '最佳化失敗';

  @override
  String get resourceUnknownTime => '未知時間';

  @override
  String get resourceCreateTitle => '新建資源';

  @override
  String get resourceTypeSectionTitle => '資源類型';

  @override
  String get resourceTypeSectionDescription => '選擇所要構建的內容載體類型';

  @override
  String get resourcePreselectedType => '預選類型';

  @override
  String get resourceCreationMethodSectionTitle => '建立方式';

  @override
  String get resourceCreationMethodSectionDescription =>
      '根據創作需要選擇由 AI 輔助推演或手動純文字編寫';

  @override
  String get resourceAiCreationTitle => 'AI 建立';

  @override
  String get resourceAiCreationDescription =>
      '基於參考資料、小說文本或現有資產，由 AI 自動推演章節大綱與正文內容。';

  @override
  String get resourceRecommendBadge => '推薦';

  @override
  String get resourceManualCreationTitle => '手動建立';

  @override
  String get resourceManualCreationDescription => '自訂名稱與簡介，建立空白資源後自由編排章節與內容。';

  @override
  String get resourceManualCreateTitle => '手動建立資源';

  @override
  String get resourceBasicInfoTitle => '基本資訊';

  @override
  String get resourceManualBasicInfoDescription =>
      '填寫資源的類型、名稱與簡要介紹，建立後即可在工作室中自由編排正文';

  @override
  String get resourceNameLabel => '名稱';

  @override
  String get resourceManualNameHint => '輸入清晰明確的名稱';

  @override
  String get resourceSummaryOptionalLabel => '簡介（可選）';

  @override
  String get resourceManualSummaryHint => '簡要介紹該資源的定位與背景設定';

  @override
  String get resourceCreateAction => '建立';

  @override
  String get resourceInputNameError => '請輸入資源名稱';

  @override
  String get resourceAiCreateTitle => 'AI 智慧建立資源';

  @override
  String get resourceAiBasicInfoDescription => '定義即將生成的資源載體類型與標題';

  @override
  String get resourceAiNameHint => '輸入將要生成的設定或角色名稱';

  @override
  String get resourceAssociateWorldviewTitle => '關聯世界觀（可選）';

  @override
  String get resourceAssociateWorldviewDescription =>
      '為角色或 NPC 指定其所屬的原生世界觀，作為生成時的補充上下文';

  @override
  String get resourceNoAvailableWorldview => '暫無可關聯的世界觀';

  @override
  String get resourceNotSpecified => '不指定';

  @override
  String get resourceReferenceSourceTitle => '參考資料來源';

  @override
  String get resourceReferenceSourceDescription =>
      '提供世界觀背景、小說設定或關聯資源，AI 將提取精髓並推演章節架構';

  @override
  String get resourceTabPaste => '貼上';

  @override
  String get resourceTabFile => '檔案';

  @override
  String get resourceTabExistingResource => '已有資源';

  @override
  String get resourcePasteReferenceLabel => '貼上參考內容';

  @override
  String get resourcePasteReferenceHint => '輸入或貼上小說大綱、設定集草稿或背景描述...';

  @override
  String get resourceFileNameLabel => '檔案名稱';

  @override
  String get resourceFileNameHint => '例如: world_notes.md';

  @override
  String get resourceFileContentLabel => '檔案文字內容';

  @override
  String get resourceFileContentHint => '貼上或輸入檔案內的原始文字...';

  @override
  String get resourceNoExistingInLibrary => '資料庫中暫無可關聯的已就緒資源，請切換至「貼上」或「檔案」輸入。';

  @override
  String get resourceSelectExistingLabel => '選擇已有資源';

  @override
  String get resourceSelectExistingHint => '點擊選取參考的既有資源';

  @override
  String get resourceGenerationLengthTitle => '生成長度';

  @override
  String get resourceGenerationLengthDescription => '控制 AI 生成資源正文的大致目標字數';

  @override
  String get resourceTargetCharactersLabel => '目標字數';

  @override
  String resourceTargetCharactersValue(Object count) {
    return '$count 字';
  }

  @override
  String get resourceLengthShort => '短篇';

  @override
  String get resourceLengthLong => '長篇';

  @override
  String get resourceStartCreateAction => '開始建立';

  @override
  String get resourceInputOrPasteReferenceError => '請輸入或貼上參考資料正文';

  @override
  String get resourceInputFileNameError => '請輸入檔案名稱';

  @override
  String get resourceInputFileContentError => '請輸入檔案內容';

  @override
  String get resourceSelectExistingError => '請選擇一個已有的資源作為參考';

  @override
  String get resourcePastedContentLabel => '貼上內容';

  @override
  String get resourceLoadFailedRetry => '資源庫載入失敗，請重試';

  @override
  String get resourceCreationFailedRetry => '資源建立失敗，請重試';

  @override
  String get resourceUnnamed => '未命名資源';

  @override
  String get resourceRevisionResourceKind => '資源';

  @override
  String get resourceRevisionSectionKind => '章節';

  @override
  String get resourceRevisionPartKind => '段落';

  @override
  String resourceTrashSubtitle(
      Object deletedAt, Object expiresAt, Object kind, Object reason) {
    return '$kind · $reason · 刪除於 $deletedAt · 保留至 $expiresAt';
  }

  @override
  String resourceTrashRestoreFailed(Object error) {
    return '恢復失敗：$error';
  }

  @override
  String get resourceTrashPermanentDeleteSuccess => '已永久刪除';

  @override
  String resourceTrashPermanentDeleteFailed(Object error) {
    return '永久刪除失敗：$error';
  }

  @override
  String get modeTitleConversation => '對話資料庫';

  @override
  String get modeTitleAdventure => '場景資料庫';

  @override
  String get modeTitleCreation => '創作資料庫';

  @override
  String get modeEmptyTitleConversation => '暫無對話角色卡';

  @override
  String get modeEmptyTitleAdventure => '暫無場景資料';

  @override
  String get modeEmptyTitleCreation => '暫無創作資料';

  @override
  String get modeEmptySubtitleConversation => '建立自訂角色卡，或查看過去的聊天記錄。';

  @override
  String get modeEmptySubtitleAdventure => '匯入角色、地點、規則或劇情資料，用於場景對話。';

  @override
  String get modeEmptySubtitleCreation => '匯入世界觀、角色設定、章節參考或寫作資料，用於創作模式。';

  @override
  String get resourceStudioRefreshTooltip => '重新整理';

  @override
  String get resourceStudioTocTitle => '目錄';

  @override
  String get resourceStudioNoContent => '當前資源還沒有可展示的內容。';

  @override
  String get resourceStudioReadAloudAll => '連續朗讀全文';

  @override
  String get resourceStudioEditPart => '編輯正文';

  @override
  String get resourceStudioDeletePart => '刪除段落';

  @override
  String get resourceStudioPartNotExistCannotEdit => '該段落已不存在，無法編輯';

  @override
  String get resourceStudioPublishCompressionTitle => '發布壓縮結果';

  @override
  String get resourceStudioPublishCompressionMessage =>
      '壓縮後的正文會替換當前內容，替換前的正文會記錄為歷史版本，可隨時恢復。\n確定要發布嗎？';

  @override
  String get resourceStudioPublishCompressionAction => '發布';

  @override
  String get resourceStudioRestoreRevisionTitle => '恢復歷史版本';

  @override
  String get resourceStudioRestoreRevisionMessage =>
      '當前內容會被該歷史版本替換，替換前的內容也會保留在版本歷史中。\n確定要恢復嗎？';

  @override
  String get resourceStudioRestoreRevisionAction => '恢復';

  @override
  String get resourceStudioDeletePartTitle => '刪除段落';

  @override
  String resourceStudioDeletePartMessage(Object title) {
    return '「$title」會被移入回收站，可在「回收站」中恢復。\n確定要刪除嗎？';
  }

  @override
  String get resourceStudioDeletePartAction => '刪除';

  @override
  String get resourceStudioPartNotExistCannotDelete => '該段落已不存在，無法刪除';

  @override
  String get resourceStudioMovedToTrash => '已移入回收站，可在「回收站」中恢復';

  @override
  String resourceStudioDeletePartFailed(Object error) {
    return '刪除段落失敗：$error';
  }

  @override
  String get resourceStudioContinueGenerating => '繼續生成';

  @override
  String get resourceStudioPauseGenerating => '暫停';

  @override
  String get resourceStudioCancelGenerating => '取消';

  @override
  String get resourceStudioRetryGenerating => '重試';

  @override
  String get resourceStudioCreatingAndStarting => '正在建立資源並啟動生成';

  @override
  String resourceStudioTargetCharacters(Object count) {
    return '目標約 $count 字';
  }

  @override
  String get resourceStudioCreationFailed => '資源建立失敗';

  @override
  String get resourceStudioPleaseRetryLater => '請稍後重試';

  @override
  String get resourceStudioRetryCreation => '重試建立';

  @override
  String get resourceStudioSelectResourceOrSession => '選擇資源或生成會話';

  @override
  String get resourceStudioSelectSession => '選擇生成會話';

  @override
  String get resourceStudioCreateAndStart => '建立並開始生成';

  @override
  String get resourceStudioPendingAiPlan => '待確認的 AI 規劃';

  @override
  String get resourceStudioConfirmAndStart => '繼續確認並開始生成';

  @override
  String resourceStudioUnfinishedTask(Object index) {
    return '未完成的生成任務 $index';
  }

  @override
  String get resourceStudioGeneratingStatus => '生成中';

  @override
  String get resourceStudioResourceLabel => '資源';

  @override
  String get resourceStudioNoResourceOrSession => '暫無資源或可恢復的生成會話。';

  @override
  String get resourceStudioAddSectionTitle => '新增章節';

  @override
  String get resourceStudioSectionTitleField => '章節標題';

  @override
  String get sectionControlsTitle => '章節控制';

  @override
  String sectionControlsCount(Object count) {
    return '$count 個章節';
  }

  @override
  String get sectionControlsAdd => '新增章節';

  @override
  String get sectionControlsEmpty => '該資源還沒有章節。';

  @override
  String sectionControlsLoadMore(Object shown, Object total) {
    return '載入更多（已顯示 $shown/$total）';
  }

  @override
  String get sectionControlsUnnamed => '（未命名章節）';

  @override
  String sectionControlsOrderIndex(Object index) {
    return '序號 $index';
  }

  @override
  String sectionControlsUpdated(Object time) {
    return '更新 $time';
  }

  @override
  String get sectionControlsValidate => '驗證';

  @override
  String get sectionControlsMoreActions => '更多操作';

  @override
  String get sectionControlsRename => '重新命名';

  @override
  String get sectionControlsMoveUp => '上移';

  @override
  String get sectionControlsMoveDown => '下移';

  @override
  String get sectionControlsDelete => '刪除';

  @override
  String get sectionControlsDeleteTitle => '刪除章節';

  @override
  String sectionControlsDeleteMessage(Object title) {
    return '確定刪除「$title」及其所有內容嗎？';
  }

  @override
  String get sectionControlsGenerate => '生成';

  @override
  String get sectionControlsRegenerate => '重新生成';

  @override
  String get sectionControlsNoTasksTooltip => '該章節沒有生成任務（非 AI 藍圖建立），無法生成';

  @override
  String get sectionControlsRegenerateTooltip =>
      '重新執行該章節的生成任務；當前內容會先記錄為歷史版本，可隨時恢復';

  @override
  String get sectionControlsRerunTooltip => '重新執行該章節的生成任務';

  @override
  String get sectionControlsRenameDialogTitle => '重新命名章節';

  @override
  String get partEditorUnsavedDraftFound => '發現未儲存的草稿';

  @override
  String get partEditorUnsavedDraftDesc => '上次編輯未寫入正文。可以載入草稿繼續編輯，或丟棄它。';

  @override
  String get partEditorLoadDraft => '載入草稿';

  @override
  String get partEditorDiscardDraft => '丟棄草稿';

  @override
  String get partEditorConflictDetected => '檢測到內容衝突';

  @override
  String get partEditorConflictDesc =>
      '其他操作（如生成或恢復）修改了此段落。自動儲存已暫停，你的文本仍保留在草稿中。請選擇保留哪個版本：';

  @override
  String get partEditorUseMyText => '使用我的文本';

  @override
  String get partEditorDiscardMyText => '放棄我的文本';

  @override
  String get partEditorHint => '在這裡編輯正文，停止輸入後會自動儲存';

  @override
  String get partEditorSaveNow => '立即儲存';

  @override
  String get partEditorFinishEditing => '完成編輯';

  @override
  String get partEditorDraftLoaded => '已載入草稿，儲存後寫入正文';

  @override
  String get partEditorDraftDiscarded => '草稿已丟棄';

  @override
  String get partEditorEditing => '編輯中…';

  @override
  String get partEditorConflictOtherSaved => '儲存衝突：其他操作修改了此段落，請選擇保留哪個版本';

  @override
  String get partEditorConflictDraftRetained => '儲存衝突：內容仍保留在草稿中，未覆蓋較新的版本';

  @override
  String partEditorAutoSaved(Object label) {
    return '已自動儲存 ($label)';
  }

  @override
  String get partEditorTargetPartMissing => '目標內容已不存在，草稿已丟棄';

  @override
  String get partEditorKeptMyTextAndSaved => '已保留我的文本並儲存';

  @override
  String get partEditorConflictStillUnresolved => '衝突仍未解決：段落又被修改了一次，請重新選擇';

  @override
  String partEditorResolveConflictFailed(Object error) {
    return '解決衝突失敗：$error';
  }

  @override
  String partEditorSaving(Object label) {
    return '正在儲存 ($label)…';
  }

  @override
  String get capacityPanelTitle => '容量';

  @override
  String capacityLatestFailureReason(Object reason) {
    return '最近一次壓縮失敗原因：$reason';
  }

  @override
  String get capacityRefresh => '重新整理容量';

  @override
  String get capacityCompressing => '壓縮中';

  @override
  String get capacityGenerateCandidates => '生成壓縮候選';

  @override
  String capacityRetryFailedWithCount(Object count) {
    return '重試失敗壓縮（$count）';
  }

  @override
  String get capacityRetryFailed => '重試失敗壓縮';

  @override
  String capacityPublishWithCount(Object count) {
    return '發布壓縮結果（$count）';
  }

  @override
  String get capacityPublish => '發布壓縮結果';

  @override
  String get capacityOptimizationTip => '優化會先生成預覽，確認後才會替換當前內容，原內容仍可恢復。';

  @override
  String get capacityPreparingState => '正在準備資源狀態。';

  @override
  String capacityTextCharacters(Object count) {
    return '正文 $count 字';
  }

  @override
  String capacitySectionsCount(Object count) {
    return '章節 $count';
  }

  @override
  String capacityPartsCount(Object count) {
    return '內容塊 $count';
  }

  @override
  String capacityRevisionsCount(Object count) {
    return '歷史記錄 $count';
  }

  @override
  String capacityArchivedSize(Object count) {
    return '已封存 $count 字';
  }

  @override
  String capacityQueuedJobs(Object count) {
    return '待優化 $count';
  }

  @override
  String capacityPotentialSavings(Object count) {
    return '採納候選後約可減少 $count 字。';
  }

  @override
  String get capacityStatusNormal => '正常';

  @override
  String get capacityStatusElastic => '彈性';

  @override
  String get capacityStatusOverflow => '超出預算';

  @override
  String get outlinePartPending => '待生成';

  @override
  String get outlinePartGenerated => '已生成';

  @override
  String get operationFailedRetry => '操作失敗，請重試';

  @override
  String get resourceImportReturnToEdit => '返回修改';

  @override
  String get resourceImportConfirmSave => '確認儲存';

  @override
  String get characterCardEditTitle => '編輯角色卡';

  @override
  String get characterCardCreateTitle => '新建角色卡';

  @override
  String get characterCardConfirmDeleteTitle => '確認刪除';

  @override
  String characterCardConfirmDeleteMessage(Object name) {
    return '確定要刪除角色卡「$name」嗎？';
  }

  @override
  String characterCardDeleteFailed(Object error) {
    return '刪除角色卡失敗: $error';
  }

  @override
  String get characterCardNameRequired => '請至少填寫姓名';

  @override
  String characterCardSaveFailed(Object error) {
    return '儲存失敗：$error';
  }

  @override
  String get characterCardInfoSection => '角色卡資訊';

  @override
  String get characterCardWorldviewOptional => '契合世界觀（可選）';

  @override
  String get noneOption => '無';

  @override
  String get characterCardAiAssistedCreation => 'AI 智慧輔助編寫角色卡';

  @override
  String get detailedMode => '詳細模式';

  @override
  String get conciseMode => '簡約模式';

  @override
  String get simpleMode => '簡潔模式';

  @override
  String characterCardTargetValidChars(Object count, Object max) {
    return '目標有效內容 $count 字（最多 $max 字）';
  }

  @override
  String get characterCardSavedInStudioTip => '生成將在資源工作室中持續儲存，可恢復並可追蹤修改記錄';

  @override
  String get characterCardRelateCharacterOptional => '關聯已有角色（可選）';

  @override
  String get characterCardRelateCharacterHint => '點擊選擇要建立關係的已有角色（留空為獨立角色）';

  @override
  String get characterCardNoOtherCharacters => '暫無其他角色';

  @override
  String get characterCardIndependentRole => '不關聯（作為獨立新角色構思）';

  @override
  String characterCardRelatedCount(Object count) {
    return '已關聯 $count 位角色';
  }

  @override
  String get characterCardUnnamed => '未命名角色';

  @override
  String get characterCardBondRelation => '羈絆關係：';

  @override
  String get relationCompanion => '同伴 / 隊友';

  @override
  String get relationChildhoodFriend => '青梅竹馬';

  @override
  String get relationLover => '戀人 / 命定伴侶';

  @override
  String get relationMentor => '師徒 (師承/弟子)';

  @override
  String get relationRival => '宿敵 / 競爭對手';

  @override
  String get relationKin => '家族親人';

  @override
  String get relationBenefactor => '救命恩人 / 報恩';

  @override
  String get relationEmployment => '僱傭關係';

  @override
  String get relationCustom => '自訂關係...';

  @override
  String get relationCustomDescLabel => '自訂關係描述';

  @override
  String get relationCustomDescHint => '例如：指腹為婚的未婚妻、異界靈魂共生者...';

  @override
  String get characterCardCoreKeywordHint =>
      '輸入角色核心詞或設定要求（如：冷傲銀髮女劍聖、背叛教會的流浪學者），留空則自由發揮...';

  @override
  String get opening => '正在開啟...';

  @override
  String get aiRegenerate => 'AI 重新生成';

  @override
  String get aiFillIn => 'AI 填入';

  @override
  String get genderLabel => '性別';

  @override
  String get genderMale => '男';

  @override
  String get genderFemale => '女';

  @override
  String get genderOther => '其他';

  @override
  String get ageLabel => '年齡';

  @override
  String get customGenderLabel => '自訂性別';

  @override
  String get occupationLabel => '職業/身分';

  @override
  String get personalityLabel => '性格';

  @override
  String get backgroundStoryLabel => '背景故事';

  @override
  String get appearanceLabel => '外貌描述';

  @override
  String get physiqueFeaturesLabel => '身材體態與生理特徵';

  @override
  String get inWorldSettingSection => '世界內設定';

  @override
  String get factionLabel => '所屬勢力';

  @override
  String get locationLabel => '活動地點 / 家鄉';

  @override
  String get publicGoalLabel => '公開目標';

  @override
  String get hiddenMotiveLabel => '隱藏動機（供敘事使用）';

  @override
  String get abilitySourceLabel => '能力來源';

  @override
  String get abilityCostLabel => '能力代價 / 限制';

  @override
  String get taboosLabel => '禁忌（用「、」分隔）';

  @override
  String get relationsNoteLabel => '關係網路備註';

  @override
  String get characterCardDetailTitle => '角色卡詳情';

  @override
  String get characterPersonalityTraits => '性格特徵';

  @override
  String get characterDescription => '角色描述';

  @override
  String get characterCustomFields => '自添加項';

  @override
  String get characterAiAssistantCreateTitle => 'AI 助手創作角色卡';

  @override
  String get characterCreateAction => '建立角色卡';

  @override
  String characterMatchWorldview(Object name) {
    return '契合：$name';
  }

  @override
  String get worldviewCreateTitle => '新建世界觀';

  @override
  String get worldviewEditTitle => '編輯世界觀';

  @override
  String get worldviewDetailedTitle => '詳細世界觀';

  @override
  String get worldviewConciseTitle => '簡潔世界觀';

  @override
  String get worldviewOverviewDetailed => '世界觀概述（計入詳細設定總字數）';

  @override
  String get worldviewOverviewConcise => '世界觀描述 (200~500字)';

  @override
  String worldviewDetailedLimitTip(Object count) {
    return '詳細設定（總字數上限 $count 字，已確認內容會進入場景對話）';
  }

  @override
  String worldviewConfirmDeleteMessage(Object name) {
    return '確定要刪除世界觀「$name」嗎？';
  }

  @override
  String get worldviewDeleteFailed => '刪除世界觀失敗，請重試';

  @override
  String get worldviewAiAssistantTitle => 'AI 助手創作世界觀';

  @override
  String get worldviewCreateAction => '建立世界觀';

  @override
  String get originalTextContent => '原文內容';

  @override
  String get worldviewAiImportTip =>
      '貼上任意文字（txt / md / HTML / 小說片段），AI 將自動提取並整合為世界觀';

  @override
  String get pasteOriginalTextHint => '在此貼上原文內容...';

  @override
  String get importModeLabel => '匯入模式';

  @override
  String get preparingDeduction => '正在準備推演…';

  @override
  String deductionProgressChars(Object current, Object partial, Object target) {
    return '當前有效字數 $current / $target\n$partial';
  }

  @override
  String deductionProgressStage(Object current, Object partial, Object total) {
    return '正在推演第 $current/$total 階段：$partial';
  }

  @override
  String get autoSaveToLibrary => '自動儲存到資料庫';

  @override
  String get expectedTotalCharacters => '期望總字數';

  @override
  String get adaptiveStageHelperText => '自適應分階段高並發推演全套9大模組，提速數倍並自動儲存';

  @override
  String get aiAnalyzeAction => 'AI 解析';

  @override
  String get selectImportModeTitle => '選擇匯入模式';

  @override
  String get selectImportModeDesc => '請選擇本次角色資料的整理粒度。該選擇會直接傳給 AI。';

  @override
  String get conciseModeDesc => '使用簡潔模式：保留身分、性格、外貌、核心經歷和必要關係，避免擴寫。';

  @override
  String get detailedModeDesc => '使用詳細模式：在原文事實範圍內完整整理身分、性格、外貌、經歷、動機、資訊與人物關係。';

  @override
  String batchImportTitle(Object kind) {
    return '批量 AI 匯入$kind';
  }

  @override
  String get provideCharacterDataTitle => '提供角色資料';

  @override
  String get batchAiRecognitionTip => 'AI 會先識別姓名，經你確認後逐個生成角色。';

  @override
  String get pleaseSelectWorldviewFirst => '請先選擇世界觀';

  @override
  String get selectRelatedCharacters => '選擇關聯角色';

  @override
  String relatedCharactersCount(Object count) {
    return '已關聯 $count 個角色';
  }

  @override
  String get minTotalCharactersLabel => '最少總字數';

  @override
  String get maxTotalCharactersLabel => '最多總字數';

  @override
  String characterDataLabel(Object label) {
    return '$label資料';
  }

  @override
  String characterDataHint(Object label) {
    return '貼上包含多個$label的章節、設定或人物小傳……';
  }

  @override
  String get planningAction => '正在規劃…';

  @override
  String get enterAiStudioAction => '進入 AI Studio';

  @override
  String selectCandidatesToImportTitle(Object count) {
    return '選擇匯入角色（$count）';
  }

  @override
  String importSelectedCharactersAction(Object count) {
    return '匯入 $count 個角色';
  }

  @override
  String get selectCandidatesMultiTitle => '選擇對象（可多選）';

  @override
  String get candidatesRelationTip => '生成資料會依據原文和這些已有角色建立可驗證的關係。';

  @override
  String confirmRelateCharactersAction(Object count) {
    return '確認關聯 $count 個角色';
  }

  @override
  String get pasteCharacterRawTextHint => '在此貼上角色或 NPC 原文……';

  @override
  String get stagedDeepGenerationTip => '分階段深度生成，並自動補全至目標完整度';

  @override
  String get worldviewModuleRules => '規則與邊界';

  @override
  String get worldviewModuleState => '當前世界現狀';

  @override
  String get worldviewModuleLocations => '地點與地理';

  @override
  String get worldviewModuleFactions => '勢力與組織';

  @override
  String get worldviewModuleCustoms => '風俗與生活';

  @override
  String get worldviewModuleTimeline => '歷史與時間線';

  @override
  String get worldviewModuleGlossary => '術語表';

  @override
  String get worldviewModuleConstraints => '創作約束';

  @override
  String get notSpecifiedOption => '不指定';

  @override
  String get unnamedWorldview => '未命名世界觀';

  @override
  String get noExistingCharacterCards => '暫無已有角色卡';

  @override
  String selectedCharactersCount(int count) {
    return '已選 $count 個角色';
  }

  @override
  String get generatingEllipsis => '正在生成…';

  @override
  String get aiImportCharacterTitle => 'AI 匯入角色';

  @override
  String get aiImportNpcTitle => 'AI 匯入 NPC';

  @override
  String get relateExistingCharactersTitle => '關聯已有角色';

  @override
  String get sceneBatchImportCharacterTitle => '場景角色批次匯入';

  @override
  String get sceneBatchImportNpcTitle => '場景 NPC 批次匯入';

  @override
  String get belongingWorldviewOptional => '所屬世界觀（可選）';

  @override
  String get relateCharactersOptional => '關聯角色（可選）';

  @override
  String get associateWorldviewOptional => '關聯世界觀（可選）';

  @override
  String get resourceStatusCancelled => '已取消';

  @override
  String get dashboardWizardBadge => '嚮導自訂';

  @override
  String get dashboardPresetBadge => '完整劇本';

  @override
  String get dashboardLibraryBadge => '全景資產';

  @override
  String get dashboardSettingsBadge => '模型設定';

  @override
  String get dashboardMyCharacterCards => '我的角色卡檔案';

  @override
  String get dashboardNoCharacterCardsTitle => '暫無角色卡檔案';

  @override
  String get dashboardNoCharacterCardsDesc =>
      '目前未建立任何角色。你可以在資料庫中塑造你的主角或同伴人設，並在冒險時選擇他們出戰。';

  @override
  String get dashboardGoToCharacterLibrary => '前往角色卡庫';

  @override
  String get dashboardDefaultProfession => '探險者';

  @override
  String get dashboardNoBackgroundDesc => '暫無背景描述';

  @override
  String get dashboardStartWithCharacter => '以此角色啟程';

  @override
  String get dashboardMyWorldSettings => '我的世界設定';

  @override
  String get dashboardNoCustomWorldsTitle => '暫無自訂世界';

  @override
  String get dashboardNoCustomWorldsDesc =>
      '目前處於純淨白板狀態，無任何預設世界。你可以在資料庫中構想專屬世界，或使用嚮導直接開啟探索。';

  @override
  String get dashboardGoToLibrary => '前往資料庫';

  @override
  String get dashboardNoWorldDesc => '暫無設定描述';

  @override
  String get dashboardStartWithWorld => '以此世界啟程';

  @override
  String get dashboardToggleSidebar => '切換導覽列';

  @override
  String get dashboardConfigureApiKey => '設定金鑰';

  @override
  String get dashboardSystemSettings => '系統設定';

  @override
  String get dashboardNoAdventuresTitle => '尚未開始任何場景冒險';

  @override
  String get dashboardNoAdventuresDesc => '選擇上方的「嚮導自訂」開啟屬於你的首部傳奇';

  @override
  String get dashboardContinueAdventures => '繼續未盡的冒險';

  @override
  String get dashboardUnnamedAdventure => '未命名冒險';

  @override
  String get dashboardDeleteAdventureTooltip => '刪除冒險記錄';

  @override
  String dashboardSavedAt(Object time) {
    return '存檔於 $time';
  }

  @override
  String get dashboardContinueExploring => '繼續探索';

  @override
  String get dashboardDeleteAdventureTitle => '刪除冒險記錄';

  @override
  String dashboardDeleteAdventureMessage(Object title) {
    return '確定要刪除場景「$title」及其全部對話記錄嗎？此操作無法撤銷。';
  }

  @override
  String dashboardAdventureDeleted(Object title) {
    return '已刪除場景「$title」';
  }

  @override
  String get characterNameLabel => '姓名';

  @override
  String get presetScenesTitle => '預存場景工房';

  @override
  String get presetScenesSubtitle => '開箱即用的完整冒險場景設定 · 一鍵啟程開局';

  @override
  String get returnToDashboard => '返回大廳';

  @override
  String presetScriptCount(int count) {
    return '$count 個劇本';
  }

  @override
  String get presetWizardNewScene => '嚮導新建場景';

  @override
  String get presetRefreshList => '重新整理清單';

  @override
  String get presetSearchHint => '搜尋場景劇本、世界觀或主角...';

  @override
  String get presetStatusReady => '已就緒';

  @override
  String get presetStatusDraft => '草稿';

  @override
  String get presetDefaultSceneName => '預存場景';

  @override
  String get presetNoMatchingScenes => '沒有找到符合條件的預存場景';

  @override
  String get presetNoScenes => '暫無預存場景劇本';

  @override
  String get presetNoMatchingScenesHint => '請嘗試更換搜尋關鍵字或重設篩選';

  @override
  String get presetNoScenesHint => '透過四步嚮導可以一鍵生成包含世界觀、主角、序章與行動分支的完整劇本預設';

  @override
  String get presetStartWizardAction => '啟動嚮導新建場景';

  @override
  String get presetScriptDetail => '劇本詳情';

  @override
  String get presetUnnamedScene => '未命名場景';

  @override
  String presetWorldviewLabel(Object name) {
    return '世界觀：$name';
  }

  @override
  String get presetPreviewFullSetting => '完整設定預覽';

  @override
  String get presetLoadIntoWizard => '載入嚮導微調';

  @override
  String get presetDeleteAction => '刪除預存場景';

  @override
  String get presetDeleteTitle => '刪除預存場景';

  @override
  String presetDeleteMessage(Object name) {
    return '確定要刪除預存場景「$name」嗎？\n刪除後此劇本預設將無法恢復。';
  }

  @override
  String presetDeletedSuccess(Object name) {
    return '已刪除場景「$name」';
  }

  @override
  String presetDeleteFailed(Object error) {
    return '刪除失敗: $error';
  }

  @override
  String presetLoadFailed(Object error) {
    return '載入預存場景失敗：$error';
  }

  @override
  String get presetStartFailed => '啟動預設場景失敗，請稍後重試';

  @override
  String presetProtagonistSummary(
      Object name, Object gender, Object profession) {
    return '主角：$name ($gender · $profession)';
  }

  @override
  String get presetNoPlotSummary => '暫無劇情描述摘要';

  @override
  String get presetDataSimplifying => '數據結構精簡中';

  @override
  String get presetQuickStartAction => '一鍵啟程';

  @override
  String get presetMenuSemantic => '場景操作功能表';

  @override
  String get worldSelectionTitle => '選擇世界觀設定';

  @override
  String get worldSelectionSubtitle => '從資料庫已構想的世界中挑選本次冒險的世界法則與背景設定';

  @override
  String get worldSelectionSearchHint => '搜尋世界觀名稱、地理風貌或設定規則...';

  @override
  String get worldSelectionNoDesc => '暫無詳細背景描述';

  @override
  String get worldSelectionTag => '世界設定';

  @override
  String get worldSelectionEmptyTitle => '暫無保存的世界觀';

  @override
  String get worldSelectionEmptyDesc => '可在資料庫中建立或在嚮導中直接輸入自訂世界觀';

  @override
  String get characterSelectionTitle => '選擇冒險角色';

  @override
  String get characterSelectionSubtitle => '從資料庫角色檔案中挑選主角與隊伍同伴';

  @override
  String get characterSelectionSearchHint => '搜尋角色姓名、職業、性格或背景...';

  @override
  String get characterCompatNative => '當前世界';

  @override
  String get characterCompatUnbound => '未綁定';

  @override
  String get characterCompatCrossWorld => '來自其他世界';

  @override
  String characterAgeYears(Object age) {
    return '$age歲';
  }

  @override
  String characterPersonalityPrefix(Object personality) {
    return '性格: $personality';
  }

  @override
  String get characterSelectionEmptyTitle => '暫無可用的角色檔案';

  @override
  String get characterSelectionEmptyDesc => '可在資料庫中建立新角色，或在嚮導中使用 AI 自動構思';

  @override
  String get npcSelectionTitle => '選擇初始 NPC';

  @override
  String get npcSelectionSubtitle => '挑選本次冒險登場的常駐 NPC（資料將獨立凍結至當前冒險快照）';

  @override
  String get npcSelectionSearchHint => '搜尋 NPC 姓名、身分或簡述...';

  @override
  String get npcSelectionEmptyTitle => '資料庫暫無 NPC';

  @override
  String get npcSelectionEmptyDesc => '可在資料庫中新增 NPC，或直接跳過此步驟';

  @override
  String get unnamedNpc => '未命名 NPC';

  @override
  String resourceSelectedCount(int count) {
    return '已選擇 $count 項';
  }

  @override
  String get resourceNoneSelected => '未選擇任何項';

  @override
  String get resourceOneSelected => '已選定 1 項';

  @override
  String get confirmSelection => '確認選擇';

  @override
  String get finishSelection => '完成選定';

  @override
  String get loadingResources => '正在載入可用資源...';

  @override
  String noMatchingResourceForQuery(Object query) {
    return '未找到包含「$query」的資源';
  }

  @override
  String get clearSearch => '清空搜尋';

  @override
  String get configureApiKeyFirstForAi => '請先設定 API Key 以使用 AI 自動生成功能';

  @override
  String get aiGenerationNoValidContent => '生成未返回有效內容，請檢查網路或重試';

  @override
  String get aiOpeningGeneratedSuccess => 'AI 序章與初始行動分支已自動生成並填入！';

  @override
  String aiGenerationFailed(Object error) {
    return '生成失敗：$error';
  }

  @override
  String get openingPromptLabel => '序章要求 / 引導提示詞 (可選)';

  @override
  String get openingPromptHint => '例如：以雨夜碼頭的懸疑氛圍開場，讓主角先察覺到異樣…';

  @override
  String get aiGenerateOpeningAndBranches => 'AI 生成序章與分支';

  @override
  String get aiOpeningGeneratingProgress => 'AI 正在結合世界觀與角色設定構思序章與行動分支…';

  @override
  String assemblyWorldviewSubtitle(Object worldview) {
    return '世界: $worldview';
  }

  @override
  String assemblyProtagonistSubtitle(Object name) {
    return '主角: $name';
  }

  @override
  String get assemblyConfigPageTitle => '序章劇情與分支配置';

  @override
  String get saveConfigAndContinue => '儲存設定並繼續';

  @override
  String get openingFirstSceneTitle => '開場第一幕劇情';

  @override
  String get openingFirstSceneDesc => '設定玩家進入冒險後的第一幕情境描述、遭遇或開篇轉折。';

  @override
  String get openingFirstSceneHint => '描述冒險啟程時的時刻、環境與突發危機...';

  @override
  String get pleaseEnterOpeningScene => '請輸入開場劇情設定';

  @override
  String get initialActionBranchesTitle => '初始行動抉擇分支 (可選)';

  @override
  String get initialActionBranchesDesc => '供玩家在開局時做出的三個行動分支，若留空將在進入後由 AI 動態生成。';

  @override
  String get actionBranch1 => '抉擇分支 1';

  @override
  String get actionBranch1Hint => '例如：拔劍迎擊襲來的黑影';

  @override
  String get actionBranch2 => '抉擇分支 2';

  @override
  String get actionBranch2Hint => '例如：尋找掩體並呼喚同伴掩護';

  @override
  String get actionBranch3 => '抉擇分支 3';

  @override
  String get actionBranch3Hint => '例如：仔細觀察四周環境尋找逃生通道';

  @override
  String get difficultyAndGuidanceTitle => '推演難度與自訂指引';

  @override
  String get difficultyAndGuidanceDesc => '控制遊戲運行的難度傾向與自訂提示詞。';

  @override
  String get narrativeDifficulty => '敘事難度';

  @override
  String get difficultyNormalDesc => '普通 (標準敘事與平衡挑戰)';

  @override
  String get difficultyCasualDesc => '休閒 (注重劇情與輕鬆沉浸)';

  @override
  String get difficultyHardDesc => '困難 (嚴苛規則與硬核抉擇)';

  @override
  String get customGuidancePromptOptional => '自訂引導提示詞 (可選)';

  @override
  String get customGuidancePromptHint => '例如：側重懸疑偵探氛圍、多增加環境感官細節描摹...';

  @override
  String get worldviewBoundRules => '已綁定世界觀規則與地理法則';

  @override
  String get defaultContinentRules => '使用預設大陸規則';

  @override
  String readinessReadError(Object error) {
    return '無法讀取資源就緒狀態：$error';
  }

  @override
  String readinessRetryError(Object error) {
    return '資源重新準備失敗：$error';
  }

  @override
  String startAdventureFailed(Object error) {
    return '啟動冒險失敗：$error';
  }

  @override
  String get unnamedHero => '無名勇者';

  @override
  String get adventurerRole => '冒險者';

  @override
  String get assemblyPreviewSubtitle => '全面檢查世界觀、角色陣容、NPC 與序章推演設定';

  @override
  String get enterAdventureAction => '踏入冒險';

  @override
  String get readinessCheckingTitle => '正在檢查資源裝配狀態';

  @override
  String get readinessUnconfirmedTitle => '無法確認資源裝配狀態';

  @override
  String get readinessReadyTitle => '冒險要素裝配完畢';

  @override
  String get readinessNotReadyTitle => '仍有資源未完成裝配';

  @override
  String get readinessCheckingDesc => '正在讀取世界觀與角色的可用版本。';

  @override
  String get readinessUnconfirmedDesc => '資源狀態讀取失敗，為安全起見暫不能確認可啟動。';

  @override
  String get readinessReadyDesc => '點擊下方「踏入冒險」即可凍結快照並開啟全新旅程。';

  @override
  String get readinessNotReadyDesc => '缺少可用版本時無法踏入冒險，請先完成資源組裝準備。';

  @override
  String get readinessRetrying => '正在重新準備…';

  @override
  String get readinessRetry => '重新準備';

  @override
  String worldviewSettingLabel(Object name) {
    return '世界設定: $name';
  }

  @override
  String get worldviewSettingTitle => '世界設定';

  @override
  String get readAloudWorldview => '朗讀世界設定';

  @override
  String protagonistLeadLabel(Object name, Object className) {
    return '主控主角: $name ($className)';
  }

  @override
  String get mainProtagonistTitle => '主控主角';

  @override
  String personalityFeatureLabel(Object personality) {
    return '性格特點: $personality';
  }

  @override
  String backgroundStoryPrefix(Object background) {
    return '背景身世: $background';
  }

  @override
  String accompanyingCharactersCount(int count) {
    return '同行角色 ($count 位):';
  }

  @override
  String characterBondsCount(int count) {
    return '羈絆關係 ($count 條):';
  }

  @override
  String residentNpcsCount(int count) {
    return '常駐 NPC ($count 位)';
  }

  @override
  String get openingSceneAndDecisionsTitle => '序章開場與行動決策';

  @override
  String get openingSceneTitle => '序章開場';

  @override
  String get readAloudOpeningScene => '朗讀序章開場';

  @override
  String get aiDynamicOpeningPlaceholder => '（由 AI 結合世界觀與角色背景動態構思開場劇情）';

  @override
  String get initialActionDecisionsTitle => '初始行動決策分支:';

  @override
  String get noMatchingResourceTitle => '暫無匹配資源';

  @override
  String get noMatchingResourceDesc => '嘗試輸入其他搜尋詞或清除篩選條件';

  @override
  String get searchResourceNameOrDesc => '搜尋資源名稱或描述...';

  @override
  String get aiOpeningPanelTitle => 'AI 自動編寫序章';

  @override
  String get aiOpeningPanelDesc =>
      '填寫你的序章要求，AI 會結合世界觀、主角與同伴角色卡、角色羈絆與 NPC 生成序章正文和初始行動分支；生成結果仍可手動修改。';

  @override
  String get regenerate => '重新生成';

  @override
  String get assemblyPipelineTitle => '冒險裝配流水線';

  @override
  String get assemblyPipelineSubtitle => '步驟推進 · 頁面化資源組裝 · 零彈窗約束';

  @override
  String get phaseWorldview => '世界設定';

  @override
  String get phaseCharacters => '角色陣容';

  @override
  String get phaseOpening => '序章分支';

  @override
  String get phasePreview => '裝配總覽';

  @override
  String nextPhaseLabel(Object phase) {
    return '下一步：$phase';
  }

  @override
  String get previousStepAction => '上一步';

  @override
  String get pleaseSetWorldviewName => '請設定世界觀名稱';

  @override
  String get pleaseAddAtLeastOneCharacter => '請至少添加一個角色';

  @override
  String worldviewSelectedSuccess(Object name) {
    return '已選定世界觀「$name」';
  }

  @override
  String get rosterUpdatedSuccess => '已更新陣容角色';

  @override
  String npcsSelectedCountSuccess(int count) {
    return '已選定 $count 位 NPC';
  }

  @override
  String get openingConfigSavedSuccess => '序章配置已保存';

  @override
  String characterJoinedPartySuccess(Object name) {
    return '角色「$name」已加入隊伍';
  }

  @override
  String get worldviewLibraryLinkTitle => '世界觀資料庫關聯';

  @override
  String get selectFromLibrary => '從資料庫選擇';

  @override
  String boundLibraryWorldviewId(Object id) {
    return '已綁定資料庫世界觀 ID: $id';
  }

  @override
  String get notBoundPresetHint => '未綁定預設，亦可直接在下方填寫自定義世界設定。';

  @override
  String get worldviewDetailsSectionTitle => '世界觀設定詳情';

  @override
  String get worldviewDetailsSectionDesc => '設定大陸法則、地理背景、文明程度與勢力格局。';

  @override
  String get worldNameRequiredLabel => '世界名稱 *';

  @override
  String get worldNameHint => '例如：艾爾登大陸、賽博新都 2099、修真古界...';

  @override
  String get pleaseEnterWorldName => '請輸入世界名稱';

  @override
  String get lawsAndBackgroundLabel => '法則與背景設定';

  @override
  String get lawsAndBackgroundHint => '描述世界的魔法與科技體系、天體氣候、陣營勢力格局...';

  @override
  String get charactersAndNpcAssemblyTitle => '角色與 NPC 裝配';

  @override
  String get selectCharactersFromLibrary => '從資料庫選擇角色';

  @override
  String selectNpcCountLabel(int count) {
    return '選擇 NPC ($count)';
  }

  @override
  String get newCharacterAction => '新建角色';

  @override
  String rosterSectionTitle(int count) {
    return '登場角色陣容 ($count)';
  }

  @override
  String get rosterSectionDesc => '必須勾選 1 位作為主控主角；其他角色可賦予同伴、反派、導師等身份定位。';

  @override
  String get noCharactersAddedYet => '尚未添加登場角色';

  @override
  String get clickAboveToAddCharactersHint => '點擊上方「從資料庫選擇角色」或「新建角色」';

  @override
  String get setAsMainProtagonist => '設為主控主角';

  @override
  String get scriptRoleOrientation => '劇本身份定位';

  @override
  String get openingAndRulesAdvancedConfigTitle => '序章與規則高級配置';

  @override
  String get fullscreenAdvancedConfig => '全屏高級配置';

  @override
  String get openingSceneContentTitle => '序章劇情內容';

  @override
  String get openingSceneContentDesc => '冒險開始的第一幕場景描寫。';

  @override
  String get openingSceneContentHint => '描述主角登場時刻的環境與轉折...';

  @override
  String get openingBranchesDesc => '供玩家在序章結束時選擇的行動方向。';

  @override
  String branchNumberLabel(Object number) {
    return '分支 $number';
  }

  @override
  String actionOptionHint(Object number) {
    return '行動選項 $number...';
  }

  @override
  String get enterStandaloneFullscreenPreview => '進入獨立全屏大預覽';

  @override
  String get fullscreenPreviewButton => '全屏預覽';

  @override
  String get customUnnamedWorld => '自定義未命名世界';

  @override
  String get unspecifiedProtagonist => '未指定主角';

  @override
  String companionRosterSummary(Object roster) {
    return '同伴陣容: $roster';
  }

  @override
  String selectedInitialNpcCount(int count) {
    return '已選定 $count 位初始 NPC';
  }

  @override
  String get firstSceneOpeningPlotTitle => '序章第一幕';

  @override
  String get aiDynamicOpeningSummary => '由 AI 結合背景自動展開';

  @override
  String get wizardWorldviewQuickBadge => '快速構思與資料庫創作';

  @override
  String get wizardWorldviewPromptLabel => '世界觀創意要求 / 題材偏好（可選）';

  @override
  String get wizardWorldviewPromptHint =>
      '例如：蒸汽龐克浮空城與古神低語、克蘇魯異界修真、深海末日城邦；留空則由 AI 自由發揮……';

  @override
  String get generationModeLabel => '生成模式';

  @override
  String get clearSettingsAction => '清空設定';

  @override
  String get wizardGenerateWorldviewAction => '開始 AI 自動撰寫';

  @override
  String get wizardRegenerateWorldviewAction => '重新生成世界觀';

  @override
  String get wizardWorldviewGeneratingBrief => '正在構思世界觀…';

  @override
  String get wizardWorldviewGeneratingDetailed => '正在分階段推演…';

  @override
  String get saveToLibraryNow => '立即儲存至資料庫';

  @override
  String get wizardReusableBadge => '可隨時重複使用';

  @override
  String get wizardWorldviewSaveDescription => '此設定會自動儲存至世界觀資料庫，方便未來冒險隨時取用與擴充。';

  @override
  String charactersSavedCount(int count) {
    return '已將 $count 個角色設定儲存至資料庫';
  }

  @override
  String characterCardSavedSuccess(String name) {
    return '角色「$name」已儲存至資料庫';
  }

  @override
  String get fullscreenSelectionAction => '全螢幕選擇';

  @override
  String wizardCharacterAiSummary(String worldview) {
    return '描述角色性格或定位偏好。AI 會結合目前世界觀「$worldview」構思主角或隊伍成員並加入陣容；資料庫創作可提供更完整的設定。';
  }

  @override
  String get wizardCharacterPromptLabel => '角色創意要求 / 人設偏好（可選）';

  @override
  String get wizardCharacterPromptHint =>
      '例如：沉穩的退魔劍士、活潑的白髮治癒法師、冷酷的機械遊俠；留空則由 AI 自由發揮……';

  @override
  String get wizardGenerateMainCharacterAction => '開始 AI 自動生成主角';

  @override
  String get wizardAddCharacterToRosterAction => '使用 AI 新增陣容角色';

  @override
  String get currentWorldviewLabel => '目前世界';

  @override
  String get removeRosterCharacter => '從陣容移除';

  @override
  String get clearRelatedCharacters => '清除關聯';

  @override
  String wizardRelatedCharactersSummary(int count, String names) {
    return '已關聯 $count 位角色：$names';
  }

  @override
  String get wizardRelationAssociationSummary => '新角色會與所選角色建立故事羈絆。';

  @override
  String charactersAddedToRoster(int count) {
    return 'AI 創作的 $count 個角色已加入冒險隊伍';
  }

  @override
  String get roleMaleLead => '男主';

  @override
  String get roleFemaleLead => '女主';

  @override
  String get roleMaleOne => '男一';

  @override
  String get roleFemaleOne => '女一';

  @override
  String get roleMaleTwo => '男二';

  @override
  String get roleFemaleTwo => '女二';

  @override
  String get roleSupporting => '重要配角';

  @override
  String get roleVillain => '反派';

  @override
  String get roleMentor => '導師';

  @override
  String get roleFamily => '親友';

  @override
  String get relationFriend => '朋友';

  @override
  String get relationEnemy => '敵人';

  @override
  String get relationStranger => '陌生人';

  @override
  String get mainProtagonistDescription => '主控主角（掌控行動與關鍵抉擇）';

  @override
  String get protagonistShortTag => '主角';

  @override
  String get relationshipNetworkDescription =>
      '標示角色之間的羈絆、陣營立場與過往恩怨，AI 推演時會遵循這些關係。';

  @override
  String relationAssetReference(String suggestion) {
    return '關聯資料：$suggestion（本次冒險可另行設定）';
  }

  @override
  String get relationDetailsHint => '描述兩人的關係淵源或羈絆線索（選填）。';

  @override
  String get relationshipNetworkTitle => '角色羈絆與關係網';

  @override
  String get adventureReadyToEnterTitle => '準備就緒，踏入世界';

  @override
  String get worldviewSnapshotBoundSummary => '已完整綁定資料庫世界觀快照與規則法則';

  @override
  String get characterCardSnapshotBoundSummary => '已完整綁定資料庫角色卡檔案';

  @override
  String get characterCustomDesignedSummary => '已自訂主角設定';

  @override
  String get unnamedCharacterA => '角色 A';

  @override
  String get unnamedCharacterB => '角色 B';

  @override
  String get savePreviewAction => '儲存預覽';

  @override
  String get previewTemplateNoStartHint => '只會儲存為可還原的預覽範本，不會啟動冒險。';

  @override
  String adventurePreviewName(String worldview) {
    return '$worldview · 冒險預覽';
  }

  @override
  String adventurePreviewSavedMessage(String name) {
    return '已儲存預覽「$name」，可在預設場景工坊中還原';
  }

  @override
  String get adventurePreviewExistsMessage => '已存在相同的冒險預覽';

  @override
  String adventurePreviewSaveFailed(String error) {
    return '儲存預覽失敗：$error';
  }

  @override
  String get wizardCharacterSaveDescription => '自動將陣容角色設定儲存到角色資料庫，方便在未來的冒險中重用。';

  @override
  String wizardMalformedCharacterCards(int count) {
    return '有 $count 張角色卡無法載入。';
  }

  @override
  String get conversationDeleteTitle => '刪除場景對話';

  @override
  String conversationDeleteConfirm(int count) {
    return '確定刪除選取的 $count 段場景對話嗎？刪除後歷史對話與演變劇情將無法復原。';
  }

  @override
  String conversationDeleteInterrupted(String error) {
    return '刪除中斷，請檢查剩餘對話後重試：$error';
  }

  @override
  String get conversationManageTitle => '管理過去的對話';

  @override
  String selectedItemsCount(int count) {
    return '已選 $count 項';
  }

  @override
  String get deletingAction => '刪除中…';

  @override
  String get batchDeleteAction => '批次刪除';

  @override
  String get noManagedConversations => '沒有可管理的場景對話';

  @override
  String get selectAllAction => '全選';

  @override
  String get sceneConversationLabel => '場景對話';

  @override
  String get messageEditUserTitle => '編輯你的訊息';

  @override
  String get messageEditAssistantTitle => '編輯 AI 回覆';

  @override
  String get messageEditUserSubtitle => '修改後會從這則訊息開始重新產生後續劇情';

  @override
  String get messageEditAssistantSubtitle => '編輯這段劇情文字，以調整敘事或修正細節';

  @override
  String get messageEditUserWarning => '注意：儲存後，這則訊息之後的所有歷史內容都會清除，並依新輸入重新構思。';

  @override
  String get messageBodyLabel => '訊息內容';

  @override
  String get messageEditDescription => '支援長文字編輯、換行與排版';

  @override
  String get messageContentHint => '輸入訊息內容…';

  @override
  String get saveAndRegenerateAction => '修改並重新產生';

  @override
  String get saveChangesAction => '儲存修改';

  @override
  String get messageContentRequired => '訊息內容不可空白';

  @override
  String get messageUnchanged => '內容未變更';

  @override
  String get messageNoLongerCurrent => '訊息已不在目前對話中，請返回並重新整理';

  @override
  String get messageSavedAndRegenerated => '已儲存並重新產生';

  @override
  String get messageChangesSaved => '修改已儲存';

  @override
  String get messageSaveRetry => '儲存失敗，請重試';

  @override
  String get inventoryTitle => '背包';

  @override
  String get inventoryItemsTitle => '物品';

  @override
  String get equipmentTitle => '裝備';

  @override
  String get legacyInventoryTitle => '舊版背包紀錄';

  @override
  String inventorySummary(int itemCount, int equipmentCount) {
    return '物品 $itemCount 件，裝備 $equipmentCount 件';
  }

  @override
  String get quickMenuTooltip => '快速選單';

  @override
  String get characterStatusTitle => '角色狀態';

  @override
  String get wordCountSettings => '字數設定';

  @override
  String get backToLobby => '返回大廳';

  @override
  String get restartAdventureTitle => '確認重新開始冒險';

  @override
  String get restartAdventureMessage => '目前對話與冒險進度將重設，然後返回首頁。';

  @override
  String get restartAdventureAction => '重新開始';

  @override
  String get stopGenerationAction => '停止產生';

  @override
  String get textAdventureTitle => '文字冒險';

  @override
  String get searchConversationAction => '搜尋對話';

  @override
  String get historyAndSidebarAction => '歷史場景與側欄';

  @override
  String get moreOptionsAction => '更多選項';

  @override
  String get replyLengthSetting => '回覆長度';

  @override
  String get switchModelAction => '切換模型';

  @override
  String get promptSettingsAction => '提示詞設定';

  @override
  String get wordCountAndDensitySettings => '字數與對話密度設定';

  @override
  String get reasoningCopiedToast => '思維鏈已複製到剪貼簿';

  @override
  String get editedBadge => '（已編輯）';

  @override
  String get deleteMessageConfirmation => '刪除後無法復原，確定要刪除嗎？';

  @override
  String get removeBookmarkAction => '取消書籤';

  @override
  String get addBookmarkAction => '新增書籤';

  @override
  String get editMessageAction => '修改';

  @override
  String get regenerateMessageAction => '重新產生';

  @override
  String get assistantReplyLabel => 'AI 回覆';

  @override
  String get selectModelForRegeneration => '選擇模型重新產生';

  @override
  String get selectLanguageModel => '選擇語言模型';

  @override
  String currentModelSummary(String model, String provider) {
    return '目前：$model（$provider）';
  }

  @override
  String get selectedModelLabel => '已選模型';

  @override
  String get defaultModelPlaceholder => '未選定（使用預設）';

  @override
  String get confirmApplyAction => '確認套用';

  @override
  String get selectValidModelError => '請選擇或輸入有效的模型名稱';

  @override
  String get messageNoLongerCurrentError => '訊息已不在目前對話中，請返回並重新整理';

  @override
  String get regenerationUserMessageMissingError => '無法重新產生：找不到有效的使用者訊息';

  @override
  String get regenerationTargetMissingError => '無法重新產生：找不到對應的使用者訊息';

  @override
  String get modelRegenerationStarting => '正在重新產生…';

  @override
  String modelSwitchedSuccess(String model) {
    return '已切換至模型：$model';
  }

  @override
  String get modelSwitchFailed => '模型切換失敗，請重試';

  @override
  String get serviceProviderSection => '服務提供者';

  @override
  String get serviceProviderDescription => '選擇官方 API 服務商或本機／第三方相容服務';

  @override
  String get llmProviderLabel => 'LLM 服務提供者';

  @override
  String get recentModelsSection => '最近使用';

  @override
  String get recentModelsDescription => '快速切換此裝置先前使用過的模型';

  @override
  String get recommendedModelsSection => '推薦模型';

  @override
  String get recommendedModelsDescription => '針對文學創作與角色扮演最佳化的核心模型';

  @override
  String get customModelSection => '自訂模型名稱';

  @override
  String get deepseekCustomModelDescription => '如需使用其他 DeepSeek 專屬模型，可在此手動輸入';

  @override
  String get otherCustomModelDescription =>
      '輸入相容端點支援的模型識別碼（例如 gpt-4o、claude-3-5-sonnet）';

  @override
  String get modelNamePlaceholder => '請輸入模型名稱…';

  @override
  String customModelSelected(String model) {
    return '已選定自訂模型：$model';
  }

  @override
  String get adventureBlankSlateTitle => '全新的冒險即將開始';

  @override
  String get adventureBlankSlateDescription =>
      '目前場景尚無對話或行動紀錄。\n在下方輸入行動或提出探索方向，展開這段冒險。';

  @override
  String get beginAdventureAction => '開始冒險';

  @override
  String get deepSeekFlashModelSubtitle =>
      'DeepSeek V4.1 Flash 最新推薦 · 多模態 · 支援深度思考';

  @override
  String get deepSeekLegacyModelSubtitle => '舊版模型，建議遷移至 DeepSeek V4.1 Flash';

  @override
  String get deleteDetectedStatusTitle => '刪除狀態';

  @override
  String confirmDeleteDetectedStatus(String name) {
    return '確定要刪除「$name」這項狀態嗎？';
  }

  @override
  String get statusNameLabel => '狀態名稱 *';

  @override
  String get statusNameExamples => '例如：理智值(SAN)、好感度、精神污染、飽食度';

  @override
  String get measurementModeLabel => '計量模式：';

  @override
  String get numericGaugeMode => '數值進度槽 (0~100)';

  @override
  String get phaseDescriptionMode => '階段描述型';

  @override
  String get currentValueLabel => '目前數值';

  @override
  String get maxValueLabel => '最大上限';

  @override
  String get currentPhaseLabel => '目前階段／描述';

  @override
  String get currentPhaseExamples => '例如：正常、輕度侵蝕、微醺、狂化中';

  @override
  String get chooseStatusIcon => '選擇狀態圖示：';

  @override
  String get statusRuleLabel => '檢定規則／劇情判定說明（選填）';

  @override
  String get statusRuleHint => '例如：低於20時陷入恐慌；擲骰成功可保持理智，失敗則觸發瘋狂幻覺';

  @override
  String get storyImportanceLabel => '劇情重要度：';

  @override
  String get statusNameRequiredError => '請輸入狀態名稱';

  @override
  String get addDetectedStatusAction => '新增狀態';

  @override
  String detectedStatusesCount(int count) {
    return '自訂狀態 ($count)';
  }

  @override
  String get combatAdventureMatrix => '戰鬥與冒險能力矩陣';

  @override
  String get physicalAttackStat => '物理攻擊 (ATK)';

  @override
  String get baseDefenseStat => '基礎防禦 (DEF)';

  @override
  String get agilitySpeedStat => '敏捷速度 (SPD)';

  @override
  String get goldStat => '持有金幣 (Gold)';

  @override
  String get availableSkillPointsStat => '可用技能點';

  @override
  String get currentSceneCoordinatesStat => '目前場景座標';

  @override
  String get openInventoryAction => '開啟背包倉庫';

  @override
  String get profileIdentityTitle => '📜 身分與職業定位';

  @override
  String get profileBackgroundTitle => '📖 背景經歷與淵源';

  @override
  String get profileWorldviewTitle => '🌍 所處世界觀';

  @override
  String get profilePersonalityTitle => '🎭 性格特質';

  @override
  String get profileRelationshipsTitle => '🤝 羈絆與關係';

  @override
  String get profileAppearanceTitle => '✨ 外貌與體態特徵';

  @override
  String get checkAction => '檢定';

  @override
  String levelRoleSummary(int level, String role) {
    return 'Lv.$level · $role';
  }

  @override
  String get editDetectedStatusTitle => '編輯狀態';

  @override
  String get noCustomDetectedStatuses => '尚無自訂狀態';

  @override
  String get detectedStatusesEmptyDescription =>
      '可自訂理智值(SAN)、好感度、精神污染、飽食度、魔力過載等冒險狀態。';

  @override
  String get energyLabel => '能量';

  @override
  String get combatStatsTitle => '戰鬥屬性';

  @override
  String get currentValuePrefix => '目前數值：';

  @override
  String get currentPhaseWithThoughtsLabel => '目前狀態階段／想法';

  @override
  String get phaseNotTriggered => '（尚未觸發階段判定）';

  @override
  String statusRulePrefix(String rule) {
    return '📌 判定規則：$rule';
  }

  @override
  String get companionsTab => '核心狀態';

  @override
  String get equipmentTab => '裝備隨身';

  @override
  String get profileTab => '身世羈絆';

  @override
  String currentExplorationRegion(String scene) {
    return '目前探索區域：$scene';
  }

  @override
  String mainStoryChapter(int chapter) {
    return '主線冒險者 · 第 $chapter 章';
  }

  @override
  String relationshipLabel(String relation) {
    return '關係：$relation';
  }

  @override
  String affinityScoreLabel(int affinity) {
    return '❤️ 好感度：$affinity';
  }

  @override
  String get healthPointsLabel => '生命值 (HP)';

  @override
  String get lifeForceLabel => '生命活力';

  @override
  String get magicPointsLabel => '精神魔法 (MP)';

  @override
  String get focusLabel => '專注力';

  @override
  String get actionEnergyLabel => '行動能量 (Energy)';

  @override
  String get tiredStatus => '⚠️ 疲憊';

  @override
  String get goodStatus => '良好';

  @override
  String get experienceLabel => '升級經驗 (EXP)';

  @override
  String nextLevelExperience(int count) {
    return '升級還需 $count';
  }

  @override
  String skillPointsValue(int count) {
    return '$count 點';
  }

  @override
  String equippedGearCount(int count) {
    return '⚔️ 目前穿戴裝備 ($count)';
  }

  @override
  String get noEquippedGear => '尚未穿戴專屬裝備，可從背包或商店取得裝備以提升戰力。';

  @override
  String gearSlotQuality(String slot, String quality) {
    return '部位：$slot · 品質：$quality';
  }

  @override
  String get carriedItemsTitle => '🎒 隨身物品與材料';

  @override
  String get noCarriedItems => '目前行囊中沒有特殊物品。';

  @override
  String get sharedPartyInventory => '📦 隊伍共用行囊：';

  @override
  String get detectedStatusFormDescription =>
      '在冒險故事中持續檢定的自訂狀態（支援進度槽、判定規則與擲骰檢定）';

  @override
  String get statusPresetsHeading => '💡 預設靈感（點選即可填入）：';

  @override
  String get explorerRole => '冒險者';

  @override
  String get startingTown => '起始城鎮';

  @override
  String get defaultProtagonistProfile => '獨自探索未知邊界，並擁有靈活行動與劇情決策權的冒險者。';

  @override
  String get defaultProtagonistBackground => '踏上風起雲湧的世界旅程，探索未知命運。';

  @override
  String get defaultWorldviewDescription => '沉浸式角色扮演敘事空間，世界會隨劇情發展而演變。';

  @override
  String get defaultCompanionPersonality => '性格深沉，會在旅途中逐漸展現內心真正的渴望。';

  @override
  String genderTag(String value) {
    return '性別：$value';
  }

  @override
  String heightTag(String value) {
    return '身高：$value';
  }

  @override
  String hairstyleTag(String value) {
    return '髮型：$value';
  }

  @override
  String skinToneTag(String value) {
    return '膚色：$value';
  }

  @override
  String facialFeaturesTag(String value) {
    return '面部：$value';
  }

  @override
  String get aliveStatus => '💚 狀態正常';

  @override
  String get incapacitatedStatus => '💀 失去行動能力';

  @override
  String companionRelationshipSummary(String relation, int affinity) {
    return '與主角設定為【$relation】關係。目前好感度：$affinity/100。';
  }

  @override
  String get diceCriticalSuccess => '大成功！判定完美達成！';

  @override
  String get diceCriticalFailure => '大失敗！遭遇嚴重失誤或異常反噬！';

  @override
  String get diceSuccess => '檢定成功！成功抵抗異常並維持狀態穩定。';

  @override
  String get diceFailure => '檢定失敗！受到狀態影響或負面效果侵擾。';

  @override
  String get diceCheckCriticalSuccess => '大成功（暴擊）！極限突破達成！';

  @override
  String get diceCheckCriticalFailure => '大失敗！判定徹底失敗！';

  @override
  String get diceCheckPassed => '檢定通過！狀態運作順利。';

  @override
  String get diceCheckFailed => '檢定未通過！受到阻礙或負面影響。';

  @override
  String diceTargetValue(int current, int maximum) {
    return '檢定目標值：$current / $maximum';
  }

  @override
  String diceCurrentStatus(String status) {
    return '目前狀態：$status';
  }

  @override
  String diceRuleDescription(String rule) {
    return '判定規則：$rule';
  }

  @override
  String get d100PercentileDie => 'D100 百分骰';

  @override
  String get d20Die => 'D20 骰';

  @override
  String get rollCheckAction => '擲出檢定骰';

  @override
  String get rerollAction => '重新擲骰';

  @override
  String get syncResultToAdventure => '同步至冒險劇情';

  @override
  String diceResultPoints(String icon, int value, String denominator) {
    return '$icon 擲出點數：$value $denominator';
  }

  @override
  String get diceResultWillBeSent => '檢定結果將作為一則使用者訊息傳送。';

  @override
  String diceResultMessage(String status, String rule, String character,
      int roll, String target, String verdict) {
    return '【狀態檢定】$character 進行「$status」檢定：🎲 擲出 $roll ($target) → 【$verdict】！$rule';
  }

  @override
  String get allItemsFilter => '全部';

  @override
  String get consumableItemType => '消耗品';

  @override
  String get equipmentItemType => '裝備物品';

  @override
  String get materialItemType => '材料';

  @override
  String get questItemType => '任務物品';

  @override
  String get weaponSlot => '武器';

  @override
  String get armorSlot => '護甲';

  @override
  String get accessorySlot => '飾品';

  @override
  String get specialSlot => '特殊';

  @override
  String get commonQuality => '普通';

  @override
  String get uncommonQuality => '優良';

  @override
  String get rareQuality => '稀有';

  @override
  String get epicQuality => '史詩';

  @override
  String get legendaryQuality => '傳說';

  @override
  String get emptyInventoryTitle => '背包是空的';

  @override
  String get emptyInventoryDescription => '劇情中取得的物品會顯示在這裡。';

  @override
  String get deepThinkingStatus => '正在深度思考…';

  @override
  String get reasoningExpandedLabel => '思考過程（點選收起）';

  @override
  String get reasoningCollapsedLabel => '已完成深度思考（點選展開推理內容）';

  @override
  String get thinkingInProgressStatus => '正在思考…';

  @override
  String get reasoningUnavailableLabel => '（無紀錄）';

  @override
  String get copyReasoningAction => '複製推理內容';

  @override
  String get writingStoryStatus => '正在撰寫劇情…';

  @override
  String get dialogueReplyLengthSettingsTitle => '調整場景對話回覆長度';

  @override
  String dialogueCurrentSelection(String id, String name, String range) {
    return '目前選擇：$id · $name（$range）';
  }

  @override
  String dialogueWordsAbove(int minWords) {
    return '$minWords 字以上';
  }

  @override
  String get dialogueLevelFast => '極速';

  @override
  String get dialogueLevelConcise => '簡潔';

  @override
  String get dialogueLevelStandard => '標準';

  @override
  String get dialogueLevelDetailed => '詳細';

  @override
  String get dialogueLevelDeep => '深度';

  @override
  String get dialogueLevelProduction => '長文生成';

  @override
  String get dialogueLevelFastDesc => '只保留關鍵回饋，適合快速確認。';

  @override
  String get dialogueLevelConciseDesc => '簡短推進，適合輕量互動。';

  @override
  String get dialogueLevelStandardDesc => '預設模式，兼顧速度與沉浸感。';

  @override
  String get dialogueLevelDetailedDesc => '提供更完整的描寫與互動。';

  @override
  String get dialogueLevelDeepDesc => '強調鋪陳、心理與場景層次。';

  @override
  String get dialogueLevelProductionDesc => '長文生成，適合嚴肅寫作。';

  @override
  String get adventureRefreshUnavailable => '生成中或場景無法使用，目前不能重新整理。';

  @override
  String get sessionOfflineHint => '離線 — 網路連線無法使用';

  @override
  String get sessionInputHint => '描述你的行動或對話…';

  @override
  String get messageGestureHint => '右滑訊息可重試 · 左滑可刪除 · 長按可編輯或收藏';

  @override
  String get adventureAssistantName => '冒險助手';

  @override
  String get currentUserDisplayName => '我';

  @override
  String get unknownRegion => '未知地區';

  @override
  String get deepThinkingBadge => '深度思考';

  @override
  String get supportingCharacterRole => '配角';

  @override
  String get autoSwitchCharacterTooltip => '自動切換角色';

  @override
  String get sessionSettlingStatus => '正在生成選項與結算狀態…';

  @override
  String get aiReplyLabel => 'AI 回覆';

  @override
  String sectionValidationPassed(String title) {
    return '「$title」驗證通過';
  }

  @override
  String sectionValidationFailed(String title, int count) {
    return '「$title」驗證未通過：$count 項問題';
  }

  @override
  String get sectionValidationComplete => '驗證完成';

  @override
  String sectionRegenerated(String title, int completed, int total) {
    return '「$title」已重新產生 $completed/$total 個段落';
  }

  @override
  String sectionRegenerationFailed(String title, String error) {
    return '「$title」產生中止：$error';
  }

  @override
  String get sectionGenerationComplete => '產生完成';

  @override
  String get capacityNoCompressionNeeded => '沒有需要壓縮的章節。';

  @override
  String get capacityCompressionAlreadyPublished => '此壓縮候選已發布，未重複修改正文。';

  @override
  String capacityCompressionPublished(int savedCharacters) {
    return '已發布壓縮候選，約節省 $savedCharacters 字；壓縮前的正文保留在歷史版本中。';
  }

  @override
  String capacityRetryBlockedByActiveTarget(int count) {
    return '$count 個失敗任務的目標已有進行中的壓縮，因此已略過。';
  }

  @override
  String capacityRetryBudgetExhausted(int count) {
    return '沒有可重試的壓縮任務；$count 個任務已達重試上限。';
  }

  @override
  String get capacityRetryUnavailable => '沒有可重試的壓縮任務。';

  @override
  String capacityCompressionRunSummary(int succeeded, int failed, int requeued,
      int activeSkipped, int exhaustedSkipped) {
    return '產生候選 $succeeded 個；失敗任務 $failed 個；重新排入 $requeued 個；因目標已有壓縮而略過 $activeSkipped 個；達重試上限而略過 $exhaustedSkipped 個。候選需確認後才會取代正文；失敗任務不會修改原文。';
  }

  @override
  String get revisionCauseManualSave => '手動儲存';

  @override
  String get revisionCauseGeneration => 'AI 生成';

  @override
  String get revisionCausePlanning => '大綱規劃';

  @override
  String get revisionCauseRegeneration => '重新生成';

  @override
  String get revisionCauseCompression => '語義壓縮';

  @override
  String get revisionCauseRestore => '版本還原';

  @override
  String get revisionCauseMigration => '資料遷移';

  @override
  String get revisionCauseDeletion => '刪除前快照';

  @override
  String get revisionUnknownDate => '日期未知';

  @override
  String get revisionAlreadyCurrent => '目前內容已經是該版本。';

  @override
  String revisionRestored(String sourceCause) {
    return '已還原至「$sourceCause」版本。';
  }

  @override
  String revisionItemSubtitle(String date, int nodeCount, int charCount) {
    return '$date · $nodeCount 個節點 · $charCount 字';
  }

  @override
  String resourceRevisionOperationFailed(String error) {
    return '版本操作失敗：$error';
  }
}
