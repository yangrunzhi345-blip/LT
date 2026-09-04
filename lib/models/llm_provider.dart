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

  /// DeepSeek 官方当前在服模型列表（参考 https://api-docs.deepseek.com/zh-cn/）
  /// 已下架的模型（如已下线的旧版别名 deepseek-chat、deepseek-reasoner）已彻底移除
  List<String> get availableModels => switch (this) {
        LLMProvider.deepseek => [
            'deepseek-v4-flash', // 284B MoE, 官方推荐主力极速模型，低延迟高性价比，支持深度思考
            'deepseek-v4-pro', // 1.6T MoE, 官方旗舰深度长考与逻辑推演模型，支持深度思考
            'deepseek-v4-flash-vision-exp', // 实验性多模态视觉模型，支持图文理解输入
          ],
        LLMProvider.custom => [],
      };

  bool get usesOpenAICompat => true;

  bool get usesAnthropicMessagesApi => false;

  String get chatCompletionsPath => '/chat/completions';

  String get modelsPath => '/models';
}
