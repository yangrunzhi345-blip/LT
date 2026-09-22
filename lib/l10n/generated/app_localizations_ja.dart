// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'LT 霊境';

  @override
  String get pageLoadError => 'ページの読み込みエラー';

  @override
  String get reloadAction => '再読み込み';

  @override
  String get loadingEnvironment => '環境を読み込み中...';

  @override
  String testingProviderConnection(String provider) {
    return '$provider の接続をテスト中...';
  }

  @override
  String get modelConnectionFailed => 'モデルへの接続に失敗しました。設定を確認してください';

  @override
  String get apiKeyNotConfiguredPrompt => 'APIキーがまだ設定されていません。設定画面で構成してください';

  @override
  String get goToSettings => '設定へ移動';

  @override
  String get createAdventureFailed => 'シーンの作成に失敗しました。後でもう一度お試しください';

  @override
  String get navExplore => '探索';

  @override
  String get navLibrary => '資料庫';

  @override
  String get navSettings => '設定';

  @override
  String get sidebarNewAdventure => '新しい冒険';

  @override
  String get sidebarRecent => '最近の対話';

  @override
  String get sidebarManageConversations => '対話を一括管理';

  @override
  String get sidebarEmptyConversations => '対話履歴はありません';

  @override
  String get sidebarUnnamedScene => '無題のシーン';

  @override
  String get sidebarDeleteDialogTitle => 'シーンの対話を削除';

  @override
  String sidebarDeleteDialogMessage(String title) {
    return '「$title」を削除してもよろしいですか？\n削除された対話履歴とストーリー展開は復元できません。';
  }

  @override
  String get sidebarReturnHome => '探索ホールに戻る';

  @override
  String get sidebarExpand => 'サイドバーを展開';

  @override
  String get sidebarCollapse => 'サイドバーを折りたたむ';

  @override
  String get sidebarClose => 'サイドバーを閉じる';

  @override
  String get brandSubtitle => '物語と世界の進化工房';

  @override
  String get serviceConnected => '接続済み';

  @override
  String get serviceNotConfigured => 'キー未設定';

  @override
  String get officialOnline => 'オンライン';

  @override
  String get languageSetupTitle => '言語を選択';

  @override
  String get languageSetupSubtitle => 'アプリケーションの表示言語を選択してください';

  @override
  String get languageSettingTitle => '言語';

  @override
  String get languageSettingSubtitle => 'アプリケーションの表示言語';

  @override
  String get confirmAction => '確定';

  @override
  String get cancelAction => 'キャンセル';

  @override
  String get deleteAction => '削除';

  @override
  String get saveAction => '保存';

  @override
  String get continueAction => '次へ';

  @override
  String get closeAction => '閉じる';

  @override
  String get doneAction => '完了';

  @override
  String get editAction => '編集';

  @override
  String get retryAction => '再試行';

  @override
  String get copyAction => 'コピー';

  @override
  String get settingsCenter => '設定センター';

  @override
  String get settingsSystemConfig => 'システム構成';

  @override
  String get settingsReturnHome => 'ホールに戻る';

  @override
  String get settingsReturnList => '設定一覧に戻る';

  @override
  String get settingsPreferencesCategory => '設定カテゴリ';

  @override
  String get settingsCoreEngine => '霊境コアエンジン';

  @override
  String get settingsStorageType => 'SQLite · ローカル暗号化優先';

  @override
  String get tabModelApi => 'モデルとAPI';

  @override
  String get tabModelApiSubtitle => 'プロバイダーとAPIキー設定';

  @override
  String get tabSessionParams => 'セッションパラメータ';

  @override
  String get tabSessionParamsSubtitle => 'サンプリングと推論思考';

  @override
  String get tabThemeAppearance => 'テーマと外観';

  @override
  String get tabThemeAppearanceSubtitle => 'ライト/ダークとテーマカラー';

  @override
  String get tabDataManagement => 'データ管理';

  @override
  String get tabDataManagementSubtitle => 'Token統計とストレージ';

  @override
  String get configCategory => '設定分類';

  @override
  String get apiServiceConnected => 'LLMサービス接続中';

  @override
  String get apiServiceConnectedDesc => 'クリックしてプロバイダー、モデル、エンドポイントを管理';

  @override
  String get apiServiceDisconnectedDesc => 'APIキーを設定して推論を開始してください';

  @override
  String get providerConfigTitle => 'モデルプロバイダーとAPI設定';

  @override
  String get providerConfigSubtitle => 'モデル提供元、エンドポイントURL、安全なキーを設定します';

  @override
  String get testConnection => '接続テスト';

  @override
  String get testingConnection => 'テスト中...';

  @override
  String get inputApiKeyHint => '有効なAPIキーを入力してください';

  @override
  String connectionSuccess(int time) {
    return '接続に成功しました！ 所要時間 ${time}ms、良好な状態です。';
  }

  @override
  String get connectionFailed => '接続に失敗しました。キーとネットワーク接続を確認してください。';

  @override
  String connectionFailedWithReason(String error) {
    return '接続エラー: $error';
  }

  @override
  String get apiKeyLabel => 'APIキー';

  @override
  String get apiKeyPlaceholder => 'APIキーを入力してください';

  @override
  String get customEndpointLabel => 'カスタムエンドポイント (Base URL)';

  @override
  String get customEndpointPlaceholder => 'https://api.example.com/v1';

  @override
  String get modelLabel => 'モデル名';

  @override
  String get modelPlaceholder => 'モデル名を入力';

  @override
  String get customModelNote => 'カスタムモデルエンドポイントを使用中';

  @override
  String get modelParamsSectionTitle => 'セッションモデルパラメータ';

  @override
  String get modelParamsSectionSubtitle => '生成温度、コンテキスト予算、思考推論モードを調整します';

  @override
  String get systemPromptLabel => 'カスタムシステムプロンプト';

  @override
  String get systemPromptPlaceholder => 'AIの役割やスタイルを指示するプロンプトを入力...';

  @override
  String get authorsNoteLabel => '作者ノート (Author\'s Note)';

  @override
  String get authorsNotePlaceholder => '直近のターンに強力なコンテキスト指示を挿入...';

  @override
  String authorsNoteDepthLabel(int depth) {
    return '挿入深度：末尾から $depth ターン前';
  }

  @override
  String authorsNoteFrequencyLabel(int freq) {
    return '発動頻度：$freq ターンごと';
  }

  @override
  String get dialogueLevelLabel => '文体スタイルと深度';

  @override
  String temperatureLabel(String value) {
    return 'サンプリング温度 (ランダム度): $value';
  }

  @override
  String get enableThinkingLabel => 'ディープシンキング (推論) を有効化';

  @override
  String get enableThinkingSubtitle => '推論モデルが最終テキスト出力前に思考プロセスを展開します';

  @override
  String get reasoningEffortLabel => '思考の強さ (Reasoning Effort)';

  @override
  String get quickModeLabel => 'クイックモード';

  @override
  String get quickModeSubtitle => 'ストリーミング表示をスキップし、素早く結果を表示';

  @override
  String get appearanceSectionTitle => '外観とテーマ設定';

  @override
  String get appearanceSectionSubtitle => 'インターフェースカラー、ダークモード、フォントサイズをカスタマイズ';

  @override
  String get themeModeLabel => 'テーマモード';

  @override
  String get themeLight => 'ライト';

  @override
  String get themeDark => 'ダーク';

  @override
  String get themeSystem => 'システム連動';

  @override
  String get themeColorPalette => 'テーマカラー';

  @override
  String get themeColorPaletteHint => 'タップして即時切り替え';

  @override
  String chatFontSizeLabel(int size) {
    return 'ストーリー本文フォントサイズ: $size pt';
  }

  @override
  String get chatFontCompact => 'コンパクト';

  @override
  String get chatFontStandard => '標準';

  @override
  String get chatFontSpacious => 'ゆったり';

  @override
  String get previewTypographyTitle => 'タイポグラフィのリアルタイムプレビュー';

  @override
  String get previewTypographySample =>
      '「霊境の物語」—— 幾重にも交錯する世界線の中で、あなたのあらゆる選択が運命に波紋を広げます。蠢く地下都市、天空に浮かぶ機械の遺跡、すべての伝説はここから始まります。';

  @override
  String get readingScrollTitle => '読書とスクロール設定';

  @override
  String get readingScrollSubtitle => '生成時の画面スクロール動作をコントロールします';

  @override
  String get autoScrollLabel => '生成時に自動追従スクロール';

  @override
  String get autoScrollSubtitleOn => '有効：新しい文章が生成されるたび、画面が一番下まで自動スクロールします。';

  @override
  String get autoScrollSubtitleOff =>
      '推奨（読書優先）：画面が安定し、先頭から集中して読むことができます。スクロールは手動操作です。';

  @override
  String get dataManagementTitle => 'データ管理と利用状況';

  @override
  String get dataManagementSubtitle => 'Token消費量、TTS音声読み上げ、ストレージの確認と管理';

  @override
  String get tokenUsageTitle => 'ローカル Token 消費量の見積もり';

  @override
  String get sessionTokensLabel => '現在のセッション消費量';

  @override
  String get totalTokensLabel => '累計保存済み Token';

  @override
  String get readAloudSectionTitle => '音声読み上げ (TTS)';

  @override
  String get readAloudSupportedPlatform =>
      '現在の環境はシステム音声読み上げに対応しています。対話や工房で利用可能です。';

  @override
  String get readAloudUnsupportedPlatform => '現在の環境は音声読み上げに対応していません。';

  @override
  String get readAloudEnable => '音声読み上げを有効化';

  @override
  String get readAloudEnableSubtitle => '対話、創作スタジオ、組み立てプレビューで本文を読み上げます';

  @override
  String get readAloudAutoRead => '完了時に自動読み上げ';

  @override
  String get readAloudAutoReadSubtitle => 'AIがストーリーを生成完了した際、自動的に音声を再生します';

  @override
  String get readAloudRate => '読み上げ速度';

  @override
  String get readAloudPitch => '声の高さ';

  @override
  String get readAloudVolume => '音量';

  @override
  String get readAloudLanguage => '読み上げ言語';

  @override
  String get readAloudAutoDetect => '自動検出';

  @override
  String get readAloudAutoDetectHint => '本文テキストに基づいて最適なシステム音声を自動選択します。';

  @override
  String get readAloudFixedHint => 'すべての本文が選択された固定言語で読み上げられます。';

  @override
  String get readAloudUnsupportedLanguage => '（非対応）';

  @override
  String readAloudAvailableLanguagesCount(int count) {
    return '利用可能なシステム音声：$count 種類';
  }

  @override
  String get readAloudDisabledInSettings => '音声読み上げは設定で無効になっています';

  @override
  String get readAloudStop => '読み上げ停止';

  @override
  String get readAloudStart => '読み上げる';

  @override
  String get diagnosticExportTitle => '診断データの出力';

  @override
  String get diagnosticExportSubtitle =>
      '現在の分岐の直近30ターンのみ出力します。APIキーや思考ログは含まれません。';

  @override
  String get exportDiagnosticJson => '診断セッション JSON を出力';

  @override
  String get cacheStorageTitle => 'キャッシュとストレージ管理';

  @override
  String get clearCache => '一時キャッシュを消去';

  @override
  String get clearCacheSuccess => '一時キャッシュを消去し、カウンターをリセットしました';

  @override
  String get clearAllData => 'すべてのローカルデータを削除';

  @override
  String get clearDataDialogTitle => '全ローカルデータのリセット';

  @override
  String get clearDataDialogMessage =>
      'ローカルのすべての冒険、カード、キャッシュを削除してもよろしいですか？\nこの操作は元に戻せません。';

  @override
  String get exportChatTitle => '対話を出力';

  @override
  String get importChatTitle => '対話をインポート';

  @override
  String get dashboardHeroTitle => '霊境 · 探索と物語の工房';

  @override
  String get dashboardHeroSubtitle => 'インタラクティブノベルと没入型RPGの物語空間';

  @override
  String get dashboardWizardCardTitle => '4ステップ作成ウィザード';

  @override
  String get dashboardWizardCardDesc => '白紙から世界観、キャラクター、プロローグ、初期行動を自由に設定します。';

  @override
  String get dashboardWizardCardAction => 'ウィザードを開始';

  @override
  String get dashboardPresetCardTitle => 'プリセットシナリオ工房';

  @override
  String get dashboardPresetCardDesc => '構築済みの冒険スクリプトを閲覧し、ワンクリックですぐに冒険を開始。';

  @override
  String get dashboardPresetCardAction => 'プリセットを見る';

  @override
  String get dashboardLibraryCardTitle => '資料庫';

  @override
  String get dashboardLibraryCardDesc => '構想した世界観、キャラクター、NPC档案を閲覧・管理します。';

  @override
  String get dashboardLibraryCardAction => '資料庫を管理';

  @override
  String get dashboardSettingsCardTitle => 'システム設定センター';

  @override
  String get dashboardSettingsCardDesc => 'モデル接続設定、外観テーマ、履歴データを管理します。';

  @override
  String get dashboardSettingsCardAction => '設定を開く';

  @override
  String get recentAdventuresTitle => '最近の冒険';

  @override
  String get noRecentAdventures => 'まだ冒険履歴はありません。ウィザードを起動して新たな旅を始めましょう。';

  @override
  String get continueAdventure => '冒険を再開';

  @override
  String get featuredWorldviews => '注目の世界観';

  @override
  String get featuredCharacters => '注目のキャラクター';

  @override
  String get resourceLibraryTitle => '資料庫';

  @override
  String get resourceLibrarySubtitle => '世界観、キャラクターカード、シナリオテンプレートを閲覧・管理';

  @override
  String get createResourceAction => '新規リソース';

  @override
  String get searchResources => 'リソースを検索...';

  @override
  String get allResources => 'すべて';

  @override
  String get worldviewsTab => '世界観';

  @override
  String get charactersTab => 'キャラクター';

  @override
  String get templatesTab => 'テンプレート';

  @override
  String get recycleBinTitle => 'ゴミ箱';

  @override
  String get emptyRecycleBin => 'ゴミ箱は空です';

  @override
  String get restoreAction => '復元';

  @override
  String get permanentlyDelete => '完全に削除';

  @override
  String get resourceStudioTitle => 'リソーススタジオ';

  @override
  String get resourceStudioSubtitle => 'マルチパート段階的創作と容量管理';

  @override
  String get outlineTab => 'アウトライン';

  @override
  String get capacityTab => '容量';

  @override
  String get historyTab => 'リビジョン';

  @override
  String get generatePart => 'コンテンツ生成';

  @override
  String get regeneratePart => '再生成';

  @override
  String get partSaved => '変更を保存しました';

  @override
  String get partSaving => '保存中...';

  @override
  String get assemblyWizardTitle => 'シナリオ組み立てと準備確認';

  @override
  String get assemblyStepWorld => '1. 世界観';

  @override
  String get assemblyStepCharacters => '2. キャラクター設定';

  @override
  String get assemblyStepNpcs => '3. NPC勢力';

  @override
  String get assemblyStepConfig => '4. ルールと導入部';

  @override
  String get assemblyPreviewTitle => '組み立てプレビュー';

  @override
  String get startAdventureAction => '冒険を始める';

  @override
  String get readinessChecking => 'リソースの準備状態を確認中...';

  @override
  String get readinessPassed => 'すべてのリソースが準備完了';

  @override
  String get readinessFailed => 'リソースの準備または圧縮が必要です';

  @override
  String get adventureSessionTitle => '冒険進行中';

  @override
  String get inputActionHint => '次の行動は？ アクションやセリフを入力...';

  @override
  String get sendAction => '送信';

  @override
  String get aiThinking => 'AIが思考中...';

  @override
  String get aiWriting => 'AIが執筆中...';

  @override
  String get diceCheckTitle => 'ダイスチェック判定';

  @override
  String get turnSettling => '現在のターンの選択肢を精算中...';

  @override
  String get bookmarkAdded => 'ブックマークを追加しました';

  @override
  String get bookmarkRemoved => 'ブックマークを解除しました';

  @override
  String get messageCopied => 'メッセージをクリップボードにコピーしました';

  @override
  String get messageEdited => 'メッセージを編集しました';

  @override
  String get chatEditMessage => 'メッセージを編集';

  @override
  String get chatReadAloudUnsupported => 'このプラットフォームでは読み上げに対応していません';

  @override
  String get chatCopyReasoning => '思考過程（思考チェーン）をコピー';

  @override
  String get chatReasoningCopied => '思考過程をクリップボードにコピーしました';

  @override
  String get chatRetryWithModel => '別のモデルで再試行';

  @override
  String get chatFork => 'ここから分岐';

  @override
  String chatBranchCreated(Object branch) {
    return 'ブランチ $branch を作成しました';
  }

  @override
  String get chatDeleteMessage => '削除';

  @override
  String get chatSearchHint => '会話を検索…';

  @override
  String get chatBookmarksOnly => 'ブックマークのみ';

  @override
  String get chatMoreActions => 'その他の操作';

  @override
  String get chatEditStatus => 'ステータスを編集';

  @override
  String get chatDeleteStatus => 'ステータスを削除';

  @override
  String get readAloudPause => '一時停止';

  @override
  String get readAloudPauseRestart => '一時停止（このセグメントの先頭から再開）';

  @override
  String get readAloudResume => '読み上げを再開';

  @override
  String get readAloudPreparing => '読み上げを準備中';

  @override
  String get readAloudPrevious => '前のセグメント';

  @override
  String get readAloudNext => '次のセグメント';

  @override
  String get tokenCurrentScene => '現在のシーンのトークン';

  @override
  String get tokenHistoryTotal => '累計トークン';

  @override
  String get tokenCurrentSceneDescription => '現在のシーンで使用したトークン';

  @override
  String get tokenHistoryDescription => 'ローカルに記録された累計';

  @override
  String get readAloudPlatformSupportedMessage =>
      'このプラットフォームはシステム読み上げに対応しています。会話とスタジオで利用できます。';

  @override
  String get diagnosticExportFailed => '診断のエクスポートに失敗しました。後でもう一度お試しください。';

  @override
  String diagnosticExported(Object path) {
    return '診断セッションをエクスポートしました: $path';
  }

  @override
  String get clearHistoryTitle => '会話履歴を削除';

  @override
  String get clearHistoryMessage =>
      '保存された会話をすべて削除しますか？\nワールド観とキャラクターカードは残りますが、シーンの会話履歴は復元できません。';

  @override
  String get clearHistoryConfirm => '履歴を削除';

  @override
  String get clearHistorySuccess => '会話履歴をすべて削除しました';

  @override
  String get readAloudRateLabel => '読み上げ速度';

  @override
  String get readAloudPitchLabel => '音程';

  @override
  String get readAloudLanguageHintAuto => '各文章に使用できるシステム音声言語を自動選択します。';

  @override
  String get readAloudLanguageHintFixed => 'すべての文章を選択した言語で読み上げます。';

  @override
  String readAloudSupportedCount(Object count) {
    return 'システムで利用可能な音声: $count';
  }

  @override
  String get generationWaiting => 'コンテンツの生成を待っています…';
}
