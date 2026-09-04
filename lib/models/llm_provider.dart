/// LLM 提供商枚举与静态目录。
///
/// 放在 models 层以便 UI 与领域模型按「类型面 import」使用，
/// `lib/services/llm_service.dart` re-export 本文件保持旧 import 兼容。
enum LLMProvider {
  deepseek,
  qwen,
  zhipu,
  kimi,
  doubao,
  baidu,
  minimax,
  xunfei,
  openai,
  anthropic,
  gemini,
  ollama,
  custom;

  /// 云端提供商（不含 Ollama 本地 / Custom 自定义）
  static const List<LLMProvider> cloudProviders = [
    LLMProvider.deepseek,
    LLMProvider.qwen,
    LLMProvider.zhipu,
    LLMProvider.kimi,
    LLMProvider.doubao,
    LLMProvider.baidu,
    LLMProvider.minimax,
    LLMProvider.xunfei,
    LLMProvider.openai,
    LLMProvider.anthropic,
    LLMProvider.gemini,
  ];

  static const List<LLMProvider> domesticProviders = [
    LLMProvider.deepseek,
    LLMProvider.qwen,
    LLMProvider.zhipu,
    LLMProvider.kimi,
    LLMProvider.doubao,
    LLMProvider.baidu,
    LLMProvider.minimax,
    LLMProvider.xunfei,
  ];

  static const List<LLMProvider> overseasProviders = [
    LLMProvider.openai,
    LLMProvider.anthropic,
    LLMProvider.gemini,
  ];

  String get displayName => switch (this) {
        LLMProvider.deepseek => 'DeepSeek',
        LLMProvider.qwen => '通义千问',
        LLMProvider.zhipu => '智谱 GLM',
        LLMProvider.kimi => 'Kimi',
        LLMProvider.doubao => '豆包',
        LLMProvider.baidu => '百度文心',
        LLMProvider.minimax => 'MiniMax',
        LLMProvider.xunfei => '讯飞星火',
        LLMProvider.openai => 'OpenAI',
        LLMProvider.anthropic => 'Claude',
        LLMProvider.gemini => 'Gemini',
        LLMProvider.ollama => 'Ollama (本地)',
        LLMProvider.custom => '自定义',
      };

  String get defaultBaseUrl => switch (this) {
        LLMProvider.deepseek => 'https://api.deepseek.com',
        LLMProvider.qwen => 'https://dashscope.aliyuncs.com/compatible-mode/v1',
        LLMProvider.zhipu => 'https://open.bigmodel.cn/api/paas/v4',
        LLMProvider.kimi => 'https://api.moonshot.cn/v1',
        LLMProvider.doubao => 'https://ark.cn-beijing.volces.com/api/v3',
        LLMProvider.baidu => 'https://qianfan.baidubce.com/v2',
        LLMProvider.minimax => 'https://api.minimaxi.com/v1',
        LLMProvider.xunfei => 'https://spark-api-open.xf-yun.com/v1',
        LLMProvider.openai => 'https://api.openai.com/v1',
        LLMProvider.anthropic => 'https://api.anthropic.com/v1',
        LLMProvider.gemini =>
          'https://generativelanguage.googleapis.com/v1beta/openai',
        LLMProvider.ollama => 'http://localhost:11434/v1',
        LLMProvider.custom => '',
      };

  String get defaultModel => switch (this) {
        LLMProvider.deepseek => 'deepseek-v4-flash',
        LLMProvider.qwen => 'qwen-plus',
        LLMProvider.zhipu => 'glm-4.7-flash',
        LLMProvider.kimi => 'kimi-k2-0711-preview',
        LLMProvider.doubao => 'doubao-seed-1-6-250615',
        LLMProvider.baidu => 'ernie-4.5-turbo-128k',
        LLMProvider.minimax => 'MiniMax-M3',
        LLMProvider.xunfei => '4.0Ultra',
        LLMProvider.openai => 'gpt-4.1-mini',
        LLMProvider.anthropic => 'claude-sonnet-5',
        LLMProvider.gemini => 'gemini-3.5-flash',
        LLMProvider.ollama => 'qwen2.5:7b',
        LLMProvider.custom => '',
      };

  /// 各提供商可用模型列表（来源：官方文档 2026）
  List<String> get availableModels => switch (this) {
        LLMProvider.deepseek => [
            'deepseek-v4-flash', // 284B MoE, 推荐
            'deepseek-v4-pro', // 1.6T MoE, 最强
            'deepseek-r1-0528', // 推理专用
            'deepseek-chat', // 兼容旧版 (2026/07下线)
          ],
        LLMProvider.qwen => [
            'qwen-plus', // 均衡性价比, 推荐
            'qwen-max', // 最强效果
            'qwen-turbo', // 最快速度
            'qwen3-235b-a22b', // 思考模式 MoE
          ],
        LLMProvider.zhipu => [
            'glm-4.7-flash', // 免费混合思考, 推荐
            'glm-4.6', // 高性能基座
            'glm-4.5', // MoE 智能体基座
          ],
        LLMProvider.kimi => [
            'kimi-k2-0711-preview',
            'kimi-latest',
            'kimi-thinking-preview',
          ],
        LLMProvider.doubao => [
            'doubao-seed-1-6-250615',
            'doubao-seed-1-6-thinking-250615',
            'doubao-seed-1-6-flash-250715',
          ],
        LLMProvider.baidu => [
            'ernie-4.5-turbo-128k',
            'ernie-4.5-8k-preview',
            'ernie-x1-turbo-32k',
          ],
        LLMProvider.minimax => [
            'MiniMax-M3',
            'MiniMax-Text-01',
          ],
        LLMProvider.xunfei => [
            '4.0Ultra',
            'generalv3.5',
            'spark-x',
          ],
        LLMProvider.openai => [
            'gpt-4.1-mini',
            'gpt-4.1',
            'gpt-5-mini',
          ],
        LLMProvider.anthropic => [
            'claude-sonnet-5',
            'claude-haiku-4-5',
            'claude-opus-4-8',
          ],
        LLMProvider.gemini => [
            'gemini-3.5-flash',
            'gemini-3.5-pro',
            'gemini-2.5-flash',
          ],
        LLMProvider.ollama => [
            if (defaultModel.isNotEmpty) defaultModel,
          ],
        LLMProvider.custom => [],
      };

  bool get usesOpenAICompat => switch (this) {
        LLMProvider.deepseek ||
        LLMProvider.qwen ||
        LLMProvider.zhipu ||
        LLMProvider.kimi ||
        LLMProvider.doubao ||
        LLMProvider.baidu ||
        LLMProvider.minimax ||
        LLMProvider.xunfei ||
        LLMProvider.openai ||
        LLMProvider.gemini ||
        LLMProvider.ollama =>
          true,
        LLMProvider.custom => true,
        LLMProvider.anthropic => false,
      };

  bool get usesAnthropicMessagesApi => this == LLMProvider.anthropic;

  String get chatCompletionsPath => switch (this) {
        LLMProvider.anthropic => '/messages',
        _ => '/chat/completions',
      };

  String get modelsPath => switch (this) {
        _ => '/models',
      };
}
