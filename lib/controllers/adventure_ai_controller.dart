import 'package:flutter/foundation.dart';

import '../application/adventure/adventure_ai_use_case.dart';
import '../data/preset_adventures.dart';

/// 冒险创建流程中的 AI 生成操作控制器。
///
/// 通过 [AdventureAiUseCase] 统一访问 AI 能力，隔离 UI 与底层 LLM 通信。
class AdventureAiController extends ChangeNotifier {
  final AdventureAiUseCase _useCase;

  bool _generating = false;
  String? _error;
  bool _disposed = false;
  int _generation = 0;

  AdventureAiController({required AdventureAiUseCase useCase})
      : _useCase = useCase;

  bool get generating => _generating;
  String? get errorMessage => _error;

  /// 从原文生成 NPC 列表（完整上下文版本）。
  Future<List<Map<String, String>>> generateNpcs({
    required String userPrompt,
    String worldview = '',
    String protagonistName = '',
    String protagonistRole = '',
    String protagonistPersonality = '',
    String protagonistBackground = '',
    String protagonistBodyDescription = '',
    String protagonistAppearance = '',
    List<Map<String, String>> selectedCharacters = const [],
    List<Map<String, String>> characterRelationships = const [],
    List<Map<String, String>> existingNpcs = const [],
    List<Map<String, String>> associatedCharacters = const [],
  }) async {
    final generation = ++_generation;
    _startGeneration();
    try {
      final results = await _useCase.textToNpcs(
        userPrompt: userPrompt,
        worldview: worldview,
        protagonistName: protagonistName,
        protagonistRole: protagonistRole,
        protagonistPersonality: protagonistPersonality,
        protagonistBackground: protagonistBackground,
        protagonistBodyDescription: protagonistBodyDescription,
        protagonistAppearance: protagonistAppearance,
        selectedCharacters: selectedCharacters,
        characterRelationships: characterRelationships,
        existingNpcs: existingNpcs,
        associatedCharacters: associatedCharacters,
      );
      if (!_isCurrent(generation)) return [];
      _finishGeneration();
      return results;
    } catch (e) {
      if (!_isCurrent(generation)) return [];
      _error = _sanitizeError(e);
      _finishGeneration();
      return [];
    }
  }

  /// 生成开场场景。
  Future<Map<String, String>?> generateOpening({
    required String userPrompt,
    String worldview = '',
    String protagonistName = '',
    String protagonistRole = '',
    String protagonistPersonality = '',
    String protagonistBackground = '',
    String protagonistBodyDescription = '',
    String protagonistAppearance = '',
    List<Map<String, String>> selectedCharacters = const [],
    List<Map<String, String>> characterRelationships = const [],
    List<Map<String, String>> npcs = const [],
  }) async {
    final generation = ++_generation;
    _startGeneration();
    try {
      final results = await _useCase.textToOpening(
        userPrompt: userPrompt,
        worldview: worldview,
        protagonistName: protagonistName,
        protagonistRole: protagonistRole,
        protagonistPersonality: protagonistPersonality,
        protagonistBackground: protagonistBackground,
        protagonistBodyDescription: protagonistBodyDescription,
        protagonistAppearance: protagonistAppearance,
        selectedCharacters: selectedCharacters,
        characterRelationships: characterRelationships,
        npcs: npcs,
      );
      if (!_isCurrent(generation)) return null;
      _finishGeneration();
      return results;
    } catch (e) {
      if (!_isCurrent(generation)) return null;
      _error = _sanitizeError(e);
      _finishGeneration();
      return null;
    }
  }

  /// 单轮 JSON 补全（替代页面直接调用 AdventureSetupContextService）。
  Future<String> generateStructuredJson({
    required String systemPrompt,
    required String instruction,
    int maximumOutputTokens = 4096,
    double temperature = .7,
  }) async {
    final generation = ++_generation;
    _startGeneration();
    try {
      final result = await _useCase.rawCompletion(
        systemPrompt: systemPrompt,
        instruction: instruction,
        maximumOutputTokens: maximumOutputTokens,
        temperature: temperature,
      );
      if (!_isCurrent(generation)) return '';
      _finishGeneration();
      return result;
    } catch (e) {
      if (!_isCurrent(generation)) return '';
      _error = _sanitizeError(e);
      _finishGeneration();
      return '';
    }
  }

  /// 从文本生成世界观预设。
  Future<Map<String, String>> generateWorldview(String source) async {
    final generation = ++_generation;
    _startGeneration();
    try {
      final result = await _useCase.generateWorldview(source);
      if (!_isCurrent(generation)) return const {};
      _finishGeneration();
      return result;
    } catch (e) {
      if (!_isCurrent(generation)) return const {};
      _error = _sanitizeError(e);
      _finishGeneration();
      return const {};
    }
  }

  /// 从图片生成世界观预设。
  Future<Map<String, String>> imageToWorldview(String base64Image) async {
    final generation = ++_generation;
    _startGeneration();
    try {
      final result = await _useCase.imageToWorldview(base64Image);
      if (!_isCurrent(generation)) return const {};
      _finishGeneration();
      return result;
    } catch (e) {
      if (!_isCurrent(generation)) return const {};
      _error = _sanitizeError(e);
      _finishGeneration();
      return const {};
    }
  }

  /// 从文本生成资源角色卡。
  Future<Map<String, String>> generateResourceCharacter({
    required String source,
    String worldview = '',
    List<Map<String, String>> associatedCharacters = const [],
  }) async {
    final generation = ++_generation;
    _startGeneration();
    try {
      final result = await _useCase.generateResourceCharacter(
        source: source,
        worldview: worldview,
        associatedCharacters: associatedCharacters,
      );
      if (!_isCurrent(generation)) return const {};
      _finishGeneration();
      return result;
    } catch (e) {
      if (!_isCurrent(generation)) return const {};
      _error = _sanitizeError(e);
      _finishGeneration();
      return const {};
    }
  }

  /// 从图片生成资源角色卡。
  Future<Map<String, String>> imageToCharacterCard(
    String base64Image, {
    String worldview = '',
  }) async {
    final generation = ++_generation;
    _startGeneration();
    try {
      final result = await _useCase.imageToCharacterCard(base64Image,
          worldview: worldview);
      if (!_isCurrent(generation)) return const {};
      _finishGeneration();
      return result;
    } catch (e) {
      if (!_isCurrent(generation)) return const {};
      _error = _sanitizeError(e);
      _finishGeneration();
      return const {};
    }
  }

  /// AI 生成预设冒险数据（重试/解析/错误归一化全部在 UseCase）。
  Future<PresetAdventureData?> generateAdventurePreset({
    required String preference,
  }) async {
    final generation = ++_generation;
    _startGeneration();
    try {
      final result = await _useCase.generateAdventurePreset(
        preference: preference,
      );
      if (!_isCurrent(generation)) return null;
      _finishGeneration();
      return result;
    } catch (e) {
      if (!_isCurrent(generation)) return null;
      _error = _sanitizeError(e);
      _finishGeneration();
      return null;
    }
  }

  /// 是否为视觉模型。
  bool isVisionModel(String modelName) {
    final lower = modelName.toLowerCase();
    return lower.contains('vision') ||
        lower.contains('gpt-4o') ||
        lower.contains('gemini') ||
        lower.contains('claude');
  }

  void reset() {
    _generation++;
    _generating = false;
    _error = null;
    _notify();
  }

  void _startGeneration() {
    _generating = true;
    _error = null;
    _notify();
  }

  void _finishGeneration() {
    _generating = false;
    _notify();
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  String _sanitizeError(Object error) {
    final msg = error.toString();
    if (msg.contains('timeout') || msg.contains('Timeout')) return '请求超时，请重试';
    if (msg.contains('401')) return 'API Key 无效，请检查设置';
    if (msg.contains('403')) return 'API 访问被拒绝';
    if (msg.contains('429') || msg.contains('rate')) return '请求过于频繁，请稍后重试';
    return 'AI 生成失败，请重试';
  }

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
