import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
    Locale('ko'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')
  ];

  /// App title
  ///
  /// In en, this message translates to:
  /// **'LT Dialogue'**
  String get appTitle;

  /// No description provided for @pageLoadError.
  ///
  /// In en, this message translates to:
  /// **'Page Load Error'**
  String get pageLoadError;

  /// No description provided for @reloadAction.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get reloadAction;

  /// No description provided for @loadingEnvironment.
  ///
  /// In en, this message translates to:
  /// **'Loading environment...'**
  String get loadingEnvironment;

  /// No description provided for @testingProviderConnection.
  ///
  /// In en, this message translates to:
  /// **'Testing {provider}...'**
  String testingProviderConnection(String provider);

  /// No description provided for @modelConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Model connection failed, please check settings'**
  String get modelConnectionFailed;

  /// No description provided for @apiKeyNotConfiguredPrompt.
  ///
  /// In en, this message translates to:
  /// **'API key not configured yet, you can configure it in settings'**
  String get apiKeyNotConfiguredPrompt;

  /// No description provided for @goToSettings.
  ///
  /// In en, this message translates to:
  /// **'Go to Settings'**
  String get goToSettings;

  /// No description provided for @createAdventureFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create scene, please try again later'**
  String get createAdventureFailed;

  /// No description provided for @navExplore.
  ///
  /// In en, this message translates to:
  /// **'Explore'**
  String get navExplore;

  /// No description provided for @navLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get navLibrary;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @sidebarNewAdventure.
  ///
  /// In en, this message translates to:
  /// **'New Adventure'**
  String get sidebarNewAdventure;

  /// No description provided for @sidebarRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get sidebarRecent;

  /// No description provided for @sidebarManageConversations.
  ///
  /// In en, this message translates to:
  /// **'Batch Manage Conversations'**
  String get sidebarManageConversations;

  /// No description provided for @sidebarEmptyConversations.
  ///
  /// In en, this message translates to:
  /// **'No past conversations'**
  String get sidebarEmptyConversations;

  /// No description provided for @sidebarUnnamedScene.
  ///
  /// In en, this message translates to:
  /// **'Unnamed Scene'**
  String get sidebarUnnamedScene;

  /// No description provided for @sidebarDeleteDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Scene Conversation'**
  String get sidebarDeleteDialogTitle;

  /// No description provided for @sidebarDeleteDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{title}\"?\nDeleted history and narrative evolution cannot be recovered.'**
  String sidebarDeleteDialogMessage(String title);

  /// No description provided for @sidebarReturnHome.
  ///
  /// In en, this message translates to:
  /// **'Return to Explore Hall'**
  String get sidebarReturnHome;

  /// No description provided for @sidebarExpand.
  ///
  /// In en, this message translates to:
  /// **'Expand Sidebar'**
  String get sidebarExpand;

  /// No description provided for @sidebarCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse Sidebar'**
  String get sidebarCollapse;

  /// No description provided for @sidebarClose.
  ///
  /// In en, this message translates to:
  /// **'Close Sidebar'**
  String get sidebarClose;

  /// No description provided for @brandSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Narrative & World Evolution Studio'**
  String get brandSubtitle;

  /// No description provided for @serviceConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get serviceConnected;

  /// No description provided for @serviceNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Key Not Configured'**
  String get serviceNotConfigured;

  /// No description provided for @officialOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get officialOnline;

  /// No description provided for @languageSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose Language'**
  String get languageSetupTitle;

  /// No description provided for @languageSetupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Please select your preferred display language'**
  String get languageSetupSubtitle;

  /// No description provided for @languageSettingTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageSettingTitle;

  /// No description provided for @languageSettingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'App display language'**
  String get languageSettingSubtitle;

  /// No description provided for @confirmAction.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirmAction;

  /// No description provided for @cancelAction.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelAction;

  /// No description provided for @deleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteAction;

  /// No description provided for @saveAction.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveAction;

  /// No description provided for @continueAction.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueAction;

  /// No description provided for @closeAction.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeAction;

  /// No description provided for @doneAction.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get doneAction;

  /// No description provided for @editAction.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editAction;

  /// No description provided for @retryAction.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryAction;

  /// No description provided for @copyAction.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copyAction;

  /// No description provided for @settingsCenter.
  ///
  /// In en, this message translates to:
  /// **'Settings Center'**
  String get settingsCenter;

  /// No description provided for @settingsSystemConfig.
  ///
  /// In en, this message translates to:
  /// **'System Configuration'**
  String get settingsSystemConfig;

  /// No description provided for @settingsReturnHome.
  ///
  /// In en, this message translates to:
  /// **'Return to Hall'**
  String get settingsReturnHome;

  /// No description provided for @settingsReturnList.
  ///
  /// In en, this message translates to:
  /// **'Return to Settings'**
  String get settingsReturnList;

  /// No description provided for @settingsPreferencesCategory.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get settingsPreferencesCategory;

  /// No description provided for @settingsCoreEngine.
  ///
  /// In en, this message translates to:
  /// **'LT Dialogue Core Engine'**
  String get settingsCoreEngine;

  /// No description provided for @settingsStorageType.
  ///
  /// In en, this message translates to:
  /// **'SQLite · Local Encryption First'**
  String get settingsStorageType;

  /// No description provided for @tabModelApi.
  ///
  /// In en, this message translates to:
  /// **'Models & API'**
  String get tabModelApi;

  /// No description provided for @tabModelApiSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Provider & Key Configuration'**
  String get tabModelApiSubtitle;

  /// No description provided for @tabSessionParams.
  ///
  /// In en, this message translates to:
  /// **'Session Parameters'**
  String get tabSessionParams;

  /// No description provided for @tabSessionParamsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sampling & Deep Thinking'**
  String get tabSessionParamsSubtitle;

  /// No description provided for @tabThemeAppearance.
  ///
  /// In en, this message translates to:
  /// **'Theme & Appearance'**
  String get tabThemeAppearance;

  /// No description provided for @tabThemeAppearanceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Light/Dark & Color Scheme'**
  String get tabThemeAppearanceSubtitle;

  /// No description provided for @tabDataManagement.
  ///
  /// In en, this message translates to:
  /// **'Data Management'**
  String get tabDataManagement;

  /// No description provided for @tabDataManagementSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Token Stats & Storage'**
  String get tabDataManagementSubtitle;

  /// No description provided for @configCategory.
  ///
  /// In en, this message translates to:
  /// **'Configuration Categories'**
  String get configCategory;

  /// No description provided for @apiServiceConnected.
  ///
  /// In en, this message translates to:
  /// **'LLM Service Connected'**
  String get apiServiceConnected;

  /// No description provided for @apiServiceConnectedDesc.
  ///
  /// In en, this message translates to:
  /// **'Click to manage provider, model and endpoints'**
  String get apiServiceConnectedDesc;

  /// No description provided for @apiServiceDisconnectedDesc.
  ///
  /// In en, this message translates to:
  /// **'Click to configure API key to start reasoning'**
  String get apiServiceDisconnectedDesc;

  /// No description provided for @providerConfigTitle.
  ///
  /// In en, this message translates to:
  /// **'Models & API Services'**
  String get providerConfigTitle;

  /// No description provided for @providerConfigSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Configure model providers, endpoints, and secure keys'**
  String get providerConfigSubtitle;

  /// No description provided for @testConnection.
  ///
  /// In en, this message translates to:
  /// **'Test Connection'**
  String get testConnection;

  /// No description provided for @testingConnection.
  ///
  /// In en, this message translates to:
  /// **'Testing...'**
  String get testingConnection;

  /// No description provided for @inputApiKeyHint.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid API key first'**
  String get inputApiKeyHint;

  /// No description provided for @connectionSuccess.
  ///
  /// In en, this message translates to:
  /// **'Connection successful! Took {time}ms, service status is great.'**
  String connectionSuccess(int time);

  /// No description provided for @connectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed, please check your key and network connection.'**
  String get connectionFailed;

  /// No description provided for @connectionFailedWithReason.
  ///
  /// In en, this message translates to:
  /// **'Connection failed: {error}'**
  String connectionFailedWithReason(String error);

  /// No description provided for @apiKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get apiKeyLabel;

  /// No description provided for @apiKeyPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Enter your API key'**
  String get apiKeyPlaceholder;

  /// No description provided for @customEndpointLabel.
  ///
  /// In en, this message translates to:
  /// **'Custom Endpoint (Base URL)'**
  String get customEndpointLabel;

  /// Model selector interface label.
  ///
  /// In en, this message translates to:
  /// **'Custom endpoint URL'**
  String get customEndpointPlaceholder;

  /// No description provided for @modelLabel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get modelLabel;

  /// No description provided for @modelPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Enter model name'**
  String get modelPlaceholder;

  /// No description provided for @customModelNote.
  ///
  /// In en, this message translates to:
  /// **'Using custom model endpoint'**
  String get customModelNote;

  /// No description provided for @modelParamsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Session Model Parameters'**
  String get modelParamsSectionTitle;

  /// No description provided for @modelParamsSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Fine-tune generation temperature, context budget, and reasoning mode'**
  String get modelParamsSectionSubtitle;

  /// No description provided for @systemPromptLabel.
  ///
  /// In en, this message translates to:
  /// **'Custom System Prompt'**
  String get systemPromptLabel;

  /// No description provided for @systemPromptPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Enter system prompt to guide AI role and behavior...'**
  String get systemPromptPlaceholder;

  /// No description provided for @authorsNoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Author\'\'s Note'**
  String get authorsNoteLabel;

  /// No description provided for @authorsNotePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Inject strong contextual reminders into recent turns...'**
  String get authorsNotePlaceholder;

  /// No description provided for @authorsNoteDepthLabel.
  ///
  /// In en, this message translates to:
  /// **'Insertion Depth: {depth} turns from bottom'**
  String authorsNoteDepthLabel(int depth);

  /// No description provided for @authorsNoteFrequencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Trigger Frequency: Every {freq} turns'**
  String authorsNoteFrequencyLabel(int freq);

  /// No description provided for @dialogueLevelLabel.
  ///
  /// In en, this message translates to:
  /// **'Prose Style & Depth'**
  String get dialogueLevelLabel;

  /// No description provided for @temperatureLabel.
  ///
  /// In en, this message translates to:
  /// **'Temperature (Randomness): {value}'**
  String temperatureLabel(String value);

  /// No description provided for @enableThinkingLabel.
  ///
  /// In en, this message translates to:
  /// **'Enable Deep Thinking (Deep Thinking)'**
  String get enableThinkingLabel;

  /// No description provided for @enableThinkingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When enabled, model outputs collapsible thinking chains before story prose'**
  String get enableThinkingSubtitle;

  /// No description provided for @reasoningEffortLabel.
  ///
  /// In en, this message translates to:
  /// **'Reasoning Effort'**
  String get reasoningEffortLabel;

  /// No description provided for @quickModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Quick Mode'**
  String get quickModeLabel;

  /// No description provided for @quickModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Bypass streaming animations and output full turns rapidly'**
  String get quickModeSubtitle;

  /// No description provided for @appearanceSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Appearance & Visual Theme'**
  String get appearanceSectionTitle;

  /// No description provided for @appearanceSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Customize interface color themes, dark mode, and reading font size'**
  String get appearanceSectionSubtitle;

  /// No description provided for @themeModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Theme Mode'**
  String get themeModeLabel;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeColorPalette.
  ///
  /// In en, this message translates to:
  /// **'Theme Palette'**
  String get themeColorPalette;

  /// No description provided for @themeColorPaletteHint.
  ///
  /// In en, this message translates to:
  /// **'Tap to switch instantly'**
  String get themeColorPaletteHint;

  /// No description provided for @chatFontSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Narrative Text Font Size: {size} pt'**
  String chatFontSizeLabel(int size);

  /// No description provided for @chatFontCompact.
  ///
  /// In en, this message translates to:
  /// **'Compact'**
  String get chatFontCompact;

  /// No description provided for @chatFontStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get chatFontStandard;

  /// No description provided for @chatFontSpacious.
  ///
  /// In en, this message translates to:
  /// **'Spacious'**
  String get chatFontSpacious;

  /// No description provided for @previewTypographyTitle.
  ///
  /// In en, this message translates to:
  /// **'Live Typography Preview'**
  String get previewTypographyTitle;

  /// No description provided for @previewTypographySample.
  ///
  /// In en, this message translates to:
  /// **'“LT Dialogue” — In the tapestry of interwoven worldlines, every decision you make ripples through fate. Dark undercity corridors, skyward mechanical ruins: all legends begin here.'**
  String get previewTypographySample;

  /// No description provided for @readingScrollTitle.
  ///
  /// In en, this message translates to:
  /// **'Reading & Scroll Controls'**
  String get readingScrollTitle;

  /// No description provided for @readingScrollSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Control screen scrolling behavior during generation'**
  String get readingScrollSubtitle;

  /// No description provided for @autoScrollLabel.
  ///
  /// In en, this message translates to:
  /// **'Auto-scroll during generation'**
  String get autoScrollLabel;

  /// No description provided for @autoScrollSubtitleOn.
  ///
  /// In en, this message translates to:
  /// **'Active: Screen continuously scrolls to the newest words as they generate.'**
  String get autoScrollSubtitleOn;

  /// No description provided for @autoScrollSubtitleOff.
  ///
  /// In en, this message translates to:
  /// **'Recommended (Reading First): Screen stays steady so you can read from the beginning without disruption.'**
  String get autoScrollSubtitleOff;

  /// No description provided for @dataManagementTitle.
  ///
  /// In en, this message translates to:
  /// **'Data Management & Usage Stats'**
  String get dataManagementTitle;

  /// No description provided for @dataManagementSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View Token consumption, TTS voice settings, and storage controls'**
  String get dataManagementSubtitle;

  /// No description provided for @tokenUsageTitle.
  ///
  /// In en, this message translates to:
  /// **'Local Token Consumption Estimate'**
  String get tokenUsageTitle;

  /// No description provided for @sessionTokensLabel.
  ///
  /// In en, this message translates to:
  /// **'Current Session Tokens'**
  String get sessionTokensLabel;

  /// No description provided for @totalTokensLabel.
  ///
  /// In en, this message translates to:
  /// **'Total Persisted Tokens'**
  String get totalTokensLabel;

  /// No description provided for @readAloudSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Voice Message Reading (TTS)'**
  String get readAloudSectionTitle;

  /// No description provided for @readAloudSupportedPlatform.
  ///
  /// In en, this message translates to:
  /// **'Platform supports system speech synthesis. Available in dialogue and studio.'**
  String get readAloudSupportedPlatform;

  /// No description provided for @readAloudUnsupportedPlatform.
  ///
  /// In en, this message translates to:
  /// **'Platform does not support system speech synthesis.'**
  String get readAloudUnsupportedPlatform;

  /// No description provided for @readAloudEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable Voice Reading'**
  String get readAloudEnable;

  /// No description provided for @readAloudEnableSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Support reading text in dialogue, studio, and assembly'**
  String get readAloudEnableSubtitle;

  /// No description provided for @readAloudAutoRead.
  ///
  /// In en, this message translates to:
  /// **'Auto Read on Completion'**
  String get readAloudAutoRead;

  /// No description provided for @readAloudAutoReadSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automatically read aloud when AI completes narrative turn'**
  String get readAloudAutoReadSubtitle;

  /// No description provided for @readAloudRate.
  ///
  /// In en, this message translates to:
  /// **'Speech Rate'**
  String get readAloudRate;

  /// No description provided for @readAloudPitch.
  ///
  /// In en, this message translates to:
  /// **'Pitch'**
  String get readAloudPitch;

  /// No description provided for @readAloudVolume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get readAloudVolume;

  /// No description provided for @readAloudLanguage.
  ///
  /// In en, this message translates to:
  /// **'Read-Aloud Language'**
  String get readAloudLanguage;

  /// No description provided for @readAloudAutoDetect.
  ///
  /// In en, this message translates to:
  /// **'Auto Detect'**
  String get readAloudAutoDetect;

  /// No description provided for @readAloudAutoDetectHint.
  ///
  /// In en, this message translates to:
  /// **'Automatically select system voice language based on text.'**
  String get readAloudAutoDetectHint;

  /// No description provided for @readAloudFixedHint.
  ///
  /// In en, this message translates to:
  /// **'All text will be read in the selected language.'**
  String get readAloudFixedHint;

  /// No description provided for @readAloudUnsupportedLanguage.
  ///
  /// In en, this message translates to:
  /// **' (Unsupported)'**
  String get readAloudUnsupportedLanguage;

  /// No description provided for @readAloudAvailableLanguagesCount.
  ///
  /// In en, this message translates to:
  /// **'System available voices: {count}'**
  String readAloudAvailableLanguagesCount(int count);

  /// No description provided for @readAloudDisabledInSettings.
  ///
  /// In en, this message translates to:
  /// **'Voice reading is disabled in settings'**
  String get readAloudDisabledInSettings;

  /// No description provided for @readAloudStop.
  ///
  /// In en, this message translates to:
  /// **'Stop Reading'**
  String get readAloudStop;

  /// No description provided for @readAloudStart.
  ///
  /// In en, this message translates to:
  /// **'Read Aloud'**
  String get readAloudStart;

  /// No description provided for @diagnosticExportTitle.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic Session Export'**
  String get diagnosticExportTitle;

  /// No description provided for @diagnosticExportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Only exports the last 30 turns of current branch; API credentials and hidden thoughts are excluded.'**
  String get diagnosticExportSubtitle;

  /// No description provided for @exportDiagnosticJson.
  ///
  /// In en, this message translates to:
  /// **'Export Diagnostic JSON'**
  String get exportDiagnosticJson;

  /// No description provided for @cacheStorageTitle.
  ///
  /// In en, this message translates to:
  /// **'Cache & Storage Management'**
  String get cacheStorageTitle;

  /// No description provided for @clearCache.
  ///
  /// In en, this message translates to:
  /// **'Clear Temp Cache'**
  String get clearCache;

  /// No description provided for @clearCacheSuccess.
  ///
  /// In en, this message translates to:
  /// **'Temporary cache cleared and counters reset'**
  String get clearCacheSuccess;

  /// No description provided for @clearAllData.
  ///
  /// In en, this message translates to:
  /// **'Clear All Local Data'**
  String get clearAllData;

  /// No description provided for @clearDataDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset All Local Data'**
  String get clearDataDialogTitle;

  /// No description provided for @clearDataDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete all local adventures, cards, and cached content?\nThis action cannot be undone.'**
  String get clearDataDialogMessage;

  /// No description provided for @exportChatTitle.
  ///
  /// In en, this message translates to:
  /// **'Export Chat'**
  String get exportChatTitle;

  /// No description provided for @importChatTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Chat'**
  String get importChatTitle;

  /// No description provided for @dashboardHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'LT Dialogue · Exploration & Narrative Studio'**
  String get dashboardHeroTitle;

  /// No description provided for @dashboardHeroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Interactive fiction & immersive RPG storytelling space'**
  String get dashboardHeroSubtitle;

  /// No description provided for @dashboardWizardCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Four-Step Custom Wizard'**
  String get dashboardWizardCardTitle;

  /// No description provided for @dashboardWizardCardDesc.
  ///
  /// In en, this message translates to:
  /// **'Start from blank canvas, define worldview, character cards, prologue and opening action.'**
  String get dashboardWizardCardDesc;

  /// No description provided for @dashboardWizardCardAction.
  ///
  /// In en, this message translates to:
  /// **'Launch Wizard'**
  String get dashboardWizardCardAction;

  /// No description provided for @dashboardPresetCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Preset Scene Studio'**
  String get dashboardPresetCardTitle;

  /// No description provided for @dashboardPresetCardDesc.
  ///
  /// In en, this message translates to:
  /// **'Browse prebuilt adventure scripts, start with one click or fine-tune.'**
  String get dashboardPresetCardDesc;

  /// No description provided for @dashboardPresetCardAction.
  ///
  /// In en, this message translates to:
  /// **'View Presets'**
  String get dashboardPresetCardAction;

  /// No description provided for @dashboardLibraryCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Resource Library'**
  String get dashboardLibraryCardTitle;

  /// No description provided for @dashboardLibraryCardDesc.
  ///
  /// In en, this message translates to:
  /// **'Review and manage your worldviews, character cards, and NPC archives.'**
  String get dashboardLibraryCardDesc;

  /// No description provided for @dashboardLibraryCardAction.
  ///
  /// In en, this message translates to:
  /// **'Manage Library'**
  String get dashboardLibraryCardAction;

  /// No description provided for @dashboardSettingsCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings Center'**
  String get dashboardSettingsCardTitle;

  /// No description provided for @dashboardSettingsCardDesc.
  ///
  /// In en, this message translates to:
  /// **'Configure model connection parameters, visual themes, and data management.'**
  String get dashboardSettingsCardDesc;

  /// No description provided for @dashboardSettingsCardAction.
  ///
  /// In en, this message translates to:
  /// **'Enter Settings'**
  String get dashboardSettingsCardAction;

  /// No description provided for @recentAdventuresTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent Adventures'**
  String get recentAdventuresTitle;

  /// No description provided for @noRecentAdventures.
  ///
  /// In en, this message translates to:
  /// **'No adventures yet. Launch a wizard or choose a preset to begin.'**
  String get noRecentAdventures;

  /// No description provided for @continueAdventure.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueAdventure;

  /// No description provided for @featuredWorldviews.
  ///
  /// In en, this message translates to:
  /// **'Featured Worldviews'**
  String get featuredWorldviews;

  /// No description provided for @featuredCharacters.
  ///
  /// In en, this message translates to:
  /// **'Featured Characters'**
  String get featuredCharacters;

  /// No description provided for @resourceLibraryTitle.
  ///
  /// In en, this message translates to:
  /// **'Resource Library'**
  String get resourceLibraryTitle;

  /// No description provided for @resourceLibrarySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Browse and manage worldviews, character cards, and scenario templates'**
  String get resourceLibrarySubtitle;

  /// No description provided for @createResourceAction.
  ///
  /// In en, this message translates to:
  /// **'Create Resource'**
  String get createResourceAction;

  /// No description provided for @searchResources.
  ///
  /// In en, this message translates to:
  /// **'Search resources...'**
  String get searchResources;

  /// No description provided for @allResources.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get allResources;

  /// No description provided for @worldviewsTab.
  ///
  /// In en, this message translates to:
  /// **'Worldviews'**
  String get worldviewsTab;

  /// No description provided for @charactersTab.
  ///
  /// In en, this message translates to:
  /// **'Characters'**
  String get charactersTab;

  /// No description provided for @templatesTab.
  ///
  /// In en, this message translates to:
  /// **'Templates'**
  String get templatesTab;

  /// No description provided for @recycleBinTitle.
  ///
  /// In en, this message translates to:
  /// **'Recycle Bin'**
  String get recycleBinTitle;

  /// No description provided for @emptyRecycleBin.
  ///
  /// In en, this message translates to:
  /// **'Recycle bin is empty'**
  String get emptyRecycleBin;

  /// No description provided for @restoreAction.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restoreAction;

  /// No description provided for @permanentlyDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete Permanently'**
  String get permanentlyDelete;

  /// No description provided for @resourceStudioTitle.
  ///
  /// In en, this message translates to:
  /// **'Resource Studio'**
  String get resourceStudioTitle;

  /// No description provided for @resourceStudioSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Multi-part progressive authoring and capacity management'**
  String get resourceStudioSubtitle;

  /// No description provided for @outlineTab.
  ///
  /// In en, this message translates to:
  /// **'Outline'**
  String get outlineTab;

  /// No description provided for @capacityTab.
  ///
  /// In en, this message translates to:
  /// **'Capacity'**
  String get capacityTab;

  /// No description provided for @historyTab.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyTab;

  /// No description provided for @generatePart.
  ///
  /// In en, this message translates to:
  /// **'Generate Content'**
  String get generatePart;

  /// No description provided for @regeneratePart.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get regeneratePart;

  /// No description provided for @partSaved.
  ///
  /// In en, this message translates to:
  /// **'Changes saved'**
  String get partSaved;

  /// No description provided for @partSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get partSaving;

  /// No description provided for @assemblyWizardTitle.
  ///
  /// In en, this message translates to:
  /// **'Adventure Assembly & Readiness'**
  String get assemblyWizardTitle;

  /// No description provided for @wizardWorldviewAiSummary.
  ///
  /// In en, this message translates to:
  /// **'Describe a genre or core idea. AI can draft a worldview here or create a detailed, multi-section setting in the library.'**
  String get wizardWorldviewAiSummary;

  /// No description provided for @adventureWizardTitle.
  ///
  /// In en, this message translates to:
  /// **'Custom Adventure Wizard'**
  String get adventureWizardTitle;

  /// No description provided for @assemblyStepWorld.
  ///
  /// In en, this message translates to:
  /// **'1. Worldview'**
  String get assemblyStepWorld;

  /// No description provided for @assemblyStepCharacters.
  ///
  /// In en, this message translates to:
  /// **'2. Character'**
  String get assemblyStepCharacters;

  /// No description provided for @assemblyStepNpcs.
  ///
  /// In en, this message translates to:
  /// **'3. NPCs'**
  String get assemblyStepNpcs;

  /// No description provided for @assemblyStepConfig.
  ///
  /// In en, this message translates to:
  /// **'4. Config & Opening'**
  String get assemblyStepConfig;

  /// No description provided for @assemblyPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Assembly Preview'**
  String get assemblyPreviewTitle;

  /// No description provided for @startAdventureAction.
  ///
  /// In en, this message translates to:
  /// **'Start Adventure'**
  String get startAdventureAction;

  /// No description provided for @readinessChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking resource readiness...'**
  String get readinessChecking;

  /// No description provided for @readinessPassed.
  ///
  /// In en, this message translates to:
  /// **'All resources ready'**
  String get readinessPassed;

  /// No description provided for @readinessFailed.
  ///
  /// In en, this message translates to:
  /// **'Resources require preparation or compression'**
  String get readinessFailed;

  /// No description provided for @adventureSessionTitle.
  ///
  /// In en, this message translates to:
  /// **'Adventure Session'**
  String get adventureSessionTitle;

  /// No description provided for @inputActionHint.
  ///
  /// In en, this message translates to:
  /// **'What do you do next? Enter your action or dialogue...'**
  String get inputActionHint;

  /// No description provided for @sendAction.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get sendAction;

  /// No description provided for @aiThinking.
  ///
  /// In en, this message translates to:
  /// **'AI is pondering...'**
  String get aiThinking;

  /// No description provided for @aiWriting.
  ///
  /// In en, this message translates to:
  /// **'AI is writing...'**
  String get aiWriting;

  /// No description provided for @diceCheckTitle.
  ///
  /// In en, this message translates to:
  /// **'Dice Check'**
  String get diceCheckTitle;

  /// No description provided for @turnSettling.
  ///
  /// In en, this message translates to:
  /// **'Settling turn options...'**
  String get turnSettling;

  /// No description provided for @bookmarkAdded.
  ///
  /// In en, this message translates to:
  /// **'Bookmark added'**
  String get bookmarkAdded;

  /// No description provided for @bookmarkRemoved.
  ///
  /// In en, this message translates to:
  /// **'Bookmark removed'**
  String get bookmarkRemoved;

  /// No description provided for @messageCopied.
  ///
  /// In en, this message translates to:
  /// **'Message copied to clipboard'**
  String get messageCopied;

  /// No description provided for @messageEdited.
  ///
  /// In en, this message translates to:
  /// **'Message edited'**
  String get messageEdited;

  /// No description provided for @chatEditMessage.
  ///
  /// In en, this message translates to:
  /// **'Edit message'**
  String get chatEditMessage;

  /// No description provided for @chatReadAloudUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Read aloud is not supported on this platform'**
  String get chatReadAloudUnsupported;

  /// No description provided for @chatCopyReasoning.
  ///
  /// In en, this message translates to:
  /// **'Copy reasoning (thought chain)'**
  String get chatCopyReasoning;

  /// No description provided for @chatReasoningCopied.
  ///
  /// In en, this message translates to:
  /// **'Reasoning copied to clipboard'**
  String get chatReasoningCopied;

  /// No description provided for @chatRetryWithModel.
  ///
  /// In en, this message translates to:
  /// **'Retry with another model'**
  String get chatRetryWithModel;

  /// No description provided for @chatFork.
  ///
  /// In en, this message translates to:
  /// **'Fork from here'**
  String get chatFork;

  /// No description provided for @chatBranchCreated.
  ///
  /// In en, this message translates to:
  /// **'Created branch {branch}'**
  String chatBranchCreated(Object branch);

  /// No description provided for @chatDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get chatDeleteMessage;

  /// No description provided for @chatSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search conversation...'**
  String get chatSearchHint;

  /// No description provided for @chatBookmarksOnly.
  ///
  /// In en, this message translates to:
  /// **'Bookmarks only'**
  String get chatBookmarksOnly;

  /// No description provided for @chatMoreActions.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get chatMoreActions;

  /// No description provided for @chatEditStatus.
  ///
  /// In en, this message translates to:
  /// **'Edit status'**
  String get chatEditStatus;

  /// No description provided for @chatDeleteStatus.
  ///
  /// In en, this message translates to:
  /// **'Delete status'**
  String get chatDeleteStatus;

  /// No description provided for @readAloudPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get readAloudPause;

  /// No description provided for @readAloudPauseRestart.
  ///
  /// In en, this message translates to:
  /// **'Pause (resume from this segment)'**
  String get readAloudPauseRestart;

  /// No description provided for @readAloudResume.
  ///
  /// In en, this message translates to:
  /// **'Resume reading'**
  String get readAloudResume;

  /// No description provided for @readAloudPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing to read'**
  String get readAloudPreparing;

  /// No description provided for @readAloudPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous segment'**
  String get readAloudPrevious;

  /// No description provided for @readAloudNext.
  ///
  /// In en, this message translates to:
  /// **'Next segment'**
  String get readAloudNext;

  /// No description provided for @tokenCurrentScene.
  ///
  /// In en, this message translates to:
  /// **'Current Scene Tokens'**
  String get tokenCurrentScene;

  /// No description provided for @tokenHistoryTotal.
  ///
  /// In en, this message translates to:
  /// **'Historical Total Tokens'**
  String get tokenHistoryTotal;

  /// No description provided for @tokenCurrentSceneDescription.
  ///
  /// In en, this message translates to:
  /// **'Tokens used in current scene'**
  String get tokenCurrentSceneDescription;

  /// No description provided for @tokenHistoryDescription.
  ///
  /// In en, this message translates to:
  /// **'Historical total recorded locally'**
  String get tokenHistoryDescription;

  /// No description provided for @readAloudPlatformSupportedMessage.
  ///
  /// In en, this message translates to:
  /// **'This platform supports system speech synthesis; available in dialogue and studio.'**
  String get readAloudPlatformSupportedMessage;

  /// No description provided for @diagnosticExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic export failed. Please try again later.'**
  String get diagnosticExportFailed;

  /// No description provided for @diagnosticExported.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic session exported: {path}'**
  String diagnosticExported(Object path);

  /// No description provided for @clearHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear Conversation History'**
  String get clearHistoryTitle;

  /// No description provided for @clearHistoryMessage.
  ///
  /// In en, this message translates to:
  /// **'Clear all saved conversations?\nWorldviews and character cards will remain, but scene chat history cannot be recovered.'**
  String get clearHistoryMessage;

  /// No description provided for @clearHistoryConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear History'**
  String get clearHistoryConfirm;

  /// No description provided for @clearHistorySuccess.
  ///
  /// In en, this message translates to:
  /// **'All conversation history was cleared'**
  String get clearHistorySuccess;

  /// No description provided for @readAloudRateLabel.
  ///
  /// In en, this message translates to:
  /// **'Speech Rate'**
  String get readAloudRateLabel;

  /// No description provided for @readAloudPitchLabel.
  ///
  /// In en, this message translates to:
  /// **'Pitch'**
  String get readAloudPitchLabel;

  /// No description provided for @readAloudLanguageHintAuto.
  ///
  /// In en, this message translates to:
  /// **'Automatically select an available system voice language for each passage.'**
  String get readAloudLanguageHintAuto;

  /// No description provided for @readAloudLanguageHintFixed.
  ///
  /// In en, this message translates to:
  /// **'All passages will be read in the selected language.'**
  String get readAloudLanguageHintFixed;

  /// No description provided for @readAloudSupportedCount.
  ///
  /// In en, this message translates to:
  /// **'System available voices: {count}'**
  String readAloudSupportedCount(Object count);

  /// No description provided for @generationWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for content generation…'**
  String get generationWaiting;

  /// No description provided for @errorTimeoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Request timed out'**
  String get errorTimeoutTitle;

  /// No description provided for @errorTimeoutSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Check your network connection and try again'**
  String get errorTimeoutSuggestion;

  /// No description provided for @errorAuthTitle.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed'**
  String get errorAuthTitle;

  /// No description provided for @errorAuthSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Check whether your API key is valid'**
  String get errorAuthSuggestion;

  /// No description provided for @errorRateTitle.
  ///
  /// In en, this message translates to:
  /// **'Too many requests'**
  String get errorRateTitle;

  /// No description provided for @errorRateSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Please wait a moment and try again'**
  String get errorRateSuggestion;

  /// No description provided for @errorApiTitle.
  ///
  /// In en, this message translates to:
  /// **'API error'**
  String get errorApiTitle;

  /// No description provided for @errorApiSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Check your API configuration or try again later'**
  String get errorApiSuggestion;

  /// No description provided for @errorNetworkTitle.
  ///
  /// In en, this message translates to:
  /// **'Network error'**
  String get errorNetworkTitle;

  /// No description provided for @errorNetworkSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Check your network connection and API settings, then try again'**
  String get errorNetworkSuggestion;

  /// No description provided for @switchModelRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry with another model'**
  String get switchModelRetry;

  /// No description provided for @resourceTrashTooltip.
  ///
  /// In en, this message translates to:
  /// **'Recycle bin'**
  String get resourceTrashTooltip;

  /// No description provided for @resourceCreateShort.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get resourceCreateShort;

  /// No description provided for @resourceNpcTab.
  ///
  /// In en, this message translates to:
  /// **'NPCs'**
  String get resourceNpcTab;

  /// No description provided for @resourceRetryLoad.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get resourceRetryLoad;

  /// No description provided for @resourceEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No resources yet'**
  String get resourceEmptyTitle;

  /// No description provided for @resourceNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matching resources'**
  String get resourceNoMatches;

  /// No description provided for @resourceNoSummary.
  ///
  /// In en, this message translates to:
  /// **'No summary'**
  String get resourceNoSummary;

  /// No description provided for @resourceMovedToTrash.
  ///
  /// In en, this message translates to:
  /// **'Moved to recycle bin'**
  String get resourceMovedToTrash;

  /// No description provided for @refreshRecycleBin.
  ///
  /// In en, this message translates to:
  /// **'Refresh recycle bin'**
  String get refreshRecycleBin;

  /// No description provided for @permanentDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" and its contents will be permanently deleted and cannot be recovered.\nContinue?'**
  String permanentDeleteMessage(Object title);

  /// No description provided for @readinessBlockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Cannot start adventure yet'**
  String get readinessBlockedTitle;

  /// No description provided for @acknowledgeAction.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get acknowledgeAction;

  /// No description provided for @staleResourceTitle.
  ///
  /// In en, this message translates to:
  /// **'Resources changed'**
  String get staleResourceTitle;

  /// No description provided for @staleResourceMessage.
  ///
  /// In en, this message translates to:
  /// **'The following resources changed after the last ready revision:'**
  String get staleResourceMessage;

  /// No description provided for @usePreviousReady.
  ///
  /// In en, this message translates to:
  /// **'Start with the previous ready version?'**
  String get usePreviousReady;

  /// No description provided for @chatImportFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get chatImportFormat;

  /// No description provided for @chatImportLabel.
  ///
  /// In en, this message translates to:
  /// **'Chat content'**
  String get chatImportLabel;

  /// No description provided for @chatImportHint.
  ///
  /// In en, this message translates to:
  /// **'Paste chat content here...'**
  String get chatImportHint;

  /// No description provided for @chatImportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Import succeeded'**
  String get chatImportSuccess;

  /// No description provided for @chatImportParsing.
  ///
  /// In en, this message translates to:
  /// **'Parsing...'**
  String get chatImportParsing;

  /// No description provided for @chatImportAction.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get chatImportAction;

  /// No description provided for @chatImportEmpty.
  ///
  /// In en, this message translates to:
  /// **'Please paste chat content first'**
  String get chatImportEmpty;

  /// No description provided for @chatImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String chatImportFailed(Object error);

  /// No description provided for @chatExportWarning.
  ///
  /// In en, this message translates to:
  /// **'Exports may contain conversations and user input. Keep the file safe.'**
  String get chatExportWarning;

  /// No description provided for @chatSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed'**
  String get chatSaveFailed;

  /// No description provided for @chatSavedPath.
  ///
  /// In en, this message translates to:
  /// **'Saved: {path}'**
  String chatSavedPath(Object path);

  /// No description provided for @chatSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get chatSaving;

  /// No description provided for @chatLoadFailedRetry.
  ///
  /// In en, this message translates to:
  /// **'Load failed, retry'**
  String get chatLoadFailedRetry;

  /// No description provided for @chatCharacterCount.
  ///
  /// In en, this message translates to:
  /// **'{count} characters'**
  String chatCharacterCount(Object count);

  /// No description provided for @resourceDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Resource Details'**
  String get resourceDetailTitle;

  /// No description provided for @resourceEnterStudio.
  ///
  /// In en, this message translates to:
  /// **'Open Resource Studio'**
  String get resourceEnterStudio;

  /// No description provided for @resourceLegacyNoStudio.
  ///
  /// In en, this message translates to:
  /// **'Advanced authoring is unavailable for legacy resources'**
  String get resourceLegacyNoStudio;

  /// No description provided for @resourceActions.
  ///
  /// In en, this message translates to:
  /// **'Resource Actions'**
  String get resourceActions;

  /// No description provided for @moveToTrashAction.
  ///
  /// In en, this message translates to:
  /// **'Move to Recycle Bin'**
  String get moveToTrashAction;

  /// No description provided for @moveToTrashMessage.
  ///
  /// In en, this message translates to:
  /// **'Move \"{name}\" to the recycle bin? It can be restored later.'**
  String moveToTrashMessage(Object name);

  /// No description provided for @moveToTrashFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not move to recycle bin. Try again.'**
  String get moveToTrashFailed;

  /// No description provided for @thinkingEngineTitle.
  ///
  /// In en, this message translates to:
  /// **'Deep Thinking Engine'**
  String get thinkingEngineTitle;

  /// No description provided for @thinkingEngineBadge.
  ///
  /// In en, this message translates to:
  /// **'V4.1 Native Reasoning'**
  String get thinkingEngineBadge;

  /// No description provided for @thinkingEngineDescription.
  ///
  /// In en, this message translates to:
  /// **'For complex branching adventures and world logic; enables pre-narrative planning with DeepSeek V4.1 reasoning.'**
  String get thinkingEngineDescription;

  /// No description provided for @worldviewDeepThinkingLabel.
  ///
  /// In en, this message translates to:
  /// **'Deep reasoning for worldviews'**
  String get worldviewDeepThinkingLabel;

  /// No description provided for @worldviewDeepThinkingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Allow V4.1 reasoning during AI worldview import; disabled by default to reduce first-token latency'**
  String get worldviewDeepThinkingSubtitle;

  /// No description provided for @characterDeepThinkingLabel.
  ///
  /// In en, this message translates to:
  /// **'Deep reasoning for character cards'**
  String get characterDeepThinkingLabel;

  /// No description provided for @characterDeepThinkingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Allow V4.1 reasoning during AI character import; disabled by default for faster generation'**
  String get characterDeepThinkingSubtitle;

  /// No description provided for @reasoningEffortLow.
  ///
  /// In en, this message translates to:
  /// **'Light · Fast response'**
  String get reasoningEffortLow;

  /// No description provided for @reasoningEffortMedium.
  ///
  /// In en, this message translates to:
  /// **'Balanced · Recommended'**
  String get reasoningEffortMedium;

  /// No description provided for @reasoningEffortHigh.
  ///
  /// In en, this message translates to:
  /// **'Deep thinking · Rich detail'**
  String get reasoningEffortHigh;

  /// No description provided for @reasoningEffortMax.
  ///
  /// In en, this message translates to:
  /// **'Maximum · Rigorous logic'**
  String get reasoningEffortMax;

  /// No description provided for @restoreRecommended.
  ///
  /// In en, this message translates to:
  /// **'Restore recommended defaults'**
  String get restoreRecommended;

  /// No description provided for @recommendedDefaultsRestored.
  ///
  /// In en, this message translates to:
  /// **'Official recommended defaults restored'**
  String get recommendedDefaultsRestored;

  /// No description provided for @revisionHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Revision History'**
  String get revisionHistoryTitle;

  /// No description provided for @revisionCount.
  ///
  /// In en, this message translates to:
  /// **'{count} revisions'**
  String revisionCount(Object count);

  /// No description provided for @refreshRevisionHistory.
  ///
  /// In en, this message translates to:
  /// **'Refresh revision history'**
  String get refreshRevisionHistory;

  /// No description provided for @noRestorableRevisions.
  ///
  /// In en, this message translates to:
  /// **'No restorable revisions yet'**
  String get noRestorableRevisions;

  /// No description provided for @currentRevision.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get currentRevision;

  /// No description provided for @restoreRevision.
  ///
  /// In en, this message translates to:
  /// **'Restore this revision'**
  String get restoreRevision;

  /// No description provided for @presetParseError.
  ///
  /// In en, this message translates to:
  /// **'The scene data could not be parsed or is incomplete'**
  String get presetParseError;

  /// No description provided for @presetWorldviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Worldview'**
  String get presetWorldviewTitle;

  /// No description provided for @presetCharacterTitle.
  ///
  /// In en, this message translates to:
  /// **'Protagonist Profile'**
  String get presetCharacterTitle;

  /// No description provided for @presetOpeningTitle.
  ///
  /// In en, this message translates to:
  /// **'Opening Prologue'**
  String get presetOpeningTitle;

  /// No description provided for @presetOptionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Initial Action Branches'**
  String get presetOptionsTitle;

  /// No description provided for @presetNpcTitle.
  ///
  /// In en, this message translates to:
  /// **'Supporting Characters (NPCs)'**
  String get presetNpcTitle;

  /// No description provided for @presetCustomizeAction.
  ///
  /// In en, this message translates to:
  /// **'Load and Customize'**
  String get presetCustomizeAction;

  /// No description provided for @presetDetailsAction.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get presetDetailsAction;

  /// No description provided for @sidebarEmptyConversationsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Click the button above to start a new adventure'**
  String get sidebarEmptyConversationsSubtitle;

  /// No description provided for @sidebarDeleteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete conversation'**
  String get sidebarDeleteTooltip;

  /// No description provided for @sidebarSettingsNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Settings (Key not configured)'**
  String get sidebarSettingsNotConfigured;

  /// No description provided for @characterFallbackName.
  ///
  /// In en, this message translates to:
  /// **'Character A'**
  String get characterFallbackName;

  /// No description provided for @monitoredStatus.
  ///
  /// In en, this message translates to:
  /// **'Monitored Status'**
  String get monitoredStatus;

  /// No description provided for @expandAction.
  ///
  /// In en, this message translates to:
  /// **'Expand ▼'**
  String get expandAction;

  /// No description provided for @collapseAction.
  ///
  /// In en, this message translates to:
  /// **'Collapse ▲'**
  String get collapseAction;

  /// No description provided for @statusItemsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String statusItemsCount(int count);

  /// No description provided for @optionsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Options ({count} options)'**
  String optionsSectionTitle(int count);

  /// No description provided for @selectPrompt.
  ///
  /// In en, this message translates to:
  /// **'Please select'**
  String get selectPrompt;

  /// No description provided for @noOptionsAvailable.
  ///
  /// In en, this message translates to:
  /// **'No options available'**
  String get noOptionsAvailable;

  /// No description provided for @notSpecified.
  ///
  /// In en, this message translates to:
  /// **'Not specified'**
  String get notSpecified;

  /// No description provided for @itemsSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String itemsSelectedCount(int count);

  /// No description provided for @backAction.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get backAction;

  /// No description provided for @showPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get hidePassword;

  /// No description provided for @actionMenuTitle.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get actionMenuTitle;

  /// No description provided for @actionMenuSemanticLabel.
  ///
  /// In en, this message translates to:
  /// **'Action menu'**
  String get actionMenuSemanticLabel;

  /// No description provided for @menuTooltip.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get menuTooltip;

  /// No description provided for @switchLibrary.
  ///
  /// In en, this message translates to:
  /// **'Switch Library'**
  String get switchLibrary;

  /// No description provided for @customAttributesTitle.
  ///
  /// In en, this message translates to:
  /// **'Custom Attributes'**
  String get customAttributesTitle;

  /// No description provided for @customAttributesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add custom lore or status for character/NPC with individual inference weighting'**
  String get customAttributesSubtitle;

  /// No description provided for @addCustomAttributeAction.
  ///
  /// In en, this message translates to:
  /// **'Add Item'**
  String get addCustomAttributeAction;

  /// No description provided for @noCustomAttributes.
  ///
  /// In en, this message translates to:
  /// **'No custom attributes'**
  String get noCustomAttributes;

  /// No description provided for @customAttributesEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Tap \"Add Item\" above to define signature weapons, taboos, weaknesses, or traits'**
  String get customAttributesEmptyHint;

  /// No description provided for @customAttributeNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Item Name *'**
  String get customAttributeNameLabel;

  /// No description provided for @customAttributeNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Signature sword, fatal weakness, casting habit'**
  String get customAttributeNameHint;

  /// No description provided for @deleteAttributeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete this item'**
  String get deleteAttributeTooltip;

  /// No description provided for @customAttributeContentLabel.
  ///
  /// In en, this message translates to:
  /// **'Content / Lore Description'**
  String get customAttributeContentLabel;

  /// No description provided for @customAttributeContentHint.
  ///
  /// In en, this message translates to:
  /// **'Describe effect, origin, or limitation (LLM will heed the importance level)'**
  String get customAttributeContentHint;

  /// No description provided for @customAttributeImportanceReference.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get customAttributeImportanceReference;

  /// No description provided for @customAttributeImportanceImportant.
  ///
  /// In en, this message translates to:
  /// **'Important'**
  String get customAttributeImportanceImportant;

  /// No description provided for @customAttributeImportanceVeryImportant.
  ///
  /// In en, this message translates to:
  /// **'Very Important'**
  String get customAttributeImportanceVeryImportant;

  /// No description provided for @customAttributeImportanceCritical.
  ///
  /// In en, this message translates to:
  /// **'Critical'**
  String get customAttributeImportanceCritical;

  /// No description provided for @feedbackSuccess.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get feedbackSuccess;

  /// No description provided for @feedbackError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get feedbackError;

  /// No description provided for @feedbackWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get feedbackWarning;

  /// No description provided for @feedbackInfo.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get feedbackInfo;

  /// No description provided for @refreshFailed.
  ///
  /// In en, this message translates to:
  /// **'Refresh failed, please try again later'**
  String get refreshFailed;

  /// No description provided for @noRefreshNeeded.
  ///
  /// In en, this message translates to:
  /// **'Current page does not need refresh'**
  String get noRefreshNeeded;

  /// No description provided for @fontSizeDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Adjust Font Size'**
  String get fontSizeDialogTitle;

  /// No description provided for @fontSizeSmall.
  ///
  /// In en, this message translates to:
  /// **'A Small'**
  String get fontSizeSmall;

  /// No description provided for @fontSizeLarge.
  ///
  /// In en, this message translates to:
  /// **'A Large'**
  String get fontSizeLarge;

  /// No description provided for @fontSizePreview.
  ///
  /// In en, this message translates to:
  /// **'Preview: Text 123\nFont size sample'**
  String get fontSizePreview;

  /// Model selector interface label.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get applyAction;

  /// No description provided for @appliedPresetNotice.
  ///
  /// In en, this message translates to:
  /// **'Applied: {preset}'**
  String appliedPresetNotice(String preset);

  /// No description provided for @dialogueParamsTitle.
  ///
  /// In en, this message translates to:
  /// **'Dialogue Parameters'**
  String get dialogueParamsTitle;

  /// No description provided for @paramsPresetLabel.
  ///
  /// In en, this message translates to:
  /// **'Parameter Presets'**
  String get paramsPresetLabel;

  /// No description provided for @customPreset.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get customPreset;

  /// No description provided for @frequencyPenalty.
  ///
  /// In en, this message translates to:
  /// **'Frequency Penalty'**
  String get frequencyPenalty;

  /// No description provided for @presencePenalty.
  ///
  /// In en, this message translates to:
  /// **'Presence Penalty'**
  String get presencePenalty;

  /// No description provided for @saveWorldviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Save Worldview'**
  String get saveWorldviewTitle;

  /// No description provided for @worldviewInfoSection.
  ///
  /// In en, this message translates to:
  /// **'Worldview Information'**
  String get worldviewInfoSection;

  /// No description provided for @worldviewSavedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Saved worldview \"{name}\"'**
  String worldviewSavedSuccess(String name);

  /// No description provided for @saveFailedPrefix.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String saveFailedPrefix(String error);

  /// No description provided for @importCardDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Character Card'**
  String get importCardDialogTitle;

  /// No description provided for @pasteCardJsonHeader.
  ///
  /// In en, this message translates to:
  /// **'Paste SillyTavern / Chub Character Card JSON'**
  String get pasteCardJsonHeader;

  /// No description provided for @pasteCardJsonHint.
  ///
  /// In en, this message translates to:
  /// **'Paste character card JSON content here...'**
  String get pasteCardJsonHint;

  /// No description provided for @newDialoguePersonaTitle.
  ///
  /// In en, this message translates to:
  /// **'New Dialogue Persona'**
  String get newDialoguePersonaTitle;

  /// No description provided for @editDialoguePersonaTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Dialogue Persona'**
  String get editDialoguePersonaTitle;

  /// No description provided for @dialoguePersonaSettingHeader.
  ///
  /// In en, this message translates to:
  /// **'Dialogue Persona Settings'**
  String get dialoguePersonaSettingHeader;

  /// No description provided for @dialoguePersonaScopeNotice.
  ///
  /// In en, this message translates to:
  /// **'Personas here are used for dialogue mode only and can be completely independent of Naira.'**
  String get dialoguePersonaScopeNotice;

  /// No description provided for @personaNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Persona Name *'**
  String get personaNameLabel;

  /// No description provided for @personaNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Naira, Advisor, Writing Partner'**
  String get personaNameHint;

  /// No description provided for @personaRoleLabel.
  ///
  /// In en, this message translates to:
  /// **'Role / Identity'**
  String get personaRoleLabel;

  /// No description provided for @personaRoleHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. General AI Assistant, Language Coach, Worldview Advisor'**
  String get personaRoleHint;

  /// No description provided for @personaUserAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'User Address'**
  String get personaUserAddressLabel;

  /// No description provided for @personaUserAddressHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. User, Creator, Commander, Teacher'**
  String get personaUserAddressHint;

  /// No description provided for @personaPersonalityLabel.
  ///
  /// In en, this message translates to:
  /// **'Personality & Behavioral Traits'**
  String get personaPersonalityLabel;

  /// No description provided for @personaPersonalityHint.
  ///
  /// In en, this message translates to:
  /// **'Describe personality, values, and problem-solving style'**
  String get personaPersonalityHint;

  /// No description provided for @personaSpeakingStyleLabel.
  ///
  /// In en, this message translates to:
  /// **'Speaking Style'**
  String get personaSpeakingStyleLabel;

  /// No description provided for @personaSpeakingStyleHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Concise, gentle, explain with steps and examples when needed'**
  String get personaSpeakingStyleHint;

  /// No description provided for @personaBackgroundLabel.
  ///
  /// In en, this message translates to:
  /// **'Background Lore'**
  String get personaBackgroundLabel;

  /// No description provided for @personaBackgroundHint.
  ///
  /// In en, this message translates to:
  /// **'Where the persona comes from and what they know'**
  String get personaBackgroundHint;

  /// No description provided for @personaContextLabel.
  ///
  /// In en, this message translates to:
  /// **'Dialogue Context'**
  String get personaContextLabel;

  /// No description provided for @personaContextHint.
  ///
  /// In en, this message translates to:
  /// **'Describe the context in which the character communicates with the user'**
  String get personaContextHint;

  /// No description provided for @personaDirectivesLabel.
  ///
  /// In en, this message translates to:
  /// **'Extra Behavioral Directives'**
  String get personaDirectivesLabel;

  /// No description provided for @personaDirectivesHint.
  ///
  /// In en, this message translates to:
  /// **'Optional: supplementary behavioral rules the persona must follow'**
  String get personaDirectivesHint;

  /// No description provided for @deleteDialoguePersonaTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Dialogue Persona?'**
  String get deleteDialoguePersonaTitle;

  /// No description provided for @deleteDialoguePersonaMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"?'**
  String deleteDialoguePersonaMessage(String name);

  /// No description provided for @deleteCharacterCardFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete character card: {error}'**
  String deleteCharacterCardFailed(String error);

  /// No description provided for @nameRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a name'**
  String get nameRequired;

  /// No description provided for @manualCreatedSource.
  ///
  /// In en, this message translates to:
  /// **'Manually created'**
  String get manualCreatedSource;

  /// No description provided for @createAction.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get createAction;

  /// No description provided for @nameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get nameLabel;

  /// No description provided for @descriptionOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Description (Optional)'**
  String get descriptionOptionalLabel;

  /// No description provided for @fontSizeAdjustment.
  ///
  /// In en, this message translates to:
  /// **'Font Size Adjustment'**
  String get fontSizeAdjustment;

  /// No description provided for @fontSizeSmallA.
  ///
  /// In en, this message translates to:
  /// **'A Small'**
  String get fontSizeSmallA;

  /// No description provided for @fontSizeLargeA.
  ///
  /// In en, this message translates to:
  /// **'A Large'**
  String get fontSizeLargeA;

  /// No description provided for @dialogueParams.
  ///
  /// In en, this message translates to:
  /// **'Dialogue Parameters'**
  String get dialogueParams;

  /// No description provided for @parameterPresets.
  ///
  /// In en, this message translates to:
  /// **'Parameter Presets'**
  String get parameterPresets;

  /// No description provided for @presetDeepThinking.
  ///
  /// In en, this message translates to:
  /// **'Deep Thinking (V4.1 Complex Deduction)'**
  String get presetDeepThinking;

  /// No description provided for @presetFastNarrative.
  ///
  /// In en, this message translates to:
  /// **'Fast Narrative (Default)'**
  String get presetFastNarrative;

  /// No description provided for @presetDeepReasoning.
  ///
  /// In en, this message translates to:
  /// **'Extreme Reasoning (Puzzle Solving)'**
  String get presetDeepReasoning;

  /// No description provided for @presetLightweightDaily.
  ///
  /// In en, this message translates to:
  /// **'Lightweight Daily (Low Latency)'**
  String get presetLightweightDaily;

  /// No description provided for @appliedPreset.
  ///
  /// In en, this message translates to:
  /// **'Applied: {preset}'**
  String appliedPreset(String preset);

  /// No description provided for @saveWorldview.
  ///
  /// In en, this message translates to:
  /// **'Save Worldview'**
  String get saveWorldview;

  /// No description provided for @worldviewInfo.
  ///
  /// In en, this message translates to:
  /// **'Worldview Information'**
  String get worldviewInfo;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @descriptionOptional.
  ///
  /// In en, this message translates to:
  /// **'Description (Optional)'**
  String get descriptionOptional;

  /// No description provided for @worldviewSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved worldview \"{name}\"'**
  String worldviewSaved(String name);

  /// No description provided for @saveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String saveFailed(String error);

  /// No description provided for @unknownError.
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get unknownError;

  /// No description provided for @importCharacterCard.
  ///
  /// In en, this message translates to:
  /// **'Import Character Card'**
  String get importCharacterCard;

  /// No description provided for @pasteCharacterCardJson.
  ///
  /// In en, this message translates to:
  /// **'Paste SillyTavern / Chub character card JSON'**
  String get pasteCharacterCardJson;

  /// No description provided for @pasteCharacterCardJsonHint.
  ///
  /// In en, this message translates to:
  /// **'Paste character card JSON content here...'**
  String get pasteCharacterCardJsonHint;

  /// No description provided for @importAction.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get importAction;

  /// No description provided for @editDialoguePersonaCard.
  ///
  /// In en, this message translates to:
  /// **'Edit Dialogue Persona Card'**
  String get editDialoguePersonaCard;

  /// No description provided for @newDialoguePersonaCard.
  ///
  /// In en, this message translates to:
  /// **'New Dialogue Persona Card'**
  String get newDialoguePersonaCard;

  /// No description provided for @dialoguePersonaSettings.
  ///
  /// In en, this message translates to:
  /// **'Dialogue Character Settings'**
  String get dialoguePersonaSettings;

  /// No description provided for @dialoguePersonaSettingsDesc.
  ///
  /// In en, this message translates to:
  /// **'Characters here are only used for dialogue mode and can completely bypass Naela.'**
  String get dialoguePersonaSettingsDesc;

  /// No description provided for @personaNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Character Name *'**
  String get personaNameRequired;

  /// No description provided for @personaRole.
  ///
  /// In en, this message translates to:
  /// **'Role & Identity'**
  String get personaRole;

  /// No description provided for @personaUserCallName.
  ///
  /// In en, this message translates to:
  /// **'How to Address User'**
  String get personaUserCallName;

  /// No description provided for @personaUserCallNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. User, Creator, Commander, Teacher'**
  String get personaUserCallNameHint;

  /// No description provided for @personaPersonality.
  ///
  /// In en, this message translates to:
  /// **'Personality & Traits'**
  String get personaPersonality;

  /// No description provided for @personaSpeakingStyle.
  ///
  /// In en, this message translates to:
  /// **'Speaking Style'**
  String get personaSpeakingStyle;

  /// No description provided for @personaBackground.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get personaBackground;

  /// No description provided for @personaScenario.
  ///
  /// In en, this message translates to:
  /// **'Dialogue Scenario'**
  String get personaScenario;

  /// No description provided for @personaScenarioHint.
  ///
  /// In en, this message translates to:
  /// **'Describe in what context the character communicates with the user'**
  String get personaScenarioHint;

  /// No description provided for @personaSystemPrompt.
  ///
  /// In en, this message translates to:
  /// **'Extra System Instructions'**
  String get personaSystemPrompt;

  /// No description provided for @personaSystemPromptHint.
  ///
  /// In en, this message translates to:
  /// **'Optional: supplementary rules the character must follow'**
  String get personaSystemPromptHint;

  /// No description provided for @deleteDialoguePersonaPrompt.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"?'**
  String deleteDialoguePersonaPrompt(String name);

  /// No description provided for @pleaseEnterPersonaName.
  ///
  /// In en, this message translates to:
  /// **'Please enter character name'**
  String get pleaseEnterPersonaName;

  /// No description provided for @manuallyCreated.
  ///
  /// In en, this message translates to:
  /// **'Manually created'**
  String get manuallyCreated;

  /// No description provided for @sidebarSystemSettings.
  ///
  /// In en, this message translates to:
  /// **'System Settings'**
  String get sidebarSystemSettings;

  /// No description provided for @settingsTabModelAndApi.
  ///
  /// In en, this message translates to:
  /// **'Models & API'**
  String get settingsTabModelAndApi;

  /// No description provided for @settingsTabModelAndApiSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Provider and key configuration'**
  String get settingsTabModelAndApiSubtitle;

  /// No description provided for @settingsTabSessionParams.
  ///
  /// In en, this message translates to:
  /// **'Session Parameters'**
  String get settingsTabSessionParams;

  /// No description provided for @settingsTabSessionParamsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sampling rate and deep thinking'**
  String get settingsTabSessionParamsSubtitle;

  /// No description provided for @settingsTabAppearance.
  ///
  /// In en, this message translates to:
  /// **'Theme & Palette'**
  String get settingsTabAppearance;

  /// No description provided for @settingsTabAppearanceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Light/dark and color accents'**
  String get settingsTabAppearanceSubtitle;

  /// No description provided for @settingsTabStorage.
  ///
  /// In en, this message translates to:
  /// **'Data Management'**
  String get settingsTabStorage;

  /// No description provided for @settingsTabStorageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Token statistics and storage'**
  String get settingsTabStorageSubtitle;

  /// No description provided for @settingsCustomProvider.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get settingsCustomProvider;

  /// No description provided for @settingsReturnToLobby.
  ///
  /// In en, this message translates to:
  /// **'Return to Lobby'**
  String get settingsReturnToLobby;

  /// No description provided for @settingsReturnToSettingsList.
  ///
  /// In en, this message translates to:
  /// **'Return to Settings'**
  String get settingsReturnToSettingsList;

  /// No description provided for @settingsConfigsCategory.
  ///
  /// In en, this message translates to:
  /// **'Configuration Categories'**
  String get settingsConfigsCategory;

  /// No description provided for @settingsOfficialInService.
  ///
  /// In en, this message translates to:
  /// **'{provider} Official Active'**
  String settingsOfficialInService(String provider);

  /// No description provided for @settingsKeyNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Key Not Configured'**
  String get settingsKeyNotConfigured;

  /// No description provided for @settingsLlmConnected.
  ///
  /// In en, this message translates to:
  /// **'LLM Service Connected'**
  String get settingsLlmConnected;

  /// No description provided for @settingsLlmDisconnected.
  ///
  /// In en, this message translates to:
  /// **'API Key Not Configured'**
  String get settingsLlmDisconnected;

  /// No description provided for @settingsLlmConnectedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Click to manage provider, models, and endpoints'**
  String get settingsLlmConnectedSubtitle;

  /// No description provided for @settingsLlmDisconnectedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Click to configure API key to start reasoning'**
  String get settingsLlmDisconnectedSubtitle;

  /// No description provided for @settingsEngineTitle.
  ///
  /// In en, this message translates to:
  /// **'LT Core Engine'**
  String get settingsEngineTitle;

  /// No description provided for @settingsEngineSubtitle.
  ///
  /// In en, this message translates to:
  /// **'SQLite · Local Encryption First'**
  String get settingsEngineSubtitle;

  /// No description provided for @settingsSystemConfigBadge.
  ///
  /// In en, this message translates to:
  /// **'System Config'**
  String get settingsSystemConfigBadge;

  /// No description provided for @inferenceParamsTitle.
  ///
  /// In en, this message translates to:
  /// **'Inference & Sampling Parameters'**
  String get inferenceParamsTitle;

  /// No description provided for @inferenceParamsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Adjust temperature, sampling thresholds, and deep thinking intensity'**
  String get inferenceParamsSubtitle;

  /// No description provided for @deepseekThinkingHint.
  ///
  /// In en, this message translates to:
  /// **'💡 Note: In DeepSeek V4.1 thinking mode, sampling is managed adaptively by the model. In non-thinking mode, top_p is fixed at 1.0 and only temperature is adjustable.'**
  String get deepseekThinkingHint;

  /// No description provided for @temperatureTitle.
  ///
  /// In en, this message translates to:
  /// **'Generation Temperature'**
  String get temperatureTitle;

  /// No description provided for @temperatureDescription.
  ///
  /// In en, this message translates to:
  /// **'0.0 Strict & Precise ↔ 2.0 Highly Creative & Diverse'**
  String get temperatureDescription;

  /// No description provided for @topPTitle.
  ///
  /// In en, this message translates to:
  /// **'Nucleus Sampling (Top-P)'**
  String get topPTitle;

  /// No description provided for @topPDescription.
  ///
  /// In en, this message translates to:
  /// **'Cumulative probability cutoff; recommended 0.90 ~ 0.95'**
  String get topPDescription;

  /// No description provided for @maxTokensTitle.
  ///
  /// In en, this message translates to:
  /// **'Max Generation Length (Max Tokens)'**
  String get maxTokensTitle;

  /// No description provided for @maxTokensDescription.
  ///
  /// In en, this message translates to:
  /// **'Maximum token budget per turn'**
  String get maxTokensDescription;

  /// No description provided for @paramsRealtimeNotice.
  ///
  /// In en, this message translates to:
  /// **'Note: Parameter changes take effect immediately without saving.'**
  String get paramsRealtimeNotice;

  /// No description provided for @testConnectionSuccess.
  ///
  /// In en, this message translates to:
  /// **'Connection successful! ({elapsed}ms), service status excellent.'**
  String testConnectionSuccess(int elapsed);

  /// No description provided for @testConnectionFailure.
  ///
  /// In en, this message translates to:
  /// **'Connection failed. Please verify your API key and network connection.'**
  String get testConnectionFailure;

  /// No description provided for @testConnectionFailureDetail.
  ///
  /// In en, this message translates to:
  /// **'Connection failed: {error}'**
  String testConnectionFailureDetail(String error);

  /// No description provided for @statusReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get statusReady;

  /// No description provided for @statusNotReady.
  ///
  /// In en, this message translates to:
  /// **'Not Ready'**
  String get statusNotReady;

  /// No description provided for @modelEndpointSummary.
  ///
  /// In en, this message translates to:
  /// **'Model: {model} · Endpoint: {endpoint}'**
  String modelEndpointSummary(String model, String endpoint);

  /// No description provided for @quickTesting.
  ///
  /// In en, this message translates to:
  /// **'Testing...'**
  String get quickTesting;

  /// No description provided for @quickTest.
  ///
  /// In en, this message translates to:
  /// **'Quick Test'**
  String get quickTest;

  /// No description provided for @llmProviderSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'LLM Service Provider'**
  String get llmProviderSectionTitle;

  /// No description provided for @llmProviderSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select and configure language model services for dialogue and reasoning'**
  String get llmProviderSectionSubtitle;

  /// No description provided for @modelProviderLabel.
  ///
  /// In en, this message translates to:
  /// **'Model Provider'**
  String get modelProviderLabel;

  /// No description provided for @selectInServiceModal.
  ///
  /// In en, this message translates to:
  /// **'Select Active Model'**
  String get selectInServiceModal;

  /// No description provided for @customModelNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Custom Model Name'**
  String get customModelNameLabel;

  /// No description provided for @customModelNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. gpt-4o, llama-3.3-70b, qwen-max'**
  String get customModelNameHint;

  /// No description provided for @apiEndpointLabel.
  ///
  /// In en, this message translates to:
  /// **'API Endpoint (Base URL)'**
  String get apiEndpointLabel;

  /// No description provided for @apiSecurityNotice.
  ///
  /// In en, this message translates to:
  /// **'Key is encrypted and stored locally in SQLite; never relayed via intermediate servers'**
  String get apiSecurityNotice;

  /// No description provided for @promptSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Prompts & Deduction Planning'**
  String get promptSettingsTitle;

  /// No description provided for @importPresets.
  ///
  /// In en, this message translates to:
  /// **'Import Presets'**
  String get importPresets;

  /// No description provided for @exportPresets.
  ///
  /// In en, this message translates to:
  /// **'Export Presets'**
  String get exportPresets;

  /// No description provided for @previewPromptAction.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get previewPromptAction;

  /// No description provided for @importPresetTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Prompt Presets'**
  String get importPresetTitle;

  /// No description provided for @exportPresetTitle.
  ///
  /// In en, this message translates to:
  /// **'Export Prompt Presets'**
  String get exportPresetTitle;

  /// No description provided for @presetJsonLabel.
  ///
  /// In en, this message translates to:
  /// **'Prompt Preset JSON'**
  String get presetJsonLabel;

  /// No description provided for @presetJsonEmptyError.
  ///
  /// In en, this message translates to:
  /// **'Please enter preset JSON'**
  String get presetJsonEmptyError;

  /// No description provided for @presetImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String presetImportFailed(String error);

  /// No description provided for @presetJsonCopied.
  ///
  /// In en, this message translates to:
  /// **'Prompt preset JSON copied'**
  String get presetJsonCopied;

  /// No description provided for @copyAllAction.
  ///
  /// In en, this message translates to:
  /// **'Copy All'**
  String get copyAllAction;

  /// No description provided for @dialogueLevelSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Dialogue Level'**
  String get dialogueLevelSectionTitle;

  /// No description provided for @dialogueLevelSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select output word budget and descriptive detail density per turn'**
  String get dialogueLevelSectionSubtitle;

  /// No description provided for @systemPromptSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'System Prompt'**
  String get systemPromptSectionTitle;

  /// No description provided for @systemPromptSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Clean baseline. Defaults to minimal universal deduction guidelines if left blank.'**
  String get systemPromptSectionSubtitle;

  /// No description provided for @systemPromptHint.
  ///
  /// In en, this message translates to:
  /// **'Enter custom system instructions, world rules, or character guidelines (leave empty for defaults)...'**
  String get systemPromptHint;

  /// No description provided for @charCountLabel.
  ///
  /// In en, this message translates to:
  /// **'{count} characters written'**
  String charCountLabel(int count);

  /// No description provided for @clearAction.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearAction;

  /// No description provided for @systemPromptSaved.
  ///
  /// In en, this message translates to:
  /// **'Global system prompt saved'**
  String get systemPromptSaved;

  /// No description provided for @savePromptAction.
  ///
  /// In en, this message translates to:
  /// **'Save Prompt'**
  String get savePromptAction;

  /// No description provided for @authorsNoteSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Author\'\'s Note'**
  String get authorsNoteSectionTitle;

  /// No description provided for @authorsNoteSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Inject high-weight directives at specified turn depths in the session context.'**
  String get authorsNoteSectionSubtitle;

  /// No description provided for @authorsNoteHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Focus on detailed protagonist actions, maintain an atmosphere of suspense...'**
  String get authorsNoteHint;

  /// No description provided for @injectionDepth.
  ///
  /// In en, this message translates to:
  /// **'Injection Depth'**
  String get injectionDepth;

  /// No description provided for @depthFollowSystem.
  ///
  /// In en, this message translates to:
  /// **'Directly after system prompt'**
  String get depthFollowSystem;

  /// No description provided for @depthBeforeRound.
  ///
  /// In en, this message translates to:
  /// **'{depth} turns from bottom'**
  String depthBeforeRound(int depth);

  /// No description provided for @injectionFrequency.
  ///
  /// In en, this message translates to:
  /// **'Injection Frequency'**
  String get injectionFrequency;

  /// No description provided for @freqEveryRound.
  ///
  /// In en, this message translates to:
  /// **'Every {freq} turns'**
  String freqEveryRound(int freq);

  /// No description provided for @authorsNoteSaved.
  ///
  /// In en, this message translates to:
  /// **'Author\'\'s note settings saved'**
  String get authorsNoteSaved;

  /// No description provided for @saveNoteConfigAction.
  ///
  /// In en, this message translates to:
  /// **'Save Note Config'**
  String get saveNoteConfigAction;

  /// No description provided for @promptPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Real-time Prompt Assembly Preview'**
  String get promptPreviewTitle;

  /// No description provided for @copyFullPrompt.
  ///
  /// In en, this message translates to:
  /// **'Copy Full Prompt'**
  String get copyFullPrompt;

  /// No description provided for @fullPromptCopied.
  ///
  /// In en, this message translates to:
  /// **'Full assembled prompt copied to clipboard'**
  String get fullPromptCopied;

  /// No description provided for @promptPreviewStats.
  ///
  /// In en, this message translates to:
  /// **'~{chars} chars · estimated {tokens} tokens'**
  String promptPreviewStats(int chars, int tokens);

  /// No description provided for @resourceTypeWorldview.
  ///
  /// In en, this message translates to:
  /// **'Worldview'**
  String get resourceTypeWorldview;

  /// No description provided for @resourceTypeCharacter.
  ///
  /// In en, this message translates to:
  /// **'Character'**
  String get resourceTypeCharacter;

  /// No description provided for @resourceTypeNpc.
  ///
  /// In en, this message translates to:
  /// **'NPC'**
  String get resourceTypeNpc;

  /// No description provided for @resourceStatusGenerating.
  ///
  /// In en, this message translates to:
  /// **'Generating'**
  String get resourceStatusGenerating;

  /// No description provided for @resourceStatusSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get resourceStatusSaved;

  /// No description provided for @resourceStatusOptimizationSuggested.
  ///
  /// In en, this message translates to:
  /// **'Optimization Suggested'**
  String get resourceStatusOptimizationSuggested;

  /// No description provided for @resourceStatusOptimizing.
  ///
  /// In en, this message translates to:
  /// **'Optimizing'**
  String get resourceStatusOptimizing;

  /// No description provided for @resourceStatusReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get resourceStatusReady;

  /// No description provided for @resourceStatusOptimizationFailed.
  ///
  /// In en, this message translates to:
  /// **'Optimization Failed'**
  String get resourceStatusOptimizationFailed;

  /// No description provided for @resourceUnknownTime.
  ///
  /// In en, this message translates to:
  /// **'Unknown Time'**
  String get resourceUnknownTime;

  /// No description provided for @resourceCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Resource'**
  String get resourceCreateTitle;

  /// No description provided for @resourceTypeSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Resource Type'**
  String get resourceTypeSectionTitle;

  /// No description provided for @resourceTypeSectionDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose the type of content carrier to build'**
  String get resourceTypeSectionDescription;

  /// No description provided for @resourcePreselectedType.
  ///
  /// In en, this message translates to:
  /// **'Selected Type'**
  String get resourcePreselectedType;

  /// No description provided for @resourceCreationMethodSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Creation Method'**
  String get resourceCreationMethodSectionTitle;

  /// No description provided for @resourceCreationMethodSectionDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose between AI-assisted derivation or manual text drafting based on your creative needs'**
  String get resourceCreationMethodSectionDescription;

  /// No description provided for @resourceAiCreationTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Creation'**
  String get resourceAiCreationTitle;

  /// No description provided for @resourceAiCreationDescription.
  ///
  /// In en, this message translates to:
  /// **'Automatically derive chapter outlines and body content from reference materials, fiction text, or existing assets using AI.'**
  String get resourceAiCreationDescription;

  /// No description provided for @resourceRecommendBadge.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get resourceRecommendBadge;

  /// No description provided for @resourceManualCreationTitle.
  ///
  /// In en, this message translates to:
  /// **'Manual Creation'**
  String get resourceManualCreationTitle;

  /// No description provided for @resourceManualCreationDescription.
  ///
  /// In en, this message translates to:
  /// **'Set custom name and summary, create a blank resource, and freely organize chapters and content.'**
  String get resourceManualCreationDescription;

  /// No description provided for @resourceManualCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Resource Manually'**
  String get resourceManualCreateTitle;

  /// No description provided for @resourceBasicInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Basic Information'**
  String get resourceBasicInfoTitle;

  /// No description provided for @resourceManualBasicInfoDescription.
  ///
  /// In en, this message translates to:
  /// **'Fill in the type, name, and brief introduction of the resource. After creation, you can freely edit the text in Studio.'**
  String get resourceManualBasicInfoDescription;

  /// No description provided for @resourceNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get resourceNameLabel;

  /// No description provided for @resourceManualNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a clear and distinct name'**
  String get resourceManualNameHint;

  /// No description provided for @resourceSummaryOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Summary (Optional)'**
  String get resourceSummaryOptionalLabel;

  /// No description provided for @resourceManualSummaryHint.
  ///
  /// In en, this message translates to:
  /// **'Briefly describe the role and background setting of the resource'**
  String get resourceManualSummaryHint;

  /// No description provided for @resourceCreateAction.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get resourceCreateAction;

  /// No description provided for @resourceInputNameError.
  ///
  /// In en, this message translates to:
  /// **'Please enter a resource name'**
  String get resourceInputNameError;

  /// No description provided for @resourceAiCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Resource Creation'**
  String get resourceAiCreateTitle;

  /// No description provided for @resourceAiBasicInfoDescription.
  ///
  /// In en, this message translates to:
  /// **'Define the carrier type and title of the resource to be generated'**
  String get resourceAiBasicInfoDescription;

  /// No description provided for @resourceAiNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the setting or character name to be generated'**
  String get resourceAiNameHint;

  /// No description provided for @resourceAssociateWorldviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Associate Worldview (Optional)'**
  String get resourceAssociateWorldviewTitle;

  /// No description provided for @resourceAssociateWorldviewDescription.
  ///
  /// In en, this message translates to:
  /// **'Specify the native worldview for the character or NPC as supplemental context during generation'**
  String get resourceAssociateWorldviewDescription;

  /// No description provided for @resourceNoAvailableWorldview.
  ///
  /// In en, this message translates to:
  /// **'No worldview available to associate'**
  String get resourceNoAvailableWorldview;

  /// No description provided for @resourceNotSpecified.
  ///
  /// In en, this message translates to:
  /// **'Not specified'**
  String get resourceNotSpecified;

  /// No description provided for @resourceReferenceSourceTitle.
  ///
  /// In en, this message translates to:
  /// **'Reference Material Source'**
  String get resourceReferenceSourceTitle;

  /// No description provided for @resourceReferenceSourceDescription.
  ///
  /// In en, this message translates to:
  /// **'Provide worldview background, novel settings, or associated resources; AI will extract the essence and derive the chapter structure'**
  String get resourceReferenceSourceDescription;

  /// No description provided for @resourceTabPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get resourceTabPaste;

  /// No description provided for @resourceTabFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get resourceTabFile;

  /// No description provided for @resourceTabExistingResource.
  ///
  /// In en, this message translates to:
  /// **'Existing Resource'**
  String get resourceTabExistingResource;

  /// No description provided for @resourcePasteReferenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Paste Reference Content'**
  String get resourcePasteReferenceLabel;

  /// No description provided for @resourcePasteReferenceHint.
  ///
  /// In en, this message translates to:
  /// **'Enter or paste novel outlines, setting drafts, or background descriptions...'**
  String get resourcePasteReferenceHint;

  /// No description provided for @resourceFileNameLabel.
  ///
  /// In en, this message translates to:
  /// **'File Name'**
  String get resourceFileNameLabel;

  /// No description provided for @resourceFileNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. world_notes.md'**
  String get resourceFileNameHint;

  /// No description provided for @resourceFileContentLabel.
  ///
  /// In en, this message translates to:
  /// **'File Text Content'**
  String get resourceFileContentLabel;

  /// No description provided for @resourceFileContentHint.
  ///
  /// In en, this message translates to:
  /// **'Paste or enter raw text from within the file...'**
  String get resourceFileContentHint;

  /// No description provided for @resourceNoExistingInLibrary.
  ///
  /// In en, this message translates to:
  /// **'No ready resources available to associate in the library. Please switch to \'Paste\' or \'File\' input.'**
  String get resourceNoExistingInLibrary;

  /// No description provided for @resourceSelectExistingLabel.
  ///
  /// In en, this message translates to:
  /// **'Select Existing Resource'**
  String get resourceSelectExistingLabel;

  /// No description provided for @resourceSelectExistingHint.
  ///
  /// In en, this message translates to:
  /// **'Click to select a reference existing resource'**
  String get resourceSelectExistingHint;

  /// No description provided for @resourceGenerationLengthTitle.
  ///
  /// In en, this message translates to:
  /// **'Generation Length'**
  String get resourceGenerationLengthTitle;

  /// No description provided for @resourceGenerationLengthDescription.
  ///
  /// In en, this message translates to:
  /// **'Control the approximate target word count of the AI generated resource text'**
  String get resourceGenerationLengthDescription;

  /// No description provided for @resourceTargetCharactersLabel.
  ///
  /// In en, this message translates to:
  /// **'Target Word Count'**
  String get resourceTargetCharactersLabel;

  /// No description provided for @resourceTargetCharactersValue.
  ///
  /// In en, this message translates to:
  /// **'{count} chars'**
  String resourceTargetCharactersValue(Object count);

  /// No description provided for @resourceLengthShort.
  ///
  /// In en, this message translates to:
  /// **'Short'**
  String get resourceLengthShort;

  /// No description provided for @resourceLengthLong.
  ///
  /// In en, this message translates to:
  /// **'Long'**
  String get resourceLengthLong;

  /// No description provided for @resourceStartCreateAction.
  ///
  /// In en, this message translates to:
  /// **'Start Creation'**
  String get resourceStartCreateAction;

  /// No description provided for @resourceInputOrPasteReferenceError.
  ///
  /// In en, this message translates to:
  /// **'Please enter or paste reference material text'**
  String get resourceInputOrPasteReferenceError;

  /// No description provided for @resourceInputFileNameError.
  ///
  /// In en, this message translates to:
  /// **'Please enter a file name'**
  String get resourceInputFileNameError;

  /// No description provided for @resourceInputFileContentError.
  ///
  /// In en, this message translates to:
  /// **'Please enter file content'**
  String get resourceInputFileContentError;

  /// No description provided for @resourceSelectExistingError.
  ///
  /// In en, this message translates to:
  /// **'Please select an existing resource as reference'**
  String get resourceSelectExistingError;

  /// No description provided for @resourcePastedContentLabel.
  ///
  /// In en, this message translates to:
  /// **'Pasted Content'**
  String get resourcePastedContentLabel;

  /// No description provided for @resourceLoadFailedRetry.
  ///
  /// In en, this message translates to:
  /// **'Failed to load resource library. Please try again.'**
  String get resourceLoadFailedRetry;

  /// No description provided for @resourceCreationFailedRetry.
  ///
  /// In en, this message translates to:
  /// **'Failed to create resource. Please try again.'**
  String get resourceCreationFailedRetry;

  /// No description provided for @resourceUnnamed.
  ///
  /// In en, this message translates to:
  /// **'Unnamed Resource'**
  String get resourceUnnamed;

  /// No description provided for @resourceRevisionResourceKind.
  ///
  /// In en, this message translates to:
  /// **'Resource'**
  String get resourceRevisionResourceKind;

  /// No description provided for @resourceRevisionSectionKind.
  ///
  /// In en, this message translates to:
  /// **'Section'**
  String get resourceRevisionSectionKind;

  /// No description provided for @resourceRevisionPartKind.
  ///
  /// In en, this message translates to:
  /// **'Paragraph'**
  String get resourceRevisionPartKind;

  /// No description provided for @resourceTrashSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{kind} · {reason} · Deleted at {deletedAt} · Kept until {expiresAt}'**
  String resourceTrashSubtitle(
      Object deletedAt, Object expiresAt, Object kind, Object reason);

  /// No description provided for @resourceTrashRestoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Restore failed: {error}'**
  String resourceTrashRestoreFailed(Object error);

  /// No description provided for @resourceTrashPermanentDeleteSuccess.
  ///
  /// In en, this message translates to:
  /// **'Permanently deleted'**
  String get resourceTrashPermanentDeleteSuccess;

  /// No description provided for @resourceTrashPermanentDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Permanent delete failed: {error}'**
  String resourceTrashPermanentDeleteFailed(Object error);

  /// No description provided for @modeTitleConversation.
  ///
  /// In en, this message translates to:
  /// **'Conversation Library'**
  String get modeTitleConversation;

  /// No description provided for @modeTitleAdventure.
  ///
  /// In en, this message translates to:
  /// **'Scenario Library'**
  String get modeTitleAdventure;

  /// No description provided for @modeTitleCreation.
  ///
  /// In en, this message translates to:
  /// **'Creation Library'**
  String get modeTitleCreation;

  /// No description provided for @modeEmptyTitleConversation.
  ///
  /// In en, this message translates to:
  /// **'No conversation character cards'**
  String get modeEmptyTitleConversation;

  /// No description provided for @modeEmptyTitleAdventure.
  ///
  /// In en, this message translates to:
  /// **'No scenario resources'**
  String get modeEmptyTitleAdventure;

  /// No description provided for @modeEmptyTitleCreation.
  ///
  /// In en, this message translates to:
  /// **'No creation resources'**
  String get modeEmptyTitleCreation;

  /// No description provided for @modeEmptySubtitleConversation.
  ///
  /// In en, this message translates to:
  /// **'Create custom character cards or view past chat history.'**
  String get modeEmptySubtitleConversation;

  /// No description provided for @modeEmptySubtitleAdventure.
  ///
  /// In en, this message translates to:
  /// **'Import characters, locations, rules, or plot resources for scenario dialogue.'**
  String get modeEmptySubtitleAdventure;

  /// No description provided for @modeEmptySubtitleCreation.
  ///
  /// In en, this message translates to:
  /// **'Import worldviews, character settings, chapter references, or writing materials for creation mode.'**
  String get modeEmptySubtitleCreation;

  /// No description provided for @resourceStudioRefreshTooltip.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get resourceStudioRefreshTooltip;

  /// No description provided for @resourceStudioTocTitle.
  ///
  /// In en, this message translates to:
  /// **'Table of Contents'**
  String get resourceStudioTocTitle;

  /// No description provided for @resourceStudioNoContent.
  ///
  /// In en, this message translates to:
  /// **'Current resource has no content to display.'**
  String get resourceStudioNoContent;

  /// No description provided for @resourceStudioReadAloudAll.
  ///
  /// In en, this message translates to:
  /// **'Read Aloud Full Text'**
  String get resourceStudioReadAloudAll;

  /// No description provided for @resourceStudioEditPart.
  ///
  /// In en, this message translates to:
  /// **'Edit Text'**
  String get resourceStudioEditPart;

  /// No description provided for @resourceStudioDeletePart.
  ///
  /// In en, this message translates to:
  /// **'Delete Paragraph'**
  String get resourceStudioDeletePart;

  /// No description provided for @resourceStudioPartNotExistCannotEdit.
  ///
  /// In en, this message translates to:
  /// **'This paragraph no longer exists and cannot be edited'**
  String get resourceStudioPartNotExistCannotEdit;

  /// No description provided for @resourceStudioPublishCompressionTitle.
  ///
  /// In en, this message translates to:
  /// **'Publish Compression Results'**
  String get resourceStudioPublishCompressionTitle;

  /// No description provided for @resourceStudioPublishCompressionMessage.
  ///
  /// In en, this message translates to:
  /// **'The compressed text will replace current content. The original text will be recorded as a historical revision and can be restored at any time.\nAre you sure you want to publish?'**
  String get resourceStudioPublishCompressionMessage;

  /// No description provided for @resourceStudioPublishCompressionAction.
  ///
  /// In en, this message translates to:
  /// **'Publish'**
  String get resourceStudioPublishCompressionAction;

  /// No description provided for @resourceStudioRestoreRevisionTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore Historical Revision'**
  String get resourceStudioRestoreRevisionTitle;

  /// No description provided for @resourceStudioRestoreRevisionMessage.
  ///
  /// In en, this message translates to:
  /// **'Current content will be replaced by this historical revision. The content before replacement will also be kept in version history.\nAre you sure you want to restore?'**
  String get resourceStudioRestoreRevisionMessage;

  /// No description provided for @resourceStudioRestoreRevisionAction.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get resourceStudioRestoreRevisionAction;

  /// No description provided for @resourceStudioDeletePartTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Paragraph'**
  String get resourceStudioDeletePartTitle;

  /// No description provided for @resourceStudioDeletePartMessage.
  ///
  /// In en, this message translates to:
  /// **'“{title}” will be moved to Recycle Bin and can be restored from Recycle Bin.\nAre you sure you want to delete?'**
  String resourceStudioDeletePartMessage(Object title);

  /// No description provided for @resourceStudioDeletePartAction.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get resourceStudioDeletePartAction;

  /// No description provided for @resourceStudioPartNotExistCannotDelete.
  ///
  /// In en, this message translates to:
  /// **'This paragraph no longer exists and cannot be deleted'**
  String get resourceStudioPartNotExistCannotDelete;

  /// No description provided for @resourceStudioMovedToTrash.
  ///
  /// In en, this message translates to:
  /// **'Moved to Recycle Bin. You can restore it from Recycle Bin'**
  String get resourceStudioMovedToTrash;

  /// No description provided for @resourceStudioDeletePartFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete paragraph: {error}'**
  String resourceStudioDeletePartFailed(Object error);

  /// No description provided for @resourceStudioContinueGenerating.
  ///
  /// In en, this message translates to:
  /// **'Continue Generation'**
  String get resourceStudioContinueGenerating;

  /// No description provided for @resourceStudioPauseGenerating.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get resourceStudioPauseGenerating;

  /// No description provided for @resourceStudioCancelGenerating.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get resourceStudioCancelGenerating;

  /// No description provided for @resourceStudioRetryGenerating.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get resourceStudioRetryGenerating;

  /// No description provided for @resourceStudioCreatingAndStarting.
  ///
  /// In en, this message translates to:
  /// **'Creating resource and starting generation'**
  String get resourceStudioCreatingAndStarting;

  /// No description provided for @resourceStudioTargetCharacters.
  ///
  /// In en, this message translates to:
  /// **'Target approx. {count} chars'**
  String resourceStudioTargetCharacters(Object count);

  /// No description provided for @resourceStudioCreationFailed.
  ///
  /// In en, this message translates to:
  /// **'Resource creation failed'**
  String get resourceStudioCreationFailed;

  /// No description provided for @resourceStudioPleaseRetryLater.
  ///
  /// In en, this message translates to:
  /// **'Please try again later'**
  String get resourceStudioPleaseRetryLater;

  /// No description provided for @resourceStudioRetryCreation.
  ///
  /// In en, this message translates to:
  /// **'Retry Creation'**
  String get resourceStudioRetryCreation;

  /// No description provided for @resourceStudioSelectResourceOrSession.
  ///
  /// In en, this message translates to:
  /// **'Select Resource or Generation Session'**
  String get resourceStudioSelectResourceOrSession;

  /// No description provided for @resourceStudioSelectSession.
  ///
  /// In en, this message translates to:
  /// **'Select Generation Session'**
  String get resourceStudioSelectSession;

  /// No description provided for @resourceStudioCreateAndStart.
  ///
  /// In en, this message translates to:
  /// **'Create and Start Generation'**
  String get resourceStudioCreateAndStart;

  /// No description provided for @resourceStudioPendingAiPlan.
  ///
  /// In en, this message translates to:
  /// **'Pending AI Plan'**
  String get resourceStudioPendingAiPlan;

  /// No description provided for @resourceStudioConfirmAndStart.
  ///
  /// In en, this message translates to:
  /// **'Confirm and start generation'**
  String get resourceStudioConfirmAndStart;

  /// No description provided for @resourceStudioUnfinishedTask.
  ///
  /// In en, this message translates to:
  /// **'Unfinished Generation Task {index}'**
  String resourceStudioUnfinishedTask(Object index);

  /// No description provided for @resourceStudioGeneratingStatus.
  ///
  /// In en, this message translates to:
  /// **'Generating'**
  String get resourceStudioGeneratingStatus;

  /// No description provided for @resourceStudioResourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Resource'**
  String get resourceStudioResourceLabel;

  /// No description provided for @resourceStudioNoResourceOrSession.
  ///
  /// In en, this message translates to:
  /// **'No resources or recoverable generation sessions.'**
  String get resourceStudioNoResourceOrSession;

  /// No description provided for @resourceStudioAddSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Section'**
  String get resourceStudioAddSectionTitle;

  /// No description provided for @resourceStudioSectionTitleField.
  ///
  /// In en, this message translates to:
  /// **'Section Title'**
  String get resourceStudioSectionTitleField;

  /// No description provided for @sectionControlsTitle.
  ///
  /// In en, this message translates to:
  /// **'Section Controls'**
  String get sectionControlsTitle;

  /// No description provided for @sectionControlsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} sections'**
  String sectionControlsCount(Object count);

  /// No description provided for @sectionControlsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add Section'**
  String get sectionControlsAdd;

  /// No description provided for @sectionControlsEmpty.
  ///
  /// In en, this message translates to:
  /// **'This resource has no sections yet.'**
  String get sectionControlsEmpty;

  /// No description provided for @sectionControlsLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more (showing {shown}/{total})'**
  String sectionControlsLoadMore(Object shown, Object total);

  /// No description provided for @sectionControlsUnnamed.
  ///
  /// In en, this message translates to:
  /// **'(Unnamed Section)'**
  String get sectionControlsUnnamed;

  /// No description provided for @sectionControlsOrderIndex.
  ///
  /// In en, this message translates to:
  /// **'No. {index}'**
  String sectionControlsOrderIndex(Object index);

  /// No description provided for @sectionControlsUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated {time}'**
  String sectionControlsUpdated(Object time);

  /// No description provided for @sectionControlsValidate.
  ///
  /// In en, this message translates to:
  /// **'Validate'**
  String get sectionControlsValidate;

  /// No description provided for @sectionControlsMoreActions.
  ///
  /// In en, this message translates to:
  /// **'More Actions'**
  String get sectionControlsMoreActions;

  /// No description provided for @sectionControlsRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get sectionControlsRename;

  /// No description provided for @sectionControlsMoveUp.
  ///
  /// In en, this message translates to:
  /// **'Move Up'**
  String get sectionControlsMoveUp;

  /// No description provided for @sectionControlsMoveDown.
  ///
  /// In en, this message translates to:
  /// **'Move Down'**
  String get sectionControlsMoveDown;

  /// No description provided for @sectionControlsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get sectionControlsDelete;

  /// No description provided for @sectionControlsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Section'**
  String get sectionControlsDeleteTitle;

  /// No description provided for @sectionControlsDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete “{title}” and all its contents?'**
  String sectionControlsDeleteMessage(Object title);

  /// No description provided for @sectionControlsGenerate.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get sectionControlsGenerate;

  /// No description provided for @sectionControlsRegenerate.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get sectionControlsRegenerate;

  /// No description provided for @sectionControlsNoTasksTooltip.
  ///
  /// In en, this message translates to:
  /// **'This section has no generation task (not created from AI blueprint) and cannot be generated'**
  String get sectionControlsNoTasksTooltip;

  /// No description provided for @sectionControlsRegenerateTooltip.
  ///
  /// In en, this message translates to:
  /// **'Rerun the generation task for this section; current content will be saved as history and can be restored at any time'**
  String get sectionControlsRegenerateTooltip;

  /// No description provided for @sectionControlsRerunTooltip.
  ///
  /// In en, this message translates to:
  /// **'Rerun the generation task for this section'**
  String get sectionControlsRerunTooltip;

  /// No description provided for @sectionControlsRenameDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename Section'**
  String get sectionControlsRenameDialogTitle;

  /// No description provided for @partEditorUnsavedDraftFound.
  ///
  /// In en, this message translates to:
  /// **'Unsaved Draft Found'**
  String get partEditorUnsavedDraftFound;

  /// No description provided for @partEditorUnsavedDraftDesc.
  ///
  /// In en, this message translates to:
  /// **'Last edits were not saved to text. You can load draft to continue editing or discard it.'**
  String get partEditorUnsavedDraftDesc;

  /// No description provided for @partEditorLoadDraft.
  ///
  /// In en, this message translates to:
  /// **'Load Draft'**
  String get partEditorLoadDraft;

  /// No description provided for @partEditorDiscardDraft.
  ///
  /// In en, this message translates to:
  /// **'Discard Draft'**
  String get partEditorDiscardDraft;

  /// No description provided for @partEditorConflictDetected.
  ///
  /// In en, this message translates to:
  /// **'Content Conflict Detected'**
  String get partEditorConflictDetected;

  /// No description provided for @partEditorConflictDesc.
  ///
  /// In en, this message translates to:
  /// **'Another operation (such as generation or restore) modified this paragraph. Autosave paused, your text is still in draft. Please choose which version to keep:'**
  String get partEditorConflictDesc;

  /// No description provided for @partEditorUseMyText.
  ///
  /// In en, this message translates to:
  /// **'Use My Text'**
  String get partEditorUseMyText;

  /// No description provided for @partEditorDiscardMyText.
  ///
  /// In en, this message translates to:
  /// **'Discard My Text'**
  String get partEditorDiscardMyText;

  /// No description provided for @partEditorHint.
  ///
  /// In en, this message translates to:
  /// **'Edit text here, autosaves when typing pauses'**
  String get partEditorHint;

  /// No description provided for @partEditorSaveNow.
  ///
  /// In en, this message translates to:
  /// **'Save Now'**
  String get partEditorSaveNow;

  /// No description provided for @partEditorFinishEditing.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get partEditorFinishEditing;

  /// No description provided for @partEditorDraftLoaded.
  ///
  /// In en, this message translates to:
  /// **'Draft loaded, will save to text on save'**
  String get partEditorDraftLoaded;

  /// No description provided for @partEditorDraftDiscarded.
  ///
  /// In en, this message translates to:
  /// **'Draft discarded'**
  String get partEditorDraftDiscarded;

  /// No description provided for @partEditorEditing.
  ///
  /// In en, this message translates to:
  /// **'Editing…'**
  String get partEditorEditing;

  /// No description provided for @partEditorConflictOtherSaved.
  ///
  /// In en, this message translates to:
  /// **'Save conflict: another operation modified this paragraph, please choose which version to keep'**
  String get partEditorConflictOtherSaved;

  /// No description provided for @partEditorConflictDraftRetained.
  ///
  /// In en, this message translates to:
  /// **'Save conflict: content retained in draft without overwriting newer version'**
  String get partEditorConflictDraftRetained;

  /// No description provided for @partEditorAutoSaved.
  ///
  /// In en, this message translates to:
  /// **'Autosaved ({label})'**
  String partEditorAutoSaved(Object label);

  /// No description provided for @partEditorTargetPartMissing.
  ///
  /// In en, this message translates to:
  /// **'Target content no longer exists, draft discarded'**
  String get partEditorTargetPartMissing;

  /// No description provided for @partEditorKeptMyTextAndSaved.
  ///
  /// In en, this message translates to:
  /// **'Kept my text and saved'**
  String get partEditorKeptMyTextAndSaved;

  /// No description provided for @partEditorConflictStillUnresolved.
  ///
  /// In en, this message translates to:
  /// **'Conflict still unresolved: paragraph was modified again, please re-select'**
  String get partEditorConflictStillUnresolved;

  /// No description provided for @partEditorResolveConflictFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to resolve conflict: {error}'**
  String partEditorResolveConflictFailed(Object error);

  /// No description provided for @partEditorSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving ({label})…'**
  String partEditorSaving(Object label);

  /// No description provided for @capacityPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Capacity'**
  String get capacityPanelTitle;

  /// No description provided for @capacityLatestFailureReason.
  ///
  /// In en, this message translates to:
  /// **'Latest compression failure reason: {reason}'**
  String capacityLatestFailureReason(Object reason);

  /// No description provided for @capacityRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh Capacity'**
  String get capacityRefresh;

  /// No description provided for @capacityCompressing.
  ///
  /// In en, this message translates to:
  /// **'Compressing'**
  String get capacityCompressing;

  /// No description provided for @capacityGenerateCandidates.
  ///
  /// In en, this message translates to:
  /// **'Generate Candidates'**
  String get capacityGenerateCandidates;

  /// No description provided for @capacityRetryFailedWithCount.
  ///
  /// In en, this message translates to:
  /// **'Retry Failed ({count})'**
  String capacityRetryFailedWithCount(Object count);

  /// No description provided for @capacityRetryFailed.
  ///
  /// In en, this message translates to:
  /// **'Retry Failed Compression'**
  String get capacityRetryFailed;

  /// No description provided for @capacityPublishWithCount.
  ///
  /// In en, this message translates to:
  /// **'Publish Compression ({count})'**
  String capacityPublishWithCount(Object count);

  /// No description provided for @capacityPublish.
  ///
  /// In en, this message translates to:
  /// **'Publish Compression Results'**
  String get capacityPublish;

  /// No description provided for @capacityOptimizationTip.
  ///
  /// In en, this message translates to:
  /// **'Optimization generates a preview first; current content is only replaced after confirmation and can always be restored.'**
  String get capacityOptimizationTip;

  /// No description provided for @capacityPreparingState.
  ///
  /// In en, this message translates to:
  /// **'Preparing resource state.'**
  String get capacityPreparingState;

  /// No description provided for @capacityTextCharacters.
  ///
  /// In en, this message translates to:
  /// **'Text {count} chars'**
  String capacityTextCharacters(Object count);

  /// No description provided for @capacitySectionsCount.
  ///
  /// In en, this message translates to:
  /// **'Sections {count}'**
  String capacitySectionsCount(Object count);

  /// No description provided for @capacityPartsCount.
  ///
  /// In en, this message translates to:
  /// **'Blocks {count}'**
  String capacityPartsCount(Object count);

  /// No description provided for @capacityRevisionsCount.
  ///
  /// In en, this message translates to:
  /// **'History {count}'**
  String capacityRevisionsCount(Object count);

  /// No description provided for @capacityArchivedSize.
  ///
  /// In en, this message translates to:
  /// **'Archived {count} chars'**
  String capacityArchivedSize(Object count);

  /// No description provided for @capacityQueuedJobs.
  ///
  /// In en, this message translates to:
  /// **'Pending {count}'**
  String capacityQueuedJobs(Object count);

  /// No description provided for @capacityPotentialSavings.
  ///
  /// In en, this message translates to:
  /// **'Adopting candidates can save approx. {count} chars.'**
  String capacityPotentialSavings(Object count);

  /// No description provided for @capacityStatusNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get capacityStatusNormal;

  /// No description provided for @capacityStatusElastic.
  ///
  /// In en, this message translates to:
  /// **'Elastic'**
  String get capacityStatusElastic;

  /// No description provided for @capacityStatusOverflow.
  ///
  /// In en, this message translates to:
  /// **'Over Budget'**
  String get capacityStatusOverflow;

  /// No description provided for @outlinePartPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get outlinePartPending;

  /// No description provided for @outlinePartGenerated.
  ///
  /// In en, this message translates to:
  /// **'Generated'**
  String get outlinePartGenerated;

  /// No description provided for @operationFailedRetry.
  ///
  /// In en, this message translates to:
  /// **'Operation failed, please try again'**
  String get operationFailedRetry;

  /// No description provided for @resourceImportReturnToEdit.
  ///
  /// In en, this message translates to:
  /// **'Back to Edit'**
  String get resourceImportReturnToEdit;

  /// No description provided for @resourceImportConfirmSave.
  ///
  /// In en, this message translates to:
  /// **'Confirm & Save'**
  String get resourceImportConfirmSave;

  /// No description provided for @characterCardEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Character Card'**
  String get characterCardEditTitle;

  /// No description provided for @characterCardCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'New Character Card'**
  String get characterCardCreateTitle;

  /// No description provided for @characterCardConfirmDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm Deletion'**
  String get characterCardConfirmDeleteTitle;

  /// No description provided for @characterCardConfirmDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete character card “{name}”?'**
  String characterCardConfirmDeleteMessage(Object name);

  /// No description provided for @characterCardDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete character card: {error}'**
  String characterCardDeleteFailed(Object error);

  /// No description provided for @characterCardNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter at least a name'**
  String get characterCardNameRequired;

  /// No description provided for @characterCardSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save: {error}'**
  String characterCardSaveFailed(Object error);

  /// No description provided for @characterCardInfoSection.
  ///
  /// In en, this message translates to:
  /// **'Character Card Info'**
  String get characterCardInfoSection;

  /// No description provided for @characterCardWorldviewOptional.
  ///
  /// In en, this message translates to:
  /// **'Matching Worldview (Optional)'**
  String get characterCardWorldviewOptional;

  /// No description provided for @noneOption.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get noneOption;

  /// No description provided for @characterCardAiAssistedCreation.
  ///
  /// In en, this message translates to:
  /// **'AI-Assisted Character Card Creation'**
  String get characterCardAiAssistedCreation;

  /// No description provided for @detailedMode.
  ///
  /// In en, this message translates to:
  /// **'Detailed Mode'**
  String get detailedMode;

  /// No description provided for @conciseMode.
  ///
  /// In en, this message translates to:
  /// **'Concise Mode'**
  String get conciseMode;

  /// No description provided for @simpleMode.
  ///
  /// In en, this message translates to:
  /// **'Simple Mode'**
  String get simpleMode;

  /// No description provided for @characterCardTargetValidChars.
  ///
  /// In en, this message translates to:
  /// **'Target content {count} chars (max {max} chars)'**
  String characterCardTargetValidChars(Object count, Object max);

  /// No description provided for @characterCardSavedInStudioTip.
  ///
  /// In en, this message translates to:
  /// **'Generation will be saved continuously in Studio, recoverable and tracked in history'**
  String get characterCardSavedInStudioTip;

  /// No description provided for @characterCardRelateCharacterOptional.
  ///
  /// In en, this message translates to:
  /// **'Relate Existing Characters (Optional)'**
  String get characterCardRelateCharacterOptional;

  /// No description provided for @characterCardRelateCharacterHint.
  ///
  /// In en, this message translates to:
  /// **'Click to select existing characters to relate with (leave empty for standalone character)'**
  String get characterCardRelateCharacterHint;

  /// No description provided for @characterCardNoOtherCharacters.
  ///
  /// In en, this message translates to:
  /// **'No other characters'**
  String get characterCardNoOtherCharacters;

  /// No description provided for @characterCardIndependentRole.
  ///
  /// In en, this message translates to:
  /// **'Not related (conceive as standalone character)'**
  String get characterCardIndependentRole;

  /// No description provided for @characterCardRelatedCount.
  ///
  /// In en, this message translates to:
  /// **'Related to {count} characters'**
  String characterCardRelatedCount(Object count);

  /// No description provided for @characterCardUnnamed.
  ///
  /// In en, this message translates to:
  /// **'Unnamed Character'**
  String get characterCardUnnamed;

  /// No description provided for @characterCardBondRelation.
  ///
  /// In en, this message translates to:
  /// **'Bond Relationship:'**
  String get characterCardBondRelation;

  /// No description provided for @relationCompanion.
  ///
  /// In en, this message translates to:
  /// **'Companion / Teammate'**
  String get relationCompanion;

  /// No description provided for @relationChildhoodFriend.
  ///
  /// In en, this message translates to:
  /// **'Childhood Friend'**
  String get relationChildhoodFriend;

  /// No description provided for @relationLover.
  ///
  /// In en, this message translates to:
  /// **'Lover / Destined Partner'**
  String get relationLover;

  /// No description provided for @relationMentor.
  ///
  /// In en, this message translates to:
  /// **'Mentor & Disciple'**
  String get relationMentor;

  /// No description provided for @relationRival.
  ///
  /// In en, this message translates to:
  /// **'Rival / Competitor'**
  String get relationRival;

  /// No description provided for @relationKin.
  ///
  /// In en, this message translates to:
  /// **'Family / Kin'**
  String get relationKin;

  /// No description provided for @relationBenefactor.
  ///
  /// In en, this message translates to:
  /// **'Life Saver / Benefactor'**
  String get relationBenefactor;

  /// No description provided for @relationEmployment.
  ///
  /// In en, this message translates to:
  /// **'Employment'**
  String get relationEmployment;

  /// No description provided for @relationCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom relationship...'**
  String get relationCustom;

  /// No description provided for @relationCustomDescLabel.
  ///
  /// In en, this message translates to:
  /// **'Custom Relationship Description'**
  String get relationCustomDescLabel;

  /// No description provided for @relationCustomDescHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. betrothed fiancée, otherworld soul symbiote...'**
  String get relationCustomDescHint;

  /// No description provided for @characterCardCoreKeywordHint.
  ///
  /// In en, this message translates to:
  /// **'Enter character keywords or setting requirements (e.g. cold silver-haired swordmaster), leave blank for free generation...'**
  String get characterCardCoreKeywordHint;

  /// No description provided for @opening.
  ///
  /// In en, this message translates to:
  /// **'Opening...'**
  String get opening;

  /// No description provided for @aiRegenerate.
  ///
  /// In en, this message translates to:
  /// **'AI Regenerate'**
  String get aiRegenerate;

  /// No description provided for @aiFillIn.
  ///
  /// In en, this message translates to:
  /// **'AI Fill In'**
  String get aiFillIn;

  /// No description provided for @genderLabel.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get genderLabel;

  /// No description provided for @genderMale.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get genderMale;

  /// No description provided for @genderFemale.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get genderFemale;

  /// No description provided for @genderOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get genderOther;

  /// No description provided for @ageLabel.
  ///
  /// In en, this message translates to:
  /// **'Age'**
  String get ageLabel;

  /// No description provided for @customGenderLabel.
  ///
  /// In en, this message translates to:
  /// **'Custom Gender'**
  String get customGenderLabel;

  /// No description provided for @occupationLabel.
  ///
  /// In en, this message translates to:
  /// **'Occupation / Identity'**
  String get occupationLabel;

  /// No description provided for @personalityLabel.
  ///
  /// In en, this message translates to:
  /// **'Personality'**
  String get personalityLabel;

  /// No description provided for @backgroundStoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Background Story'**
  String get backgroundStoryLabel;

  /// No description provided for @appearanceLabel.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearanceLabel;

  /// No description provided for @physiqueFeaturesLabel.
  ///
  /// In en, this message translates to:
  /// **'Physique & Features'**
  String get physiqueFeaturesLabel;

  /// No description provided for @inWorldSettingSection.
  ///
  /// In en, this message translates to:
  /// **'In-World Settings'**
  String get inWorldSettingSection;

  /// No description provided for @factionLabel.
  ///
  /// In en, this message translates to:
  /// **'Faction'**
  String get factionLabel;

  /// No description provided for @locationLabel.
  ///
  /// In en, this message translates to:
  /// **'Location / Hometown'**
  String get locationLabel;

  /// No description provided for @publicGoalLabel.
  ///
  /// In en, this message translates to:
  /// **'Public Goal'**
  String get publicGoalLabel;

  /// No description provided for @hiddenMotiveLabel.
  ///
  /// In en, this message translates to:
  /// **'Hidden Motive (Narrative)'**
  String get hiddenMotiveLabel;

  /// No description provided for @abilitySourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Ability Source'**
  String get abilitySourceLabel;

  /// No description provided for @abilityCostLabel.
  ///
  /// In en, this message translates to:
  /// **'Ability Cost / Limit'**
  String get abilityCostLabel;

  /// No description provided for @taboosLabel.
  ///
  /// In en, this message translates to:
  /// **'Taboos (separated by comma)'**
  String get taboosLabel;

  /// No description provided for @relationsNoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Relationship Notes'**
  String get relationsNoteLabel;

  /// No description provided for @characterCardDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Character Card Details'**
  String get characterCardDetailTitle;

  /// No description provided for @characterPersonalityTraits.
  ///
  /// In en, this message translates to:
  /// **'Personality Traits'**
  String get characterPersonalityTraits;

  /// No description provided for @characterDescription.
  ///
  /// In en, this message translates to:
  /// **'Character Description'**
  String get characterDescription;

  /// No description provided for @characterCustomFields.
  ///
  /// In en, this message translates to:
  /// **'Custom Fields'**
  String get characterCustomFields;

  /// No description provided for @characterAiAssistantCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Assistant Character Creation'**
  String get characterAiAssistantCreateTitle;

  /// No description provided for @characterCreateAction.
  ///
  /// In en, this message translates to:
  /// **'Create Character Card'**
  String get characterCreateAction;

  /// No description provided for @characterMatchWorldview.
  ///
  /// In en, this message translates to:
  /// **'Matching: {name}'**
  String characterMatchWorldview(Object name);

  /// No description provided for @worldviewCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'New Worldview'**
  String get worldviewCreateTitle;

  /// No description provided for @worldviewEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Worldview'**
  String get worldviewEditTitle;

  /// No description provided for @worldviewDetailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Detailed Worldview'**
  String get worldviewDetailedTitle;

  /// No description provided for @worldviewConciseTitle.
  ///
  /// In en, this message translates to:
  /// **'Concise Worldview'**
  String get worldviewConciseTitle;

  /// No description provided for @worldviewOverviewDetailed.
  ///
  /// In en, this message translates to:
  /// **'Worldview Overview (counted toward total chars)'**
  String get worldviewOverviewDetailed;

  /// No description provided for @worldviewOverviewConcise.
  ///
  /// In en, this message translates to:
  /// **'Worldview Description (200~500 chars)'**
  String get worldviewOverviewConcise;

  /// No description provided for @worldviewDetailedLimitTip.
  ///
  /// In en, this message translates to:
  /// **'Detailed settings (max {count} chars, confirmed content enters scenario dialogue)'**
  String worldviewDetailedLimitTip(Object count);

  /// No description provided for @worldviewConfirmDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete worldview “{name}”?'**
  String worldviewConfirmDeleteMessage(Object name);

  /// No description provided for @worldviewDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete worldview, please try again'**
  String get worldviewDeleteFailed;

  /// No description provided for @worldviewAiAssistantTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Assistant Worldview Creation'**
  String get worldviewAiAssistantTitle;

  /// No description provided for @worldviewCreateAction.
  ///
  /// In en, this message translates to:
  /// **'Create Worldview'**
  String get worldviewCreateAction;

  /// No description provided for @originalTextContent.
  ///
  /// In en, this message translates to:
  /// **'Original Text Content'**
  String get originalTextContent;

  /// No description provided for @worldviewAiImportTip.
  ///
  /// In en, this message translates to:
  /// **'Paste any text (txt / md / HTML / novel snippet); AI will extract and integrate it into a worldview'**
  String get worldviewAiImportTip;

  /// No description provided for @pasteOriginalTextHint.
  ///
  /// In en, this message translates to:
  /// **'Paste original text content here...'**
  String get pasteOriginalTextHint;

  /// No description provided for @importModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Import Mode'**
  String get importModeLabel;

  /// No description provided for @preparingDeduction.
  ///
  /// In en, this message translates to:
  /// **'Preparing deduction…'**
  String get preparingDeduction;

  /// No description provided for @deductionProgressChars.
  ///
  /// In en, this message translates to:
  /// **'Current valid chars: {current} / {target}\n{partial}'**
  String deductionProgressChars(Object current, Object partial, Object target);

  /// No description provided for @deductionProgressStage.
  ///
  /// In en, this message translates to:
  /// **'Deducing stage {current}/{total}: {partial}'**
  String deductionProgressStage(Object current, Object partial, Object total);

  /// No description provided for @autoSaveToLibrary.
  ///
  /// In en, this message translates to:
  /// **'Autosave to Library'**
  String get autoSaveToLibrary;

  /// No description provided for @expectedTotalCharacters.
  ///
  /// In en, this message translates to:
  /// **'Expected Total Characters'**
  String get expectedTotalCharacters;

  /// No description provided for @adaptiveStageHelperText.
  ///
  /// In en, this message translates to:
  /// **'Adaptive phased high-concurrency deduction of all 9 modules, accelerating multiple times with autosave'**
  String get adaptiveStageHelperText;

  /// No description provided for @aiAnalyzeAction.
  ///
  /// In en, this message translates to:
  /// **'AI Analyze'**
  String get aiAnalyzeAction;

  /// No description provided for @selectImportModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Import Mode'**
  String get selectImportModeTitle;

  /// No description provided for @selectImportModeDesc.
  ///
  /// In en, this message translates to:
  /// **'Please select the granularity for this character material. This choice is passed directly to AI.'**
  String get selectImportModeDesc;

  /// No description provided for @conciseModeDesc.
  ///
  /// In en, this message translates to:
  /// **'Concise Mode: Preserves identity, personality, appearance, key experiences and necessary relations without expansion.'**
  String get conciseModeDesc;

  /// No description provided for @detailedModeDesc.
  ///
  /// In en, this message translates to:
  /// **'Detailed Mode: Fully organizes identity, personality, appearance, background, motives, info and relations within factual scope.'**
  String get detailedModeDesc;

  /// No description provided for @batchImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Batch AI Import {kind}'**
  String batchImportTitle(Object kind);

  /// No description provided for @provideCharacterDataTitle.
  ///
  /// In en, this message translates to:
  /// **'Provide Character Materials'**
  String get provideCharacterDataTitle;

  /// No description provided for @batchAiRecognitionTip.
  ///
  /// In en, this message translates to:
  /// **'AI will identify character names first, generating characters individually after your confirmation.'**
  String get batchAiRecognitionTip;

  /// No description provided for @pleaseSelectWorldviewFirst.
  ///
  /// In en, this message translates to:
  /// **'Please select a worldview first'**
  String get pleaseSelectWorldviewFirst;

  /// No description provided for @selectRelatedCharacters.
  ///
  /// In en, this message translates to:
  /// **'Select Related Characters'**
  String get selectRelatedCharacters;

  /// No description provided for @relatedCharactersCount.
  ///
  /// In en, this message translates to:
  /// **'{count} characters related'**
  String relatedCharactersCount(Object count);

  /// No description provided for @minTotalCharactersLabel.
  ///
  /// In en, this message translates to:
  /// **'Min Total Characters'**
  String get minTotalCharactersLabel;

  /// No description provided for @maxTotalCharactersLabel.
  ///
  /// In en, this message translates to:
  /// **'Max Total Characters'**
  String get maxTotalCharactersLabel;

  /// No description provided for @characterDataLabel.
  ///
  /// In en, this message translates to:
  /// **'{label} Materials'**
  String characterDataLabel(Object label);

  /// No description provided for @characterDataHint.
  ///
  /// In en, this message translates to:
  /// **'Paste chapters, settings, or bios containing multiple {label}…'**
  String characterDataHint(Object label);

  /// No description provided for @planningAction.
  ///
  /// In en, this message translates to:
  /// **'Planning…'**
  String get planningAction;

  /// No description provided for @enterAiStudioAction.
  ///
  /// In en, this message translates to:
  /// **'Enter AI Studio'**
  String get enterAiStudioAction;

  /// No description provided for @selectCandidatesToImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Characters to Import ({count})'**
  String selectCandidatesToImportTitle(Object count);

  /// No description provided for @importSelectedCharactersAction.
  ///
  /// In en, this message translates to:
  /// **'Import {count} Characters'**
  String importSelectedCharactersAction(Object count);

  /// No description provided for @selectCandidatesMultiTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Targets (Multiple)'**
  String get selectCandidatesMultiTitle;

  /// No description provided for @candidatesRelationTip.
  ///
  /// In en, this message translates to:
  /// **'Generated materials will establish verifiable relations based on original text and these existing characters.'**
  String get candidatesRelationTip;

  /// No description provided for @confirmRelateCharactersAction.
  ///
  /// In en, this message translates to:
  /// **'Confirm Relation to {count} Characters'**
  String confirmRelateCharactersAction(Object count);

  /// No description provided for @pasteCharacterRawTextHint.
  ///
  /// In en, this message translates to:
  /// **'Paste character or NPC original text here…'**
  String get pasteCharacterRawTextHint;

  /// No description provided for @stagedDeepGenerationTip.
  ///
  /// In en, this message translates to:
  /// **'Staged deep generation, automatically completing to target completeness'**
  String get stagedDeepGenerationTip;

  /// No description provided for @worldviewModuleRules.
  ///
  /// In en, this message translates to:
  /// **'Rules & Boundaries'**
  String get worldviewModuleRules;

  /// No description provided for @worldviewModuleState.
  ///
  /// In en, this message translates to:
  /// **'Current World Status'**
  String get worldviewModuleState;

  /// No description provided for @worldviewModuleLocations.
  ///
  /// In en, this message translates to:
  /// **'Locations & Geography'**
  String get worldviewModuleLocations;

  /// No description provided for @worldviewModuleFactions.
  ///
  /// In en, this message translates to:
  /// **'Factions & Organizations'**
  String get worldviewModuleFactions;

  /// No description provided for @worldviewModuleCustoms.
  ///
  /// In en, this message translates to:
  /// **'Customs & Daily Life'**
  String get worldviewModuleCustoms;

  /// No description provided for @worldviewModuleTimeline.
  ///
  /// In en, this message translates to:
  /// **'History & Timeline'**
  String get worldviewModuleTimeline;

  /// No description provided for @worldviewModuleGlossary.
  ///
  /// In en, this message translates to:
  /// **'Glossary'**
  String get worldviewModuleGlossary;

  /// No description provided for @worldviewModuleConstraints.
  ///
  /// In en, this message translates to:
  /// **'Creative Constraints'**
  String get worldviewModuleConstraints;

  /// No description provided for @notSpecifiedOption.
  ///
  /// In en, this message translates to:
  /// **'Not specified'**
  String get notSpecifiedOption;

  /// No description provided for @unnamedWorldview.
  ///
  /// In en, this message translates to:
  /// **'Unnamed Worldview'**
  String get unnamedWorldview;

  /// No description provided for @noExistingCharacterCards.
  ///
  /// In en, this message translates to:
  /// **'No existing character cards'**
  String get noExistingCharacterCards;

  /// No description provided for @selectedCharactersCount.
  ///
  /// In en, this message translates to:
  /// **'{count} characters selected'**
  String selectedCharactersCount(int count);

  /// No description provided for @generatingEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Generating…'**
  String get generatingEllipsis;

  /// No description provided for @aiImportCharacterTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Import Character'**
  String get aiImportCharacterTitle;

  /// No description provided for @aiImportNpcTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Import NPC'**
  String get aiImportNpcTitle;

  /// No description provided for @relateExistingCharactersTitle.
  ///
  /// In en, this message translates to:
  /// **'Relate Existing Characters'**
  String get relateExistingCharactersTitle;

  /// No description provided for @sceneBatchImportCharacterTitle.
  ///
  /// In en, this message translates to:
  /// **'Batch Import Scene Characters'**
  String get sceneBatchImportCharacterTitle;

  /// No description provided for @sceneBatchImportNpcTitle.
  ///
  /// In en, this message translates to:
  /// **'Batch Import Scene NPCs'**
  String get sceneBatchImportNpcTitle;

  /// No description provided for @belongingWorldviewOptional.
  ///
  /// In en, this message translates to:
  /// **'Belonging Worldview (Optional)'**
  String get belongingWorldviewOptional;

  /// No description provided for @relateCharactersOptional.
  ///
  /// In en, this message translates to:
  /// **'Relate Characters (Optional)'**
  String get relateCharactersOptional;

  /// No description provided for @associateWorldviewOptional.
  ///
  /// In en, this message translates to:
  /// **'Associate Worldview (Optional)'**
  String get associateWorldviewOptional;

  /// No description provided for @resourceStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get resourceStatusCancelled;

  /// No description provided for @dashboardWizardBadge.
  ///
  /// In en, this message translates to:
  /// **'Wizard'**
  String get dashboardWizardBadge;

  /// No description provided for @dashboardPresetBadge.
  ///
  /// In en, this message translates to:
  /// **'Complete Script'**
  String get dashboardPresetBadge;

  /// No description provided for @dashboardLibraryBadge.
  ///
  /// In en, this message translates to:
  /// **'All Assets'**
  String get dashboardLibraryBadge;

  /// No description provided for @dashboardSettingsBadge.
  ///
  /// In en, this message translates to:
  /// **'Model Config'**
  String get dashboardSettingsBadge;

  /// No description provided for @dashboardMyCharacterCards.
  ///
  /// In en, this message translates to:
  /// **'My Character Cards'**
  String get dashboardMyCharacterCards;

  /// No description provided for @dashboardNoCharacterCardsTitle.
  ///
  /// In en, this message translates to:
  /// **'No Character Cards'**
  String get dashboardNoCharacterCardsTitle;

  /// No description provided for @dashboardNoCharacterCardsDesc.
  ///
  /// In en, this message translates to:
  /// **'No characters created yet. Shape your protagonist or companion in the library and select them for adventure.'**
  String get dashboardNoCharacterCardsDesc;

  /// No description provided for @dashboardGoToCharacterLibrary.
  ///
  /// In en, this message translates to:
  /// **'Go to Character Library'**
  String get dashboardGoToCharacterLibrary;

  /// No description provided for @dashboardDefaultProfession.
  ///
  /// In en, this message translates to:
  /// **'Explorer'**
  String get dashboardDefaultProfession;

  /// No description provided for @dashboardNoBackgroundDesc.
  ///
  /// In en, this message translates to:
  /// **'No background description'**
  String get dashboardNoBackgroundDesc;

  /// No description provided for @dashboardStartWithCharacter.
  ///
  /// In en, this message translates to:
  /// **'Start with this character'**
  String get dashboardStartWithCharacter;

  /// No description provided for @dashboardMyWorldSettings.
  ///
  /// In en, this message translates to:
  /// **'My World Settings'**
  String get dashboardMyWorldSettings;

  /// No description provided for @dashboardNoCustomWorldsTitle.
  ///
  /// In en, this message translates to:
  /// **'No Custom Worlds'**
  String get dashboardNoCustomWorldsTitle;

  /// No description provided for @dashboardNoCustomWorldsDesc.
  ///
  /// In en, this message translates to:
  /// **'Blank slate state with no preset worlds. Conceive exclusive worlds in the library or use the wizard to start exploring.'**
  String get dashboardNoCustomWorldsDesc;

  /// No description provided for @dashboardGoToLibrary.
  ///
  /// In en, this message translates to:
  /// **'Go to Library'**
  String get dashboardGoToLibrary;

  /// No description provided for @dashboardNoWorldDesc.
  ///
  /// In en, this message translates to:
  /// **'No setting description'**
  String get dashboardNoWorldDesc;

  /// No description provided for @dashboardStartWithWorld.
  ///
  /// In en, this message translates to:
  /// **'Start with this world'**
  String get dashboardStartWithWorld;

  /// No description provided for @dashboardToggleSidebar.
  ///
  /// In en, this message translates to:
  /// **'Toggle sidebar'**
  String get dashboardToggleSidebar;

  /// No description provided for @dashboardConfigureApiKey.
  ///
  /// In en, this message translates to:
  /// **'Configure Key'**
  String get dashboardConfigureApiKey;

  /// No description provided for @dashboardSystemSettings.
  ///
  /// In en, this message translates to:
  /// **'System Settings'**
  String get dashboardSystemSettings;

  /// No description provided for @dashboardNoAdventuresTitle.
  ///
  /// In en, this message translates to:
  /// **'No Scenario Adventures Started'**
  String get dashboardNoAdventuresTitle;

  /// No description provided for @dashboardNoAdventuresDesc.
  ///
  /// In en, this message translates to:
  /// **'Select \"Custom Wizard\" above to begin your first legend'**
  String get dashboardNoAdventuresDesc;

  /// No description provided for @dashboardContinueAdventures.
  ///
  /// In en, this message translates to:
  /// **'Continue Adventures'**
  String get dashboardContinueAdventures;

  /// No description provided for @dashboardUnnamedAdventure.
  ///
  /// In en, this message translates to:
  /// **'Unnamed Adventure'**
  String get dashboardUnnamedAdventure;

  /// No description provided for @dashboardDeleteAdventureTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete adventure record'**
  String get dashboardDeleteAdventureTooltip;

  /// No description provided for @dashboardSavedAt.
  ///
  /// In en, this message translates to:
  /// **'Saved at {time}'**
  String dashboardSavedAt(Object time);

  /// No description provided for @dashboardContinueExploring.
  ///
  /// In en, this message translates to:
  /// **'Continue Exploring'**
  String get dashboardContinueExploring;

  /// No description provided for @dashboardDeleteAdventureTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Adventure Record'**
  String get dashboardDeleteAdventureTitle;

  /// No description provided for @dashboardDeleteAdventureMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete scenario \"{title}\" and all dialogue logs? This action cannot be undone.'**
  String dashboardDeleteAdventureMessage(Object title);

  /// No description provided for @dashboardAdventureDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted scenario \"{title}\"'**
  String dashboardAdventureDeleted(Object title);

  /// No description provided for @characterNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get characterNameLabel;

  /// No description provided for @presetScenesTitle.
  ///
  /// In en, this message translates to:
  /// **'Preset Scenes Studio'**
  String get presetScenesTitle;

  /// No description provided for @presetScenesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Ready-to-use complete adventure scenario settings · Start your journey with one click'**
  String get presetScenesSubtitle;

  /// No description provided for @returnToDashboard.
  ///
  /// In en, this message translates to:
  /// **'Return to Lobby'**
  String get returnToDashboard;

  /// No description provided for @presetScriptCount.
  ///
  /// In en, this message translates to:
  /// **'{count} Scripts'**
  String presetScriptCount(int count);

  /// No description provided for @presetWizardNewScene.
  ///
  /// In en, this message translates to:
  /// **'New Scene with Wizard'**
  String get presetWizardNewScene;

  /// No description provided for @presetRefreshList.
  ///
  /// In en, this message translates to:
  /// **'Refresh List'**
  String get presetRefreshList;

  /// No description provided for @presetSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search scenario scripts, worlds, or protagonists...'**
  String get presetSearchHint;

  /// No description provided for @presetStatusReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get presetStatusReady;

  /// No description provided for @presetStatusDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get presetStatusDraft;

  /// No description provided for @presetDefaultSceneName.
  ///
  /// In en, this message translates to:
  /// **'Preset Scene'**
  String get presetDefaultSceneName;

  /// No description provided for @presetNoMatchingScenes.
  ///
  /// In en, this message translates to:
  /// **'No matching preset scenes found'**
  String get presetNoMatchingScenes;

  /// No description provided for @presetNoScenes.
  ///
  /// In en, this message translates to:
  /// **'No preset scene scripts yet'**
  String get presetNoScenes;

  /// No description provided for @presetNoMatchingScenesHint.
  ///
  /// In en, this message translates to:
  /// **'Try different search terms or reset filters'**
  String get presetNoMatchingScenesHint;

  /// No description provided for @presetNoScenesHint.
  ///
  /// In en, this message translates to:
  /// **'Use the four-step wizard to generate a complete script preset with worldview, protagonist, prologue, and action branches'**
  String get presetNoScenesHint;

  /// No description provided for @presetStartWizardAction.
  ///
  /// In en, this message translates to:
  /// **'Start Wizard to Create Scene'**
  String get presetStartWizardAction;

  /// No description provided for @presetScriptDetail.
  ///
  /// In en, this message translates to:
  /// **'Script Details'**
  String get presetScriptDetail;

  /// No description provided for @presetUnnamedScene.
  ///
  /// In en, this message translates to:
  /// **'Unnamed Scene'**
  String get presetUnnamedScene;

  /// No description provided for @presetWorldviewLabel.
  ///
  /// In en, this message translates to:
  /// **'Worldview: {name}'**
  String presetWorldviewLabel(Object name);

  /// No description provided for @presetPreviewFullSetting.
  ///
  /// In en, this message translates to:
  /// **'Full Setting Preview'**
  String get presetPreviewFullSetting;

  /// No description provided for @presetLoadIntoWizard.
  ///
  /// In en, this message translates to:
  /// **'Load into Wizard for Tuning'**
  String get presetLoadIntoWizard;

  /// No description provided for @presetDeleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete Preset Scene'**
  String get presetDeleteAction;

  /// No description provided for @presetDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Preset Scene'**
  String get presetDeleteTitle;

  /// No description provided for @presetDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete preset scene \"{name}\"?\nThis script preset cannot be recovered after deletion.'**
  String presetDeleteMessage(Object name);

  /// No description provided for @presetDeletedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Deleted scene \"{name}\"'**
  String presetDeletedSuccess(Object name);

  /// No description provided for @presetDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String presetDeleteFailed(Object error);

  /// No description provided for @presetLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load preset scenes: {error}'**
  String presetLoadFailed(Object error);

  /// No description provided for @presetStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to start preset scene, please try again later'**
  String get presetStartFailed;

  /// No description provided for @presetProtagonistSummary.
  ///
  /// In en, this message translates to:
  /// **'Protagonist: {name} ({gender} · {profession})'**
  String presetProtagonistSummary(
      Object name, Object gender, Object profession);

  /// No description provided for @presetNoPlotSummary.
  ///
  /// In en, this message translates to:
  /// **'No plot summary available'**
  String get presetNoPlotSummary;

  /// No description provided for @presetDataSimplifying.
  ///
  /// In en, this message translates to:
  /// **'Simplifying data structure'**
  String get presetDataSimplifying;

  /// No description provided for @presetQuickStartAction.
  ///
  /// In en, this message translates to:
  /// **'Quick Start'**
  String get presetQuickStartAction;

  /// No description provided for @presetMenuSemantic.
  ///
  /// In en, this message translates to:
  /// **'Scene operations menu'**
  String get presetMenuSemantic;

  /// No description provided for @worldSelectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Worldview'**
  String get worldSelectionTitle;

  /// No description provided for @worldSelectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose the world laws and background settings for this adventure from conceived worlds in the library'**
  String get worldSelectionSubtitle;

  /// No description provided for @worldSelectionSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search worldview name, geography, or rules...'**
  String get worldSelectionSearchHint;

  /// No description provided for @worldSelectionNoDesc.
  ///
  /// In en, this message translates to:
  /// **'No detailed background description'**
  String get worldSelectionNoDesc;

  /// No description provided for @worldSelectionTag.
  ///
  /// In en, this message translates to:
  /// **'World Setting'**
  String get worldSelectionTag;

  /// No description provided for @worldSelectionEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No saved worldviews'**
  String get worldSelectionEmptyTitle;

  /// No description provided for @worldSelectionEmptyDesc.
  ///
  /// In en, this message translates to:
  /// **'You can create one in the library or enter custom worldview in the wizard'**
  String get worldSelectionEmptyDesc;

  /// No description provided for @characterSelectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Adventure Characters'**
  String get characterSelectionTitle;

  /// No description provided for @characterSelectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick protagonists and party companions from character archives'**
  String get characterSelectionSubtitle;

  /// No description provided for @characterSelectionSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search character name, profession, personality, or background...'**
  String get characterSelectionSearchHint;

  /// No description provided for @characterCompatNative.
  ///
  /// In en, this message translates to:
  /// **'Current World'**
  String get characterCompatNative;

  /// No description provided for @characterCompatUnbound.
  ///
  /// In en, this message translates to:
  /// **'Unbound'**
  String get characterCompatUnbound;

  /// No description provided for @characterCompatCrossWorld.
  ///
  /// In en, this message translates to:
  /// **'From Other Worlds'**
  String get characterCompatCrossWorld;

  /// No description provided for @characterAgeYears.
  ///
  /// In en, this message translates to:
  /// **'{age} years old'**
  String characterAgeYears(Object age);

  /// No description provided for @characterPersonalityPrefix.
  ///
  /// In en, this message translates to:
  /// **'Personality: {personality}'**
  String characterPersonalityPrefix(Object personality);

  /// No description provided for @characterSelectionEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No character archives available'**
  String get characterSelectionEmptyTitle;

  /// No description provided for @characterSelectionEmptyDesc.
  ///
  /// In en, this message translates to:
  /// **'Create new characters in the library, or use AI in the wizard to generate'**
  String get characterSelectionEmptyDesc;

  /// No description provided for @npcSelectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Initial NPCs'**
  String get npcSelectionTitle;

  /// No description provided for @npcSelectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose resident NPCs appearing in this adventure (frozen into adventure snapshot)'**
  String get npcSelectionSubtitle;

  /// No description provided for @npcSelectionSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search NPC name, role, or brief...'**
  String get npcSelectionSearchHint;

  /// No description provided for @npcSelectionEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No NPCs in library'**
  String get npcSelectionEmptyTitle;

  /// No description provided for @npcSelectionEmptyDesc.
  ///
  /// In en, this message translates to:
  /// **'Add NPCs in the library, or skip this step'**
  String get npcSelectionEmptyDesc;

  /// No description provided for @unnamedNpc.
  ///
  /// In en, this message translates to:
  /// **'Unnamed NPC'**
  String get unnamedNpc;

  /// No description provided for @resourceSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items selected'**
  String resourceSelectedCount(int count);

  /// No description provided for @resourceNoneSelected.
  ///
  /// In en, this message translates to:
  /// **'No items selected'**
  String get resourceNoneSelected;

  /// No description provided for @resourceOneSelected.
  ///
  /// In en, this message translates to:
  /// **'1 item selected'**
  String get resourceOneSelected;

  /// No description provided for @confirmSelection.
  ///
  /// In en, this message translates to:
  /// **'Confirm Selection'**
  String get confirmSelection;

  /// No description provided for @finishSelection.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get finishSelection;

  /// No description provided for @loadingResources.
  ///
  /// In en, this message translates to:
  /// **'Loading available resources...'**
  String get loadingResources;

  /// No description provided for @noMatchingResourceForQuery.
  ///
  /// In en, this message translates to:
  /// **'No resources found containing \"{query}\"'**
  String noMatchingResourceForQuery(Object query);

  /// No description provided for @clearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear Search'**
  String get clearSearch;

  /// No description provided for @configureApiKeyFirstForAi.
  ///
  /// In en, this message translates to:
  /// **'Please configure an API Key to use AI generation'**
  String get configureApiKeyFirstForAi;

  /// No description provided for @aiGenerationNoValidContent.
  ///
  /// In en, this message translates to:
  /// **'Generation returned no valid content. Please check network or retry'**
  String get aiGenerationNoValidContent;

  /// No description provided for @aiOpeningGeneratedSuccess.
  ///
  /// In en, this message translates to:
  /// **'AI prologue and initial action branches generated and applied!'**
  String get aiOpeningGeneratedSuccess;

  /// No description provided for @aiGenerationFailed.
  ///
  /// In en, this message translates to:
  /// **'Generation failed: {error}'**
  String aiGenerationFailed(Object error);

  /// No description provided for @openingPromptLabel.
  ///
  /// In en, this message translates to:
  /// **'Prologue Requirements / Guidance Prompts (Optional)'**
  String get openingPromptLabel;

  /// No description provided for @openingPromptHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., Start with suspense on a rainy pier, protagonist notices anomaly first...'**
  String get openingPromptHint;

  /// No description provided for @aiGenerateOpeningAndBranches.
  ///
  /// In en, this message translates to:
  /// **'Generate Prologue & Branches with AI'**
  String get aiGenerateOpeningAndBranches;

  /// No description provided for @aiOpeningGeneratingProgress.
  ///
  /// In en, this message translates to:
  /// **'AI is creating the prologue and action branches using the worldview and characters...'**
  String get aiOpeningGeneratingProgress;

  /// No description provided for @assemblyWorldviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'World: {worldview}'**
  String assemblyWorldviewSubtitle(Object worldview);

  /// No description provided for @assemblyProtagonistSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Protagonist: {name}'**
  String assemblyProtagonistSubtitle(Object name);

  /// No description provided for @assemblyConfigPageTitle.
  ///
  /// In en, this message translates to:
  /// **'Prologue Plot & Branches Configuration'**
  String get assemblyConfigPageTitle;

  /// No description provided for @saveConfigAndContinue.
  ///
  /// In en, this message translates to:
  /// **'Save Configuration & Continue'**
  String get saveConfigAndContinue;

  /// No description provided for @openingFirstSceneTitle.
  ///
  /// In en, this message translates to:
  /// **'Opening First Scene Plot'**
  String get openingFirstSceneTitle;

  /// No description provided for @openingFirstSceneDesc.
  ///
  /// In en, this message translates to:
  /// **'Set the situation description, encounter, or opening twist when the player enters the adventure.'**
  String get openingFirstSceneDesc;

  /// No description provided for @openingFirstSceneHint.
  ///
  /// In en, this message translates to:
  /// **'Describe the departure moment, environment, and unexpected crisis...'**
  String get openingFirstSceneHint;

  /// No description provided for @pleaseEnterOpeningScene.
  ///
  /// In en, this message translates to:
  /// **'Please enter the opening scene plot'**
  String get pleaseEnterOpeningScene;

  /// No description provided for @initialActionBranchesTitle.
  ///
  /// In en, this message translates to:
  /// **'Initial Action Decision Branches (Optional)'**
  String get initialActionBranchesTitle;

  /// No description provided for @initialActionBranchesDesc.
  ///
  /// In en, this message translates to:
  /// **'Three action branches for player at start; if empty, dynamically generated by AI upon entry.'**
  String get initialActionBranchesDesc;

  /// No description provided for @actionBranch1.
  ///
  /// In en, this message translates to:
  /// **'Decision Branch 1'**
  String get actionBranch1;

  /// No description provided for @actionBranch1Hint.
  ///
  /// In en, this message translates to:
  /// **'e.g., Draw sword to meet the incoming shadow'**
  String get actionBranch1Hint;

  /// No description provided for @actionBranch2.
  ///
  /// In en, this message translates to:
  /// **'Decision Branch 2'**
  String get actionBranch2;

  /// No description provided for @actionBranch2Hint.
  ///
  /// In en, this message translates to:
  /// **'e.g., Find cover and call companions for covering fire'**
  String get actionBranch2Hint;

  /// No description provided for @actionBranch3.
  ///
  /// In en, this message translates to:
  /// **'Decision Branch 3'**
  String get actionBranch3;

  /// No description provided for @actionBranch3Hint.
  ///
  /// In en, this message translates to:
  /// **'e.g., Carefully observe surroundings for an escape route'**
  String get actionBranch3Hint;

  /// No description provided for @difficultyAndGuidanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Deduction Difficulty & Custom Guidance'**
  String get difficultyAndGuidanceTitle;

  /// No description provided for @difficultyAndGuidanceDesc.
  ///
  /// In en, this message translates to:
  /// **'Control gameplay difficulty tendency and custom prompt guidance.'**
  String get difficultyAndGuidanceDesc;

  /// No description provided for @narrativeDifficulty.
  ///
  /// In en, this message translates to:
  /// **'Narrative Difficulty'**
  String get narrativeDifficulty;

  /// No description provided for @difficultyNormalDesc.
  ///
  /// In en, this message translates to:
  /// **'Normal (Standard narrative & balanced challenge)'**
  String get difficultyNormalDesc;

  /// No description provided for @difficultyCasualDesc.
  ///
  /// In en, this message translates to:
  /// **'Casual (Focus on story & relaxed immersion)'**
  String get difficultyCasualDesc;

  /// No description provided for @difficultyHardDesc.
  ///
  /// In en, this message translates to:
  /// **'Hard (Strict rules & hardcore choices)'**
  String get difficultyHardDesc;

  /// No description provided for @customGuidancePromptOptional.
  ///
  /// In en, this message translates to:
  /// **'Custom Guidance Prompt (Optional)'**
  String get customGuidancePromptOptional;

  /// No description provided for @customGuidancePromptHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., Focus on suspenseful detective atmosphere, add more sensory details...'**
  String get customGuidancePromptHint;

  /// No description provided for @worldviewBoundRules.
  ///
  /// In en, this message translates to:
  /// **'Bound worldview rules and geographical laws'**
  String get worldviewBoundRules;

  /// No description provided for @defaultContinentRules.
  ///
  /// In en, this message translates to:
  /// **'Use default continent rules'**
  String get defaultContinentRules;

  /// No description provided for @readinessReadError.
  ///
  /// In en, this message translates to:
  /// **'Cannot read resource readiness status: {error}'**
  String readinessReadError(Object error);

  /// No description provided for @readinessRetryError.
  ///
  /// In en, this message translates to:
  /// **'Failed to re-prepare resources: {error}'**
  String readinessRetryError(Object error);

  /// No description provided for @startAdventureFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to start adventure: {error}'**
  String startAdventureFailed(Object error);

  /// No description provided for @unnamedHero.
  ///
  /// In en, this message translates to:
  /// **'Nameless Hero'**
  String get unnamedHero;

  /// No description provided for @adventurerRole.
  ///
  /// In en, this message translates to:
  /// **'Adventurer'**
  String get adventurerRole;

  /// No description provided for @assemblyPreviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Comprehensive inspection of worldview, character roster, NPCs, and prologue deduction settings'**
  String get assemblyPreviewSubtitle;

  /// No description provided for @enterAdventureAction.
  ///
  /// In en, this message translates to:
  /// **'Enter Adventure'**
  String get enterAdventureAction;

  /// No description provided for @readinessCheckingTitle.
  ///
  /// In en, this message translates to:
  /// **'Checking resource assembly readiness'**
  String get readinessCheckingTitle;

  /// No description provided for @readinessUnconfirmedTitle.
  ///
  /// In en, this message translates to:
  /// **'Cannot confirm resource assembly status'**
  String get readinessUnconfirmedTitle;

  /// No description provided for @readinessReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'Adventure elements assembled'**
  String get readinessReadyTitle;

  /// No description provided for @readinessNotReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'Some resources are not yet ready'**
  String get readinessNotReadyTitle;

  /// No description provided for @readinessCheckingDesc.
  ///
  /// In en, this message translates to:
  /// **'Reading available versions of worldviews and characters.'**
  String get readinessCheckingDesc;

  /// No description provided for @readinessUnconfirmedDesc.
  ///
  /// In en, this message translates to:
  /// **'Failed to read resource status. Launch cannot be confirmed safely.'**
  String get readinessUnconfirmedDesc;

  /// No description provided for @readinessReadyDesc.
  ///
  /// In en, this message translates to:
  /// **'Click \"Enter Adventure\" below to freeze snapshot and start a new journey.'**
  String get readinessReadyDesc;

  /// No description provided for @readinessNotReadyDesc.
  ///
  /// In en, this message translates to:
  /// **'Cannot enter adventure without available revisions. Please complete resource readiness first.'**
  String get readinessNotReadyDesc;

  /// No description provided for @readinessRetrying.
  ///
  /// In en, this message translates to:
  /// **'Re-preparing…'**
  String get readinessRetrying;

  /// No description provided for @readinessRetry.
  ///
  /// In en, this message translates to:
  /// **'Re-prepare'**
  String get readinessRetry;

  /// No description provided for @worldviewSettingLabel.
  ///
  /// In en, this message translates to:
  /// **'World Setting: {name}'**
  String worldviewSettingLabel(Object name);

  /// No description provided for @worldviewSettingTitle.
  ///
  /// In en, this message translates to:
  /// **'World Setting'**
  String get worldviewSettingTitle;

  /// No description provided for @readAloudWorldview.
  ///
  /// In en, this message translates to:
  /// **'Read Aloud World Setting'**
  String get readAloudWorldview;

  /// No description provided for @protagonistLeadLabel.
  ///
  /// In en, this message translates to:
  /// **'Main Protagonist: {name} ({className})'**
  String protagonistLeadLabel(Object name, Object className);

  /// No description provided for @mainProtagonistTitle.
  ///
  /// In en, this message translates to:
  /// **'Main Protagonist'**
  String get mainProtagonistTitle;

  /// No description provided for @personalityFeatureLabel.
  ///
  /// In en, this message translates to:
  /// **'Personality: {personality}'**
  String personalityFeatureLabel(Object personality);

  /// No description provided for @backgroundStoryPrefix.
  ///
  /// In en, this message translates to:
  /// **'Background: {background}'**
  String backgroundStoryPrefix(Object background);

  /// No description provided for @accompanyingCharactersCount.
  ///
  /// In en, this message translates to:
  /// **'Accompanying Characters ({count}):'**
  String accompanyingCharactersCount(int count);

  /// No description provided for @characterBondsCount.
  ///
  /// In en, this message translates to:
  /// **'Character Bonds ({count}):'**
  String characterBondsCount(int count);

  /// No description provided for @residentNpcsCount.
  ///
  /// In en, this message translates to:
  /// **'Resident NPCs ({count})'**
  String residentNpcsCount(int count);

  /// No description provided for @openingSceneAndDecisionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Prologue & Action Decisions'**
  String get openingSceneAndDecisionsTitle;

  /// No description provided for @openingSceneTitle.
  ///
  /// In en, this message translates to:
  /// **'Prologue Scene'**
  String get openingSceneTitle;

  /// No description provided for @readAloudOpeningScene.
  ///
  /// In en, this message translates to:
  /// **'Read Aloud Prologue Scene'**
  String get readAloudOpeningScene;

  /// No description provided for @aiDynamicOpeningPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'(AI will dynamically conceive the opening scene based on the worldview and character background)'**
  String get aiDynamicOpeningPlaceholder;

  /// No description provided for @initialActionDecisionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Initial Action Decision Branches:'**
  String get initialActionDecisionsTitle;

  /// No description provided for @noMatchingResourceTitle.
  ///
  /// In en, this message translates to:
  /// **'No matching resources'**
  String get noMatchingResourceTitle;

  /// No description provided for @noMatchingResourceDesc.
  ///
  /// In en, this message translates to:
  /// **'Try entering other search terms or clear filters'**
  String get noMatchingResourceDesc;

  /// No description provided for @searchResourceNameOrDesc.
  ///
  /// In en, this message translates to:
  /// **'Search resource name or description...'**
  String get searchResourceNameOrDesc;

  /// No description provided for @aiOpeningPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Prologue Generator'**
  String get aiOpeningPanelTitle;

  /// No description provided for @aiOpeningPanelDesc.
  ///
  /// In en, this message translates to:
  /// **'Fill in your prologue requirements, and AI will generate the prologue and initial action branches based on the worldview, protagonist and companion character cards, bonds, and NPCs; the result can still be edited manually.'**
  String get aiOpeningPanelDesc;

  /// No description provided for @regenerate.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get regenerate;

  /// No description provided for @assemblyPipelineTitle.
  ///
  /// In en, this message translates to:
  /// **'Adventure Assembly Pipeline'**
  String get assemblyPipelineTitle;

  /// No description provided for @assemblyPipelineSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Step-by-step · Page-based resource assembly · Zero dialog constraints'**
  String get assemblyPipelineSubtitle;

  /// No description provided for @phaseWorldview.
  ///
  /// In en, this message translates to:
  /// **'Worldview'**
  String get phaseWorldview;

  /// No description provided for @phaseCharacters.
  ///
  /// In en, this message translates to:
  /// **'Roster'**
  String get phaseCharacters;

  /// No description provided for @phaseOpening.
  ///
  /// In en, this message translates to:
  /// **'Opening & Branches'**
  String get phaseOpening;

  /// No description provided for @phasePreview.
  ///
  /// In en, this message translates to:
  /// **'Assembly Overview'**
  String get phasePreview;

  /// No description provided for @nextPhaseLabel.
  ///
  /// In en, this message translates to:
  /// **'Next: {phase}'**
  String nextPhaseLabel(Object phase);

  /// No description provided for @previousStepAction.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previousStepAction;

  /// No description provided for @pleaseSetWorldviewName.
  ///
  /// In en, this message translates to:
  /// **'Please set a worldview name'**
  String get pleaseSetWorldviewName;

  /// No description provided for @pleaseAddAtLeastOneCharacter.
  ///
  /// In en, this message translates to:
  /// **'Please add at least one character'**
  String get pleaseAddAtLeastOneCharacter;

  /// No description provided for @worldviewSelectedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Worldview \"{name}\" selected'**
  String worldviewSelectedSuccess(Object name);

  /// No description provided for @rosterUpdatedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Character roster updated'**
  String get rosterUpdatedSuccess;

  /// No description provided for @npcsSelectedCountSuccess.
  ///
  /// In en, this message translates to:
  /// **'{count} NPCs selected'**
  String npcsSelectedCountSuccess(int count);

  /// No description provided for @openingConfigSavedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Prologue configuration saved'**
  String get openingConfigSavedSuccess;

  /// No description provided for @characterJoinedPartySuccess.
  ///
  /// In en, this message translates to:
  /// **'Character \"{name}\" joined the party'**
  String characterJoinedPartySuccess(Object name);

  /// No description provided for @worldviewLibraryLinkTitle.
  ///
  /// In en, this message translates to:
  /// **'Worldview Library Association'**
  String get worldviewLibraryLinkTitle;

  /// No description provided for @selectFromLibrary.
  ///
  /// In en, this message translates to:
  /// **'Select from Library'**
  String get selectFromLibrary;

  /// No description provided for @boundLibraryWorldviewId.
  ///
  /// In en, this message translates to:
  /// **'Bound Library Worldview ID: {id}'**
  String boundLibraryWorldviewId(Object id);

  /// No description provided for @notBoundPresetHint.
  ///
  /// In en, this message translates to:
  /// **'No preset bound. You can also enter custom world settings below directly.'**
  String get notBoundPresetHint;

  /// No description provided for @worldviewDetailsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Worldview Setting Details'**
  String get worldviewDetailsSectionTitle;

  /// No description provided for @worldviewDetailsSectionDesc.
  ///
  /// In en, this message translates to:
  /// **'Set continental laws, geographical background, civilization level, and factions.'**
  String get worldviewDetailsSectionDesc;

  /// No description provided for @worldNameRequiredLabel.
  ///
  /// In en, this message translates to:
  /// **'World Name *'**
  String get worldNameRequiredLabel;

  /// No description provided for @worldNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., Elden Continent, Cyber Neo Metropolis 2099, Cultivation Ancient Realm...'**
  String get worldNameHint;

  /// No description provided for @pleaseEnterWorldName.
  ///
  /// In en, this message translates to:
  /// **'Please enter the world name'**
  String get pleaseEnterWorldName;

  /// No description provided for @lawsAndBackgroundLabel.
  ///
  /// In en, this message translates to:
  /// **'Laws & Background Setting'**
  String get lawsAndBackgroundLabel;

  /// No description provided for @lawsAndBackgroundHint.
  ///
  /// In en, this message translates to:
  /// **'Describe magic and tech systems, celestial climate, factions, and power dynamics...'**
  String get lawsAndBackgroundHint;

  /// No description provided for @charactersAndNpcAssemblyTitle.
  ///
  /// In en, this message translates to:
  /// **'Character & NPC Assembly'**
  String get charactersAndNpcAssemblyTitle;

  /// No description provided for @selectCharactersFromLibrary.
  ///
  /// In en, this message translates to:
  /// **'Select Characters from Library'**
  String get selectCharactersFromLibrary;

  /// No description provided for @selectNpcCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Select NPCs ({count})'**
  String selectNpcCountLabel(int count);

  /// No description provided for @newCharacterAction.
  ///
  /// In en, this message translates to:
  /// **'New Character'**
  String get newCharacterAction;

  /// No description provided for @rosterSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Appearing Characters Roster ({count})'**
  String rosterSectionTitle(int count);

  /// No description provided for @rosterSectionDesc.
  ///
  /// In en, this message translates to:
  /// **'Must select 1 as the main protagonist; others can be assigned companion, antagonist, mentor, etc.'**
  String get rosterSectionDesc;

  /// No description provided for @noCharactersAddedYet.
  ///
  /// In en, this message translates to:
  /// **'No appearing characters added yet'**
  String get noCharactersAddedYet;

  /// No description provided for @clickAboveToAddCharactersHint.
  ///
  /// In en, this message translates to:
  /// **'Click \"Select Characters from Library\" or \"New Character\" above'**
  String get clickAboveToAddCharactersHint;

  /// No description provided for @setAsMainProtagonist.
  ///
  /// In en, this message translates to:
  /// **'Set as Main Protagonist'**
  String get setAsMainProtagonist;

  /// No description provided for @scriptRoleOrientation.
  ///
  /// In en, this message translates to:
  /// **'Script Role Position'**
  String get scriptRoleOrientation;

  /// No description provided for @openingAndRulesAdvancedConfigTitle.
  ///
  /// In en, this message translates to:
  /// **'Prologue & Rules Advanced Configuration'**
  String get openingAndRulesAdvancedConfigTitle;

  /// No description provided for @fullscreenAdvancedConfig.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen Advanced Config'**
  String get fullscreenAdvancedConfig;

  /// No description provided for @openingSceneContentTitle.
  ///
  /// In en, this message translates to:
  /// **'Prologue Scene Content'**
  String get openingSceneContentTitle;

  /// No description provided for @openingSceneContentDesc.
  ///
  /// In en, this message translates to:
  /// **'The first scene description when the adventure begins.'**
  String get openingSceneContentDesc;

  /// No description provided for @openingSceneContentHint.
  ///
  /// In en, this message translates to:
  /// **'Describe the environment and twist when the protagonist appears...'**
  String get openingSceneContentHint;

  /// No description provided for @openingBranchesDesc.
  ///
  /// In en, this message translates to:
  /// **'Action directions for the player to choose at the end of the prologue.'**
  String get openingBranchesDesc;

  /// No description provided for @branchNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Branch {number}'**
  String branchNumberLabel(Object number);

  /// No description provided for @actionOptionHint.
  ///
  /// In en, this message translates to:
  /// **'Action Option {number}...'**
  String actionOptionHint(Object number);

  /// No description provided for @enterStandaloneFullscreenPreview.
  ///
  /// In en, this message translates to:
  /// **'Enter Standalone Fullscreen Preview'**
  String get enterStandaloneFullscreenPreview;

  /// No description provided for @fullscreenPreviewButton.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen Preview'**
  String get fullscreenPreviewButton;

  /// No description provided for @customUnnamedWorld.
  ///
  /// In en, this message translates to:
  /// **'Custom Unnamed World'**
  String get customUnnamedWorld;

  /// No description provided for @unspecifiedProtagonist.
  ///
  /// In en, this message translates to:
  /// **'Unspecified Protagonist'**
  String get unspecifiedProtagonist;

  /// No description provided for @companionRosterSummary.
  ///
  /// In en, this message translates to:
  /// **'Companions: {roster}'**
  String companionRosterSummary(Object roster);

  /// No description provided for @selectedInitialNpcCount.
  ///
  /// In en, this message translates to:
  /// **'{count} initial NPCs selected'**
  String selectedInitialNpcCount(int count);

  /// No description provided for @firstSceneOpeningPlotTitle.
  ///
  /// In en, this message translates to:
  /// **'Prologue First Scene'**
  String get firstSceneOpeningPlotTitle;

  /// No description provided for @aiDynamicOpeningSummary.
  ///
  /// In en, this message translates to:
  /// **'Dynamically developed by AI based on background'**
  String get aiDynamicOpeningSummary;

  /// No description provided for @wizardWorldviewQuickBadge.
  ///
  /// In en, this message translates to:
  /// **'Quick ideas and library authoring'**
  String get wizardWorldviewQuickBadge;

  /// No description provided for @wizardWorldviewPromptLabel.
  ///
  /// In en, this message translates to:
  /// **'Worldview idea / genre preference (optional)'**
  String get wizardWorldviewPromptLabel;

  /// No description provided for @wizardWorldviewPromptHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., a steampunk sky city, whispers of ancient gods, or a deep-sea dystopia. Leave blank for a free-form idea...'**
  String get wizardWorldviewPromptHint;

  /// No description provided for @generationModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Generation mode'**
  String get generationModeLabel;

  /// No description provided for @clearSettingsAction.
  ///
  /// In en, this message translates to:
  /// **'Clear settings'**
  String get clearSettingsAction;

  /// No description provided for @wizardGenerateWorldviewAction.
  ///
  /// In en, this message translates to:
  /// **'Generate worldview with AI'**
  String get wizardGenerateWorldviewAction;

  /// No description provided for @wizardRegenerateWorldviewAction.
  ///
  /// In en, this message translates to:
  /// **'Regenerate worldview'**
  String get wizardRegenerateWorldviewAction;

  /// No description provided for @wizardWorldviewGeneratingBrief.
  ///
  /// In en, this message translates to:
  /// **'Drafting worldview…'**
  String get wizardWorldviewGeneratingBrief;

  /// No description provided for @wizardWorldviewGeneratingDetailed.
  ///
  /// In en, this message translates to:
  /// **'Developing worldview in stages…'**
  String get wizardWorldviewGeneratingDetailed;

  /// No description provided for @saveToLibraryNow.
  ///
  /// In en, this message translates to:
  /// **'Save to library now'**
  String get saveToLibraryNow;

  /// No description provided for @wizardReusableBadge.
  ///
  /// In en, this message translates to:
  /// **'Reusable anytime'**
  String get wizardReusableBadge;

  /// No description provided for @wizardWorldviewSaveDescription.
  ///
  /// In en, this message translates to:
  /// **'Save this setting to the worldview library so you can reuse and expand it in future adventures.'**
  String get wizardWorldviewSaveDescription;

  /// No description provided for @charactersSavedCount.
  ///
  /// In en, this message translates to:
  /// **'Saved {count} character settings to the library'**
  String charactersSavedCount(int count);

  /// No description provided for @characterCardSavedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Saved character \"{name}\" to the library'**
  String characterCardSavedSuccess(String name);

  /// No description provided for @fullscreenSelectionAction.
  ///
  /// In en, this message translates to:
  /// **'Full-screen selection'**
  String get fullscreenSelectionAction;

  /// No description provided for @wizardCharacterAiSummary.
  ///
  /// In en, this message translates to:
  /// **'Describe the character’s personality or role. AI uses the current worldview, {worldview}, to create a protagonist or party member and add them to the roster. The library creator offers a more detailed workflow.'**
  String wizardCharacterAiSummary(String worldview);

  /// No description provided for @wizardCharacterPromptLabel.
  ///
  /// In en, this message translates to:
  /// **'Character idea / persona preference (optional)'**
  String get wizardCharacterPromptLabel;

  /// No description provided for @wizardCharacterPromptHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., a composed demon-slaying swordsman, a cheerful white-haired healer, or a cool mechanical ranger...'**
  String get wizardCharacterPromptHint;

  /// No description provided for @wizardGenerateMainCharacterAction.
  ///
  /// In en, this message translates to:
  /// **'Generate protagonist with AI'**
  String get wizardGenerateMainCharacterAction;

  /// No description provided for @wizardAddCharacterToRosterAction.
  ///
  /// In en, this message translates to:
  /// **'Add character with AI'**
  String get wizardAddCharacterToRosterAction;

  /// No description provided for @currentWorldviewLabel.
  ///
  /// In en, this message translates to:
  /// **'Current world'**
  String get currentWorldviewLabel;

  /// No description provided for @removeRosterCharacter.
  ///
  /// In en, this message translates to:
  /// **'Remove from roster'**
  String get removeRosterCharacter;

  /// No description provided for @clearRelatedCharacters.
  ///
  /// In en, this message translates to:
  /// **'Clear links'**
  String get clearRelatedCharacters;

  /// No description provided for @wizardRelatedCharactersSummary.
  ///
  /// In en, this message translates to:
  /// **'{count} linked: {names}'**
  String wizardRelatedCharactersSummary(int count, String names);

  /// No description provided for @wizardRelationAssociationSummary.
  ///
  /// In en, this message translates to:
  /// **'The new character will form a story bond with the selected characters.'**
  String get wizardRelationAssociationSummary;

  /// No description provided for @charactersAddedToRoster.
  ///
  /// In en, this message translates to:
  /// **'Added {count} AI-generated characters to the roster'**
  String charactersAddedToRoster(int count);

  /// No description provided for @roleMaleLead.
  ///
  /// In en, this message translates to:
  /// **'Male lead'**
  String get roleMaleLead;

  /// No description provided for @roleFemaleLead.
  ///
  /// In en, this message translates to:
  /// **'Female lead'**
  String get roleFemaleLead;

  /// No description provided for @roleMaleOne.
  ///
  /// In en, this message translates to:
  /// **'Male lead 1'**
  String get roleMaleOne;

  /// No description provided for @roleFemaleOne.
  ///
  /// In en, this message translates to:
  /// **'Female lead 1'**
  String get roleFemaleOne;

  /// No description provided for @roleMaleTwo.
  ///
  /// In en, this message translates to:
  /// **'Male lead 2'**
  String get roleMaleTwo;

  /// No description provided for @roleFemaleTwo.
  ///
  /// In en, this message translates to:
  /// **'Female lead 2'**
  String get roleFemaleTwo;

  /// No description provided for @roleSupporting.
  ///
  /// In en, this message translates to:
  /// **'Supporting character'**
  String get roleSupporting;

  /// No description provided for @roleVillain.
  ///
  /// In en, this message translates to:
  /// **'Antagonist'**
  String get roleVillain;

  /// No description provided for @roleMentor.
  ///
  /// In en, this message translates to:
  /// **'Mentor'**
  String get roleMentor;

  /// No description provided for @roleFamily.
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get roleFamily;

  /// No description provided for @relationFriend.
  ///
  /// In en, this message translates to:
  /// **'Friend'**
  String get relationFriend;

  /// No description provided for @relationEnemy.
  ///
  /// In en, this message translates to:
  /// **'Enemy'**
  String get relationEnemy;

  /// No description provided for @relationStranger.
  ///
  /// In en, this message translates to:
  /// **'Stranger'**
  String get relationStranger;

  /// No description provided for @mainProtagonistDescription.
  ///
  /// In en, this message translates to:
  /// **'Main protagonist (controls actions and key decisions)'**
  String get mainProtagonistDescription;

  /// No description provided for @protagonistShortTag.
  ///
  /// In en, this message translates to:
  /// **'Protagonist'**
  String get protagonistShortTag;

  /// No description provided for @relationshipNetworkDescription.
  ///
  /// In en, this message translates to:
  /// **'Set the bonds, affiliations, and past conflicts between the characters. AI will follow these relationships.'**
  String get relationshipNetworkDescription;

  /// No description provided for @relationAssetReference.
  ///
  /// In en, this message translates to:
  /// **'Related resource: {suggestion} (can be changed for this adventure)'**
  String relationAssetReference(String suggestion);

  /// No description provided for @relationDetailsHint.
  ///
  /// In en, this message translates to:
  /// **'Describe the history or clues behind their relationship (optional).'**
  String get relationDetailsHint;

  /// No description provided for @relationshipNetworkTitle.
  ///
  /// In en, this message translates to:
  /// **'Character Bonds & Relationships'**
  String get relationshipNetworkTitle;

  /// No description provided for @adventureReadyToEnterTitle.
  ///
  /// In en, this message translates to:
  /// **'Ready to enter the world'**
  String get adventureReadyToEnterTitle;

  /// No description provided for @worldviewSnapshotBoundSummary.
  ///
  /// In en, this message translates to:
  /// **'Bound worldview snapshot, rules, and geography are ready'**
  String get worldviewSnapshotBoundSummary;

  /// No description provided for @characterCardSnapshotBoundSummary.
  ///
  /// In en, this message translates to:
  /// **'Bound to the complete character card in the library'**
  String get characterCardSnapshotBoundSummary;

  /// No description provided for @characterCustomDesignedSummary.
  ///
  /// In en, this message translates to:
  /// **'Protagonist settings customized'**
  String get characterCustomDesignedSummary;

  /// No description provided for @unnamedCharacterA.
  ///
  /// In en, this message translates to:
  /// **'Character A'**
  String get unnamedCharacterA;

  /// No description provided for @unnamedCharacterB.
  ///
  /// In en, this message translates to:
  /// **'Character B'**
  String get unnamedCharacterB;

  /// No description provided for @savePreviewAction.
  ///
  /// In en, this message translates to:
  /// **'Save preview'**
  String get savePreviewAction;

  /// No description provided for @previewTemplateNoStartHint.
  ///
  /// In en, this message translates to:
  /// **'This saves a recoverable preview template and does not start the adventure.'**
  String get previewTemplateNoStartHint;

  /// No description provided for @adventurePreviewName.
  ///
  /// In en, this message translates to:
  /// **'{worldview} · Adventure Preview'**
  String adventurePreviewName(String worldview);

  /// No description provided for @adventurePreviewSavedMessage.
  ///
  /// In en, this message translates to:
  /// **'Saved preview \"{name}\". You can restore it in Preset Scenes.'**
  String adventurePreviewSavedMessage(String name);

  /// No description provided for @adventurePreviewExistsMessage.
  ///
  /// In en, this message translates to:
  /// **'An adventure preview with the same details already exists.'**
  String get adventurePreviewExistsMessage;

  /// No description provided for @adventurePreviewSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save preview: {error}'**
  String adventurePreviewSaveFailed(String error);

  /// Explains automatic saving of roster characters to the library.
  ///
  /// In en, this message translates to:
  /// **'Automatically save roster character designs to your character library for future adventures.'**
  String get wizardCharacterSaveDescription;

  /// Reports character cards that could not be loaded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{One character card could not be loaded.} other{{count} character cards could not be loaded.}}'**
  String wizardMalformedCharacterCards(int count);

  /// Localized conversation management label.
  ///
  /// In en, this message translates to:
  /// **'Delete scene conversations'**
  String get conversationDeleteTitle;

  /// Localized conversation management message.
  ///
  /// In en, this message translates to:
  /// **'Delete the selected {count} scene conversations? This cannot be undone.'**
  String conversationDeleteConfirm(int count);

  /// Localized conversation management message.
  ///
  /// In en, this message translates to:
  /// **'Deletion stopped. Check the remaining conversations and try again: {error}'**
  String conversationDeleteInterrupted(String error);

  /// Localized conversation management label.
  ///
  /// In en, this message translates to:
  /// **'Manage past conversations'**
  String get conversationManageTitle;

  /// Localized conversation management message.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedItemsCount(int count);

  /// Localized conversation management label.
  ///
  /// In en, this message translates to:
  /// **'Deleting…'**
  String get deletingAction;

  /// Localized conversation management label.
  ///
  /// In en, this message translates to:
  /// **'Delete selected'**
  String get batchDeleteAction;

  /// Localized conversation management label.
  ///
  /// In en, this message translates to:
  /// **'No scene conversations to manage'**
  String get noManagedConversations;

  /// Localized conversation management label.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAllAction;

  /// Localized conversation management label.
  ///
  /// In en, this message translates to:
  /// **'Scene conversation'**
  String get sceneConversationLabel;

  /// Message editing interface text.
  ///
  /// In en, this message translates to:
  /// **'Edit your message'**
  String get messageEditUserTitle;

  /// Message editing interface text.
  ///
  /// In en, this message translates to:
  /// **'Edit AI reply'**
  String get messageEditAssistantTitle;

  /// Message editing interface text.
  ///
  /// In en, this message translates to:
  /// **'Editing this message regenerates the story that follows.'**
  String get messageEditUserSubtitle;

  /// Message editing interface text.
  ///
  /// In en, this message translates to:
  /// **'Edit this story text to adjust narration or correct details.'**
  String get messageEditAssistantSubtitle;

  /// Message editing interface text.
  ///
  /// In en, this message translates to:
  /// **'Saving clears all history after this message and regenerates the story from your new input.'**
  String get messageEditUserWarning;

  /// Message editing interface text.
  ///
  /// In en, this message translates to:
  /// **'Message text'**
  String get messageBodyLabel;

  /// Message editing interface text.
  ///
  /// In en, this message translates to:
  /// **'Long text is supported, including line breaks and formatting.'**
  String get messageEditDescription;

  /// Message editing interface text.
  ///
  /// In en, this message translates to:
  /// **'Enter message content…'**
  String get messageContentHint;

  /// Message editing interface text.
  ///
  /// In en, this message translates to:
  /// **'Save and regenerate'**
  String get saveAndRegenerateAction;

  /// Message editing interface text.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get saveChangesAction;

  /// Message editing interface text.
  ///
  /// In en, this message translates to:
  /// **'Message content cannot be empty.'**
  String get messageContentRequired;

  /// Message editing interface text.
  ///
  /// In en, this message translates to:
  /// **'No changes were made.'**
  String get messageUnchanged;

  /// Message editing interface text.
  ///
  /// In en, this message translates to:
  /// **'This message is no longer in the current conversation. Return and refresh.'**
  String get messageNoLongerCurrent;

  /// Message editing interface text.
  ///
  /// In en, this message translates to:
  /// **'Saved and regenerated'**
  String get messageSavedAndRegenerated;

  /// Message editing interface text.
  ///
  /// In en, this message translates to:
  /// **'Changes saved'**
  String get messageChangesSaved;

  /// Message editing interface text.
  ///
  /// In en, this message translates to:
  /// **'Could not save. Please try again.'**
  String get messageSaveRetry;

  /// Inventory and adventure session labels.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get inventoryTitle;

  /// Inventory and adventure session labels.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get inventoryItemsTitle;

  /// Inventory and adventure session labels.
  ///
  /// In en, this message translates to:
  /// **'Equipment'**
  String get equipmentTitle;

  /// Inventory and adventure session labels.
  ///
  /// In en, this message translates to:
  /// **'Legacy inventory'**
  String get legacyInventoryTitle;

  /// Inventory counts summary.
  ///
  /// In en, this message translates to:
  /// **'{itemCount} items, {equipmentCount} equipment pieces'**
  String inventorySummary(int itemCount, int equipmentCount);

  /// Inventory and adventure session labels.
  ///
  /// In en, this message translates to:
  /// **'Quick menu'**
  String get quickMenuTooltip;

  /// Inventory and adventure session labels.
  ///
  /// In en, this message translates to:
  /// **'Character status'**
  String get characterStatusTitle;

  /// Inventory and adventure session labels.
  ///
  /// In en, this message translates to:
  /// **'Word count settings'**
  String get wordCountSettings;

  /// Inventory and adventure session labels.
  ///
  /// In en, this message translates to:
  /// **'Back to lobby'**
  String get backToLobby;

  /// Inventory and adventure session labels.
  ///
  /// In en, this message translates to:
  /// **'Restart adventure?'**
  String get restartAdventureTitle;

  /// Inventory and adventure session labels.
  ///
  /// In en, this message translates to:
  /// **'This resets the current conversation and adventure progress, then returns to the home page.'**
  String get restartAdventureMessage;

  /// Inventory and adventure session labels.
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get restartAdventureAction;

  /// Inventory and adventure session labels.
  ///
  /// In en, this message translates to:
  /// **'Stop generation'**
  String get stopGenerationAction;

  /// Adventure session navigation label.
  ///
  /// In en, this message translates to:
  /// **'Text adventure'**
  String get textAdventureTitle;

  /// Adventure session navigation label.
  ///
  /// In en, this message translates to:
  /// **'Search conversation'**
  String get searchConversationAction;

  /// Adventure session navigation label.
  ///
  /// In en, this message translates to:
  /// **'Scene history and sidebar'**
  String get historyAndSidebarAction;

  /// Adventure session navigation label.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get moreOptionsAction;

  /// Adventure session navigation label.
  ///
  /// In en, this message translates to:
  /// **'Reply length'**
  String get replyLengthSetting;

  /// Adventure session navigation label.
  ///
  /// In en, this message translates to:
  /// **'Switch model'**
  String get switchModelAction;

  /// Adventure session navigation label.
  ///
  /// In en, this message translates to:
  /// **'Prompt settings'**
  String get promptSettingsAction;

  /// Settings page title for response length and dialogue density.
  ///
  /// In en, this message translates to:
  /// **'Word count and dialogue density settings'**
  String get wordCountAndDensitySettings;

  /// Chat message action label.
  ///
  /// In en, this message translates to:
  /// **'Reasoning copied to clipboard'**
  String get reasoningCopiedToast;

  /// Chat message action label.
  ///
  /// In en, this message translates to:
  /// **'(Edited)'**
  String get editedBadge;

  /// Chat message action label.
  ///
  /// In en, this message translates to:
  /// **'This message cannot be recovered. Delete it?'**
  String get deleteMessageConfirmation;

  /// Chat message action label.
  ///
  /// In en, this message translates to:
  /// **'Remove bookmark'**
  String get removeBookmarkAction;

  /// Chat message action label.
  ///
  /// In en, this message translates to:
  /// **'Add bookmark'**
  String get addBookmarkAction;

  /// Chat message action label.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editMessageAction;

  /// Chat message action label.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get regenerateMessageAction;

  /// Label for the assistant response.
  ///
  /// In en, this message translates to:
  /// **'AI reply'**
  String get assistantReplyLabel;

  /// Model selector interface label.
  ///
  /// In en, this message translates to:
  /// **'Select model to regenerate'**
  String get selectModelForRegeneration;

  /// Model selector interface label.
  ///
  /// In en, this message translates to:
  /// **'Select language model'**
  String get selectLanguageModel;

  /// Model selector interface message.
  ///
  /// In en, this message translates to:
  /// **'Current: {model} ({provider})'**
  String currentModelSummary(String model, String provider);

  /// Model selector interface label.
  ///
  /// In en, this message translates to:
  /// **'Selected model'**
  String get selectedModelLabel;

  /// Model selector interface label.
  ///
  /// In en, this message translates to:
  /// **'Not selected (using default)'**
  String get defaultModelPlaceholder;

  /// Model selector interface label.
  ///
  /// In en, this message translates to:
  /// **'Apply selection'**
  String get confirmApplyAction;

  /// Model selector interface label.
  ///
  /// In en, this message translates to:
  /// **'Select or enter a valid model name.'**
  String get selectValidModelError;

  /// Model selector interface label.
  ///
  /// In en, this message translates to:
  /// **'This message is no longer in the current conversation. Return and refresh.'**
  String get messageNoLongerCurrentError;

  /// Model selector interface label.
  ///
  /// In en, this message translates to:
  /// **'Cannot regenerate: no valid user message was found.'**
  String get regenerationUserMessageMissingError;

  /// Model selector interface label.
  ///
  /// In en, this message translates to:
  /// **'Cannot regenerate: the associated user message was not found.'**
  String get regenerationTargetMissingError;

  /// Model selector interface label.
  ///
  /// In en, this message translates to:
  /// **'Regenerating…'**
  String get modelRegenerationStarting;

  /// Model selector interface message.
  ///
  /// In en, this message translates to:
  /// **'Switched to model: {model}'**
  String modelSwitchedSuccess(String model);

  /// Model selector interface label.
  ///
  /// In en, this message translates to:
  /// **'Could not switch models. Please try again.'**
  String get modelSwitchFailed;

  /// Model selector interface label.
  ///
  /// In en, this message translates to:
  /// **'Service provider'**
  String get serviceProviderSection;

  /// Model selector interface label.
  ///
  /// In en, this message translates to:
  /// **'Choose an official API provider or a local/third-party compatible service.'**
  String get serviceProviderDescription;

  /// Model selector interface label.
  ///
  /// In en, this message translates to:
  /// **'LLM provider'**
  String get llmProviderLabel;

  /// Model selector interface label.
  ///
  /// In en, this message translates to:
  /// **'Recently used'**
  String get recentModelsSection;

  /// Model selector interface label.
  ///
  /// In en, this message translates to:
  /// **'Quickly switch to models used on this device.'**
  String get recentModelsDescription;

  /// Model selector interface label.
  ///
  /// In en, this message translates to:
  /// **'Recommended models'**
  String get recommendedModelsSection;

  /// Model selector interface label.
  ///
  /// In en, this message translates to:
  /// **'Core models optimized for creative writing and role-playing.'**
  String get recommendedModelsDescription;

  /// Model selector interface label.
  ///
  /// In en, this message translates to:
  /// **'Custom model name'**
  String get customModelSection;

  /// Model selector interface label.
  ///
  /// In en, this message translates to:
  /// **'Enter another DeepSeek model name here if needed.'**
  String get deepseekCustomModelDescription;

  /// Model selector interface label.
  ///
  /// In en, this message translates to:
  /// **'Enter a model identifier supported by the compatible endpoint (for example, gpt-4o or claude-3-5-sonnet).'**
  String get otherCustomModelDescription;

  /// Model selector interface label.
  ///
  /// In en, this message translates to:
  /// **'Enter model name…'**
  String get modelNamePlaceholder;

  /// Model selector interface message.
  ///
  /// In en, this message translates to:
  /// **'Selected custom model: {model}'**
  String customModelSelected(String model);

  /// Empty adventure scene state text.
  ///
  /// In en, this message translates to:
  /// **'A fresh adventure awaits'**
  String get adventureBlankSlateTitle;

  /// Empty adventure scene state text.
  ///
  /// In en, this message translates to:
  /// **'This scene has no conversations or action records yet. Enter an action below or choose a direction to explore and begin your adventure.'**
  String get adventureBlankSlateDescription;

  /// Empty adventure scene state text.
  ///
  /// In en, this message translates to:
  /// **'Begin adventure'**
  String get beginAdventureAction;

  /// Model selection description.
  ///
  /// In en, this message translates to:
  /// **'Latest recommended DeepSeek V4.1 Flash · multimodal · deep thinking supported'**
  String get deepSeekFlashModelSubtitle;

  /// Model selection description.
  ///
  /// In en, this message translates to:
  /// **'Legacy model; migration to DeepSeek V4.1 Flash is recommended'**
  String get deepSeekLegacyModelSubtitle;

  /// Character status interface label.
  ///
  /// In en, this message translates to:
  /// **'Delete status'**
  String get deleteDetectedStatusTitle;

  /// Character status dialog message.
  ///
  /// In en, this message translates to:
  /// **'Delete the status “{name}”?'**
  String confirmDeleteDetectedStatus(String name);

  /// Character status interface label.
  ///
  /// In en, this message translates to:
  /// **'Status name *'**
  String get statusNameLabel;

  /// Character status interface label.
  ///
  /// In en, this message translates to:
  /// **'For example: Sanity (SAN), affinity, corruption, hunger'**
  String get statusNameExamples;

  /// Character status interface label.
  ///
  /// In en, this message translates to:
  /// **'Value type:'**
  String get measurementModeLabel;

  /// Character status interface label.
  ///
  /// In en, this message translates to:
  /// **'Numeric gauge (0–100)'**
  String get numericGaugeMode;

  /// Character status interface label.
  ///
  /// In en, this message translates to:
  /// **'Phase description'**
  String get phaseDescriptionMode;

  /// Character status interface label.
  ///
  /// In en, this message translates to:
  /// **'Current value'**
  String get currentValueLabel;

  /// Character status interface label.
  ///
  /// In en, this message translates to:
  /// **'Maximum value'**
  String get maxValueLabel;

  /// Character status interface label.
  ///
  /// In en, this message translates to:
  /// **'Current phase / description'**
  String get currentPhaseLabel;

  /// Character status interface label.
  ///
  /// In en, this message translates to:
  /// **'For example: Normal, mildly corrupted, tipsy, enraged'**
  String get currentPhaseExamples;

  /// Character status interface label.
  ///
  /// In en, this message translates to:
  /// **'Choose status icon:'**
  String get chooseStatusIcon;

  /// Character status interface label.
  ///
  /// In en, this message translates to:
  /// **'Check rule / story instructions (optional)'**
  String get statusRuleLabel;

  /// Character status interface label.
  ///
  /// In en, this message translates to:
  /// **'For example: panic below 20; a successful roll preserves sanity, while a failed roll causes hallucinations'**
  String get statusRuleHint;

  /// Character status interface label.
  ///
  /// In en, this message translates to:
  /// **'Story importance:'**
  String get storyImportanceLabel;

  /// Character status interface label.
  ///
  /// In en, this message translates to:
  /// **'Enter a status name.'**
  String get statusNameRequiredError;

  /// Character status interface label.
  ///
  /// In en, this message translates to:
  /// **'Add status'**
  String get addDetectedStatusAction;

  /// Character status count.
  ///
  /// In en, this message translates to:
  /// **'Custom statuses ({count})'**
  String detectedStatusesCount(int count);

  /// Character status interface label.
  ///
  /// In en, this message translates to:
  /// **'Combat and adventure attributes'**
  String get combatAdventureMatrix;

  /// Character status interface label.
  ///
  /// In en, this message translates to:
  /// **'Physical attack (ATK)'**
  String get physicalAttackStat;

  /// Character status interface label.
  ///
  /// In en, this message translates to:
  /// **'Base defense (DEF)'**
  String get baseDefenseStat;

  /// Character status interface label.
  ///
  /// In en, this message translates to:
  /// **'Agility (SPD)'**
  String get agilitySpeedStat;

  /// Character status interface label.
  ///
  /// In en, this message translates to:
  /// **'Gold'**
  String get goldStat;

  /// Character status interface label.
  ///
  /// In en, this message translates to:
  /// **'Available skill points'**
  String get availableSkillPointsStat;

  /// Character status interface label.
  ///
  /// In en, this message translates to:
  /// **'Current scene coordinates'**
  String get currentSceneCoordinatesStat;

  /// Character status interface label.
  ///
  /// In en, this message translates to:
  /// **'Open inventory'**
  String get openInventoryAction;

  /// Character status interface label.
  ///
  /// In en, this message translates to:
  /// **'📜 Identity and role'**
  String get profileIdentityTitle;

  /// Character status interface label.
  ///
  /// In en, this message translates to:
  /// **'📖 Background and history'**
  String get profileBackgroundTitle;

  /// Character status interface label.
  ///
  /// In en, this message translates to:
  /// **'🌍 Worldview'**
  String get profileWorldviewTitle;

  /// Character status interface label.
  ///
  /// In en, this message translates to:
  /// **'🎭 Personality'**
  String get profilePersonalityTitle;

  /// Character status interface label.
  ///
  /// In en, this message translates to:
  /// **'🤝 Bonds and relationships'**
  String get profileRelationshipsTitle;

  /// Character status interface label.
  ///
  /// In en, this message translates to:
  /// **'✨ Appearance'**
  String get profileAppearanceTitle;

  /// Character status interface label.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get checkAction;

  /// Character level and role summary.
  ///
  /// In en, this message translates to:
  /// **'Lv. {level} · {role}'**
  String levelRoleSummary(int level, String role);

  /// Character status sheet interface text.
  ///
  /// In en, this message translates to:
  /// **'Edit status'**
  String get editDetectedStatusTitle;

  /// Character status sheet interface text.
  ///
  /// In en, this message translates to:
  /// **'No custom statuses yet'**
  String get noCustomDetectedStatuses;

  /// Character status sheet interface text.
  ///
  /// In en, this message translates to:
  /// **'Create any adventure status, such as sanity (SAN), affinity, corruption, hunger, or magic overload.'**
  String get detectedStatusesEmptyDescription;

  /// Character status sheet interface text.
  ///
  /// In en, this message translates to:
  /// **'Energy'**
  String get energyLabel;

  /// Character status sheet interface text.
  ///
  /// In en, this message translates to:
  /// **'Combat attributes'**
  String get combatStatsTitle;

  /// Character status sheet interface text.
  ///
  /// In en, this message translates to:
  /// **'Current value: '**
  String get currentValuePrefix;

  /// Character status sheet interface text.
  ///
  /// In en, this message translates to:
  /// **'Current phase / thought'**
  String get currentPhaseWithThoughtsLabel;

  /// Character status sheet interface text.
  ///
  /// In en, this message translates to:
  /// **'(Phase check has not triggered yet)'**
  String get phaseNotTriggered;

  /// Status check rule display.
  ///
  /// In en, this message translates to:
  /// **'📌 Rule: {rule}'**
  String statusRulePrefix(String rule);

  /// Character status sheet interface text.
  ///
  /// In en, this message translates to:
  /// **'Companions'**
  String get companionsTab;

  /// Character status sheet interface text.
  ///
  /// In en, this message translates to:
  /// **'Equipment'**
  String get equipmentTab;

  /// Character status sheet interface text.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTab;

  /// Character status and inventory presentation text.
  ///
  /// In en, this message translates to:
  /// **'Current area: {scene}'**
  String currentExplorationRegion(String scene);

  /// Character status and inventory presentation text.
  ///
  /// In en, this message translates to:
  /// **'Main adventurer · Chapter {chapter}'**
  String mainStoryChapter(int chapter);

  /// Character status and inventory presentation text.
  ///
  /// In en, this message translates to:
  /// **'Relationship: {relation}'**
  String relationshipLabel(String relation);

  /// Character status and inventory presentation text.
  ///
  /// In en, this message translates to:
  /// **'❤️ Affinity: {affinity}'**
  String affinityScoreLabel(int affinity);

  /// Character status and inventory presentation text.
  ///
  /// In en, this message translates to:
  /// **'Health (HP)'**
  String get healthPointsLabel;

  /// Character status and inventory presentation text.
  ///
  /// In en, this message translates to:
  /// **'Vitality'**
  String get lifeForceLabel;

  /// Character status and inventory presentation text.
  ///
  /// In en, this message translates to:
  /// **'Magic (MP)'**
  String get magicPointsLabel;

  /// Character status and inventory presentation text.
  ///
  /// In en, this message translates to:
  /// **'Focus'**
  String get focusLabel;

  /// Character status and inventory presentation text.
  ///
  /// In en, this message translates to:
  /// **'Action energy'**
  String get actionEnergyLabel;

  /// Character status and inventory presentation text.
  ///
  /// In en, this message translates to:
  /// **'⚠️ Tired'**
  String get tiredStatus;

  /// Character status and inventory presentation text.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get goodStatus;

  /// Character status and inventory presentation text.
  ///
  /// In en, this message translates to:
  /// **'Experience (EXP)'**
  String get experienceLabel;

  /// Character status and inventory presentation text.
  ///
  /// In en, this message translates to:
  /// **'{count} to next level'**
  String nextLevelExperience(int count);

  /// Character status and inventory presentation text.
  ///
  /// In en, this message translates to:
  /// **'{count} points'**
  String skillPointsValue(int count);

  /// Character status and inventory presentation text.
  ///
  /// In en, this message translates to:
  /// **'⚔️ Equipped gear ({count})'**
  String equippedGearCount(int count);

  /// Character status and inventory presentation text.
  ///
  /// In en, this message translates to:
  /// **'No equipped gear. Find equipment in your inventory or a shop to improve combat ability.'**
  String get noEquippedGear;

  /// Character status and inventory presentation text.
  ///
  /// In en, this message translates to:
  /// **'Slot: {slot} · Quality: {quality}'**
  String gearSlotQuality(String slot, String quality);

  /// Character status and inventory presentation text.
  ///
  /// In en, this message translates to:
  /// **'🎒 Carried items and materials'**
  String get carriedItemsTitle;

  /// Character status and inventory presentation text.
  ///
  /// In en, this message translates to:
  /// **'No special items in this inventory.'**
  String get noCarriedItems;

  /// Character status and inventory presentation text.
  ///
  /// In en, this message translates to:
  /// **'📦 Shared party inventory:'**
  String get sharedPartyInventory;

  /// Custom character status editor instruction.
  ///
  /// In en, this message translates to:
  /// **'Track a custom status in the adventure, with gauges, check rules and dice rolls.'**
  String get detectedStatusFormDescription;

  /// Custom character status editor instruction.
  ///
  /// In en, this message translates to:
  /// **'💡 Preset ideas (tap to fill in):'**
  String get statusPresetsHeading;

  /// Character profile and status display text.
  ///
  /// In en, this message translates to:
  /// **'Explorer'**
  String get explorerRole;

  /// Character profile and status display text.
  ///
  /// In en, this message translates to:
  /// **'Starting town'**
  String get startingTown;

  /// Character profile and status display text.
  ///
  /// In en, this message translates to:
  /// **'An adaptable adventurer who explores unknown frontiers and makes story decisions.'**
  String get defaultProtagonistProfile;

  /// Character profile and status display text.
  ///
  /// In en, this message translates to:
  /// **'Set out into a turbulent world and discover how your fate unfolds.'**
  String get defaultProtagonistBackground;

  /// Character profile and status display text.
  ///
  /// In en, this message translates to:
  /// **'An immersive role-playing world that changes as the story develops.'**
  String get defaultWorldviewDescription;

  /// Character profile and status display text.
  ///
  /// In en, this message translates to:
  /// **'A reserved personality whose true wishes emerge throughout the journey.'**
  String get defaultCompanionPersonality;

  /// Character information tag.
  ///
  /// In en, this message translates to:
  /// **'Gender: {value}'**
  String genderTag(String value);

  /// Character information tag.
  ///
  /// In en, this message translates to:
  /// **'Height: {value}'**
  String heightTag(String value);

  /// Character information tag.
  ///
  /// In en, this message translates to:
  /// **'Hair: {value}'**
  String hairstyleTag(String value);

  /// Character information tag.
  ///
  /// In en, this message translates to:
  /// **'Skin tone: {value}'**
  String skinToneTag(String value);

  /// Character information tag.
  ///
  /// In en, this message translates to:
  /// **'Face: {value}'**
  String facialFeaturesTag(String value);

  /// Character profile and status display text.
  ///
  /// In en, this message translates to:
  /// **'💚 Healthy'**
  String get aliveStatus;

  /// Character profile and status display text.
  ///
  /// In en, this message translates to:
  /// **'💀 Incapacitated'**
  String get incapacitatedStatus;

  /// Companion relationship and affinity summary.
  ///
  /// In en, this message translates to:
  /// **'Relationship: {relation}. Current affinity: {affinity}/100.'**
  String companionRelationshipSummary(String relation, int affinity);

  /// Dice check interface or result text.
  ///
  /// In en, this message translates to:
  /// **'Critical success! A perfect result.'**
  String get diceCriticalSuccess;

  /// Dice check interface or result text.
  ///
  /// In en, this message translates to:
  /// **'Critical failure! A serious mishap or backlash.'**
  String get diceCriticalFailure;

  /// Dice check interface or result text.
  ///
  /// In en, this message translates to:
  /// **'Check passed! You resist the effect and remain stable.'**
  String get diceSuccess;

  /// Dice check interface or result text.
  ///
  /// In en, this message translates to:
  /// **'Check failed! You are affected by a negative effect.'**
  String get diceFailure;

  /// Dice check interface or result text.
  ///
  /// In en, this message translates to:
  /// **'Critical success! Breakthrough achieved!'**
  String get diceCheckCriticalSuccess;

  /// Dice check interface or result text.
  ///
  /// In en, this message translates to:
  /// **'Critical failure! The check failed completely.'**
  String get diceCheckCriticalFailure;

  /// Dice check interface or result text.
  ///
  /// In en, this message translates to:
  /// **'Check passed! Your condition remains stable.'**
  String get diceCheckPassed;

  /// Dice check interface or result text.
  ///
  /// In en, this message translates to:
  /// **'Check failed! You suffer an adverse effect.'**
  String get diceCheckFailed;

  /// Dice check interface or result text.
  ///
  /// In en, this message translates to:
  /// **'Target value: {current} / {maximum}'**
  String diceTargetValue(int current, int maximum);

  /// Dice check interface or result text.
  ///
  /// In en, this message translates to:
  /// **'Current status: {status}'**
  String diceCurrentStatus(String status);

  /// Dice check interface or result text.
  ///
  /// In en, this message translates to:
  /// **'Check rule: {rule}'**
  String diceRuleDescription(String rule);

  /// Dice check interface or result text.
  ///
  /// In en, this message translates to:
  /// **'D100 percentile die'**
  String get d100PercentileDie;

  /// Dice check interface or result text.
  ///
  /// In en, this message translates to:
  /// **'D20 die'**
  String get d20Die;

  /// Dice check interface or result text.
  ///
  /// In en, this message translates to:
  /// **'Roll check'**
  String get rollCheckAction;

  /// Dice check interface or result text.
  ///
  /// In en, this message translates to:
  /// **'Roll again'**
  String get rerollAction;

  /// Dice check interface or result text.
  ///
  /// In en, this message translates to:
  /// **'Add result to adventure'**
  String get syncResultToAdventure;

  /// Dice check interface or result text.
  ///
  /// In en, this message translates to:
  /// **'{icon} Roll: {value} {denominator}'**
  String diceResultPoints(String icon, int value, String denominator);

  /// Dice check interface or result text.
  ///
  /// In en, this message translates to:
  /// **'The result will be sent as a user message.'**
  String get diceResultWillBeSent;

  /// Dice check interface or result text.
  ///
  /// In en, this message translates to:
  /// **'[Status check] {character} rolled “{status}”: 🎲 {roll} ({target}) → [{verdict}]. {rule}'**
  String diceResultMessage(String status, String rule, String character,
      int roll, String target, String verdict);

  /// Inventory item classification and empty state label.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get allItemsFilter;

  /// Inventory item classification and empty state label.
  ///
  /// In en, this message translates to:
  /// **'Consumables'**
  String get consumableItemType;

  /// Inventory item classification and empty state label.
  ///
  /// In en, this message translates to:
  /// **'Equipment'**
  String get equipmentItemType;

  /// Inventory item classification and empty state label.
  ///
  /// In en, this message translates to:
  /// **'Materials'**
  String get materialItemType;

  /// Inventory item classification and empty state label.
  ///
  /// In en, this message translates to:
  /// **'Quest items'**
  String get questItemType;

  /// Inventory item classification and empty state label.
  ///
  /// In en, this message translates to:
  /// **'Weapon'**
  String get weaponSlot;

  /// Inventory item classification and empty state label.
  ///
  /// In en, this message translates to:
  /// **'Armor'**
  String get armorSlot;

  /// Inventory item classification and empty state label.
  ///
  /// In en, this message translates to:
  /// **'Accessory'**
  String get accessorySlot;

  /// Inventory item classification and empty state label.
  ///
  /// In en, this message translates to:
  /// **'Special'**
  String get specialSlot;

  /// Inventory item classification and empty state label.
  ///
  /// In en, this message translates to:
  /// **'Common'**
  String get commonQuality;

  /// Inventory item classification and empty state label.
  ///
  /// In en, this message translates to:
  /// **'Uncommon'**
  String get uncommonQuality;

  /// Inventory item classification and empty state label.
  ///
  /// In en, this message translates to:
  /// **'Rare'**
  String get rareQuality;

  /// Inventory item classification and empty state label.
  ///
  /// In en, this message translates to:
  /// **'Epic'**
  String get epicQuality;

  /// Inventory item classification and empty state label.
  ///
  /// In en, this message translates to:
  /// **'Legendary'**
  String get legendaryQuality;

  /// Inventory item classification and empty state label.
  ///
  /// In en, this message translates to:
  /// **'Your inventory is empty'**
  String get emptyInventoryTitle;

  /// Inventory item classification and empty state label.
  ///
  /// In en, this message translates to:
  /// **'Items you find in the story will appear here.'**
  String get emptyInventoryDescription;

  /// Chat reasoning and generation state label.
  ///
  /// In en, this message translates to:
  /// **'Thinking deeply…'**
  String get deepThinkingStatus;

  /// Chat reasoning and generation state label.
  ///
  /// In en, this message translates to:
  /// **'Thinking process (tap to collapse)'**
  String get reasoningExpandedLabel;

  /// Chat reasoning and generation state label.
  ///
  /// In en, this message translates to:
  /// **'Thinking finished (tap to view reasoning)'**
  String get reasoningCollapsedLabel;

  /// Chat reasoning and generation state label.
  ///
  /// In en, this message translates to:
  /// **'Thinking…'**
  String get thinkingInProgressStatus;

  /// Chat reasoning and generation state label.
  ///
  /// In en, this message translates to:
  /// **'(No record)'**
  String get reasoningUnavailableLabel;

  /// Chat reasoning and generation state label.
  ///
  /// In en, this message translates to:
  /// **'Copy reasoning'**
  String get copyReasoningAction;

  /// Chat reasoning and generation state label.
  ///
  /// In en, this message translates to:
  /// **'Writing story…'**
  String get writingStoryStatus;

  /// Dialogue response density setting label.
  ///
  /// In en, this message translates to:
  /// **'Adjust scene reply length'**
  String get dialogueReplyLengthSettingsTitle;

  /// Dialogue response density setting label.
  ///
  /// In en, this message translates to:
  /// **'Selected: {id} · {name} ({range})'**
  String dialogueCurrentSelection(String id, String name, String range);

  /// Dialogue response density setting label.
  ///
  /// In en, this message translates to:
  /// **'{minWords}+ words'**
  String dialogueWordsAbove(int minWords);

  /// Dialogue response density setting label.
  ///
  /// In en, this message translates to:
  /// **'Fast'**
  String get dialogueLevelFast;

  /// Dialogue response density setting label.
  ///
  /// In en, this message translates to:
  /// **'Concise'**
  String get dialogueLevelConcise;

  /// Dialogue response density setting label.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get dialogueLevelStandard;

  /// Dialogue response density setting label.
  ///
  /// In en, this message translates to:
  /// **'Detailed'**
  String get dialogueLevelDetailed;

  /// Dialogue response density setting label.
  ///
  /// In en, this message translates to:
  /// **'In depth'**
  String get dialogueLevelDeep;

  /// Dialogue response density setting label.
  ///
  /// In en, this message translates to:
  /// **'Production'**
  String get dialogueLevelProduction;

  /// Dialogue response density setting label.
  ///
  /// In en, this message translates to:
  /// **'Keeps only key feedback for quick confirmation.'**
  String get dialogueLevelFastDesc;

  /// Dialogue response density setting label.
  ///
  /// In en, this message translates to:
  /// **'Brief story progress for lightweight interaction.'**
  String get dialogueLevelConciseDesc;

  /// Dialogue response density setting label.
  ///
  /// In en, this message translates to:
  /// **'Default mode balancing speed and immersion.'**
  String get dialogueLevelStandardDesc;

  /// Dialogue response density setting label.
  ///
  /// In en, this message translates to:
  /// **'More complete descriptions and interaction.'**
  String get dialogueLevelDetailedDesc;

  /// Dialogue response density setting label.
  ///
  /// In en, this message translates to:
  /// **'Emphasizes buildup, psychology and layered scenes.'**
  String get dialogueLevelDeepDesc;

  /// Dialogue response density setting label.
  ///
  /// In en, this message translates to:
  /// **'Long-form output for serious writing.'**
  String get dialogueLevelProductionDesc;

  /// Dialogue response density setting label.
  ///
  /// In en, this message translates to:
  /// **'Cannot refresh while generating or when the scene is unavailable.'**
  String get adventureRefreshUnavailable;

  /// Adventure session interface text.
  ///
  /// In en, this message translates to:
  /// **'Offline — network connection unavailable'**
  String get sessionOfflineHint;

  /// Adventure session interface text.
  ///
  /// In en, this message translates to:
  /// **'Describe your action or dialogue…'**
  String get sessionInputHint;

  /// Adventure session interface text.
  ///
  /// In en, this message translates to:
  /// **'Swipe right to retry · swipe left to delete · long press to edit or bookmark'**
  String get messageGestureHint;

  /// Adventure session interface text.
  ///
  /// In en, this message translates to:
  /// **'Adventure Assistant'**
  String get adventureAssistantName;

  /// Adventure session interface text.
  ///
  /// In en, this message translates to:
  /// **'Me'**
  String get currentUserDisplayName;

  /// Adventure session interface text.
  ///
  /// In en, this message translates to:
  /// **'Unknown region'**
  String get unknownRegion;

  /// Adventure session interface text.
  ///
  /// In en, this message translates to:
  /// **'Deep thinking'**
  String get deepThinkingBadge;

  /// Adventure session interface text.
  ///
  /// In en, this message translates to:
  /// **'Supporting character'**
  String get supportingCharacterRole;

  /// Adventure session interface text.
  ///
  /// In en, this message translates to:
  /// **'Automatically switch character'**
  String get autoSwitchCharacterTooltip;

  /// Chat and adventure status text.
  ///
  /// In en, this message translates to:
  /// **'Generating options and settling the turn…'**
  String get sessionSettlingStatus;

  /// Chat and adventure status text.
  ///
  /// In en, this message translates to:
  /// **'AI reply'**
  String get aiReplyLabel;

  /// Resource Studio section operation feedback.
  ///
  /// In en, this message translates to:
  /// **'{title} validation passed'**
  String sectionValidationPassed(String title);

  /// Resource Studio section operation feedback.
  ///
  /// In en, this message translates to:
  /// **'{title} validation failed: {count, plural, =0{no issues} one{# issue} other{# issues}}'**
  String sectionValidationFailed(String title, int count);

  /// Resource Studio section operation feedback.
  ///
  /// In en, this message translates to:
  /// **'Validation complete'**
  String get sectionValidationComplete;

  /// Resource Studio section operation feedback.
  ///
  /// In en, this message translates to:
  /// **'{title} regenerated {completed} of {total} parts'**
  String sectionRegenerated(String title, int completed, int total);

  /// Resource Studio section operation feedback.
  ///
  /// In en, this message translates to:
  /// **'Generation stopped for {title}: {error}'**
  String sectionRegenerationFailed(String title, String error);

  /// Resource Studio section operation feedback.
  ///
  /// In en, this message translates to:
  /// **'Generation complete'**
  String get sectionGenerationComplete;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja', 'ko', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hans':
            return AppLocalizationsZhHans();
          case 'Hant':
            return AppLocalizationsZhHant();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
