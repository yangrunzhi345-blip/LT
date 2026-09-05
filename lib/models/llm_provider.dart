/// LLM 提供商枚举与静态目录。
///
/// 放在 models 层以便 UI 与领域模型按「类型面 import」使用，
/// `lib/services/llm_service.dart` re-export 本文件保持旧 import 兼容。
/// LLM 提供商枚举与静态目录。
///
/// 专精适配 DeepSeek 官方 API 与自定义兼容接口。
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
        LLMProvider.deepseek => 'deepseek-v4-flash',
        LLMProvider.custom => '',
      };

  /// DeepSeek 官方当前在服模型列表：
  /// - deepseek-v4-flash: 284B MoE 极速推理主力 (低延迟/高效叙事/角色扮演) [默认推荐]
  /// - deepseek-v4-pro: 1.6T MoE 旗舰全能长考 (多步逻辑推演/复杂任务/深度推理)
  List<String> get availableModels => switch (this) {
        LLMProvider.deepseek => [
            'deepseek-v4-flash',
            'deepseek-v4-pro',
          ],
        LLMProvider.custom => [],
      };

  bool get usesOpenAICompat => true;

  bool get usesAnthropicMessagesApi => false;

  String get chatCompletionsPath => '/chat/completions';

  String get modelsPath => '/models';
}
