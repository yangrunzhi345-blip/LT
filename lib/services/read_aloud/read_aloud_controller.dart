import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/read_aloud/read_aloud_contracts.dart';
import 'playback_queue.dart';
import 'read_aloud_engine.dart';
import 'read_aloud_settings_store.dart';
import 'text_segmenter.dart';
import 'text_sanitizer.dart';

/// 全局朗读 Authority。
///
/// 整个应用在任何时刻都只允许存在一个朗读会话，并且只能由本类持有播放权：
/// 页面、Widget、Provider 都不得自行维护“正在播放”的伪状态，也不得直接
/// 触碰 [ReadAloudEngine]。
///
/// 并发与生命周期保证：
/// - 单调递增的 run token 隔离迟到的 completion/cancel/error 回调；
/// - 新朗读替换旧朗读前一定先打断旧 utterance；
/// - stop/pause/resume/next/previous 与状态机严格一致；
/// - 平台不支持 pause/resume 时使用显式回退，绝不伪造 paused；
/// - 页面退出可调用 [stopIfActive] 确保不留下失控朗读任务。
class ReadAloudController extends ChangeNotifier {
  ReadAloudController({
    required ReadAloudEngine engine,
    ReadAloudSettingsStore? store,
    TextSanitizer sanitizer = const TextSanitizer(),
    TextSegmenter segmenter = const TextSegmenter(),
    ReadAloudPreferences initialPreferences = ReadAloudPreferences.defaults,
  })  : _engine = engine,
        _store = store,
        _sanitizer = sanitizer,
        _segmenter = segmenter,
        _state = ReadAloudState(
          preferences: initialPreferences,
          capability: engine.capability,
        ) {
    _engine.onComplete = _handleEngineComplete;
    _engine.onCancel = _handleEngineCancel;
    _engine.onError = _handleEngineError;
  }

  final ReadAloudEngine _engine;
  final ReadAloudSettingsStore? _store;
  final TextSanitizer _sanitizer;
  final TextSegmenter _segmenter;

  ReadAloudState _state;

  bool _disposed = false;
  Future<void>? _initFuture;

  int _run = 0;

  /// 当前正在等待 completion 的 run；为 null 表示没有“在途 utterance”。
  int? _activeRun;

  PlaybackQueue _queue = PlaybackQueue.empty;
  int _index = 0;

  ReadAloudState get state => _state;

  ReadAloudCapability get capability => _state.capability;
  bool get enabled => _state.enabled;
  bool get autoRead => _state.autoRead;
  double get rate => _state.rate;
  double get pitch => _state.pitch;
  double get volume => _state.volume;

  bool get isSupported => _state.capability.supported;

  /// 初始化引擎（幂等、并发安全）。不读取偏好：偏好由 [restore] 从
  /// `SettingsProvider` 已加载的 settings 推入，避免启动期重复读数据库。
  Future<void> init() {
    final active = _initFuture;
    if (active != null) return active;
    late final Future<void> future;
    future = _initialize().whenComplete(() {
      if (identical(_initFuture, future)) _initFuture = null;
    });
    _initFuture = future;
    return future;
  }

  Future<void> _initialize() async {
    await _engine.initialize();
    if (_disposed) return;
    await _applyEngineParameters();
    if (_disposed) return;
    _emit(capability: _engine.capability);
  }

  /// 恢复持久化的朗读偏好。
  ///
  /// 同步、无副作用：只更新内存状态并通知监听者。**不**在这里做引擎/平台调用
  /// —— 本方法在 `SettingsProvider` 的启动加载路径上调用，任何平台往返都会
  /// 拖慢设置加载并改变既有启动时序。引擎参数由 [init] 或已初始化时的
  /// 异步应用补齐。
  void restore(ReadAloudPreferences preferences) {
    if (_disposed) return;
    _emit(preferences: preferences, errorMessage: null);
    if (_engine.isInitialized) {
      unawaited(_applyEngineParameters());
    }
  }

  // ─────────────────────────── 播放控制 ───────────────────────────

  /// 开始朗读一组来源。[sessionId] 是会话级来源 id（消息 id / 资源 id），
  /// 每个 [ReadAloudSource.id] 是段级 id（Part id 等）。
  Future<void> play({
    required String sessionId,
    required ReadAloudSourceType sourceType,
    required List<ReadAloudSource> sources,
  }) async {
    if (_disposed) return;
    if (!_state.capability.supported) {
      // 平台不支持：明确进入 error 并给出原因，不静默假装成功。
      _run++;
      _activeRun = null;
      _queue = PlaybackQueue.empty;
      _index = 0;
      _emit(
        status: ReadAloudStatus.error,
        sourceId: sessionId,
        sourceType: sourceType,
        currentChunkId: null,
        currentLabel: null,
        currentText: '',
        segmentIndex: -1,
        segmentCount: 0,
        errorMessage: _state.capability.message ?? '朗读不可用',
        runId: _run,
      );
      return;
    }
    if (!_state.enabled) {
      // 朗读总开关关闭：遵循既有语义，手动与自动朗读都不触发。
      return;
    }

    final queue = PlaybackQueue.build(
      sources: sources,
      sanitizer: _sanitizer,
      segmenter: _segmenter,
    );
    if (queue.isEmpty) {
      // 没有可朗读的可见正文：结束旧会话而不是留下一个空会话。
      await stop();
      return;
    }

    final run = ++_run;
    _activeRun = null;
    _queue = queue;
    _index = 0;
    final first = queue.chunkAt(0);
    _emit(
      status: ReadAloudStatus.preparing,
      sourceId: sessionId,
      sourceType: sourceType,
      currentChunkId: first.sourceId,
      currentLabel: first.label,
      currentText: first.text,
      segmentIndex: 0,
      segmentCount: queue.length,
      errorMessage: null,
      runId: run,
    );
    await _applyEngineParameters();
    if (run != _run || _disposed) return;
    await _speakCurrent(run);
  }

  /// 便捷入口：朗读单段正文。
  Future<void> playText(
    String text, {
    required String sourceId,
    ReadAloudSourceType sourceType = ReadAloudSourceType.generic,
    String? label,
    String? chunkId,
  }) {
    return play(
      sessionId: sourceId,
      sourceType: sourceType,
      sources: <ReadAloudSource>[
        ReadAloudSource(id: chunkId ?? sourceId, text: text, label: label),
      ],
    );
  }

  /// 若 [sessionId] 正在朗读则停止，否则开始朗读。
  Future<void> toggle({
    required String sessionId,
    required ReadAloudSourceType sourceType,
    required List<ReadAloudSource> sources,
  }) {
    if (_state.isActiveSource(sessionId)) return stop();
    return play(sessionId: sessionId, sourceType: sourceType, sources: sources);
  }

  /// 显式停止并清空会话。迟到的 completion 会因 run 失配被丢弃。
  Future<void> stop() async {
    final wasActive = _state.hasActiveSession;
    _run++;
    _activeRun = null;
    _queue = PlaybackQueue.empty;
    _index = 0;
    await _safeEngineStop();
    if (_disposed) return;
    _emit(
      status: wasActive ? ReadAloudStatus.stopped : ReadAloudStatus.idle,
      sourceId: null,
      sourceType: null,
      currentChunkId: null,
      currentLabel: null,
      currentText: '',
      segmentIndex: -1,
      segmentCount: 0,
      errorMessage: null,
    );
  }

  /// 仅当 [sessionId] 正是当前朗读会话时停止。页面 dispose 使用，
  /// 避免误停其它页面正在进行的朗读。
  Future<void> stopIfActive(String sessionId) async {
    if (!_state.hasActiveSession || _state.sourceId != sessionId) return;
    await stop();
  }

  /// 暂停。平台不支持或未生效时显式回退为“停止音频但保留当前段位置”。
  Future<void> pause() async {
    if (_state.status != ReadAloudStatus.playing) return;
    final run = _run;
    if (_state.capability.supportsPause) {
      final ok = await _engine.pause();
      if (_disposed || run != _run) return;
      if (ok) {
        _emit(status: ReadAloudStatus.paused, errorMessage: null);
        return;
      }
    }
    await _safeEngineStop();
    if (_disposed || run != _run) return;
    _activeRun = null;
    _emit(status: ReadAloudStatus.paused, errorMessage: null);
  }

  /// 继续。平台原生 resume 不可用时回退为从当前段开头重播。
  Future<void> resume() async {
    if (_state.status != ReadAloudStatus.paused) return;
    final run = _run;
    if (_state.capability.supportsPause) {
      final ok = await _engine.resume();
      if (_disposed || run != _run) return;
      if (ok) {
        _emit(status: ReadAloudStatus.playing, errorMessage: null);
        return;
      }
    }
    await _speakCurrent(run);
  }

  /// 下一段。已在最后一段时明确结束本次朗读。
  Future<void> next() async {
    if (!_state.hasActiveSession || _queue.isEmpty) return;
    final run = _run;
    if (_index + 1 >= _queue.length) {
      _activeRun = null;
      await _safeEngineStop();
      if (_disposed || run != _run) return;
      _complete(run);
      return;
    }
    _index++;
    await _speakCurrent(run);
  }

  /// 上一段。已在第一段时重播当前段（越界收敛到合法位置）。
  Future<void> previous() async {
    if (!_state.hasActiveSession || _queue.isEmpty) return;
    final run = _run;
    if (_index > 0) _index--;
    await _speakCurrent(run);
  }

  /// 重播当前段。
  Future<void> replayCurrent() async {
    if (!_state.hasActiveSession || _queue.isEmpty) return;
    await _speakCurrent(_run);
  }

  // ─────────────────────────── 偏好 ───────────────────────────

  Future<void> setEnabled(bool value) async {
    if (_state.enabled == value) return;
    _emit(preferences: _state.preferences.copyWith(enabled: value));
    if (!value) {
      if (_state.hasActiveSession) await stop();
    } else {
      await _engine.initialize();
      if (_disposed) return;
      _emit(capability: _engine.capability);
      await _applyEngineParameters();
    }
    await _persist();
  }

  Future<void> setAutoRead(bool value) async {
    if (_state.autoRead == value) return;
    _emit(preferences: _state.preferences.copyWith(autoRead: value));
    await _persist();
  }

  Future<void> setRate(double value) async {
    final normalized = value.clamp(0.0, 1.0);
    if (_state.rate == normalized) return;
    _emit(preferences: _state.preferences.copyWith(rate: normalized));
    await _applyEngineParameters();
    await _persist();
  }

  Future<void> setPitch(double value) async {
    final normalized = value.clamp(0.5, 2.0);
    if (_state.pitch == normalized) return;
    _emit(preferences: _state.preferences.copyWith(pitch: normalized));
    await _applyEngineParameters();
    await _persist();
  }

  Future<void> setVolume(double value) async {
    final normalized = value.clamp(0.0, 1.0);
    if (_state.volume == normalized) return;
    _emit(preferences: _state.preferences.copyWith(volume: normalized));
    await _applyEngineParameters();
    await _persist();
  }

  // ─────────────────────────── 内部实现 ───────────────────────────

  Future<void> _safeEngineStop() async {
    try {
      await _engine.stop();
    } catch (error) {
      // 停止失败不应该让 UI 卡在“播放中”：记录并继续收敛状态。
      debugPrint('[ReadAloud] 停止引擎失败: $error');
    }
  }

  Future<void> _applyEngineParameters() async {
    if (!_engine.capability.supported) return;
    // 未初始化前不触碰平台通道；参数会在 init() 完成后统一应用。
    if (!_engine.isInitialized) return;
    try {
      await _engine.configure(
        rate: _state.rate,
        pitch: _state.pitch,
        volume: _state.volume,
      );
    } catch (error) {
      // 参数配置失败不是播放状态错误：真正的失败会在 speak 时暴露。
      debugPrint('[ReadAloud] 参数应用失败: $error');
    }
  }

  Future<void> _persist() async {
    final store = _store;
    if (store == null) return;
    try {
      await store.save(_state.preferences);
    } catch (error) {
      debugPrint('[ReadAloud] 偏好写入失败: $error');
    }
  }

  Future<void> _speakCurrent(int run) async {
    if (_disposed || run != _run) return;
    if (_index < 0 || _index >= _queue.length) {
      _complete(run);
      return;
    }
    final chunk = _queue.chunkAt(_index);
    // 在打断旧 utterance 之前先放弃它的 completion，这样即便某个平台在
    // stop 时错误地发出完成回调，也不会推进队列。
    _activeRun = null;
    _emit(
      status: ReadAloudStatus.playing,
      segmentIndex: _index,
      segmentCount: _queue.length,
      currentChunkId: chunk.sourceId,
      currentLabel: chunk.label,
      currentText: chunk.text,
      errorMessage: null,
    );
    try {
      await _engine.speak(chunk.text);
    } catch (error) {
      if (_disposed || run != _run) return;
      _fail(error);
      return;
    }
    if (_disposed || run != _run) return;
    _activeRun = run;
  }

  void _handleEngineComplete() {
    if (_disposed) return;
    final run = _activeRun;
    if (run == null || run != _run) return; // 迟到/已作废的回调
    _activeRun = null;
    if (_index + 1 >= _queue.length) {
      _complete(run);
      return;
    }
    _index++;
    unawaited(_speakCurrent(run));
  }

  void _handleEngineCancel() {
    if (_disposed) return;
    // 只有“没有在途 utterance 被主动放弃”的意外中断才改变状态；
    // 自身打断时 _activeRun 已被置空。
    if (_activeRun == null || _activeRun != _run) return;
    if (_state.status != ReadAloudStatus.playing) return;
    _activeRun = null;
    _emit(status: ReadAloudStatus.stopped, errorMessage: null);
  }

  void _handleEngineError(Object error) {
    if (_disposed) return;
    final capability = _engine.capability;
    if (!capability.supported) {
      _activeRun = null;
      _queue = PlaybackQueue.empty;
      _index = 0;
      _emit(
        status: ReadAloudStatus.error,
        capability: capability,
        errorMessage: capability.message ?? '朗读不可用',
      );
      return;
    }
    if (_activeRun == null || _activeRun != _run) return;
    _activeRun = null;
    _fail(error);
  }

  void _complete(int run) {
    if (run != _run || _disposed) return;
    _activeRun = null;
    final last = _queue.length - 1;
    _emit(
      status: ReadAloudStatus.completed,
      segmentIndex: last >= 0 ? last : -1,
      segmentCount: _queue.length,
      errorMessage: null,
    );
  }

  void _fail(Object error) {
    _activeRun = null;
    _emit(
      status: ReadAloudStatus.error,
      errorMessage:
          error is ReadAloudEngineException ? error.message : error.toString(),
    );
  }

  void _emit({
    ReadAloudStatus? status,
    Object? sourceId = ReadAloudState.unset,
    Object? sourceType = ReadAloudState.unset,
    Object? currentChunkId = ReadAloudState.unset,
    Object? currentLabel = ReadAloudState.unset,
    String? currentText,
    int? segmentIndex,
    int? segmentCount,
    ReadAloudPreferences? preferences,
    ReadAloudCapability? capability,
    Object? errorMessage = ReadAloudState.unset,
    int? runId,
  }) {
    if (_disposed) return;
    _state = _state.copyWith(
      status: status,
      sourceId: sourceId,
      sourceType: sourceType,
      currentChunkId: currentChunkId,
      currentLabel: currentLabel,
      currentText: currentText,
      segmentIndex: segmentIndex,
      segmentCount: segmentCount,
      preferences: preferences,
      capability: capability,
      errorMessage: errorMessage,
      runId: runId,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _run++;
    _activeRun = null;
    _queue = PlaybackQueue.empty;
    _engine.onComplete = null;
    _engine.onStart = null;
    _engine.onCancel = null;
    _engine.onError = null;
    _engine.dispose();
    super.dispose();
  }
}
