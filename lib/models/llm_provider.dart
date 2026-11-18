import 'model_capabilities.dart';

/// LLM 提供商枚举与静态目录。
///
/// 放在 models 层以便 UI 与领域模型按「类型面 import」使用，
/// `lib/services/llm_service.dart` re-export 本文件保持旧 import 兼容。
/// LLM 提供商枚举与静态目录。
///
/// 内置 DeepSeek 与 Anthropic Messages 官方 API，以及 OpenAI 兼容自定义
/// 接口。具体模型 id、能力与兼容 alias 统一由 [ModelCapabilityRegistry]
/// 描述，避免在 enum 里散落字符串判断。
enum LLMProvider {
  deepseek,
  anthropic,
  custom;

  /// 云端提供商（官方支持的内置服务商）
  static const List<LLMProvider> cloudProviders = [
    LLMProvider.deepseek,
    LLMProvider.anthropic,
  ];

  String get displayName => switch (this) {
        LLMProvider.deepseek => 'DeepSeek 官方 API',
        LLMProvider.anthropic => 'Anthropic Claude',
        LLMProvider.custom => '自定义 (OpenAI 兼容)',
      };

  String get defaultBaseUrl => switch (this) {
        LLMProvider.deepseek => 'https://api.deepseek.com',
        LLMProvider.anthropic => 'https://api.anthropic.com',
        LLMProvider.custom => '',
      };

  String get defaultModel => switch (this) {
        LLMProvider.deepseek => ModelCapabilityRegistry.deepSeekFlash.modelId,
        LLMProvider.anthropic => ModelCapabilityRegistry.claudeSonnet.modelId,
        LLMProvider.custom => '',
      };

  /// 可供用户新选择的在服模型列表（不含 legacy/隐藏模型）。
  /// - deepseek-flash: DeepSeek V4.1 Flash，最新推荐 · 多模态 · 支持深度思考
  /// - claude-sonnet: Anthropic Messages API，多模态 · 长上下文
  List<String> get availableModels => switch (this) {
        LLMProvider.deepseek => ModelCapabilityRegistry.deepSeekPickerModels
            .map((caps) => caps.modelId)
            .toList(growable: false),
        LLMProvider.anthropic => ModelCapabilityRegistry.anthropicModels
            .map((caps) => caps.modelId)
            .toList(growable: false),
        LLMProvider.custom => [],
      };

  /// 全部内置模型 id，包含隐藏的 legacy 模型（如 deepseek-v4-pro）。
  /// 用于保留用户已保存的选择，而不是静默重置为默认模型。
  List<String> get knownModels => switch (this) {
        LLMProvider.deepseek => ModelCapabilityRegistry.deepSeekKnownModelIds,
        LLMProvider.anthropic => ModelCapabilityRegistry.anthropicModels
            .map((caps) => caps.modelId)
            .toList(growable: false),
        LLMProvider.custom => [],
      };

  /// Whether this provider speaks the Anthropic Messages protocol.
  ///
  /// Only the built-in Anthropic provider does; DeepSeek and custom endpoints
  /// stay on the OpenAI-compatible chat completions protocol.
  bool get usesAnthropicMessagesApi => this == LLMProvider.anthropic;

  /// Path appended to the provider base URL for streaming requests.
  ///
  /// Anthropic has its own Messages endpoint; every other provider uses the
  /// OpenAI-compatible chat completions route.
  String get chatCompletionsPath =>
      this == LLMProvider.anthropic ? '/v1/messages' : '/chat/completions';

  String get modelsPath =>
      this == LLMProvider.anthropic ? '/v1/models' : '/models';
}
