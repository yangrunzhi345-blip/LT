// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => 'LT 영경';

  @override
  String get pageLoadError => '페이지 로드 오류';

  @override
  String get reloadAction => '다시 로드';

  @override
  String get loadingEnvironment => '환경 로딩 중...';

  @override
  String testingProviderConnection(String provider) {
    return '$provider 연결 테스트 중...';
  }

  @override
  String get modelConnectionFailed => '모델 연결 실패, 설정을 확인해 주세요';

  @override
  String get apiKeyNotConfiguredPrompt =>
      'API 키가 아직 설정되지 않았습니다. 설정 화면에서 구성할 수 있습니다';

  @override
  String get goToSettings => '설정으로 이동';

  @override
  String get createAdventureFailed => '시나리오 생성에 실패했습니다. 잠시 후 다시 시도해 주세요';

  @override
  String get navExplore => '탐색';

  @override
  String get navLibrary => '자료실';

  @override
  String get navSettings => '설정';

  @override
  String get sidebarNewAdventure => '새 모험';

  @override
  String get sidebarRecent => '최근 대화';

  @override
  String get sidebarManageConversations => '대화 일괄 관리';

  @override
  String get sidebarEmptyConversations => '지난 대화가 없습니다';

  @override
  String get sidebarUnnamedScene => '이름 없는 시나리오';

  @override
  String get sidebarDeleteDialogTitle => '시나리오 대화 삭제';

  @override
  String sidebarDeleteDialogMessage(String title) {
    return '「$title」 대화를 삭제하시겠습니까?\n삭제된 대화 기록과 이야기 전개는 복구할 수 없습니다.';
  }

  @override
  String get sidebarReturnHome => '탐색 로비로 돌아가기';

  @override
  String get sidebarExpand => '사이드바 펼치기';

  @override
  String get sidebarCollapse => '사이드바 접기';

  @override
  String get sidebarClose => '사이드바 닫기';

  @override
  String get brandSubtitle => '서사 및 세계 진화 공방';

  @override
  String get serviceConnected => '연결됨';

  @override
  String get serviceNotConfigured => '키 미설정';

  @override
  String get officialOnline => '온라인';

  @override
  String get languageSetupTitle => '언어 선택';

  @override
  String get languageSetupSubtitle => '애플리케이션 표시 언어를 선택해 주세요';

  @override
  String get languageSettingTitle => '언어';

  @override
  String get languageSettingSubtitle => '애플리케이션 표시 언어';

  @override
  String get confirmAction => '확인';

  @override
  String get cancelAction => '취소';

  @override
  String get deleteAction => '삭제';

  @override
  String get saveAction => '저장';

  @override
  String get continueAction => '계속';

  @override
  String get closeAction => '닫기';

  @override
  String get doneAction => '완료';

  @override
  String get editAction => '수정';

  @override
  String get retryAction => '다시 시도';

  @override
  String get copyAction => '복사';

  @override
  String get settingsCenter => '설정 센터';

  @override
  String get settingsSystemConfig => '시스템 구성';

  @override
  String get settingsReturnHome => '로비로 돌아가기';

  @override
  String get settingsReturnList => '설정 목록으로 돌아가기';

  @override
  String get settingsPreferencesCategory => '환경설정 분류';

  @override
  String get settingsCoreEngine => '영경 코어 엔진';

  @override
  String get settingsStorageType => 'SQLite · 로컬 암호화 우선';

  @override
  String get tabModelApi => '모델 및 API';

  @override
  String get tabModelApiSubtitle => '제공자 및 키 설정';

  @override
  String get tabSessionParams => '세션 매개변수';

  @override
  String get tabSessionParamsSubtitle => '샘플링 및 심층 사고';

  @override
  String get tabThemeAppearance => '테마 및 외형';

  @override
  String get tabThemeAppearanceSubtitle => '라이트/다크 및 테마 색상';

  @override
  String get tabDataManagement => '데이터 관리';

  @override
  String get tabDataManagementSubtitle => 'Token 통계 및 저장소';

  @override
  String get configCategory => '설정 분류';

  @override
  String get apiServiceConnected => 'LLM 서비스 연결됨';

  @override
  String get apiServiceConnectedDesc => '클릭하여 제공자, 모델 및 엔드포인트 관리';

  @override
  String get apiServiceDisconnectedDesc => '추론을 시작하려면 API 키를 설정하세요';

  @override
  String get providerConfigTitle => '모델 제공자 및 API 설정';

  @override
  String get providerConfigSubtitle => '대규모 언어 모델 제공자, 엔드포인트 URL 및 보안 키를 구성합니다';

  @override
  String get testConnection => '연결 테스트';

  @override
  String get testingConnection => '테스트 중...';

  @override
  String get inputApiKeyHint => '유효한 API 키를 먼저 입력하세요';

  @override
  String connectionSuccess(int time) {
    return '연결 성공! 소요 시간 ${time}ms, 서비스 상태가 매우 좋습니다.';
  }

  @override
  String get connectionFailed => '연결 실패, 키와 네트워크 연결 상태를 확인하세요.';

  @override
  String connectionFailedWithReason(String error) {
    return '연결 실패: $error';
  }

  @override
  String get apiKeyLabel => 'API 키';

  @override
  String get apiKeyPlaceholder => 'API 키를 입력하세요';

  @override
  String get customEndpointLabel => '사용자 정의 엔드포인트 (Base URL)';

  @override
  String get customEndpointPlaceholder => 'https://api.example.com/v1';

  @override
  String get modelLabel => '모델 이름';

  @override
  String get modelPlaceholder => '모델 이름을 입력하세요';

  @override
  String get customModelNote => '사용자 정의 엔드포인트 사용 중';

  @override
  String get modelParamsSectionTitle => '세션 모델 매개변수';

  @override
  String get modelParamsSectionSubtitle =>
      '생성 온도, 컨텍스트 예산 및 심층 사고 모드를 정밀 조정합니다';

  @override
  String get systemPromptLabel => '사용자 정의 시스템 프롬프트';

  @override
  String get systemPromptPlaceholder => 'AI 역할과 행동 양식을 안내하는 프롬프트를 입력하세요...';

  @override
  String get authorsNoteLabel => '작가의 메모 (Author\'s Note)';

  @override
  String get authorsNotePlaceholder => '최근 턴에 강력한 컨텍스트 지침을 주입합니다...';

  @override
  String authorsNoteDepthLabel(int depth) {
    return '삽입 깊이: 마지막에서 $depth턴 전';
  }

  @override
  String authorsNoteFrequencyLabel(int freq) {
    return '발동 주기: 매 $freq턴마다';
  }

  @override
  String get dialogueLevelLabel => '문학 스타일 및 깊이';

  @override
  String temperatureLabel(String value) {
    return '샘플링 온도 (창의성): $value';
  }

  @override
  String get enableThinkingLabel => '심층 사고 모드 활성화 (Deep Thinking)';

  @override
  String get enableThinkingSubtitle =>
      '활성화 시 모델이 스토리 본문 생성 전에 접을 수 있는 사고 과정을 출력합니다';

  @override
  String get reasoningEffortLabel => '추론 강도 (Reasoning Effort)';

  @override
  String get quickModeLabel => '고속 모드';

  @override
  String get quickModeSubtitle => '타이핑 스트리밍 애니메이션을 건너뛰고 결과를 빠르게 표시합니다';

  @override
  String get appearanceSectionTitle => '외형 및 비주얼 테마';

  @override
  String get appearanceSectionSubtitle =>
      '인터페이스 색상 테마, 다크 모드 및 읽기 글꼴 크기를 맞춤설정합니다';

  @override
  String get themeModeLabel => '테마 모드';

  @override
  String get themeLight => '라이트';

  @override
  String get themeDark => '다크';

  @override
  String get themeSystem => '시스템 설정 따름';

  @override
  String get themeColorPalette => '테마 색상 팔레트';

  @override
  String get themeColorPaletteHint => '탭하여 즉시 테마 변경';

  @override
  String chatFontSizeLabel(int size) {
    return '스토리 텍스트 글꼴 크기: $size pt';
  }

  @override
  String get chatFontCompact => '작게';

  @override
  String get chatFontStandard => '표준';

  @override
  String get chatFontSpacious => '크게';

  @override
  String get previewTypographyTitle => '읽기 레이아웃 실시간 미리보기';

  @override
  String get previewTypographySample =>
      '「영경 서사」—— 무수히 얽힌 세계선 속에서 당신의 모든 선택은 운명의 파문을 일으킵니다. 태동하는 지하 도시, 하늘에 떠 있는 기계 유적, 모든 전설은 여기서 시작됩니다.';

  @override
  String get readingScrollTitle => '읽기 및 스크롤 제어';

  @override
  String get readingScrollSubtitle => '생성 및 읽기 시 화면 스크롤 동작을 제어합니다';

  @override
  String get autoScrollLabel => '생성 시 자동 스크롤 추적';

  @override
  String get autoScrollSubtitleOn =>
      '활성화: 새로운 내용이 생성될 때 화면이 최신 문장으로 자동 스크롤됩니다.';

  @override
  String get autoScrollSubtitleOff =>
      '권장(읽기 우선): 화면이 고정되어 처음부터 방해 없이 집중하여 읽을 수 있습니다. 스크롤은 수동 제어됩니다.';

  @override
  String get dataManagementTitle => '데이터 관리 및 사용 통계';

  @override
  String get dataManagementSubtitle =>
      'Token 소비량, TTS 음성 낭독 설정 및 저장소를 확인하고 관리합니다';

  @override
  String get tokenUsageTitle => '로컬 Token 소비 추정';

  @override
  String get sessionTokensLabel => '현재 세션 소비량';

  @override
  String get totalTokensLabel => '누적 영구 저장 Token';

  @override
  String get readAloudSectionTitle => '음성 메시지 낭독 (TTS)';

  @override
  String get readAloudSupportedPlatform =>
      '현재 플랫폼은 시스템 음성 낭독을 지원합니다. 대화와 공방에서 사용 가능합니다.';

  @override
  String get readAloudUnsupportedPlatform => '현재 플랫폼은 음성 낭독을 지원하지 않습니다.';

  @override
  String get readAloudEnable => '음성 낭독 활성화';

  @override
  String get readAloudEnableSubtitle => '대화, 창작 스튜디오 및 조립 미리보기에서 본문을 낭독합니다';

  @override
  String get readAloudAutoRead => '완료 시 자동 낭독';

  @override
  String get readAloudAutoReadSubtitle => 'AI가 스토리 생성을 마쳤을 때 자동으로 음성 재생합니다';

  @override
  String get readAloudRate => '낭독 속도';

  @override
  String get readAloudPitch => '음높이';

  @override
  String get readAloudVolume => '음량';

  @override
  String get readAloudLanguage => '낭독 언어';

  @override
  String get readAloudAutoDetect => '자동 감지';

  @override
  String get readAloudAutoDetectHint => '본문 텍스트를 기반으로 최적의 시스템 음성 언어를 자동 선택합니다.';

  @override
  String get readAloudFixedHint => '모든 본문이 선택된 고정 언어로 낭독됩니다.';

  @override
  String get readAloudUnsupportedLanguage => ' (미지원)';

  @override
  String readAloudAvailableLanguagesCount(int count) {
    return '사용 가능한 시스템 음성: $count개';
  }

  @override
  String get readAloudDisabledInSettings => '음성 낭독이 설정에서 비활성화되어 있습니다';

  @override
  String get readAloudStop => '낭독 중지';

  @override
  String get readAloudStart => '낭독';

  @override
  String get diagnosticExportTitle => '진단 데이터 내보내기';

  @override
  String get diagnosticExportSubtitle =>
      '현재 분기의 최근 30턴만 내보냅니다. API 키와 숨김 추론은 파일에 기록되지 않습니다.';

  @override
  String get exportDiagnosticJson => '진단 세션 JSON 내보내기';

  @override
  String get cacheStorageTitle => '캐시 및 저장소 관리';

  @override
  String get clearCache => '임시 캐시 지우기';

  @override
  String get clearCacheSuccess => '임시 캐시가 지워지고 카운터가 초기화되었습니다';

  @override
  String get clearAllData => '모든 로컬 데이터 삭제';

  @override
  String get clearDataDialogTitle => '모든 로컬 데이터 초기화';

  @override
  String get clearDataDialogMessage =>
      '로컬의 모든 모험, 카드 및 캐시 데이터를 삭제하시겠습니까?\n이 작업은 취소할 수 없습니다.';

  @override
  String get exportChatTitle => '대화 내보내기';

  @override
  String get importChatTitle => '대화 가져오기';

  @override
  String get dashboardHeroTitle => '영경 · 탐색 및 서사 공방';

  @override
  String get dashboardHeroSubtitle => '인터랙티브 소설과 몰입형 RPG 스토리텔링 공간';

  @override
  String get dashboardWizardCardTitle => '4단계 마법사 맞춤설정';

  @override
  String get dashboardWizardCardDesc =>
      '백지 상태에서 세계관, 캐릭터, 프롤로그 및 초기 행동을 자유롭게 설정합니다.';

  @override
  String get dashboardWizardCardAction => '마법사 시작';

  @override
  String get dashboardPresetCardTitle => '프리셋 시나리오 공방';

  @override
  String get dashboardPresetCardDesc => '사전 구축된 모험 대본을 살펴보고 원클릭으로 모험을 시작하세요.';

  @override
  String get dashboardPresetCardAction => '프리셋 보기';

  @override
  String get dashboardLibraryCardTitle => '자료실';

  @override
  String get dashboardLibraryCardDesc =>
      '구상한 세계관, 캐릭터 카드 및 NPC 기록을 검토하고 관리합니다.';

  @override
  String get dashboardLibraryCardAction => '자료실 관리';

  @override
  String get dashboardSettingsCardTitle => '시스템 설정 센터';

  @override
  String get dashboardSettingsCardDesc => '모델 연결 매개변수, 비주얼 테마 및 기록 데이터를 관리합니다.';

  @override
  String get dashboardSettingsCardAction => '설정 열기';

  @override
  String get recentAdventuresTitle => '최근 모험';

  @override
  String get noRecentAdventures => '아직 모험 기록이 없습니다. 마법사를 실행하여 새로운 여정을 시작하세요.';

  @override
  String get continueAdventure => '모험 계속하기';

  @override
  String get featuredWorldviews => '추천 세계관';

  @override
  String get featuredCharacters => '추천 캐릭터';

  @override
  String get resourceLibraryTitle => '자료실';

  @override
  String get resourceLibrarySubtitle => '세계관, 캐릭터 카드 및 시나리오 템플릿 탐색 및 관리';

  @override
  String get createResourceAction => '새 리소스';

  @override
  String get searchResources => '리소스 검색...';

  @override
  String get allResources => '전체';

  @override
  String get worldviewsTab => '세계관';

  @override
  String get charactersTab => '캐릭터';

  @override
  String get templatesTab => '템플릿';

  @override
  String get recycleBinTitle => '휴지통';

  @override
  String get emptyRecycleBin => '휴지통이 비어 있습니다';

  @override
  String get restoreAction => '복원';

  @override
  String get permanentlyDelete => '영구 삭제';

  @override
  String get resourceStudioTitle => '리소스 스튜디오';

  @override
  String get resourceStudioSubtitle => '다중 소절 점진적 창작 및 용량 관리';

  @override
  String get outlineTab => '개요';

  @override
  String get capacityTab => '용량';

  @override
  String get historyTab => '버전';

  @override
  String get generatePart => '내용 생성';

  @override
  String get regeneratePart => '재생성';

  @override
  String get partSaved => '변경사항 저장됨';

  @override
  String get partSaving => '저장 중...';

  @override
  String get assemblyWizardTitle => '시나리오 조립 및 준비 점검';

  @override
  String get assemblyStepWorld => '1. 세계관';

  @override
  String get assemblyStepCharacters => '2. 캐릭터 설정';

  @override
  String get assemblyStepNpcs => '3. NPC 진영';

  @override
  String get assemblyStepConfig => '4. 규칙 및 프롤로그';

  @override
  String get assemblyPreviewTitle => '조립 미리보기';

  @override
  String get startAdventureAction => '모험 시작';

  @override
  String get readinessChecking => '리소스 준비 상태 확인 중...';

  @override
  String get readinessPassed => '모든 리소스 준비 완료';

  @override
  String get readinessFailed => '리소스의 조립 준비 또는 압축 처리가 필요합니다';

  @override
  String get adventureSessionTitle => '모험 진행 중';

  @override
  String get inputActionHint => '다음 행동은 무엇인가요? 행동이나 대사를 입력하세요...';

  @override
  String get sendAction => '전송';

  @override
  String get aiThinking => 'AI가 생각 중...';

  @override
  String get aiWriting => 'AI가 작성 중...';

  @override
  String get diceCheckTitle => '주사위 판정';

  @override
  String get turnSettling => '현재 턴 옵션 정산 중...';

  @override
  String get bookmarkAdded => '북마크 추가됨';

  @override
  String get bookmarkRemoved => '북마크 제거됨';

  @override
  String get messageCopied => '메시지가 클립보드에 복사되었습니다';

  @override
  String get messageEdited => '메시지 수정됨';

  @override
  String get chatEditMessage => '메시지 편집';

  @override
  String get chatReadAloudUnsupported => '이 플랫폼에서는 소리 내어 읽기를 지원하지 않습니다';

  @override
  String get chatCopyReasoning => '추론(사고 과정) 복사';

  @override
  String get chatReasoningCopied => '추론을 클립보드에 복사했습니다';

  @override
  String get chatRetryWithModel => '다른 모델로 재시도';

  @override
  String get chatFork => '여기서 분기';

  @override
  String chatBranchCreated(Object branch) {
    return '브랜치 $branch를 만들었습니다';
  }

  @override
  String get chatDeleteMessage => '삭제';

  @override
  String get chatSearchHint => '대화 검색…';

  @override
  String get chatBookmarksOnly => '북마크만';

  @override
  String get chatMoreActions => '추가 작업';

  @override
  String get chatEditStatus => '상태 편집';

  @override
  String get chatDeleteStatus => '상태 삭제';

  @override
  String get readAloudPause => '일시정지';

  @override
  String get readAloudPauseRestart => '일시정지(이 구간의 처음부터 재개)';

  @override
  String get readAloudResume => '읽기 재개';

  @override
  String get readAloudPreparing => '읽기 준비 중';

  @override
  String get readAloudPrevious => '이전 구간';

  @override
  String get readAloudNext => '다음 구간';

  @override
  String get tokenCurrentScene => '현재 장면 토큰';

  @override
  String get tokenHistoryTotal => '누적 토큰';

  @override
  String get tokenCurrentSceneDescription => '현재 장면에서 사용한 토큰';

  @override
  String get tokenHistoryDescription => '로컬에 기록된 누적 합계';

  @override
  String get readAloudPlatformSupportedMessage =>
      '이 플랫폼은 시스템 음성 합성을 지원하며 대화와 스튜디오에서 사용할 수 있습니다.';

  @override
  String get diagnosticExportFailed => '진단 내보내기에 실패했습니다. 나중에 다시 시도하세요.';

  @override
  String diagnosticExported(Object path) {
    return '진단 세션을 내보냈습니다: $path';
  }

  @override
  String get clearHistoryTitle => '대화 기록 삭제';

  @override
  String get clearHistoryMessage =>
      '저장된 대화를 모두 삭제할까요?\n세계관과 캐릭터 카드는 유지되지만 장면 대화 기록은 복구할 수 없습니다.';

  @override
  String get clearHistoryConfirm => '기록 삭제';

  @override
  String get clearHistorySuccess => '모든 대화 기록을 삭제했습니다';

  @override
  String get readAloudRateLabel => '말하기 속도';

  @override
  String get readAloudPitchLabel => '음높이';

  @override
  String get readAloudLanguageHintAuto =>
      '각 문단에 사용할 수 있는 시스템 음성 언어를 자동으로 선택합니다.';

  @override
  String get readAloudLanguageHintFixed => '모든 문단을 선택한 언어로 읽습니다.';

  @override
  String readAloudSupportedCount(Object count) {
    return '시스템에서 사용 가능한 음성: $count';
  }

  @override
  String get generationWaiting => '콘텐츠 생성을 기다리는 중…';

  @override
  String get errorTimeoutTitle => '요청 시간이 초과되었습니다';

  @override
  String get errorTimeoutSuggestion => '네트워크 연결을 확인하고 다시 시도하세요';

  @override
  String get errorAuthTitle => '인증에 실패했습니다';

  @override
  String get errorAuthSuggestion => 'API 키가 유효한지 확인하세요';

  @override
  String get errorRateTitle => '요청이 너무 많습니다';

  @override
  String get errorRateSuggestion => '잠시 후 다시 시도하세요';

  @override
  String get errorApiTitle => 'API 오류';

  @override
  String get errorApiSuggestion => 'API 설정을 확인하거나 나중에 다시 시도하세요';

  @override
  String get errorNetworkTitle => '네트워크 오류';

  @override
  String get errorNetworkSuggestion => '네트워크 연결과 API 설정을 확인한 후 다시 시도하세요';

  @override
  String get switchModelRetry => '다른 모델로 재시도';

  @override
  String get resourceTrashTooltip => '휴지통';

  @override
  String get resourceCreateShort => '새로 만들기';

  @override
  String get resourceNpcTab => 'NPC';

  @override
  String get resourceRetryLoad => '다시 시도';

  @override
  String get resourceEmptyTitle => '아직 리소스가 없습니다';

  @override
  String get resourceNoMatches => '일치하는 리소스가 없습니다';

  @override
  String get resourceNoSummary => '요약 없음';

  @override
  String get resourceMovedToTrash => '휴지통으로 이동했습니다';

  @override
  String get refreshRecycleBin => '휴지통 새로 고침';

  @override
  String permanentDeleteMessage(Object title) {
    return '{title} 및 내용이 영구적으로 삭제되어 복구할 수 없습니다.\n계속할까요?';
  }

  @override
  String get readinessBlockedTitle => '아직 모험을 시작할 수 없습니다';

  @override
  String get acknowledgeAction => '알겠습니다';

  @override
  String get staleResourceTitle => '리소스가 변경되었습니다';

  @override
  String get staleResourceMessage => '마지막 준비 완료 후 변경된 리소스:';

  @override
  String get usePreviousReady => '이전 준비 완료 버전으로 시작할까요?';

  @override
  String get chatImportFormat => '형식';

  @override
  String get chatImportLabel => '대화 내용';

  @override
  String get chatImportHint => '여기에 대화 내용을 붙여넣으세요...';

  @override
  String get chatImportSuccess => '가져오기가 완료되었습니다';

  @override
  String get chatImportParsing => '분석 중...';

  @override
  String get chatImportAction => '가져오기';

  @override
  String get chatImportEmpty => '먼저 대화 내용을 붙여넣으세요';

  @override
  String chatImportFailed(Object error) {
    return '가져오기 실패: $error';
  }

  @override
  String get chatExportWarning =>
      '내보낸 파일에는 대화와 사용자 입력이 포함될 수 있습니다. 안전하게 보관하세요.';

  @override
  String get chatSaveFailed => '저장 실패';

  @override
  String chatSavedPath(Object path) {
    return '저장됨: $path';
  }

  @override
  String get chatSaving => '저장 중...';

  @override
  String get chatLoadFailedRetry => '로드 실패, 다시 시도';

  @override
  String chatCharacterCount(Object count) {
    return '$count자';
  }

  @override
  String get resourceDetailTitle => '리소스 상세';

  @override
  String get resourceEnterStudio => '리소스 스튜디오 열기';

  @override
  String get resourceLegacyNoStudio => '레거시 리소스에서는 고급 편집을 사용할 수 없습니다';

  @override
  String get resourceActions => '리소스 작업';

  @override
  String get moveToTrashAction => '휴지통으로 이동';

  @override
  String moveToTrashMessage(Object name) {
    return '{name}을(를) 휴지통으로 이동할까요? 나중에 복원할 수 있습니다.';
  }

  @override
  String get moveToTrashFailed => '휴지통으로 이동하지 못했습니다. 다시 시도하세요.';

  @override
  String get thinkingEngineTitle => '심층 사고 엔진';

  @override
  String get thinkingEngineBadge => 'V4.1 네이티브 추론';

  @override
  String get thinkingEngineDescription =>
      '복잡한 분기 모험과 세계관 논리를 위해 DeepSeek V4.1 추론으로 이야기 전 계획을 활성화합니다.';

  @override
  String get worldviewDeepThinkingLabel => '세계관 심층 추론 생성';

  @override
  String get worldviewDeepThinkingSubtitle =>
      'AI 세계관 가져오기에 V4.1 추론을 사용합니다. 첫 토큰 지연을 줄이기 위해 기본값은 꺼져 있습니다';

  @override
  String get characterDeepThinkingLabel => '캐릭터 카드 심층 추론 생성';

  @override
  String get characterDeepThinkingSubtitle =>
      'AI 캐릭터 가져오기에 V4.1 추론을 사용합니다. 빠른 생성을 위해 기본값은 꺼져 있습니다';

  @override
  String get reasoningEffortLow => '낮음 · 빠른 응답';

  @override
  String get reasoningEffortMedium => '균형 · 일상 권장';

  @override
  String get reasoningEffortHigh => '깊은 사고 · 풍부한 세부사항';

  @override
  String get reasoningEffortMax => '최대 · 엄격한 논리';

  @override
  String get restoreRecommended => '권장 기본값 복원';

  @override
  String get recommendedDefaultsRestored => '공식 권장 기본값을 복원했습니다';

  @override
  String get revisionHistoryTitle => '변경 기록';

  @override
  String revisionCount(Object count) {
    return '변경 기록 $count개';
  }

  @override
  String get refreshRevisionHistory => '변경 기록 새로 고침';

  @override
  String get noRestorableRevisions => '복원할 수 있는 기록이 아직 없습니다';

  @override
  String get currentRevision => '현재';

  @override
  String get restoreRevision => '이 기록 복원';

  @override
  String get presetParseError => '장면 데이터를 해석할 수 없거나 형식이 올바르지 않습니다';

  @override
  String get presetWorldviewTitle => '세계관 설정';

  @override
  String get presetCharacterTitle => '주인공 프로필';

  @override
  String get presetOpeningTitle => '오프닝 프롤로그';

  @override
  String get presetOptionsTitle => '초기 행동 분기';

  @override
  String get presetNpcTitle => '등장인물(NPC)';

  @override
  String get presetCustomizeAction => '불러와 조정';

  @override
  String get presetDetailsAction => '세부 정보';

  @override
  String get sidebarEmptyConversationsSubtitle => '위 버튼을 클릭하여 새 모험을 시작하세요';

  @override
  String get sidebarDeleteTooltip => '대화 삭제';

  @override
  String get sidebarSettingsNotConfigured => '설정 (키 미구성)';

  @override
  String get characterFallbackName => '캐릭터 A';

  @override
  String get monitoredStatus => '모니터링 상태';

  @override
  String get expandAction => '펼치기 ▼';

  @override
  String get collapseAction => '접기 ▲';

  @override
  String statusItemsCount(int count) {
    return '$count개 항목';
  }

  @override
  String optionsSectionTitle(int count) {
    return '선택지 ($count개 선택지)';
  }

  @override
  String get selectPrompt => '선택해 주세요';

  @override
  String get noOptionsAvailable => '선택할 수 있는 옵션이 없습니다';

  @override
  String get notSpecified => '지정 안 됨';

  @override
  String itemsSelectedCount(int count) {
    return '$count개 선택됨';
  }

  @override
  String get backAction => '뒤로';

  @override
  String get showPassword => '비밀번호 표시';

  @override
  String get hidePassword => '비밀번호 숨기기';

  @override
  String get actionMenuTitle => '동작';

  @override
  String get actionMenuSemanticLabel => '동작 메뉴';

  @override
  String get menuTooltip => '메뉴';

  @override
  String get switchLibrary => '라이브러리 전환';

  @override
  String get customAttributesTitle => '사용자 추가 속성';

  @override
  String get customAttributesSubtitle =>
      '캐릭터/NPC에 고유 설정을 추가하고 추론 시 중요도를 개별 설정할 수 있습니다';

  @override
  String get addCustomAttributeAction => '항목 추가';

  @override
  String get noCustomAttributes => '사용자 추가 항목이 없습니다';

  @override
  String get customAttributesEmptyHint =>
      '우측 상단의 「항목 추가」를 눌러 전용 무기, 금기, 약점 또는 특성을 정의하세요';

  @override
  String get customAttributeNameLabel => '항목 이름 *';

  @override
  String get customAttributeNameHint => '예: 소지한 검, 치명적인 약점, 시전 습관';

  @override
  String get deleteAttributeTooltip => '이 항목 삭제';

  @override
  String get customAttributeContentLabel => '항목 내용 / 설정 설명';

  @override
  String get customAttributeContentHint =>
      '구체적인 효과, 기원 또는 제한을 설명합니다 (LLM 추론 시 중요도를 따릅니다)';

  @override
  String get customAttributeImportanceReference => '참고';

  @override
  String get customAttributeImportanceImportant => '주요 참고';

  @override
  String get customAttributeImportanceVeryImportant => '매우 중요';

  @override
  String get customAttributeImportanceCritical => '필수 항목';

  @override
  String get feedbackSuccess => '성공';

  @override
  String get feedbackError => '오류';

  @override
  String get feedbackWarning => '경고';

  @override
  String get feedbackInfo => '알림';

  @override
  String get refreshFailed => '새로고침 실패, 잠시 후 다시 시도하세요';

  @override
  String get noRefreshNeeded => '현재 페이지는 새로고침이 필요하지 않습니다';

  @override
  String get fontSizeDialogTitle => '글자 크기 조절';

  @override
  String get fontSizeSmall => 'A작게';

  @override
  String get fontSizeLarge => 'A크게';

  @override
  String get fontSizePreview => '미리보기: 한국어 123\n글자 크기 예시';

  @override
  String get applyAction => '적용';

  @override
  String appliedPresetNotice(String preset) {
    return '적용됨: $preset';
  }

  @override
  String get dialogueParamsTitle => '대화 매개변수';

  @override
  String get paramsPresetLabel => '매개변수 프리셋';

  @override
  String get customPreset => '사용자 정의';

  @override
  String get frequencyPenalty => '빈도 페널티';

  @override
  String get presencePenalty => '존재 페널티';

  @override
  String get saveWorldviewTitle => '세계관 저장';

  @override
  String get worldviewInfoSection => '세계관 정보';

  @override
  String worldviewSavedSuccess(String name) {
    return '세계관 「$name」을(를) 저장했습니다';
  }

  @override
  String saveFailedPrefix(String error) {
    return '저장 실패: $error';
  }

  @override
  String get importCardDialogTitle => '캐릭터 카드 가져오기';

  @override
  String get pasteCardJsonHeader => 'SillyTavern / Chub 캐릭터 카드 JSON 붙여넣기';

  @override
  String get pasteCardJsonHint => '여기에 캐릭터 카드 JSON 내용을 붙여넣으세요...';

  @override
  String get newDialoguePersonaTitle => '새 대화 페르소나';

  @override
  String get editDialoguePersonaTitle => '대화 페르소나 편집';

  @override
  String get dialoguePersonaSettingHeader => '대화 페르소나 설정';

  @override
  String get dialoguePersonaScopeNotice =>
      '여기 페르소나는 대화 모드 전용이며 나이라와 완전히 독립적으로 설정할 수 있습니다.';

  @override
  String get personaNameLabel => '페르소나 이름 *';

  @override
  String get personaNameHint => '예: 나이라, 조언자, 글쓰기 파트너';

  @override
  String get personaRoleLabel => '역할 / 정체성';

  @override
  String get personaRoleHint => '예: 범용 AI 어시스턴트, 어학 코치, 세계관 조언자';

  @override
  String get personaUserAddressLabel => '사용자 호칭';

  @override
  String get personaUserAddressHint => '예: 사용자, 창작자, 사령관, 선생님';

  @override
  String get personaPersonalityLabel => '성격 및 행동 특성';

  @override
  String get personaPersonalityHint => '성격, 가치관, 문제 해결 방식을 설명합니다';

  @override
  String get personaSpeakingStyleLabel => '말투';

  @override
  String get personaSpeakingStyleHint => '예: 간결하고 온화함, 필요시 단계와 예시로 설명';

  @override
  String get personaBackgroundLabel => '배경 설정';

  @override
  String get personaBackgroundHint => '페르소나의 출신과 알고 있는 내용';

  @override
  String get personaContextLabel => '대화 상황';

  @override
  String get personaContextHint => '페르소나와 사용자가 주로 어떤 맥락에서 대화하는지 설명합니다';

  @override
  String get personaDirectivesLabel => '추가 행동 지침';

  @override
  String get personaDirectivesHint => '선택: 페르소나가 반드시 준수해야 할 추가 규칙';

  @override
  String get deleteDialoguePersonaTitle => '대화 페르소나를 삭제하시겠습니까?';

  @override
  String deleteDialoguePersonaMessage(String name) {
    return '「$name」을(를) 삭제하시겠습니까?';
  }

  @override
  String deleteCharacterCardFailed(String error) {
    return '캐릭터 카드 삭제 실패: $error';
  }

  @override
  String get nameRequired => '이름을 입력해 주세요';

  @override
  String get manualCreatedSource => '수동 생성';

  @override
  String get createAction => '생성';

  @override
  String get nameLabel => '이름';

  @override
  String get descriptionOptionalLabel => '설명 (선택 사항)';

  @override
  String get fontSizeAdjustment => '글꼴 크기 조절';

  @override
  String get fontSizeSmallA => 'A작게';

  @override
  String get fontSizeLargeA => 'A크게';

  @override
  String get dialogueParams => '대화 매개변수';

  @override
  String get parameterPresets => '매개변수 프리셋';

  @override
  String get presetDeepThinking => '심층 생각 (V4.1 복합 추론)';

  @override
  String get presetFastNarrative => '초고속 서사 (기본 체험)';

  @override
  String get presetDeepReasoning => '극한 추론 (장고 퍼즐 해결)';

  @override
  String get presetLightweightDaily => '가벼운 일상 (초저지연)';

  @override
  String appliedPreset(String preset) {
    return '적용됨: $preset';
  }

  @override
  String get saveWorldview => '세계관 저장';

  @override
  String get worldviewInfo => '세계관 정보';

  @override
  String get name => '이름';

  @override
  String get descriptionOptional => '설명(선택)';

  @override
  String worldviewSaved(String name) {
    return '세계관 {name}이(가) 저장되었습니다';
  }

  @override
  String saveFailed(String error) {
    return '저장 실패: $error';
  }

  @override
  String get unknownError => '알 수 없는 오류';

  @override
  String get importCharacterCard => '캐릭터 카드 가져오기';

  @override
  String get pasteCharacterCardJson => 'SillyTavern / Chub 캐릭터 카드 JSON 붙여넣기';

  @override
  String get pasteCharacterCardJsonHint => '여기에 캐릭터 카드 JSON 내용을 붙여넣으세요...';

  @override
  String get importAction => '가져오기';

  @override
  String get editDialoguePersonaCard => '대화 캐릭터 카드 편집';

  @override
  String get newDialoguePersonaCard => '새 대화 캐릭터 카드';

  @override
  String get dialoguePersonaSettings => '대화 캐릭터 설정';

  @override
  String get dialoguePersonaSettingsDesc =>
      '여기의 캐릭터는 대화 모드 전용이며 Naela를 전혀 사용하지 않을 수도 있습니다.';

  @override
  String get personaNameRequired => '캐릭터 이름 *';

  @override
  String get personaRole => '신분 정체성';

  @override
  String get personaUserCallName => '사용자 호칭 방식';

  @override
  String get personaUserCallNameHint => '예: 사용자, 창작자, 지휘관, 선생님';

  @override
  String get personaPersonality => '성격 및 행동 특성';

  @override
  String get personaSpeakingStyle => '말투';

  @override
  String get personaBackground => '배경 설정';

  @override
  String get personaScenario => '대화 상황';

  @override
  String get personaScenarioHint => '캐릭터와 사용자가 일반적으로 어떤 상황에서 대화하는지 서술';

  @override
  String get personaSystemPrompt => '추가 시스템 지시';

  @override
  String get personaSystemPromptHint => '선택: 캐릭터가 준수해야 할 추가 행동 규칙';

  @override
  String deleteDialoguePersonaPrompt(String name) {
    return '정말 {name}을(를) 삭제하시겠습니까?';
  }

  @override
  String get pleaseEnterPersonaName => '캐릭터 이름을 입력하세요';

  @override
  String get manuallyCreated => '수동 생성';

  @override
  String get sidebarSystemSettings => '시스템 설정';

  @override
  String get settingsTabModelAndApi => '모델 및 API';

  @override
  String get settingsTabModelAndApiSubtitle => '제공자 및 키 구성';

  @override
  String get settingsTabSessionParams => '세션 매개변수';

  @override
  String get settingsTabSessionParamsSubtitle => '샘플링 속도 및 심층 사고';

  @override
  String get settingsTabAppearance => '테마 색상';

  @override
  String get settingsTabAppearanceSubtitle => '라이트/다크 및 테마 색상';

  @override
  String get settingsTabStorage => '데이터 관리';

  @override
  String get settingsTabStorageSubtitle => '토큰 통계 및 저장소';

  @override
  String get settingsCustomProvider => '사용자 지정';

  @override
  String get settingsReturnToLobby => '로비로 돌아가기';

  @override
  String get settingsReturnToSettingsList => '설정 목록으로 돌아가기';

  @override
  String get settingsConfigsCategory => '구성 카테고리';

  @override
  String settingsOfficialInService(String provider) {
    return '$provider 공식 서비스 중';
  }

  @override
  String get settingsKeyNotConfigured => 'API 키 미설정';

  @override
  String get settingsLlmConnected => 'LLM 서비스 연결됨';

  @override
  String get settingsLlmDisconnected => 'API 키 미구성';

  @override
  String get settingsLlmConnectedSubtitle => '클릭하여 제공자, 모델 및 엔드포인트 관리';

  @override
  String get settingsLlmDisconnectedSubtitle => '클릭하여 API 키를 구성하고 추론 시작';

  @override
  String get settingsEngineTitle => '영경 코어 엔진';

  @override
  String get settingsEngineSubtitle => 'SQLite · 로컬 암호화 우선';

  @override
  String get settingsSystemConfigBadge => '시스템 구성';

  @override
  String get inferenceParamsTitle => '추론 파라미터 및 샘플링 조정';

  @override
  String get inferenceParamsSubtitle =>
      '온도, 샘플링 임계값 및 심층 사고 강도를 조정하여 문체와 논리적 일관성의 균형 유지';

  @override
  String get deepseekThinkingHint =>
      '💡 팁: DeepSeek V4.1 사고 모드에서는 샘플링 파라미터가 모델에 의해 자율 관리됩니다. 비사고 모드에서는 top_p가 1.0으로 고정되며 온도만 조정 가능합니다.';

  @override
  String get temperatureTitle => '생성 온도 (Temperature)';

  @override
  String get temperatureDescription => '0.0 절대적 정밀함 ↔ 2.0 다채로운 상상력';

  @override
  String get topPTitle => '핵심 샘플링 확률 (Top-P)';

  @override
  String get topPDescription => '누적 확률 차단 임계값, 권장 0.90 ~ 0.95';

  @override
  String get maxTokensTitle => '1회 최대 생성 길이 (Max Tokens)';

  @override
  String get maxTokensDescription => '단일 턴 대화의 최대 토큰 예산 제한';

  @override
  String get paramsRealtimeNotice => '팁: 매개변수 변경사항은 저장 없이 즉시 적용됩니다';

  @override
  String testConnectionSuccess(int elapsed) {
    return '연결 성공! 소요 시간 ${elapsed}ms, 서비스 상태 원활.';
  }

  @override
  String get testConnectionFailure =>
      '연결 실패. API 키가 정확한지 및 네트워크가 원활한지 확인해 주세요.';

  @override
  String testConnectionFailureDetail(String error) {
    return '연결 실패: $error';
  }

  @override
  String get statusReady => '준비 완료';

  @override
  String get statusNotReady => '미준비';

  @override
  String modelEndpointSummary(String model, String endpoint) {
    return '모델: $model · 엔드포인트: $endpoint';
  }

  @override
  String get quickTesting => '검사 중';

  @override
  String get quickTest => '빠른 테스트';

  @override
  String get llmProviderSectionTitle => 'LLM 서비스 제공자';

  @override
  String get llmProviderSectionSubtitle =>
      '시나리오 대화 및 추론에 사용할 핵심 언어 모델 서비스 선택 및 구성';

  @override
  String get modelProviderLabel => '모델 제공자';

  @override
  String get selectInServiceModal => '서비스 모델 선택';

  @override
  String get customModelNameLabel => '사용자 지정 모델 이름';

  @override
  String get customModelNameHint => '예: gpt-4o, llama-3.3-70b, qwen-max';

  @override
  String get apiEndpointLabel => 'API 엔드포인트 (Base URL)';

  @override
  String get apiSecurityNotice =>
      '키는 로컬 SQLite 데이터베이스에 암호화되어 저장되며 중계 서버를 거치지 않습니다';

  @override
  String get promptSettingsTitle => '프롬프트 및 추론 편성';

  @override
  String get importPresets => '프리셋 가져오기';

  @override
  String get exportPresets => '프리셋 내보내기';

  @override
  String get previewPromptAction => '미리보기';

  @override
  String get importPresetTitle => '프롬프트 프리셋 가져오기';

  @override
  String get exportPresetTitle => '프롬프트 프리셋 내보내기';

  @override
  String get presetJsonLabel => '프롬프트 프리셋 JSON';

  @override
  String get presetJsonEmptyError => '프리셋 JSON을 입력해 주세요';

  @override
  String presetImportFailed(String error) {
    return '가져오기 실패: $error';
  }

  @override
  String get presetJsonCopied => '프리셋 JSON이 복사되었습니다';

  @override
  String get copyAllAction => '모두 복사';

  @override
  String get dialogueLevelSectionTitle => '대화 레벨 (Dialogue Level)';

  @override
  String get dialogueLevelSectionSubtitle =>
      '단일 턴 대화에서의 글자 수 출력 예산 및 묘사 밀도를 선택합니다.';

  @override
  String get systemPromptSectionTitle => '전역 시스템 프롬프트 (System Prompt)';

  @override
  String get systemPromptSectionSubtitle => '초기 상태. 비워둘 경우 기본 범용 추론 규격이 적용됩니다.';

  @override
  String get systemPromptHint =>
      '사용자 지정 시스템 설정, 세계 규칙 또는 추론 지침 작성 (비워둘 시 기본값 적용)...';

  @override
  String charCountLabel(int count) {
    return '$count자 작성됨';
  }

  @override
  String get clearAction => '지우기';

  @override
  String get systemPromptSaved => '전역 시스템 프롬프트가 저장되었습니다';

  @override
  String get savePromptAction => '프롬프트 저장';

  @override
  String get authorsNoteSectionTitle => '작가의 메모 (Author\'s Note)';

  @override
  String get authorsNoteSectionSubtitle => '세션 컨텍스트의 지정된 턴 깊이에 고가중치 지시를 주입합니다.';

  @override
  String get authorsNoteHint =>
      '예: 주인공 행동의 세밀한 묘사에 집중하고 신비롭고 서스펜스 있는 분위기 유지...';

  @override
  String get injectionDepth => '주입 깊이';

  @override
  String get depthFollowSystem => '시스템 설정 바로 뒤';

  @override
  String depthBeforeRound(int depth) {
    return '최근 $depth턴 이전';
  }

  @override
  String get injectionFrequency => '주입 빈도';

  @override
  String freqEveryRound(int freq) {
    return '매 $freq턴마다';
  }

  @override
  String get authorsNoteSaved => '작가의 메모 설정이 저장되었습니다';

  @override
  String get saveNoteConfigAction => '메모 구성 저장';

  @override
  String get promptPreviewTitle => '실시간 Prompt 조립 미리보기';

  @override
  String get copyFullPrompt => '전체 Prompt 복사';

  @override
  String get fullPromptCopied => '조립된 전체 Prompt가 클립보드에 복사되었습니다';

  @override
  String promptPreviewStats(int chars, int tokens) {
    return '약 $chars자 · 예상 $tokens 토큰';
  }

  @override
  String get resourceTypeWorldview => '세계관';

  @override
  String get resourceTypeCharacter => '캐릭터';

  @override
  String get resourceTypeNpc => 'NPC';

  @override
  String get resourceStatusGenerating => '생성 중';

  @override
  String get resourceStatusSaved => '저장됨';

  @override
  String get resourceStatusOptimizationSuggested => '최적화 권장';

  @override
  String get resourceStatusOptimizing => '최적화 중';

  @override
  String get resourceStatusReady => '준비 완료';

  @override
  String get resourceStatusOptimizationFailed => '최적화 실패';

  @override
  String get resourceUnknownTime => '알 수 없는 시간';

  @override
  String get resourceCreateTitle => '새 리소스';

  @override
  String get resourceTypeSectionTitle => '리소스 유형';

  @override
  String get resourceTypeSectionDescription => '구축할 콘텐츠 유형을 선택하세요';

  @override
  String get resourcePreselectedType => '선택된 유형';

  @override
  String get resourceCreationMethodSectionTitle => '생성 방식';

  @override
  String get resourceCreationMethodSectionDescription =>
      '창작 필요에 따라 AI 지원 추론 또는 수동 텍스트 작성을 선택하세요';

  @override
  String get resourceAiCreationTitle => 'AI 생성';

  @override
  String get resourceAiCreationDescription =>
      '참고자료, 소설 텍스트 또는 기존 에셋을 바탕으로 AI가 챕터 개요와 본문을 자동 추론합니다.';

  @override
  String get resourceRecommendBadge => '추천';

  @override
  String get resourceManualCreationTitle => '수동 생성';

  @override
  String get resourceManualCreationDescription =>
      '이름과 설명을 사용자 정의하고 빈 리소스를 만든 뒤 챕터와 내용을 자유롭게 구성하세요.';

  @override
  String get resourceManualCreateTitle => '리소스 수동 생성';

  @override
  String get resourceBasicInfoTitle => '기본 정보';

  @override
  String get resourceManualBasicInfoDescription =>
      '리소스의 유형, 이름 및 간단한 소개를 입력하세요. 생성 후 스튜디오에서 자유롭게 본문을 편집할 수 있습니다.';

  @override
  String get resourceNameLabel => '이름';

  @override
  String get resourceManualNameHint => '명확하고 식별하기 쉬운 이름을 입력하세요';

  @override
  String get resourceSummaryOptionalLabel => '소개 (선택 사항)';

  @override
  String get resourceManualSummaryHint => '해당 리소스의 위치와 배경 설정을 간단히 소개하세요';

  @override
  String get resourceCreateAction => '생성';

  @override
  String get resourceInputNameError => '리소스 이름을 입력하세요';

  @override
  String get resourceAiCreateTitle => 'AI 스마트 리소스 생성';

  @override
  String get resourceAiBasicInfoDescription => '생성할 리소스 캐리어 유형과 제목을 정의하세요';

  @override
  String get resourceAiNameHint => '생성할 설정 또는 캐릭터 이름을 입력하세요';

  @override
  String get resourceAssociateWorldviewTitle => '세계관 연결 (선택 사항)';

  @override
  String get resourceAssociateWorldviewDescription =>
      '캐릭터 또는 NPC의 소속 기본 세계관을 지정하여 생성 시 보충 컨텍스트로 활용합니다';

  @override
  String get resourceNoAvailableWorldview => '연결 가능한 세계관이 없습니다';

  @override
  String get resourceNotSpecified => '지정 안 함';

  @override
  String get resourceReferenceSourceTitle => '참고자료 출처';

  @override
  String get resourceReferenceSourceDescription =>
      '세계관 배경, 소설 설정 또는 관련 리소스를 제공하면 AI가 정수를 추출하여 챕터 구조를 추론합니다';

  @override
  String get resourceTabPaste => '붙여넣기';

  @override
  String get resourceTabFile => 'ファイル';

  @override
  String get resourceTabExistingResource => '기존 리소스';

  @override
  String get resourcePasteReferenceLabel => '참고 내용 붙여넣기';

  @override
  String get resourcePasteReferenceHint =>
      '소설 개요, 설정집 초안 또는 배경 설명을 입력하거나 붙여넣으세요...';

  @override
  String get resourceFileNameLabel => '파일 이름';

  @override
  String get resourceFileNameHint => '예: world_notes.md';

  @override
  String get resourceFileContentLabel => '파일 텍스트 내용';

  @override
  String get resourceFileContentHint => '파일 내의 원본 텍스트를 붙여넣거나 입력하세요...';

  @override
  String get resourceNoExistingInLibrary =>
      '라이브러리에 연결 가능한 준비된 리소스가 없습니다. 붙여넣기 또는 파일 입력으로 전환하세요.';

  @override
  String get resourceSelectExistingLabel => '기존 리소스 선택';

  @override
  String get resourceSelectExistingHint => '참고할 기존 리소스를 클릭하여 선택하세요';

  @override
  String get resourceGenerationLengthTitle => '생성 길이';

  @override
  String get resourceGenerationLengthDescription =>
      'AI가 생성할 리소스 본문의 대략적인 목표 글자 수를 조절합니다';

  @override
  String get resourceTargetCharactersLabel => '목표 글자 수';

  @override
  String resourceTargetCharactersValue(Object count) {
    return '$count 자';
  }

  @override
  String get resourceLengthShort => '단편';

  @override
  String get resourceLengthLong => '장편';

  @override
  String get resourceStartCreateAction => '생성 시작';

  @override
  String get resourceInputOrPasteReferenceError => '참고자료 본문을 입력하거나 붙여넣으세요';

  @override
  String get resourceInputFileNameError => '파일 이름을 입력하세요';

  @override
  String get resourceInputFileContentError => '파일 내용을 입력하세요';

  @override
  String get resourceSelectExistingError => '참고할 기존 리소스를 선택하세요';

  @override
  String get resourcePastedContentLabel => '붙여넣은 내용';

  @override
  String get resourceLoadFailedRetry => '리소스 라이브러리를 불러오지 못했습니다. 다시 시도하세요.';

  @override
  String get resourceCreationFailedRetry => '리소스를 생성하지 못했습니다. 다시 시도하세요.';

  @override
  String get resourceUnnamed => '이름 없는 리소스';

  @override
  String get resourceRevisionResourceKind => '리소스';

  @override
  String get resourceRevisionSectionKind => '챕터';

  @override
  String get resourceRevisionPartKind => '단락';

  @override
  String resourceTrashSubtitle(
      Object deletedAt, Object expiresAt, Object kind, Object reason) {
    return '$kind · $reason · 삭제 일시: $deletedAt · 보관 기한: $expiresAt';
  }

  @override
  String resourceTrashRestoreFailed(Object error) {
    return '복원 실패: $error';
  }

  @override
  String get resourceTrashPermanentDeleteSuccess => '영구 삭제되었습니다';

  @override
  String resourceTrashPermanentDeleteFailed(Object error) {
    return '영구 삭제 실패: $error';
  }

  @override
  String get modeTitleConversation => '대화 라이브러리';

  @override
  String get modeTitleAdventure => '시나리오 라이브러리';

  @override
  String get modeTitleCreation => '창작 라이브러리';

  @override
  String get modeEmptyTitleConversation => '대화 캐릭터 카드가 없습니다';

  @override
  String get modeEmptyTitleAdventure => '시나리오 자료가 없습니다';

  @override
  String get modeEmptyTitleCreation => '창작 자료가 없습니다';

  @override
  String get modeEmptySubtitleConversation =>
      '사용자 지정 캐릭터 카드를 만들거나 이전 채팅 기록을 확인하세요.';

  @override
  String get modeEmptySubtitleAdventure =>
      '시나리오 대화에 사용할 캐릭터, 장소, 규칙 또는 스토리 자료를 가져옵니다.';

  @override
  String get modeEmptySubtitleCreation =>
      '창작 모드에 사용할 세계관, 캐릭터 설정, 챕터 참고자료 또는 집필 자료를 가져옵니다.';

  @override
  String get resourceStudioRefreshTooltip => '새로고침';

  @override
  String get resourceStudioTocTitle => '목차';

  @override
  String get resourceStudioNoContent => '현재 리소스에 표시할 콘텐츠가 없습니다.';

  @override
  String get resourceStudioReadAloudAll => '전체 텍스트 연속 낭독';

  @override
  String get resourceStudioEditPart => '본문 편집';

  @override
  String get resourceStudioDeletePart => '문단 삭제';

  @override
  String get resourceStudioPartNotExistCannotEdit =>
      '해당 문단이 더 이상 존재하지 않아 편집할 수 없습니다';

  @override
  String get resourceStudioPublishCompressionTitle => '압축 결과 게시';

  @override
  String get resourceStudioPublishCompressionMessage =>
      '압축된 본문이 현재 내용을 대체합니다. 대체 전 본문은 기록 버전으로 보존되어 언제든지 복원할 수 있습니다.\n게시하시겠습니까?';

  @override
  String get resourceStudioPublishCompressionAction => '게시';

  @override
  String get resourceStudioRestoreRevisionTitle => '이전 버전 복원';

  @override
  String get resourceStudioRestoreRevisionMessage =>
      '현재 내용이 이 버전으로 대체됩니다. 대체 전 내용 역시 버전 기록에 보존됩니다.\n복원하시겠습니까?';

  @override
  String get resourceStudioRestoreRevisionAction => '복원';

  @override
  String get resourceStudioDeletePartTitle => '문단 삭제';

  @override
  String resourceStudioDeletePartMessage(Object title) {
    return '“$title” 항목이 휴지통으로 이동되며 휴지통에서 복원할 수 있습니다.\n삭제하시겠습니까?';
  }

  @override
  String get resourceStudioDeletePartAction => '삭제';

  @override
  String get resourceStudioPartNotExistCannotDelete =>
      '해당 문단이 더 이상 존재하지 않아 삭제할 수 없습니다';

  @override
  String get resourceStudioMovedToTrash => '휴지통으로 이동되었습니다. 휴지통에서 복원할 수 있습니다';

  @override
  String resourceStudioDeletePartFailed(Object error) {
    return '문단 삭제 실패: $error';
  }

  @override
  String get resourceStudioContinueGenerating => '생성 계속';

  @override
  String get resourceStudioPauseGenerating => '일시 중지';

  @override
  String get resourceStudioCancelGenerating => '취소';

  @override
  String get resourceStudioRetryGenerating => '다시 시도';

  @override
  String get resourceStudioCreatingAndStarting => '리소스를 생성하고 생성을 시작하는 중입니다';

  @override
  String resourceStudioTargetCharacters(Object count) {
    return '목표 약 $count자';
  }

  @override
  String get resourceStudioCreationFailed => '리소스 생성 실패';

  @override
  String get resourceStudioPleaseRetryLater => '잠시 후 다시 시도해 주세요';

  @override
  String get resourceStudioRetryCreation => '생성 재시도';

  @override
  String get resourceStudioSelectResourceOrSession => '리소스 또는 생성 세션 선택';

  @override
  String get resourceStudioSelectSession => '생성 세션 선택';

  @override
  String get resourceStudioCreateAndStart => '생성 및 생성 시작';

  @override
  String get resourceStudioPendingAiPlan => '확인 대기 중인 AI 계획';

  @override
  String get resourceStudioConfirmAndStart => '확인을 계속하고 생성을 시작';

  @override
  String resourceStudioUnfinishedTask(Object index) {
    return '미완료 생성 작업 $index';
  }

  @override
  String get resourceStudioGeneratingStatus => '생성 중';

  @override
  String get resourceStudioResourceLabel => '리소스';

  @override
  String get resourceStudioNoResourceOrSession => '리소스 또는 복구 가능한 생성 세션이 없습니다.';

  @override
  String get resourceStudioAddSectionTitle => '챕터 추가';

  @override
  String get resourceStudioSectionTitleField => '챕터 제목';

  @override
  String get sectionControlsTitle => '챕터 제어';

  @override
  String sectionControlsCount(Object count) {
    return '$count개 챕터';
  }

  @override
  String get sectionControlsAdd => '챕터 추가';

  @override
  String get sectionControlsEmpty => '이 리소스에는 아직 챕터가 없습니다.';

  @override
  String sectionControlsLoadMore(Object shown, Object total) {
    return '더 불러오기 ($shown/$total 표시됨)';
  }

  @override
  String get sectionControlsUnnamed => '(이름 없는 챕터)';

  @override
  String sectionControlsOrderIndex(Object index) {
    return '순번 $index';
  }

  @override
  String sectionControlsUpdated(Object time) {
    return '업데이트 $time';
  }

  @override
  String get sectionControlsValidate => '검증';

  @override
  String get sectionControlsMoreActions => '더 많은 작업';

  @override
  String get sectionControlsRename => '이름 바꾸기';

  @override
  String get sectionControlsMoveUp => '위로 이동';

  @override
  String get sectionControlsMoveDown => '아래로 이동';

  @override
  String get sectionControlsDelete => '삭제';

  @override
  String get sectionControlsDeleteTitle => '챕터 삭제';

  @override
  String sectionControlsDeleteMessage(Object title) {
    return '“$title” 및 모든 내용을 삭제하시겠습니까?';
  }

  @override
  String get sectionControlsGenerate => '생성';

  @override
  String get sectionControlsRegenerate => '재생성';

  @override
  String get sectionControlsNoTasksTooltip =>
      '해당 챕터에는 생성 작업이 없어(AI 청사진 미생성) 생성할 수 없습니다';

  @override
  String get sectionControlsRegenerateTooltip =>
      '해당 챕터의 생성 작업을 다시 실행합니다. 현재 내용은 이전 버전으로 기록되어 언제든지 복원할 수 있습니다';

  @override
  String get sectionControlsRerunTooltip => '해당 챕터의 생성 작업을 다시 실행합니다';

  @override
  String get sectionControlsRenameDialogTitle => '챕터 이름 바꾸기';

  @override
  String get partEditorUnsavedDraftFound => '저장되지 않은 임시 저장본 발견';

  @override
  String get partEditorUnsavedDraftDesc =>
      '이전 편집 내용이 본문에 저장되지 않았습니다. 임시 저장본을 불러와 계속 편집하거나 삭제할 수 있습니다.';

  @override
  String get partEditorLoadDraft => '임시 저장본 불러오기';

  @override
  String get partEditorDiscardDraft => '임시 저장본 삭제';

  @override
  String get partEditorConflictDetected => '콘텐츠 충돌 감지됨';

  @override
  String get partEditorConflictDesc =>
      '다른 작업(생성 또는 복원 등)이 이 문단을 수정했습니다. 자동 저장이 일시 중지되었으며 작성한 내용은 임시 저장본에 보존되어 있습니다. 유지할 버전을 선택하세요:';

  @override
  String get partEditorUseMyText => '내 텍스트 사용';

  @override
  String get partEditorDiscardMyText => '내 텍스트 버리기';

  @override
  String get partEditorHint => '여기서 본문을 편집하세요. 입력을 멈추면 자동으로 저장됩니다';

  @override
  String get partEditorSaveNow => '지금 저장';

  @override
  String get partEditorFinishEditing => '편집 완료';

  @override
  String get partEditorDraftLoaded => '임시 저장본을 불러왔습니다. 저장 시 본문에 반영됩니다';

  @override
  String get partEditorDraftDiscarded => '임시 저장본이 삭제되었습니다';

  @override
  String get partEditorEditing => '편집 중…';

  @override
  String get partEditorConflictOtherSaved =>
      '저장 충돌: 다른 작업이 이 문단을 수정했습니다. 유지할 버전을 선택하세요';

  @override
  String get partEditorConflictDraftRetained =>
      '저장 충돌: 최신 버전을 덮어쓰지 않고 내용이 임시 저장본에 보존되었습니다';

  @override
  String partEditorAutoSaved(Object label) {
    return '자동 저장됨 ($label)';
  }

  @override
  String get partEditorTargetPartMissing =>
      '대상 콘텐츠가 더 이상 존재하지 않아 임시 저장본이 삭제되었습니다';

  @override
  String get partEditorKeptMyTextAndSaved => '내 텍스트를 유지하고 저장했습니다';

  @override
  String get partEditorConflictStillUnresolved =>
      '충돌이 아직 해결되지 않음: 문단이 다시 수정되었습니다. 다시 선택하세요';

  @override
  String partEditorResolveConflictFailed(Object error) {
    return '충돌 해결 실패: $error';
  }

  @override
  String partEditorSaving(Object label) {
    return '저장 중 ($label)…';
  }

  @override
  String get capacityPanelTitle => '용량';

  @override
  String capacityLatestFailureReason(Object reason) {
    return '최근 압축 실패 원인: $reason';
  }

  @override
  String get capacityRefresh => '용량 새로고침';

  @override
  String get capacityCompressing => '압축 중';

  @override
  String get capacityGenerateCandidates => '압축 후보 생성';

  @override
  String capacityRetryFailedWithCount(Object count) {
    return '실패한 압축 재시도 ($count)';
  }

  @override
  String get capacityRetryFailed => '실패한 압축 재시도';

  @override
  String capacityPublishWithCount(Object count) {
    return '압축 결과 게시 ($count)';
  }

  @override
  String get capacityPublish => '압축 결과 게시';

  @override
  String get capacityOptimizationTip =>
      '최적화는 먼저 미리보기를 생성하며, 확인 후에만 현재 내용을 대체하고 이전 내용은 언제든 복원할 수 있습니다.';

  @override
  String get capacityPreparingState => '리소스 상태를 준비하는 중입니다.';

  @override
  String capacityTextCharacters(Object count) {
    return '본문 $count자';
  }

  @override
  String capacitySectionsCount(Object count) {
    return '챕터 $count';
  }

  @override
  String capacityPartsCount(Object count) {
    return '콘텐츠 블록 $count';
  }

  @override
  String capacityRevisionsCount(Object count) {
    return '기록 $count';
  }

  @override
  String capacityArchivedSize(Object count) {
    return '보관됨 $count자';
  }

  @override
  String capacityQueuedJobs(Object count) {
    return '최적화 대기 $count';
  }

  @override
  String capacityPotentialSavings(Object count) {
    return '후보를 채택하면 약 $count자를 절약할 수 있습니다.';
  }

  @override
  String get capacityStatusNormal => '정상';

  @override
  String get capacityStatusElastic => '탄력';

  @override
  String get capacityStatusOverflow => '예산 초과';

  @override
  String get outlinePartPending => '생성 대기';

  @override
  String get outlinePartGenerated => '생성됨';

  @override
  String get operationFailedRetry => '작업 실패, 다시 시도해 주세요';

  @override
  String get resourceImportReturnToEdit => '수정으로 돌아가기';

  @override
  String get resourceImportConfirmSave => '저장 확인';

  @override
  String get characterCardEditTitle => '캐릭터 카드 편집';

  @override
  String get characterCardCreateTitle => '새 캐릭터 카드';

  @override
  String get characterCardConfirmDeleteTitle => '삭제 확인';

  @override
  String characterCardConfirmDeleteMessage(Object name) {
    return '캐릭터 카드 “$name”을(를) 삭제하시겠습니까?';
  }

  @override
  String characterCardDeleteFailed(Object error) {
    return '캐릭터 카드 삭제 실패: $error';
  }

  @override
  String get characterCardNameRequired => '이름을 최소한 입력하세요';

  @override
  String characterCardSaveFailed(Object error) {
    return '저장 실패: $error';
  }

  @override
  String get characterCardInfoSection => '캐릭터 카드 정보';

  @override
  String get characterCardWorldviewOptional => '맞는 세계관 (선택 사항)';

  @override
  String get noneOption => '없음';

  @override
  String get characterCardAiAssistedCreation => 'AI 보조 캐릭터 카드 생성';

  @override
  String get detailedMode => '상세 모드';

  @override
  String get conciseMode => '간결 모드';

  @override
  String get simpleMode => '간결 모드';

  @override
  String characterCardTargetValidChars(Object count, Object max) {
    return '목표 유효 글자 수 $count자 (최대 $max자)';
  }

  @override
  String get characterCardSavedInStudioTip =>
      '생성 내용은 스튜디오에 지속적으로 저장되며 복원 및 수정 내역 추적이 가능합니다';

  @override
  String get characterCardRelateCharacterOptional => '기존 캐릭터 연결 (선택 사항)';

  @override
  String get characterCardRelateCharacterHint =>
      '관계를 맺을 기존 캐릭터를 클릭하여 선택하세요 (비워두면 독립 캐릭터)';

  @override
  String get characterCardNoOtherCharacters => '다른 캐릭터 없음';

  @override
  String get characterCardIndependentRole => '연결 안 함 (독립적인 새 캐릭터로 구상)';

  @override
  String characterCardRelatedCount(Object count) {
    return '$count명의 캐릭터와 연결됨';
  }

  @override
  String get characterCardUnnamed => '이름 없는 캐릭터';

  @override
  String get characterCardBondRelation => '유대 관계:';

  @override
  String get relationCompanion => '동료 / 팀원';

  @override
  String get relationChildhoodFriend => '소꿉친구';

  @override
  String get relationLover => '연인 / 운명의 동반자';

  @override
  String get relationMentor => '사제 (스승/제자)';

  @override
  String get relationRival => '숙적 / 경쟁자';

  @override
  String get relationKin => '가족 친척';

  @override
  String get relationBenefactor => '생명의 은인 / 보은';

  @override
  String get relationEmployment => '고용 관계';

  @override
  String get relationCustom => '사용자 지정 관계...';

  @override
  String get relationCustomDescLabel => '사용자 지정 관계 설명';

  @override
  String get relationCustomDescHint => '예: 정혼자, 이세계 영혼 공생자...';

  @override
  String get characterCardCoreKeywordHint =>
      '캐릭터 핵심 키워드 또는 설정 요구사항을 입력하세요 (예: 차가운 은발의 여검사), 비워두면 자유롭게 생성됩니다...';

  @override
  String get opening => '여는 중...';

  @override
  String get aiRegenerate => 'AI 재생성';

  @override
  String get aiFillIn => 'AI 채우기';

  @override
  String get genderLabel => '성별';

  @override
  String get genderMale => '남성';

  @override
  String get genderFemale => '여성';

  @override
  String get genderOther => '기타';

  @override
  String get ageLabel => '나이';

  @override
  String get customGenderLabel => '사용자 지정 성별';

  @override
  String get occupationLabel => '직업 / 신분';

  @override
  String get personalityLabel => '성격';

  @override
  String get backgroundStoryLabel => '배경 이야기';

  @override
  String get appearanceLabel => '외모 묘사';

  @override
  String get physiqueFeaturesLabel => '체형 및 신체적 특징';

  @override
  String get inWorldSettingSection => '세계 내 설정';

  @override
  String get factionLabel => '소속 세력';

  @override
  String get locationLabel => '활동 장소 / 고향';

  @override
  String get publicGoalLabel => '공개 목표';

  @override
  String get hiddenMotiveLabel => '숨겨진 동기 (서사용)';

  @override
  String get abilitySourceLabel => '능력의 원천';

  @override
  String get abilityCostLabel => '능력의 대가 / 한계';

  @override
  String get taboosLabel => '금기사항 (쉼표로 구분)';

  @override
  String get relationsNoteLabel => '관계망 메모';

  @override
  String get characterCardDetailTitle => '캐릭터 카드 상세';

  @override
  String get characterPersonalityTraits => '성격 특성';

  @override
  String get characterDescription => '캐릭터 설명';

  @override
  String get characterCustomFields => '직접 추가한 항목';

  @override
  String get characterAiAssistantCreateTitle => 'AI 어시스턴트로 캐릭터 생성';

  @override
  String get characterCreateAction => '캐릭터 카드 생성';

  @override
  String characterMatchWorldview(Object name) {
    return '적합: $name';
  }

  @override
  String get worldviewCreateTitle => '새 세계관';

  @override
  String get worldviewEditTitle => '세계관 편집';

  @override
  String get worldviewDetailedTitle => '상세한 세계관';

  @override
  String get worldviewConciseTitle => '간결한 세계관';

  @override
  String get worldviewOverviewDetailed => '세계관 개요 (상세 설정 총 글자 수에 포함)';

  @override
  String get worldviewOverviewConcise => '세계관 설명 (200~500자)';

  @override
  String worldviewDetailedLimitTip(Object count) {
    return '상세 설정 (최대 $count자, 확인된 내용은 시나리오 대화에 포함)';
  }

  @override
  String worldviewConfirmDeleteMessage(Object name) {
    return '세계관 “$name”을(를) 삭제하시겠습니까?';
  }

  @override
  String get worldviewDeleteFailed => '세계관 삭제 실패, 다시 시도해 주세요';

  @override
  String get worldviewAiAssistantTitle => 'AI 어시스턴트로 세계관 생성';

  @override
  String get worldviewCreateAction => '세계관 생성';

  @override
  String get originalTextContent => '원문 콘텐츠';

  @override
  String get worldviewAiImportTip =>
      '텍스트(txt / md / HTML / 소설 단편)를 붙여넣으면 AI가 자동으로 추출하여 세계관으로 통합합니다';

  @override
  String get pasteOriginalTextHint => '여기에 원문 내용을 붙여넣으세요...';

  @override
  String get importModeLabel => '가져오기 모드';

  @override
  String get preparingDeduction => '추론 준비 중…';

  @override
  String deductionProgressChars(Object current, Object partial, Object target) {
    return '현재 유효 글자 수 $current / $target\n$partial';
  }

  @override
  String deductionProgressStage(Object current, Object partial, Object total) {
    return '$current/$total 단계 추론 중: $partial';
  }

  @override
  String get autoSaveToLibrary => '라이브러리에 자동 저장';

  @override
  String get expectedTotalCharacters => '예상 총 글자 수';

  @override
  String get adaptiveStageHelperText =>
      '적응형 단계별 고병렬 추론으로 9대 모듈 전체를 몇 배 빠르게 처리하고 자동 저장';

  @override
  String get aiAnalyzeAction => 'AI 분석';

  @override
  String get selectImportModeTitle => '가져오기 모드 선택';

  @override
  String get selectImportModeDesc =>
      '이번 캐릭터 자료의 정리 단위를 선택하세요. 이 선택은 AI에 직접 전달됩니다.';

  @override
  String get conciseModeDesc =>
      '간결 모드: 신분, 성격, 외모, 핵심 경험 및 필수 관계를 보존하고 불필요한 확장을 피합니다.';

  @override
  String get detailedModeDesc =>
      '상세 모드: 원문 사실 범위 내에서 신분, 성격, 외모, 경험, 동기, 정보 및 인물 관계를 완전하게 정리합니다.';

  @override
  String batchImportTitle(Object kind) {
    return '일괄 AI 가져오기 $kind';
  }

  @override
  String get provideCharacterDataTitle => '캐릭터 자료 제공';

  @override
  String get batchAiRecognitionTip =>
      'AI가 먼저 이름을 식별한 뒤, 확인을 거쳐 캐릭터를 하나씩 생성합니다.';

  @override
  String get pleaseSelectWorldviewFirst => '먼저 세계관을 선택하세요';

  @override
  String get selectRelatedCharacters => '연결할 캐릭터 선택';

  @override
  String relatedCharactersCount(Object count) {
    return '$count명의 캐릭터 연결됨';
  }

  @override
  String get minTotalCharactersLabel => '최소 총 글자 수';

  @override
  String get maxTotalCharactersLabel => '최대 총 글자 수';

  @override
  String characterDataLabel(Object label) {
    return '$label 자료';
  }

  @override
  String characterDataHint(Object label) {
    return '여러 $label이(가) 포함된 챕터, 설정 또는 인물 소개를 붙여넣으세요…';
  }

  @override
  String get planningAction => '기획 중…';

  @override
  String get enterAiStudioAction => 'AI 스튜디오 진입';

  @override
  String selectCandidatesToImportTitle(Object count) {
    return '가져올 캐릭터 선택 ($count)';
  }

  @override
  String importSelectedCharactersAction(Object count) {
    return '$count명의 캐릭터 가져오기';
  }

  @override
  String get selectCandidatesMultiTitle => '대상 선택 (다중 선택 가능)';

  @override
  String get candidatesRelationTip =>
      '생성되는 자료는 원문과 기존 캐릭터를 바탕으로 검증 가능한 관계를 구축합니다.';

  @override
  String confirmRelateCharactersAction(Object count) {
    return '$count명의 캐릭터 연결 확인';
  }

  @override
  String get pasteCharacterRawTextHint => '여기에 캐릭터 또는 NPC 원문을 붙여넣으세요…';

  @override
  String get stagedDeepGenerationTip => '단계별 심층 생성으로 목표 완성도까지 자동 완성합니다';

  @override
  String get worldviewModuleRules => '규칙 및 경계';

  @override
  String get worldviewModuleState => '현재 세계 현황';

  @override
  String get worldviewModuleLocations => '장소 및 지리';

  @override
  String get worldviewModuleFactions => '세력 및 조직';

  @override
  String get worldviewModuleCustoms => '풍습 및 생활';

  @override
  String get worldviewModuleTimeline => '역사 및 연표';

  @override
  String get worldviewModuleGlossary => '용어집';

  @override
  String get worldviewModuleConstraints => '창작 제약';

  @override
  String get notSpecifiedOption => '지정 안 함';

  @override
  String get unnamedWorldview => '이름 없는 세계관';

  @override
  String get noExistingCharacterCards => '기존 캐릭터 카드가 없습니다';

  @override
  String selectedCharactersCount(int count) {
    return '$count명 캐릭터 선택됨';
  }

  @override
  String get generatingEllipsis => '생성 중…';

  @override
  String get aiImportCharacterTitle => 'AI 캐릭터 가져오기';

  @override
  String get aiImportNpcTitle => 'AI NPC 가져오기';

  @override
  String get relateExistingCharactersTitle => '기존 캐릭터 연관';

  @override
  String get sceneBatchImportCharacterTitle => '장면 캐릭터 일괄 가져오기';

  @override
  String get sceneBatchImportNpcTitle => '장면 NPC 일괄 가져오기';

  @override
  String get belongingWorldviewOptional => '소속 세계관 (선택)';

  @override
  String get relateCharactersOptional => '연관 캐릭터 (선택)';

  @override
  String get associateWorldviewOptional => '연관 세계관 (선택)';

  @override
  String get resourceStatusCancelled => '취소됨';
}
