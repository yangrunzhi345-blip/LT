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
  String get customEndpointPlaceholder => '사용자 지정 엔드포인트 URL';

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
  String get wizardWorldviewAiSummary =>
      '장르나 핵심 아이디어를 입력하세요. 여기서 세계관 초안을 만들거나 라이브러리에서 상세한 세계 설정을 만들 수 있습니다.';

  @override
  String get adventureWizardTitle => '모험 만들기 마법사';

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

  @override
  String get dashboardWizardBadge => '마법사';

  @override
  String get dashboardPresetBadge => '완전한 스크립트';

  @override
  String get dashboardLibraryBadge => '전체 자산';

  @override
  String get dashboardSettingsBadge => '모델 설정';

  @override
  String get dashboardMyCharacterCards => '내 캐릭터 카드';

  @override
  String get dashboardNoCharacterCardsTitle => '캐릭터 카드가 없습니다';

  @override
  String get dashboardNoCharacterCardsDesc =>
      '아직 생성된 캐릭터가 없습니다. 리소스 라이브러리에서 주인공이나 동료 설정을 만들고 모험에서 선택할 수 있습니다.';

  @override
  String get dashboardGoToCharacterLibrary => '캐릭터 라이브러리로 이동';

  @override
  String get dashboardDefaultProfession => '탐험가';

  @override
  String get dashboardNoBackgroundDesc => '배경 설명이 없습니다';

  @override
  String get dashboardStartWithCharacter => '이 캐릭터로 시작';

  @override
  String get dashboardMyWorldSettings => '내 세계 설정';

  @override
  String get dashboardNoCustomWorldsTitle => '맞춤 세계가 없습니다';

  @override
  String get dashboardNoCustomWorldsDesc =>
      '사전 설정된 세계가 없는 빈 상태입니다. 라이브러리에서 고유한 세계를 구상하거나 마법사를 사용하여 탐험을 시작할 수 있습니다.';

  @override
  String get dashboardGoToLibrary => '라이브러리로 이동';

  @override
  String get dashboardNoWorldDesc => '설정 설명이 없습니다';

  @override
  String get dashboardStartWithWorld => '이 세계로 시작';

  @override
  String get dashboardToggleSidebar => '사이드바 전환';

  @override
  String get dashboardConfigureApiKey => 'API 키 설정';

  @override
  String get dashboardSystemSettings => '시스템 설정';

  @override
  String get dashboardNoAdventuresTitle => '아직 시작된 시나리오 모험이 없습니다';

  @override
  String get dashboardNoAdventuresDesc => '위의 맞춤 마법사를 선택하여 첫 번째 전설을 시작하세요';

  @override
  String get dashboardContinueAdventures => '모험 계속하기';

  @override
  String get dashboardUnnamedAdventure => '이름 없는 모험';

  @override
  String get dashboardDeleteAdventureTooltip => '모험 기록 삭제';

  @override
  String dashboardSavedAt(Object time) {
    return '$time에 저장됨';
  }

  @override
  String get dashboardContinueExploring => '탐험 계속하기';

  @override
  String get dashboardDeleteAdventureTitle => '모험 기록 삭제';

  @override
  String dashboardDeleteAdventureMessage(Object title) {
    return '시나리오 {title} 및 모든 대화 기록을 삭제하시겠습니까? 이 작업은 되돌릴 수 없습니다.';
  }

  @override
  String dashboardAdventureDeleted(Object title) {
    return '시나리오 {title}이(가) 삭제되었습니다';
  }

  @override
  String get characterNameLabel => '이름';

  @override
  String get presetScenesTitle => '프리셋 시나리오 공방';

  @override
  String get presetScenesSubtitle => '즉시 사용 가능한 완전한 모험 시나리오 설정 · 원클릭 시작';

  @override
  String get returnToDashboard => '로비로 돌아가기';

  @override
  String presetScriptCount(int count) {
    return '$count개 시나리오';
  }

  @override
  String get presetWizardNewScene => '마법사로 새 시나리오';

  @override
  String get presetRefreshList => '목록 새로고침';

  @override
  String get presetSearchHint => '시나리오 대본, 세계관 또는 주인공 검색...';

  @override
  String get presetStatusReady => '준비 완료';

  @override
  String get presetStatusDraft => '초안';

  @override
  String get presetDefaultSceneName => '프리셋 시나리오';

  @override
  String get presetNoMatchingScenes => '일치하는 프리셋 시나리오가 없습니다';

  @override
  String get presetNoScenes => '아직 프리셋 시나리오 대본이 없습니다';

  @override
  String get presetNoMatchingScenesHint => '다른 검색어를 시도하거나 필터를 초기화해 보세요';

  @override
  String get presetNoScenesHint =>
      '4단계 마법사를 통해 세계관, 주인공, 프롤로그 및 행동 분기가 포함된 완전한 대본 프리셋을 생성할 수 있습니다';

  @override
  String get presetStartWizardAction => '마법사를 시작하여 새 시나리오 생성';

  @override
  String get presetScriptDetail => '대본 상세';

  @override
  String get presetUnnamedScene => '이름 없는 시나리오';

  @override
  String presetWorldviewLabel(Object name) {
    return '세계관: $name';
  }

  @override
  String get presetPreviewFullSetting => '전체 설정 미리보기';

  @override
  String get presetLoadIntoWizard => '마법사에 로드하여 미세 조정';

  @override
  String get presetDeleteAction => '프리셋 시나리오 삭제';

  @override
  String get presetDeleteTitle => '프리셋 시나리오 삭제';

  @override
  String presetDeleteMessage(Object name) {
    return '프리셋 시나리오 \"$name\"을(를) 삭제하시겠습니까?\n삭제 후에는 이 대본 프리셋을 복구할 수 없습니다.';
  }

  @override
  String presetDeletedSuccess(Object name) {
    return '시나리오 \"$name\"이(가) 삭제되었습니다';
  }

  @override
  String presetDeleteFailed(Object error) {
    return '삭제 실패: $error';
  }

  @override
  String presetLoadFailed(Object error) {
    return '프리셋 시나리오 로드 실패: $error';
  }

  @override
  String get presetStartFailed => '프리셋 시나리오 시작에 실패했습니다. 나중에 다시 시도해 주세요';

  @override
  String presetProtagonistSummary(
      Object name, Object gender, Object profession) {
    return '주인공: $name ($gender · $profession)';
  }

  @override
  String get presetNoPlotSummary => '줄거리 요약이 없습니다';

  @override
  String get presetDataSimplifying => '데이터 구조 간소화 중';

  @override
  String get presetQuickStartAction => '원클릭 시작';

  @override
  String get presetMenuSemantic => '시나리오 작업 메뉴';

  @override
  String get worldSelectionTitle => '세계관 설정 선택';

  @override
  String get worldSelectionSubtitle =>
      '자료실에 구상된 세계 중에서 이번 모험의 세계 법칙과 배경 설정을 선택하세요';

  @override
  String get worldSelectionSearchHint => '세계관 이름, 지리 또는 규칙 검색...';

  @override
  String get worldSelectionNoDesc => '상세한 배경 설명이 없습니다';

  @override
  String get worldSelectionTag => '세계 설정';

  @override
  String get worldSelectionEmptyTitle => '저장된 세계관이 없습니다';

  @override
  String get worldSelectionEmptyDesc =>
      '자료실에서 생성하거나 마법사에서 직접 사용자 정의 세계관을 입력할 수 있습니다';

  @override
  String get characterSelectionTitle => '모험 캐릭터 선택';

  @override
  String get characterSelectionSubtitle => '캐릭터 아카이브에서 주인공과 파티 동료를 선택하세요';

  @override
  String get characterSelectionSearchHint => '캐릭터 이름, 직업, 성격 또는 배경 검색...';

  @override
  String get characterCompatNative => '현재 세계';

  @override
  String get characterCompatUnbound => '미바인딩';

  @override
  String get characterCompatCrossWorld => '다른 세계에서 온';

  @override
  String characterAgeYears(Object age) {
    return '$age세';
  }

  @override
  String characterPersonalityPrefix(Object personality) {
    return '성격: $personality';
  }

  @override
  String get characterSelectionEmptyTitle => '사용 가능한 캐릭터 아카이브가 없습니다';

  @override
  String get characterSelectionEmptyDesc =>
      '자료실에서 새 캐릭터를 생성하거나 마법사에서 AI 자동 생성을 사용할 수 있습니다';

  @override
  String get npcSelectionTitle => '초기 NPC 선택';

  @override
  String get npcSelectionSubtitle =>
      '이번 모험에 등장할 상주 NPC를 선택하세요 (데이터는 모험 스냅샷으로 고정됨)';

  @override
  String get npcSelectionSearchHint => 'NPC 이름, 역할 또는 요약 검색...';

  @override
  String get npcSelectionEmptyTitle => '자료실에 NPC가 없습니다';

  @override
  String get npcSelectionEmptyDesc => '자료실에서 NPC를 추가하거나 이 단계를 건너뛸 수 있습니다';

  @override
  String get unnamedNpc => '이름 없는 NPC';

  @override
  String resourceSelectedCount(int count) {
    return '$count개 항목 선택됨';
  }

  @override
  String get resourceNoneSelected => '선택된 항목 없음';

  @override
  String get resourceOneSelected => '1개 항목 선택됨';

  @override
  String get confirmSelection => '선택 확인';

  @override
  String get finishSelection => '선택 완료';

  @override
  String get loadingResources => '사용 가능한 리소스를 로드하는 중...';

  @override
  String noMatchingResourceForQuery(Object query) {
    return '\"$query\"을(를) 포함하는 리소스를 찾을 수 없습니다';
  }

  @override
  String get clearSearch => '검색 지우기';

  @override
  String get configureApiKeyFirstForAi =>
      'AI 자동 생성 기능을 사용하려면 먼저 API Key를 설정하세요';

  @override
  String get aiGenerationNoValidContent =>
      '생성에 유효한 콘텐츠가 반환되지 않았습니다. 네트워크를 확인하거나 다시 시도하세요';

  @override
  String get aiOpeningGeneratedSuccess =>
      'AI 프롤로그 및 초기 행동 분기가 자동 생성되어 입력되었습니다!';

  @override
  String aiGenerationFailed(Object error) {
    return '생성 실패: $error';
  }

  @override
  String get openingPromptLabel => '프롤로그 요구 사항 / 가이드 프롬프트 (선택)';

  @override
  String get openingPromptHint =>
      '예: 비 내리는 밤 부두의 미스터리한 분위기로 시작하며, 주인공이 먼저 이상함을 감지함...';

  @override
  String get aiGenerateOpeningAndBranches => 'AI로 프롤로그 및 분기 생성';

  @override
  String get aiOpeningGeneratingProgress =>
      'AI가 세계관과 캐릭터 설정을 바탕으로 프롤로그와 행동 분기를 구상 중입니다…';

  @override
  String assemblyWorldviewSubtitle(Object worldview) {
    return '세계: $worldview';
  }

  @override
  String assemblyProtagonistSubtitle(Object name) {
    return '주인공: $name';
  }

  @override
  String get assemblyConfigPageTitle => '프롤로그 줄거리 및 분기 구성';

  @override
  String get saveConfigAndContinue => '설정 저장 후 계속';

  @override
  String get openingFirstSceneTitle => '오프닝 첫 막 줄거리';

  @override
  String get openingFirstSceneDesc =>
      '플레이어가 모험에 진입했을 때의 첫 상황 설명, 조우 또는 오프닝 전환점을 설정합니다.';

  @override
  String get openingFirstSceneHint => '모험을 시작할 때의 순간, 환경 및 예상치 못한 위기를 설명하세요...';

  @override
  String get pleaseEnterOpeningScene => '오프닝 장면 줄거리를 입력하세요';

  @override
  String get initialActionBranchesTitle => '초기 행동 결정 분기 (선택)';

  @override
  String get initialActionBranchesDesc =>
      '플레이어가 시작할 때 선택할 3가지 행동 분기입니다. 비워두면 진입 후 AI가 동적으로 생성합니다.';

  @override
  String get actionBranch1 => '선택 분기 1';

  @override
  String get actionBranch1Hint => '예: 다가오는 그림자에 맞서 검을 뽑는다';

  @override
  String get actionBranch2 => '선택 분기 2';

  @override
  String get actionBranch2Hint => '예: 엄폐물을 찾고 동료에게 엄호를 요청한다';

  @override
  String get actionBranch3 => '선택 분기 3';

  @override
  String get actionBranch3Hint => '예: 주변 환경을 면밀히 관찰하여 탈출로를 찾는다';

  @override
  String get difficultyAndGuidanceTitle => '추론 난이도 및 사용자 정의 지침';

  @override
  String get difficultyAndGuidanceDesc => '게임 진행의 난이도 성향과 사용자 정의 프롬프트를 제어합니다.';

  @override
  String get narrativeDifficulty => '서사 난이도';

  @override
  String get difficultyNormalDesc => '보통 (표준 서사 및 균형 잡힌 도전)';

  @override
  String get difficultyCasualDesc => '캐주얼 (스토리 중심 및 편안한 몰입)';

  @override
  String get difficultyHardDesc => '어려움 (엄격한 규칙 및 하드코어 선택)';

  @override
  String get customGuidancePromptOptional => '사용자 정의 가이드 프롬프트 (선택)';

  @override
  String get customGuidancePromptHint => '예: 미스터리 추리 분위기 강조, 환경 감각 묘사 추가...';

  @override
  String get worldviewBoundRules => '연결된 세계관 규칙 및 지리 법칙';

  @override
  String get defaultContinentRules => '기본 대륙 규칙 사용';

  @override
  String readinessReadError(Object error) {
    return '리소스 준비 상태를 읽을 수 없습니다: $error';
  }

  @override
  String readinessRetryError(Object error) {
    return '리소스 재준비 실패: $error';
  }

  @override
  String startAdventureFailed(Object error) {
    return '모험 시작 실패: $error';
  }

  @override
  String get unnamedHero => '이름 없는 용사';

  @override
  String get adventurerRole => '모험가';

  @override
  String get assemblyPreviewSubtitle =>
      '세계관, 캐릭터 로스터, NPC 및 프롤로그 추론 설정을 종합 점검합니다';

  @override
  String get enterAdventureAction => '모험으로 출발';

  @override
  String get readinessCheckingTitle => '리소스 조합 준비 상태 확인 중';

  @override
  String get readinessUnconfirmedTitle => '리소스 준비 상태를 확인할 수 없습니다';

  @override
  String get readinessReadyTitle => '모험 요소 조합 완료';

  @override
  String get readinessNotReadyTitle => '아직 준비되지 않은 리소스가 있습니다';

  @override
  String get readinessCheckingDesc => '세계관 및 캐릭터의 사용 가능한 버전을 읽는 중입니다.';

  @override
  String get readinessUnconfirmedDesc =>
      '리소스 상태 읽기에 실패했습니다. 안전을 위해 시작 여부를 확인할 수 없습니다.';

  @override
  String get readinessReadyDesc =>
      '아래의 \"모험으로 출발\"을 클릭하여 스냅샷을 고정하고 새로운 여정을 시작하세요.';

  @override
  String get readinessNotReadyDesc =>
      '사용 가능한 리비전이 없으면 모험을 시작할 수 없습니다. 먼저 리소스 준비를 완료하세요.';

  @override
  String get readinessRetrying => '재준비 중…';

  @override
  String get readinessRetry => '다시 준비';

  @override
  String worldviewSettingLabel(Object name) {
    return '세계 설정: $name';
  }

  @override
  String get worldviewSettingTitle => '세계 설정';

  @override
  String get readAloudWorldview => '세계 설정 낭독';

  @override
  String protagonistLeadLabel(Object name, Object className) {
    return '주 조작 주인공: $name ($className)';
  }

  @override
  String get mainProtagonistTitle => '주인공';

  @override
  String personalityFeatureLabel(Object personality) {
    return '성격 특징: $personality';
  }

  @override
  String backgroundStoryPrefix(Object background) {
    return '출신 배경: $background';
  }

  @override
  String accompanyingCharactersCount(int count) {
    return '동행 캐릭터 ($count명):';
  }

  @override
  String characterBondsCount(int count) {
    return '인연 관계 ($count개):';
  }

  @override
  String residentNpcsCount(int count) {
    return '상주 NPC ($count명)';
  }

  @override
  String get openingSceneAndDecisionsTitle => '프롤로그 및 행동 결정';

  @override
  String get openingSceneTitle => '프롤로그 장면';

  @override
  String get readAloudOpeningScene => '프롤로그 장면 낭독';

  @override
  String get aiDynamicOpeningPlaceholder =>
      '(AI가 세계관과 캐릭터 배경을 바탕으로 오프닝 줄거리를 동적으로 구상합니다)';

  @override
  String get initialActionDecisionsTitle => '초기 행동 결정 분기:';

  @override
  String get noMatchingResourceTitle => '일치하는 리소스가 없습니다';

  @override
  String get noMatchingResourceDesc => '다른 검색어를 입력하거나 필터를 지워보세요';

  @override
  String get searchResourceNameOrDesc => '리소스 이름 또는 설명 검색...';

  @override
  String get aiOpeningPanelTitle => 'AI 프롤로그 자동 생성';

  @override
  String get aiOpeningPanelDesc =>
      '프롤로그 요구 사항을 입력하면 AI가 세계관, 주인공 및 동료 캐릭터 카드, 인연 관계, NPC를 결합하여 프롤로그 본문과 초기 행동 분기를 생성합니다. 생성 결과는 수동으로 수정할 수 있습니다.';

  @override
  String get regenerate => '다시 생성';

  @override
  String get assemblyPipelineTitle => '어드벤처 조립 파이프라인';

  @override
  String get assemblyPipelineSubtitle => '단계별 진행 · 페이지 기반 리소스 조립 · 팝업 제약 제로';

  @override
  String get phaseWorldview => '세계관 설정';

  @override
  String get phaseCharacters => '캐릭터 라인업';

  @override
  String get phaseOpening => '프롤로그 분기';

  @override
  String get phasePreview => '조립 개요';

  @override
  String nextPhaseLabel(Object phase) {
    return '다음: $phase';
  }

  @override
  String get previousStepAction => '이전';

  @override
  String get pleaseSetWorldviewName => '세계관 이름을 설정해주세요';

  @override
  String get pleaseAddAtLeastOneCharacter => '최소 한 명의 캐릭터를 추가해주세요';

  @override
  String worldviewSelectedSuccess(Object name) {
    return '세계관 \"$name\" 선택됨';
  }

  @override
  String get rosterUpdatedSuccess => '라인업 캐릭터가 업데이트되었습니다';

  @override
  String npcsSelectedCountSuccess(int count) {
    return '$count명의 NPC가 선택되었습니다';
  }

  @override
  String get openingConfigSavedSuccess => '프롤로그 구성이 저장되었습니다';

  @override
  String characterJoinedPartySuccess(Object name) {
    return '캐릭터 \"$name\"이(가) 파티에 합류했습니다';
  }

  @override
  String get worldviewLibraryLinkTitle => '세계관 라이브러리 연동';

  @override
  String get selectFromLibrary => '라이브러리에서 선택';

  @override
  String boundLibraryWorldviewId(Object id) {
    return '연결된 라이브러리 세계관 ID: $id';
  }

  @override
  String get notBoundPresetHint =>
      '프리셋이 연결되지 않았습니다. 아래에 직접 커스텀 세계관 설정을 입력할 수도 있습니다.';

  @override
  String get worldviewDetailsSectionTitle => '세계관 설정 세부사항';

  @override
  String get worldviewDetailsSectionDesc =>
      '대륙의 법칙, 지리적 배경, 문명 수준 및 세력 구도를 설정합니다.';

  @override
  String get worldNameRequiredLabel => '세계 이름 *';

  @override
  String get worldNameHint => '예: 엘든 대륙, 사이버 네오 2099, 수선 고대 세계...';

  @override
  String get pleaseEnterWorldName => '세계 이름을 입력해주세요';

  @override
  String get lawsAndBackgroundLabel => '법칙 및 배경 설정';

  @override
  String get lawsAndBackgroundHint =>
      '세계의 마법 및 기술 체계, 천체 기후, 진영 세력 구도 등을 설명...';

  @override
  String get charactersAndNpcAssemblyTitle => '캐릭터 및 NPC 조립';

  @override
  String get selectCharactersFromLibrary => '라이브러리에서 캐릭터 선택';

  @override
  String selectNpcCountLabel(int count) {
    return 'NPC 선택 ($count)';
  }

  @override
  String get newCharacterAction => '새 캐릭터';

  @override
  String rosterSectionTitle(int count) {
    return '등장 캐릭터 라인업 ($count)';
  }

  @override
  String get rosterSectionDesc =>
      '반드시 1명을 메인 주인공으로 지정해야 합니다. 다른 캐릭터는 동료, 빌런, 멘토 등의 역할을 부여할 수 있습니다.';

  @override
  String get noCharactersAddedYet => '아직 등장 캐릭터가 추가되지 않았습니다';

  @override
  String get clickAboveToAddCharactersHint =>
      '위의 \"라이브러리에서 캐릭터 선택\" 또는 \"새 캐릭터\"를 클릭하세요';

  @override
  String get setAsMainProtagonist => '메인 주인공으로 설정';

  @override
  String get scriptRoleOrientation => '시나리오 역할 포지션';

  @override
  String get openingAndRulesAdvancedConfigTitle => '프롤로그 및 규칙 고급 설정';

  @override
  String get fullscreenAdvancedConfig => '전체 화면 고급 설정';

  @override
  String get openingSceneContentTitle => '프롤로그 장면 내용';

  @override
  String get openingSceneContentDesc => '모험이 시작될 때의 첫 번째 장면 묘사.';

  @override
  String get openingSceneContentHint => '주인공이 등장하는 순간의 환경과 반전을 설명...';

  @override
  String get openingBranchesDesc => '프롤로그 종료 시 플레이어가 선택할 행동 방향입니다.';

  @override
  String branchNumberLabel(Object number) {
    return '분기 $number';
  }

  @override
  String actionOptionHint(Object number) {
    return '행동 선택지 $number...';
  }

  @override
  String get enterStandaloneFullscreenPreview => '독립 전체 화면 미리보기';

  @override
  String get fullscreenPreviewButton => '전체 화면 미리보기';

  @override
  String get customUnnamedWorld => '커스텀 이름 없는 세계';

  @override
  String get unspecifiedProtagonist => '주인공 미지정';

  @override
  String companionRosterSummary(Object roster) {
    return '동료 라인업: $roster';
  }

  @override
  String selectedInitialNpcCount(int count) {
    return '$count명의 초기 NPC 선택됨';
  }

  @override
  String get firstSceneOpeningPlotTitle => '프롤로그 첫 번째 장면';

  @override
  String get aiDynamicOpeningSummary => '배경을 바탕으로 AI가 자동 전개';

  @override
  String get wizardWorldviewQuickBadge => '빠른 구상 및 라이브러리 작성';

  @override
  String get wizardWorldviewPromptLabel => '세계관 아이디어 / 장르 선호 (선택 사항)';

  @override
  String get wizardWorldviewPromptHint =>
      '예: 스팀펑크 공중 도시, 고대 신의 속삭임, 심해 종말 도시. 비워 두면 AI가 자유롭게 구상합니다…';

  @override
  String get generationModeLabel => '생성 모드';

  @override
  String get clearSettingsAction => '설정 비우기';

  @override
  String get wizardGenerateWorldviewAction => 'AI로 세계관 생성';

  @override
  String get wizardRegenerateWorldviewAction => '세계관 다시 생성';

  @override
  String get wizardWorldviewGeneratingBrief => '세계관 구상 중…';

  @override
  String get wizardWorldviewGeneratingDetailed => '단계별로 세계관 구성 중…';

  @override
  String get saveToLibraryNow => '라이브러리에 저장';

  @override
  String get wizardReusableBadge => '언제든 재사용 가능';

  @override
  String get wizardWorldviewSaveDescription =>
      '이 설정을 세계관 라이브러리에 저장하면 이후 모험에서 재사용하고 확장할 수 있습니다.';

  @override
  String charactersSavedCount(int count) {
    return '캐릭터 설정 $count개를 라이브러리에 저장했습니다';
  }

  @override
  String characterCardSavedSuccess(String name) {
    return '캐릭터 \"$name\"을(를) 라이브러리에 저장했습니다';
  }

  @override
  String get fullscreenSelectionAction => '전체 화면 선택';

  @override
  String wizardCharacterAiSummary(String worldview) {
    return '캐릭터의 성격이나 역할을 입력하세요. AI가 현재 세계관 \"$worldview\"에 맞춰 주인공이나 동료를 만들고 명단에 추가합니다. 라이브러리에서 더 자세하게 작성할 수도 있습니다.';
  }

  @override
  String get wizardCharacterPromptLabel => '캐릭터 아이디어 / 인물상 선호 (선택 사항)';

  @override
  String get wizardCharacterPromptHint =>
      '예: 침착한 퇴마 검객, 쾌활한 백발 치유 마법사, 냉철한 기계 레인저…';

  @override
  String get wizardGenerateMainCharacterAction => 'AI로 주인공 생성';

  @override
  String get wizardAddCharacterToRosterAction => 'AI로 파티원 추가';

  @override
  String get currentWorldviewLabel => '현재 세계';

  @override
  String get removeRosterCharacter => '명단에서 제거';

  @override
  String get clearRelatedCharacters => '연결 지우기';

  @override
  String wizardRelatedCharactersSummary(int count, String names) {
    return '$count명 연결됨: $names';
  }

  @override
  String get wizardRelationAssociationSummary =>
      '새 캐릭터는 선택한 캐릭터와 이야기 속 인연을 맺습니다.';

  @override
  String charactersAddedToRoster(int count) {
    return 'AI로 생성한 캐릭터 $count명을 명단에 추가했습니다';
  }

  @override
  String get roleMaleLead => '남자 주인공';

  @override
  String get roleFemaleLead => '여자 주인공';

  @override
  String get roleMaleOne => '남성 캐릭터 1';

  @override
  String get roleFemaleOne => '여성 캐릭터 1';

  @override
  String get roleMaleTwo => '남성 캐릭터 2';

  @override
  String get roleFemaleTwo => '여성 캐릭터 2';

  @override
  String get roleSupporting => '주요 조연';

  @override
  String get roleVillain => '악역';

  @override
  String get roleMentor => '스승';

  @override
  String get roleFamily => '가족';

  @override
  String get relationFriend => '친구';

  @override
  String get relationEnemy => '적';

  @override
  String get relationStranger => '낯선 사람';

  @override
  String get mainProtagonistDescription => '주인공 (행동과 주요 선택을 담당)';

  @override
  String get protagonistShortTag => '주인공';

  @override
  String get relationshipNetworkDescription =>
      '등장인물 사이의 인연, 소속, 과거 갈등을 설정하세요. AI는 이 관계를 따릅니다.';

  @override
  String relationAssetReference(String suggestion) {
    return '관련 자료: $suggestion (이번 모험에서 변경할 수 있음)';
  }

  @override
  String get relationDetailsHint => '두 사람의 관계 배경이나 인연의 단서를 입력하세요 (선택 사항).';

  @override
  String get relationshipNetworkTitle => '캐릭터 인연 및 관계망';

  @override
  String get adventureReadyToEnterTitle => '세계로 떠날 준비가 되었습니다';

  @override
  String get worldviewSnapshotBoundSummary => '라이브러리 세계관 스냅샷과 규칙을 연결했습니다';

  @override
  String get characterCardSnapshotBoundSummary => '라이브러리 캐릭터 카드에 연결했습니다';

  @override
  String get characterCustomDesignedSummary => '주인공 설정을 직접 구성했습니다';

  @override
  String get unnamedCharacterA => '캐릭터 A';

  @override
  String get unnamedCharacterB => '캐릭터 B';

  @override
  String get savePreviewAction => '미리보기 저장';

  @override
  String get previewTemplateNoStartHint =>
      '복구할 수 있는 미리보기 템플릿으로만 저장하며 모험을 시작하지 않습니다.';

  @override
  String adventurePreviewName(String worldview) {
    return '$worldview · 모험 미리보기';
  }

  @override
  String adventurePreviewSavedMessage(String name) {
    return '미리보기 \"$name\"을(를) 저장했습니다. 프리셋 장면에서 복구할 수 있습니다.';
  }

  @override
  String get adventurePreviewExistsMessage => '같은 내용의 모험 미리보기가 이미 있습니다.';

  @override
  String adventurePreviewSaveFailed(String error) {
    return '미리보기 저장 실패: $error';
  }

  @override
  String get wizardCharacterSaveDescription =>
      '파티 캐릭터 설정을 캐릭터 라이브러리에 저장해 이후 모험에서 다시 사용할 수 있습니다.';

  @override
  String wizardMalformedCharacterCards(int count) {
    return '캐릭터 카드 $count개를 불러오지 못했습니다.';
  }

  @override
  String get conversationDeleteTitle => '장면 대화 삭제';

  @override
  String conversationDeleteConfirm(int count) {
    return '선택한 장면 대화 $count개를 삭제할까요? 기록과 진행된 스토리는 복구할 수 없습니다.';
  }

  @override
  String conversationDeleteInterrupted(String error) {
    return '삭제가 중단되었습니다. 남은 대화를 확인한 뒤 다시 시도하세요: $error';
  }

  @override
  String get conversationManageTitle => '지난 대화 관리';

  @override
  String selectedItemsCount(int count) {
    return '$count개 선택됨';
  }

  @override
  String get deletingAction => '삭제 중…';

  @override
  String get batchDeleteAction => '선택 항목 삭제';

  @override
  String get noManagedConversations => '관리할 장면 대화가 없습니다';

  @override
  String get selectAllAction => '모두 선택';

  @override
  String get sceneConversationLabel => '장면 대화';

  @override
  String get messageEditUserTitle => '메시지 편집';

  @override
  String get messageEditAssistantTitle => 'AI 답변 편집';

  @override
  String get messageEditUserSubtitle => '이 메시지를 수정하면 이후 스토리가 다시 생성됩니다.';

  @override
  String get messageEditAssistantSubtitle =>
      '서술이나 세부 내용을 조정하도록 스토리 텍스트를 편집합니다.';

  @override
  String get messageEditUserWarning =>
      '저장하면 이 메시지 이후의 기록이 삭제되고 새 입력을 바탕으로 다시 생성됩니다.';

  @override
  String get messageBodyLabel => '메시지 내용';

  @override
  String get messageEditDescription => '긴 텍스트, 줄 바꿈 및 서식을 지원합니다.';

  @override
  String get messageContentHint => '메시지 내용을 입력하세요…';

  @override
  String get saveAndRegenerateAction => '저장 후 다시 생성';

  @override
  String get saveChangesAction => '변경 사항 저장';

  @override
  String get messageContentRequired => '메시지 내용을 입력하세요.';

  @override
  String get messageUnchanged => '변경 사항이 없습니다.';

  @override
  String get messageNoLongerCurrent => '현재 대화에 없는 메시지입니다. 돌아가서 새로 고침하세요.';

  @override
  String get messageSavedAndRegenerated => '저장하고 다시 생성했습니다';

  @override
  String get messageChangesSaved => '변경 사항을 저장했습니다';

  @override
  String get messageSaveRetry => '저장하지 못했습니다. 다시 시도하세요.';

  @override
  String get inventoryTitle => '인벤토리';

  @override
  String get inventoryItemsTitle => '아이템';

  @override
  String get equipmentTitle => '장비';

  @override
  String get legacyInventoryTitle => '이전 인벤토리 기록';

  @override
  String inventorySummary(int itemCount, int equipmentCount) {
    return '아이템 $itemCount개, 장비 $equipmentCount개';
  }

  @override
  String get quickMenuTooltip => '빠른 메뉴';

  @override
  String get characterStatusTitle => '캐릭터 상태';

  @override
  String get wordCountSettings => '글자 수 설정';

  @override
  String get backToLobby => '로비로 돌아가기';

  @override
  String get restartAdventureTitle => '모험을 다시 시작할까요?';

  @override
  String get restartAdventureMessage => '현재 대화와 모험 진행 상황을 초기화하고 홈으로 돌아갑니다.';

  @override
  String get restartAdventureAction => '다시 시작';

  @override
  String get stopGenerationAction => '생성 중지';

  @override
  String get textAdventureTitle => '텍스트 모험';

  @override
  String get searchConversationAction => '대화 검색';

  @override
  String get historyAndSidebarAction => '장면 기록 및 사이드바';

  @override
  String get moreOptionsAction => '추가 옵션';

  @override
  String get replyLengthSetting => '답변 길이';

  @override
  String get switchModelAction => '모델 전환';

  @override
  String get promptSettingsAction => '프롬프트 설정';

  @override
  String get wordCountAndDensitySettings => '글자 수 및 대화 밀도 설정';

  @override
  String get reasoningCopiedToast => '추론 내용을 클립보드에 복사했습니다';

  @override
  String get editedBadge => '(편집됨)';

  @override
  String get deleteMessageConfirmation => '삭제한 메시지는 복구할 수 없습니다. 삭제할까요?';

  @override
  String get removeBookmarkAction => '북마크 해제';

  @override
  String get addBookmarkAction => '북마크 추가';

  @override
  String get editMessageAction => '편집';

  @override
  String get regenerateMessageAction => '다시 생성';

  @override
  String get assistantReplyLabel => 'AI 답변';

  @override
  String get selectModelForRegeneration => '다시 생성할 모델 선택';

  @override
  String get selectLanguageModel => '언어 모델 선택';

  @override
  String currentModelSummary(String model, String provider) {
    return '현재: $model ($provider)';
  }

  @override
  String get selectedModelLabel => '선택한 모델';

  @override
  String get defaultModelPlaceholder => '선택되지 않음(기본값 사용)';

  @override
  String get confirmApplyAction => '적용';

  @override
  String get selectValidModelError => '유효한 모델 이름을 선택하거나 입력하세요.';

  @override
  String get messageNoLongerCurrentError => '현재 대화에 없는 메시지입니다. 돌아가서 새로 고침하세요.';

  @override
  String get regenerationUserMessageMissingError =>
      '다시 생성할 수 없습니다. 유효한 사용자 메시지를 찾지 못했습니다.';

  @override
  String get regenerationTargetMissingError =>
      '다시 생성할 수 없습니다. 대상 사용자 메시지를 찾지 못했습니다.';

  @override
  String get modelRegenerationStarting => '다시 생성 중…';

  @override
  String modelSwitchedSuccess(String model) {
    return '모델을 전환했습니다: $model';
  }

  @override
  String get modelSwitchFailed => '모델을 전환하지 못했습니다. 다시 시도하세요.';

  @override
  String get serviceProviderSection => '서비스 제공업체';

  @override
  String get serviceProviderDescription =>
      '공식 API 제공업체 또는 로컬/타사 호환 서비스를 선택하세요.';

  @override
  String get llmProviderLabel => 'LLM 제공업체';

  @override
  String get recentModelsSection => '최근 사용';

  @override
  String get recentModelsDescription => '이 기기에서 사용한 모델로 빠르게 전환합니다.';

  @override
  String get recommendedModelsSection => '추천 모델';

  @override
  String get recommendedModelsDescription => '창작 글쓰기와 역할극에 최적화된 주요 모델입니다.';

  @override
  String get customModelSection => '사용자 지정 모델 이름';

  @override
  String get deepseekCustomModelDescription =>
      '다른 DeepSeek 전용 모델을 사용하려면 여기에 입력하세요.';

  @override
  String get otherCustomModelDescription =>
      '호환 엔드포인트가 지원하는 모델 식별자를 입력하세요(예: gpt-4o, claude-3-5-sonnet).';

  @override
  String get modelNamePlaceholder => '모델 이름 입력…';

  @override
  String customModelSelected(String model) {
    return '사용자 지정 모델 선택: $model';
  }

  @override
  String get adventureBlankSlateTitle => '새로운 모험의 시작';

  @override
  String get adventureBlankSlateDescription =>
      '이 장면에는 아직 대화나 행동 기록이 없습니다.\n아래에 행동을 입력하거나 탐험할 방향을 정해 모험을 시작하세요.';

  @override
  String get beginAdventureAction => '모험 시작';

  @override
  String get deepSeekFlashModelSubtitle =>
      '최신 추천 DeepSeek V4.1 Flash · 멀티모달 · 깊은 사고 지원';

  @override
  String get deepSeekLegacyModelSubtitle =>
      '이전 모델입니다. DeepSeek V4.1 Flash로 이전하는 것을 권장합니다';

  @override
  String get deleteDetectedStatusTitle => '상태 삭제';

  @override
  String confirmDeleteDetectedStatus(String name) {
    return '“$name” 상태를 삭제할까요?';
  }

  @override
  String get statusNameLabel => '상태 이름 *';

  @override
  String get statusNameExamples => '예: 정신력(SAN), 호감도, 오염도, 포만감';

  @override
  String get measurementModeLabel => '값 유형:';

  @override
  String get numericGaugeMode => '숫자 게이지 (0~100)';

  @override
  String get phaseDescriptionMode => '단계 설명';

  @override
  String get currentValueLabel => '현재 값';

  @override
  String get maxValueLabel => '최댓값';

  @override
  String get currentPhaseLabel => '현재 단계/설명';

  @override
  String get currentPhaseExamples => '예: 정상, 경미한 오염, 취기, 광폭화';

  @override
  String get chooseStatusIcon => '상태 아이콘 선택:';

  @override
  String get statusRuleLabel => '판정 규칙/스토리 지침 (선택)';

  @override
  String get statusRuleHint =>
      '예: 20 미만이면 공황 상태. 판정 성공 시 정신력을 유지하고 실패 시 환각이 발생합니다.';

  @override
  String get storyImportanceLabel => '스토리 중요도:';

  @override
  String get statusNameRequiredError => '상태 이름을 입력하세요.';

  @override
  String get addDetectedStatusAction => '상태 추가';

  @override
  String detectedStatusesCount(int count) {
    return '사용자 지정 상태 ($count)';
  }

  @override
  String get combatAdventureMatrix => '전투 및 모험 능력';

  @override
  String get physicalAttackStat => '물리 공격 (ATK)';

  @override
  String get baseDefenseStat => '기본 방어 (DEF)';

  @override
  String get agilitySpeedStat => '민첩성 (SPD)';

  @override
  String get goldStat => '보유 골드';

  @override
  String get availableSkillPointsStat => '사용 가능한 스킬 포인트';

  @override
  String get currentSceneCoordinatesStat => '현재 장면 좌표';

  @override
  String get openInventoryAction => '인벤토리 열기';

  @override
  String get profileIdentityTitle => '📜 신분 및 직업';

  @override
  String get profileBackgroundTitle => '📖 배경과 이력';

  @override
  String get profileWorldviewTitle => '🌍 세계관';

  @override
  String get profilePersonalityTitle => '🎭 성격';

  @override
  String get profileRelationshipsTitle => '🤝 유대와 관계';

  @override
  String get profileAppearanceTitle => '✨ 외모와 체형';

  @override
  String get checkAction => '판정';

  @override
  String levelRoleSummary(int level, String role) {
    return 'Lv. $level · $role';
  }

  @override
  String get editDetectedStatusTitle => '상태 편집';

  @override
  String get noCustomDetectedStatuses => '사용자 지정 상태가 없습니다';

  @override
  String get detectedStatusesEmptyDescription =>
      '정신력(SAN), 호감도, 오염도, 포만감, 마력 과부하 등의 모험 상태를 만들 수 있습니다.';

  @override
  String get energyLabel => '에너지';

  @override
  String get combatStatsTitle => '전투 능력';

  @override
  String get currentValuePrefix => '현재 값: ';

  @override
  String get currentPhaseWithThoughtsLabel => '현재 상태 단계/생각';

  @override
  String get phaseNotTriggered => '(단계 판정이 아직 발생하지 않았습니다)';

  @override
  String statusRulePrefix(String rule) {
    return '📌 규칙: $rule';
  }

  @override
  String get companionsTab => '상태';

  @override
  String get equipmentTab => '장비';

  @override
  String get profileTab => '인물 정보';

  @override
  String currentExplorationRegion(String scene) {
    return '현재 탐험 지역: $scene';
  }

  @override
  String mainStoryChapter(int chapter) {
    return '메인 모험가 · $chapter장';
  }

  @override
  String relationshipLabel(String relation) {
    return '관계: $relation';
  }

  @override
  String affinityScoreLabel(int affinity) {
    return '❤️ 호감도: $affinity';
  }

  @override
  String get healthPointsLabel => '생명력 (HP)';

  @override
  String get lifeForceLabel => '활력';

  @override
  String get magicPointsLabel => '정신 마법 (MP)';

  @override
  String get focusLabel => '집중력';

  @override
  String get actionEnergyLabel => '행동 에너지';

  @override
  String get tiredStatus => '⚠️ 피로';

  @override
  String get goodStatus => '양호';

  @override
  String get experienceLabel => '경험치 (EXP)';

  @override
  String nextLevelExperience(int count) {
    return '다음 레벨까지 $count';
  }

  @override
  String skillPointsValue(int count) {
    return '$count 포인트';
  }

  @override
  String equippedGearCount(int count) {
    return '⚔️ 장착 장비 ($count)';
  }

  @override
  String get noEquippedGear => '장착한 장비가 없습니다. 인벤토리나 상점에서 장비를 얻어 전투력을 높이세요.';

  @override
  String gearSlotQuality(String slot, String quality) {
    return '부위: $slot · 품질: $quality';
  }

  @override
  String get carriedItemsTitle => '🎒 소지품과 재료';

  @override
  String get noCarriedItems => '소지품이 없습니다.';

  @override
  String get sharedPartyInventory => '📦 파티 공용 인벤토리:';

  @override
  String get detectedStatusFormDescription =>
      '게이지, 판정 규칙, 주사위 굴림을 사용해 모험 상태를 추적합니다.';

  @override
  String get statusPresetsHeading => '💡 프리셋 예시 (탭하여 입력):';

  @override
  String get explorerRole => '모험가';

  @override
  String get startingTown => '시작 마을';

  @override
  String get defaultProtagonistProfile =>
      '미지의 변경을 탐험하고 이야기의 결정을 내리는 기민한 모험가입니다.';

  @override
  String get defaultProtagonistBackground => '격동하는 세계로 여정을 떠나 미지의 운명을 헤쳐 나갑니다.';

  @override
  String get defaultWorldviewDescription => '이야기의 진행에 따라 변화하는 몰입형 역할극 세계입니다.';

  @override
  String get defaultCompanionPersonality => '여정 속에서 진정한 바람을 드러내는 차분한 성격입니다.';

  @override
  String genderTag(String value) {
    return '성별: $value';
  }

  @override
  String heightTag(String value) {
    return '키: $value';
  }

  @override
  String hairstyleTag(String value) {
    return '머리: $value';
  }

  @override
  String skinToneTag(String value) {
    return '피부색: $value';
  }

  @override
  String facialFeaturesTag(String value) {
    return '얼굴 특징: $value';
  }

  @override
  String get aliveStatus => '💚 건강';

  @override
  String get incapacitatedStatus => '💀 행동 불능';

  @override
  String companionRelationshipSummary(String relation, int affinity) {
    return '주인공과의 관계: $relation. 현재 호감도: $affinity/100.';
  }

  @override
  String get diceCriticalSuccess => '대성공! 완벽한 판정입니다.';

  @override
  String get diceCriticalFailure => '대실패! 심각한 실수나 역효과가 발생했습니다.';

  @override
  String get diceSuccess => '판정 성공! 이상 현상을 막고 상태를 유지했습니다.';

  @override
  String get diceFailure => '판정 실패! 상태의 영향이나 부정적인 효과를 받았습니다.';

  @override
  String get diceCheckCriticalSuccess => '대성공(치명타)! 한계를 돌파했습니다.';

  @override
  String get diceCheckCriticalFailure => '대실패! 판정에 완전히 실패했습니다.';

  @override
  String get diceCheckPassed => '판정 통과! 상태가 안정적으로 유지됩니다.';

  @override
  String get diceCheckFailed => '판정 실패! 방해나 부정적인 영향을 받았습니다.';

  @override
  String diceTargetValue(int current, int maximum) {
    return '목표 값: $current / $maximum';
  }

  @override
  String diceCurrentStatus(String status) {
    return '현재 상태: $status';
  }

  @override
  String diceRuleDescription(String rule) {
    return '판정 규칙: $rule';
  }

  @override
  String get d100PercentileDie => 'D100 백분위 주사위';

  @override
  String get d20Die => 'D20 주사위';

  @override
  String get rollCheckAction => '판정 주사위 굴리기';

  @override
  String get rerollAction => '다시 굴리기';

  @override
  String get syncResultToAdventure => '모험 이야기로 전송';

  @override
  String diceResultPoints(String icon, int value, String denominator) {
    return '$icon 결과: $value $denominator';
  }

  @override
  String get diceResultWillBeSent => '결과가 사용자 메시지로 전송됩니다.';

  @override
  String diceResultMessage(String status, String rule, String character,
      int roll, String target, String verdict) {
    return '【상태 판정】$character이(가) “$status” 판정을 수행했습니다: 🎲 $roll ($target) → 【$verdict】! $rule';
  }

  @override
  String get allItemsFilter => '전체';

  @override
  String get consumableItemType => '소모품';

  @override
  String get equipmentItemType => '장비';

  @override
  String get materialItemType => '재료';

  @override
  String get questItemType => '퀘스트 아이템';

  @override
  String get weaponSlot => '무기';

  @override
  String get armorSlot => '방어구';

  @override
  String get accessorySlot => '장신구';

  @override
  String get specialSlot => '특수';

  @override
  String get commonQuality => '일반';

  @override
  String get uncommonQuality => '고급';

  @override
  String get rareQuality => '희귀';

  @override
  String get epicQuality => '영웅';

  @override
  String get legendaryQuality => '전설';

  @override
  String get emptyInventoryTitle => '인벤토리가 비어 있습니다';

  @override
  String get emptyInventoryDescription => '이야기에서 획득한 아이템이 여기에 표시됩니다.';

  @override
  String get deepThinkingStatus => '깊이 생각하는 중…';

  @override
  String get reasoningExpandedLabel => '사고 과정 (탭하여 접기)';

  @override
  String get reasoningCollapsedLabel => '깊은 사고 완료 (탭하여 추론 펼치기)';

  @override
  String get thinkingInProgressStatus => '생각 중…';

  @override
  String get reasoningUnavailableLabel => '(기록 없음)';

  @override
  String get copyReasoningAction => '추론 복사';

  @override
  String get writingStoryStatus => '이야기 작성 중…';

  @override
  String get dialogueReplyLengthSettingsTitle => '장면 대화 답변 길이 조정';

  @override
  String dialogueCurrentSelection(String id, String name, String range) {
    return '선택: $id · $name ($range)';
  }

  @override
  String dialogueWordsAbove(int minWords) {
    return '$minWords자 이상';
  }

  @override
  String get dialogueLevelFast => '빠르게';

  @override
  String get dialogueLevelConcise => '간결하게';

  @override
  String get dialogueLevelStandard => '표준';

  @override
  String get dialogueLevelDetailed => '상세하게';

  @override
  String get dialogueLevelDeep => '깊이 있게';

  @override
  String get dialogueLevelProduction => '장문 작성';

  @override
  String get dialogueLevelFastDesc => '핵심 피드백만 남겨 빠르게 확인합니다.';

  @override
  String get dialogueLevelConciseDesc => '가벼운 상호작용에 적합한 짧은 진행입니다.';

  @override
  String get dialogueLevelStandardDesc => '속도와 몰입감의 균형을 맞춘 기본 모드입니다.';

  @override
  String get dialogueLevelDetailedDesc => '더 자세한 묘사와 상호작용을 제공합니다.';

  @override
  String get dialogueLevelDeepDesc => '복선, 심리, 장면의 층위를 강조합니다.';

  @override
  String get dialogueLevelProductionDesc => '진지한 글쓰기에 적합한 장문 출력입니다.';

  @override
  String get adventureRefreshUnavailable =>
      '생성 중이거나 장면을 사용할 수 없어 새로 고침할 수 없습니다.';

  @override
  String get sessionOfflineHint => '오프라인 — 네트워크에 연결할 수 없습니다';

  @override
  String get sessionInputHint => '행동이나 대화를 입력하세요…';

  @override
  String get messageGestureHint =>
      '오른쪽으로 밀어 재시도 · 왼쪽으로 밀어 삭제 · 길게 눌러 편집 또는 북마크';

  @override
  String get adventureAssistantName => '모험 도우미';

  @override
  String get currentUserDisplayName => '나';

  @override
  String get unknownRegion => '알 수 없는 지역';

  @override
  String get deepThinkingBadge => '깊이 생각 중';

  @override
  String get supportingCharacterRole => '조연';

  @override
  String get autoSwitchCharacterTooltip => '캐릭터 자동 전환';

  @override
  String get sessionSettlingStatus => '선택지와 턴 상태를 생성하는 중…';

  @override
  String get aiReplyLabel => 'AI 답변';

  @override
  String sectionValidationPassed(String title) {
    return '‘$title’ 검증을 통과했습니다';
  }

  @override
  String sectionValidationFailed(String title, int count) {
    return '‘$title’ 검증 실패: $count개 문제';
  }

  @override
  String get sectionValidationComplete => '검증이 완료되었습니다';

  @override
  String sectionRegenerated(String title, int completed, int total) {
    return '‘$title’ 섹션의 $total개 단락 중 $completed개를 다시 생성했습니다';
  }

  @override
  String sectionRegenerationFailed(String title, String error) {
    return '‘$title’ 생성 중단: $error';
  }

  @override
  String get sectionGenerationComplete => '생성이 완료되었습니다';

  @override
  String get capacityNoCompressionNeeded => '압축할 단락이 없습니다.';

  @override
  String get capacityCompressionAlreadyPublished =>
      '이 압축 후보는 이미 게시되어 본문을 다시 변경하지 않았습니다.';

  @override
  String capacityCompressionPublished(int savedCharacters) {
    return '압축 후보를 게시해 약 $savedCharacters자를 줄였습니다. 게시 전 본문은 버전 기록에 보관했습니다.';
  }

  @override
  String capacityRetryBlockedByActiveTarget(int count) {
    return '대상에서 압축이 진행 중이어서 실패한 작업 $count개를 건너뛰었습니다.';
  }

  @override
  String capacityRetryBudgetExhausted(int count) {
    return '재시도할 수 있는 압축 작업이 없습니다. $count개 작업이 재시도 한도에 도달했습니다.';
  }

  @override
  String get capacityRetryUnavailable => '재시도할 압축 작업이 없습니다.';

  @override
  String capacityCompressionRunSummary(int succeeded, int failed, int requeued,
      int activeSkipped, int exhaustedSkipped) {
    return '후보 $succeeded개 생성, 작업 $failed개 실패, $requeued개 재시도 등록, 대상 압축 진행 중으로 $activeSkipped개 건너뜀, 재시도 한도 도달로 $exhaustedSkipped개 건너뜀. 후보를 적용하려면 확인이 필요하며 실패한 작업은 원문을 변경하지 않습니다.';
  }

  @override
  String get revisionCauseManualSave => '수동 저장';

  @override
  String get revisionCauseGeneration => 'AI 생성';

  @override
  String get revisionCausePlanning => '개요 계획';

  @override
  String get revisionCauseRegeneration => '다시 생성';

  @override
  String get revisionCauseCompression => '의미 압축';

  @override
  String get revisionCauseRestore => '복원';

  @override
  String get revisionCauseMigration => '데이터 마이그레이션';

  @override
  String get revisionCauseDeletion => '삭제 전 스냅샷';

  @override
  String get revisionUnknownDate => '날짜 알 수 없음';

  @override
  String get revisionAlreadyCurrent => '이 버전은 이미 현재 버전입니다.';

  @override
  String revisionRestored(String sourceCause) {
    return '$sourceCause 버전으로 복원했습니다.';
  }

  @override
  String revisionItemSubtitle(String date, int nodeCount, int charCount) {
    return '$date · 노드 $nodeCount개 · 글자 $charCount자';
  }

  @override
  String resourceRevisionOperationFailed(String error) {
    return '버전 작업 실패: $error';
  }

  @override
  String get resourceTrashKindResource => '리소스';

  @override
  String get resourceTrashKindSection => '섹션';

  @override
  String get resourceTrashKindPart => '문단';

  @override
  String get resourceTrashReasonUserDelete => '사용자 삭제';

  @override
  String get resourceTrashRestoreOriginal => '원래 위치로 복원했습니다.';

  @override
  String get resourceTrashRestoreFallback => '원래 섹션이 없어 리소스 루트의 새 섹션에 복원했습니다.';

  @override
  String get resourceTrashRestoreToLibrary => '리소스 라이브러리로 복원했습니다.';

  @override
  String get resourceTrashAlreadyRestored => '이미 복원된 항목이며 변경 사항이 없습니다.';

  @override
  String resourceTrashLoadFailed(String error) {
    return '휴지통을 불러오지 못했습니다: $error';
  }

  @override
  String get unnamedSceneTitle => '제목 없는 장면';

  @override
  String get statusPresetSanityLabel => '🧠 이성 (SAN)';

  @override
  String get statusPresetSanityName => '이성 (SAN)';

  @override
  String get statusPresetSanityDescription =>
      '미지와 공포에 저항합니다. 20 미만이면 환각에 빠질 수 있습니다.';

  @override
  String get statusPresetAffinityLabel => '❤️ 캐릭터 호감도';

  @override
  String get statusPresetAffinityName => '호감도';

  @override
  String get statusPresetAffinityDescription =>
      '캐릭터와의 유대감을 나타냅니다. 일정 수치에 도달하면 특별한 이야기와 상호작용이 열립니다.';

  @override
  String get statusPresetCorruptionLabel => '☣️ 심연 침식';

  @override
  String get statusPresetCorruptionName => '심연 침식도';

  @override
  String get statusPresetCorruptionDescription =>
      '육체와 정신의 변이가 쌓입니다. 지나치게 높아지면 변이가 나타날 수 있습니다.';

  @override
  String get statusPresetHungerLabel => '🍖 포만 / 허기';

  @override
  String get statusPresetHungerName => '포만도';

  @override
  String get statusPresetHungerDescription =>
      '탐험에 필요한 체력을 나타냅니다. 30 미만이면 쇠약과 피로가 생길 수 있습니다.';

  @override
  String get statusPresetMagicLabel => '🔥 마력 과부하';

  @override
  String get statusPresetMagicName => '마력 과부하';

  @override
  String get statusPresetMagicDescription =>
      '몸 안에서 폭주하는 힘입니다. 과부하 상태에서 주문을 쓰면 다치거나 역효과가 날 수 있습니다.';

  @override
  String get statusPresetPressureLabel => '⚡ 정신적 압박';

  @override
  String get statusPresetPressureName => '정신적 압박';

  @override
  String get statusPresetPressureDescription => '공포와 위기로 인해 쌓이는 심리적 부담을 나타냅니다.';

  @override
  String get statusPresetArmorLabel => '🛡️ 방어구 내구도';

  @override
  String get statusPresetArmorName => '방어구 내구도';

  @override
  String get statusPresetArmorDescription =>
      '방어 장비의 내구성을 나타내며 외부 충격을 먼저 흡수합니다.';

  @override
  String get statusPresetSpiritLabel => '💧 영력 비축량';

  @override
  String get statusPresetSpiritName => '영력 비축량';

  @override
  String get statusPresetSpiritDescription =>
      '주술과 초자연적 능력을 사용하는 데 필요한 핵심 영적 에너지입니다.';

  @override
  String get adventureDefaultOpeningScene =>
      '낯선 변경에서 눈을 뜬다. 주변은 고요하다. 짐을 정리하고 첫걸음을 내디딜 준비를 한다.';

  @override
  String get adventureDefaultOpeningOptionOne => '소지품과 지도를 확인한다';

  @override
  String get adventureDefaultOpeningOptionTwo => '앞에 난 길을 따라 계속 탐험한다';

  @override
  String get adventureDefaultOpeningOptionThree => '몸을 숨기고 주변을 살핀다';

  @override
  String get autosaveTriggerDebounce => '입력 일시 중지 후 저장';

  @override
  String get autosaveTriggerMaxBufferedAge => '연속 입력 중 저장';

  @override
  String get autosaveTriggerManual => '수동 저장';

  @override
  String get autosaveTriggerPageLeave => '페이지를 나가기 전 저장';

  @override
  String get autosaveTriggerDispose => '편집기를 닫기 전 저장';

  @override
  String get autosaveTriggerCancel => '생성을 취소하기 전 저장';

  @override
  String get autosaveTriggerGenerationError => '생성 실패를 알리기 전 저장';

  @override
  String get autosaveTriggerAppLifecycle => '앱이 백그라운드로 이동하기 전 저장';

  @override
  String get revisionBeforeRestore => '복원 전';

  @override
  String get revisionBeforeCompression => '압축 전';

  @override
  String get revisionAssembly => '구성 스냅샷';

  @override
  String revisionCompressionSaved(int characters) {
    return '의미 압축($characters자 절약)';
  }

  @override
  String get revisionModeRegenerate => '재생성';

  @override
  String get revisionModeRewrite => '다시 쓰기';

  @override
  String get revisionModeExpand => '확장';

  @override
  String get revisionModeCondense => '축약';

  @override
  String revisionBeforeRegeneration(String mode) {
    return '$mode 전';
  }

  @override
  String readAloudSegmentProgress(int current, int total) {
    return '$total개 중 $current번째';
  }

  @override
  String sessionTokenUsageMeter(int current, int limitThousands) {
    return '$current / ${limitThousands}K 토큰';
  }

  @override
  String combatStatsSummary(int attack, int defense, int speed) {
    return '전투 능력 · 공격 $attack · 방어 $defense · 속도 $speed';
  }

  @override
  String get adventureAssetNotManaged =>
      '이 자산은 통합 리소스 라이브러리 외부에 있어 조립 준비 확인 대상이 아닙니다.';

  @override
  String get adventureAssemblyMissingCharacterCard =>
      '조립 버전에 캐릭터 카드가 없어 모험을 시작할 수 없습니다.';

  @override
  String get adventureAssemblyInvalidCharacterCard =>
      '조립 버전의 캐릭터 카드를 읽을 수 없어 모험을 시작할 수 없습니다.';

  @override
  String adventureAssetNoSavedRevision(String name) {
    return '‘$name’에 저장된 버전이 없어 모험을 시작할 수 없습니다.';
  }

  @override
  String adventureAssetPreparing(String name) {
    return '‘$name’ 조립을 준비하고 있습니다. 잠시 기다려 주세요.';
  }

  @override
  String adventureAssetPreparingWithDetails(String name, String details) {
    return '‘$name’ 조립을 준비하고 있습니다: $details';
  }

  @override
  String adventureAssetPreparationFailed(String name, String details) {
    return '‘$name’ 조립 준비에 실패했습니다: $details';
  }

  @override
  String adventureAssetReady(String name) {
    return '‘$name’ 준비가 완료되었습니다.';
  }

  @override
  String adventureAssetNoAssemblyRevision(String name) {
    return '‘$name’에 사용할 수 있는 버전이 없습니다. 먼저 리소스 조립을 완료해 주세요.';
  }

  @override
  String adventureAssetStaleWithPrevious(String name) {
    return '‘$name’이(가) 변경되었습니다. 이전에 준비된 버전을 사용할 수 있습니다.';
  }

  @override
  String get errorUnknown => '알 수 없는 오류가 발생했습니다. 다시 시도해 주세요.';

  @override
  String get errorNetworkUnavailable => '네트워크 연결에 실패했습니다. 연결을 확인하고 다시 시도해 주세요.';

  @override
  String get errorRequestTimeout => '요청 시간이 초과되었습니다. 다시 시도해 주세요.';

  @override
  String get errorUnauthorized => '인증에 실패했습니다. API 설정을 확인해 주세요.';

  @override
  String get errorPaymentRequired => 'API 계정을 확인해야 요청을 계속할 수 있습니다.';

  @override
  String get errorForbidden => '접근이 거부되었습니다. API 권한을 확인해 주세요.';

  @override
  String get errorNotFound => '요청한 모델 또는 엔드포인트를 찾을 수 없습니다.';

  @override
  String get errorRateLimited => '요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.';

  @override
  String get errorInvalidRequest => '요청을 처리할 수 없습니다. 설정을 확인하고 다시 시도해 주세요.';

  @override
  String resourceErrorCapacityExceeded(int current, int limit) {
    return '리소스 용량을 초과했습니다($current/$limit).';
  }

  @override
  String resourceErrorValidationFailed(String details) {
    return '리소스 검증에 실패했습니다: $details';
  }

  @override
  String get resourceErrorGenerationFailed => '리소스 생성에 실패했습니다. 다시 시도해 주세요.';

  @override
  String get resourceErrorConflict => '리소스가 변경되었습니다. 새로 고친 후 다시 시도해 주세요.';

  @override
  String adventureErrorAssetMissing(String name) {
    return '\"$name\"은(는) 모험을 시작할 준비가 되지 않았습니다.';
  }

  @override
  String adventureErrorAssetStale(String name) {
    return '\"$name\"이(가) 변경되어 다시 준비해야 합니다.';
  }

  @override
  String get ttsErrorUnsupported => '이 환경에서는 소리 내어 읽기를 지원하지 않습니다.';

  @override
  String get ttsErrorEngineUnavailable => '읽기 엔진을 사용할 수 없습니다.';

  @override
  String get ttsErrorVoiceUnavailable => '선택한 음성을 사용할 수 없습니다.';

  @override
  String get ttsErrorPlaybackFailed => '읽기에 실패했습니다. 다시 시도해 주세요.';

  @override
  String eventCombatVictory(int exp, int gold) {
    return '승리! 경험치 $exp와 골드 $gold을(를) 획득했습니다.';
  }

  @override
  String eventCombatAttack(String actor) {
    return '$actor이(가) 공격했습니다.';
  }

  @override
  String eventCombatCriticalHit(String actor) {
    return '$actor의 치명타!';
  }

  @override
  String eventCombatSkillUsed(String skill) {
    return '$skill 기술을 사용했습니다.';
  }

  @override
  String get eventCombatDefeat => '패배했습니다.';

  @override
  String eventLevelUp(int level) {
    return '레벨 업! 레벨 $level이(가) 되었습니다.';
  }

  @override
  String get eventRestCompleted => '휴식이 완료되었습니다.';

  @override
  String eventItemAdded(String item) {
    return '$item을(를) 획득했습니다.';
  }

  @override
  String eventItemRemoved(String item) {
    return '$item을(를) 제거했습니다.';
  }

  @override
  String eventItemUsed(String item) {
    return '$item을(를) 사용했습니다.';
  }

  @override
  String eventSkillLearned(String skill) {
    return '$skill 기술을 배웠습니다.';
  }

  @override
  String get eventSkillFailed => '기술을 사용할 수 없습니다.';
}
