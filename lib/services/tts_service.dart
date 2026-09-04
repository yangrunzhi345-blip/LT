import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import '../models/completion_params.dart';
import '../services/llm_service.dart';

class TtsService {
  TtsService();
  final FlutterTts _flutterTts = FlutterTts();
  bool _initialized = false;
  bool _enabled = false;
  double _rate = 0.5;
  double _pitch = 1.0;
  final double _volume = 0.9;
  bool _autoRead = false;

  bool get enabled => _enabled;
  bool get autoRead => _autoRead;
  double get rate => _rate;
  double get pitch => _pitch;

  Future<void> init() async {
    if (_initialized) return;
    try {
      await _flutterTts.setLanguage('zh-CN');
      await _flutterTts.setSpeechRate(_rate);
      await _flutterTts.setPitch(_pitch);
      await _flutterTts.setVolume(_volume);
      _initialized = true;
    } catch (_) {}
  }

  void setEnabled(bool value) {
    _enabled = value;
    if (!value) _flutterTts.stop();
  }

  void setAutoRead(bool value) => _autoRead = value;

  Future<void> setRate(double value) async {
    _rate = value.clamp(0.0, 1.0);
    await _flutterTts.setSpeechRate(_rate);
  }

  Future<void> setPitch(double value) async {
    _pitch = value.clamp(0.5, 2.0);
    await _flutterTts.setPitch(_pitch);
  }

  Future<void> speak(String text) async {
    if (!_enabled || !_initialized) return;
    try {
      _flutterTts.stop();
      await Future.delayed(const Duration(milliseconds: 100));
      final cleanText = stripForSpeech(text);
      if (cleanText.isEmpty) return;
      await _flutterTts.speak(cleanText);
    } catch (_) {}
  }

  Future<void> stop() async {
    await _flutterTts.stop();
  }

  String stripForSpeech(String text) {
    var clean = text
        .replaceAll(RegExp(r'---JSON---.*', dotAll: true), '')
        .replaceAll(RegExp(r'```json.*?```', dotAll: true), '')
        .replaceAll(RegExp(r'[*_~`#]'), '')
        .replaceAll(RegExp(r'\[.*?\]\(.*?\)'), '')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'\n+'), ' ')
        .trim();
    return clean;
  }

  /// 使用 LLM 生成 TTS 朗读文本（适合云 TTS 场景）
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
        params: const CompletionParams(maxTokens: 1024, temperature: 0.2),
      );
      return result.isEmpty ? stripForSpeech(text) : result;
    } catch (_) {
      return stripForSpeech(text);
    }
  }

  void dispose() {
    // stop() 依赖平台通道；测试环境无实现会抛 MissingPluginException，
    // 与 init()/speak() 一致地吞掉异步错误。
    unawaited(_flutterTts.stop().catchError((_) {}));
  }
}
