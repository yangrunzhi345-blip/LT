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

  /// 面向用户的能力说明。
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

/// 用户朗读偏好。默认值沿用既有行为。
class ReadAloudPreferences {
  const ReadAloudPreferences({
    this.enabled = false,
    this.autoRead = false,
    this.rate = 0.5,
    this.pitch = 1.0,
    this.volume = 0.9,
  });

  /// 朗读总开关。关闭时手动朗读与自动朗读都不触发。
  final bool enabled;

  /// AI 生成完成后自动朗读。
  final bool autoRead;

  final double rate;
  final double pitch;
  final double volume;

  static const ReadAloudPreferences defaults = ReadAloudPreferences();

  ReadAloudPreferences copyWith({
    bool? enabled,
    bool? autoRead,
    double? rate,
    double? pitch,
    double? volume,
  }) {
    return ReadAloudPreferences(
      enabled: enabled ?? this.enabled,
      autoRead: autoRead ?? this.autoRead,
      rate: rate ?? this.rate,
      pitch: pitch ?? this.pitch,
      volume: volume ?? this.volume,
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
    this.runId = 0,
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

  /// 单调递增的 run token，用于隔离迟到的 completion/error 回调。
  final int runId;

  bool get enabled => preferences.enabled;
  bool get autoRead => preferences.autoRead;
  double get rate => preferences.rate;
  double get pitch => preferences.pitch;
  double get volume => preferences.volume;

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
    int? runId,
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
      runId: runId ?? this.runId,
    );
  }
}
