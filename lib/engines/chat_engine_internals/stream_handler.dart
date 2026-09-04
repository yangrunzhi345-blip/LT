import 'dart:async';
import 'package:flutter/foundation.dart';

/// v2.13.1: 打字机流式控制器 — 客户端缓冲区 + 自适应速率逐字吐出。
///
/// 替代旧版 StreamHandler（80ms debounce 一次性抛出大块文本），
/// 通过周期性 Timer 将 LLM 到达的文本逐批发送到 UI，实现平滑的打字机效果。
///
/// 速率自适应：
///   - 正常（缓冲 <100字）: 2字符/tick ≈ 67字/秒
///   - 加速（缓冲 100-300字）: 4字符/tick ≈ 133字/秒
///   - 追赶（缓冲 >300字）: 8字符/tick ≈ 267字/秒
///   - 收尾（流已结束）: 3字符/tick ≈ 100字/秒
class TypewriterController {
  /// 基础 tick 间隔（毫秒）
  static const tickMs = 30;

  /// 正常速率：每 tick 输出字符数
  static const normalCharsPerTick = 2;

  /// 加速速率
  static const fastCharsPerTick = 4;

  /// 追赶速率
  static const catchUpCharsPerTick = 8;

  /// 收尾速率（流结束后的清空速率）
  static const tailCharsPerTick = 3;

  /// 缓冲区超过此值触发加速
  static const bufferFastThreshold = 100;

  /// 缓冲区超过此值触发追赶
  static const bufferCatchUpThreshold = 300;

  /// 首次输出前的微延迟（毫秒），让用户感知"AI 在思考"
  static const initialDelayMs = 150;

  // ─── 状态 ───

  Timer? _tickTimer;
  Timer? _initialDelayTimer;
  String _buffer = '';
  int _cursor = 0;
  bool _streamEnded = false;
  bool _initialDelayDone = false;
  Completer<void>? _drainCompleter;

  // ─── 公开 API ───

  /// 流式期间调用：接收累积的完整文本。
  /// [fullText] 是 LLM 到当前为止输出的全部文本（每次 SSE chunk 到达时递增）。
  void feed(
    String fullText,
    ValueNotifier<String> notifier,
    VoidCallback notifyParent,
  ) {
    _buffer = fullText;

    if (!_initialDelayDone) {
      _initialDelayTimer ??= Timer(
        const Duration(milliseconds: initialDelayMs),
        () {
          _initialDelayTimer = null;
          _initialDelayDone = true;
          _startTicking(notifier, notifyParent);
        },
      );
      return;
    }
    if (_tickTimer == null) {
      _startTicking(notifier, notifyParent);
    }
  }

  /// 流结束时调用：标记流结束，继续 tick 直到缓冲区清空。
  /// 返回 Future，在全部文本显示完毕时完成。
  Future<void> onStreamEnd(
    ValueNotifier<String> notifier,
    VoidCallback notifyParent,
  ) {
    _streamEnded = true;
    if (_drainCompleter != null) return _drainCompleter!.future;
    _drainCompleter = Completer<void>();
    _initialDelayTimer?.cancel();
    _initialDelayTimer = null;
    _initialDelayDone = true;
    if (_cursor >= _buffer.length) {
      _finishDrain();
      return Future<void>.value();
    }
    if (_tickTimer == null) {
      _startTicking(notifier, notifyParent);
    }
    return _drainCompleter!.future;
  }

  /// 取消所有定时器并重置状态。
  void cancel() {
    _initialDelayTimer?.cancel();
    _initialDelayTimer = null;
    _tickTimer?.cancel();
    _tickTimer = null;
    _cursor = 0;
    _buffer = '';
    _streamEnded = false;
    _initialDelayDone = false;
    if (_drainCompleter?.isCompleted == false) {
      _drainCompleter!.complete();
    }
    _drainCompleter = null;
  }

  // ─── 内部 ───

  void _startTicking(
    ValueNotifier<String> notifier,
    VoidCallback notifyParent,
  ) {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(milliseconds: tickMs), (_) {
      _tick(notifier, notifyParent);
    });
  }

  void _tick(
    ValueNotifier<String> notifier,
    VoidCallback notifyParent,
  ) {
    final remaining = _buffer.length - _cursor;
    if (remaining <= 0) {
      if (_streamEnded) {
        _finishDrain();
      }
      return;
    }

    // 自适应速率
    int charsPerTick = normalCharsPerTick;
    if (remaining > bufferCatchUpThreshold) {
      charsPerTick = catchUpCharsPerTick;
    } else if (remaining > bufferFastThreshold) {
      charsPerTick = fastCharsPerTick;
    } else if (_streamEnded) {
      charsPerTick = tailCharsPerTick;
    }

    _cursor = (_cursor + charsPerTick).clamp(0, _buffer.length);
    notifier.value = _buffer.substring(0, _cursor);
    notifyParent();

    // 流结束后，清空缓冲区则停止
    if (_streamEnded && _cursor >= _buffer.length) {
      _finishDrain();
    }
  }

  void _finishDrain() {
    _tickTimer?.cancel();
    _tickTimer = null;
    if (_drainCompleter?.isCompleted == false) {
      _drainCompleter!.complete();
    }
    _drainCompleter = null;
  }
}
