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
  String get enableThinkingLabel => '심층 사고 활성화 (Reasoning)';

  @override
  String get enableThinkingSubtitle => '추론 모델이 최종 본문을 출력하기 전에 생각 과정을 전개합니다';

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
}
