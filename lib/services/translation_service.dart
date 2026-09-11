import '../models/completion_params.dart';
import '../models/llm_task.dart';
import '../models/model_capabilities.dart';
import '../models/translation_mode.dart';
import '../services/llm_service.dart';
import 'llm_task_policy.dart';

export '../models/translation_mode.dart';

class TranslationService {
  TranslationMode _mode = TranslationMode.off;
  String _inputLang = 'zh';
  String _outputLang = 'en';
  bool _isTranslating = false;

  TranslationMode get mode => _mode;
  bool get isTranslating => _isTranslating;
  String get inputLang => _inputLang;
  String get outputLang => _outputLang;

  void setMode(TranslationMode mode) => _mode = mode;
  void setInputLang(String lang) => _inputLang = lang;
  void setOutputLang(String lang) => _outputLang = lang;

  Future<String> translate({
    required LLMService llmService,
    required String text,
    required String fromLang,
    required String toLang,
  }) async {
    if (text.trim().isEmpty) return text;
    _isTranslating = true;
    try {
      final messages = [
        {
          'role': 'system',
          'content': '你是翻译助手。只输出译文，保留格式、emoji 和 ---JSON--- 等特殊标记。',
        },
        {
          'role': 'user',
          'content': '将文本从 $fromLang 翻译为 $toLang：\n\n$text',
        },
      ];
      final result = await llmService.sendMessageStream(
        messages,
        (_) {},
        () {},
        // 翻译是确定性短任务：任务策略显式关闭思考，避免继承用户默认。
        params: const LlmTaskResolver().resolve(
          task: LlmTask.translation,
          capabilities:
              ModelCapabilityRegistry.resolve(llmService.config.model),
          userParams: const CompletionParams(
            maxTokens: 2048,
            temperature: 0.2,
          ),
        ),
      );
      return result.isEmpty ? text : result;
    } catch (_) {
      return text;
    } finally {
      _isTranslating = false;
    }
  }

  Future<String> translateInputIfNeeded({
    required LLMService llmService,
    required String text,
    required String aiInputLang,
  }) async {
    if (_mode == TranslationMode.off || _mode == TranslationMode.outputOnly) {
      return text;
    }
    return translate(
      llmService: llmService,
      text: text,
      fromLang: _inputLang,
      toLang: aiInputLang,
    );
  }

  Future<String> translateOutputIfNeeded({
    required LLMService llmService,
    required String text,
    required String aiOutputLang,
  }) async {
    if (_mode == TranslationMode.off || _mode == TranslationMode.inputOnly) {
      return text;
    }
    return translate(
      llmService: llmService,
      text: text,
      fromLang: aiOutputLang,
      toLang: _inputLang,
    );
  }
}
