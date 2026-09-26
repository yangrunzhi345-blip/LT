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
  String get navLibrary => 'ライブラリ';

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
  String get settingsPreferencesCategory => '設定カテゴリー';

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
  String get customEndpointPlaceholder => 'カスタムエンドポイント URL';

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
  String get enableThinkingLabel => 'ディープシンキングモードを有効化 (Deep Thinking)';

  @override
  String get enableThinkingSubtitle =>
      '有効にすると、ストーリー本文の出力前に折りたたみ可能な思考プロセスが出力されます';

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
  String get dashboardLibraryCardTitle => 'ライブラリ';

  @override
  String get dashboardLibraryCardDesc => '構想した世界観、キャラクター、NPC档案を閲覧・管理します。';

  @override
  String get dashboardLibraryCardAction => 'ライブラリを管理';

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
  String get resourceLibraryTitle => 'ライブラリ';

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
  String get wizardWorldviewAiSummary =>
      'ジャンルや中心となるアイデアを入力してください。ここで世界観の草案を作成するか、ライブラリで詳細な世界設定を作成できます。';

  @override
  String get adventureWizardTitle => 'アドベンチャー作成ウィザード';

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

  @override
  String get errorTimeoutTitle => 'リクエストがタイムアウトしました';

  @override
  String get errorTimeoutSuggestion => 'ネットワーク接続を確認して再試行してください';

  @override
  String get errorAuthTitle => '認証に失敗しました';

  @override
  String get errorAuthSuggestion => 'APIキーが有効か確認してください';

  @override
  String get errorRateTitle => 'リクエストが多すぎます';

  @override
  String get errorRateSuggestion => '少し待ってから再試行してください';

  @override
  String get errorApiTitle => 'APIエラー';

  @override
  String get errorApiSuggestion => 'API設定を確認するか、後でもう一度お試しください';

  @override
  String get errorNetworkTitle => 'ネットワークエラー';

  @override
  String get errorNetworkSuggestion => 'ネットワーク接続とAPI設定を確認して再試行してください';

  @override
  String get switchModelRetry => '別のモデルで再試行';

  @override
  String get resourceTrashTooltip => 'ごみ箱';

  @override
  String get resourceCreateShort => '新規作成';

  @override
  String get resourceNpcTab => 'NPC';

  @override
  String get resourceRetryLoad => '再試行';

  @override
  String get resourceEmptyTitle => 'リソースはまだありません';

  @override
  String get resourceNoMatches => '一致するリソースがありません';

  @override
  String get resourceNoSummary => '概要なし';

  @override
  String get resourceMovedToTrash => 'ごみ箱に移動しました';

  @override
  String get refreshRecycleBin => 'ごみ箱を更新';

  @override
  String permanentDeleteMessage(Object title) {
    return '「$title」とその内容は完全に削除され、復元できません。\n続行しますか？';
  }

  @override
  String get readinessBlockedTitle => 'まだ冒険を開始できません';

  @override
  String get acknowledgeAction => '了解';

  @override
  String get staleResourceTitle => 'リソースが変更されました';

  @override
  String get staleResourceMessage => '前回の準備完了後に変更されたリソース：';

  @override
  String get usePreviousReady => '前回の準備完了バージョンで開始しますか？';

  @override
  String get chatImportFormat => '形式';

  @override
  String get chatImportLabel => '会話内容';

  @override
  String get chatImportHint => 'ここに会話内容を貼り付け…';

  @override
  String get chatImportSuccess => 'インポートしました';

  @override
  String get chatImportParsing => '解析中…';

  @override
  String get chatImportAction => 'インポート';

  @override
  String get chatImportEmpty => '先に会話内容を貼り付けてください';

  @override
  String chatImportFailed(Object error) {
    return 'インポートに失敗しました: $error';
  }

  @override
  String get chatExportWarning => 'エクスポートには会話とユーザー入力が含まれる場合があります。安全に保管してください。';

  @override
  String get chatSaveFailed => '保存に失敗しました';

  @override
  String chatSavedPath(Object path) {
    return '保存しました: $path';
  }

  @override
  String get chatSaving => '保存中…';

  @override
  String get chatLoadFailedRetry => '読み込みに失敗しました。再試行';

  @override
  String chatCharacterCount(Object count) {
    return '$count 文字';
  }

  @override
  String get resourceDetailTitle => 'リソース詳細';

  @override
  String get resourceEnterStudio => 'リソーススタジオを開く';

  @override
  String get resourceLegacyNoStudio => 'レガシーリソースでは高度な編集を利用できません';

  @override
  String get resourceActions => 'リソース操作';

  @override
  String get moveToTrashAction => 'ごみ箱へ移動';

  @override
  String moveToTrashMessage(Object name) {
    return '「$name」をごみ箱に移動しますか？後で復元できます。';
  }

  @override
  String get moveToTrashFailed => 'ごみ箱への移動に失敗しました。再試行してください。';

  @override
  String get thinkingEngineTitle => '深層思考エンジン';

  @override
  String get thinkingEngineBadge => 'V4.1 ネイティブ推論';

  @override
  String get thinkingEngineDescription =>
      '複雑な分岐冒険と世界観の論理推論向け。DeepSeek V4.1 の思考で物語前の計画を有効にします。';

  @override
  String get worldviewDeepThinkingLabel => '世界観の深層推論生成';

  @override
  String get worldviewDeepThinkingSubtitle =>
      'AIによる世界観インポートでV4.1推論を使用します。初回トークン遅延を抑えるため既定ではオフです';

  @override
  String get characterDeepThinkingLabel => 'キャラクターカードの深層推論生成';

  @override
  String get characterDeepThinkingSubtitle =>
      'AIによるキャラクターインポートでV4.1推論を使用します。高速生成のため既定ではオフです';

  @override
  String get reasoningEffortLow => '軽度・高速応答';

  @override
  String get reasoningEffortMedium => 'バランス・おすすめ';

  @override
  String get reasoningEffortHigh => '深い思考・豊富な詳細';

  @override
  String get reasoningEffortMax => '最大・厳密な論理';

  @override
  String get restoreRecommended => 'おすすめの既定値に戻す';

  @override
  String get recommendedDefaultsRestored => '公式おすすめの既定値に戻しました';

  @override
  String get revisionHistoryTitle => '変更履歴';

  @override
  String revisionCount(Object count) {
    return '$count 件の履歴';
  }

  @override
  String get refreshRevisionHistory => '変更履歴を更新';

  @override
  String get noRestorableRevisions => '復元可能な履歴はまだありません';

  @override
  String get currentRevision => '現在';

  @override
  String get restoreRevision => 'この履歴を復元';

  @override
  String get presetParseError => 'シーンデータを解析できないか、形式が不完全です';

  @override
  String get presetWorldviewTitle => '世界観設定';

  @override
  String get presetCharacterTitle => '主人公プロフィール';

  @override
  String get presetOpeningTitle => 'オープニング序章';

  @override
  String get presetOptionsTitle => '初期行動分岐';

  @override
  String get presetNpcTitle => '登場人物（NPC）';

  @override
  String get presetCustomizeAction => '読み込んで調整';

  @override
  String get presetDetailsAction => '詳細';

  @override
  String get sidebarEmptyConversationsSubtitle => '上のボタンをクリックして新しい冒険を開始';

  @override
  String get sidebarDeleteTooltip => '会話を削除';

  @override
  String get sidebarSettingsNotConfigured => '設定（キー未設定）';

  @override
  String get characterFallbackName => 'キャラクターA';

  @override
  String get monitoredStatus => '監視ステータス';

  @override
  String get expandAction => '展開 ▼';

  @override
  String get collapseAction => '折りたたむ ▲';

  @override
  String statusItemsCount(int count) {
    return '$count件';
  }

  @override
  String optionsSectionTitle(int count) {
    return '選択肢 ($count 件の選択肢)';
  }

  @override
  String get selectPrompt => '選択してください';

  @override
  String get noOptionsAvailable => '選択可能な項目がありません';

  @override
  String get notSpecified => '指定なし';

  @override
  String itemsSelectedCount(int count) {
    return '$count件選択中';
  }

  @override
  String get backAction => '戻る';

  @override
  String get showPassword => 'パスワードを表示';

  @override
  String get hidePassword => 'パスワードを非表示';

  @override
  String get actionMenuTitle => '操作';

  @override
  String get actionMenuSemanticLabel => 'アクションメニュー';

  @override
  String get menuTooltip => 'メニュー';

  @override
  String get switchLibrary => 'ライブラリを切り替え';

  @override
  String get customAttributesTitle => 'カスタム属性';

  @override
  String get customAttributesSubtitle =>
      'キャラクターやNPCに固有設定を追加し、推論時の重要度を個別に設定できます';

  @override
  String get addCustomAttributeAction => '項目を追加';

  @override
  String get noCustomAttributes => 'カスタム属性はありません';

  @override
  String get customAttributesEmptyHint => '右上の「項目を追加」をタップして武器、禁忌、弱点、特性を定義できます';

  @override
  String get customAttributeNameLabel => '項目名 *';

  @override
  String get customAttributeNameHint => '例: 愛用の剣、致命的な弱点、詠唱の癖';

  @override
  String get deleteAttributeTooltip => 'この項目を削除';

  @override
  String get customAttributeContentLabel => '項目の内容 / 設定説明';

  @override
  String get customAttributeContentHint =>
      '具体的な効果、起源、制限を記述します（LLMの推論時に重要度に従います）';

  @override
  String get customAttributeImportanceReference => '参考';

  @override
  String get customAttributeImportanceImportant => '重要参考';

  @override
  String get customAttributeImportanceVeryImportant => '最重要参考';

  @override
  String get customAttributeImportanceCritical => '必須項目';

  @override
  String get feedbackSuccess => '成功';

  @override
  String get feedbackError => 'エラー';

  @override
  String get feedbackWarning => '注意';

  @override
  String get feedbackInfo => '情報';

  @override
  String get refreshFailed => '更新に失敗しました。後でもう一度お試しください';

  @override
  String get noRefreshNeeded => '現在のページは更新不要です';

  @override
  String get fontSizeDialogTitle => 'フォントサイズ調整';

  @override
  String get fontSizeSmall => 'A小';

  @override
  String get fontSizeLarge => 'A大';

  @override
  String get fontSizePreview => 'プレビュー: 日本語 123\n文字サイズサンプル';

  @override
  String get applyAction => '適用';

  @override
  String appliedPresetNotice(String preset) {
    return '適用済み: $preset';
  }

  @override
  String get dialogueParamsTitle => '対話パラメータ';

  @override
  String get paramsPresetLabel => 'パラメータプリセット';

  @override
  String get customPreset => 'カスタム';

  @override
  String get frequencyPenalty => '頻度ペナルティ';

  @override
  String get presencePenalty => '存在ペナルティ';

  @override
  String get saveWorldviewTitle => '世界観を保存';

  @override
  String get worldviewInfoSection => '世界観情報';

  @override
  String worldviewSavedSuccess(String name) {
    return '世界観「$name」を保存しました';
  }

  @override
  String saveFailedPrefix(String error) {
    return '保存に失敗しました: $error';
  }

  @override
  String get importCardDialogTitle => 'キャラクターカードをインポート';

  @override
  String get pasteCardJsonHeader => 'SillyTavern / Chub キャラクターカード JSON を貼り付け';

  @override
  String get pasteCardJsonHint => 'ここにキャラクターカードの JSON を貼り付けてください...';

  @override
  String get newDialoguePersonaTitle => '対話ペルソナを新規作成';

  @override
  String get editDialoguePersonaTitle => '対話ペルソナを編集';

  @override
  String get dialoguePersonaSettingHeader => '対話ペルソナ設定';

  @override
  String get dialoguePersonaScopeNotice =>
      'ここでのペルソナは対話モード専用であり、ナイラとは完全に独立して設定できます。';

  @override
  String get personaNameLabel => 'ペルソナ名 *';

  @override
  String get personaNameHint => '例: ナイラ、アドバイザー、執筆パートナー';

  @override
  String get personaRoleLabel => '役割 / アイデンティティ';

  @override
  String get personaRoleHint => '例: 汎用AIアシスタント、語学コーチ、世界観アドバイザー';

  @override
  String get personaUserAddressLabel => 'ユーザーの呼び名';

  @override
  String get personaUserAddressHint => '例: ユーザー、創作者、司令官、先生';

  @override
  String get personaPersonalityLabel => '性格と行動の特徴';

  @override
  String get personaPersonalityHint => '性格、価値観、問題解決の姿勢などを記述します';

  @override
  String get personaSpeakingStyleLabel => '話し方';

  @override
  String get personaSpeakingStyleHint => '例: 簡潔、丁寧、必要に応じて手順や例を交えて説明';

  @override
  String get personaBackgroundLabel => '背景設定';

  @override
  String get personaBackgroundHint => 'ペルソナの出自や知っていること';

  @override
  String get personaContextLabel => '対話シチュエーション';

  @override
  String get personaContextHint => '通常どのような状況で対話を行うかを記述します';

  @override
  String get contextWeightsTitle => 'コンテキストの重み';

  @override
  String get contextWeightsAdjust => 'ソースを調整';

  @override
  String get contextWeightsBalanced => 'バランス';

  @override
  String get contextWeightsHighControl => '高コントロール';

  @override
  String get contextWeightsImmersive => '没入';

  @override
  String get contextWeightsCustom => 'カスタム';

  @override
  String get contextSourceUserControl => 'ユーザー制御';

  @override
  String get contextSourceCurrentScene => '現在のシーン';

  @override
  String get contextSourceCharacterProfile => 'キャラクタープロフィール';

  @override
  String get contextSourceRuntimeCharacterState => 'キャラクター実行状態';

  @override
  String get contextSourceWorldview => '世界観';

  @override
  String get contextSourceRuntimeWorldState => '世界実行状態';

  @override
  String get contextSourceRecentDialogue => '最近の会話';

  @override
  String get contextSourceHistoricalSummary => '履歴要約';

  @override
  String get contextSourceArchiveRetrieval => 'アーカイブ検索';

  @override
  String get personaDirectivesLabel => '追加行動指示';

  @override
  String get personaDirectivesHint => '任意: ペルソナが遵守すべき補足ルール';

  @override
  String get deleteDialoguePersonaTitle => '対話ペルソナを削除しますか？';

  @override
  String deleteDialoguePersonaMessage(String name) {
    return '「$name」を削除してもよろしいですか？';
  }

  @override
  String deleteCharacterCardFailed(String error) {
    return 'キャラクターカードの削除に失敗しました: $error';
  }

  @override
  String get nameRequired => '名前を入力してください';

  @override
  String get manualCreatedSource => '手動作成';

  @override
  String get createAction => '作成';

  @override
  String get nameLabel => '名前';

  @override
  String get descriptionOptionalLabel => '説明（任意）';

  @override
  String get fontSizeAdjustment => 'フォントサイズ調整';

  @override
  String get fontSizeSmallA => 'A小';

  @override
  String get fontSizeLargeA => 'A大';

  @override
  String get dialogueParams => '対話パラメータ';

  @override
  String get parameterPresets => 'パラメータプリセット';

  @override
  String get presetDeepThinking => 'ディープシンキング (V4.1 複雑な推論)';

  @override
  String get presetFastNarrative => '高速ナラティブ (デフォルト)';

  @override
  String get presetDeepReasoning => '極限推論 (パズル解決)';

  @override
  String get presetLightweightDaily => '軽量デイリー (超低遅延)';

  @override
  String appliedPreset(String preset) {
    return '適用済み: $preset';
  }

  @override
  String get saveWorldview => '世界観を保存';

  @override
  String get worldviewInfo => '世界観情報';

  @override
  String get name => '名前';

  @override
  String get descriptionOptional => '説明（任意）';

  @override
  String worldviewSaved(String name) {
    return '世界観「$name」を保存しました';
  }

  @override
  String saveFailed(String error) {
    return '保存失敗: $error';
  }

  @override
  String get unknownError => '不明なエラー';

  @override
  String get importCharacterCard => 'キャラクターカードをインポート';

  @override
  String get pasteCharacterCardJson =>
      'SillyTavern / Chub キャラクターカードの JSON を貼り付け';

  @override
  String get pasteCharacterCardJsonHint => 'ここにキャラクターカードの JSON を貼り付け...';

  @override
  String get importAction => 'インポート';

  @override
  String get editDialoguePersonaCard => '対話キャラクターカードを編集';

  @override
  String get newDialoguePersonaCard => '新規対話キャラクターカード';

  @override
  String get dialoguePersonaSettings => '対話キャラクター設定';

  @override
  String get dialoguePersonaSettingsDesc =>
      'ここでのキャラクターは対話モード専用で、Naela を一切使用しないことも可能です。';

  @override
  String get personaNameRequired => 'キャラクター名 *';

  @override
  String get personaRole => 'アイデンティティ';

  @override
  String get personaUserCallName => 'ユーザーの呼び方';

  @override
  String get personaUserCallNameHint => '例：ユーザー、クリエイター、指揮官、先生';

  @override
  String get personaPersonality => '性格と行動の特徴';

  @override
  String get personaSpeakingStyle => '話し方';

  @override
  String get personaBackground => '背景設定';

  @override
  String get personaScenario => '対話シチュエーション';

  @override
  String get personaScenarioHint => 'キャラクターとユーザーがどのようなシチュエーションで会話するかを記述';

  @override
  String get personaSystemPrompt => '追加システム指示';

  @override
  String get personaSystemPromptHint => '任意：キャラクターが遵守すべき追加の行動ルール';

  @override
  String deleteDialoguePersonaPrompt(String name) {
    return '「$name」を削除してもよろしいですか？';
  }

  @override
  String get pleaseEnterPersonaName => 'キャラクター名を入力してください';

  @override
  String get manuallyCreated => '手動作成';

  @override
  String get sidebarSystemSettings => 'システム設定';

  @override
  String get settingsTabModelAndApi => 'モデルとAPI';

  @override
  String get settingsTabModelAndApiSubtitle => 'プロバイダーとAPIキーの設定';

  @override
  String get settingsTabSessionParams => 'セッションパラメータ';

  @override
  String get settingsTabSessionParamsSubtitle => 'サンプリングレートとディープシンキング';

  @override
  String get settingsTabAppearance => 'テーマカラー';

  @override
  String get settingsTabAppearanceSubtitle => 'ライト・ダークとアクセントカラー';

  @override
  String get settingsTabStorage => 'データ管理';

  @override
  String get settingsTabStorageSubtitle => 'Token統計とストレージ';

  @override
  String get settingsCustomProvider => 'カスタム';

  @override
  String get settingsReturnToLobby => 'ロビーに戻る';

  @override
  String get settingsReturnToSettingsList => '設定リストに戻る';

  @override
  String get settingsConfigsCategory => '構成カテゴリー';

  @override
  String settingsOfficialInService(String provider) {
    return '$provider 公式稼働中';
  }

  @override
  String get settingsKeyNotConfigured => 'APIキー未設定';

  @override
  String get settingsLlmConnected => 'LLMサービス接続済み';

  @override
  String get settingsLlmDisconnected => 'APIキー未設定';

  @override
  String get settingsLlmConnectedSubtitle => 'クリックしてプロバイダー、モデル、エンドポイントを管理';

  @override
  String get settingsLlmDisconnectedSubtitle => 'クリックしてAPIキーを設定し推論を開始';

  @override
  String get settingsEngineTitle => '霊境コアエンジン';

  @override
  String get settingsEngineSubtitle => 'SQLite · ローカル暗号化優先';

  @override
  String get settingsSystemConfigBadge => 'システム設定';

  @override
  String get inferenceParamsTitle => '推論ハイパーパラメータとサンプリング調整';

  @override
  String get inferenceParamsSubtitle => '文彩と論理的一貫性を両立するため、温度、サンプリング閾値、思考強度を調整';

  @override
  String get deepseekThinkingHint =>
      '💡 ヒント：DeepSeek V4.1 思考モードではサンプリングが自動管理されます。非思考モードでは top_p=1.0 に固定され、温度のみ調整可能です。';

  @override
  String get temperatureTitle => '生成温度 (Temperature)';

  @override
  String get temperatureDescription => '0.0 厳密・高精度 ↔ 2.0 独創的・多彩';

  @override
  String get topPTitle => '核サンプリング確率 (Top-P)';

  @override
  String get topPDescription => '累積確率の閾値。推奨値は 0.90 〜 0.95';

  @override
  String get maxTokensTitle => '1回の最大生成長 (Max Tokens)';

  @override
  String get maxTokensDescription => '1ターンの対話における最大Token予算を制限';

  @override
  String get paramsRealtimeNotice => 'ヒント：パラメータの変更は即座に反映され、手動保存は不要です';

  @override
  String testConnectionSuccess(int elapsed) {
    return '接続成功！所要時間 ${elapsed}ms、サービス正常稼働中。';
  }

  @override
  String get testConnectionFailure => '接続失敗。APIキーとネットワーク接続を確認してください。';

  @override
  String testConnectionFailureDetail(String error) {
    return '接続失敗: $error';
  }

  @override
  String get statusReady => '準備完了';

  @override
  String get statusNotReady => '未準備';

  @override
  String modelEndpointSummary(String model, String endpoint) {
    return 'モデル: $model · エンドポイント: $endpoint';
  }

  @override
  String get quickTesting => '検査中';

  @override
  String get quickTest => '接続テスト';

  @override
  String get llmProviderSectionTitle => 'LLMサービスプロバイダー';

  @override
  String get llmProviderSectionSubtitle => 'シナリオ対話と推論に使用する主要言語モデルサービスを選択・構成';

  @override
  String get modelProviderLabel => 'モデルプロバイダー';

  @override
  String get selectInServiceModal => '稼働中モデルを選択';

  @override
  String get customModelNameLabel => 'カスタムモデル名';

  @override
  String get customModelNameHint => '例：gpt-4o, llama-3.3-70b, qwen-max';

  @override
  String get apiEndpointLabel => 'APIエンドポイント (Base URL)';

  @override
  String get apiSecurityNotice => 'APIキーはローカルSQLiteに暗号化保存され、中間サーバーを経由しません';

  @override
  String get promptSettingsTitle => 'プロンプトと推論の編成';

  @override
  String get importPresets => 'プリセットをインポート';

  @override
  String get exportPresets => 'プリセットをエクスポート';

  @override
  String get previewPromptAction => 'プレビュー';

  @override
  String get importPresetTitle => 'プロンプトプリセットをインポート';

  @override
  String get exportPresetTitle => 'プロンプトプリセットをエクスポート';

  @override
  String get presetJsonLabel => 'プロンプトプリセット JSON';

  @override
  String get presetJsonEmptyError => 'プリセットJSONを入力してください';

  @override
  String presetImportFailed(String error) {
    return 'インポート失敗：$error';
  }

  @override
  String get presetJsonCopied => 'プリセットJSONをコピーしました';

  @override
  String get copyAllAction => 'すべてコピー';

  @override
  String get dialogueLevelSectionTitle => '対話レベル (Dialogue Level)';

  @override
  String get dialogueLevelSectionSubtitle => '1ターンの対話における文字数予算と描写の詳細密度を選択します。';

  @override
  String get systemPromptSectionTitle => 'グローバルシステムプロンプト (System Prompt)';

  @override
  String get systemPromptSectionSubtitle => '初期状態。空白の場合は汎用推論ガイドラインが適用されます。';

  @override
  String get systemPromptHint => 'カスタムのシステム設定や推論ルールを記入（空白でデフォルト使用）...';

  @override
  String charCountLabel(int count) {
    return '$count 文字入力済み';
  }

  @override
  String get clearAction => 'クリア';

  @override
  String get systemPromptSaved => 'システムプロンプトを保存しました';

  @override
  String get savePromptAction => 'プロンプトを保存';

  @override
  String get authorsNoteSectionTitle => '作者ノート (Author\'s Note)';

  @override
  String get authorsNoteSectionSubtitle => 'セッションの指定ターン深度に高優先度の指示を挿入します。';

  @override
  String get authorsNoteHint => '例：主人公の行動を詳細に描写し、サスペンスな雰囲気を維持する...';

  @override
  String get injectionDepth => '挿入深度';

  @override
  String get depthFollowSystem => 'システムプロンプトの直後';

  @override
  String depthBeforeRound(int depth) {
    return '最新から $depth ターン前';
  }

  @override
  String get injectionFrequency => '挿入頻度';

  @override
  String freqEveryRound(int freq) {
    return '$freq ターンごと';
  }

  @override
  String get authorsNoteSaved => '作者ノートの設定を保存しました';

  @override
  String get saveNoteConfigAction => 'ノート設定を保存';

  @override
  String get promptPreviewTitle => 'リアルタイムPrompt組み立てプレビュー';

  @override
  String get copyFullPrompt => '完全なPromptをコピー';

  @override
  String get fullPromptCopied => '完全なPromptをクリップボードにコピーしました';

  @override
  String promptPreviewStats(int chars, int tokens) {
    return '約 $chars 文字 · 推定 $tokens tokens';
  }

  @override
  String get resourceTypeWorldview => '世界観';

  @override
  String get resourceTypeCharacter => 'キャラクター';

  @override
  String get resourceTypeNpc => 'NPC';

  @override
  String get resourceStatusGenerating => '生成中';

  @override
  String get resourceStatusSaved => '保存済み';

  @override
  String get resourceStatusOptimizationSuggested => '最適化推奨';

  @override
  String get resourceStatusOptimizing => '最適化中';

  @override
  String get resourceStatusReady => '準備完了';

  @override
  String get resourceStatusOptimizationFailed => '最適化失敗';

  @override
  String get resourceUnknownTime => '不明な日時';

  @override
  String get resourceCreateTitle => '新規リソース';

  @override
  String get resourceTypeSectionTitle => 'リソースタイプ';

  @override
  String get resourceTypeSectionDescription => '構築するコンテンツのキャリアタイプを選択します';

  @override
  String get resourcePreselectedType => '事前選択タイプ';

  @override
  String get resourceCreationMethodSectionTitle => '作成方法';

  @override
  String get resourceCreationMethodSectionDescription =>
      '創作ニーズに合わせて、AI支援生成または手動テキスト作成を選択します';

  @override
  String get resourceAiCreationTitle => 'AI作成';

  @override
  String get resourceAiCreationDescription =>
      '参考資料や小説テキスト、既存アセットに基づき、AIが章のアウトラインと本文を自動生成します。';

  @override
  String get resourceRecommendBadge => 'おすすめ';

  @override
  String get resourceManualCreationTitle => '手動作成';

  @override
  String get resourceManualCreationDescription =>
      '名称と概要を設定し、空白のリソースを作成して章と内容を自由に構成します。';

  @override
  String get resourceManualCreateTitle => 'リソースを手動作成';

  @override
  String get resourceBasicInfoTitle => '基本情報';

  @override
  String get resourceManualBasicInfoDescription =>
      'リソースの種類、名前、概要を入力します。作成後はスタジオで自由に本文を編集できます。';

  @override
  String get resourceNameLabel => '名称';

  @override
  String get resourceManualNameHint => '明確で分かりやすい名称を入力';

  @override
  String get resourceSummaryOptionalLabel => '概要（任意）';

  @override
  String get resourceManualSummaryHint => 'このリソースの位置付けや背景設定を簡潔に紹介';

  @override
  String get resourceCreateAction => '作成';

  @override
  String get resourceInputNameError => 'リソース名を入力してください';

  @override
  String get resourceAiCreateTitle => 'AIスマートリソース作成';

  @override
  String get resourceAiBasicInfoDescription => '生成するリソースのキャリアタイプとタイトルを定義します';

  @override
  String get resourceAiNameHint => '生成する設定またはキャラクターの名前を入力';

  @override
  String get resourceAssociateWorldviewTitle => '世界観の関連付け（任意）';

  @override
  String get resourceAssociateWorldviewDescription =>
      'キャラクターやNPCに所属するネイティブ世界観を指定し、生成時の補足コンテキストとします';

  @override
  String get resourceNoAvailableWorldview => '関連付け可能な世界観がありません';

  @override
  String get resourceNotSpecified => '指定なし';

  @override
  String get resourceReferenceSourceTitle => '参考資料の出典';

  @override
  String get resourceReferenceSourceDescription =>
      '世界観の背景、小説設定、または関連リソースを提供すると、AIが要点を抽出して章の構成を生成します';

  @override
  String get resourceTabPaste => '貼り付け';

  @override
  String get resourceTabFile => 'ファイル';

  @override
  String get resourceTabExistingResource => '既存リソース';

  @override
  String get resourcePasteReferenceLabel => '参考内容を貼り付け';

  @override
  String get resourcePasteReferenceHint =>
      '小説のあらすじ、設定資料の草稿、または背景説明を入力または貼り付け...';

  @override
  String get resourceFileNameLabel => 'ファイル名';

  @override
  String get resourceFileNameHint => '例: world_notes.md';

  @override
  String get resourceFileContentLabel => 'ファイルテキスト内容';

  @override
  String get resourceFileContentHint => 'ファイル内の生テキストを入力または貼り付け...';

  @override
  String get resourceNoExistingInLibrary =>
      'ライブラリに関連付け可能な準備完了リソースがありません。「貼り付け」または「ファイル」に切り替えてください。';

  @override
  String get resourceSelectExistingLabel => '既存リソースを選択';

  @override
  String get resourceSelectExistingHint => '参考にする既存リソースをクリックして選択';

  @override
  String get resourceGenerationLengthTitle => '生成の長さ';

  @override
  String get resourceGenerationLengthDescription =>
      'AIが生成するリソース本文のおおよその目標文字数を制御します';

  @override
  String get resourceTargetCharactersLabel => '目標文字数';

  @override
  String resourceTargetCharactersValue(Object count) {
    return '$count 文字';
  }

  @override
  String get resourceLengthShort => 'ショート';

  @override
  String get resourceLengthLong => 'ロング';

  @override
  String get resourceStartCreateAction => '作成を開始';

  @override
  String get resourceInputOrPasteReferenceError => '参考資料の本文を入力または貼り付けてください';

  @override
  String get resourceInputFileNameError => 'ファイル名を入力してください';

  @override
  String get resourceInputFileContentError => 'ファイルの内容を入力してください';

  @override
  String get resourceSelectExistingError => '参考にする既存リソースを選択してください';

  @override
  String get resourcePastedContentLabel => '貼り付け内容';

  @override
  String get resourceLoadFailedRetry => 'リソースライブラリの読み込みに失敗しました。再試行してください。';

  @override
  String get resourceCreationFailedRetry => 'リソースの作成に失敗しました。再試行してください。';

  @override
  String get resourceUnnamed => '未命名リソース';

  @override
  String get resourceRevisionResourceKind => 'リソース';

  @override
  String get resourceRevisionSectionKind => '章';

  @override
  String get resourceRevisionPartKind => '段落';

  @override
  String resourceTrashSubtitle(
      Object deletedAt, Object expiresAt, Object kind, Object reason) {
    return '$kind · $reason · 削除日時: $deletedAt · 保持期限: $expiresAt';
  }

  @override
  String resourceTrashRestoreFailed(Object error) {
    return '復元失敗: $error';
  }

  @override
  String get resourceTrashPermanentDeleteSuccess => '完全に削除されました';

  @override
  String resourceTrashPermanentDeleteFailed(Object error) {
    return '完全削除に失敗しました: $error';
  }

  @override
  String get modeTitleConversation => '対話ライブラリ';

  @override
  String get modeTitleAdventure => 'シナリオライブラリ';

  @override
  String get modeTitleCreation => '創作ライブラリ';

  @override
  String get modeEmptyTitleConversation => '対話キャラクターカードがありません';

  @override
  String get modeEmptyTitleAdventure => 'シナリオ資料がありません';

  @override
  String get modeEmptyTitleCreation => '創作資料がありません';

  @override
  String get modeEmptySubtitleConversation =>
      'カスタムキャラクターカードを作成するか、過去のチャット履歴を確認します。';

  @override
  String get modeEmptySubtitleAdventure =>
      'シナリオ対話用のキャラクター、場所、ルール、またはストーリー資料をインポートします。';

  @override
  String get modeEmptySubtitleCreation =>
      '創作モード用の世界観、キャラクター設定、章リファレンス、または執筆資料をインポートします。';

  @override
  String get resourceStudioRefreshTooltip => '更新';

  @override
  String get resourceStudioTocTitle => '目次';

  @override
  String get resourceStudioNoContent => '現在のソースには表示可能なコンテンツがありません。';

  @override
  String get resourceStudioReadAloudAll => '全文を連続読み上げ';

  @override
  String get resourceStudioEditPart => '本文を編集';

  @override
  String get resourceStudioDeletePart => '段落を削除';

  @override
  String get resourceStudioPartNotExistCannotEdit => 'この段落は既に存在しないため編集できません';

  @override
  String get resourceStudioPublishCompressionTitle => '圧縮結果を公開';

  @override
  String get resourceStudioPublishCompressionMessage =>
      '圧縮後の本文で現在の内容が置き換えられます。置き換え前の本文は履歴バージョンとして記録され、いつでも復元可能です。\n本当に公開しますか？';

  @override
  String get resourceStudioPublishCompressionAction => '公開';

  @override
  String get resourceStudioRestoreRevisionTitle => '履歴バージョンを復元';

  @override
  String get resourceStudioRestoreRevisionMessage =>
      '現在の内容がこの履歴バージョンに置き換えられます。置き換え前の内容もバージョン履歴に残ります。\n本当に復元しますか？';

  @override
  String get resourceStudioRestoreRevisionAction => '復元';

  @override
  String get resourceStudioDeletePartTitle => '段落を削除';

  @override
  String resourceStudioDeletePartMessage(Object title) {
    return '「$title」はごみ箱に移動され、ごみ箱から復元可能です。\n本当に削除しますか？';
  }

  @override
  String get resourceStudioDeletePartAction => '削除';

  @override
  String get resourceStudioPartNotExistCannotDelete => 'この段落は既に存在しないため削除できません';

  @override
  String get resourceStudioMovedToTrash => 'ごみ箱に移動しました。ごみ箱から復元できます';

  @override
  String resourceStudioDeletePartFailed(Object error) {
    return '段落の削除に失敗しました: $error';
  }

  @override
  String get resourceStudioContinueGenerating => '生成を続行';

  @override
  String get resourceStudioPauseGenerating => '一時停止';

  @override
  String get resourceStudioCancelGenerating => 'キャンセル';

  @override
  String get resourceStudioRetryGenerating => '再試行';

  @override
  String get resourceStudioCreatingAndStarting => 'リソースを作成して生成を開始しています';

  @override
  String resourceStudioTargetCharacters(Object count) {
    return '目標 約 $count 文字';
  }

  @override
  String get resourceStudioCreationFailed => 'リソースの作成に失敗しました';

  @override
  String get resourceStudioPleaseRetryLater => 'しばらくしてから再試行してください';

  @override
  String get resourceStudioRetryCreation => '作成を再試行';

  @override
  String get resourceStudioSelectResourceOrSession => 'リソースまたは生成セッションを選択';

  @override
  String get resourceStudioSelectSession => '生成セッションを選択';

  @override
  String get resourceStudioCreateAndStart => '作成して生成を開始';

  @override
  String get resourceStudioPendingAiPlan => '確認待ちのAIプラン';

  @override
  String get resourceStudioConfirmAndStart => '確認を続けて生成を開始';

  @override
  String resourceStudioUnfinishedTask(Object index) {
    return '未完了の生成タスク $index';
  }

  @override
  String get resourceStudioGeneratingStatus => '生成中';

  @override
  String get resourceStudioResourceLabel => 'リソース';

  @override
  String get resourceStudioNoResourceOrSession => 'リソースまたは復元可能な生成セッションがありません。';

  @override
  String get resourceStudioAddSectionTitle => '章を追加';

  @override
  String get resourceStudioSectionTitleField => '章のタイトル';

  @override
  String get sectionControlsTitle => '章の制御';

  @override
  String sectionControlsCount(Object count) {
    return '$count 個の章';
  }

  @override
  String get sectionControlsAdd => '章を追加';

  @override
  String get sectionControlsEmpty => 'このリソースにはまだ章がありません。';

  @override
  String sectionControlsLoadMore(Object shown, Object total) {
    return 'さらに読み込む ($shown/$total 件表示中)';
  }

  @override
  String get sectionControlsUnnamed => '(無名の章)';

  @override
  String sectionControlsOrderIndex(Object index) {
    return '番号 $index';
  }

  @override
  String sectionControlsUpdated(Object time) {
    return '更新 $time';
  }

  @override
  String get sectionControlsValidate => '検証';

  @override
  String get sectionControlsMoreActions => 'その他の操作';

  @override
  String get sectionControlsRename => '名前変更';

  @override
  String get sectionControlsMoveUp => '上に移動';

  @override
  String get sectionControlsMoveDown => '下に移動';

  @override
  String get sectionControlsDelete => '削除';

  @override
  String get sectionControlsDeleteTitle => '章を削除';

  @override
  String sectionControlsDeleteMessage(Object title) {
    return '「$title」とそのすべての内容を削除してもよろしいですか？';
  }

  @override
  String get sectionControlsGenerate => '生成';

  @override
  String get sectionControlsRegenerate => '再生成';

  @override
  String get sectionControlsNoTasksTooltip =>
      'この章には生成タスクがないため（AIブループリント非作成）、生成できません';

  @override
  String get sectionControlsRegenerateTooltip =>
      'この章の生成タスクを再実行します。現在の内容は履歴バージョンとして保存され、いつでも復元可能です';

  @override
  String get sectionControlsRerunTooltip => 'この章の生成タスクを再実行します';

  @override
  String get sectionControlsRenameDialogTitle => '章の名前を変更';

  @override
  String get partEditorUnsavedDraftFound => '未保存の下書きが見つかりました';

  @override
  String get partEditorUnsavedDraftDesc =>
      '前回の編集が本文に保存されていません。下書きを読み込んで編集を続けるか、破棄できます。';

  @override
  String get partEditorLoadDraft => '下書きを読み込む';

  @override
  String get partEditorDiscardDraft => '下書きを破棄';

  @override
  String get partEditorConflictDetected => 'コンテンツの競合を検出';

  @override
  String get partEditorConflictDesc =>
      '他の操作（生成や復元など）によってこの段落が変更されました。自動保存は一時停止され、入力内容は下書きに残っています。どちらのバージョンを保持するか選択してください：';

  @override
  String get partEditorUseMyText => '自分のテキストを使用';

  @override
  String get partEditorDiscardMyText => '自分のテキストを破棄';

  @override
  String get partEditorHint => 'ここで本文を編集します。入力を停止すると自動保存されます';

  @override
  String get partEditorSaveNow => '今すぐ保存';

  @override
  String get partEditorFinishEditing => '編集完了';

  @override
  String get partEditorDraftLoaded => '下書きを読み込みました。保存時に本文に書き込まれます';

  @override
  String get partEditorDraftDiscarded => '下書きを破棄しました';

  @override
  String get partEditorEditing => '編集中…';

  @override
  String get partEditorConflictOtherSaved =>
      '保存競合: 他の操作によってこの段落が変更されました。保持するバージョンを選択してください';

  @override
  String get partEditorConflictDraftRetained =>
      '保存競合: 新しいバージョンを上書きせず、下書きに保持されました';

  @override
  String partEditorAutoSaved(Object label) {
    return '自動保存完了 ($label)';
  }

  @override
  String get partEditorTargetPartMissing => '対象のコンテンツが既に存在しないため、下書きは破棄されました';

  @override
  String get partEditorKeptMyTextAndSaved => '自分のテキストを保持して保存しました';

  @override
  String get partEditorConflictStillUnresolved =>
      '競合が未解決です: 段落が再度変更されました。もう一度選択してください';

  @override
  String partEditorResolveConflictFailed(Object error) {
    return '競合の解決に失敗しました: $error';
  }

  @override
  String partEditorSaving(Object label) {
    return '保存中 ($label)…';
  }

  @override
  String get capacityPanelTitle => '容量';

  @override
  String capacityLatestFailureReason(Object reason) {
    return '直近の圧縮失敗の理由: $reason';
  }

  @override
  String get capacityRefresh => '容量を更新';

  @override
  String get capacityCompressing => '圧縮中';

  @override
  String get capacityGenerateCandidates => '圧縮候補を生成';

  @override
  String capacityRetryFailedWithCount(Object count) {
    return '失敗した圧縮を再試行 ($count)';
  }

  @override
  String get capacityRetryFailed => '失敗した圧縮を再試行';

  @override
  String capacityPublishWithCount(Object count) {
    return '圧縮結果を公開 ($count)';
  }

  @override
  String get capacityPublish => '圧縮結果を公開';

  @override
  String get capacityOptimizationTip =>
      '最適化ではまずプレビューが生成されます。確認後にのみ現在の内容が置換され、元の内容はいつでも復元できます。';

  @override
  String get capacityPreparingState => 'リソースの状態を準備しています。';

  @override
  String capacityTextCharacters(Object count) {
    return '本文 $count 文字';
  }

  @override
  String capacitySectionsCount(Object count) {
    return '章 $count';
  }

  @override
  String capacityPartsCount(Object count) {
    return 'コンテンツブロック $count';
  }

  @override
  String capacityRevisionsCount(Object count) {
    return '履歴 $count';
  }

  @override
  String capacityArchivedSize(Object count) {
    return 'アーカイブ済み $count 文字';
  }

  @override
  String capacityQueuedJobs(Object count) {
    return '最適化待ち $count';
  }

  @override
  String capacityPotentialSavings(Object count) {
    return '候補を適用すると約 $count 文字削減できます。';
  }

  @override
  String get capacityStatusNormal => '正常';

  @override
  String get capacityStatusElastic => '弾力';

  @override
  String get capacityStatusOverflow => '予算超過';

  @override
  String get outlinePartPending => '生成待ち';

  @override
  String get outlinePartGenerated => '生成済み';

  @override
  String get operationFailedRetry => '操作に失敗しました。再試行してください';

  @override
  String get resourceImportReturnToEdit => '修正に戻る';

  @override
  String get resourceImportConfirmSave => '保存を確認';

  @override
  String get characterCardEditTitle => 'キャラクターカードを編集';

  @override
  String get characterCardCreateTitle => 'キャラクターカードを新規作成';

  @override
  String get characterCardConfirmDeleteTitle => '削除の確認';

  @override
  String characterCardConfirmDeleteMessage(Object name) {
    return 'キャラクターカード「$name」を削除してもよろしいですか？';
  }

  @override
  String characterCardDeleteFailed(Object error) {
    return 'キャラクターカードの削除に失敗しました: $error';
  }

  @override
  String get characterCardNameRequired => '名前を少なくとも入力してください';

  @override
  String characterCardSaveFailed(Object error) {
    return '保存に失敗しました: $error';
  }

  @override
  String get characterCardInfoSection => 'キャラクターカード情報';

  @override
  String get characterCardWorldviewOptional => '適合世界観（任意）';

  @override
  String get noneOption => 'なし';

  @override
  String get characterCardAiAssistedCreation => 'AIスマートキャラクターカード作成';

  @override
  String get detailedMode => '詳細モード';

  @override
  String get conciseMode => 'シンプルモード';

  @override
  String get simpleMode => '簡潔モード';

  @override
  String characterCardTargetValidChars(Object count, Object max) {
    return '目標有効文字数 $count 文字 (最大 $max 文字)';
  }

  @override
  String get characterCardSavedInStudioTip =>
      '生成内容はスタジオで継続保存され、復元および変更履歴の追跡が可能です';

  @override
  String get characterCardRelateCharacterOptional => '既存キャラクターを関連付け（任意）';

  @override
  String get characterCardRelateCharacterHint =>
      '関係を構築する既存キャラクターをクリックして選択（空欄の場合は独立キャラクター）';

  @override
  String get characterCardNoOtherCharacters => '他のキャラクターはありません';

  @override
  String get characterCardIndependentRole => '関連付けなし（独立した新規キャラクターとして構想）';

  @override
  String characterCardRelatedCount(Object count) {
    return '$count 人のキャラクターと関連付け済み';
  }

  @override
  String get characterCardUnnamed => '未命名キャラクター';

  @override
  String get characterCardBondRelation => '絆・関係性:';

  @override
  String get relationCompanion => '仲間 / チームメイト';

  @override
  String get relationChildhoodFriend => '幼馴染';

  @override
  String get relationLover => '恋人 / 運命の相手';

  @override
  String get relationMentor => '師弟 (師匠/弟子)';

  @override
  String get relationRival => '宿敵 / ライバル';

  @override
  String get relationKin => '家族・親族';

  @override
  String get relationBenefactor => '命の恩人 / 恩返し';

  @override
  String get relationEmployment => '雇用関係';

  @override
  String get relationCustom => 'カスタム関係...';

  @override
  String get relationCustomDescLabel => 'カスタム関係の説明';

  @override
  String get relationCustomDescHint => '例: 許嫁、異世界の魂の共生者...';

  @override
  String get characterCardCoreKeywordHint =>
      'キャラクターのキーワードや設定要件を入力（例: 冷淡な銀髪の女性剣士）、空欄の場合は自由生成...';

  @override
  String get opening => '開いています...';

  @override
  String get aiRegenerate => 'AIで再生成';

  @override
  String get aiFillIn => 'AI入力';

  @override
  String get genderLabel => '性別';

  @override
  String get genderMale => '男性';

  @override
  String get genderFemale => '女性';

  @override
  String get genderOther => 'その他';

  @override
  String get ageLabel => '年齢';

  @override
  String get customGenderLabel => 'カスタム性別';

  @override
  String get occupationLabel => '職業 / 身元';

  @override
  String get personalityLabel => '性格';

  @override
  String get backgroundStoryLabel => '背景ストーリー';

  @override
  String get appearanceLabel => '外見の描写';

  @override
  String get physiqueFeaturesLabel => '体型と身体的特徴';

  @override
  String get inWorldSettingSection => '世界内設定';

  @override
  String get factionLabel => '所属勢力';

  @override
  String get locationLabel => '活動場所 / 故郷';

  @override
  String get publicGoalLabel => '公開目標';

  @override
  String get hiddenMotiveLabel => '隠された動機（ナラティブ用）';

  @override
  String get abilitySourceLabel => '能力の源';

  @override
  String get abilityCostLabel => '能力の代償 / 制限';

  @override
  String get taboosLabel => '禁忌（読点で区切る）';

  @override
  String get relationsNoteLabel => '人間関係のメモ';

  @override
  String get characterCardDetailTitle => 'キャラクターカード詳細';

  @override
  String get characterPersonalityTraits => '性格の特徴';

  @override
  String get characterDescription => 'キャラクター解説';

  @override
  String get characterCustomFields => 'カスタム項目';

  @override
  String get characterAiAssistantCreateTitle => 'AIアシスタントでキャラクター作成';

  @override
  String get characterCreateAction => 'キャラクターカードを作成';

  @override
  String characterMatchWorldview(Object name) {
    return '適合: $name';
  }

  @override
  String get worldviewCreateTitle => '世界観を新規作成';

  @override
  String get worldviewEditTitle => '世界観を編集';

  @override
  String get worldviewDetailedTitle => '詳細な世界観';

  @override
  String get worldviewConciseTitle => '簡潔な世界観';

  @override
  String get worldviewOverviewDetailed => '世界観の概要（詳細設定の合計文字数にカウント）';

  @override
  String get worldviewOverviewConcise => '世界観の説明 (200~500文字)';

  @override
  String worldviewDetailedLimitTip(Object count) {
    return '詳細設定（最大 $count 文字、確認済み内容はシナリオ対話に入力）';
  }

  @override
  String worldviewConfirmDeleteMessage(Object name) {
    return '世界観「$name」を削除してもよろしいですか？';
  }

  @override
  String get worldviewDeleteFailed => '世界観の削除に失敗しました。再試行してください';

  @override
  String get worldviewAiAssistantTitle => 'AIアシスタントで世界観作成';

  @override
  String get worldviewCreateAction => '世界観を作成';

  @override
  String get originalTextContent => '原文コンテンツ';

  @override
  String get worldviewAiImportTip =>
      'テキスト（txt / md / HTML / 小説の断片）を貼り付けると、AIが自動抽出して世界観に統合します';

  @override
  String get pasteOriginalTextHint => 'ここに原文テキストを貼り付け...';

  @override
  String get importModeLabel => 'インポートモード';

  @override
  String get preparingDeduction => '推論を準備中…';

  @override
  String deductionProgressChars(Object current, Object partial, Object target) {
    return '現在の有効文字数 $current / $target\n$partial';
  }

  @override
  String deductionProgressStage(Object current, Object partial, Object total) {
    return '第 $current/$total ステージを推論中: $partial';
  }

  @override
  String get autoSaveToLibrary => 'ライブラリに自動保存';

  @override
  String get expectedTotalCharacters => '期待される総文字数';

  @override
  String get adaptiveStageHelperText => '全9モジュールを適応型の段階別・高並行で推論し、大幅に高速化して自動保存';

  @override
  String get aiAnalyzeAction => 'AI解析';

  @override
  String get selectImportModeTitle => 'インポートモードを選択';

  @override
  String get selectImportModeDesc =>
      '今回のキャラクター資料の整理粒度を選択してください。この選択は直接AIに渡されます。';

  @override
  String get conciseModeDesc =>
      '簡潔モード: アイデンティティ、性格、外見、重要経歴、必要な関係性を維持し、過度な加筆を避けます。';

  @override
  String get detailedModeDesc =>
      '詳細モード: 原文の事実の範囲内で身元、性格、外見、経歴、動機、情報、人物関係を完全に整理します。';

  @override
  String batchImportTitle(Object kind) {
    return 'バッチAIインポート $kind';
  }

  @override
  String get provideCharacterDataTitle => 'キャラクター資料を提供';

  @override
  String get batchAiRecognitionTip => 'AIがまず名前を識別し、確認後に各キャラクターを順次生成します。';

  @override
  String get pleaseSelectWorldviewFirst => 'まず世界観を選択してください';

  @override
  String get selectRelatedCharacters => '関連キャラクターを選択';

  @override
  String relatedCharactersCount(Object count) {
    return '$count 人のキャラクターを関連付け済み';
  }

  @override
  String get minTotalCharactersLabel => '最小総文字数';

  @override
  String get maxTotalCharactersLabel => '最大総文字数';

  @override
  String characterDataLabel(Object label) {
    return '$label 資料';
  }

  @override
  String characterDataHint(Object label) {
    return '複数の $label を含む章、設定、または人物紹介を貼り付け…';
  }

  @override
  String get planningAction => 'プランニング中…';

  @override
  String get enterAiStudioAction => 'AIスタジオに入る';

  @override
  String selectCandidatesToImportTitle(Object count) {
    return 'インポートするキャラクターを選択 ($count)';
  }

  @override
  String importSelectedCharactersAction(Object count) {
    return '$count 人のキャラクターをインポート';
  }

  @override
  String get selectCandidatesMultiTitle => '対象を選択（複数可）';

  @override
  String get candidatesRelationTip =>
      '生成される資料は原文とこれらの既存キャラクターに基づいて検証可能な関係を構築します。';

  @override
  String confirmRelateCharactersAction(Object count) {
    return '$count 人のキャラクターとの関連付けを確認';
  }

  @override
  String get pasteCharacterRawTextHint => 'ここにキャラクターまたはNPCの原文を貼り付け…';

  @override
  String get stagedDeepGenerationTip => '段階的な詳細生成を行い、目標の完全度まで自動補完します';

  @override
  String get worldviewModuleRules => 'ルールと境界';

  @override
  String get worldviewModuleState => '現在の世界状況';

  @override
  String get worldviewModuleLocations => '場所と地理';

  @override
  String get worldviewModuleFactions => '勢力と組織';

  @override
  String get worldviewModuleCustoms => '風俗と生活';

  @override
  String get worldviewModuleTimeline => '歴史とタイムライン';

  @override
  String get worldviewModuleGlossary => '用語集';

  @override
  String get worldviewModuleConstraints => '創作の制約';

  @override
  String get notSpecifiedOption => '指定なし';

  @override
  String get unnamedWorldview => '名称未設定の世界観';

  @override
  String get noExistingCharacterCards => '既存のキャラクターカードはありません';

  @override
  String selectedCharactersCount(int count) {
    return '$count 人のキャラクターを選択済み';
  }

  @override
  String get generatingEllipsis => '生成中…';

  @override
  String get aiImportCharacterTitle => 'AIキャラクターのインポート';

  @override
  String get aiImportNpcTitle => 'AI NPCのインポート';

  @override
  String get relateExistingCharactersTitle => '既存のキャラクターと関連付け';

  @override
  String get sceneBatchImportCharacterTitle => 'シーンキャラクターの一括インポート';

  @override
  String get sceneBatchImportNpcTitle => 'シーンNPCの一括インポート';

  @override
  String get belongingWorldviewOptional => '所属世界観（任意）';

  @override
  String get relateCharactersOptional => '関連キャラクター（任意）';

  @override
  String get associateWorldviewOptional => '関連世界観（任意）';

  @override
  String get resourceStatusCancelled => 'キャンセル済み';

  @override
  String get dashboardWizardBadge => 'ウィザード';

  @override
  String get dashboardPresetBadge => '完全な脚本';

  @override
  String get dashboardLibraryBadge => '全アセット';

  @override
  String get dashboardSettingsBadge => 'モデル設定';

  @override
  String get dashboardMyCharacterCards => 'マイキャラクターカード';

  @override
  String get dashboardNoCharacterCardsTitle => 'キャラクターカードがありません';

  @override
  String get dashboardNoCharacterCardsDesc =>
      'まだキャラクターが作成されていません。リソースライブラリで主人公や仲間の設定を作成し、冒険で選択できます。';

  @override
  String get dashboardGoToCharacterLibrary => 'キャラクターライブラリへ';

  @override
  String get dashboardDefaultProfession => '探検家';

  @override
  String get dashboardNoBackgroundDesc => '背景説明がありません';

  @override
  String get dashboardStartWithCharacter => 'このキャラクターで旅立つ';

  @override
  String get dashboardMyWorldSettings => 'マイワールド設定';

  @override
  String get dashboardNoCustomWorldsTitle => 'カスタムワールドがありません';

  @override
  String get dashboardNoCustomWorldsDesc =>
      'プリセットワールドのない白紙の状態です。ライブラリで独自の世界を構想するか、ウィザードで探索を開始できます。';

  @override
  String get dashboardGoToLibrary => 'ライブラリへ';

  @override
  String get dashboardNoWorldDesc => '設定説明がありません';

  @override
  String get dashboardStartWithWorld => 'この世界で旅立つ';

  @override
  String get dashboardToggleSidebar => 'サイドバーの切り替え';

  @override
  String get dashboardConfigureApiKey => 'APIキーを設定';

  @override
  String get dashboardSystemSettings => 'システム設定';

  @override
  String get dashboardNoAdventuresTitle => 'まだ冒険が始まっていません';

  @override
  String get dashboardNoAdventuresDesc => '上記の「ウィザード」を選択して最初の伝説を始めましょう';

  @override
  String get dashboardContinueAdventures => '冒険を再開';

  @override
  String get dashboardUnnamedAdventure => '名前のない冒険';

  @override
  String get dashboardDeleteAdventureTooltip => '冒険記録を削除';

  @override
  String dashboardSavedAt(Object time) {
    return '$time に保存';
  }

  @override
  String get dashboardContinueExploring => '探索を続ける';

  @override
  String get dashboardDeleteAdventureTitle => '冒険記録の削除';

  @override
  String dashboardDeleteAdventureMessage(Object title) {
    return 'シナリオ「$title」とそのすべての対話記録を削除してもよろしいですか？この操作は取り消せません。';
  }

  @override
  String dashboardAdventureDeleted(Object title) {
    return 'シナリオ「$title」を削除しました';
  }

  @override
  String get characterNameLabel => '氏名';

  @override
  String get presetScenesTitle => 'プリセットシナリオ工房';

  @override
  String get presetScenesSubtitle => 'すぐに使える完全な冒険シナリオ設定 · ワンクリックで開始';

  @override
  String get returnToDashboard => 'ロビーに戻る';

  @override
  String presetScriptCount(int count) {
    return '$count 個のシナリオ';
  }

  @override
  String get presetWizardNewScene => 'ウィザードで新規シーン';

  @override
  String get presetRefreshList => 'リストを更新';

  @override
  String get presetSearchHint => 'シナリオ、世界観、主人公を検索...';

  @override
  String get presetStatusReady => '準備完了';

  @override
  String get presetStatusDraft => '下書き';

  @override
  String get presetDefaultSceneName => 'プリセットシーン';

  @override
  String get presetNoMatchingScenes => '一致するプリセットシーンが見つかりません';

  @override
  String get presetNoScenes => 'プリセットシナリオはまだありません';

  @override
  String get presetNoMatchingScenesHint => '別の検索キーワードを試すか、フィルターをリセットしてください';

  @override
  String get presetNoScenesHint =>
      '4ステップウィザードで世界観、主人公、プロローグ、行動分岐を含む完全なシナリオを生成できます';

  @override
  String get presetStartWizardAction => 'ウィザードで新規シーンを作成';

  @override
  String get presetScriptDetail => 'シナリオ詳細';

  @override
  String get presetUnnamedScene => '無名のシーン';

  @override
  String presetWorldviewLabel(Object name) {
    return '世界観：$name';
  }

  @override
  String get presetPreviewFullSetting => '完全な設定のプレビュー';

  @override
  String get presetLoadIntoWizard => 'ウィザードに読み込んで微調整';

  @override
  String get presetDeleteAction => 'プリセットシーンを削除';

  @override
  String get presetDeleteTitle => 'プリセットシーンを削除';

  @override
  String presetDeleteMessage(Object name) {
    return 'プリセットシーン「$name」を削除してもよろしいですか？\n削除するとこのスクリプトプリセットは復元できません。';
  }

  @override
  String presetDeletedSuccess(Object name) {
    return 'シーン「$name」を削除しました';
  }

  @override
  String presetDeleteFailed(Object error) {
    return '削除に失敗しました: $error';
  }

  @override
  String presetLoadFailed(Object error) {
    return 'プリセットシーンの読み込みに失敗しました: $error';
  }

  @override
  String get presetStartFailed => 'プリセットシーンの開始に失敗しました。後でもう一度お試しください';

  @override
  String presetProtagonistSummary(
      Object name, Object gender, Object profession) {
    return '主人公：$name ($gender · $profession)';
  }

  @override
  String get presetNoPlotSummary => 'プロットの概要はありません';

  @override
  String get presetDataSimplifying => 'データ構造を簡素化中';

  @override
  String get presetQuickStartAction => 'ワンクリック開始';

  @override
  String get presetMenuSemantic => 'シーン操作メニュー';

  @override
  String get worldSelectionTitle => '世界観設定を選択';

  @override
  String get worldSelectionSubtitle => 'ライブラリから今回の冒険の世界法則と背景設定を選択します';

  @override
  String get worldSelectionSearchHint => '世界観の名前、地理、ルールを検索...';

  @override
  String get worldSelectionNoDesc => '詳細な背景説明はありません';

  @override
  String get worldSelectionTag => '世界設定';

  @override
  String get worldSelectionEmptyTitle => '保存された世界観はありません';

  @override
  String get worldSelectionEmptyDesc => 'ライブラリで作成するか、ウィザードで直接カスタム世界観を入力できます';

  @override
  String get characterSelectionTitle => '冒険キャラクターを選択';

  @override
  String get characterSelectionSubtitle => 'キャラクターアーカイブから主人公と同行者を選択します';

  @override
  String get characterSelectionSearchHint => 'キャラクター名、職業、性格、背景を検索...';

  @override
  String get characterCompatNative => '現在の世界';

  @override
  String get characterCompatUnbound => '未バインド';

  @override
  String get characterCompatCrossWorld => '他の世界から';

  @override
  String characterAgeYears(Object age) {
    return '$age歳';
  }

  @override
  String characterPersonalityPrefix(Object personality) {
    return '性格: $personality';
  }

  @override
  String get characterSelectionEmptyTitle => '利用可能なキャラクターアーカイブはありません';

  @override
  String get characterSelectionEmptyDesc => 'ライブラリで新規作成するか、ウィザードでAI自動生成を使用できます';

  @override
  String get npcSelectionTitle => '初期NPCを選択';

  @override
  String get npcSelectionSubtitle => '今回の冒険に登場する常駐NPCを選択（データはスナップショットに固定されます）';

  @override
  String get npcSelectionSearchHint => 'NPCの名前、役割、概要を検索...';

  @override
  String get npcSelectionEmptyTitle => 'ライブラリにNPCはありません';

  @override
  String get npcSelectionEmptyDesc => 'ライブラリでNPCを追加するか、このステップをスキップできます';

  @override
  String get unnamedNpc => '無名のNPC';

  @override
  String resourceSelectedCount(int count) {
    return '$count 件選択中';
  }

  @override
  String get resourceNoneSelected => '選択されていません';

  @override
  String get resourceOneSelected => '1 件選択済み';

  @override
  String get confirmSelection => '選択を確定';

  @override
  String get finishSelection => '完了';

  @override
  String get loadingResources => '利用可能なリソースを読み込み中...';

  @override
  String noMatchingResourceForQuery(Object query) {
    return '「$query」を含むリソースは見つかりませんでした';
  }

  @override
  String get clearSearch => '検索をクリア';

  @override
  String get configureApiKeyFirstForAi => 'AI自動生成機能を使用するには、まずAPI Keyを設定してください';

  @override
  String get aiGenerationNoValidContent =>
      '生成結果に有効な内容が含まれていません。ネットワークを確認するか再試行してください';

  @override
  String get aiOpeningGeneratedSuccess => 'AIプロローグと初期行動分岐が自動生成され適用されました！';

  @override
  String aiGenerationFailed(Object error) {
    return '生成に失敗しました: $error';
  }

  @override
  String get openingPromptLabel => 'プロローグ要望 / ガイドプロンプト (任意)';

  @override
  String get openingPromptHint => '例：雨の夜の波止場のサスペンスフルな雰囲気で幕を開け、主人公が異変を察知する…';

  @override
  String get aiGenerateOpeningAndBranches => 'AIでプロローグと分岐を生成';

  @override
  String get aiOpeningGeneratingProgress =>
      'AIが世界観とキャラクター設定を組み合わせてプロローグと行動分岐を構想中…';

  @override
  String assemblyWorldviewSubtitle(Object worldview) {
    return '世界: $worldview';
  }

  @override
  String assemblyProtagonistSubtitle(Object name) {
    return '主人公: $name';
  }

  @override
  String get assemblyConfigPageTitle => 'プロローグプロットと分岐設定';

  @override
  String get saveConfigAndContinue => '設定を保存して続行';

  @override
  String get openingFirstSceneTitle => 'オープニング第1幕プロット';

  @override
  String get openingFirstSceneDesc =>
      'プレイヤーが冒険に入った直後の状況描写、遭遇、またはオープニングの転換を設定します。';

  @override
  String get openingFirstSceneHint => '冒険立ち上がり時の瞬間、環境、予期せぬ危機を描写...';

  @override
  String get pleaseEnterOpeningScene => 'オープニングシーンのプロットを入力してください';

  @override
  String get initialActionBranchesTitle => '初期行動選択分岐 (任意)';

  @override
  String get initialActionBranchesDesc =>
      '開始時にプレイヤーが選択する3つの行動分岐。空白の場合は開始時にAIが動的に生成します。';

  @override
  String get actionBranch1 => '選択分岐 1';

  @override
  String get actionBranch1Hint => '例：迫り来る影を迎撃するために剣を抜く';

  @override
  String get actionBranch2 => '選択分岐 2';

  @override
  String get actionBranch2Hint => '例：遮蔽物を探し、仲間に援護を求める';

  @override
  String get actionBranch3 => '選択分岐 3';

  @override
  String get actionBranch3Hint => '例：周囲を観察して脱出ルートを探す';

  @override
  String get difficultyAndGuidanceTitle => '推論難易度とカスタムガイド';

  @override
  String get difficultyAndGuidanceDesc => 'ゲーム進行の難易度傾向とカスタムプロンプト指針を制御します。';

  @override
  String get narrativeDifficulty => '叙事の難易度';

  @override
  String get difficultyNormalDesc => '普通 (標準的な叙事とバランスの取れた挑戦)';

  @override
  String get difficultyCasualDesc => 'カジュアル (物語重視とリラックスした没入)';

  @override
  String get difficultyHardDesc => 'ハード (厳格なルールとハードコアな選択)';

  @override
  String get customGuidancePromptOptional => 'カスタムガイダンスプロンプト (任意)';

  @override
  String get customGuidancePromptHint => '例：サスペンス探偵の雰囲気を重視し、環境の感覚的描写を増やす…';

  @override
  String get worldviewBoundRules => 'バインドされた世界観ルールと地理法則';

  @override
  String get defaultContinentRules => 'デフォルトの大陸ルールを使用';

  @override
  String readinessReadError(Object error) {
    return 'リソースの準備状態を読み取れません: $error';
  }

  @override
  String readinessRetryError(Object error) {
    return 'リソースの再準備に失敗しました: $error';
  }

  @override
  String startAdventureFailed(Object error) {
    return '冒険の開始に失敗しました: $error';
  }

  @override
  String get unnamedHero => '無名の勇者';

  @override
  String get adventurerRole => '冒険者';

  @override
  String get assemblyPreviewSubtitle => '世界観、キャラクター、NPC、プロローグ設定を包括的に確認します';

  @override
  String get enterAdventureAction => '冒険に足を踏み入れる';

  @override
  String get readinessCheckingTitle => 'リソースの準備状態を確認中';

  @override
  String get readinessUnconfirmedTitle => 'リソースの準備状態を確認できません';

  @override
  String get readinessReadyTitle => '冒険要素の準備が完了しました';

  @override
  String get readinessNotReadyTitle => '一部のリソースの準備が完了していません';

  @override
  String get readinessCheckingDesc => '世界観とキャラクターの利用可能なバージョンを読み込んでいます。';

  @override
  String get readinessUnconfirmedDesc => 'リソース状態の読み取りに失敗しました。安全のため開始を確認できません。';

  @override
  String get readinessReadyDesc =>
      '下の「冒険に足を踏み入れる」をクリックしてスナップショットを固定し、新しい旅を始めます。';

  @override
  String get readinessNotReadyDesc =>
      '利用可能なリビジョンがないと冒険を開始できません。まずリソースの準備を完了してください。';

  @override
  String get readinessRetrying => '再準備中…';

  @override
  String get readinessRetry => '再準備';

  @override
  String worldviewSettingLabel(Object name) {
    return '世界設定: $name';
  }

  @override
  String get worldviewSettingTitle => '世界設定';

  @override
  String get readAloudWorldview => '世界設定を読み上げ';

  @override
  String protagonistLeadLabel(Object name, Object className) {
    return '主操作主人公: $name ($className)';
  }

  @override
  String get mainProtagonistTitle => '主人公';

  @override
  String personalityFeatureLabel(Object personality) {
    return '性格的特徴: $personality';
  }

  @override
  String backgroundStoryPrefix(Object background) {
    return '生い立ち: $background';
  }

  @override
  String accompanyingCharactersCount(int count) {
    return '同行キャラクター ($count 人):';
  }

  @override
  String characterBondsCount(int count) {
    return '絆関係 ($count 件):';
  }

  @override
  String residentNpcsCount(int count) {
    return '常駐NPC ($count 人)';
  }

  @override
  String get openingSceneAndDecisionsTitle => 'プロローグと行動の決断';

  @override
  String get openingSceneTitle => 'プロローグシーン';

  @override
  String get readAloudOpeningScene => 'プロローグシーンを読み上げ';

  @override
  String get aiDynamicOpeningPlaceholder =>
      '（世界観とキャラクター背景に基づき、AIがオープニングプロットを動的に構想します）';

  @override
  String get initialActionDecisionsTitle => '初期行動の決断分岐:';

  @override
  String get noMatchingResourceTitle => '一致するリソースがありません';

  @override
  String get noMatchingResourceDesc => '他の検索キーワードを入力するか、フィルターをクリアしてください';

  @override
  String get searchResourceNameOrDesc => 'リソース名または説明を検索...';

  @override
  String get aiOpeningPanelTitle => 'AIプロローグ自動生成';

  @override
  String get aiOpeningPanelDesc =>
      'プロローグの要望を入力すると、AIが世界観、主人公、仲間のキャラクターカード、絆、NPCを組み合わせてプロローグ本文と初期行動分岐を生成します。生成結果は手動で変更可能です。';

  @override
  String get regenerate => '再生成';

  @override
  String get assemblyPipelineTitle => '冒険アセンブリパイプライン';

  @override
  String get assemblyPipelineSubtitle => 'ステップ推進 · ページ化リソース組み立て · ダイアログ制約ゼロ';

  @override
  String get phaseWorldview => '世界観設定';

  @override
  String get phaseCharacters => 'キャラクター';

  @override
  String get phaseOpening => 'プロローグ分岐';

  @override
  String get phasePreview => 'アセンブリ概要';

  @override
  String nextPhaseLabel(Object phase) {
    return '次へ：$phase';
  }

  @override
  String get previousStepAction => '前へ';

  @override
  String get pleaseSetWorldviewName => '世界観名を設定してください';

  @override
  String get pleaseAddAtLeastOneCharacter => '少なくとも1人のキャラクターを追加してください';

  @override
  String worldviewSelectedSuccess(Object name) {
    return '世界観「$name」を選択しました';
  }

  @override
  String get rosterUpdatedSuccess => '登場キャラクター陣容を更新しました';

  @override
  String npcsSelectedCountSuccess(int count) {
    return '$count人のNPCを選択しました';
  }

  @override
  String get openingConfigSavedSuccess => 'プロローグ設定を保存しました';

  @override
  String characterJoinedPartySuccess(Object name) {
    return 'キャラクター「$name」がパーティに加わりました';
  }

  @override
  String get worldviewLibraryLinkTitle => '世界観ライブラリ関連付け';

  @override
  String get selectFromLibrary => 'ライブラリから選択';

  @override
  String boundLibraryWorldviewId(Object id) {
    return 'バインドされたライブラリ世界観ID: $id';
  }

  @override
  String get notBoundPresetHint => 'プリセット未バインド。下部に直接カスタム世界設定を入力することもできます。';

  @override
  String get worldviewDetailsSectionTitle => '世界観設定の詳細';

  @override
  String get worldviewDetailsSectionDesc => '大陸の法則、地理的背景、文明度、勢力構図を設定します。';

  @override
  String get worldNameRequiredLabel => '世界名 *';

  @override
  String get worldNameHint => '例：エルデン大陸、サイバーネオ2099、修仙古代世界...';

  @override
  String get pleaseEnterWorldName => '世界名を入力してください';

  @override
  String get lawsAndBackgroundLabel => '法則と背景設定';

  @override
  String get lawsAndBackgroundHint => '世界の魔法・科学技術体系、気候、陣営勢力などを記述...';

  @override
  String get charactersAndNpcAssemblyTitle => 'キャラクターとNPCのアセンブリ';

  @override
  String get selectCharactersFromLibrary => 'ライブラリからキャラクターを選択';

  @override
  String selectNpcCountLabel(int count) {
    return 'NPCを選択 ($count)';
  }

  @override
  String get newCharacterAction => '新規キャラクター';

  @override
  String rosterSectionTitle(int count) {
    return '登場キャラクター陣容 ($count)';
  }

  @override
  String get rosterSectionDesc =>
      '主控主人公として1人を選択する必要があります。他のキャラクターには仲間、ヴィラン、メンターなどの役割を付与できます。';

  @override
  String get noCharactersAddedYet => '登場キャラクターがまだ追加されていません';

  @override
  String get clickAboveToAddCharactersHint =>
      '上の「ライブラリからキャラクターを選択」または「新規キャラクター」をクリック';

  @override
  String get setAsMainProtagonist => 'メイン主人公に設定';

  @override
  String get scriptRoleOrientation => 'シナリオ役割位置づけ';

  @override
  String get openingAndRulesAdvancedConfigTitle => 'プロローグとルール詳細設定';

  @override
  String get fullscreenAdvancedConfig => '全画面詳細設定';

  @override
  String get openingSceneContentTitle => 'プロローグシーン内容';

  @override
  String get openingSceneContentDesc => '冒険開始時の最初のシーン描写。';

  @override
  String get openingSceneContentHint => '主人公が登場する瞬間の環境と展開を記述...';

  @override
  String get openingBranchesDesc => 'プロローグ終了時にプレイヤーが選択する行動の方向性。';

  @override
  String branchNumberLabel(Object number) {
    return '分岐 $number';
  }

  @override
  String actionOptionHint(Object number) {
    return '行動の選択肢 $number...';
  }

  @override
  String get enterStandaloneFullscreenPreview => '独立全画面プレビューへ';

  @override
  String get fullscreenPreviewButton => '全画面プレビュー';

  @override
  String get customUnnamedWorld => 'カスタム無名世界';

  @override
  String get unspecifiedProtagonist => '主人公未指定';

  @override
  String companionRosterSummary(Object roster) {
    return '仲間陣容: $roster';
  }

  @override
  String selectedInitialNpcCount(int count) {
    return '$count人の初期NPCを選択済み';
  }

  @override
  String get firstSceneOpeningPlotTitle => 'プロローグ第1幕';

  @override
  String get aiDynamicOpeningSummary => '背景をもとにAIが自動展開';

  @override
  String get wizardWorldviewQuickBadge => '素早い構想とライブラリでの作成';

  @override
  String get wizardWorldviewPromptLabel => '世界観のアイデア・ジャンル（任意）';

  @override
  String get wizardWorldviewPromptHint =>
      '例：スチームパンクの空中都市、古き神々のささやき、深海の終末都市。空欄なら自由に構想します…';

  @override
  String get generationModeLabel => '生成モード';

  @override
  String get clearSettingsAction => '設定をクリア';

  @override
  String get wizardGenerateWorldviewAction => 'AIで世界観を作成';

  @override
  String get wizardRegenerateWorldviewAction => '世界観を再生成';

  @override
  String get wizardWorldviewGeneratingBrief => '世界観を構想中…';

  @override
  String get wizardWorldviewGeneratingDetailed => '段階的に世界観を構築中…';

  @override
  String get saveToLibraryNow => 'ライブラリに保存';

  @override
  String get wizardReusableBadge => 'いつでも再利用可能';

  @override
  String get wizardWorldviewSaveDescription =>
      'この設定を世界観ライブラリに保存すると、今後の冒険で再利用・拡張できます。';

  @override
  String charactersSavedCount(int count) {
    return 'キャラクター設定を $count 件ライブラリに保存しました';
  }

  @override
  String characterCardSavedSuccess(String name) {
    return 'キャラクター「$name」をライブラリに保存しました';
  }

  @override
  String get fullscreenSelectionAction => '全画面で選択';

  @override
  String wizardCharacterAiSummary(String worldview) {
    return 'キャラクターの性格や役割を入力してください。AIが現在の世界観「$worldview」に合わせて主人公や仲間を作成し、メンバーに追加します。ライブラリではより詳細に作成できます。';
  }

  @override
  String get wizardCharacterPromptLabel => 'キャラクターのアイデア・人物像（任意）';

  @override
  String get wizardCharacterPromptHint => '例：冷静な退魔剣士、天真爛漫な白髪の治癒術師、冷徹な機械遊撃手…';

  @override
  String get wizardGenerateMainCharacterAction => 'AIで主人公を作成';

  @override
  String get wizardAddCharacterToRosterAction => 'AIで仲間を追加';

  @override
  String get currentWorldviewLabel => '現在の世界';

  @override
  String get removeRosterCharacter => 'メンバーから削除';

  @override
  String get clearRelatedCharacters => '関連をクリア';

  @override
  String wizardRelatedCharactersSummary(int count, String names) {
    return '$count 人と関連：$names';
  }

  @override
  String get wizardRelationAssociationSummary =>
      '新しいキャラクターは選択したキャラクターと物語上の絆を結びます。';

  @override
  String charactersAddedToRoster(int count) {
    return 'AIで作成したキャラクターを $count 人メンバーに追加しました';
  }

  @override
  String get roleMaleLead => '男性主人公';

  @override
  String get roleFemaleLead => '女性主人公';

  @override
  String get roleMaleOne => '男性キャラクター1';

  @override
  String get roleFemaleOne => '女性キャラクター1';

  @override
  String get roleMaleTwo => '男性キャラクター2';

  @override
  String get roleFemaleTwo => '女性キャラクター2';

  @override
  String get roleSupporting => '重要な脇役';

  @override
  String get roleVillain => '敵役';

  @override
  String get roleMentor => '師匠';

  @override
  String get roleFamily => '親しい人';

  @override
  String get relationFriend => '友人';

  @override
  String get relationEnemy => '敵';

  @override
  String get relationStranger => '他人';

  @override
  String get mainProtagonistDescription => '主人公（行動と重要な選択を担います）';

  @override
  String get protagonistShortTag => '主人公';

  @override
  String get relationshipNetworkDescription =>
      '登場人物の絆、陣営、過去の因縁を設定します。AIはこの関係に沿って推論します。';

  @override
  String relationAssetReference(String suggestion) {
    return '関連リソース：$suggestion（この冒険では変更できます）';
  }

  @override
  String get relationDetailsHint => '二人の関係の背景や絆の手がかりを入力（任意）。';

  @override
  String get relationshipNetworkTitle => 'キャラクターの絆と関係';

  @override
  String get adventureReadyToEnterTitle => '世界へ旅立つ準備ができました';

  @override
  String get worldviewSnapshotBoundSummary => 'ライブラリの世界観スナップショットと規則を関連付けました';

  @override
  String get characterCardSnapshotBoundSummary => 'ライブラリのキャラクターカードに関連付けました';

  @override
  String get characterCustomDesignedSummary => '主人公の設定をカスタマイズしました';

  @override
  String get unnamedCharacterA => 'キャラクター A';

  @override
  String get unnamedCharacterB => 'キャラクター B';

  @override
  String get savePreviewAction => 'プレビューを保存';

  @override
  String get previewTemplateNoStartHint =>
      '復元可能なプレビューテンプレートとして保存します。冒険は開始しません。';

  @override
  String adventurePreviewName(String worldview) {
    return '$worldview · 冒険プレビュー';
  }

  @override
  String adventurePreviewSavedMessage(String name) {
    return 'プレビュー「$name」を保存しました。プリセットシーンから復元できます。';
  }

  @override
  String get adventurePreviewExistsMessage => '同じ内容の冒険プレビューがすでにあります。';

  @override
  String adventurePreviewSaveFailed(String error) {
    return 'プレビューの保存に失敗しました：$error';
  }

  @override
  String get wizardCharacterSaveDescription =>
      'パーティーのキャラクター設定をキャラクターライブラリに保存し、今後の冒険で再利用できます。';

  @override
  String wizardMalformedCharacterCards(int count) {
    return '$count 件のキャラクターカードを読み込めませんでした。';
  }

  @override
  String get conversationDeleteTitle => 'シーン会話を削除';

  @override
  String conversationDeleteConfirm(int count) {
    return '選択した$count件のシーン会話を削除しますか？履歴と展開したストーリーは元に戻せません。';
  }

  @override
  String conversationDeleteInterrupted(String error) {
    return '削除を中断しました。残りの会話を確認して再試行してください: $error';
  }

  @override
  String get conversationManageTitle => '過去の会話を管理';

  @override
  String selectedItemsCount(int count) {
    return '$count件を選択';
  }

  @override
  String get deletingAction => '削除中…';

  @override
  String get batchDeleteAction => '一括削除';

  @override
  String get noManagedConversations => '管理できるシーン会話はありません';

  @override
  String get selectAllAction => 'すべて選択';

  @override
  String get sceneConversationLabel => 'シーン会話';

  @override
  String get messageEditUserTitle => 'メッセージを編集';

  @override
  String get messageEditAssistantTitle => 'AIの返信を編集';

  @override
  String get messageEditUserSubtitle => '編集すると、このメッセージ以降のストーリーが再生成されます。';

  @override
  String get messageEditAssistantSubtitle => '物語の文章を編集して、語り口や詳細を調整できます。';

  @override
  String get messageEditUserWarning =>
      '保存すると、このメッセージ以降の履歴が削除され、新しい入力からストーリーが再生成されます。';

  @override
  String get messageBodyLabel => 'メッセージ本文';

  @override
  String get messageEditDescription => '長文の編集や改行、書式設定に対応しています。';

  @override
  String get messageContentHint => 'メッセージを入力…';

  @override
  String get saveAndRegenerateAction => '保存して再生成';

  @override
  String get saveChangesAction => '変更を保存';

  @override
  String get messageContentRequired => 'メッセージを入力してください。';

  @override
  String get messageUnchanged => '変更はありません。';

  @override
  String get messageNoLongerCurrent => 'このメッセージは現在の会話にありません。戻って更新してください。';

  @override
  String get messageSavedAndRegenerated => '保存して再生成しました';

  @override
  String get messageChangesSaved => '変更を保存しました';

  @override
  String get messageSaveRetry => '保存できませんでした。もう一度お試しください。';

  @override
  String get inventoryTitle => 'インベントリ';

  @override
  String get inventoryItemsTitle => 'アイテム';

  @override
  String get equipmentTitle => '装備';

  @override
  String get legacyInventoryTitle => '旧インベントリ記録';

  @override
  String inventorySummary(int itemCount, int equipmentCount) {
    return 'アイテム $itemCount 件、装備 $equipmentCount 件';
  }

  @override
  String get quickMenuTooltip => 'クイックメニュー';

  @override
  String get characterStatusTitle => 'キャラクター状態';

  @override
  String get wordCountSettings => '文字数設定';

  @override
  String get backToLobby => 'ロビーに戻る';

  @override
  String get restartAdventureTitle => '冒険を再開しますか？';

  @override
  String get restartAdventureMessage => '現在の会話と冒険の進行状況をリセットしてホームに戻ります。';

  @override
  String get restartAdventureAction => '再開';

  @override
  String get stopGenerationAction => '生成を停止';

  @override
  String get textAdventureTitle => 'テキストアドベンチャー';

  @override
  String get searchConversationAction => '会話を検索';

  @override
  String get historyAndSidebarAction => 'シーン履歴とサイドバー';

  @override
  String get moreOptionsAction => 'その他の操作';

  @override
  String get replyLengthSetting => '返信の長さ';

  @override
  String get switchModelAction => 'モデルを切り替え';

  @override
  String get promptSettingsAction => 'プロンプト設定';

  @override
  String get wordCountAndDensitySettings => '文字数と会話密度の設定';

  @override
  String get reasoningCopiedToast => '推論をクリップボードにコピーしました';

  @override
  String get editedBadge => '（編集済み）';

  @override
  String get deleteMessageConfirmation => '削除すると元に戻せません。削除しますか？';

  @override
  String get removeBookmarkAction => 'ブックマークを解除';

  @override
  String get addBookmarkAction => 'ブックマークに追加';

  @override
  String get editMessageAction => '編集';

  @override
  String get regenerateMessageAction => '再生成';

  @override
  String get assistantReplyLabel => 'AIの返信';

  @override
  String get selectModelForRegeneration => '再生成するモデルを選択';

  @override
  String get selectLanguageModel => '言語モデルを選択';

  @override
  String currentModelSummary(String model, String provider) {
    return '現在: $model ($provider)';
  }

  @override
  String get selectedModelLabel => '選択中のモデル';

  @override
  String get defaultModelPlaceholder => '未選択（デフォルトを使用）';

  @override
  String get confirmApplyAction => '適用';

  @override
  String get selectValidModelError => '有効なモデル名を選択または入力してください。';

  @override
  String get messageNoLongerCurrentError => 'このメッセージは現在の会話にありません。戻って更新してください。';

  @override
  String get regenerationUserMessageMissingError =>
      '再生成できません。有効なユーザーメッセージがありません。';

  @override
  String get regenerationTargetMissingError => '再生成できません。対象のユーザーメッセージが見つかりません。';

  @override
  String get modelRegenerationStarting => '再生成中…';

  @override
  String modelSwitchedSuccess(String model) {
    return 'モデルを切り替えました: $model';
  }

  @override
  String get modelSwitchFailed => 'モデルを切り替えられませんでした。もう一度お試しください。';

  @override
  String get serviceProviderSection => 'サービスプロバイダー';

  @override
  String get serviceProviderDescription =>
      '公式 API またはローカル／サードパーティ互換サービスを選択します。';

  @override
  String get llmProviderLabel => 'LLMプロバイダー';

  @override
  String get recentModelsSection => '最近使用したモデル';

  @override
  String get recentModelsDescription => 'このデバイスで使用したモデルにすばやく切り替えます。';

  @override
  String get recommendedModelsSection => 'おすすめモデル';

  @override
  String get recommendedModelsDescription => '創作やロールプレイ向けに最適化されたモデルです。';

  @override
  String get customModelSection => 'カスタムモデル名';

  @override
  String get deepseekCustomModelDescription =>
      '他の DeepSeek 専用モデルを使う場合は、ここに入力してください。';

  @override
  String get otherCustomModelDescription =>
      '互換エンドポイントのモデル ID を入力します（例: gpt-4o、claude-3-5-sonnet）。';

  @override
  String get modelNamePlaceholder => 'モデル名を入力…';

  @override
  String customModelSelected(String model) {
    return 'カスタムモデルを選択しました: $model';
  }

  @override
  String get adventureBlankSlateTitle => '新たな冒険の始まり';

  @override
  String get adventureBlankSlateDescription =>
      'このシーンにはまだ会話や行動の記録がありません。\n下に行動を入力するか、探索したい方向を選んで冒険を始めましょう。';

  @override
  String get beginAdventureAction => '冒険を始める';

  @override
  String get deepSeekFlashModelSubtitle =>
      '最新のおすすめ DeepSeek V4.1 Flash · マルチモーダル · 深い思考に対応';

  @override
  String get deepSeekLegacyModelSubtitle =>
      '旧モデルです。DeepSeek V4.1 Flash への移行をおすすめします';

  @override
  String get deleteDetectedStatusTitle => '状態を削除';

  @override
  String confirmDeleteDetectedStatus(String name) {
    return '状態「$name」を削除しますか？';
  }

  @override
  String get statusNameLabel => '状態名 *';

  @override
  String get statusNameExamples => '例: 正気度(SAN)、好感度、汚染度、空腹度';

  @override
  String get measurementModeLabel => '値の形式:';

  @override
  String get numericGaugeMode => '数値ゲージ (0～100)';

  @override
  String get phaseDescriptionMode => '段階の説明';

  @override
  String get currentValueLabel => '現在値';

  @override
  String get maxValueLabel => '最大値';

  @override
  String get currentPhaseLabel => '現在の段階／説明';

  @override
  String get currentPhaseExamples => '例: 通常、軽度汚染、ほろ酔い、狂戦士化中';

  @override
  String get chooseStatusIcon => '状態アイコンを選択:';

  @override
  String get statusRuleLabel => '判定ルール／ストーリー指示（任意）';

  @override
  String get statusRuleHint => '例: 20未満でパニック。判定成功で正気を保ち、失敗すると幻覚が発生';

  @override
  String get storyImportanceLabel => 'ストーリー上の重要度:';

  @override
  String get statusNameRequiredError => '状態名を入力してください。';

  @override
  String get addDetectedStatusAction => '状態を追加';

  @override
  String detectedStatusesCount(int count) {
    return 'カスタム状態 ($count)';
  }

  @override
  String get combatAdventureMatrix => '戦闘と冒険の能力';

  @override
  String get physicalAttackStat => '物理攻撃 (ATK)';

  @override
  String get baseDefenseStat => '基礎防御 (DEF)';

  @override
  String get agilitySpeedStat => '敏捷性 (SPD)';

  @override
  String get goldStat => '所持金 (Gold)';

  @override
  String get availableSkillPointsStat => '使用可能なスキルポイント';

  @override
  String get currentSceneCoordinatesStat => '現在のシーン座標';

  @override
  String get openInventoryAction => 'インベントリを開く';

  @override
  String get profileIdentityTitle => '📜 身分と役割';

  @override
  String get profileBackgroundTitle => '📖 背景と経歴';

  @override
  String get profileWorldviewTitle => '🌍 世界観';

  @override
  String get profilePersonalityTitle => '🎭 性格';

  @override
  String get profileRelationshipsTitle => '🤝 絆と関係';

  @override
  String get profileAppearanceTitle => '✨ 外見と体格';

  @override
  String get checkAction => '判定';

  @override
  String levelRoleSummary(int level, String role) {
    return 'Lv. $level · $role';
  }

  @override
  String get editDetectedStatusTitle => '状態を編集';

  @override
  String get noCustomDetectedStatuses => 'カスタム状態はありません';

  @override
  String get detectedStatusesEmptyDescription =>
      '正気度(SAN)、好感度、汚染度、空腹度、魔力過負荷などの冒険状態を作成できます。';

  @override
  String get energyLabel => 'エネルギー';

  @override
  String get combatStatsTitle => '戦闘能力';

  @override
  String get currentValuePrefix => '現在値: ';

  @override
  String get currentPhaseWithThoughtsLabel => '現在の状態／考え';

  @override
  String get phaseNotTriggered => '（段階判定はまだ発生していません）';

  @override
  String statusRulePrefix(String rule) {
    return '📌 ルール: $rule';
  }

  @override
  String get companionsTab => 'ステータス';

  @override
  String get equipmentTab => '装備';

  @override
  String get profileTab => '人物像';

  @override
  String currentExplorationRegion(String scene) {
    return '現在の探索エリア: $scene';
  }

  @override
  String mainStoryChapter(int chapter) {
    return 'メイン冒険者 · 第$chapter章';
  }

  @override
  String relationshipLabel(String relation) {
    return '関係: $relation';
  }

  @override
  String affinityScoreLabel(int affinity) {
    return '❤️ 好感度: $affinity';
  }

  @override
  String get healthPointsLabel => '生命力 (HP)';

  @override
  String get lifeForceLabel => '活力';

  @override
  String get magicPointsLabel => '精神魔法 (MP)';

  @override
  String get focusLabel => '集中力';

  @override
  String get actionEnergyLabel => '行動エネルギー';

  @override
  String get tiredStatus => '⚠️ 疲労';

  @override
  String get goodStatus => '良好';

  @override
  String get experienceLabel => '経験値 (EXP)';

  @override
  String nextLevelExperience(int count) {
    return '次のレベルまで $count';
  }

  @override
  String skillPointsValue(int count) {
    return '$countポイント';
  }

  @override
  String equippedGearCount(int count) {
    return '⚔️ 装備中 ($count)';
  }

  @override
  String get noEquippedGear => '装備がありません。インベントリやショップで装備を入手すると戦闘力が上がります。';

  @override
  String gearSlotQuality(String slot, String quality) {
    return '部位: $slot · 品質: $quality';
  }

  @override
  String get carriedItemsTitle => '🎒 所持品と素材';

  @override
  String get noCarriedItems => '所持品はありません。';

  @override
  String get sharedPartyInventory => '📦 パーティー共有インベントリ:';

  @override
  String get detectedStatusFormDescription =>
      'ゲージ、判定ルール、ダイスロールを使って冒険中の状態を追跡します。';

  @override
  String get statusPresetsHeading => '💡 プリセット例（タップして入力）:';

  @override
  String get explorerRole => '冒険者';

  @override
  String get startingTown => '始まりの町';

  @override
  String get defaultProtagonistProfile => '未知の辺境を探索し、物語の決断を担う臨機応変な冒険者。';

  @override
  String get defaultProtagonistBackground => '激動の世界へ旅立ち、未知の運命を切り開きます。';

  @override
  String get defaultWorldviewDescription => '物語の進行に合わせて変化する、没入型ロールプレイ世界。';

  @override
  String get defaultCompanionPersonality => '旅を通して本当の願いを見せていく、物静かな性格。';

  @override
  String genderTag(String value) {
    return '性別: $value';
  }

  @override
  String heightTag(String value) {
    return '身長: $value';
  }

  @override
  String hairstyleTag(String value) {
    return '髪型: $value';
  }

  @override
  String skinToneTag(String value) {
    return '肌の色: $value';
  }

  @override
  String facialFeaturesTag(String value) {
    return '顔立ち: $value';
  }

  @override
  String get aliveStatus => '💚 健康';

  @override
  String get incapacitatedStatus => '💀 行動不能';

  @override
  String companionRelationshipSummary(String relation, int affinity) {
    return '主人公との関係: $relation。現在の好感度: $affinity/100。';
  }

  @override
  String get diceCriticalSuccess => 'クリティカル成功！完璧な判定です。';

  @override
  String get diceCriticalFailure => 'ファンブル！重大な失敗や反動が発生しました。';

  @override
  String get diceSuccess => '判定成功！異常に抵抗し、状態を維持しました。';

  @override
  String get diceFailure => '判定失敗！状態への影響や悪影響を受けました。';

  @override
  String get diceCheckCriticalSuccess => 'クリティカル成功！限界を突破しました。';

  @override
  String get diceCheckCriticalFailure => 'クリティカル失敗！判定に完全に失敗しました。';

  @override
  String get diceCheckPassed => '判定成功！状態は安定しています。';

  @override
  String get diceCheckFailed => '判定失敗！妨害や悪影響を受けました。';

  @override
  String diceTargetValue(int current, int maximum) {
    return '目標値: $current / $maximum';
  }

  @override
  String diceCurrentStatus(String status) {
    return '現在の状態: $status';
  }

  @override
  String diceRuleDescription(String rule) {
    return '判定ルール: $rule';
  }

  @override
  String get d100PercentileDie => 'D100 パーセンタイルダイス';

  @override
  String get d20Die => 'D20 ダイス';

  @override
  String get rollCheckAction => '判定ダイスを振る';

  @override
  String get rerollAction => '振り直す';

  @override
  String get syncResultToAdventure => '冒険ストーリーに追加';

  @override
  String diceResultPoints(String icon, int value, String denominator) {
    return '$icon 出目: $value $denominator';
  }

  @override
  String get diceResultWillBeSent => '結果はユーザーメッセージとして送信されます。';

  @override
  String diceResultMessage(String status, String rule, String character,
      int roll, String target, String verdict) {
    return '【状態判定】$character が「$status」を判定: 🎲 $roll ($target) → 【$verdict】！$rule';
  }

  @override
  String get allItemsFilter => 'すべて';

  @override
  String get consumableItemType => '消耗品';

  @override
  String get equipmentItemType => '装備品';

  @override
  String get materialItemType => '素材';

  @override
  String get questItemType => 'クエストアイテム';

  @override
  String get weaponSlot => '武器';

  @override
  String get armorSlot => '防具';

  @override
  String get accessorySlot => 'アクセサリー';

  @override
  String get specialSlot => '特殊';

  @override
  String get commonQuality => 'コモン';

  @override
  String get uncommonQuality => 'アンコモン';

  @override
  String get rareQuality => 'レア';

  @override
  String get epicQuality => 'エピック';

  @override
  String get legendaryQuality => 'レジェンダリー';

  @override
  String get emptyInventoryTitle => 'インベントリは空です';

  @override
  String get emptyInventoryDescription => '物語で入手したアイテムがここに表示されます。';

  @override
  String get deepThinkingStatus => '深く考えています…';

  @override
  String get reasoningExpandedLabel => '思考過程（タップして折りたたむ）';

  @override
  String get reasoningCollapsedLabel => '思考完了（タップして推論を表示）';

  @override
  String get thinkingInProgressStatus => '考えています…';

  @override
  String get reasoningUnavailableLabel => '（記録なし）';

  @override
  String get copyReasoningAction => '推論をコピー';

  @override
  String get writingStoryStatus => 'ストーリーを執筆中…';

  @override
  String get dialogueReplyLengthSettingsTitle => 'シーンの返信量を調整';

  @override
  String dialogueCurrentSelection(String id, String name, String range) {
    return '選択中: $id · $name ($range)';
  }

  @override
  String dialogueWordsAbove(int minWords) {
    return '$minWords語以上';
  }

  @override
  String get dialogueLevelFast => '高速';

  @override
  String get dialogueLevelConcise => '簡潔';

  @override
  String get dialogueLevelStandard => '標準';

  @override
  String get dialogueLevelDetailed => '詳細';

  @override
  String get dialogueLevelDeep => '深い描写';

  @override
  String get dialogueLevelProduction => '長文作成';

  @override
  String get dialogueLevelFastDesc => '要点のみを返し、すばやく確認できます。';

  @override
  String get dialogueLevelConciseDesc => '軽いやり取り向けの短い進行です。';

  @override
  String get dialogueLevelStandardDesc => '速度と没入感のバランスが取れた標準モードです。';

  @override
  String get dialogueLevelDetailedDesc => 'より詳しい描写とやり取りを行います。';

  @override
  String get dialogueLevelDeepDesc => '伏線、心理、場面の重層性を重視します。';

  @override
  String get dialogueLevelProductionDesc => '本格的な執筆向けの長文出力です。';

  @override
  String get adventureRefreshUnavailable => '生成中、またはシーンを利用できないため更新できません。';

  @override
  String get sessionOfflineHint => 'オフライン — ネットワークに接続できません';

  @override
  String get sessionInputHint => '行動や会話を入力…';

  @override
  String get messageGestureHint => '右スワイプで再試行 · 左スワイプで削除 · 長押しで編集またはブックマーク';

  @override
  String get adventureAssistantName => '冒険アシスタント';

  @override
  String get currentUserDisplayName => '自分';

  @override
  String get unknownRegion => '未知の地域';

  @override
  String get deepThinkingBadge => '深く考える';

  @override
  String get supportingCharacterRole => '仲間';

  @override
  String get autoSwitchCharacterTooltip => 'キャラクターを自動で切り替える';

  @override
  String get sessionSettlingStatus => '選択肢とターンの状態を生成中…';

  @override
  String get aiReplyLabel => 'AI の返信';

  @override
  String sectionValidationPassed(String title) {
    return '「$title」の検証に合格しました';
  }

  @override
  String sectionValidationFailed(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件の問題',
    );
    return '「$title」の検証に失敗しました：$_temp0';
  }

  @override
  String get sectionValidationComplete => '検証が完了しました';

  @override
  String sectionRegenerated(String title, int completed, int total) {
    return '「$title」の $total パート中 $completed パートを再生成しました';
  }

  @override
  String sectionRegenerationFailed(String title, String error) {
    return '「$title」の生成を中止しました：$error';
  }

  @override
  String get sectionGenerationComplete => '生成が完了しました';

  @override
  String get capacityNoCompressionNeeded => '圧縮が必要なセクションはありません。';

  @override
  String get capacityCompressionAlreadyPublished =>
      'この圧縮候補は公開済みです。本文は再度変更されていません。';

  @override
  String capacityCompressionPublished(int savedCharacters) {
    return '圧縮候補を公開しました。約 $savedCharacters 文字を削減し、公開前の本文は履歴に保存しました。';
  }

  @override
  String capacityRetryBlockedByActiveTarget(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件の失敗タスクをスキップしました。',
    );
    return '対象ですでに圧縮が進行中のため、$_temp0';
  }

  @override
  String capacityRetryBudgetExhausted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件は再試行上限に達しています。',
    );
    return '再試行できる圧縮タスクはありません。$_temp0';
  }

  @override
  String get capacityRetryUnavailable => '再試行できる圧縮タスクはありません。';

  @override
  String capacityCompressionRunSummary(int succeeded, int failed, int requeued,
      int activeSkipped, int exhaustedSkipped) {
    return '候補 $succeeded 件を生成、失敗 $failed 件、再試行 $requeued 件、対象の圧縮中につきスキップ $activeSkipped 件、再試行上限によりスキップ $exhaustedSkipped 件。候補の反映には確認が必要です。失敗したタスクでは本文は変更されません。';
  }

  @override
  String get revisionCauseManualSave => '手動保存';

  @override
  String get revisionCauseGeneration => 'AI生成';

  @override
  String get revisionCausePlanning => 'アウトライン作成';

  @override
  String get revisionCauseRegeneration => '再生成';

  @override
  String get revisionCauseCompression => '意味圧縮';

  @override
  String get revisionCauseRestore => '復元';

  @override
  String get revisionCauseMigration => 'データ移行';

  @override
  String get revisionCauseDeletion => '削除前スナップショット';

  @override
  String get revisionUnknownDate => '日付不明';

  @override
  String get revisionAlreadyCurrent => 'このリビジョンはすでに現在の状態です。';

  @override
  String revisionRestored(String sourceCause) {
    return '「$sourceCause」リビジョンに復元しました。';
  }

  @override
  String revisionItemSubtitle(String date, int nodeCount, int charCount) {
    return '$date · ノード数 $nodeCount · 文字数 $charCount';
  }

  @override
  String resourceRevisionOperationFailed(String error) {
    return 'リビジョン操作に失敗しました: $error';
  }

  @override
  String get resourceTrashKindResource => 'リソース';

  @override
  String get resourceTrashKindSection => 'セクション';

  @override
  String get resourceTrashKindPart => '段落';

  @override
  String get resourceTrashReasonUserDelete => 'ユーザーによる削除';

  @override
  String get resourceTrashRestoreOriginal => '元の場所に復元しました。';

  @override
  String get resourceTrashRestoreFallback =>
      '元のセクションがないため、リソース直下の新しいセクションに復元しました。';

  @override
  String get resourceTrashRestoreToLibrary => 'リソースライブラリに復元しました。';

  @override
  String get resourceTrashAlreadyRestored => 'この項目はすでに復元されているため、変更はありません。';

  @override
  String resourceTrashLoadFailed(String error) {
    return 'ごみ箱を読み込めませんでした: $error';
  }

  @override
  String get unnamedSceneTitle => '無題のシーン';

  @override
  String get statusPresetSanityLabel => '🧠 正気度 (SAN)';

  @override
  String get statusPresetSanityName => '正気度 (SAN)';

  @override
  String get statusPresetSanityDescription =>
      '未知や恐怖に抗います。20未満になると幻覚に陥ることがあります。';

  @override
  String get statusPresetAffinityLabel => '❤️ キャラクター好感度';

  @override
  String get statusPresetAffinityName => '好感度';

  @override
  String get statusPresetAffinityDescription =>
      'キャラクターとの絆を表します。一定値に達すると専用の物語や交流が解放されます。';

  @override
  String get statusPresetCorruptionLabel => '☣️ 深淵の侵食';

  @override
  String get statusPresetCorruptionName => '深淵の侵食度';

  @override
  String get statusPresetCorruptionDescription =>
      '肉体と精神の変化が蓄積します。高くなりすぎると異形化することがあります。';

  @override
  String get statusPresetHungerLabel => '🍖 空腹／満腹';

  @override
  String get statusPresetHungerName => '満腹度';

  @override
  String get statusPresetHungerDescription =>
      '探索に必要な体力を表します。30未満になると衰弱や疲労が生じることがあります。';

  @override
  String get statusPresetMagicLabel => '🔥 魔力過負荷';

  @override
  String get statusPresetMagicName => '魔力過負荷';

  @override
  String get statusPresetMagicDescription =>
      '体内で暴走する力です。過負荷状態での詠唱は、自傷や暴発を招くことがあります。';

  @override
  String get statusPresetPressureLabel => '⚡ 精神的ストレス';

  @override
  String get statusPresetPressureName => '精神的ストレス';

  @override
  String get statusPresetPressureDescription => '恐怖や危機によって蓄積する心理的な負荷を表します。';

  @override
  String get statusPresetArmorLabel => '🛡️ 防具の耐久度';

  @override
  String get statusPresetArmorName => '防具耐久度';

  @override
  String get statusPresetArmorDescription => '防具の耐久性を表し、外部からの衝撃を優先して受け止めます。';

  @override
  String get statusPresetSpiritLabel => '💧 霊力の蓄え';

  @override
  String get statusPresetSpiritName => '霊力の蓄え';

  @override
  String get statusPresetSpiritDescription => '術や神通力を使うための中心となる霊的エネルギーです。';

  @override
  String get adventureDefaultOpeningScene =>
      '見知らぬ辺境で目を覚ます。周囲は静まり返っている。荷物を確かめ、最初の一歩を踏み出そうとする。';

  @override
  String get adventureDefaultOpeningOptionOne => '持ち物と地図を確認する';

  @override
  String get adventureDefaultOpeningOptionTwo => '目の前の道を進んで探索を続ける';

  @override
  String get adventureDefaultOpeningOptionThree => '身を隠して周囲の様子をうかがう';

  @override
  String get autosaveTriggerDebounce => '入力停止後の保存';

  @override
  String get autosaveTriggerMaxBufferedAge => '連続入力中の保存';

  @override
  String get autosaveTriggerManual => '手動保存';

  @override
  String get autosaveTriggerPageLeave => 'ページを離れる前の保存';

  @override
  String get autosaveTriggerDispose => 'エディターを閉じる前の保存';

  @override
  String get autosaveTriggerCancel => '生成をキャンセルする前の保存';

  @override
  String get autosaveTriggerGenerationError => '生成失敗を報告する前の保存';

  @override
  String get autosaveTriggerAppLifecycle => 'アプリをバックグラウンドに移す前の保存';

  @override
  String get revisionBeforeRestore => '復元前';

  @override
  String get revisionBeforeCompression => '圧縮前';

  @override
  String get revisionAssembly => '組み立てスナップショット';

  @override
  String revisionCompressionSaved(int characters) {
    return '意味圧縮（$characters文字削減）';
  }

  @override
  String get revisionModeRegenerate => '再生成';

  @override
  String get revisionModeRewrite => '書き換え';

  @override
  String get revisionModeExpand => '拡張';

  @override
  String get revisionModeCondense => '要約';

  @override
  String revisionBeforeRegeneration(String mode) {
    return '$modeの前';
  }

  @override
  String readAloudSegmentProgress(int current, int total) {
    return '$total段中$current段目';
  }

  @override
  String sessionTokenUsageMeter(int current, int limitThousands) {
    return '$current / ${limitThousands}K トークン';
  }

  @override
  String combatStatsSummary(int attack, int defense, int speed) {
    return '戦闘能力 · 攻撃 $attack · 防御 $defense · 速度 $speed';
  }

  @override
  String get adventureAssetNotManaged =>
      'このアセットは統合リソースライブラリにないため、組み立て準備の確認対象ではありません。';

  @override
  String get adventureAssemblyMissingCharacterCard =>
      '組み立て版にキャラクターカードがないため、冒険を開始できません。';

  @override
  String get adventureAssemblyInvalidCharacterCard =>
      '組み立て版のキャラクターカードを読み取れないため、冒険を開始できません。';

  @override
  String adventureAssetNoSavedRevision(String name) {
    return '「$name」には保存済みのリビジョンがないため、冒険を開始できません。';
  }

  @override
  String adventureAssetPreparing(String name) {
    return '「$name」を組み立てています。しばらくお待ちください。';
  }

  @override
  String adventureAssetPreparingWithDetails(String name, String details) {
    return '「$name」を組み立てています：$details';
  }

  @override
  String adventureAssetPreparationFailed(String name, String details) {
    return '「$name」の組み立てに失敗しました：$details';
  }

  @override
  String adventureAssetReady(String name) {
    return '「$name」の準備ができました。';
  }

  @override
  String adventureAssetNoAssemblyRevision(String name) {
    return '「$name」には利用可能なリビジョンがありません。先に組み立てを完了してください。';
  }

  @override
  String adventureAssetStaleWithPrevious(String name) {
    return '「$name」は変更されています。前回準備済みのバージョンを使用できます。';
  }

  @override
  String get errorUnknown => '不明なエラーが発生しました。もう一度お試しください。';

  @override
  String get errorNetworkUnavailable => 'ネットワーク接続に失敗しました。接続を確認して再試行してください。';

  @override
  String get errorRequestTimeout => 'リクエストがタイムアウトしました。もう一度お試しください。';

  @override
  String get errorUnauthorized => '認証に失敗しました。API 設定を確認してください。';

  @override
  String get errorPaymentRequired => 'API アカウントの確認が必要です。';

  @override
  String get errorForbidden => 'アクセスが拒否されました。API 権限を確認してください。';

  @override
  String get errorNotFound => '要求されたモデルまたはエンドポイントが見つかりません。';

  @override
  String get errorRateLimited => 'リクエストが多すぎます。しばらくして再試行してください。';

  @override
  String get errorInvalidRequest => 'リクエストを処理できません。設定を確認して再試行してください。';

  @override
  String resourceErrorCapacityExceeded(int current, int limit) {
    return 'リソース容量を超えました（$current/$limit）。';
  }

  @override
  String resourceErrorValidationFailed(String details) {
    return 'リソースの検証に失敗しました：$details';
  }

  @override
  String get resourceErrorGenerationFailed => 'リソースの生成に失敗しました。再試行してください。';

  @override
  String get resourceErrorConflict => 'リソースが変更されました。再読み込みして再試行してください。';

  @override
  String adventureErrorAssetMissing(String name) {
    return '「$name」は冒険の準備ができていません。';
  }

  @override
  String adventureErrorAssetStale(String name) {
    return '「$name」が変更されたため、再準備が必要です。';
  }

  @override
  String get ttsErrorUnsupported => 'この環境では読み上げを利用できません。';

  @override
  String get ttsErrorEngineUnavailable => '読み上げエンジンを利用できません。';

  @override
  String get ttsErrorVoiceUnavailable => '選択した音声を利用できません。';

  @override
  String get ttsErrorPlaybackFailed => '読み上げに失敗しました。もう一度お試しください。';

  @override
  String eventCombatVictory(int exp, int gold) {
    return '勝利！EXP $exp とゴールド $gold を獲得しました。';
  }

  @override
  String eventCombatAttack(String actor) {
    return '$actor が攻撃しました。';
  }

  @override
  String eventCombatCriticalHit(String actor) {
    return '$actor のクリティカルヒット！';
  }

  @override
  String eventCombatSkillUsed(String skill) {
    return 'スキル「$skill」を使用しました。';
  }

  @override
  String get eventCombatDefeat => '敗北しました。';

  @override
  String eventLevelUp(int level) {
    return 'レベルアップ！レベル $level になりました。';
  }

  @override
  String get eventRestCompleted => '休息が完了しました。';

  @override
  String eventItemAdded(String item) {
    return '$item を獲得しました。';
  }

  @override
  String eventItemRemoved(String item) {
    return '$item を削除しました。';
  }

  @override
  String eventItemUsed(String item) {
    return '$item を使用しました。';
  }

  @override
  String eventSkillLearned(String skill) {
    return 'スキル「$skill」を習得しました。';
  }

  @override
  String get eventSkillFailed => 'スキルを使用できませんでした。';

  @override
  String get errorImportInvalidInput => 'インポート入力が無効です。';

  @override
  String get errorImportParseFailed => 'インポートデータを解析できませんでした。';

  @override
  String get errorImportUnsupportedFormat => 'このインポート形式はサポートされていません。';

  @override
  String get adventureErrorReadinessFailed => '冒険の準備状態を確認できませんでした。';

  @override
  String get readinessDiagnosticNoSavedRevision => '利用可能な保存済みリビジョンがありません。';

  @override
  String get readinessDiagnosticCompressionUnavailable =>
      '容量を超えていますが、利用可能な圧縮コンポーネントがありません。';

  @override
  String get readinessDiagnosticCompressionPending => '圧縮準備をキューに追加しました。';

  @override
  String get readinessDiagnosticStaleResource => '準備中にリソースが変更されました。';

  @override
  String get readinessDiagnosticAssemblyRevisionMissing =>
      '組み立て済みリビジョンを利用できません。';

  @override
  String get readinessDiagnosticPreparationFailed => 'リソースの準備に失敗しました。';

  @override
  String get readinessDiagnosticInterruptedPreparation =>
      '前回の準備は中断されました。再試行できます。';

  @override
  String get readinessDiagnosticUnknown => 'リソースの準備状態を確認できません。';

  @override
  String get partEditorDiscardedRemoteText => '自分のテキストを破棄し、最新の内容を採用しました';

  @override
  String get sectionValidationIssueEmptySection => 'セクションにパートがありません';

  @override
  String sectionValidationIssuePartMissing(Object part) {
    return '$partに本文がありません';
  }

  @override
  String sectionValidationIssuePartTooLong(
      Object actual, Object limit, Object part) {
    return '$partは$actual文字で、上限は$limit文字です';
  }

  @override
  String get runtimeStateNoChanges => 'ランタイム変更はまだありません';

  @override
  String get runtimeStateStructuredValue => '構造化された値';

  @override
  String get runtimeStateLegacy => '過去の記録';

  @override
  String get runtimeStateHistoricalChange => '過去の状態変更';

  @override
  String get runtimeStateCommittedEvent => 'コミット済みランタイムイベント';

  @override
  String runtimeStateRevision(Object revision) {
    return 'リビジョン $revision';
  }

  @override
  String get runtimeStateCurrent => '現在の状態';

  @override
  String get runtimeStateInitial => '初期ベースライン';

  @override
  String get runtimeStateResetToBaseline => 'ベースラインに戻す';

  @override
  String get runtimeStateKeepOverride => '上書きを保持';

  @override
  String get runtimeStateEditConflict => '状態が変更されました。再読み込みしてから編集してください。';

  @override
  String get runtimeStateIntegerRequired => '整数を入力してください';

  @override
  String get runtimeStateNumberRequired => '有効な数値を入力してください';

  @override
  String get runtimeStateValueRequired => '有効な値を入力してください';

  @override
  String get runtimeStateValueTooSmall => '最小値を下回っています';

  @override
  String get runtimeStateValueTooLarge => '最大値を超えています';

  @override
  String get runtimeStateFieldHp => 'HP';

  @override
  String get runtimeStateFieldMp => 'MP';

  @override
  String get runtimeStateFieldEnergy => 'エネルギー';

  @override
  String get runtimeStateFieldExperience => '経験値';

  @override
  String get runtimeStateFieldLevel => 'レベル';

  @override
  String get runtimeStateFieldBaseAtk => '攻撃';

  @override
  String get runtimeStateFieldBaseDef => '防御';

  @override
  String get runtimeStateFieldBaseSpeed => '速度';

  @override
  String get runtimeStateFieldAffinity => '好感度';

  @override
  String get runtimeStateFieldLifeStatus => '生命状態';

  @override
  String get runtimeStateFieldLifecycleStatus => 'ライフサイクル';

  @override
  String get runtimeStateFieldGlobalFlag => 'グローバルフラグ';

  @override
  String get runtimeStateFieldFactionId => '派閥';

  @override
  String get runtimeStateFieldFormerFactionId => '旧派閥';

  @override
  String get runtimeStateFieldControllerId => '管理者';

  @override
  String get runtimeStateFieldRelationship => '関係';

  @override
  String get runtimeStateFieldGoal => '目標';

  @override
  String get runtimeStateFieldStatus => '状態';

  @override
  String get runtimeStateFieldControl => '制御';

  @override
  String get runtimeStateFieldEnvironment => '環境';

  @override
  String get runtimeStateFieldCondition => '状況';

  @override
  String get runtimeStateFieldInfluence => '影響力';

  @override
  String get runtimeStateFieldTime => '時間';

  @override
  String get sceneCharactersTitle => 'シーンのキャラクター';

  @override
  String get sceneCharactersPresent => '参加中';

  @override
  String get sceneCharactersAvailable => '冒険で利用可能';

  @override
  String get sceneCharactersAdd => 'キャラクターを追加';

  @override
  String get sceneCharactersEnter => 'シーンに入る';

  @override
  String get sceneCharactersLeave => 'シーンから退出';

  @override
  String get sceneCharactersEmpty => '利用可能なキャラクターはありません';

  @override
  String get sceneCharactersConflict => 'シーンが変わりました。再読み込みして再試行してください。';

  @override
  String get characterManagementTitle => 'キャラクター管理';

  @override
  String get characterManagementAdd => 'キャラクターを追加';

  @override
  String get characterManagementPresent => '現在シーンにいるキャラクター';

  @override
  String get characterManagementJoined => '冒険に参加中';

  @override
  String get characterManagementInScene => 'シーン内';

  @override
  String get characterManagementOutOfScene => 'シーン外';

  @override
  String get characterManagementAlive => '生存';

  @override
  String get characterManagementDead => '死亡';

  @override
  String get characterManagementUnknown => '不明';

  @override
  String get characterManagementNoData => 'データなし';

  @override
  String get characterManagementViewStatus => '現在の状態を見る';

  @override
  String get characterManagementManage => 'キャラクターを管理';

  @override
  String get characterManagementGold => '所持金';

  @override
  String get runtimeStateCompare => '比較';

  @override
  String get runtimeStateSaveSnapshot => 'スナップショットを保存';

  @override
  String get runtimeStateSnapshotName => '名前';

  @override
  String get runtimeStateSnapshotNote => 'メモ';

  @override
  String get runtimeStateCompareCurrent => '現在と比較';

  @override
  String runtimeStateChangedFields(Object count) {
    return '$count 件のフィールドが変更';
  }

  @override
  String get runtimeStateUnableCompare => '比較できません';

  @override
  String get runtimeStateNoAdventure => 'アクティブな冒険がありません';

  @override
  String get runtimeStateHead => 'HEAD';

  @override
  String get runtimeStateCheckpoint => 'チェックポイント';

  @override
  String get runtimeStateAll => 'すべて';

  @override
  String get runtimeStateNotInInitial => '初期状態には含まれません';

  @override
  String runtimeStateTurnLabel(Object number) {
    return '第 $numberターン';
  }

  @override
  String runtimeStateRevisionRange(Object from, Object to) {
    return 'ランタイムリビジョン $from → $to';
  }

  @override
  String get runtimeStateRelationships => '関係';

  @override
  String get runtimeStateSignificantChange => '重大变化';

  @override
  String get runtimeStateFieldUnknown => 'Unknown state';

  @override
  String get runtimeStateConfigured => 'Configured';

  @override
  String get runtimeStateAlive => 'Alive';

  @override
  String get runtimeStateDead => 'Dead';

  @override
  String get runtimeStateActive => 'Active';

  @override
  String get runtimeStateInactive => 'Inactive';

  @override
  String get runtimeStateDestroyed => 'Destroyed';

  @override
  String get runtimeStateCauseDialogue => 'Dialogue';

  @override
  String get runtimeStateCauseUserEdit => 'User edit';

  @override
  String get runtimeStateCauseSystem => 'System event';

  @override
  String get runtimeStateCauseRestore => 'State restored';

  @override
  String get runtimeStateCauseImport => 'インポート';

  @override
  String get runtimeStateChangedState => '状態変更';

  @override
  String get runtimeStateNoVisibleChanges => 'このターンで表示可能な状態変化はありません';

  @override
  String get runtimeStateTurnSummary => 'ターンの概要';

  @override
  String get runtimeStateWorldChanges => '世界の変化';

  @override
  String get runtimeStateCharacterChanges => 'キャラクターの変化';

  @override
  String get runtimeStateChangeBefore => '変更前';

  @override
  String get runtimeStateChangeAfter => '変更後';

  @override
  String get runtimeStateChangeReason => '理由';

  @override
  String get runtimeStateSource => 'ソース';

  @override
  String get runtimeStateAffectedEntities => '影響を受けた対象';

  @override
  String get runtimeStateMainStory => 'メインストーリー';

  @override
  String get runtimeStateCurrentBranch => '現在の分岐';

  @override
  String get runtimeStateRecentChange => '最近の状態変化';

  @override
  String get runtimeStateInScene => 'その場にいる';

  @override
  String get runtimeStateBaselineProfile => 'ベースライン設定';

  @override
  String get runtimeStateDynamicState => 'ランタイム動的状態';

  @override
  String get runtimeStateTrue => 'はい';

  @override
  String get runtimeStateFalse => 'いいえ';

  @override
  String runtimeStateTotalTurns(Object count) {
    return '合計 $count ターン';
  }

  @override
  String runtimeStateChangeCount(Object count) {
    return '$count 件の状態変化';
  }

  @override
  String get runtimeStateOverview => '概要';

  @override
  String get runtimeStateUnknownTurn => '不明なターン';

  @override
  String get runtimeStateUnknownEntity => '不明なエンティティ';

  @override
  String get runtimeStateUnknownSource => '不明なソース';

  @override
  String get resourceLifecyclePlanning => '構成企画中';

  @override
  String get resourceLifecycleGenerating => '本文生成中';

  @override
  String get resourceLifecycleValidating => '検証中';

  @override
  String get resourceLifecycleReady => '準備完了';

  @override
  String get resourceLifecycleFailed => '生成失敗';

  @override
  String get resourceLifecycleCancelled => 'キャンセル済み';

  @override
  String get resourceLifecycleRecovering => '復旧中';

  @override
  String get resourceLifecycleTrashed => 'ゴミ箱';

  @override
  String get resourceLifecycleDraft => '下書き';

  @override
  String get resourceLifecyclePaused => '一時停止';

  @override
  String get resourceLifecycleArchived => 'アーカイブ済み';

  @override
  String get resourceConsumableBadge => '冒険で使用可能';

  @override
  String get resourceNotConsumableBadge => '冒険で使用不可';

  @override
  String get resourceUseForAdventure => '冒険を作成';

  @override
  String get resourceNotConsumableTip => 'リソースの準備が完了するまで冒険を作成できません。';

  @override
  String get resourceFilterStatusAll => 'すべてのステータス';

  @override
  String get resourceFilterStatusReady => '準備完了';

  @override
  String get resourceFilterStatusInProgress => '処理中';

  @override
  String get resourceFilterStatusDraft => '下書き';

  @override
  String get resourceFilterStatusFailed => '失敗/停止';

  @override
  String get resourceSortUpdatedDesc => '更新日時 (新しい順)';

  @override
  String get resourceSortUpdatedAsc => '更新日時 (古い順)';

  @override
  String get resourceSortNameAsc => '名前 (A-Z)';

  @override
  String get resourceSortNameDesc => '名前 (Z-A)';

  @override
  String get resourceSortLabel => '並び替え';

  @override
  String get resourceStatusFilterLabel => 'ステータス';

  @override
  String resourcePaginationPageInfo(int page, int totalPages, int totalCount) {
    return '$page / $totalPages ページ (全 $totalCount 件)';
  }

  @override
  String get resourcePaginationPrev => '前へ';

  @override
  String get resourcePaginationNext => '次へ';

  @override
  String get resourceBlueprintReviewTitle => 'ブループリント確認';

  @override
  String get resourceBlueprintReviewSubtitle =>
      '生成を開始する前にセクションとパートの構成を確認してください。';

  @override
  String get resourceBlueprintConfirmAndGenerate => '確認して生成開始';

  @override
  String get resourceBlueprintPlanningNotice =>
      'ブループリントが作成されました。本文の生成はまだ開始されていません。';

  @override
  String get resourceBlueprintPlanAction => 'ブループリント作成';

  @override
  String get resourceBlueprintPlanning => 'ブループリント作成中...';

  @override
  String resourceBlueprintTotalEstimatedChars(int count) {
    return '推定文字数: 約 $count 文字';
  }

  @override
  String resourceSectionsCount(int count) {
    return '$count 個のセクション';
  }

  @override
  String resourcePartsCount(int count) {
    return '$count 個のパート';
  }

  @override
  String get resourceTreeStructureTitle => 'リソース構造ツリー';

  @override
  String get resourceTreeNoSections => 'セクションとパートはまだありません';

  @override
  String get resourceProvenanceLabel => 'ソース情報';

  @override
  String get resourceValidationStatusLabel => '検証ステータス';

  @override
  String get resourceValidationPassed => '検証合格';

  @override
  String get resourceValidationPending => '検証待ち / 検証中';

  @override
  String get resourceValidationFailed => '検証不合格';

  @override
  String get resourceSectionEmpty => '（パートなし）';

  @override
  String get resourcePartEmpty => '（本文なし）';

  @override
  String resourcePartCharCount(int count) {
    return '$count 文字';
  }

  @override
  String get resourceDetailOpenStudio => 'スタジオを開く';

  @override
  String get resourceDetailRetryGeneration => '生成を再試行';

  @override
  String get resourceDetailCancelGeneration => '生成をキャンセル';

  @override
  String get resourceDetailRecoverTask => 'タスク復旧';

  @override
  String get resourceDetailCancelConfirmTitle => '生成タスクのキャンセル';

  @override
  String get resourceDetailCancelConfirmMessage =>
      '生成タスクをキャンセルしてもよろしいですか？生成済みの内容は保持されます。';

  @override
  String get resourceDetailCancelSuccess => '生成がキャンセルされました';

  @override
  String get resourceDetailRecoverSuccess => 'タスクが正常に復旧しました';

  @override
  String get resourceDetailRecoverFailed => 'タスクの復旧に失敗しました';

  @override
  String resourceDetailActionFailed(String error) {
    return '操作に失敗しました: $error';
  }

  @override
  String resourceLastUpdated(String time) {
    return '更新日時: $time';
  }

  @override
  String get resourceInFlightGenerating => '本文を生成中...';

  @override
  String get resourceInFlightValidating => '品質を検証中...';

  @override
  String get resourceInFlightRecovering => 'セッションを復旧中...';

  @override
  String get resourceInFlightPlanning => '構成を計画中...';
}
