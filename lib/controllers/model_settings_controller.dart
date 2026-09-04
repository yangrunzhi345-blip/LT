import 'package:flutter/foundation.dart';

import '../application/llm/model_settings_use_case.dart';
import '../services/llm_service.dart';

/// 模型设置控制器 — 当前模型解析、密钥管理、端点管理、连接测试。
///
/// 统一收编 settings_center_screen 和 app_dialogs 中散落的 LLM 配置逻辑。
/// 连接测试与端点规则委托 [ModelSettingsUseCase]。
class ModelSettingsController extends ChangeNotifier {
  final LLMService Function() _llmResolver;
  final ModelSettingsUseCase _useCase;

  LLMProvider _currentProvider = LLMProvider.deepseek;
  String _currentModel = '';
  String _currentEndpoint = '';
  String _currentApiKey = '';
  bool _testing = false;
  String? _testResult;
  String? _error;
  bool _disposed = false;
  int _generation = 0;

  ModelSettingsController({
    required LLMService Function() llmResolver,
    ModelSettingsUseCase? useCase,
  })  : _llmResolver = llmResolver,
        _useCase = useCase ?? const ModelSettingsUseCase();

  LLMProvider get currentProvider => _currentProvider;
  String get currentModel => _currentModel;
  String get currentEndpoint => _currentEndpoint;
  String get currentApiKey => _currentApiKey;
  bool get testing => _testing;
  String? get testResult => _testResult;
  String? get error => _error;

  LLMService get currentLlm => _llmResolver();

  /// 从当前 LLMService 加载配置。
  void loadFromCurrent() {
    final llm = _llmResolver();
    _currentProvider = llm.config.provider;
    _currentModel = llm.config.model;
    _currentEndpoint = llm.config.baseUrl;
    _currentApiKey = llm.config.apiKey;
    _notify();
  }

  /// 设置当前提供商。
  void setProvider(LLMProvider provider) {
    _currentProvider = provider;
    _notify();
  }

  /// 设置当前模型。
  void setModel(String model) {
    _currentModel = model;
    _notify();
  }

  /// 设置 API Key。
  void setApiKey(String key) {
    _currentApiKey = key;
    _notify();
  }

  /// 设置自定义端点。
  void setEndpoint(String url) {
    _currentEndpoint = url;
    _notify();
  }

  /// 测试当前配置的连接（内置商固定官方端点，自定义使用自定义端点）。
  Future<bool> testConnection({
    LLMProvider? provider,
    String? apiKey,
    String? model,
    String? endpoint,
  }) async {
    final generation = ++_generation;
    _testing = true;
    _testResult = null;
    _error = null;
    _notify();
    try {
      final result = await _useCase.testConnection(
        provider: provider ?? _currentProvider,
        apiKey: apiKey ?? _currentApiKey,
        model: model ?? _currentModel,
        endpoint: endpoint ?? _currentEndpoint,
      );
      if (!_isCurrent(generation)) return false;
      _testResult = result ? '连接成功' : '连接失败';
      _testing = false;
      _notify();
      return result;
    } catch (e) {
      if (!_isCurrent(generation)) return false;
      _error = e.toString();
      _testing = false;
      _notify();
      return false;
    }
  }

  void reset() {
    _generation++;
    _testing = false;
    _testResult = null;
    _error = null;
    _notify();
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
