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
  String get testingConnection => '测试中...';

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
  String get apiKeyLabel => 'API 密钥';

  @override
  String get apiKeyPlaceholder => '请输入 API 密钥';

  @override
  String get customEndpointLabel => '自定义端点 (Base URL)';

  @override
  String get customEndpointPlaceholder => 'https://api.example.com/v1';

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
  String get enableThinkingLabel => '启用深度思考 (Reasoning)';

  @override
  String get enableThinkingSubtitle => '支持推理模型在输出最终正文前展现思维链路';

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
  String get charactersTab => '角色卡';

  @override
  String get templatesTab => '模版';

  @override
  String get recycleBinTitle => '回收站';

  @override
  String get emptyRecycleBin => '回收站暂无内容';

  @override
  String get restoreAction => '还原';

  @override
  String get permanentlyDelete => '彻底删除';

  @override
  String get resourceStudioTitle => '资源工坊';

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
  String get testingConnection => '测试中...';

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
  String get apiKeyLabel => 'API 密钥';

  @override
  String get apiKeyPlaceholder => '请输入 API 密钥';

  @override
  String get customEndpointLabel => '自定义端点 (Base URL)';

  @override
  String get customEndpointPlaceholder => 'https://api.example.com/v1';

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
  String get enableThinkingLabel => '启用深度思考 (Reasoning)';

  @override
  String get enableThinkingSubtitle => '支持推理模型在输出最终正文前展现思维链路';

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
  String get charactersTab => '角色卡';

  @override
  String get templatesTab => '模版';

  @override
  String get recycleBinTitle => '回收站';

  @override
  String get emptyRecycleBin => '回收站暂无内容';

  @override
  String get restoreAction => '还原';

  @override
  String get permanentlyDelete => '彻底删除';

  @override
  String get resourceStudioTitle => '资源工坊';

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
  String get testingConnection => '測試中...';

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
  String get apiKeyLabel => 'API 金鑰';

  @override
  String get apiKeyPlaceholder => '請輸入 API 金鑰';

  @override
  String get customEndpointLabel => '自訂端點 (Base URL)';

  @override
  String get customEndpointPlaceholder => 'https://api.example.com/v1';

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
  String get enableThinkingLabel => '啟用深度思考 (Reasoning)';

  @override
  String get enableThinkingSubtitle => '支援推理模型在輸出最終內文前展現思維鏈路';

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
  String get charactersTab => '角色卡';

  @override
  String get templatesTab => '範本';

  @override
  String get recycleBinTitle => '資源回收筒';

  @override
  String get emptyRecycleBin => '資源回收筒暫無內容';

  @override
  String get restoreAction => '還原';

  @override
  String get permanentlyDelete => '永久刪除';

  @override
  String get resourceStudioTitle => '資源工坊';

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
}
