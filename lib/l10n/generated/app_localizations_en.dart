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
  String get customEndpointPlaceholder => 'https://api.example.com/v1';

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
  String get enableThinkingLabel => 'Enable Deep Thinking (Reasoning)';

  @override
  String get enableThinkingSubtitle =>
      'Support reasoning models to output thinking chains before final prose';

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
}
