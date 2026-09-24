// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'LT Dialogue';

  @override
  String get pageLoadError => 'Page Load Error';

  @override
  String get reloadAction => 'Reload';

  @override
  String get loadingEnvironment => 'Loading environment...';

  @override
  String testingProviderConnection(String provider) {
    return 'Testing $provider...';
  }

  @override
  String get modelConnectionFailed =>
      'Model connection failed, please check settings';

  @override
  String get apiKeyNotConfiguredPrompt =>
      'API key not configured yet, you can configure it in settings';

  @override
  String get goToSettings => 'Go to Settings';

  @override
  String get createAdventureFailed =>
      'Failed to create scene, please try again later';

  @override
  String get navExplore => 'Explore';

  @override
  String get navLibrary => 'Library';

  @override
  String get navSettings => 'Settings';

  @override
  String get sidebarNewAdventure => 'New Adventure';

  @override
  String get sidebarRecent => 'Recent';

  @override
  String get sidebarManageConversations => 'Batch Manage Conversations';

  @override
  String get sidebarEmptyConversations => 'No past conversations';

  @override
  String get sidebarUnnamedScene => 'Unnamed Scene';

  @override
  String get sidebarDeleteDialogTitle => 'Delete Scene Conversation';

  @override
  String sidebarDeleteDialogMessage(String title) {
    return 'Are you sure you want to delete \"$title\"?\nDeleted history and narrative evolution cannot be recovered.';
  }

  @override
  String get sidebarReturnHome => 'Return to Explore Hall';

  @override
  String get sidebarExpand => 'Expand Sidebar';

  @override
  String get sidebarCollapse => 'Collapse Sidebar';

  @override
  String get sidebarClose => 'Close Sidebar';

  @override
  String get brandSubtitle => 'Narrative & World Evolution Studio';

  @override
  String get serviceConnected => 'Connected';

  @override
  String get serviceNotConfigured => 'Key Not Configured';

  @override
  String get officialOnline => 'Online';

  @override
  String get languageSetupTitle => 'Choose Language';

  @override
  String get languageSetupSubtitle =>
      'Please select your preferred display language';

  @override
  String get languageSettingTitle => 'Language';

  @override
  String get languageSettingSubtitle => 'App display language';

  @override
  String get confirmAction => 'Confirm';

  @override
  String get cancelAction => 'Cancel';

  @override
  String get deleteAction => 'Delete';

  @override
  String get saveAction => 'Save';

  @override
  String get continueAction => 'Continue';

  @override
  String get closeAction => 'Close';

  @override
  String get doneAction => 'Done';

  @override
  String get editAction => 'Edit';

  @override
  String get retryAction => 'Retry';

  @override
  String get copyAction => 'Copy';

  @override
  String get settingsCenter => 'Settings Center';

  @override
  String get settingsSystemConfig => 'System Configuration';

  @override
  String get settingsReturnHome => 'Return to Hall';

  @override
  String get settingsReturnList => 'Return to Settings';

  @override
  String get settingsPreferencesCategory => 'Preferences';

  @override
  String get settingsCoreEngine => 'LT Dialogue Core Engine';

  @override
  String get settingsStorageType => 'SQLite · Local Encryption First';

  @override
  String get tabModelApi => 'Models & API';

  @override
  String get tabModelApiSubtitle => 'Provider & Key Configuration';

  @override
  String get tabSessionParams => 'Session Parameters';

  @override
  String get tabSessionParamsSubtitle => 'Sampling & Deep Thinking';

  @override
  String get tabThemeAppearance => 'Theme & Appearance';

  @override
  String get tabThemeAppearanceSubtitle => 'Light/Dark & Color Scheme';

  @override
  String get tabDataManagement => 'Data Management';

  @override
  String get tabDataManagementSubtitle => 'Token Stats & Storage';

  @override
  String get configCategory => 'Configuration Categories';

  @override
  String get apiServiceConnected => 'LLM Service Connected';

  @override
  String get apiServiceConnectedDesc =>
      'Click to manage provider, model and endpoints';

  @override
  String get apiServiceDisconnectedDesc =>
      'Click to configure API key to start reasoning';

  @override
  String get providerConfigTitle => 'Models & API Services';

  @override
  String get providerConfigSubtitle =>
      'Configure model providers, endpoints, and secure keys';

  @override
  String get testConnection => 'Test Connection';

  @override
  String get testingConnection => 'Testing...';

  @override
  String get inputApiKeyHint => 'Please enter a valid API key first';

  @override
  String connectionSuccess(int time) {
    return 'Connection successful! Took ${time}ms, service status is great.';
  }

  @override
  String get connectionFailed =>
      'Connection failed, please check your key and network connection.';

  @override
  String connectionFailedWithReason(String error) {
    return 'Connection failed: $error';
  }

  @override
  String get apiKeyLabel => 'API Key';

  @override
  String get apiKeyPlaceholder => 'Enter your API key';

  @override
  String get customEndpointLabel => 'Custom Endpoint (Base URL)';

  @override
  String get customEndpointPlaceholder => 'Custom endpoint URL';

  @override
  String get modelLabel => 'Model';

  @override
  String get modelPlaceholder => 'Enter model name';

  @override
  String get customModelNote => 'Using custom model endpoint';

  @override
  String get modelParamsSectionTitle => 'Session Model Parameters';

  @override
  String get modelParamsSectionSubtitle =>
      'Fine-tune generation temperature, context budget, and reasoning mode';

  @override
  String get systemPromptLabel => 'Custom System Prompt';

  @override
  String get systemPromptPlaceholder =>
      'Enter system prompt to guide AI role and behavior...';

  @override
  String get authorsNoteLabel => 'Author\'s Note';

  @override
  String get authorsNotePlaceholder =>
      'Inject strong contextual reminders into recent turns...';

  @override
  String authorsNoteDepthLabel(int depth) {
    return 'Insertion Depth: $depth turns from bottom';
  }

  @override
  String authorsNoteFrequencyLabel(int freq) {
    return 'Trigger Frequency: Every $freq turns';
  }

  @override
  String get dialogueLevelLabel => 'Prose Style & Depth';

  @override
  String temperatureLabel(String value) {
    return 'Temperature (Randomness): $value';
  }

  @override
  String get enableThinkingLabel => 'Enable Deep Thinking (Deep Thinking)';

  @override
  String get enableThinkingSubtitle =>
      'When enabled, model outputs collapsible thinking chains before story prose';

  @override
  String get reasoningEffortLabel => 'Reasoning Effort';

  @override
  String get quickModeLabel => 'Quick Mode';

  @override
  String get quickModeSubtitle =>
      'Bypass streaming animations and output full turns rapidly';

  @override
  String get appearanceSectionTitle => 'Appearance & Visual Theme';

  @override
  String get appearanceSectionSubtitle =>
      'Customize interface color themes, dark mode, and reading font size';

  @override
  String get themeModeLabel => 'Theme Mode';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeSystem => 'System';

  @override
  String get themeColorPalette => 'Theme Palette';

  @override
  String get themeColorPaletteHint => 'Tap to switch instantly';

  @override
  String chatFontSizeLabel(int size) {
    return 'Narrative Text Font Size: $size pt';
  }

  @override
  String get chatFontCompact => 'Compact';

  @override
  String get chatFontStandard => 'Standard';

  @override
  String get chatFontSpacious => 'Spacious';

  @override
  String get previewTypographyTitle => 'Live Typography Preview';

  @override
  String get previewTypographySample =>
      '“LT Dialogue” — In the tapestry of interwoven worldlines, every decision you make ripples through fate. Dark undercity corridors, skyward mechanical ruins: all legends begin here.';

  @override
  String get readingScrollTitle => 'Reading & Scroll Controls';

  @override
  String get readingScrollSubtitle =>
      'Control screen scrolling behavior during generation';

  @override
  String get autoScrollLabel => 'Auto-scroll during generation';

  @override
  String get autoScrollSubtitleOn =>
      'Active: Screen continuously scrolls to the newest words as they generate.';

  @override
  String get autoScrollSubtitleOff =>
      'Recommended (Reading First): Screen stays steady so you can read from the beginning without disruption.';

  @override
  String get dataManagementTitle => 'Data Management & Usage Stats';

  @override
  String get dataManagementSubtitle =>
      'View Token consumption, TTS voice settings, and storage controls';

  @override
  String get tokenUsageTitle => 'Local Token Consumption Estimate';

  @override
  String get sessionTokensLabel => 'Current Session Tokens';

  @override
  String get totalTokensLabel => 'Total Persisted Tokens';

  @override
  String get readAloudSectionTitle => 'Voice Message Reading (TTS)';

  @override
  String get readAloudSupportedPlatform =>
      'Platform supports system speech synthesis. Available in dialogue and studio.';

  @override
  String get readAloudUnsupportedPlatform =>
      'Platform does not support system speech synthesis.';

  @override
  String get readAloudEnable => 'Enable Voice Reading';

  @override
  String get readAloudEnableSubtitle =>
      'Support reading text in dialogue, studio, and assembly';

  @override
  String get readAloudAutoRead => 'Auto Read on Completion';

  @override
  String get readAloudAutoReadSubtitle =>
      'Automatically read aloud when AI completes narrative turn';

  @override
  String get readAloudRate => 'Speech Rate';

  @override
  String get readAloudPitch => 'Pitch';

  @override
  String get readAloudVolume => 'Volume';

  @override
  String get readAloudLanguage => 'Read-Aloud Language';

  @override
  String get readAloudAutoDetect => 'Auto Detect';

  @override
  String get readAloudAutoDetectHint =>
      'Automatically select system voice language based on text.';

  @override
  String get readAloudFixedHint =>
      'All text will be read in the selected language.';

  @override
  String get readAloudUnsupportedLanguage => ' (Unsupported)';

  @override
  String readAloudAvailableLanguagesCount(int count) {
    return 'System available voices: $count';
  }

  @override
  String get readAloudDisabledInSettings =>
      'Voice reading is disabled in settings';

  @override
  String get readAloudStop => 'Stop Reading';

  @override
  String get readAloudStart => 'Read Aloud';

  @override
  String get diagnosticExportTitle => 'Diagnostic Session Export';

  @override
  String get diagnosticExportSubtitle =>
      'Only exports the last 30 turns of current branch; API credentials and hidden thoughts are excluded.';

  @override
  String get exportDiagnosticJson => 'Export Diagnostic JSON';

  @override
  String get cacheStorageTitle => 'Cache & Storage Management';

  @override
  String get clearCache => 'Clear Temp Cache';

  @override
  String get clearCacheSuccess => 'Temporary cache cleared and counters reset';

  @override
  String get clearAllData => 'Clear All Local Data';

  @override
  String get clearDataDialogTitle => 'Reset All Local Data';

  @override
  String get clearDataDialogMessage =>
      'Are you sure you want to delete all local adventures, cards, and cached content?\nThis action cannot be undone.';

  @override
  String get exportChatTitle => 'Export Chat';

  @override
  String get importChatTitle => 'Import Chat';

  @override
  String get dashboardHeroTitle =>
      'LT Dialogue · Exploration & Narrative Studio';

  @override
  String get dashboardHeroSubtitle =>
      'Interactive fiction & immersive RPG storytelling space';

  @override
  String get dashboardWizardCardTitle => 'Four-Step Custom Wizard';

  @override
  String get dashboardWizardCardDesc =>
      'Start from blank canvas, define worldview, character cards, prologue and opening action.';

  @override
  String get dashboardWizardCardAction => 'Launch Wizard';

  @override
  String get dashboardPresetCardTitle => 'Preset Scene Studio';

  @override
  String get dashboardPresetCardDesc =>
      'Browse prebuilt adventure scripts, start with one click or fine-tune.';

  @override
  String get dashboardPresetCardAction => 'View Presets';

  @override
  String get dashboardLibraryCardTitle => 'Resource Library';

  @override
  String get dashboardLibraryCardDesc =>
      'Review and manage your worldviews, character cards, and NPC archives.';

  @override
  String get dashboardLibraryCardAction => 'Manage Library';

  @override
  String get dashboardSettingsCardTitle => 'Settings Center';

  @override
  String get dashboardSettingsCardDesc =>
      'Configure model connection parameters, visual themes, and data management.';

  @override
  String get dashboardSettingsCardAction => 'Enter Settings';

  @override
  String get recentAdventuresTitle => 'Recent Adventures';

  @override
  String get noRecentAdventures =>
      'No adventures yet. Launch a wizard or choose a preset to begin.';

  @override
  String get continueAdventure => 'Continue';

  @override
  String get featuredWorldviews => 'Featured Worldviews';

  @override
  String get featuredCharacters => 'Featured Characters';

  @override
  String get resourceLibraryTitle => 'Resource Library';

  @override
  String get resourceLibrarySubtitle =>
      'Browse and manage worldviews, character cards, and scenario templates';

  @override
  String get createResourceAction => 'Create Resource';

  @override
  String get searchResources => 'Search resources...';

  @override
  String get allResources => 'All';

  @override
  String get worldviewsTab => 'Worldviews';

  @override
  String get charactersTab => 'Characters';

  @override
  String get templatesTab => 'Templates';

  @override
  String get recycleBinTitle => 'Recycle Bin';

  @override
  String get emptyRecycleBin => 'Recycle bin is empty';

  @override
  String get restoreAction => 'Restore';

  @override
  String get permanentlyDelete => 'Delete Permanently';

  @override
  String get resourceStudioTitle => 'Resource Studio';

  @override
  String get resourceStudioSubtitle =>
      'Multi-part progressive authoring and capacity management';

  @override
  String get outlineTab => 'Outline';

  @override
  String get capacityTab => 'Capacity';

  @override
  String get historyTab => 'History';

  @override
  String get generatePart => 'Generate Content';

  @override
  String get regeneratePart => 'Regenerate';

  @override
  String get partSaved => 'Changes saved';

  @override
  String get partSaving => 'Saving...';

  @override
  String get assemblyWizardTitle => 'Adventure Assembly & Readiness';

  @override
  String get wizardWorldviewAiSummary =>
      'Describe a genre or core idea. AI can draft a worldview here or create a detailed, multi-section setting in the library.';

  @override
  String get adventureWizardTitle => 'Custom Adventure Wizard';

  @override
  String get assemblyStepWorld => '1. Worldview';

  @override
  String get assemblyStepCharacters => '2. Character';

  @override
  String get assemblyStepNpcs => '3. NPCs';

  @override
  String get assemblyStepConfig => '4. Config & Opening';

  @override
  String get assemblyPreviewTitle => 'Assembly Preview';

  @override
  String get startAdventureAction => 'Start Adventure';

  @override
  String get readinessChecking => 'Checking resource readiness...';

  @override
  String get readinessPassed => 'All resources ready';

  @override
  String get readinessFailed => 'Resources require preparation or compression';

  @override
  String get adventureSessionTitle => 'Adventure Session';

  @override
  String get inputActionHint =>
      'What do you do next? Enter your action or dialogue...';

  @override
  String get sendAction => 'Send';

  @override
  String get aiThinking => 'AI is pondering...';

  @override
  String get aiWriting => 'AI is writing...';

  @override
  String get diceCheckTitle => 'Dice Check';

  @override
  String get turnSettling => 'Settling turn options...';

  @override
  String get bookmarkAdded => 'Bookmark added';

  @override
  String get bookmarkRemoved => 'Bookmark removed';

  @override
  String get messageCopied => 'Message copied to clipboard';

  @override
  String get messageEdited => 'Message edited';

  @override
  String get chatEditMessage => 'Edit message';

  @override
  String get chatReadAloudUnsupported =>
      'Read aloud is not supported on this platform';

  @override
  String get chatCopyReasoning => 'Copy reasoning (thought chain)';

  @override
  String get chatReasoningCopied => 'Reasoning copied to clipboard';

  @override
  String get chatRetryWithModel => 'Retry with another model';

  @override
  String get chatFork => 'Fork from here';

  @override
  String chatBranchCreated(Object branch) {
    return 'Created branch $branch';
  }

  @override
  String get chatDeleteMessage => 'Delete';

  @override
  String get chatSearchHint => 'Search conversation...';

  @override
  String get chatBookmarksOnly => 'Bookmarks only';

  @override
  String get chatMoreActions => 'More actions';

  @override
  String get chatEditStatus => 'Edit status';

  @override
  String get chatDeleteStatus => 'Delete status';

  @override
  String get readAloudPause => 'Pause';

  @override
  String get readAloudPauseRestart => 'Pause (resume from this segment)';

  @override
  String get readAloudResume => 'Resume reading';

  @override
  String get readAloudPreparing => 'Preparing to read';

  @override
  String get readAloudPrevious => 'Previous segment';

  @override
  String get readAloudNext => 'Next segment';

  @override
  String get tokenCurrentScene => 'Current Scene Tokens';

  @override
  String get tokenHistoryTotal => 'Historical Total Tokens';

  @override
  String get tokenCurrentSceneDescription => 'Tokens used in current scene';

  @override
  String get tokenHistoryDescription => 'Historical total recorded locally';

  @override
  String get readAloudPlatformSupportedMessage =>
      'This platform supports system speech synthesis; available in dialogue and studio.';

  @override
  String get diagnosticExportFailed =>
      'Diagnostic export failed. Please try again later.';

  @override
  String diagnosticExported(Object path) {
    return 'Diagnostic session exported: $path';
  }

  @override
  String get clearHistoryTitle => 'Clear Conversation History';

  @override
  String get clearHistoryMessage =>
      'Clear all saved conversations?\nWorldviews and character cards will remain, but scene chat history cannot be recovered.';

  @override
  String get clearHistoryConfirm => 'Clear History';

  @override
  String get clearHistorySuccess => 'All conversation history was cleared';

  @override
  String get readAloudRateLabel => 'Speech Rate';

  @override
  String get readAloudPitchLabel => 'Pitch';

  @override
  String get readAloudLanguageHintAuto =>
      'Automatically select an available system voice language for each passage.';

  @override
  String get readAloudLanguageHintFixed =>
      'All passages will be read in the selected language.';

  @override
  String readAloudSupportedCount(Object count) {
    return 'System available voices: $count';
  }

  @override
  String get generationWaiting => 'Waiting for content generation…';

  @override
  String get errorTimeoutTitle => 'Request timed out';

  @override
  String get errorTimeoutSuggestion =>
      'Check your network connection and try again';

  @override
  String get errorAuthTitle => 'Authentication failed';

  @override
  String get errorAuthSuggestion => 'Check whether your API key is valid';

  @override
  String get errorRateTitle => 'Too many requests';

  @override
  String get errorRateSuggestion => 'Please wait a moment and try again';

  @override
  String get errorApiTitle => 'API error';

  @override
  String get errorApiSuggestion =>
      'Check your API configuration or try again later';

  @override
  String get errorNetworkTitle => 'Network error';

  @override
  String get errorNetworkSuggestion =>
      'Check your network connection and API settings, then try again';

  @override
  String get switchModelRetry => 'Retry with another model';

  @override
  String get resourceTrashTooltip => 'Recycle bin';

  @override
  String get resourceCreateShort => 'Create';

  @override
  String get resourceNpcTab => 'NPCs';

  @override
  String get resourceRetryLoad => 'Retry';

  @override
  String get resourceEmptyTitle => 'No resources yet';

  @override
  String get resourceNoMatches => 'No matching resources';

  @override
  String get resourceNoSummary => 'No summary';

  @override
  String get resourceMovedToTrash => 'Moved to recycle bin';

  @override
  String get refreshRecycleBin => 'Refresh recycle bin';

  @override
  String permanentDeleteMessage(Object title) {
    return '\"$title\" and its contents will be permanently deleted and cannot be recovered.\nContinue?';
  }

  @override
  String get readinessBlockedTitle => 'Cannot start adventure yet';

  @override
  String get acknowledgeAction => 'Got it';

  @override
  String get staleResourceTitle => 'Resources changed';

  @override
  String get staleResourceMessage =>
      'The following resources changed after the last ready revision:';

  @override
  String get usePreviousReady => 'Start with the previous ready version?';

  @override
  String get chatImportFormat => 'Format';

  @override
  String get chatImportLabel => 'Chat content';

  @override
  String get chatImportHint => 'Paste chat content here...';

  @override
  String get chatImportSuccess => 'Import succeeded';

  @override
  String get chatImportParsing => 'Parsing...';

  @override
  String get chatImportAction => 'Import';

  @override
  String get chatImportEmpty => 'Please paste chat content first';

  @override
  String chatImportFailed(Object error) {
    return 'Import failed: $error';
  }

  @override
  String get chatExportWarning =>
      'Exports may contain conversations and user input. Keep the file safe.';

  @override
  String get chatSaveFailed => 'Save failed';

  @override
  String chatSavedPath(Object path) {
    return 'Saved: $path';
  }

  @override
  String get chatSaving => 'Saving...';

  @override
  String get chatLoadFailedRetry => 'Load failed, retry';

  @override
  String chatCharacterCount(Object count) {
    return '$count characters';
  }

  @override
  String get resourceDetailTitle => 'Resource Details';

  @override
  String get resourceEnterStudio => 'Open Resource Studio';

  @override
  String get resourceLegacyNoStudio =>
      'Advanced authoring is unavailable for legacy resources';

  @override
  String get resourceActions => 'Resource Actions';

  @override
  String get moveToTrashAction => 'Move to Recycle Bin';

  @override
  String moveToTrashMessage(Object name) {
    return 'Move \"$name\" to the recycle bin? It can be restored later.';
  }

  @override
  String get moveToTrashFailed => 'Could not move to recycle bin. Try again.';

  @override
  String get thinkingEngineTitle => 'Deep Thinking Engine';

  @override
  String get thinkingEngineBadge => 'V4.1 Native Reasoning';

  @override
  String get thinkingEngineDescription =>
      'For complex branching adventures and world logic; enables pre-narrative planning with DeepSeek V4.1 reasoning.';

  @override
  String get worldviewDeepThinkingLabel => 'Deep reasoning for worldviews';

  @override
  String get worldviewDeepThinkingSubtitle =>
      'Allow V4.1 reasoning during AI worldview import; disabled by default to reduce first-token latency';

  @override
  String get characterDeepThinkingLabel => 'Deep reasoning for character cards';

  @override
  String get characterDeepThinkingSubtitle =>
      'Allow V4.1 reasoning during AI character import; disabled by default for faster generation';

  @override
  String get reasoningEffortLow => 'Light · Fast response';

  @override
  String get reasoningEffortMedium => 'Balanced · Recommended';

  @override
  String get reasoningEffortHigh => 'Deep thinking · Rich detail';

  @override
  String get reasoningEffortMax => 'Maximum · Rigorous logic';

  @override
  String get restoreRecommended => 'Restore recommended defaults';

  @override
  String get recommendedDefaultsRestored =>
      'Official recommended defaults restored';

  @override
  String get revisionHistoryTitle => 'Revision History';

  @override
  String revisionCount(Object count) {
    return '$count revisions';
  }

  @override
  String get refreshRevisionHistory => 'Refresh revision history';

  @override
  String get noRestorableRevisions => 'No restorable revisions yet';

  @override
  String get currentRevision => 'Current';

  @override
  String get restoreRevision => 'Restore this revision';

  @override
  String get presetParseError =>
      'The scene data could not be parsed or is incomplete';

  @override
  String get presetWorldviewTitle => 'Worldview';

  @override
  String get presetCharacterTitle => 'Protagonist Profile';

  @override
  String get presetOpeningTitle => 'Opening Prologue';

  @override
  String get presetOptionsTitle => 'Initial Action Branches';

  @override
  String get presetNpcTitle => 'Supporting Characters (NPCs)';

  @override
  String get presetCustomizeAction => 'Load and Customize';

  @override
  String get presetDetailsAction => 'Details';

  @override
  String get sidebarEmptyConversationsSubtitle =>
      'Click the button above to start a new adventure';

  @override
  String get sidebarDeleteTooltip => 'Delete conversation';

  @override
  String get sidebarSettingsNotConfigured => 'Settings (Key not configured)';

  @override
  String get characterFallbackName => 'Character A';

  @override
  String get monitoredStatus => 'Monitored Status';

  @override
  String get expandAction => 'Expand ▼';

  @override
  String get collapseAction => 'Collapse ▲';

  @override
  String statusItemsCount(int count) {
    return '$count items';
  }

  @override
  String optionsSectionTitle(int count) {
    return 'Options ($count options)';
  }

  @override
  String get selectPrompt => 'Please select';

  @override
  String get noOptionsAvailable => 'No options available';

  @override
  String get notSpecified => 'Not specified';

  @override
  String itemsSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get backAction => 'Back';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get actionMenuTitle => 'Actions';

  @override
  String get actionMenuSemanticLabel => 'Action menu';

  @override
  String get menuTooltip => 'Menu';

  @override
  String get switchLibrary => 'Switch Library';

  @override
  String get customAttributesTitle => 'Custom Attributes';

  @override
  String get customAttributesSubtitle =>
      'Add custom lore or status for character/NPC with individual inference weighting';

  @override
  String get addCustomAttributeAction => 'Add Item';

  @override
  String get noCustomAttributes => 'No custom attributes';

  @override
  String get customAttributesEmptyHint =>
      'Tap \"Add Item\" above to define signature weapons, taboos, weaknesses, or traits';

  @override
  String get customAttributeNameLabel => 'Item Name *';

  @override
  String get customAttributeNameHint =>
      'e.g. Signature sword, fatal weakness, casting habit';

  @override
  String get deleteAttributeTooltip => 'Delete this item';

  @override
  String get customAttributeContentLabel => 'Content / Lore Description';

  @override
  String get customAttributeContentHint =>
      'Describe effect, origin, or limitation (LLM will heed the importance level)';

  @override
  String get customAttributeImportanceReference => 'Reference';

  @override
  String get customAttributeImportanceImportant => 'Important';

  @override
  String get customAttributeImportanceVeryImportant => 'Very Important';

  @override
  String get customAttributeImportanceCritical => 'Critical';

  @override
  String get feedbackSuccess => 'Success';

  @override
  String get feedbackError => 'Error';

  @override
  String get feedbackWarning => 'Warning';

  @override
  String get feedbackInfo => 'Info';

  @override
  String get refreshFailed => 'Refresh failed, please try again later';

  @override
  String get noRefreshNeeded => 'Current page does not need refresh';

  @override
  String get fontSizeDialogTitle => 'Adjust Font Size';

  @override
  String get fontSizeSmall => 'A Small';

  @override
  String get fontSizeLarge => 'A Large';

  @override
  String get fontSizePreview => 'Preview: Text 123\nFont size sample';

  @override
  String get applyAction => 'Apply';

  @override
  String appliedPresetNotice(String preset) {
    return 'Applied: $preset';
  }

  @override
  String get dialogueParamsTitle => 'Dialogue Parameters';

  @override
  String get paramsPresetLabel => 'Parameter Presets';

  @override
  String get customPreset => 'Custom';

  @override
  String get frequencyPenalty => 'Frequency Penalty';

  @override
  String get presencePenalty => 'Presence Penalty';

  @override
  String get saveWorldviewTitle => 'Save Worldview';

  @override
  String get worldviewInfoSection => 'Worldview Information';

  @override
  String worldviewSavedSuccess(String name) {
    return 'Saved worldview \"$name\"';
  }

  @override
  String saveFailedPrefix(String error) {
    return 'Save failed: $error';
  }

  @override
  String get importCardDialogTitle => 'Import Character Card';

  @override
  String get pasteCardJsonHeader =>
      'Paste SillyTavern / Chub Character Card JSON';

  @override
  String get pasteCardJsonHint => 'Paste character card JSON content here...';

  @override
  String get newDialoguePersonaTitle => 'New Dialogue Persona';

  @override
  String get editDialoguePersonaTitle => 'Edit Dialogue Persona';

  @override
  String get dialoguePersonaSettingHeader => 'Dialogue Persona Settings';

  @override
  String get dialoguePersonaScopeNotice =>
      'Personas here are used for dialogue mode only and can be completely independent of Naira.';

  @override
  String get personaNameLabel => 'Persona Name *';

  @override
  String get personaNameHint => 'e.g. Naira, Advisor, Writing Partner';

  @override
  String get personaRoleLabel => 'Role / Identity';

  @override
  String get personaRoleHint =>
      'e.g. General AI Assistant, Language Coach, Worldview Advisor';

  @override
  String get personaUserAddressLabel => 'User Address';

  @override
  String get personaUserAddressHint => 'e.g. User, Creator, Commander, Teacher';

  @override
  String get personaPersonalityLabel => 'Personality & Behavioral Traits';

  @override
  String get personaPersonalityHint =>
      'Describe personality, values, and problem-solving style';

  @override
  String get personaSpeakingStyleLabel => 'Speaking Style';

  @override
  String get personaSpeakingStyleHint =>
      'e.g. Concise, gentle, explain with steps and examples when needed';

  @override
  String get personaBackgroundLabel => 'Background Lore';

  @override
  String get personaBackgroundHint =>
      'Where the persona comes from and what they know';

  @override
  String get personaContextLabel => 'Dialogue Context';

  @override
  String get personaContextHint =>
      'Describe the context in which the character communicates with the user';

  @override
  String get personaDirectivesLabel => 'Extra Behavioral Directives';

  @override
  String get personaDirectivesHint =>
      'Optional: supplementary behavioral rules the persona must follow';

  @override
  String get deleteDialoguePersonaTitle => 'Delete Dialogue Persona?';

  @override
  String deleteDialoguePersonaMessage(String name) {
    return 'Are you sure you want to delete \"$name\"?';
  }

  @override
  String deleteCharacterCardFailed(String error) {
    return 'Failed to delete character card: $error';
  }

  @override
  String get nameRequired => 'Please enter a name';

  @override
  String get manualCreatedSource => 'Manually created';

  @override
  String get createAction => 'Create';

  @override
  String get nameLabel => 'Name';

  @override
  String get descriptionOptionalLabel => 'Description (Optional)';

  @override
  String get fontSizeAdjustment => 'Font Size Adjustment';

  @override
  String get fontSizeSmallA => 'A Small';

  @override
  String get fontSizeLargeA => 'A Large';

  @override
  String get dialogueParams => 'Dialogue Parameters';

  @override
  String get parameterPresets => 'Parameter Presets';

  @override
  String get presetDeepThinking => 'Deep Thinking (V4.1 Complex Deduction)';

  @override
  String get presetFastNarrative => 'Fast Narrative (Default)';

  @override
  String get presetDeepReasoning => 'Extreme Reasoning (Puzzle Solving)';

  @override
  String get presetLightweightDaily => 'Lightweight Daily (Low Latency)';

  @override
  String appliedPreset(String preset) {
    return 'Applied: $preset';
  }

  @override
  String get saveWorldview => 'Save Worldview';

  @override
  String get worldviewInfo => 'Worldview Information';

  @override
  String get name => 'Name';

  @override
  String get descriptionOptional => 'Description (Optional)';

  @override
  String worldviewSaved(String name) {
    return 'Saved worldview \"$name\"';
  }

  @override
  String saveFailed(String error) {
    return 'Save failed: $error';
  }

  @override
  String get unknownError => 'Unknown error';

  @override
  String get importCharacterCard => 'Import Character Card';

  @override
  String get pasteCharacterCardJson =>
      'Paste SillyTavern / Chub character card JSON';

  @override
  String get pasteCharacterCardJsonHint =>
      'Paste character card JSON content here...';

  @override
  String get importAction => 'Import';

  @override
  String get editDialoguePersonaCard => 'Edit Dialogue Persona Card';

  @override
  String get newDialoguePersonaCard => 'New Dialogue Persona Card';

  @override
  String get dialoguePersonaSettings => 'Dialogue Character Settings';

  @override
  String get dialoguePersonaSettingsDesc =>
      'Characters here are only used for dialogue mode and can completely bypass Naela.';

  @override
  String get personaNameRequired => 'Character Name *';

  @override
  String get personaRole => 'Role & Identity';

  @override
  String get personaUserCallName => 'How to Address User';

  @override
  String get personaUserCallNameHint =>
      'e.g. User, Creator, Commander, Teacher';

  @override
  String get personaPersonality => 'Personality & Traits';

  @override
  String get personaSpeakingStyle => 'Speaking Style';

  @override
  String get personaBackground => 'Background';

  @override
  String get personaScenario => 'Dialogue Scenario';

  @override
  String get personaScenarioHint =>
      'Describe in what context the character communicates with the user';

  @override
  String get personaSystemPrompt => 'Extra System Instructions';

  @override
  String get personaSystemPromptHint =>
      'Optional: supplementary rules the character must follow';

  @override
  String deleteDialoguePersonaPrompt(String name) {
    return 'Are you sure you want to delete \"$name\"?';
  }

  @override
  String get pleaseEnterPersonaName => 'Please enter character name';

  @override
  String get manuallyCreated => 'Manually created';

  @override
  String get sidebarSystemSettings => 'System Settings';

  @override
  String get settingsTabModelAndApi => 'Models & API';

  @override
  String get settingsTabModelAndApiSubtitle => 'Provider and key configuration';

  @override
  String get settingsTabSessionParams => 'Session Parameters';

  @override
  String get settingsTabSessionParamsSubtitle =>
      'Sampling rate and deep thinking';

  @override
  String get settingsTabAppearance => 'Theme & Palette';

  @override
  String get settingsTabAppearanceSubtitle => 'Light/dark and color accents';

  @override
  String get settingsTabStorage => 'Data Management';

  @override
  String get settingsTabStorageSubtitle => 'Token statistics and storage';

  @override
  String get settingsCustomProvider => 'Custom';

  @override
  String get settingsReturnToLobby => 'Return to Lobby';

  @override
  String get settingsReturnToSettingsList => 'Return to Settings';

  @override
  String get settingsConfigsCategory => 'Configuration Categories';

  @override
  String settingsOfficialInService(String provider) {
    return '$provider Official Active';
  }

  @override
  String get settingsKeyNotConfigured => 'Key Not Configured';

  @override
  String get settingsLlmConnected => 'LLM Service Connected';

  @override
  String get settingsLlmDisconnected => 'API Key Not Configured';

  @override
  String get settingsLlmConnectedSubtitle =>
      'Click to manage provider, models, and endpoints';

  @override
  String get settingsLlmDisconnectedSubtitle =>
      'Click to configure API key to start reasoning';

  @override
  String get settingsEngineTitle => 'LT Core Engine';

  @override
  String get settingsEngineSubtitle => 'SQLite · Local Encryption First';

  @override
  String get settingsSystemConfigBadge => 'System Config';

  @override
  String get inferenceParamsTitle => 'Inference & Sampling Parameters';

  @override
  String get inferenceParamsSubtitle =>
      'Adjust temperature, sampling thresholds, and deep thinking intensity';

  @override
  String get deepseekThinkingHint =>
      '💡 Note: In DeepSeek V4.1 thinking mode, sampling is managed adaptively by the model. In non-thinking mode, top_p is fixed at 1.0 and only temperature is adjustable.';

  @override
  String get temperatureTitle => 'Generation Temperature';

  @override
  String get temperatureDescription =>
      '0.0 Strict & Precise ↔ 2.0 Highly Creative & Diverse';

  @override
  String get topPTitle => 'Nucleus Sampling (Top-P)';

  @override
  String get topPDescription =>
      'Cumulative probability cutoff; recommended 0.90 ~ 0.95';

  @override
  String get maxTokensTitle => 'Max Generation Length (Max Tokens)';

  @override
  String get maxTokensDescription => 'Maximum token budget per turn';

  @override
  String get paramsRealtimeNotice =>
      'Note: Parameter changes take effect immediately without saving.';

  @override
  String testConnectionSuccess(int elapsed) {
    return 'Connection successful! (${elapsed}ms), service status excellent.';
  }

  @override
  String get testConnectionFailure =>
      'Connection failed. Please verify your API key and network connection.';

  @override
  String testConnectionFailureDetail(String error) {
    return 'Connection failed: $error';
  }

  @override
  String get statusReady => 'Ready';

  @override
  String get statusNotReady => 'Not Ready';

  @override
  String modelEndpointSummary(String model, String endpoint) {
    return 'Model: $model · Endpoint: $endpoint';
  }

  @override
  String get quickTesting => 'Testing...';

  @override
  String get quickTest => 'Quick Test';

  @override
  String get llmProviderSectionTitle => 'LLM Service Provider';

  @override
  String get llmProviderSectionSubtitle =>
      'Select and configure language model services for dialogue and reasoning';

  @override
  String get modelProviderLabel => 'Model Provider';

  @override
  String get selectInServiceModal => 'Select Active Model';

  @override
  String get customModelNameLabel => 'Custom Model Name';

  @override
  String get customModelNameHint => 'e.g. gpt-4o, llama-3.3-70b, qwen-max';

  @override
  String get apiEndpointLabel => 'API Endpoint (Base URL)';

  @override
  String get apiSecurityNotice =>
      'Key is encrypted and stored locally in SQLite; never relayed via intermediate servers';

  @override
  String get promptSettingsTitle => 'Prompts & Deduction Planning';

  @override
  String get importPresets => 'Import Presets';

  @override
  String get exportPresets => 'Export Presets';

  @override
  String get previewPromptAction => 'Preview';

  @override
  String get importPresetTitle => 'Import Prompt Presets';

  @override
  String get exportPresetTitle => 'Export Prompt Presets';

  @override
  String get presetJsonLabel => 'Prompt Preset JSON';

  @override
  String get presetJsonEmptyError => 'Please enter preset JSON';

  @override
  String presetImportFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String get presetJsonCopied => 'Prompt preset JSON copied';

  @override
  String get copyAllAction => 'Copy All';

  @override
  String get dialogueLevelSectionTitle => 'Dialogue Level';

  @override
  String get dialogueLevelSectionSubtitle =>
      'Select output word budget and descriptive detail density per turn';

  @override
  String get systemPromptSectionTitle => 'System Prompt';

  @override
  String get systemPromptSectionSubtitle =>
      'Clean baseline. Defaults to minimal universal deduction guidelines if left blank.';

  @override
  String get systemPromptHint =>
      'Enter custom system instructions, world rules, or character guidelines (leave empty for defaults)...';

  @override
  String charCountLabel(int count) {
    return '$count characters written';
  }

  @override
  String get clearAction => 'Clear';

  @override
  String get systemPromptSaved => 'Global system prompt saved';

  @override
  String get savePromptAction => 'Save Prompt';

  @override
  String get authorsNoteSectionTitle => 'Author\'s Note';

  @override
  String get authorsNoteSectionSubtitle =>
      'Inject high-weight directives at specified turn depths in the session context.';

  @override
  String get authorsNoteHint =>
      'e.g. Focus on detailed protagonist actions, maintain an atmosphere of suspense...';

  @override
  String get injectionDepth => 'Injection Depth';

  @override
  String get depthFollowSystem => 'Directly after system prompt';

  @override
  String depthBeforeRound(int depth) {
    return '$depth turns from bottom';
  }

  @override
  String get injectionFrequency => 'Injection Frequency';

  @override
  String freqEveryRound(int freq) {
    return 'Every $freq turns';
  }

  @override
  String get authorsNoteSaved => 'Author\'s note settings saved';

  @override
  String get saveNoteConfigAction => 'Save Note Config';

  @override
  String get promptPreviewTitle => 'Real-time Prompt Assembly Preview';

  @override
  String get copyFullPrompt => 'Copy Full Prompt';

  @override
  String get fullPromptCopied => 'Full assembled prompt copied to clipboard';

  @override
  String promptPreviewStats(int chars, int tokens) {
    return '~$chars chars · estimated $tokens tokens';
  }

  @override
  String get resourceTypeWorldview => 'Worldview';

  @override
  String get resourceTypeCharacter => 'Character';

  @override
  String get resourceTypeNpc => 'NPC';

  @override
  String get resourceStatusGenerating => 'Generating';

  @override
  String get resourceStatusSaved => 'Saved';

  @override
  String get resourceStatusOptimizationSuggested => 'Optimization Suggested';

  @override
  String get resourceStatusOptimizing => 'Optimizing';

  @override
  String get resourceStatusReady => 'Ready';

  @override
  String get resourceStatusOptimizationFailed => 'Optimization Failed';

  @override
  String get resourceUnknownTime => 'Unknown Time';

  @override
  String get resourceCreateTitle => 'Create Resource';

  @override
  String get resourceTypeSectionTitle => 'Resource Type';

  @override
  String get resourceTypeSectionDescription =>
      'Choose the type of content carrier to build';

  @override
  String get resourcePreselectedType => 'Selected Type';

  @override
  String get resourceCreationMethodSectionTitle => 'Creation Method';

  @override
  String get resourceCreationMethodSectionDescription =>
      'Choose between AI-assisted derivation or manual text drafting based on your creative needs';

  @override
  String get resourceAiCreationTitle => 'AI Creation';

  @override
  String get resourceAiCreationDescription =>
      'Automatically derive chapter outlines and body content from reference materials, fiction text, or existing assets using AI.';

  @override
  String get resourceRecommendBadge => 'Recommended';

  @override
  String get resourceManualCreationTitle => 'Manual Creation';

  @override
  String get resourceManualCreationDescription =>
      'Set custom name and summary, create a blank resource, and freely organize chapters and content.';

  @override
  String get resourceManualCreateTitle => 'Create Resource Manually';

  @override
  String get resourceBasicInfoTitle => 'Basic Information';

  @override
  String get resourceManualBasicInfoDescription =>
      'Fill in the type, name, and brief introduction of the resource. After creation, you can freely edit the text in Studio.';

  @override
  String get resourceNameLabel => 'Name';

  @override
  String get resourceManualNameHint => 'Enter a clear and distinct name';

  @override
  String get resourceSummaryOptionalLabel => 'Summary (Optional)';

  @override
  String get resourceManualSummaryHint =>
      'Briefly describe the role and background setting of the resource';

  @override
  String get resourceCreateAction => 'Create';

  @override
  String get resourceInputNameError => 'Please enter a resource name';

  @override
  String get resourceAiCreateTitle => 'AI Resource Creation';

  @override
  String get resourceAiBasicInfoDescription =>
      'Define the carrier type and title of the resource to be generated';

  @override
  String get resourceAiNameHint =>
      'Enter the setting or character name to be generated';

  @override
  String get resourceAssociateWorldviewTitle =>
      'Associate Worldview (Optional)';

  @override
  String get resourceAssociateWorldviewDescription =>
      'Specify the native worldview for the character or NPC as supplemental context during generation';

  @override
  String get resourceNoAvailableWorldview =>
      'No worldview available to associate';

  @override
  String get resourceNotSpecified => 'Not specified';

  @override
  String get resourceReferenceSourceTitle => 'Reference Material Source';

  @override
  String get resourceReferenceSourceDescription =>
      'Provide worldview background, novel settings, or associated resources; AI will extract the essence and derive the chapter structure';

  @override
  String get resourceTabPaste => 'Paste';

  @override
  String get resourceTabFile => 'File';

  @override
  String get resourceTabExistingResource => 'Existing Resource';

  @override
  String get resourcePasteReferenceLabel => 'Paste Reference Content';

  @override
  String get resourcePasteReferenceHint =>
      'Enter or paste novel outlines, setting drafts, or background descriptions...';

  @override
  String get resourceFileNameLabel => 'File Name';

  @override
  String get resourceFileNameHint => 'e.g. world_notes.md';

  @override
  String get resourceFileContentLabel => 'File Text Content';

  @override
  String get resourceFileContentHint =>
      'Paste or enter raw text from within the file...';

  @override
  String get resourceNoExistingInLibrary =>
      'No ready resources available to associate in the library. Please switch to Paste or File input.';

  @override
  String get resourceSelectExistingLabel => 'Select Existing Resource';

  @override
  String get resourceSelectExistingHint =>
      'Click to select a reference existing resource';

  @override
  String get resourceGenerationLengthTitle => 'Generation Length';

  @override
  String get resourceGenerationLengthDescription =>
      'Control the approximate target word count of the AI generated resource text';

  @override
  String get resourceTargetCharactersLabel => 'Target Word Count';

  @override
  String resourceTargetCharactersValue(Object count) {
    return '$count chars';
  }

  @override
  String get resourceLengthShort => 'Short';

  @override
  String get resourceLengthLong => 'Long';

  @override
  String get resourceStartCreateAction => 'Start Creation';

  @override
  String get resourceInputOrPasteReferenceError =>
      'Please enter or paste reference material text';

  @override
  String get resourceInputFileNameError => 'Please enter a file name';

  @override
  String get resourceInputFileContentError => 'Please enter file content';

  @override
  String get resourceSelectExistingError =>
      'Please select an existing resource as reference';

  @override
  String get resourcePastedContentLabel => 'Pasted Content';

  @override
  String get resourceLoadFailedRetry =>
      'Failed to load resource library. Please try again.';

  @override
  String get resourceCreationFailedRetry =>
      'Failed to create resource. Please try again.';

  @override
  String get resourceUnnamed => 'Unnamed Resource';

  @override
  String get resourceRevisionResourceKind => 'Resource';

  @override
  String get resourceRevisionSectionKind => 'Section';

  @override
  String get resourceRevisionPartKind => 'Paragraph';

  @override
  String resourceTrashSubtitle(
      Object deletedAt, Object expiresAt, Object kind, Object reason) {
    return '$kind · $reason · Deleted at $deletedAt · Kept until $expiresAt';
  }

  @override
  String resourceTrashRestoreFailed(Object error) {
    return 'Restore failed: $error';
  }

  @override
  String get resourceTrashPermanentDeleteSuccess => 'Permanently deleted';

  @override
  String resourceTrashPermanentDeleteFailed(Object error) {
    return 'Permanent delete failed: $error';
  }

  @override
  String get modeTitleConversation => 'Conversation Library';

  @override
  String get modeTitleAdventure => 'Scenario Library';

  @override
  String get modeTitleCreation => 'Creation Library';

  @override
  String get modeEmptyTitleConversation => 'No conversation character cards';

  @override
  String get modeEmptyTitleAdventure => 'No scenario resources';

  @override
  String get modeEmptyTitleCreation => 'No creation resources';

  @override
  String get modeEmptySubtitleConversation =>
      'Create custom character cards or view past chat history.';

  @override
  String get modeEmptySubtitleAdventure =>
      'Import characters, locations, rules, or plot resources for scenario dialogue.';

  @override
  String get modeEmptySubtitleCreation =>
      'Import worldviews, character settings, chapter references, or writing materials for creation mode.';

  @override
  String get resourceStudioRefreshTooltip => 'Refresh';

  @override
  String get resourceStudioTocTitle => 'Table of Contents';

  @override
  String get resourceStudioNoContent =>
      'Current resource has no content to display.';

  @override
  String get resourceStudioReadAloudAll => 'Read Aloud Full Text';

  @override
  String get resourceStudioEditPart => 'Edit Text';

  @override
  String get resourceStudioDeletePart => 'Delete Paragraph';

  @override
  String get resourceStudioPartNotExistCannotEdit =>
      'This paragraph no longer exists and cannot be edited';

  @override
  String get resourceStudioPublishCompressionTitle =>
      'Publish Compression Results';

  @override
  String get resourceStudioPublishCompressionMessage =>
      'The compressed text will replace current content. The original text will be recorded as a historical revision and can be restored at any time.\nAre you sure you want to publish?';

  @override
  String get resourceStudioPublishCompressionAction => 'Publish';

  @override
  String get resourceStudioRestoreRevisionTitle =>
      'Restore Historical Revision';

  @override
  String get resourceStudioRestoreRevisionMessage =>
      'Current content will be replaced by this historical revision. The content before replacement will also be kept in version history.\nAre you sure you want to restore?';

  @override
  String get resourceStudioRestoreRevisionAction => 'Restore';

  @override
  String get resourceStudioDeletePartTitle => 'Delete Paragraph';

  @override
  String resourceStudioDeletePartMessage(Object title) {
    return '“$title” will be moved to Recycle Bin and can be restored from Recycle Bin.\nAre you sure you want to delete?';
  }

  @override
  String get resourceStudioDeletePartAction => 'Delete';

  @override
  String get resourceStudioPartNotExistCannotDelete =>
      'This paragraph no longer exists and cannot be deleted';

  @override
  String get resourceStudioMovedToTrash =>
      'Moved to Recycle Bin. You can restore it from Recycle Bin';

  @override
  String resourceStudioDeletePartFailed(Object error) {
    return 'Failed to delete paragraph: $error';
  }

  @override
  String get resourceStudioContinueGenerating => 'Continue Generation';

  @override
  String get resourceStudioPauseGenerating => 'Pause';

  @override
  String get resourceStudioCancelGenerating => 'Cancel';

  @override
  String get resourceStudioRetryGenerating => 'Retry';

  @override
  String get resourceStudioCreatingAndStarting =>
      'Creating resource and starting generation';

  @override
  String resourceStudioTargetCharacters(Object count) {
    return 'Target approx. $count chars';
  }

  @override
  String get resourceStudioCreationFailed => 'Resource creation failed';

  @override
  String get resourceStudioPleaseRetryLater => 'Please try again later';

  @override
  String get resourceStudioRetryCreation => 'Retry Creation';

  @override
  String get resourceStudioSelectResourceOrSession =>
      'Select Resource or Generation Session';

  @override
  String get resourceStudioSelectSession => 'Select Generation Session';

  @override
  String get resourceStudioCreateAndStart => 'Create and Start Generation';

  @override
  String get resourceStudioPendingAiPlan => 'Pending AI Plan';

  @override
  String get resourceStudioConfirmAndStart => 'Confirm and start generation';

  @override
  String resourceStudioUnfinishedTask(Object index) {
    return 'Unfinished Generation Task $index';
  }

  @override
  String get resourceStudioGeneratingStatus => 'Generating';

  @override
  String get resourceStudioResourceLabel => 'Resource';

  @override
  String get resourceStudioNoResourceOrSession =>
      'No resources or recoverable generation sessions.';

  @override
  String get resourceStudioAddSectionTitle => 'Add Section';

  @override
  String get resourceStudioSectionTitleField => 'Section Title';

  @override
  String get sectionControlsTitle => 'Section Controls';

  @override
  String sectionControlsCount(Object count) {
    return '$count sections';
  }

  @override
  String get sectionControlsAdd => 'Add Section';

  @override
  String get sectionControlsEmpty => 'This resource has no sections yet.';

  @override
  String sectionControlsLoadMore(Object shown, Object total) {
    return 'Load more (showing $shown/$total)';
  }

  @override
  String get sectionControlsUnnamed => '(Unnamed Section)';

  @override
  String sectionControlsOrderIndex(Object index) {
    return 'No. $index';
  }

  @override
  String sectionControlsUpdated(Object time) {
    return 'Updated $time';
  }

  @override
  String get sectionControlsValidate => 'Validate';

  @override
  String get sectionControlsMoreActions => 'More Actions';

  @override
  String get sectionControlsRename => 'Rename';

  @override
  String get sectionControlsMoveUp => 'Move Up';

  @override
  String get sectionControlsMoveDown => 'Move Down';

  @override
  String get sectionControlsDelete => 'Delete';

  @override
  String get sectionControlsDeleteTitle => 'Delete Section';

  @override
  String sectionControlsDeleteMessage(Object title) {
    return 'Are you sure you want to delete “$title” and all its contents?';
  }

  @override
  String get sectionControlsGenerate => 'Generate';

  @override
  String get sectionControlsRegenerate => 'Regenerate';

  @override
  String get sectionControlsNoTasksTooltip =>
      'This section has no generation task (not created from AI blueprint) and cannot be generated';

  @override
  String get sectionControlsRegenerateTooltip =>
      'Rerun the generation task for this section; current content will be saved as history and can be restored at any time';

  @override
  String get sectionControlsRerunTooltip =>
      'Rerun the generation task for this section';

  @override
  String get sectionControlsRenameDialogTitle => 'Rename Section';

  @override
  String get partEditorUnsavedDraftFound => 'Unsaved Draft Found';

  @override
  String get partEditorUnsavedDraftDesc =>
      'Last edits were not saved to text. You can load draft to continue editing or discard it.';

  @override
  String get partEditorLoadDraft => 'Load Draft';

  @override
  String get partEditorDiscardDraft => 'Discard Draft';

  @override
  String get partEditorConflictDetected => 'Content Conflict Detected';

  @override
  String get partEditorConflictDesc =>
      'Another operation (such as generation or restore) modified this paragraph. Autosave paused, your text is still in draft. Please choose which version to keep:';

  @override
  String get partEditorUseMyText => 'Use My Text';

  @override
  String get partEditorDiscardMyText => 'Discard My Text';

  @override
  String get partEditorHint => 'Edit text here, autosaves when typing pauses';

  @override
  String get partEditorSaveNow => 'Save Now';

  @override
  String get partEditorFinishEditing => 'Done';

  @override
  String get partEditorDraftLoaded => 'Draft loaded, will save to text on save';

  @override
  String get partEditorDraftDiscarded => 'Draft discarded';

  @override
  String get partEditorEditing => 'Editing…';

  @override
  String get partEditorConflictOtherSaved =>
      'Save conflict: another operation modified this paragraph, please choose which version to keep';

  @override
  String get partEditorConflictDraftRetained =>
      'Save conflict: content retained in draft without overwriting newer version';

  @override
  String partEditorAutoSaved(Object label) {
    return 'Autosaved ($label)';
  }

  @override
  String get partEditorTargetPartMissing =>
      'Target content no longer exists, draft discarded';

  @override
  String get partEditorKeptMyTextAndSaved => 'Kept my text and saved';

  @override
  String get partEditorConflictStillUnresolved =>
      'Conflict still unresolved: paragraph was modified again, please re-select';

  @override
  String partEditorResolveConflictFailed(Object error) {
    return 'Failed to resolve conflict: $error';
  }

  @override
  String partEditorSaving(Object label) {
    return 'Saving ($label)…';
  }

  @override
  String get capacityPanelTitle => 'Capacity';

  @override
  String capacityLatestFailureReason(Object reason) {
    return 'Latest compression failure reason: $reason';
  }

  @override
  String get capacityRefresh => 'Refresh Capacity';

  @override
  String get capacityCompressing => 'Compressing';

  @override
  String get capacityGenerateCandidates => 'Generate Candidates';

  @override
  String capacityRetryFailedWithCount(Object count) {
    return 'Retry Failed ($count)';
  }

  @override
  String get capacityRetryFailed => 'Retry Failed Compression';

  @override
  String capacityPublishWithCount(Object count) {
    return 'Publish Compression ($count)';
  }

  @override
  String get capacityPublish => 'Publish Compression Results';

  @override
  String get capacityOptimizationTip =>
      'Optimization generates a preview first; current content is only replaced after confirmation and can always be restored.';

  @override
  String get capacityPreparingState => 'Preparing resource state.';

  @override
  String capacityTextCharacters(Object count) {
    return 'Text $count chars';
  }

  @override
  String capacitySectionsCount(Object count) {
    return 'Sections $count';
  }

  @override
  String capacityPartsCount(Object count) {
    return 'Blocks $count';
  }

  @override
  String capacityRevisionsCount(Object count) {
    return 'History $count';
  }

  @override
  String capacityArchivedSize(Object count) {
    return 'Archived $count chars';
  }

  @override
  String capacityQueuedJobs(Object count) {
    return 'Pending $count';
  }

  @override
  String capacityPotentialSavings(Object count) {
    return 'Adopting candidates can save approx. $count chars.';
  }

  @override
  String get capacityStatusNormal => 'Normal';

  @override
  String get capacityStatusElastic => 'Elastic';

  @override
  String get capacityStatusOverflow => 'Over Budget';

  @override
  String get outlinePartPending => 'Pending';

  @override
  String get outlinePartGenerated => 'Generated';

  @override
  String get operationFailedRetry => 'Operation failed, please try again';

  @override
  String get resourceImportReturnToEdit => 'Back to Edit';

  @override
  String get resourceImportConfirmSave => 'Confirm & Save';

  @override
  String get characterCardEditTitle => 'Edit Character Card';

  @override
  String get characterCardCreateTitle => 'New Character Card';

  @override
  String get characterCardConfirmDeleteTitle => 'Confirm Deletion';

  @override
  String characterCardConfirmDeleteMessage(Object name) {
    return 'Are you sure you want to delete character card “$name”?';
  }

  @override
  String characterCardDeleteFailed(Object error) {
    return 'Failed to delete character card: $error';
  }

  @override
  String get characterCardNameRequired => 'Please enter at least a name';

  @override
  String characterCardSaveFailed(Object error) {
    return 'Failed to save: $error';
  }

  @override
  String get characterCardInfoSection => 'Character Card Info';

  @override
  String get characterCardWorldviewOptional => 'Matching Worldview (Optional)';

  @override
  String get noneOption => 'None';

  @override
  String get characterCardAiAssistedCreation =>
      'AI-Assisted Character Card Creation';

  @override
  String get detailedMode => 'Detailed Mode';

  @override
  String get conciseMode => 'Concise Mode';

  @override
  String get simpleMode => 'Simple Mode';

  @override
  String characterCardTargetValidChars(Object count, Object max) {
    return 'Target content $count chars (max $max chars)';
  }

  @override
  String get characterCardSavedInStudioTip =>
      'Generation will be saved continuously in Studio, recoverable and tracked in history';

  @override
  String get characterCardRelateCharacterOptional =>
      'Relate Existing Characters (Optional)';

  @override
  String get characterCardRelateCharacterHint =>
      'Click to select existing characters to relate with (leave empty for standalone character)';

  @override
  String get characterCardNoOtherCharacters => 'No other characters';

  @override
  String get characterCardIndependentRole =>
      'Not related (conceive as standalone character)';

  @override
  String characterCardRelatedCount(Object count) {
    return 'Related to $count characters';
  }

  @override
  String get characterCardUnnamed => 'Unnamed Character';

  @override
  String get characterCardBondRelation => 'Bond Relationship:';

  @override
  String get relationCompanion => 'Companion / Teammate';

  @override
  String get relationChildhoodFriend => 'Childhood Friend';

  @override
  String get relationLover => 'Lover / Destined Partner';

  @override
  String get relationMentor => 'Mentor & Disciple';

  @override
  String get relationRival => 'Rival / Competitor';

  @override
  String get relationKin => 'Family / Kin';

  @override
  String get relationBenefactor => 'Life Saver / Benefactor';

  @override
  String get relationEmployment => 'Employment';

  @override
  String get relationCustom => 'Custom relationship...';

  @override
  String get relationCustomDescLabel => 'Custom Relationship Description';

  @override
  String get relationCustomDescHint =>
      'e.g. betrothed fiancée, otherworld soul symbiote...';

  @override
  String get characterCardCoreKeywordHint =>
      'Enter character keywords or setting requirements (e.g. cold silver-haired swordmaster), leave blank for free generation...';

  @override
  String get opening => 'Opening...';

  @override
  String get aiRegenerate => 'AI Regenerate';

  @override
  String get aiFillIn => 'AI Fill In';

  @override
  String get genderLabel => 'Gender';

  @override
  String get genderMale => 'Male';

  @override
  String get genderFemale => 'Female';

  @override
  String get genderOther => 'Other';

  @override
  String get ageLabel => 'Age';

  @override
  String get customGenderLabel => 'Custom Gender';

  @override
  String get occupationLabel => 'Occupation / Identity';

  @override
  String get personalityLabel => 'Personality';

  @override
  String get backgroundStoryLabel => 'Background Story';

  @override
  String get appearanceLabel => 'Appearance';

  @override
  String get physiqueFeaturesLabel => 'Physique & Features';

  @override
  String get inWorldSettingSection => 'In-World Settings';

  @override
  String get factionLabel => 'Faction';

  @override
  String get locationLabel => 'Location / Hometown';

  @override
  String get publicGoalLabel => 'Public Goal';

  @override
  String get hiddenMotiveLabel => 'Hidden Motive (Narrative)';

  @override
  String get abilitySourceLabel => 'Ability Source';

  @override
  String get abilityCostLabel => 'Ability Cost / Limit';

  @override
  String get taboosLabel => 'Taboos (separated by comma)';

  @override
  String get relationsNoteLabel => 'Relationship Notes';

  @override
  String get characterCardDetailTitle => 'Character Card Details';

  @override
  String get characterPersonalityTraits => 'Personality Traits';

  @override
  String get characterDescription => 'Character Description';

  @override
  String get characterCustomFields => 'Custom Fields';

  @override
  String get characterAiAssistantCreateTitle =>
      'AI Assistant Character Creation';

  @override
  String get characterCreateAction => 'Create Character Card';

  @override
  String characterMatchWorldview(Object name) {
    return 'Matching: $name';
  }

  @override
  String get worldviewCreateTitle => 'New Worldview';

  @override
  String get worldviewEditTitle => 'Edit Worldview';

  @override
  String get worldviewDetailedTitle => 'Detailed Worldview';

  @override
  String get worldviewConciseTitle => 'Concise Worldview';

  @override
  String get worldviewOverviewDetailed =>
      'Worldview Overview (counted toward total chars)';

  @override
  String get worldviewOverviewConcise =>
      'Worldview Description (200~500 chars)';

  @override
  String worldviewDetailedLimitTip(Object count) {
    return 'Detailed settings (max $count chars, confirmed content enters scenario dialogue)';
  }

  @override
  String worldviewConfirmDeleteMessage(Object name) {
    return 'Are you sure you want to delete worldview “$name”?';
  }

  @override
  String get worldviewDeleteFailed =>
      'Failed to delete worldview, please try again';

  @override
  String get worldviewAiAssistantTitle => 'AI Assistant Worldview Creation';

  @override
  String get worldviewCreateAction => 'Create Worldview';

  @override
  String get originalTextContent => 'Original Text Content';

  @override
  String get worldviewAiImportTip =>
      'Paste any text (txt / md / HTML / novel snippet); AI will extract and integrate it into a worldview';

  @override
  String get pasteOriginalTextHint => 'Paste original text content here...';

  @override
  String get importModeLabel => 'Import Mode';

  @override
  String get preparingDeduction => 'Preparing deduction…';

  @override
  String deductionProgressChars(Object current, Object partial, Object target) {
    return 'Current valid chars: $current / $target\n$partial';
  }

  @override
  String deductionProgressStage(Object current, Object partial, Object total) {
    return 'Deducing stage $current/$total: $partial';
  }

  @override
  String get autoSaveToLibrary => 'Autosave to Library';

  @override
  String get expectedTotalCharacters => 'Expected Total Characters';

  @override
  String get adaptiveStageHelperText =>
      'Adaptive phased high-concurrency deduction of all 9 modules, accelerating multiple times with autosave';

  @override
  String get aiAnalyzeAction => 'AI Analyze';

  @override
  String get selectImportModeTitle => 'Select Import Mode';

  @override
  String get selectImportModeDesc =>
      'Please select the granularity for this character material. This choice is passed directly to AI.';

  @override
  String get conciseModeDesc =>
      'Concise Mode: Preserves identity, personality, appearance, key experiences and necessary relations without expansion.';

  @override
  String get detailedModeDesc =>
      'Detailed Mode: Fully organizes identity, personality, appearance, background, motives, info and relations within factual scope.';

  @override
  String batchImportTitle(Object kind) {
    return 'Batch AI Import $kind';
  }

  @override
  String get provideCharacterDataTitle => 'Provide Character Materials';

  @override
  String get batchAiRecognitionTip =>
      'AI will identify character names first, generating characters individually after your confirmation.';

  @override
  String get pleaseSelectWorldviewFirst => 'Please select a worldview first';

  @override
  String get selectRelatedCharacters => 'Select Related Characters';

  @override
  String relatedCharactersCount(Object count) {
    return '$count characters related';
  }

  @override
  String get minTotalCharactersLabel => 'Min Total Characters';

  @override
  String get maxTotalCharactersLabel => 'Max Total Characters';

  @override
  String characterDataLabel(Object label) {
    return '$label Materials';
  }

  @override
  String characterDataHint(Object label) {
    return 'Paste chapters, settings, or bios containing multiple $label…';
  }

  @override
  String get planningAction => 'Planning…';

  @override
  String get enterAiStudioAction => 'Enter AI Studio';

  @override
  String selectCandidatesToImportTitle(Object count) {
    return 'Select Characters to Import ($count)';
  }

  @override
  String importSelectedCharactersAction(Object count) {
    return 'Import $count Characters';
  }

  @override
  String get selectCandidatesMultiTitle => 'Select Targets (Multiple)';

  @override
  String get candidatesRelationTip =>
      'Generated materials will establish verifiable relations based on original text and these existing characters.';

  @override
  String confirmRelateCharactersAction(Object count) {
    return 'Confirm Relation to $count Characters';
  }

  @override
  String get pasteCharacterRawTextHint =>
      'Paste character or NPC original text here…';

  @override
  String get stagedDeepGenerationTip =>
      'Staged deep generation, automatically completing to target completeness';

  @override
  String get worldviewModuleRules => 'Rules & Boundaries';

  @override
  String get worldviewModuleState => 'Current World Status';

  @override
  String get worldviewModuleLocations => 'Locations & Geography';

  @override
  String get worldviewModuleFactions => 'Factions & Organizations';

  @override
  String get worldviewModuleCustoms => 'Customs & Daily Life';

  @override
  String get worldviewModuleTimeline => 'History & Timeline';

  @override
  String get worldviewModuleGlossary => 'Glossary';

  @override
  String get worldviewModuleConstraints => 'Creative Constraints';

  @override
  String get notSpecifiedOption => 'Not specified';

  @override
  String get unnamedWorldview => 'Unnamed Worldview';

  @override
  String get noExistingCharacterCards => 'No existing character cards';

  @override
  String selectedCharactersCount(int count) {
    return '$count characters selected';
  }

  @override
  String get generatingEllipsis => 'Generating…';

  @override
  String get aiImportCharacterTitle => 'AI Import Character';

  @override
  String get aiImportNpcTitle => 'AI Import NPC';

  @override
  String get relateExistingCharactersTitle => 'Relate Existing Characters';

  @override
  String get sceneBatchImportCharacterTitle => 'Batch Import Scene Characters';

  @override
  String get sceneBatchImportNpcTitle => 'Batch Import Scene NPCs';

  @override
  String get belongingWorldviewOptional => 'Belonging Worldview (Optional)';

  @override
  String get relateCharactersOptional => 'Relate Characters (Optional)';

  @override
  String get associateWorldviewOptional => 'Associate Worldview (Optional)';

  @override
  String get resourceStatusCancelled => 'Cancelled';

  @override
  String get dashboardWizardBadge => 'Wizard';

  @override
  String get dashboardPresetBadge => 'Complete Script';

  @override
  String get dashboardLibraryBadge => 'All Assets';

  @override
  String get dashboardSettingsBadge => 'Model Config';

  @override
  String get dashboardMyCharacterCards => 'My Character Cards';

  @override
  String get dashboardNoCharacterCardsTitle => 'No Character Cards';

  @override
  String get dashboardNoCharacterCardsDesc =>
      'No characters created yet. Shape your protagonist or companion in the library and select them for adventure.';

  @override
  String get dashboardGoToCharacterLibrary => 'Go to Character Library';

  @override
  String get dashboardDefaultProfession => 'Explorer';

  @override
  String get dashboardNoBackgroundDesc => 'No background description';

  @override
  String get dashboardStartWithCharacter => 'Start with this character';

  @override
  String get dashboardMyWorldSettings => 'My World Settings';

  @override
  String get dashboardNoCustomWorldsTitle => 'No Custom Worlds';

  @override
  String get dashboardNoCustomWorldsDesc =>
      'Blank slate state with no preset worlds. Conceive exclusive worlds in the library or use the wizard to start exploring.';

  @override
  String get dashboardGoToLibrary => 'Go to Library';

  @override
  String get dashboardNoWorldDesc => 'No setting description';

  @override
  String get dashboardStartWithWorld => 'Start with this world';

  @override
  String get dashboardToggleSidebar => 'Toggle sidebar';

  @override
  String get dashboardConfigureApiKey => 'Configure Key';

  @override
  String get dashboardSystemSettings => 'System Settings';

  @override
  String get dashboardNoAdventuresTitle => 'No Scenario Adventures Started';

  @override
  String get dashboardNoAdventuresDesc =>
      'Select \"Custom Wizard\" above to begin your first legend';

  @override
  String get dashboardContinueAdventures => 'Continue Adventures';

  @override
  String get dashboardUnnamedAdventure => 'Unnamed Adventure';

  @override
  String get dashboardDeleteAdventureTooltip => 'Delete adventure record';

  @override
  String dashboardSavedAt(Object time) {
    return 'Saved at $time';
  }

  @override
  String get dashboardContinueExploring => 'Continue Exploring';

  @override
  String get dashboardDeleteAdventureTitle => 'Delete Adventure Record';

  @override
  String dashboardDeleteAdventureMessage(Object title) {
    return 'Are you sure you want to delete scenario \"$title\" and all dialogue logs? This action cannot be undone.';
  }

  @override
  String dashboardAdventureDeleted(Object title) {
    return 'Deleted scenario \"$title\"';
  }

  @override
  String get characterNameLabel => 'Name';

  @override
  String get presetScenesTitle => 'Preset Scenes Studio';

  @override
  String get presetScenesSubtitle =>
      'Ready-to-use complete adventure scenario settings · Start your journey with one click';

  @override
  String get returnToDashboard => 'Return to Lobby';

  @override
  String presetScriptCount(int count) {
    return '$count Scripts';
  }

  @override
  String get presetWizardNewScene => 'New Scene with Wizard';

  @override
  String get presetRefreshList => 'Refresh List';

  @override
  String get presetSearchHint =>
      'Search scenario scripts, worlds, or protagonists...';

  @override
  String get presetStatusReady => 'Ready';

  @override
  String get presetStatusDraft => 'Draft';

  @override
  String get presetDefaultSceneName => 'Preset Scene';

  @override
  String get presetNoMatchingScenes => 'No matching preset scenes found';

  @override
  String get presetNoScenes => 'No preset scene scripts yet';

  @override
  String get presetNoMatchingScenesHint =>
      'Try different search terms or reset filters';

  @override
  String get presetNoScenesHint =>
      'Use the four-step wizard to generate a complete script preset with worldview, protagonist, prologue, and action branches';

  @override
  String get presetStartWizardAction => 'Start Wizard to Create Scene';

  @override
  String get presetScriptDetail => 'Script Details';

  @override
  String get presetUnnamedScene => 'Unnamed Scene';

  @override
  String presetWorldviewLabel(Object name) {
    return 'Worldview: $name';
  }

  @override
  String get presetPreviewFullSetting => 'Full Setting Preview';

  @override
  String get presetLoadIntoWizard => 'Load into Wizard for Tuning';

  @override
  String get presetDeleteAction => 'Delete Preset Scene';

  @override
  String get presetDeleteTitle => 'Delete Preset Scene';

  @override
  String presetDeleteMessage(Object name) {
    return 'Are you sure you want to delete preset scene \"$name\"?\nThis script preset cannot be recovered after deletion.';
  }

  @override
  String presetDeletedSuccess(Object name) {
    return 'Deleted scene \"$name\"';
  }

  @override
  String presetDeleteFailed(Object error) {
    return 'Delete failed: $error';
  }

  @override
  String presetLoadFailed(Object error) {
    return 'Failed to load preset scenes: $error';
  }

  @override
  String get presetStartFailed =>
      'Failed to start preset scene, please try again later';

  @override
  String presetProtagonistSummary(
      Object name, Object gender, Object profession) {
    return 'Protagonist: $name ($gender · $profession)';
  }

  @override
  String get presetNoPlotSummary => 'No plot summary available';

  @override
  String get presetDataSimplifying => 'Simplifying data structure';

  @override
  String get presetQuickStartAction => 'Quick Start';

  @override
  String get presetMenuSemantic => 'Scene operations menu';

  @override
  String get worldSelectionTitle => 'Select Worldview';

  @override
  String get worldSelectionSubtitle =>
      'Choose the world laws and background settings for this adventure from conceived worlds in the library';

  @override
  String get worldSelectionSearchHint =>
      'Search worldview name, geography, or rules...';

  @override
  String get worldSelectionNoDesc => 'No detailed background description';

  @override
  String get worldSelectionTag => 'World Setting';

  @override
  String get worldSelectionEmptyTitle => 'No saved worldviews';

  @override
  String get worldSelectionEmptyDesc =>
      'You can create one in the library or enter custom worldview in the wizard';

  @override
  String get characterSelectionTitle => 'Select Adventure Characters';

  @override
  String get characterSelectionSubtitle =>
      'Pick protagonists and party companions from character archives';

  @override
  String get characterSelectionSearchHint =>
      'Search character name, profession, personality, or background...';

  @override
  String get characterCompatNative => 'Current World';

  @override
  String get characterCompatUnbound => 'Unbound';

  @override
  String get characterCompatCrossWorld => 'From Other Worlds';

  @override
  String characterAgeYears(Object age) {
    return '$age years old';
  }

  @override
  String characterPersonalityPrefix(Object personality) {
    return 'Personality: $personality';
  }

  @override
  String get characterSelectionEmptyTitle => 'No character archives available';

  @override
  String get characterSelectionEmptyDesc =>
      'Create new characters in the library, or use AI in the wizard to generate';

  @override
  String get npcSelectionTitle => 'Select Initial NPCs';

  @override
  String get npcSelectionSubtitle =>
      'Choose resident NPCs appearing in this adventure (frozen into adventure snapshot)';

  @override
  String get npcSelectionSearchHint => 'Search NPC name, role, or brief...';

  @override
  String get npcSelectionEmptyTitle => 'No NPCs in library';

  @override
  String get npcSelectionEmptyDesc =>
      'Add NPCs in the library, or skip this step';

  @override
  String get unnamedNpc => 'Unnamed NPC';

  @override
  String resourceSelectedCount(int count) {
    return '$count items selected';
  }

  @override
  String get resourceNoneSelected => 'No items selected';

  @override
  String get resourceOneSelected => '1 item selected';

  @override
  String get confirmSelection => 'Confirm Selection';

  @override
  String get finishSelection => 'Done';

  @override
  String get loadingResources => 'Loading available resources...';

  @override
  String noMatchingResourceForQuery(Object query) {
    return 'No resources found containing \"$query\"';
  }

  @override
  String get clearSearch => 'Clear Search';

  @override
  String get configureApiKeyFirstForAi =>
      'Please configure an API Key to use AI generation';

  @override
  String get aiGenerationNoValidContent =>
      'Generation returned no valid content. Please check network or retry';

  @override
  String get aiOpeningGeneratedSuccess =>
      'AI prologue and initial action branches generated and applied!';

  @override
  String aiGenerationFailed(Object error) {
    return 'Generation failed: $error';
  }

  @override
  String get openingPromptLabel =>
      'Prologue Requirements / Guidance Prompts (Optional)';

  @override
  String get openingPromptHint =>
      'e.g., Start with suspense on a rainy pier, protagonist notices anomaly first...';

  @override
  String get aiGenerateOpeningAndBranches =>
      'Generate Prologue & Branches with AI';

  @override
  String get aiOpeningGeneratingProgress =>
      'AI is creating the prologue and action branches using the worldview and characters...';

  @override
  String assemblyWorldviewSubtitle(Object worldview) {
    return 'World: $worldview';
  }

  @override
  String assemblyProtagonistSubtitle(Object name) {
    return 'Protagonist: $name';
  }

  @override
  String get assemblyConfigPageTitle =>
      'Prologue Plot & Branches Configuration';

  @override
  String get saveConfigAndContinue => 'Save Configuration & Continue';

  @override
  String get openingFirstSceneTitle => 'Opening First Scene Plot';

  @override
  String get openingFirstSceneDesc =>
      'Set the situation description, encounter, or opening twist when the player enters the adventure.';

  @override
  String get openingFirstSceneHint =>
      'Describe the departure moment, environment, and unexpected crisis...';

  @override
  String get pleaseEnterOpeningScene => 'Please enter the opening scene plot';

  @override
  String get initialActionBranchesTitle =>
      'Initial Action Decision Branches (Optional)';

  @override
  String get initialActionBranchesDesc =>
      'Three action branches for player at start; if empty, dynamically generated by AI upon entry.';

  @override
  String get actionBranch1 => 'Decision Branch 1';

  @override
  String get actionBranch1Hint =>
      'e.g., Draw sword to meet the incoming shadow';

  @override
  String get actionBranch2 => 'Decision Branch 2';

  @override
  String get actionBranch2Hint =>
      'e.g., Find cover and call companions for covering fire';

  @override
  String get actionBranch3 => 'Decision Branch 3';

  @override
  String get actionBranch3Hint =>
      'e.g., Carefully observe surroundings for an escape route';

  @override
  String get difficultyAndGuidanceTitle =>
      'Deduction Difficulty & Custom Guidance';

  @override
  String get difficultyAndGuidanceDesc =>
      'Control gameplay difficulty tendency and custom prompt guidance.';

  @override
  String get narrativeDifficulty => 'Narrative Difficulty';

  @override
  String get difficultyNormalDesc =>
      'Normal (Standard narrative & balanced challenge)';

  @override
  String get difficultyCasualDesc =>
      'Casual (Focus on story & relaxed immersion)';

  @override
  String get difficultyHardDesc => 'Hard (Strict rules & hardcore choices)';

  @override
  String get customGuidancePromptOptional =>
      'Custom Guidance Prompt (Optional)';

  @override
  String get customGuidancePromptHint =>
      'e.g., Focus on suspenseful detective atmosphere, add more sensory details...';

  @override
  String get worldviewBoundRules =>
      'Bound worldview rules and geographical laws';

  @override
  String get defaultContinentRules => 'Use default continent rules';

  @override
  String readinessReadError(Object error) {
    return 'Cannot read resource readiness status: $error';
  }

  @override
  String readinessRetryError(Object error) {
    return 'Failed to re-prepare resources: $error';
  }

  @override
  String startAdventureFailed(Object error) {
    return 'Failed to start adventure: $error';
  }

  @override
  String get unnamedHero => 'Nameless Hero';

  @override
  String get adventurerRole => 'Adventurer';

  @override
  String get assemblyPreviewSubtitle =>
      'Comprehensive inspection of worldview, character roster, NPCs, and prologue deduction settings';

  @override
  String get enterAdventureAction => 'Enter Adventure';

  @override
  String get readinessCheckingTitle => 'Checking resource assembly readiness';

  @override
  String get readinessUnconfirmedTitle =>
      'Cannot confirm resource assembly status';

  @override
  String get readinessReadyTitle => 'Adventure elements assembled';

  @override
  String get readinessNotReadyTitle => 'Some resources are not yet ready';

  @override
  String get readinessCheckingDesc =>
      'Reading available versions of worldviews and characters.';

  @override
  String get readinessUnconfirmedDesc =>
      'Failed to read resource status. Launch cannot be confirmed safely.';

  @override
  String get readinessReadyDesc =>
      'Click \"Enter Adventure\" below to freeze snapshot and start a new journey.';

  @override
  String get readinessNotReadyDesc =>
      'Cannot enter adventure without available revisions. Please complete resource readiness first.';

  @override
  String get readinessRetrying => 'Re-preparing…';

  @override
  String get readinessRetry => 'Re-prepare';

  @override
  String worldviewSettingLabel(Object name) {
    return 'World Setting: $name';
  }

  @override
  String get worldviewSettingTitle => 'World Setting';

  @override
  String get readAloudWorldview => 'Read Aloud World Setting';

  @override
  String protagonistLeadLabel(Object name, Object className) {
    return 'Main Protagonist: $name ($className)';
  }

  @override
  String get mainProtagonistTitle => 'Main Protagonist';

  @override
  String personalityFeatureLabel(Object personality) {
    return 'Personality: $personality';
  }

  @override
  String backgroundStoryPrefix(Object background) {
    return 'Background: $background';
  }

  @override
  String accompanyingCharactersCount(int count) {
    return 'Accompanying Characters ($count):';
  }

  @override
  String characterBondsCount(int count) {
    return 'Character Bonds ($count):';
  }

  @override
  String residentNpcsCount(int count) {
    return 'Resident NPCs ($count)';
  }

  @override
  String get openingSceneAndDecisionsTitle => 'Prologue & Action Decisions';

  @override
  String get openingSceneTitle => 'Prologue Scene';

  @override
  String get readAloudOpeningScene => 'Read Aloud Prologue Scene';

  @override
  String get aiDynamicOpeningPlaceholder =>
      '(AI will dynamically conceive the opening scene based on the worldview and character background)';

  @override
  String get initialActionDecisionsTitle => 'Initial Action Decision Branches:';

  @override
  String get noMatchingResourceTitle => 'No matching resources';

  @override
  String get noMatchingResourceDesc =>
      'Try entering other search terms or clear filters';

  @override
  String get searchResourceNameOrDesc =>
      'Search resource name or description...';

  @override
  String get aiOpeningPanelTitle => 'AI Prologue Generator';

  @override
  String get aiOpeningPanelDesc =>
      'Fill in your prologue requirements, and AI will generate the prologue and initial action branches based on the worldview, protagonist and companion character cards, bonds, and NPCs; the result can still be edited manually.';

  @override
  String get regenerate => 'Regenerate';

  @override
  String get assemblyPipelineTitle => 'Adventure Assembly Pipeline';

  @override
  String get assemblyPipelineSubtitle =>
      'Step-by-step · Page-based resource assembly · Zero dialog constraints';

  @override
  String get phaseWorldview => 'Worldview';

  @override
  String get phaseCharacters => 'Roster';

  @override
  String get phaseOpening => 'Opening & Branches';

  @override
  String get phasePreview => 'Assembly Overview';

  @override
  String nextPhaseLabel(Object phase) {
    return 'Next: $phase';
  }

  @override
  String get previousStepAction => 'Previous';

  @override
  String get pleaseSetWorldviewName => 'Please set a worldview name';

  @override
  String get pleaseAddAtLeastOneCharacter =>
      'Please add at least one character';

  @override
  String worldviewSelectedSuccess(Object name) {
    return 'Worldview \"$name\" selected';
  }

  @override
  String get rosterUpdatedSuccess => 'Character roster updated';

  @override
  String npcsSelectedCountSuccess(int count) {
    return '$count NPCs selected';
  }

  @override
  String get openingConfigSavedSuccess => 'Prologue configuration saved';

  @override
  String characterJoinedPartySuccess(Object name) {
    return 'Character \"$name\" joined the party';
  }

  @override
  String get worldviewLibraryLinkTitle => 'Worldview Library Association';

  @override
  String get selectFromLibrary => 'Select from Library';

  @override
  String boundLibraryWorldviewId(Object id) {
    return 'Bound Library Worldview ID: $id';
  }

  @override
  String get notBoundPresetHint =>
      'No preset bound. You can also enter custom world settings below directly.';

  @override
  String get worldviewDetailsSectionTitle => 'Worldview Setting Details';

  @override
  String get worldviewDetailsSectionDesc =>
      'Set continental laws, geographical background, civilization level, and factions.';

  @override
  String get worldNameRequiredLabel => 'World Name *';

  @override
  String get worldNameHint =>
      'e.g., Elden Continent, Cyber Neo Metropolis 2099, Cultivation Ancient Realm...';

  @override
  String get pleaseEnterWorldName => 'Please enter the world name';

  @override
  String get lawsAndBackgroundLabel => 'Laws & Background Setting';

  @override
  String get lawsAndBackgroundHint =>
      'Describe magic and tech systems, celestial climate, factions, and power dynamics...';

  @override
  String get charactersAndNpcAssemblyTitle => 'Character & NPC Assembly';

  @override
  String get selectCharactersFromLibrary => 'Select Characters from Library';

  @override
  String selectNpcCountLabel(int count) {
    return 'Select NPCs ($count)';
  }

  @override
  String get newCharacterAction => 'New Character';

  @override
  String rosterSectionTitle(int count) {
    return 'Appearing Characters Roster ($count)';
  }

  @override
  String get rosterSectionDesc =>
      'Must select 1 as the main protagonist; others can be assigned companion, antagonist, mentor, etc.';

  @override
  String get noCharactersAddedYet => 'No appearing characters added yet';

  @override
  String get clickAboveToAddCharactersHint =>
      'Click \"Select Characters from Library\" or \"New Character\" above';

  @override
  String get setAsMainProtagonist => 'Set as Main Protagonist';

  @override
  String get scriptRoleOrientation => 'Script Role Position';

  @override
  String get openingAndRulesAdvancedConfigTitle =>
      'Prologue & Rules Advanced Configuration';

  @override
  String get fullscreenAdvancedConfig => 'Fullscreen Advanced Config';

  @override
  String get openingSceneContentTitle => 'Prologue Scene Content';

  @override
  String get openingSceneContentDesc =>
      'The first scene description when the adventure begins.';

  @override
  String get openingSceneContentHint =>
      'Describe the environment and twist when the protagonist appears...';

  @override
  String get openingBranchesDesc =>
      'Action directions for the player to choose at the end of the prologue.';

  @override
  String branchNumberLabel(Object number) {
    return 'Branch $number';
  }

  @override
  String actionOptionHint(Object number) {
    return 'Action Option $number...';
  }

  @override
  String get enterStandaloneFullscreenPreview =>
      'Enter Standalone Fullscreen Preview';

  @override
  String get fullscreenPreviewButton => 'Fullscreen Preview';

  @override
  String get customUnnamedWorld => 'Custom Unnamed World';

  @override
  String get unspecifiedProtagonist => 'Unspecified Protagonist';

  @override
  String companionRosterSummary(Object roster) {
    return 'Companions: $roster';
  }

  @override
  String selectedInitialNpcCount(int count) {
    return '$count initial NPCs selected';
  }

  @override
  String get firstSceneOpeningPlotTitle => 'Prologue First Scene';

  @override
  String get aiDynamicOpeningSummary =>
      'Dynamically developed by AI based on background';

  @override
  String get wizardWorldviewQuickBadge => 'Quick ideas and library authoring';

  @override
  String get wizardWorldviewPromptLabel =>
      'Worldview idea / genre preference (optional)';

  @override
  String get wizardWorldviewPromptHint =>
      'e.g., a steampunk sky city, whispers of ancient gods, or a deep-sea dystopia. Leave blank for a free-form idea...';

  @override
  String get generationModeLabel => 'Generation mode';

  @override
  String get clearSettingsAction => 'Clear settings';

  @override
  String get wizardGenerateWorldviewAction => 'Generate worldview with AI';

  @override
  String get wizardRegenerateWorldviewAction => 'Regenerate worldview';

  @override
  String get wizardWorldviewGeneratingBrief => 'Drafting worldview…';

  @override
  String get wizardWorldviewGeneratingDetailed =>
      'Developing worldview in stages…';

  @override
  String get saveToLibraryNow => 'Save to library now';

  @override
  String get wizardReusableBadge => 'Reusable anytime';

  @override
  String get wizardWorldviewSaveDescription =>
      'Save this setting to the worldview library so you can reuse and expand it in future adventures.';

  @override
  String charactersSavedCount(int count) {
    return 'Saved $count character settings to the library';
  }

  @override
  String characterCardSavedSuccess(String name) {
    return 'Saved character \"$name\" to the library';
  }

  @override
  String get fullscreenSelectionAction => 'Full-screen selection';

  @override
  String wizardCharacterAiSummary(String worldview) {
    return 'Describe the character’s personality or role. AI uses the current worldview, $worldview, to create a protagonist or party member and add them to the roster. The library creator offers a more detailed workflow.';
  }

  @override
  String get wizardCharacterPromptLabel =>
      'Character idea / persona preference (optional)';

  @override
  String get wizardCharacterPromptHint =>
      'e.g., a composed demon-slaying swordsman, a cheerful white-haired healer, or a cool mechanical ranger...';

  @override
  String get wizardGenerateMainCharacterAction =>
      'Generate protagonist with AI';

  @override
  String get wizardAddCharacterToRosterAction => 'Add character with AI';

  @override
  String get currentWorldviewLabel => 'Current world';

  @override
  String get removeRosterCharacter => 'Remove from roster';

  @override
  String get clearRelatedCharacters => 'Clear links';

  @override
  String wizardRelatedCharactersSummary(int count, String names) {
    return '$count linked: $names';
  }

  @override
  String get wizardRelationAssociationSummary =>
      'The new character will form a story bond with the selected characters.';

  @override
  String charactersAddedToRoster(int count) {
    return 'Added $count AI-generated characters to the roster';
  }

  @override
  String get roleMaleLead => 'Male lead';

  @override
  String get roleFemaleLead => 'Female lead';

  @override
  String get roleMaleOne => 'Male lead 1';

  @override
  String get roleFemaleOne => 'Female lead 1';

  @override
  String get roleMaleTwo => 'Male lead 2';

  @override
  String get roleFemaleTwo => 'Female lead 2';

  @override
  String get roleSupporting => 'Supporting character';

  @override
  String get roleVillain => 'Antagonist';

  @override
  String get roleMentor => 'Mentor';

  @override
  String get roleFamily => 'Family';

  @override
  String get relationFriend => 'Friend';

  @override
  String get relationEnemy => 'Enemy';

  @override
  String get relationStranger => 'Stranger';

  @override
  String get mainProtagonistDescription =>
      'Main protagonist (controls actions and key decisions)';

  @override
  String get protagonistShortTag => 'Protagonist';

  @override
  String get relationshipNetworkDescription =>
      'Set the bonds, affiliations, and past conflicts between the characters. AI will follow these relationships.';

  @override
  String relationAssetReference(String suggestion) {
    return 'Related resource: $suggestion (can be changed for this adventure)';
  }

  @override
  String get relationDetailsHint =>
      'Describe the history or clues behind their relationship (optional).';

  @override
  String get relationshipNetworkTitle => 'Character Bonds & Relationships';

  @override
  String get adventureReadyToEnterTitle => 'Ready to enter the world';

  @override
  String get worldviewSnapshotBoundSummary =>
      'Bound worldview snapshot, rules, and geography are ready';

  @override
  String get characterCardSnapshotBoundSummary =>
      'Bound to the complete character card in the library';

  @override
  String get characterCustomDesignedSummary =>
      'Protagonist settings customized';

  @override
  String get unnamedCharacterA => 'Character A';

  @override
  String get unnamedCharacterB => 'Character B';

  @override
  String get savePreviewAction => 'Save preview';

  @override
  String get previewTemplateNoStartHint =>
      'This saves a recoverable preview template and does not start the adventure.';

  @override
  String adventurePreviewName(String worldview) {
    return '$worldview · Adventure Preview';
  }

  @override
  String adventurePreviewSavedMessage(String name) {
    return 'Saved preview \"$name\". You can restore it in Preset Scenes.';
  }

  @override
  String get adventurePreviewExistsMessage =>
      'An adventure preview with the same details already exists.';

  @override
  String adventurePreviewSaveFailed(String error) {
    return 'Failed to save preview: $error';
  }

  @override
  String get wizardCharacterSaveDescription =>
      'Automatically save roster character designs to your character library for future adventures.';

  @override
  String wizardMalformedCharacterCards(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count character cards could not be loaded.',
      one: 'One character card could not be loaded.',
    );
    return '$_temp0';
  }

  @override
  String get conversationDeleteTitle => 'Delete scene conversations';

  @override
  String conversationDeleteConfirm(int count) {
    return 'Delete the selected $count scene conversations? This cannot be undone.';
  }

  @override
  String conversationDeleteInterrupted(String error) {
    return 'Deletion stopped. Check the remaining conversations and try again: $error';
  }

  @override
  String get conversationManageTitle => 'Manage past conversations';

  @override
  String selectedItemsCount(int count) {
    return '$count selected';
  }

  @override
  String get deletingAction => 'Deleting…';

  @override
  String get batchDeleteAction => 'Delete selected';

  @override
  String get noManagedConversations => 'No scene conversations to manage';

  @override
  String get selectAllAction => 'Select all';

  @override
  String get sceneConversationLabel => 'Scene conversation';

  @override
  String get messageEditUserTitle => 'Edit your message';

  @override
  String get messageEditAssistantTitle => 'Edit AI reply';

  @override
  String get messageEditUserSubtitle =>
      'Editing this message regenerates the story that follows.';

  @override
  String get messageEditAssistantSubtitle =>
      'Edit this story text to adjust narration or correct details.';

  @override
  String get messageEditUserWarning =>
      'Saving clears all history after this message and regenerates the story from your new input.';

  @override
  String get messageBodyLabel => 'Message text';

  @override
  String get messageEditDescription =>
      'Long text is supported, including line breaks and formatting.';

  @override
  String get messageContentHint => 'Enter message content…';

  @override
  String get saveAndRegenerateAction => 'Save and regenerate';

  @override
  String get saveChangesAction => 'Save changes';

  @override
  String get messageContentRequired => 'Message content cannot be empty.';

  @override
  String get messageUnchanged => 'No changes were made.';

  @override
  String get messageNoLongerCurrent =>
      'This message is no longer in the current conversation. Return and refresh.';

  @override
  String get messageSavedAndRegenerated => 'Saved and regenerated';

  @override
  String get messageChangesSaved => 'Changes saved';

  @override
  String get messageSaveRetry => 'Could not save. Please try again.';

  @override
  String get inventoryTitle => 'Inventory';

  @override
  String get inventoryItemsTitle => 'Items';

  @override
  String get equipmentTitle => 'Equipment';

  @override
  String get legacyInventoryTitle => 'Legacy inventory';

  @override
  String inventorySummary(int itemCount, int equipmentCount) {
    return '$itemCount items, $equipmentCount equipment pieces';
  }

  @override
  String get quickMenuTooltip => 'Quick menu';

  @override
  String get characterStatusTitle => 'Character status';

  @override
  String get wordCountSettings => 'Word count settings';

  @override
  String get backToLobby => 'Back to lobby';

  @override
  String get restartAdventureTitle => 'Restart adventure?';

  @override
  String get restartAdventureMessage =>
      'This resets the current conversation and adventure progress, then returns to the home page.';

  @override
  String get restartAdventureAction => 'Restart';

  @override
  String get stopGenerationAction => 'Stop generation';

  @override
  String get textAdventureTitle => 'Text adventure';

  @override
  String get searchConversationAction => 'Search conversation';

  @override
  String get historyAndSidebarAction => 'Scene history and sidebar';

  @override
  String get moreOptionsAction => 'More options';

  @override
  String get replyLengthSetting => 'Reply length';

  @override
  String get switchModelAction => 'Switch model';

  @override
  String get promptSettingsAction => 'Prompt settings';

  @override
  String get wordCountAndDensitySettings =>
      'Word count and dialogue density settings';

  @override
  String get reasoningCopiedToast => 'Reasoning copied to clipboard';

  @override
  String get editedBadge => '(Edited)';

  @override
  String get deleteMessageConfirmation =>
      'This message cannot be recovered. Delete it?';

  @override
  String get removeBookmarkAction => 'Remove bookmark';

  @override
  String get addBookmarkAction => 'Add bookmark';

  @override
  String get editMessageAction => 'Edit';

  @override
  String get regenerateMessageAction => 'Regenerate';

  @override
  String get assistantReplyLabel => 'AI reply';

  @override
  String get selectModelForRegeneration => 'Select model to regenerate';

  @override
  String get selectLanguageModel => 'Select language model';

  @override
  String currentModelSummary(String model, String provider) {
    return 'Current: $model ($provider)';
  }

  @override
  String get selectedModelLabel => 'Selected model';

  @override
  String get defaultModelPlaceholder => 'Not selected (using default)';

  @override
  String get confirmApplyAction => 'Apply selection';

  @override
  String get selectValidModelError => 'Select or enter a valid model name.';

  @override
  String get messageNoLongerCurrentError =>
      'This message is no longer in the current conversation. Return and refresh.';

  @override
  String get regenerationUserMessageMissingError =>
      'Cannot regenerate: no valid user message was found.';

  @override
  String get regenerationTargetMissingError =>
      'Cannot regenerate: the associated user message was not found.';

  @override
  String get modelRegenerationStarting => 'Regenerating…';

  @override
  String modelSwitchedSuccess(String model) {
    return 'Switched to model: $model';
  }

  @override
  String get modelSwitchFailed => 'Could not switch models. Please try again.';

  @override
  String get serviceProviderSection => 'Service provider';

  @override
  String get serviceProviderDescription =>
      'Choose an official API provider or a local/third-party compatible service.';

  @override
  String get llmProviderLabel => 'LLM provider';

  @override
  String get recentModelsSection => 'Recently used';

  @override
  String get recentModelsDescription =>
      'Quickly switch to models used on this device.';

  @override
  String get recommendedModelsSection => 'Recommended models';

  @override
  String get recommendedModelsDescription =>
      'Core models optimized for creative writing and role-playing.';

  @override
  String get customModelSection => 'Custom model name';

  @override
  String get deepseekCustomModelDescription =>
      'Enter another DeepSeek model name here if needed.';

  @override
  String get otherCustomModelDescription =>
      'Enter a model identifier supported by the compatible endpoint (for example, gpt-4o or claude-3-5-sonnet).';

  @override
  String get modelNamePlaceholder => 'Enter model name…';

  @override
  String customModelSelected(String model) {
    return 'Selected custom model: $model';
  }

  @override
  String get adventureBlankSlateTitle => 'A fresh adventure awaits';

  @override
  String get adventureBlankSlateDescription =>
      'This scene has no conversations or action records yet. Enter an action below or choose a direction to explore and begin your adventure.';

  @override
  String get beginAdventureAction => 'Begin adventure';

  @override
  String get deepSeekFlashModelSubtitle =>
      'Latest recommended DeepSeek V4.1 Flash · multimodal · deep thinking supported';

  @override
  String get deepSeekLegacyModelSubtitle =>
      'Legacy model; migration to DeepSeek V4.1 Flash is recommended';

  @override
  String get deleteDetectedStatusTitle => 'Delete status';

  @override
  String confirmDeleteDetectedStatus(String name) {
    return 'Delete the status “$name”?';
  }

  @override
  String get statusNameLabel => 'Status name *';

  @override
  String get statusNameExamples =>
      'For example: Sanity (SAN), affinity, corruption, hunger';

  @override
  String get measurementModeLabel => 'Value type:';

  @override
  String get numericGaugeMode => 'Numeric gauge (0–100)';

  @override
  String get phaseDescriptionMode => 'Phase description';

  @override
  String get currentValueLabel => 'Current value';

  @override
  String get maxValueLabel => 'Maximum value';

  @override
  String get currentPhaseLabel => 'Current phase / description';

  @override
  String get currentPhaseExamples =>
      'For example: Normal, mildly corrupted, tipsy, enraged';

  @override
  String get chooseStatusIcon => 'Choose status icon:';

  @override
  String get statusRuleLabel => 'Check rule / story instructions (optional)';

  @override
  String get statusRuleHint =>
      'For example: panic below 20; a successful roll preserves sanity, while a failed roll causes hallucinations';

  @override
  String get storyImportanceLabel => 'Story importance:';

  @override
  String get statusNameRequiredError => 'Enter a status name.';

  @override
  String get addDetectedStatusAction => 'Add status';

  @override
  String detectedStatusesCount(int count) {
    return 'Custom statuses ($count)';
  }

  @override
  String get combatAdventureMatrix => 'Combat and adventure attributes';

  @override
  String get physicalAttackStat => 'Physical attack (ATK)';

  @override
  String get baseDefenseStat => 'Base defense (DEF)';

  @override
  String get agilitySpeedStat => 'Agility (SPD)';

  @override
  String get goldStat => 'Gold';

  @override
  String get availableSkillPointsStat => 'Available skill points';

  @override
  String get currentSceneCoordinatesStat => 'Current scene coordinates';

  @override
  String get openInventoryAction => 'Open inventory';

  @override
  String get profileIdentityTitle => '📜 Identity and role';

  @override
  String get profileBackgroundTitle => '📖 Background and history';

  @override
  String get profileWorldviewTitle => '🌍 Worldview';

  @override
  String get profilePersonalityTitle => '🎭 Personality';

  @override
  String get profileRelationshipsTitle => '🤝 Bonds and relationships';

  @override
  String get profileAppearanceTitle => '✨ Appearance';

  @override
  String get checkAction => 'Check';

  @override
  String levelRoleSummary(int level, String role) {
    return 'Lv. $level · $role';
  }

  @override
  String get editDetectedStatusTitle => 'Edit status';

  @override
  String get noCustomDetectedStatuses => 'No custom statuses yet';

  @override
  String get detectedStatusesEmptyDescription =>
      'Create any adventure status, such as sanity (SAN), affinity, corruption, hunger, or magic overload.';

  @override
  String get energyLabel => 'Energy';

  @override
  String get combatStatsTitle => 'Combat attributes';

  @override
  String get currentValuePrefix => 'Current value: ';

  @override
  String get currentPhaseWithThoughtsLabel => 'Current phase / thought';

  @override
  String get phaseNotTriggered => '(Phase check has not triggered yet)';

  @override
  String statusRulePrefix(String rule) {
    return '📌 Rule: $rule';
  }

  @override
  String get companionsTab => 'Companions';

  @override
  String get equipmentTab => 'Equipment';

  @override
  String get profileTab => 'Profile';

  @override
  String currentExplorationRegion(String scene) {
    return 'Current area: $scene';
  }

  @override
  String mainStoryChapter(int chapter) {
    return 'Main adventurer · Chapter $chapter';
  }

  @override
  String relationshipLabel(String relation) {
    return 'Relationship: $relation';
  }

  @override
  String affinityScoreLabel(int affinity) {
    return '❤️ Affinity: $affinity';
  }

  @override
  String get healthPointsLabel => 'Health (HP)';

  @override
  String get lifeForceLabel => 'Vitality';

  @override
  String get magicPointsLabel => 'Magic (MP)';

  @override
  String get focusLabel => 'Focus';

  @override
  String get actionEnergyLabel => 'Action energy';

  @override
  String get tiredStatus => '⚠️ Tired';

  @override
  String get goodStatus => 'Good';

  @override
  String get experienceLabel => 'Experience (EXP)';

  @override
  String nextLevelExperience(int count) {
    return '$count to next level';
  }

  @override
  String skillPointsValue(int count) {
    return '$count points';
  }

  @override
  String equippedGearCount(int count) {
    return '⚔️ Equipped gear ($count)';
  }

  @override
  String get noEquippedGear =>
      'No equipped gear. Find equipment in your inventory or a shop to improve combat ability.';

  @override
  String gearSlotQuality(String slot, String quality) {
    return 'Slot: $slot · Quality: $quality';
  }

  @override
  String get carriedItemsTitle => '🎒 Carried items and materials';

  @override
  String get noCarriedItems => 'No special items in this inventory.';

  @override
  String get sharedPartyInventory => '📦 Shared party inventory:';

  @override
  String get detectedStatusFormDescription =>
      'Track a custom status in the adventure, with gauges, check rules and dice rolls.';

  @override
  String get statusPresetsHeading => '💡 Preset ideas (tap to fill in):';

  @override
  String get explorerRole => 'Explorer';

  @override
  String get startingTown => 'Starting town';

  @override
  String get defaultProtagonistProfile =>
      'An adaptable adventurer who explores unknown frontiers and makes story decisions.';

  @override
  String get defaultProtagonistBackground =>
      'Set out into a turbulent world and discover how your fate unfolds.';

  @override
  String get defaultWorldviewDescription =>
      'An immersive role-playing world that changes as the story develops.';

  @override
  String get defaultCompanionPersonality =>
      'A reserved personality whose true wishes emerge throughout the journey.';

  @override
  String genderTag(String value) {
    return 'Gender: $value';
  }

  @override
  String heightTag(String value) {
    return 'Height: $value';
  }

  @override
  String hairstyleTag(String value) {
    return 'Hair: $value';
  }

  @override
  String skinToneTag(String value) {
    return 'Skin tone: $value';
  }

  @override
  String facialFeaturesTag(String value) {
    return 'Face: $value';
  }

  @override
  String get aliveStatus => '💚 Healthy';

  @override
  String get incapacitatedStatus => '💀 Incapacitated';

  @override
  String companionRelationshipSummary(String relation, int affinity) {
    return 'Relationship: $relation. Current affinity: $affinity/100.';
  }

  @override
  String get diceCriticalSuccess => 'Critical success! A perfect result.';

  @override
  String get diceCriticalFailure =>
      'Critical failure! A serious mishap or backlash.';

  @override
  String get diceSuccess =>
      'Check passed! You resist the effect and remain stable.';

  @override
  String get diceFailure =>
      'Check failed! You are affected by a negative effect.';

  @override
  String get diceCheckCriticalSuccess =>
      'Critical success! Breakthrough achieved!';

  @override
  String get diceCheckCriticalFailure =>
      'Critical failure! The check failed completely.';

  @override
  String get diceCheckPassed => 'Check passed! Your condition remains stable.';

  @override
  String get diceCheckFailed => 'Check failed! You suffer an adverse effect.';

  @override
  String diceTargetValue(int current, int maximum) {
    return 'Target value: $current / $maximum';
  }

  @override
  String diceCurrentStatus(String status) {
    return 'Current status: $status';
  }

  @override
  String diceRuleDescription(String rule) {
    return 'Check rule: $rule';
  }

  @override
  String get d100PercentileDie => 'D100 percentile die';

  @override
  String get d20Die => 'D20 die';

  @override
  String get rollCheckAction => 'Roll check';

  @override
  String get rerollAction => 'Roll again';

  @override
  String get syncResultToAdventure => 'Add result to adventure';

  @override
  String diceResultPoints(String icon, int value, String denominator) {
    return '$icon Roll: $value $denominator';
  }

  @override
  String get diceResultWillBeSent =>
      'The result will be sent as a user message.';

  @override
  String diceResultMessage(String status, String rule, String character,
      int roll, String target, String verdict) {
    return '[Status check] $character rolled “$status”: 🎲 $roll ($target) → [$verdict]. $rule';
  }

  @override
  String get allItemsFilter => 'All';

  @override
  String get consumableItemType => 'Consumables';

  @override
  String get equipmentItemType => 'Equipment';

  @override
  String get materialItemType => 'Materials';

  @override
  String get questItemType => 'Quest items';

  @override
  String get weaponSlot => 'Weapon';

  @override
  String get armorSlot => 'Armor';

  @override
  String get accessorySlot => 'Accessory';

  @override
  String get specialSlot => 'Special';

  @override
  String get commonQuality => 'Common';

  @override
  String get uncommonQuality => 'Uncommon';

  @override
  String get rareQuality => 'Rare';

  @override
  String get epicQuality => 'Epic';

  @override
  String get legendaryQuality => 'Legendary';

  @override
  String get emptyInventoryTitle => 'Your inventory is empty';

  @override
  String get emptyInventoryDescription =>
      'Items you find in the story will appear here.';

  @override
  String get deepThinkingStatus => 'Thinking deeply…';

  @override
  String get reasoningExpandedLabel => 'Thinking process (tap to collapse)';

  @override
  String get reasoningCollapsedLabel =>
      'Thinking finished (tap to view reasoning)';

  @override
  String get thinkingInProgressStatus => 'Thinking…';

  @override
  String get reasoningUnavailableLabel => '(No record)';

  @override
  String get copyReasoningAction => 'Copy reasoning';

  @override
  String get writingStoryStatus => 'Writing story…';

  @override
  String get dialogueReplyLengthSettingsTitle => 'Adjust scene reply length';

  @override
  String dialogueCurrentSelection(String id, String name, String range) {
    return 'Selected: $id · $name ($range)';
  }

  @override
  String dialogueWordsAbove(int minWords) {
    return '$minWords+ words';
  }

  @override
  String get dialogueLevelFast => 'Fast';

  @override
  String get dialogueLevelConcise => 'Concise';

  @override
  String get dialogueLevelStandard => 'Standard';

  @override
  String get dialogueLevelDetailed => 'Detailed';

  @override
  String get dialogueLevelDeep => 'In depth';

  @override
  String get dialogueLevelProduction => 'Production';

  @override
  String get dialogueLevelFastDesc =>
      'Keeps only key feedback for quick confirmation.';

  @override
  String get dialogueLevelConciseDesc =>
      'Brief story progress for lightweight interaction.';

  @override
  String get dialogueLevelStandardDesc =>
      'Default mode balancing speed and immersion.';

  @override
  String get dialogueLevelDetailedDesc =>
      'More complete descriptions and interaction.';

  @override
  String get dialogueLevelDeepDesc =>
      'Emphasizes buildup, psychology and layered scenes.';

  @override
  String get dialogueLevelProductionDesc =>
      'Long-form output for serious writing.';

  @override
  String get adventureRefreshUnavailable =>
      'Cannot refresh while generating or when the scene is unavailable.';

  @override
  String get sessionOfflineHint => 'Offline — network connection unavailable';

  @override
  String get sessionInputHint => 'Describe your action or dialogue…';

  @override
  String get messageGestureHint =>
      'Swipe right to retry · swipe left to delete · long press to edit or bookmark';

  @override
  String get adventureAssistantName => 'Adventure Assistant';

  @override
  String get currentUserDisplayName => 'Me';

  @override
  String get unknownRegion => 'Unknown region';

  @override
  String get deepThinkingBadge => 'Deep thinking';

  @override
  String get supportingCharacterRole => 'Supporting character';

  @override
  String get autoSwitchCharacterTooltip => 'Automatically switch character';

  @override
  String get sessionSettlingStatus =>
      'Generating options and settling the turn…';

  @override
  String get aiReplyLabel => 'AI reply';

  @override
  String sectionValidationPassed(String title) {
    return '$title validation passed';
  }

  @override
  String sectionValidationFailed(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count issues',
      one: '$count issue',
      zero: 'no issues',
    );
    return '$title validation failed: $_temp0';
  }

  @override
  String get sectionValidationComplete => 'Validation complete';

  @override
  String sectionRegenerated(String title, int completed, int total) {
    return '$title regenerated $completed of $total parts';
  }

  @override
  String sectionRegenerationFailed(String title, String error) {
    return 'Generation stopped for $title: $error';
  }

  @override
  String get sectionGenerationComplete => 'Generation complete';

  @override
  String get capacityNoCompressionNeeded => 'No sections need compression.';

  @override
  String get capacityCompressionAlreadyPublished =>
      'This compression candidate was already published; no text was changed again.';

  @override
  String capacityCompressionPublished(int savedCharacters) {
    return 'Published the compression candidate, saving about $savedCharacters characters. The previous text is kept in revision history.';
  }

  @override
  String capacityRetryBlockedByActiveTarget(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count failed jobs were skipped because their targets already have active compression.',
      one:
          '$count failed job was skipped because its target already has an active compression.',
    );
    return '$_temp0';
  }

  @override
  String capacityRetryBudgetExhausted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count jobs have',
      one: '$count job has',
    );
    return 'No compression jobs can be retried; $_temp0 reached the retry limit.';
  }

  @override
  String get capacityRetryUnavailable =>
      'There are no compression jobs available to retry.';

  @override
  String capacityCompressionRunSummary(int succeeded, int failed, int requeued,
      int activeSkipped, int exhaustedSkipped) {
    String _temp0 = intl.Intl.pluralLogic(
      succeeded,
      locale: localeName,
      other: 'Generated $succeeded candidates',
      one: 'Generated $succeeded candidate',
      zero: 'Generated no candidates',
    );
    String _temp1 = intl.Intl.pluralLogic(
      failed,
      locale: localeName,
      other: '$failed jobs failed',
      one: '$failed job failed',
      zero: '$failed jobs failed',
    );
    String _temp2 = intl.Intl.pluralLogic(
      requeued,
      locale: localeName,
      other: '$requeued jobs retried',
      one: '$requeued job retried',
      zero: '$requeued jobs retried',
    );
    String _temp3 = intl.Intl.pluralLogic(
      activeSkipped,
      locale: localeName,
      other: '$activeSkipped active targets skipped',
      one: '$activeSkipped active target skipped',
      zero: '$activeSkipped active targets skipped',
    );
    String _temp4 = intl.Intl.pluralLogic(
      exhaustedSkipped,
      locale: localeName,
      other: '$exhaustedSkipped jobs skipped at the retry limit',
      one: '$exhaustedSkipped job skipped at the retry limit',
      zero: '$exhaustedSkipped jobs skipped at the retry limit',
    );
    return '$_temp0; $_temp1; $_temp2; $_temp3; $_temp4. Candidates require confirmation before replacing text; failed jobs leave the original unchanged.';
  }

  @override
  String get revisionCauseManualSave => 'Manual save';

  @override
  String get revisionCauseGeneration => 'AI generation';

  @override
  String get revisionCausePlanning => 'Outline planning';

  @override
  String get revisionCauseRegeneration => 'Regeneration';

  @override
  String get revisionCauseCompression => 'Semantic compression';

  @override
  String get revisionCauseRestore => 'Restore';

  @override
  String get revisionCauseMigration => 'Data migration';

  @override
  String get revisionCauseDeletion => 'Pre-deletion snapshot';

  @override
  String get revisionUnknownDate => 'Unknown date';

  @override
  String get revisionAlreadyCurrent => 'This revision is already current.';

  @override
  String revisionRestored(String sourceCause) {
    return 'Restored the $sourceCause revision.';
  }

  @override
  String revisionItemSubtitle(String date, int nodeCount, int charCount) {
    String _temp0 = intl.Intl.pluralLogic(
      nodeCount,
      locale: localeName,
      other: '$nodeCount nodes',
      one: '$nodeCount node',
    );
    String _temp1 = intl.Intl.pluralLogic(
      charCount,
      locale: localeName,
      other: '$charCount characters',
      one: '$charCount character',
    );
    return '$date · $_temp0 · $_temp1';
  }

  @override
  String resourceRevisionOperationFailed(String error) {
    return 'Revision operation failed: $error';
  }

  @override
  String get resourceTrashKindResource => 'Resource';

  @override
  String get resourceTrashKindSection => 'Section';

  @override
  String get resourceTrashKindPart => 'Paragraph';

  @override
  String get resourceTrashReasonUserDelete => 'User deleted';

  @override
  String get resourceTrashRestoreOriginal =>
      'Restored to its original location.';

  @override
  String get resourceTrashRestoreFallback =>
      'The original section no longer exists. Restored under a new section at the resource root.';

  @override
  String get resourceTrashRestoreToLibrary =>
      'Restored to the resource library.';

  @override
  String get resourceTrashAlreadyRestored =>
      'This item was already restored; no changes were made.';

  @override
  String resourceTrashLoadFailed(String error) {
    return 'Could not load the recycle bin: $error';
  }

  @override
  String get unnamedSceneTitle => 'Untitled scene';

  @override
  String get statusPresetSanityLabel => '🧠 Sanity (SAN)';

  @override
  String get statusPresetSanityName => 'Sanity (SAN)';

  @override
  String get statusPresetSanityDescription =>
      'Resist the unknown and fear; dropping below 20 may cause hallucinations.';

  @override
  String get statusPresetAffinityLabel => '❤️ Character Affinity';

  @override
  String get statusPresetAffinityName => 'Affinity';

  @override
  String get statusPresetAffinityDescription =>
      'A close bond with the character; reaching milestones can unlock special story events and interactions.';

  @override
  String get statusPresetCorruptionLabel => '☣️ Abyssal Corruption';

  @override
  String get statusPresetCorruptionName => 'Abyssal Corruption';

  @override
  String get statusPresetCorruptionDescription =>
      'Physical and mental change accumulates here; excessive corruption may cause mutations.';

  @override
  String get statusPresetHungerLabel => '🍖 Hunger / Satiety';

  @override
  String get statusPresetHungerName => 'Satiety';

  @override
  String get statusPresetHungerDescription =>
      'Tracks stamina for exploration; dropping below 30 may cause weakness and exhaustion.';

  @override
  String get statusPresetMagicLabel => '🔥 Magic Overload';

  @override
  String get statusPresetMagicName => 'Magic Overload';

  @override
  String get statusPresetMagicDescription =>
      'Unstable power within; overloaded spells may injure the caster or backfire.';

  @override
  String get statusPresetPressureLabel => '⚡ Mental Pressure';

  @override
  String get statusPresetPressureName => 'Mental Pressure';

  @override
  String get statusPresetPressureDescription =>
      'Tracks the psychological strain caused by fear and danger.';

  @override
  String get statusPresetArmorLabel => '🛡️ Armor Durability';

  @override
  String get statusPresetArmorName => 'Armor Durability';

  @override
  String get statusPresetArmorDescription =>
      'Measures the resilience of defensive gear, which absorbs incoming impact first.';

  @override
  String get statusPresetSpiritLabel => '💧 Spirit Reserve';

  @override
  String get statusPresetSpiritName => 'Spirit Reserve';

  @override
  String get statusPresetSpiritDescription =>
      'The core spiritual energy used to perform spells and supernatural abilities.';

  @override
  String get adventureDefaultOpeningScene =>
      'You wake at an unfamiliar frontier. The surroundings are quiet. After checking your pack, you prepare to take your first step.';

  @override
  String get adventureDefaultOpeningOptionOne =>
      'Check the equipment and map you are carrying';

  @override
  String get adventureDefaultOpeningOptionTwo =>
      'Follow the road ahead and continue exploring';

  @override
  String get adventureDefaultOpeningOptionThree =>
      'Keep out of sight and observe your surroundings';

  @override
  String get autosaveTriggerDebounce => 'after typing pauses';

  @override
  String get autosaveTriggerMaxBufferedAge => 'during continuous typing';

  @override
  String get autosaveTriggerManual => 'manual save';

  @override
  String get autosaveTriggerPageLeave => 'when leaving the page';

  @override
  String get autosaveTriggerDispose => 'when closing the editor';

  @override
  String get autosaveTriggerCancel => 'before cancelling generation';

  @override
  String get autosaveTriggerGenerationError =>
      'before reporting a generation failure';

  @override
  String get autosaveTriggerAppLifecycle =>
      'when the app moves to the background';

  @override
  String get revisionBeforeRestore => 'Before restore';

  @override
  String get revisionBeforeCompression => 'Before compression';

  @override
  String get revisionAssembly => 'Assembly snapshot';

  @override
  String revisionCompressionSaved(int characters) {
    return 'Semantic compression (saved $characters characters)';
  }

  @override
  String get revisionModeRegenerate => 'Regenerate';

  @override
  String get revisionModeRewrite => 'Rewrite';

  @override
  String get revisionModeExpand => 'Expand';

  @override
  String get revisionModeCondense => 'Condense';

  @override
  String revisionBeforeRegeneration(String mode) {
    return 'Before $mode';
  }

  @override
  String readAloudSegmentProgress(int current, int total) {
    return 'Segment $current of $total';
  }

  @override
  String sessionTokenUsageMeter(int current, int limitThousands) {
    return '$current / ${limitThousands}K tokens';
  }

  @override
  String combatStatsSummary(int attack, int defense, int speed) {
    return 'Combat attributes · Attack $attack · Defense $defense · Speed $speed';
  }

  @override
  String get adventureAssetNotManaged =>
      'This asset is outside the resource library and is not checked for assembly readiness.';

  @override
  String get adventureAssemblyMissingCharacterCard =>
      'The assembly revision is missing a character card, so the adventure cannot start.';

  @override
  String get adventureAssemblyInvalidCharacterCard =>
      'The character card in the assembly revision could not be read, so the adventure cannot start.';

  @override
  String adventureAssetNoSavedRevision(String name) {
    return '\"$name\" has no saved revision yet, so the adventure cannot start.';
  }

  @override
  String adventureAssetPreparing(String name) {
    return 'Preparing \"$name\" for assembly. Please wait.';
  }

  @override
  String adventureAssetPreparingWithDetails(String name, String details) {
    return 'Preparing \"$name\": $details';
  }

  @override
  String adventureAssetPreparationFailed(String name, String details) {
    return 'Preparing \"$name\" failed: $details';
  }

  @override
  String adventureAssetReady(String name) {
    return '\"$name\" is ready.';
  }

  @override
  String adventureAssetNoAssemblyRevision(String name) {
    return '\"$name\" has no available revision. Complete its assembly first.';
  }

  @override
  String adventureAssetStaleWithPrevious(String name) {
    return '\"$name\" has changed. You can use the previous ready version.';
  }

  @override
  String get errorUnknown => 'Something went wrong. Please try again.';

  @override
  String get errorNetworkUnavailable =>
      'Network connection failed. Check your connection and try again.';

  @override
  String get errorRequestTimeout => 'The request timed out. Please try again.';

  @override
  String get errorUnauthorized =>
      'Authorization failed. Check your API settings.';

  @override
  String get errorPaymentRequired =>
      'The API account needs attention before this request can continue.';

  @override
  String get errorForbidden => 'Access was denied. Check your API permissions.';

  @override
  String get errorNotFound => 'The requested model or endpoint was not found.';

  @override
  String get errorRateLimited =>
      'Too many requests. Please wait and try again.';

  @override
  String get errorInvalidRequest =>
      'The request could not be processed. Check your settings and try again.';

  @override
  String resourceErrorCapacityExceeded(int current, int limit) {
    return 'Resource capacity exceeded ($current/$limit).';
  }

  @override
  String resourceErrorValidationFailed(String details) {
    return 'Resource validation failed: $details';
  }

  @override
  String get resourceErrorGenerationFailed =>
      'Resource generation failed. Please try again.';

  @override
  String get resourceErrorConflict =>
      'The resource changed. Reload and try again.';

  @override
  String adventureErrorAssetMissing(String name) {
    return '\"$name\" is not ready for this adventure.';
  }

  @override
  String adventureErrorAssetStale(String name) {
    return '\"$name\" has changed and must be prepared again.';
  }

  @override
  String get ttsErrorUnsupported => 'Read aloud is not supported here.';

  @override
  String get ttsErrorEngineUnavailable =>
      'The read-aloud engine is unavailable.';

  @override
  String get ttsErrorVoiceUnavailable => 'The selected voice is unavailable.';

  @override
  String get ttsErrorPlaybackFailed => 'Read aloud failed. Please try again.';

  @override
  String eventCombatVictory(int exp, int gold) {
    return 'Victory! Gained $exp EXP and $gold gold.';
  }

  @override
  String eventCombatAttack(String actor) {
    return '$actor attacks.';
  }

  @override
  String eventCombatCriticalHit(String actor) {
    return 'Critical hit by $actor!';
  }

  @override
  String eventCombatSkillUsed(String skill) {
    return 'Used skill $skill.';
  }

  @override
  String get eventCombatDefeat => 'Defeated.';

  @override
  String eventLevelUp(int level) {
    return 'Level up! Reached level $level.';
  }

  @override
  String get eventRestCompleted => 'Rest completed.';

  @override
  String eventItemAdded(String item) {
    return 'Added $item.';
  }

  @override
  String eventItemRemoved(String item) {
    return 'Removed $item.';
  }

  @override
  String eventItemUsed(String item) {
    return 'Used $item.';
  }

  @override
  String eventSkillLearned(String skill) {
    return 'Learned skill $skill.';
  }

  @override
  String get eventSkillFailed => 'The skill could not be used.';

  @override
  String get errorImportInvalidInput => 'Invalid import input.';

  @override
  String get errorImportParseFailed => 'Import data could not be parsed.';

  @override
  String get errorImportUnsupportedFormat =>
      'This import format is not supported.';

  @override
  String get adventureErrorReadinessFailed =>
      'Adventure readiness could not be verified.';

  @override
  String get partEditorDiscardedRemoteText =>
      'Discarded my text and adopted the latest content';

  @override
  String get sectionValidationIssueEmptySection => 'Section has no parts';

  @override
  String sectionValidationIssuePartMissing(Object part) {
    return '$part has no content';
  }

  @override
  String sectionValidationIssuePartTooLong(
      Object actual, Object limit, Object part) {
    return '$part is $actual characters long (limit $limit)';
  }
}
