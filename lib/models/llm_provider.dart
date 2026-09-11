import 'model_capabilities.dart';

/// LLM 提供商枚举与静态目录。
///
/// 放在 models 层以便 UI 与领域模型按「类型面 import」使用，
/// `lib/services/llm_service.dart` re-export 本文件保持旧 import 兼容。
/// LLM 提供商枚举与静态目录。
///
/// 专精适配 DeepSeek 官方 API 与自定义兼容接口。具体模型 id、能力与
/// 兼容 alias 统一由 [ModelCapabilityRegistry] 描述，避免在 enum 里散落
/// 字符串判断。
enum LLMProvider {
  deepseek,
  custom;

  /// 云端提供商（仅包含官方支持的 DeepSeek）
  static const List<LLMProvider> cloudProviders = [
    LLMProvider.deepseek,
  ];

  static const List<LLMProvider> domesticProviders = [
    LLMProvider.deepseek,
  ];

  static const List<LLMProvider> overseasProviders = <LLMProvider>[];

  String get displayName => switch (this) {
        LLMProvider.deepseek => 'DeepSeek 官方 API',
        LLMProvider.custom => '自定义 (OpenAI 兼容)',
      };

  String get defaultBaseUrl => switch (this) {
        LLMProvider.deepseek => 'https://api.deepseek.com',
        LLMProvider.custom => '',
      };

  String get defaultModel => switch (this) {
        LLMProvider.deepseek => ModelCapabilityRegistry.deepSeekFlash.modelId,
        LLMProvider.custom => '',
      };

  /// 可供用户新选择的在服模型列表（不含 legacy/隐藏模型）。
  /// - deepseek-flash: DeepSeek V4.1 Flash，最新推荐 · 多模态 · 支持深度思考
  List<String> get availableModels => switch (this) {
        LLMProvider.deepseek => ModelCapabilityRegistry.pickerModels()
            .map((caps) => caps.modelId)
            .toList(growable: false),
        LLMProvider.custom => [],
      };

  /// 全部内置模型 id，包含隐藏的 legacy 模型（如 deepseek-v4-pro）。
  /// 用于保留用户已保存的选择，而不是静默重置为默认模型。
  List<String> get knownModels => switch (this) {
        LLMProvider.deepseek => ModelCapabilityRegistry.knownModelIds(),
        LLMProvider.custom => [],
      };

  bool get usesOpenAICompat => true;

  bool get usesAnthropicMessagesApi => false;

  String get chatCompletionsPath => '/chat/completions';

  String get modelsPath => '/models';
}
