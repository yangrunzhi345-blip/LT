/// 全局朗读（Read-Aloud）的纯数据契约。
///
/// 这一层只描述“朗读系统对外暴露的事实”：播放状态、来源标识、平台能力与
/// 用户偏好。它不包含任何 Flutter 依赖，也不包含引擎实现，因此可以被
/// presentation 层安全引用，而无需让 UI 直接依赖 `lib/services/**`。
library;

/// 朗读播放状态机。
///
/// 状态只由唯一的全局 Authority（[ReadAloudController]）驱动，页面不得自行
/// 维护“正在播放”的伪状态。
enum ReadAloudStatus {
  /// 没有朗读任务。
  idle,

  /// 已接受任务，正在准备引擎/首段。
  preparing,

  /// 正在朗读当前段。
  playing,

  /// 已暂停，等待继续。
  paused,

  /// 全部段朗读完毕。
  completed,

  /// 被用户或页面显式停止。
  stopped,

  /// 发生不可忽略的错误（含平台能力缺失）。
  error,
}

/// Stable failure categories exposed by the read-aloud authority.
enum ReadAloudErrorCode {
  unsupported,
  engineUnavailable,
  voiceUnavailable,
  playbackFailed,
}

extension ReadAloudStatusX on ReadAloudStatus {
  /// 是否存在一个仍然“持有”播放权、尚未终结的会话。
  bool get isActive =>
      this == ReadAloudStatus.preparing ||
      this == ReadAloudStatus.playing ||
      this == ReadAloudStatus.paused;
}

/// 朗读来源类型，用于 UI 判断“当前朗读是否属于我”。
enum ReadAloudSourceType {
  /// 对话中的一条 AI 回复。
  chat,

  /// Resource Studio 的单个 Part。
  studioPart,

  /// Resource Studio 的整个资源（按 Section/Part 顺序连续朗读）。
  studioResource,

  /// 组装/预览页的可读正文。
  assemblyPreview,

  /// 其它一次性正文。
  generic,
}

/// 平台朗读能力。
///
/// 能力必须如实反映真实后端：不支持时 UI 必须能显式提示，绝不能伪造成功。
class ReadAloudCapability {
  const ReadAloudCapability({
    required this.supported,
    required this.supportsPause,
    this.reasonCode,
    this.message,
  });

  /// 后端可用，可以朗读。
  const ReadAloudCapability.available({required this.supportsPause})
      : supported = true,
        reasonCode = null,
        message = null;

  /// 后端不可用；[reasonCode] 为稳定的机器可读标识，[message] 为用户可读说明。
  const ReadAloudCapability.unavailable({
    required String this.reasonCode,
    required String this.message,
  })  : supported = false,
        supportsPause = false;

  /// 是否支持朗读。
  final bool supported;

  /// 是否支持 pause/resume。不支持时 UI 必须隐藏/禁用暂停入口。
  final bool supportsPause;

  /// 稳定错误码，例如 `unsupported_platform` / `plugin_unavailable`。
  final String? reasonCode;

  /// Legacy diagnostic copy. Presentation must map [reasonCode] through the
  /// active locale instead of rendering this value.
  @Deprecated('Use reasonCode and the presentation localizer.')
  final String? message;
}

/// 一段待朗读的原始正文（尚未清洗与分段）。
class ReadAloudSource {
  const ReadAloudSource({
    required this.id,
    required this.text,
    this.label,
  });

  /// 段级来源 id：对话消息 id、ResourcePart id 等。
  ///
  /// 播放推进到该段时，[ReadAloudState.currentChunkId] 会等于这个 id，因此
  /// 连续阅读可以把“当前朗读段”映射回具体的 Part/Section。
  final String id;

  /// 可选的人类可读标题（例如 Part 标题）。
  final String? label;

  /// 原始正文，允许包含 Markdown/HTML/协议 JSON；由清洗器负责过滤。
  final String text;
}

/// 朗读语言选择模式。
///
/// 用显式枚举区分“自动检测”与“固定语言”，而不是用一个 nullable String 把
/// 两种语义混在一起：`null` 既可能表示“自动”，也可能表示“用户没选过”，
/// 会让持久化与 UI 都无法可靠表达当前意图。
enum ReadAloudLanguageMode {
  /// 每个朗读 Chunk 基于正文自动检测语言。
  auto,

  /// 所有 Chunk 都使用用户指定的 [ReadAloudPreferences.languageTag]。
  fixed,
}

/// 用户朗读偏好。默认值沿用既有行为。
class ReadAloudPreferences {
  const ReadAloudPreferences({
    this.enabled = false,
    this.autoRead = false,
    this.rate = 0.5,
    this.pitch = 1.0,
    this.volume = 0.9,
    this.languageMode = ReadAloudLanguageMode.auto,
    this.languageTag = defaultLanguageTag,
  });

  /// 固定模式与自动检测无法可靠判断时使用的默认语言。
  ///
  /// 沿用既有全局朗读的默认语言，保证未做任何语言设置的老用户行为不变。
  static const String defaultLanguageTag = 'zh-CN';

  /// 朗读总开关。关闭时手动朗读与自动朗读都不触发。
  final bool enabled;

  /// AI 生成完成后自动朗读。
  final bool autoRead;

  final double rate;
  final double pitch;
  final double volume;

  /// 语言选择模式：自动检测或固定语言。
  final ReadAloudLanguageMode languageMode;

  /// 固定模式的目标语言，同时作为自动模式的兜底语言。
  ///
  /// 存储为归一化后的 BCP-47 tag（例如 `zh-CN` / `en-US`）；架构本身不限制
  /// 取值，只需要是合法的 BCP-47。
  final String languageTag;

  static const ReadAloudPreferences defaults = ReadAloudPreferences();

  ReadAloudPreferences copyWith({
    bool? enabled,
    bool? autoRead,
    double? rate,
    double? pitch,
    double? volume,
    ReadAloudLanguageMode? languageMode,
    String? languageTag,
  }) {
    return ReadAloudPreferences(
      enabled: enabled ?? this.enabled,
      autoRead: autoRead ?? this.autoRead,
      rate: rate ?? this.rate,
      pitch: pitch ?? this.pitch,
      volume: volume ?? this.volume,
      languageMode: languageMode ?? this.languageMode,
      languageTag: languageTag ?? this.languageTag,
    );
  }
}

/// 朗读系统的全局不可变状态快照。
class ReadAloudState {
  const ReadAloudState({
    this.status = ReadAloudStatus.idle,
    this.sourceId,
    this.sourceType,
    this.currentChunkId,
    this.currentLabel,
    this.currentText = '',
    this.segmentIndex = -1,
    this.segmentCount = 0,
    this.preferences = ReadAloudPreferences.defaults,
    this.capability = const ReadAloudCapability.unavailable(
      reasonCode: 'not_initialized',
      message: '朗读尚未初始化',
    ),
    this.errorMessage,
    this.errorCode,
    this.runId = 0,
    this.requestedLanguageTag,
    this.resolvedLanguageTag,
    this.availableLanguages = const <String>[],
  });

  final ReadAloudStatus status;

  /// 会话级来源 id（消息 id / 资源 id）。
  final String? sourceId;
  final ReadAloudSourceType? sourceType;

  /// 当前段所属的段级来源 id（Part id 等）。
  final String? currentChunkId;

  /// 当前段标题。
  final String? currentLabel;

  /// 当前正在朗读的正文（清洗后的可见文本）。
  final String currentText;

  /// 当前段下标（0 基），无会话时为 -1。
  final int segmentIndex;

  /// 段总数。
  final int segmentCount;

  final ReadAloudPreferences preferences;

  final ReadAloudCapability capability;

  final String? errorMessage;

  /// Stable failure category; technical detail is never stored here.
  final ReadAloudErrorCode? errorCode;

  /// 单调递增的 run token，用于隔离迟到的 completion/error 回调。
  final int runId;

  /// 当前段请求使用的语言（自动检测结果或用户固定语言）。
  ///
  /// 这是“想用什么语言读”，可能因为系统不支持而落到
  /// [resolvedLanguageTag] 上的其它语言。
  final String? requestedLanguageTag;

  /// 当前段实际应用到引擎的语言。
  ///
  /// 当它和 [requestedLanguageTag] 不同时，说明发生过 fallback；UI/调试不应
  /// 把它伪装成请求语言。
  final String? resolvedLanguageTag;

  /// 系统真实可用的语言列表（归一化 BCP-47）。
  ///
  /// 空列表表示“能力未知”（例如后端不提供枚举或平台不支持），此时不得由
  /// 代码支持列表推断可用性。
  final List<String> availableLanguages;

  /// 当前实际用于朗读的语言，等价于 [resolvedLanguageTag]。
  String? get currentLanguageTag => resolvedLanguageTag;

  /// 系统是否上报了可用的语言列表。
  bool get hasKnownLanguages => availableLanguages.isNotEmpty;

  bool get enabled => preferences.enabled;
  bool get autoRead => preferences.autoRead;
  double get rate => preferences.rate;
  double get pitch => preferences.pitch;
  double get volume => preferences.volume;

  /// 当前语言选择模式。
  ReadAloudLanguageMode get languageMode => preferences.languageMode;

  /// 用户配置的固定/兜底语言。
  String get languageTag => preferences.languageTag;

  /// 当前段是否因为系统不支持而发生语言 fallback。
  bool get hasLanguageFallback =>
      requestedLanguageTag != null &&
      resolvedLanguageTag != null &&
      requestedLanguageTag != resolvedLanguageTag;

  /// 是否存在活跃会话。
  bool get hasActiveSession => status.isActive;

  /// 后端能力 + 用户开关都允许播放。
  bool get canPlay => capability.supported && preferences.enabled;

  /// 当前是否正在朗读 [sourceId] 这个会话。
  bool isActiveSource(String sourceId) =>
      hasActiveSession && this.sourceId == sourceId;

  /// 当前朗读段是否属于 [chunkId]。
  ///
  /// 连续朗读整份资源时，会话 id 是资源 id，而每个段携带 Part id；UI 用这个
  /// 判断“正在念的就是我这一段”，从而把朗读映射回对应 Part。
  bool isSpeakingChunk(String chunkId) =>
      hasActiveSession && currentChunkId == chunkId;

  /// 是否朗读 [sourceId] 这个会话，且正处于 playing。
  bool isPlayingSource(String sourceId) =>
      status == ReadAloudStatus.playing && this.sourceId == sourceId;

  /// 进度文案，例如 `第 2/7 段`。
  String get progressLabel {
    if (segmentCount <= 0 || segmentIndex < 0) return '';
    return '第 ${segmentIndex + 1}/$segmentCount 段';
  }

  /// [copyWith] 的哨兵值：区分“不修改该字段”与“显式清空为 null”。
  static const Object unset = Object();

  ReadAloudState copyWith({
    ReadAloudStatus? status,
    Object? sourceId = unset,
    Object? sourceType = unset,
    Object? currentChunkId = unset,
    Object? currentLabel = unset,
    String? currentText,
    int? segmentIndex,
    int? segmentCount,
    ReadAloudPreferences? preferences,
    ReadAloudCapability? capability,
    Object? errorMessage = unset,
    Object? errorCode = unset,
    int? runId,
    Object? requestedLanguageTag = unset,
    Object? resolvedLanguageTag = unset,
    List<String>? availableLanguages,
  }) {
    return ReadAloudState(
      status: status ?? this.status,
      sourceId:
          identical(sourceId, unset) ? this.sourceId : sourceId as String?,
      sourceType: identical(sourceType, unset)
          ? this.sourceType
          : sourceType as ReadAloudSourceType?,
      currentChunkId: identical(currentChunkId, unset)
          ? this.currentChunkId
          : currentChunkId as String?,
      currentLabel: identical(currentLabel, unset)
          ? this.currentLabel
          : currentLabel as String?,
      currentText: currentText ?? this.currentText,
      segmentIndex: segmentIndex ?? this.segmentIndex,
      segmentCount: segmentCount ?? this.segmentCount,
      preferences: preferences ?? this.preferences,
      capability: capability ?? this.capability,
      errorMessage: identical(errorMessage, unset)
          ? this.errorMessage
          : errorMessage as String?,
      errorCode: identical(errorCode, unset)
          ? this.errorCode
          : errorCode as ReadAloudErrorCode?,
      runId: runId ?? this.runId,
      requestedLanguageTag: identical(requestedLanguageTag, unset)
          ? this.requestedLanguageTag
          : requestedLanguageTag as String?,
      resolvedLanguageTag: identical(resolvedLanguageTag, unset)
          ? this.resolvedLanguageTag
          : resolvedLanguageTag as String?,
      availableLanguages: availableLanguages ?? this.availableLanguages,
    );
  }
}
