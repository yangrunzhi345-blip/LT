import 'package:lt_dialogue/domain/read_aloud/read_aloud_contracts.dart';
import 'package:lt_dialogue/services/read_aloud/read_aloud_engine.dart';
import 'package:lt_dialogue/services/read_aloud/read_aloud_settings_store.dart';

/// 可控的朗读引擎替身。
///
/// 只记录调用并允许测试手动驱动 completion/cancel/error，因此并发与迟到回调
/// 场景完全确定，不依赖真实平台通道。
class FakeReadAloudEngine implements ReadAloudEngine {
  FakeReadAloudEngine({
    this.supported = true,
    this.supportsPause = true,
    this.pauseResult = true,
    this.resumeResult = true,
    this.speakError,
    this.initializeError,
  });

  bool supported;
  bool supportsPause;
  bool pauseResult;
  bool resumeResult;
  Object? speakError;
  Object? initializeError;

  /// 允许测试模拟“引擎尚未初始化”的启动阶段。
  bool initialized = true;

  final List<String> spokenTexts = <String>[];
  int initializeCount = 0;
  int configureCount = 0;
  int stopCount = 0;
  int pauseCount = 0;
  int resumeCount = 0;
  bool disposed = false;
  double? lastRate;
  double? lastPitch;
  double? lastVolume;

  void Function()? _onComplete;
  void Function()? _onStart;
  void Function()? _onCancel;
  void Function(Object error)? _onError;

  @override
  ReadAloudCapability get capability => supported
      ? ReadAloudCapability.available(supportsPause: supportsPause)
      : const ReadAloudCapability.unavailable(
          reasonCode: 'unsupported_platform',
          message: '测试：平台不支持朗读',
        );

  @override
  bool get isInitialized => initialized;

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
    initializeCount++;
    final error = initializeError;
    if (error != null) throw error;
    initialized = true;
  }

  @override
  Future<void> configure({
    double? rate,
    double? pitch,
    double? volume,
    String? language,
  }) async {
    configureCount++;
    if (rate != null) lastRate = rate;
    if (pitch != null) lastPitch = pitch;
    if (volume != null) lastVolume = volume;
  }

  @override
  Future<void> speak(String text) async {
    final error = speakError;
    if (error != null) throw error;
    spokenTexts.add(text);
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<bool> pause() async {
    pauseCount++;
    return pauseResult;
  }

  @override
  Future<bool> resume() async {
    resumeCount++;
    return resumeResult;
  }

  @override
  void dispose() {
    disposed = true;
  }

  // ─── 测试驱动 ───

  void emitStart() => _onStart?.call();
  void emitComplete() => _onComplete?.call();
  void emitCancel() => _onCancel?.call();
  void emitError(Object error) => _onError?.call(error);
}

/// 内存版偏好存储，验证“持久化”语义而不依赖 SQLite。
class InMemoryReadAloudSettingsStore implements ReadAloudSettingsStore {
  InMemoryReadAloudSettingsStore([
    this._preferences = ReadAloudPreferences.defaults,
  ]);

  ReadAloudPreferences _preferences;
  int saveCount = 0;
  bool failOnSave = false;

  ReadAloudPreferences get preferences => _preferences;

  @override
  Future<void> save(ReadAloudPreferences preferences) async {
    if (failOnSave) throw StateError('save failed');
    saveCount++;
    _preferences = preferences;
  }
}

/// 等待控制器内部的 unawaited microtask 收敛。
Future<void> settleReadAloud() => Future<void>.delayed(Duration.zero);
