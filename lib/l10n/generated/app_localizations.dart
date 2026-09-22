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

  /// No description provided for @customEndpointPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'https://api.example.com/v1'**
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
  /// **'Enable Deep Thinking (Reasoning)'**
  String get enableThinkingLabel;

  /// No description provided for @enableThinkingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Support reasoning models to output thinking chains before final prose'**
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
