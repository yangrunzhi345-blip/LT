import 'dart:async';

import '../domain/read_aloud/read_aloud_contracts.dart';
import '../models/completion_params.dart';
import 'llm_service.dart';
import 'read_aloud/read_aloud_controller.dart';
import 'read_aloud/text_sanitizer.dart';

/// 朗读兼容门面。
///
/// 全项目唯一的朗读 Authority 是 [ReadAloudController]（由
/// `SettingsProvider.readAloud` 持有）。本类只保留历史调用方（ChatEngineHost、
/// 聊天消息菜单、设置页）使用的旧 API 形状，并原样转发到该 Authority，
/// **不**持有自己的 `FlutterTts`，也不允许被新代码用来创建第二套朗读实现。
///
/// 未绑定控制器时（例如单元测试直接构造 `TtsService()`）只有纯函数式能力
/// 可用：[stripForSpeech] 与 `synthesizeWithLLM`。其余方法为安全空操作。
class TtsService {
  TtsService([this._controller]);

  final ReadAloudController? _controller;

  bool get enabled => _controller?.enabled ?? false;
  bool get autoRead => _controller?.autoRead ?? false;
  double get rate => _controller?.rate ?? 0.5;
  double get pitch => _controller?.pitch ?? 1.0;

  Future<void> init() async {
    await _controller?.init();
  }

  void setEnabled(bool value) {
    final controller = _controller;
    if (controller == null) return;
    unawaited(controller.setEnabled(value));
  }

  void setAutoRead(bool value) {
    final controller = _controller;
    if (controller == null) return;
    unawaited(controller.setAutoRead(value));
  }

  Future<void> setRate(double value) async {
    await _controller?.setRate(value);
  }

  Future<void> setPitch(double value) async {
    await _controller?.setPitch(value);
  }

  Future<void> speak(String text) async {
    final controller = _controller;
    if (controller == null) return;
    // 兼容入口没有来源上下文，使用固定会话 id；页面级朗读应改用
    // ReadAloudController.play / AppReadAloudButton 以携带真实来源。
    await controller.playText(
      text,
      sourceId: 'legacy-tts',
      sourceType: ReadAloudSourceType.chat,
    );
  }

  Future<void> stop() async {
    await _controller?.stop();
  }

  /// 清洗为可朗读的可见正文。转发到全局清洗器，保证只有一套清洗规则。
  String stripForSpeech(String text) => const TextSanitizer().sanitize(text);

  /// 使用 LLM 生成 TTS 朗读文本（适合云 TTS 场景）。
  ///
  /// 这是**可选**的兼容路径，不属于标准本地朗读流程：普通朗读不得依赖
  /// LLM/API，否则会引入费用、延迟与文本漂移。
  Future<String> synthesizeWithLLM({
    required LLMService llmService,
    required String text,
  }) async {
    try {
      final messages = [
        {
          'role': 'system',
          'content': '将文本转为自然、简洁的朗读稿，移除 Markdown、HTML 和 JSON 块。',
        },
        {'role': 'user', 'content': text},
      ];
      final result = await llmService.sendMessageStream(
        messages,
        (_) {},
        () {},
        // 朗读稿清洗是低延迟辅助任务：显式关闭思考。
        params: const CompletionParams(
          maxTokens: 1024,
          temperature: 0.2,
          enableThinking: false,
        ),
      );
      return result.isEmpty ? stripForSpeech(text) : result;
    } catch (_) {
      return stripForSpeech(text);
    }
  }

  /// 生命周期由 [SettingsProvider] 管理，这里不做任何释放。
  void dispose() {}
}
