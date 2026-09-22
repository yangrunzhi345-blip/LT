import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:flutter_tts/flutter_tts.dart';

import '../../domain/read_aloud/read_aloud_contracts.dart';
import 'language_tag.dart';
import 'read_aloud_engine.dart';

/// 朗读后端平台事实。
///
/// 这里不是“pubspec 里有 flutter_tts 就假设可用”，而是按插件真正声明的平台
/// 能力判断。`flutter_tts 4.2.5` 的 `pubspec.yaml` 声明 android / ios /
/// macos / windows / web；仓库的 `linux/flutter/generated_plugin_registrant.cc`
/// 也只注册了 `flutter_secure_storage_linux`。因此 Linux 桌面端不存在系统语音
/// 合成后端，必须显式报告不可用，而不是在运行期抛 MissingPluginException。
///
/// Web 不能由 [defaultTargetPlatform] 判定：Linux 浏览器会报告
/// [TargetPlatform.linux]，但 flutter_tts 已注册 Web 后端。
class ReadAloudPlatform {
  const ReadAloudPlatform._();

  static const String unsupportedReasonCode = 'unsupported_platform';
  static const String pluginUnavailableReasonCode = 'plugin_unavailable';

  static TargetPlatform get platform => defaultTargetPlatform;

  /// 当前平台是否存在系统语音合成后端。
  static bool get hasSystemTtsBackend {
    if (kIsWeb) return true;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return true;
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  /// 插件在全部受支持平台都暴露了 `pause`/continue 语义（Windows 的 continue
  /// 通过重新 speak 实现，由引擎统一处理）。
  static bool get supportsPause => hasSystemTtsBackend;

  static String get platformLabel {
    if (kIsWeb) return 'Web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.iOS:
        return 'iOS';
      case TargetPlatform.macOS:
        return 'macOS';
      case TargetPlatform.windows:
        return 'Windows';
      case TargetPlatform.linux:
        return 'Linux';
      case TargetPlatform.fuchsia:
        return 'Fuchsia';
    }
  }

  static String get unsupportedMessage => '$platformLabel 未提供系统语音合成后端，朗读功能不可用。';
}

/// 创建一个符合当前平台的默认引擎。
///
/// [tts] 仅用于测试注入；生产环境始终使用插件默认实现。
ReadAloudEngine createDefaultReadAloudEngine({FlutterTts? tts}) {
  if (!ReadAloudPlatform.hasSystemTtsBackend) {
    return UnsupportedReadAloudEngine(
      reasonCode: ReadAloudPlatform.unsupportedReasonCode,
      message: ReadAloudPlatform.unsupportedMessage,
    );
  }
  return FlutterTtsEngine(tts: tts);
}

/// 真实 `flutter_tts` 引擎。
class FlutterTtsEngine implements ReadAloudEngine {
  FlutterTtsEngine({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;

  ReadAloudCapability _capability =
      const ReadAloudCapability.available(supportsPause: true);
  bool _initialized = false;
  bool _handlersBound = false;

  double _rate = 0.5;
  double _pitch = 1.0;
  double _volume = 0.9;

  /// 当前（最近一次交给平台的）文本，用于在不支持原生 resume 的平台上重播。
  String? _currentUtterance;
  bool _speaking = false;

  /// 引擎自身为“打断上一条”而调用 stop 时置位，用于吞掉随之而来的 cancel，
  /// 避免 Authority 把自身打断误判为意外中断。
  bool _suppressNextCancel = false;

  void Function()? _onComplete;
  void Function()? _onStart;
  void Function()? _onCancel;
  void Function(Object error)? _onError;

  @override
  ReadAloudCapability get capability => _capability;

  @override
  bool get isInitialized => _initialized;

  @override
  set onComplete(void Function()? handler) => _onComplete = handler;

  @override
  set onStart(void Function()? handler) => _onStart = handler;

  @override
  set onCancel(void Function()? handler) => _onCancel = handler;

  @override
  set onError(void Function(Object error)? handler) => _onError = handler;

  @override
  Future<void> initialize() async {
    if (_initialized || !_capability.supported) return;
    _bindHandlers();
    try {
      // 不在这里写死任何语言：朗读语言由全局 Authority 在每段朗读前通过
      // [configure] 解析并应用，避免“初始化即固定 zh-CN”的多语言障碍。
      await _tts.setSpeechRate(_rate);
      await _tts.setPitch(_pitch);
      await _tts.setVolume(_volume);
      _initialized = true;
    } on MissingPluginException catch (error) {
      _markUnavailable(
        ReadAloudPlatform.pluginUnavailableReasonCode,
        '当前平台未注册系统语音合成插件，朗读不可用。',
        error,
      );
    } on PlatformException catch (error) {
      _markUnavailable(
        ReadAloudPlatform.pluginUnavailableReasonCode,
        '系统语音合成插件不可用：${error.message ?? error.code}',
        error,
      );
    } catch (error) {
      _markUnavailable('engine_init_failed', '语音合成初始化失败。', error);
    }
  }

  @override
  Future<List<String>> availableLanguages() async {
    if (!_capability.supported) return const <String>[];
    try {
      final raw = await _tts.getLanguages;
      if (raw is! Iterable) return const <String>[];
      final normalized = <String>{};
      for (final item in raw) {
        final tag = normalizeBcp47(item?.toString());
        if (tag.isNotEmpty) normalized.add(tag);
      }
      return normalized.toList(growable: false)..sort();
    } on MissingPluginException {
      // 后端不提供语言枚举：返回空集合（“能力未知”），不阻塞朗读。
      return const <String>[];
    } on PlatformException {
      return const <String>[];
    } catch (_) {
      return const <String>[];
    }
  }

  @override
  Future<void> configure({
    double? rate,
    double? pitch,
    double? volume,
    String? language,
  }) async {
    if (!_capability.supported) return;
    if (rate != null) {
      _rate = rate.clamp(0.0, 1.0);
      await _tts.setSpeechRate(_rate);
    }
    if (pitch != null) {
      _pitch = pitch.clamp(0.5, 2.0);
      await _tts.setPitch(_pitch);
    }
    if (volume != null) {
      _volume = volume.clamp(0.0, 1.0);
      await _tts.setVolume(_volume);
    }
    if (language != null && language.isNotEmpty) {
      await _tts.setLanguage(language);
    }
  }

  @override
  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    if (!_capability.supported) {
      throw ReadAloudEngineException(_capability.message ?? '朗读不可用');
    }
    if (!_initialized) await initialize();
    if (!_capability.supported) {
      throw ReadAloudEngineException(_capability.message ?? '朗读不可用');
    }
    // Android 默认 QUEUE_FLUSH：正在朗读时新的 speak 会被静默忽略，
    // 因此必须先显式 stop，保证“新朗读替换旧朗读”。
    if (_speaking) {
      _suppressNextCancel = true;
      await _tts.stop();
    }
    _currentUtterance = text;
    _speaking = true;
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    if (!_capability.supported) return;
    // 主动停止：后续 cancel 由 Authority 通过 run token 过滤。
    _speaking = false;
    _currentUtterance = null;
    try {
      await _tts.stop();
    } on MissingPluginException {
      // 后端消失时不阻塞 UI；能力状态已在 initialize 中记录。
    }
  }

  @override
  Future<bool> pause() async {
    if (!_capability.supported || !_capability.supportsPause) return false;
    try {
      final result = await _tts.pause();
      return result == 1 || result == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> resume() async {
    if (!_capability.supported || !_capability.supportsPause) return false;
    final text = _currentUtterance;
    if (text == null || text.isEmpty) return false;
    try {
      // flutter_tts 没有暴露 continueSpeaking；Android 与 Windows 在暂停后
      // 用相同文本重新 speak 即从断点继续。
      await _tts.speak(text);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    if (!_capability.supported) return;
    _suppressNextCancel = true;
    // dispose 时无 UI 可更新，平台通道异常按既有约定吞掉。
    _tts.stop().catchError((_) {});
    _onComplete = null;
    _onStart = null;
    _onCancel = null;
    _onError = null;
  }

  void _bindHandlers() {
    if (_handlersBound) return;
    _handlersBound = true;
    _tts.setStartHandler(_handleStart);
    _tts.setCompletionHandler(_handleComplete);
    _tts.setCancelHandler(_handleCancel);
    _tts.setPauseHandler(() {});
    _tts.setContinueHandler(() {});
    _tts.setErrorHandler(
      (message) => _onError?.call(
        ReadAloudEngineException('语音合成错误：$message'),
      ),
    );
  }

  void _handleStart() {
    _speaking = true;
    _suppressNextCancel = false;
    _onStart?.call();
  }

  void _handleComplete() {
    _speaking = false;
    _onComplete?.call();
  }

  void _handleCancel() {
    if (_suppressNextCancel) {
      _suppressNextCancel = false;
      return;
    }
    _speaking = false;
    _onCancel?.call();
  }

  void _markUnavailable(String reasonCode, String message, Object cause) {
    _capability = ReadAloudCapability.unavailable(
      reasonCode: reasonCode,
      message: message,
    );
    _initialized = false;
    _onError?.call(ReadAloudEngineException(message, cause: cause));
  }
}

/// 平台不支持朗读时的占位引擎。
///
/// 它不会崩溃，也不会伪装成功：[speak] 明确抛出 [ReadAloudEngineException]，
/// 能力状态如实标记为 unavailable，UI 据此禁用入口并提示原因。
class UnsupportedReadAloudEngine implements ReadAloudEngine {
  UnsupportedReadAloudEngine({
    required String reasonCode,
    required String message,
  }) : capability = ReadAloudCapability.unavailable(
          reasonCode: reasonCode,
          message: message,
        );

  @override
  final ReadAloudCapability capability;

  @override
  bool get isInitialized => true;

  @override
  set onComplete(void Function()? handler) {}

  @override
  set onStart(void Function()? handler) {}

  @override
  set onCancel(void Function()? handler) {}

  @override
  set onError(void Function(Object error)? handler) {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> configure({
    double? rate,
    double? pitch,
    double? volume,
    String? language,
  }) async {}

  @override
  Future<List<String>> availableLanguages() async => const <String>[];

  @override
  Future<void> speak(String text) async {
    throw ReadAloudEngineException(capability.message ?? '朗读不可用');
  }

  @override
  Future<void> stop() async {}

  @override
  Future<bool> pause() async => false;

  @override
  Future<bool> resume() async => false;

  @override
  void dispose() {}
}
