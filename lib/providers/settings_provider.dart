import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../config/app_config.dart';
import '../core/theme/app_colors.dart';
import '../models/completion_params.dart';
import '../models/dialogue_level.dart';
import '../services/llm_service.dart';
import '../services/tts_service.dart';
import '../services/translation_service.dart';
import '../services/key_vault.dart';
import '../services/repositories/settings_repository.dart';

/// 应用设置与配置的 Provider
/// 拥有：API配置、模型、主题、字体、系统提示词、作者注释、完成参数、网络状态等
class SettingsProvider extends ChangeNotifier {
  final ISettingsRepository _settingsRepo;
  final FlutterSecureStorage _secureStorage;
  final Stream<List<ConnectivityResult>> _connectivityStream;
  bool _disposed = false;
  int _loadGeneration = 0;
  Future<void>? _loadFuture;

  String _apiKey = '';
  String _apiBaseUrl = AppConfig.apiBaseUrl;
  bool _isKeyConfigured = false;
  LLMProvider _providerType = LLMProvider.deepseek;
  String _modelName = LLMProvider.deepseek.defaultModel;

  // ─── 按提供商隔离的 Key 存储 ───
  // 每个 LLM 提供商独立存储 API Key，切换时自动加载对应 Key
  final Map<String, String> _providerKeys = {}; // provider.name → apiKey
  final Map<String, String> _providerBaseUrls = {};
  final Map<String, String> _providerModels = {};
  Brightness _brightness = Brightness.light;
  ThemeMode _themeMode = ThemeMode.light;
  bool _searchVisible = false;
  Color? _colorSeed;
  Color? get colorSeed => _colorSeed;
  bool _quickMode = true;
  bool get quickMode => _quickMode;
  DialogueLevel _dialogueLevel = DialogueLevel.defaultLevel;
  DialogueLevel get dialogueLevel => _dialogueLevel;

  Future<void> setQuickMode(bool v) async {
    await _waitForActiveLoad();
    await _settingsRepo.setSetting('quick_mode', v ? '1' : '0');
    if (_disposed) return;
    _quickMode = v;
    notifyListeners();
  }

  String _customSystemPrompt = '';
  String _authorsNote = '';
  int _authorsNoteDepth = 3;
  int _authorsNoteFrequency = 3;

  double _chatFontSize = 14.0;
  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  List<String> _recentModels = [];

  CompletionParams _completionParams = const CompletionParams();

  final TtsService tts = TtsService();
  final TranslationService translator = TranslationService();
  final TextEditingController searchController = TextEditingController();

  // ─── LLMService 缓存 ───
  LLMService? _cachedLlm;
  String? _cachedLlmKey;

  LLMService get llmService => getOrCreateLlm();

  /// 使用当前已解析的服务商、模型、端点和密钥测试连接。
  Future<bool> testCurrentLlmConnection() => getOrCreateLlm().testConnection();

  LLMService getOrCreateLlm() {
    final newKey =
        '${_providerType.name}:$_modelName:$_apiBaseUrl:${_apiKey.hashCode}';
    if (_cachedLlmKey != newKey || _cachedLlm == null) {
      _cachedLlm = LLMService(LLMConfig(
        provider: _providerType,
        apiKey: _apiKey,
        baseUrl: _apiBaseUrl,
        model: _modelName,
      ));
      _cachedLlmKey = newKey;
    }
    return _cachedLlm!;
  }

  // ─── Getters ───
  String get apiKey => _apiKey;
  String get apiBaseUrl => _apiBaseUrl;
  bool get isKeyConfigured => _isKeyConfigured;
  LLMProvider get providerType => _providerType;
  String get modelName => _modelName;
  Brightness get brightness => _brightness;
  ThemeMode get themeMode => _themeMode;
  bool get searchVisible => _searchVisible;
  String get customSystemPrompt => _customSystemPrompt;
  String get authorsNote => _authorsNote;
  int get authorsNoteDepth => _authorsNoteDepth;
  int get authorsNoteFrequency => _authorsNoteFrequency;
  double get chatFontSize => _chatFontSize;
  bool get isOnline => _isOnline;
  List<String> get recentModels => _recentModels;
  CompletionParams get completionParams => _completionParams;

  SettingsProvider({
    required ISettingsRepository settingsRepo,
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(),
    Stream<List<ConnectivityResult>>? connectivityStream,
  })  : _settingsRepo = settingsRepo,
        _secureStorage = secureStorage,
        _connectivityStream =
            connectivityStream ?? Connectivity().onConnectivityChanged;

  // ─── 初始化 ───

  bool? _readLegacyBool(SharedPreferences prefs, String key) {
    final value = prefs.get(key);
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
    }
    return null;
  }

  Future<void> _waitForActiveLoad() async {
    final active = _loadFuture;
    if (active != null) await active;
  }

  Future<void> loadApiKey() {
    final active = _loadFuture;
    if (active != null) return active;
    final generation = ++_loadGeneration;
    late final Future<void> future;
    future = _loadApiKey(generation).whenComplete(() {
      if (identical(_loadFuture, future)) _loadFuture = null;
    });
    _loadFuture = future;
    return future;
  }

  Future<void> _loadApiKey(int generation) async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateEncryptedKeys(prefs);
    await _migrateConfigToSettings(prefs);
    final settings = await _settingsRepo.getAllSettings();
    final providerKeys = <String, String>{};
    final encryptedKeys = await _settingsRepo.getEncryptedApiKeys();
    for (final p in LLMProvider.values) {
      try {
        final encrypted = encryptedKeys[p.name] ?? '';
        final decrypted = encrypted.isEmpty ? '' : KeyVault.decrypt(encrypted);
        if (decrypted.isNotEmpty) providerKeys[p.name] = decrypted;
      } catch (_) {}
    }

    final storedProvider =
        settings['llm_provider'] ?? prefs.getString('llm_provider');
    final persistedProvider = LLMProvider.values.firstWhere(
      (item) => item.name == storedProvider,
      orElse: () => LLMProvider.deepseek,
    );
    final configuredProviders = LLMProvider.cloudProviders
        .where((provider) => (providerKeys[provider.name] ?? '').isNotEmpty)
        .toList(growable: false);
    // 启动模型由内置云模型的可用密钥决定：没有密钥或有多个密钥时优先
    // DeepSeek；只有一个密钥时自动选中对应模型。自定义接口不是内置模型，
    // 用户已明确选择且配置了其密钥时应保留该选择。
    final provider = persistedProvider == LLMProvider.custom &&
            (providerKeys[LLMProvider.custom.name] ?? '').isNotEmpty
        ? LLMProvider.custom
        : configuredProviders.length == 1
            ? configuredProviders.single
            : LLMProvider.deepseek;
    final providerBaseUrls = <String, String>{};
    final providerModels = <String, String>{};
    for (final p in LLMProvider.values) {
      final endpointKey = 'api_base_url_${p.name}';
      // 内置服务商只能走官方端点。旧的全局 api_base_url 没有服务商
      // 归属，在多服务商时代可能是另一家服务商遗留的值，绝不能回填。
      providerBaseUrls[p.name] = p == LLMProvider.custom
          ? settings[endpointKey] ??
              prefs.getString(endpointKey) ??
              p.defaultBaseUrl
          : p.defaultBaseUrl;

      final modelKey = 'llm_model_${p.name}';
      providerModels[p.name] = settings[modelKey] ??
          prefs.getString(modelKey) ??
          (p == persistedProvider
              ? settings['llm_model'] ?? prefs.getString('llm_model')
              : null) ??
          p.defaultModel;
    }
    var baseUrl = providerBaseUrls[provider.name] ?? provider.defaultBaseUrl;
    final model = providerModels[provider.name] ?? provider.defaultModel;
    if (baseUrl.isEmpty) baseUrl = provider.defaultBaseUrl;
    final repairedEndpoints = <String, String>{
      for (final p in LLMProvider.values)
        if (p != LLMProvider.custom &&
            settings['api_base_url_${p.name}'] != p.defaultBaseUrl)
          'api_base_url_${p.name}': p.defaultBaseUrl,
      if (provider != LLMProvider.custom &&
          settings['api_base_url'] != provider.defaultBaseUrl)
        'api_base_url': provider.defaultBaseUrl,
      if (provider != persistedProvider) ...{
        'llm_provider': provider.name,
        'llm_model': model,
        'llm_model_${provider.name}': model,
      },
    };
    if (repairedEndpoints.isNotEmpty) {
      await _settingsRepo.setSettings(repairedEndpoints);
    }
    final customSystemPrompt = settings['system_prompt'] ??
        prefs.getString('custom_system_prompt') ??
        '';
    final authorsNote =
        settings['authors_note'] ?? prefs.getString('authors_note') ?? '';
    final authorsNoteDepth = int.tryParse(settings['authors_note_depth'] ??
            prefs.getInt('authors_note_depth')?.toString() ??
            '') ??
        3;
    final authorsNoteFrequency = int.tryParse(
            settings['authors_note_frequency'] ??
                prefs.getInt('authors_note_frequency')?.toString() ??
                '') ??
        3;
    final dialogueLevel = DialogueLevel.fromId(
        settings['dialogue_level'] ?? prefs.getString('dialogue_level'));
    final themeModeStr =
        settings['theme_mode'] ?? prefs.getString('theme_mode') ?? 'system';
    final themeMode = switch (themeModeStr) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };
    final colorSeedValue = int.tryParse(settings['color_seed'] ?? '') ??
        prefs.getInt('color_seed');
    final colorSeed = colorSeedValue == null ? null : Color(colorSeedValue);
    final fontSizeInt = int.tryParse(settings['chat_font_size'] ?? '');
    final chatFontSize =
        ((fontSizeInt?.toDouble()) ?? prefs.getDouble('chat_font_size') ?? 14.0)
            .clamp(12.0, 20.0);
    final recentStr =
        settings['recent_models'] ?? prefs.getString('recent_models');
    final recentModels = recentStr == null || recentStr.isEmpty
        ? <String>[]
        : recentStr.split(',').where((value) => value.isNotEmpty).toList();
    final paramsStr =
        settings['completion_params'] ?? prefs.getString('completion_params');
    var completionParams = const CompletionParams();
    if (paramsStr != null && paramsStr.isNotEmpty) {
      try {
        completionParams = CompletionParams.fromJson(
            Map<String, dynamic>.from(jsonDecode(paramsStr) as Map));
      } catch (_) {}
    }
    final quickValue = settings['quick_mode'];
    final quickMode = quickValue == null
        ? _readLegacyBool(prefs, 'quick_mode') ?? true
        : quickValue == '1' || quickValue == 'true';
    if (_disposed || generation != _loadGeneration) return;
    _providerKeys
      ..clear()
      ..addAll(providerKeys);
    _providerBaseUrls
      ..clear()
      ..addAll(providerBaseUrls);
    _providerModels
      ..clear()
      ..addAll(providerModels);
    _providerType = provider;
    _apiBaseUrl = baseUrl;
    _modelName = model;
    _apiKey = providerKeys[provider.name] ?? '';
    _isKeyConfigured = _apiKey.isNotEmpty;
    _customSystemPrompt = customSystemPrompt;
    _authorsNote = authorsNote;
    _authorsNoteDepth = authorsNoteDepth;
    _authorsNoteFrequency = authorsNoteFrequency;
    _dialogueLevel = dialogueLevel;
    _themeMode = themeMode;
    _colorSeed = colorSeed;
    _chatFontSize = chatFontSize;
    _recentModels = recentModels;
    _completionParams = completionParams;
    _quickMode = quickMode;
    await _initConnectivity();
    if (!_disposed && generation == _loadGeneration) notifyListeners();
  }

  Future<void> _migrateEncryptedKeys(SharedPreferences prefs) async {
    if (_readLegacyBool(prefs, '_key_encrypted_v2') ?? false) return;
    final oldKey =
        prefs.getString('api_key') ?? prefs.getString('deepseek_api_key') ?? '';
    if (oldKey.isNotEmpty) {
      await _saveEncryptedKey('deepseek', oldKey);
      await prefs.remove('api_key');
      await prefs.remove('deepseek_api_key');
    } else {
      try {
        final secureKey = await _secureStorage.read(key: 'api_key') ?? '';
        if (secureKey.isNotEmpty) {
          await _saveEncryptedKey('deepseek', secureKey);
          await _secureStorage.delete(key: 'api_key');
        }
      } catch (_) {}
    }
    for (final provider in LLMProvider.values) {
      final keyName = 'api_key_${provider.name}';
      final providerKey = prefs.getString(keyName) ?? '';
      if (providerKey.isEmpty) continue;
      await _saveEncryptedKey(provider.name, providerKey);
      await prefs.remove(keyName);
    }
    await prefs.setBool('_key_encrypted_v2', true);
  }

  Future<void> _migrateConfigToSettings(SharedPreferences prefs) async {
    final migrated = await _settingsRepo.getSettingInt('_config_migrated');
    if (migrated == 1) return;

    final legacyQuickMode = _readLegacyBool(prefs, 'quick_mode');
    final toMigrate = <String, String?>{
      'api_base_url': prefs.getString('deepseek_api_base'),
      'llm_provider': prefs.getString('llm_provider'),
      'llm_model': prefs.getString('llm_model'),
      'system_prompt': prefs.getString('custom_system_prompt'),
      'authors_note': prefs.getString('authors_note'),
      'authors_note_depth': prefs.getInt('authors_note_depth')?.toString(),
      'authors_note_frequency':
          prefs.getInt('authors_note_frequency')?.toString(),
      'dialogue_level': prefs.getString('dialogue_level'),
      'chat_font_size': prefs.getDouble('chat_font_size')?.toInt().toString(),
      'recent_models': prefs.getString('recent_models'),
      'completion_params': prefs.getString('completion_params'),
      'quick_mode':
          legacyQuickMode == null ? null : (legacyQuickMode ? '1' : '0'),
    };
    final pending = <String, String>{};
    for (final entry in toMigrate.entries) {
      if (entry.value != null && entry.value!.isNotEmpty) {
        // SQLite 是迁移后的权威配置来源。迁移只能补齐缺失的旧值，
        // 不能用 SharedPreferences 中的陈旧值覆盖已持久化的用户配置。
        final persistedValue = await _settingsRepo.getSetting(entry.key);
        if (persistedValue == null) {
          pending[entry.key] = entry.value!;
        }
      }
    }
    await _settingsRepo.setSettings({...pending, '_config_migrated': '1'});
  }

  Future<void> _initConnectivity() async {
    try {
      await _connectivitySub?.cancel();
      if (_disposed) return;
      _connectivitySub =
          _connectivityStream.listen((List<ConnectivityResult> results) {
        final online = results.isNotEmpty &&
            !results.every((r) => r == ConnectivityResult.none);
        if (_isOnline != online) {
          _isOnline = online;
          // 防御：连接状态可能在任何时机变更，延迟到帧后避免 build 期间 notify
          WidgetsBinding.instance.addPostFrameCallback((_) {
            notifyListeners();
          });
        }
      });
    } catch (_) {}
  }

  List<String> _recentModelsWith(String model) {
    final values = List<String>.from(_recentModels)..remove(model);
    values.insert(0, model);
    return values.take(5).toList(growable: false);
  }

  // ─── Setters ───

  Future<void> setApiKey(String key) async {
    await _waitForActiveLoad();
    final normalized = key.trim();
    final providerName = _providerType.name;
    if (normalized.isNotEmpty) {
      await _saveEncryptedKey(providerName, normalized);
    } else {
      await _settingsRepo.deleteEncryptedApiKey(providerName);
    }
    if (_disposed || providerName != _providerType.name) return;
    _apiKey = normalized;
    if (normalized.isEmpty) {
      _providerKeys.remove(providerName);
    } else {
      _providerKeys[providerName] = normalized;
    }
    _isKeyConfigured = _apiKey.isNotEmpty;
    notifyListeners();
  }

  /// 加密并存储 API Key 到 api_keys 表
  Future<void> _saveEncryptedKey(String providerName, String plainKey) async {
    final encrypted = KeyVault.encrypt(plainKey);
    await _settingsRepo.setEncryptedApiKey(providerName, encrypted);
  }

  Future<void> setApiBaseUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isNotEmpty && !trimmed.startsWith('http')) return;
    await _waitForActiveLoad();
    final provider = _providerType;
    final next = provider == LLMProvider.custom
        ? (trimmed.isEmpty ? provider.defaultBaseUrl : trimmed)
        : provider.defaultBaseUrl;
    await _settingsRepo.saveLlmConfiguration(
      provider: provider.name,
      model: _modelName,
      baseUrl: next,
    );
    if (_disposed || provider != _providerType) return;
    _apiBaseUrl = next;
    _providerBaseUrls[provider.name] = next;
    notifyListeners();
  }

  /// 检查指定提供商是否有已保存的 Key
  bool hasProviderKey(LLMProvider provider) {
    return _providerKeys.containsKey(provider.name) &&
        (_providerKeys[provider.name]?.isNotEmpty ?? false);
  }

  /// 获取指定提供商的已保存 Key（可能为空）
  String? getProviderKey(LLMProvider provider) {
    return _providerKeys[provider.name];
  }

  /// 获取指定提供商的已保存模型（可能为空）
  String? getProviderModel(LLMProvider provider) {
    return _providerModels[provider.name];
  }

  /// 内置服务商端点由官方注册表锁定；仅自定义兼容接口可保存用户地址。
  String getProviderBaseUrl(LLMProvider provider) =>
      provider == LLMProvider.custom
          ? (_providerBaseUrls[provider.name] ?? provider.defaultBaseUrl)
          : provider.defaultBaseUrl;

  Future<void> setProvider(LLMProvider provider) async {
    await _waitForActiveLoad();
    if (_providerType == provider) return;
    final baseUrl = getProviderBaseUrl(provider);
    // 确保默认模型在可用列表中，避免统一下拉组件出现无效选中值
    final available = provider.availableModels;
    final savedModel = _providerModels[provider.name];
    final modelName = savedModel != null &&
            (available.isEmpty || available.contains(savedModel))
        ? savedModel
        : (available.contains(provider.defaultModel)
            ? provider.defaultModel
            : (available.isNotEmpty ? available.first : provider.defaultModel));
    await _settingsRepo.saveLlmConfiguration(
      provider: provider.name,
      model: modelName,
      baseUrl: baseUrl,
    );
    if (_disposed) return;
    _providerType = provider;
    _apiBaseUrl = baseUrl;
    _modelName = modelName;
    _providerModels[provider.name] = modelName;
    final savedKey = _providerKeys[provider.name] ?? '';
    _apiKey = savedKey;
    _isKeyConfigured = _apiKey.isNotEmpty;
    notifyListeners();
  }

  Future<void> setProviderType(LLMProvider provider) => setProvider(provider);

  Future<void> setModel(String model) async {
    final trimmed = model.trim();
    if (trimmed.isEmpty) return;
    await _waitForActiveLoad();
    final provider = _providerType;
    final recentModels = _recentModelsWith(trimmed);
    await _settingsRepo.saveLlmConfiguration(
      provider: provider.name,
      model: trimmed,
      baseUrl: _apiBaseUrl,
      recentModels: recentModels.join(','),
    );
    if (_disposed || provider != _providerType) return;
    _modelName = trimmed;
    _providerModels[provider.name] = trimmed;
    _recentModels = recentModels;
    notifyListeners();
  }

  Future<void> setCustomSystemPrompt(String prompt) async {
    await _waitForActiveLoad();
    await _settingsRepo.setSetting('system_prompt', prompt);
    if (_disposed) return;
    _customSystemPrompt = prompt;
    notifyListeners();
  }

  Future<void> setAuthorsNote(String note) async {
    await _waitForActiveLoad();
    await _settingsRepo.setSetting('authors_note', note);
    if (_disposed) return;
    _authorsNote = note;
    notifyListeners();
  }

  Future<void> setAuthorsNoteConfig(int depth, int frequency) async {
    await _waitForActiveLoad();
    await _settingsRepo.setSettings({
      'authors_note_depth': '$depth',
      'authors_note_frequency': '$frequency',
    });
    if (_disposed) return;
    _authorsNoteDepth = depth;
    _authorsNoteFrequency = frequency;
    notifyListeners();
  }

  Future<void> setDialogueLevel(DialogueLevel level) async {
    await _waitForActiveLoad();
    await _settingsRepo.setSetting('dialogue_level', level.id);
    if (_disposed) return;
    _dialogueLevel = level;
    notifyListeners();
  }

  void updateBrightness(Brightness value) {
    if (_brightness == value) return;
    _brightness = value;
    WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
  }

  Future<void> setColorSeed(Color seed) async {
    await _waitForActiveLoad();
    await _settingsRepo.setSettingInt('color_seed', seed.toARGB32());
    if (_disposed) return;
    _colorSeed = seed;
    notifyListeners();
  }

  Future<void> updateThemeMode(ThemeMode mode) async {
    await _waitForActiveLoad();
    if (_themeMode == mode) return;
    await _settingsRepo.setSetting('theme_mode', mode.name);
    if (_disposed) return;
    _themeMode = mode;
    notifyListeners();
  }

  Future<void> resetTheme() async {
    await _waitForActiveLoad();
    final seed = AppColors.colorSeeds['海洋蓝']!;
    await _settingsRepo.setSettings({
      'theme_mode': ThemeMode.system.name,
      'color_seed': '${seed.toARGB32()}',
      'chat_font_size': '14',
    });
    if (_disposed) return;
    _themeMode = ThemeMode.system;
    _colorSeed = seed;
    _chatFontSize = 14.0;
    notifyListeners();
  }

  Future<void> setChatFontSize(double size) async {
    await _waitForActiveLoad();
    final normalized = size.clamp(12.0, 20.0);
    await _settingsRepo.setSettingInt('chat_font_size', normalized.toInt());
    if (_disposed) return;
    _chatFontSize = normalized;
    notifyListeners();
  }

  Future<void> setCompletionParams(CompletionParams params) async {
    await _waitForActiveLoad();
    final paramsJson = jsonEncode(params.toJson());
    await _settingsRepo.setSetting('completion_params', paramsJson);
    if (_disposed) return;
    _completionParams = params;
    notifyListeners();
  }

  void toggleSearch() {
    _searchVisible = !_searchVisible;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration++;
    _connectivitySub?.cancel();
    searchController.dispose();
    tts.dispose();
    super.dispose();
  }
}
