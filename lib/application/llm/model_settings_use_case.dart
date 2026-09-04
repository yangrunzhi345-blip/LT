import '../../services/llm_service.dart';

/// 模型设置应用层用例 — 连接测试、端点规则与模型切换。
///
/// 端点规则:
/// - 内置官方模型固定使用官方端点，忽略用户输入的端点；
/// - 只有自定义模型允许使用自定义端点。
/// 页面不再自行构造 LLMConfig，也不再直接调用 LLMService.testConfiguration。
class ModelSettingsUseCase {
  final Future<bool> Function(LLMConfig config)? _configurationTester;

  const ModelSettingsUseCase(
      {Future<bool> Function(LLMConfig config)? configurationTester})
      : _configurationTester = configurationTester;

  /// 测试当前配置的连接（内置商固定官方端点，自定义使用自定义端点）。
  Future<bool> testConnection({
    required LLMProvider provider,
    required String apiKey,
    required String model,
    String? endpoint,
  }) async {
    final baseUrl = provider == LLMProvider.custom
        ? ((endpoint == null || endpoint.trim().isEmpty)
            ? provider.defaultBaseUrl
            : endpoint.trim())
        : provider.defaultBaseUrl;
    final tester = _configurationTester ?? LLMService.testConfiguration;
    return tester(LLMConfig(
      provider: provider,
      apiKey: apiKey.trim(),
      baseUrl: baseUrl,
      model: model.trim(),
    ));
  }
}
