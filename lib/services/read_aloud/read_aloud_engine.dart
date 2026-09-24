import '../../domain/read_aloud/read_aloud_contracts.dart';

/// 朗读引擎异常。引擎层只抛出这一种错误类型，由 Authority 映射为
/// [ReadAloudStatus.error]，避免平台异常细节泄漏到 UI。
class ReadAloudEngineException implements Exception {
  ReadAloudEngineException(
    this.message, {
    this.cause,
    this.code = ReadAloudErrorCode.playbackFailed,
  });

  final String message;
  final Object? cause;
  final ReadAloudErrorCode code;

  @override
  String toString() =>
      'ReadAloudEngineException: $message${cause == null ? '' : ' ($cause)'}';
}

/// 底层语音合成引擎（TTS backend）抽象。
///
/// 这是项目里唯一允许直接触碰 `flutter_tts` 的地方。页面与 Provider 一律不
/// 得直接操作底层插件；所有播放请求都必须经过全局 Authority。
///
/// 引擎只负责“把一段文本念出来，并报告开始/完成/失败”。队列、分段、换段、
/// 暂停语义、迟到回调隔离都由 Authority 负责。
abstract class ReadAloudEngine {
  /// 当前平台/后端的真实能力。必须在 [initialize] 前后都可读。
  ReadAloudCapability get capability;

  /// 是否已完成初始化。
  bool get isInitialized;

  /// 绑定回调并完成一次性配置。不可用时应静默降级为 unsupported，不得抛出。
  Future<void> initialize();

  /// 应用朗读参数。不可用时必须是安全的空操作。
  Future<void> configure({
    double? rate,
    double? pitch,
    double? volume,
    String? language,
  });

  /// 系统语音后端真实可用的语言列表（归一化 BCP-47 tag）。
  ///
  /// 必须来自系统真实能力，**不得**因为代码里写了 `zh/ja/ko` 就报告可用。
  /// 返回空列表表示“无法枚举”（后端不支持查询或平台不可用），调用方不得据此
  /// 断定某个语言一定不支持。实现必须安全收敛 [MissingPluginException] /
  /// [PlatformException]，不得因查询失败而崩溃。
  Future<List<String>> availableLanguages();

  /// 朗读一段文本。会在朗读前打断当前 utterance（平台 QUEUE_FLUSH 语义下
  /// 新的 speak 可能被忽略，因此必须显式 stop）。
  ///
  /// 未初始化或后端不可用时抛出 [ReadAloudEngineException]。
  Future<void> speak(String text);

  /// 立即停止当前朗读（不触发 completion）。
  Future<void> stop();

  /// 暂停。返回 true 表示平台确实已暂停；返回 false 表示未生效，
  /// 调用方必须使用显式回退而不是假装成功。
  Future<bool> pause();

  /// 继续播放。返回 true 表示平台已继续；false 表示未生效。
  Future<bool> resume();

  /// 一段 utterance 自然播放结束。
  set onComplete(void Function()? handler);

  /// 一段 utterance 开始播放。
  set onStart(void Function()? handler);

  /// 一段 utterance 被中断（非自然结束）。引擎必须过滤掉自身打断产生的
  /// cancel，只上报真正的意外中断（例如系统抢占音频焦点）。
  set onCancel(void Function()? handler);

  /// 平台错误。
  set onError(void Function(Object error)? handler);

  void dispose();
}
