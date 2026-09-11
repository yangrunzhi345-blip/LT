import 'package:equatable/equatable.dart';

import '../core/utils/json_value_reader.dart';
import 'model_capabilities.dart';

class CompletionParams with Equatable {
  final double temperature;
  final double topP;
  final double frequencyPenalty;
  final double presencePenalty;
  final int maxTokens;
  final bool enableThinking;
  final String reasoningEffort;
  final Map<String, dynamic>? responseFormat;

  const CompletionParams({
    this.temperature = 1.0, // 场景叙事与角色扮演官方推荐 1.0 ~ 1.3
    this.topP = 0.95,
    this.frequencyPenalty = 0.0,
    this.presencePenalty = 0.0,
    this.maxTokens = 4096, // 官方常用输出范围
    // 普通 Adventure RP 默认走低延迟非思考；深度推演由设置中的显式开关
    // 或任务策略开启。
    this.enableThinking = false,
    this.reasoningEffort = 'high', // low, medium, high, max
    this.responseFormat,
  });

  /// Serializes request parameters for a specific model.
  ///
  /// The thinking shape is decided by [capabilities], never by the model name:
  /// DeepSeek V4.1 uses `thinking:{type}` (+ `reasoning_effort` when thinking
  /// is on); every other provider keeps plain OpenAI-compatible sampling.
  ///
  /// V4.1 non-thinking fixes `top_p` at 1.0 and ignores the penalty knobs, so
  /// those fields are deliberately omitted there — only `temperature` remains
  /// a meaningful knob.
  Map<String, dynamic> toRequestMap({required ModelCapabilities capabilities}) {
    final map = <String, dynamic>{
      'max_tokens': maxTokens,
    };

    if (responseFormat != null) {
      map['response_format'] = responseFormat;
    }

    final usesThinkingProtocol = capabilities.supportsThinking &&
        capabilities.thinkingWireStyle == ThinkingWireStyle.deepSeekV41;
    if (!usesThinkingProtocol) {
      _applyPlainSampling(map);
      return map;
    }

    map['thinking'] = {
      'type': enableThinking ? 'enabled' : 'disabled',
    };
    if (enableThinking) {
      // 思考模式下采样参数由模型自适应管理；只在模型支持时透传思考强度。
      if (capabilities.supportsReasoningEffort) {
        map['reasoning_effort'] = reasoningEffort;
      }
    } else {
      map['temperature'] = temperature;
    }
    return map;
  }

  void _applyPlainSampling(Map<String, dynamic> map) {
    map['temperature'] = temperature;
    map['top_p'] = topP;
    if (frequencyPenalty != 0.0) {
      map['frequency_penalty'] = frequencyPenalty;
    }
    if (presencePenalty != 0.0) {
      map['presence_penalty'] = presencePenalty;
    }
  }

  Map<String, dynamic> toJson() => {
        'temperature': temperature,
        'top_p': topP,
        'frequency_penalty': frequencyPenalty,
        'presence_penalty': presencePenalty,
        'max_tokens': maxTokens,
        'enable_thinking': enableThinking,
        'reasoning_effort': reasoningEffort,
        if (responseFormat != null) 'response_format': responseFormat,
      };

  factory CompletionParams.fromJson(Map<String, dynamic> json) {
    return CompletionParams(
      temperature: JsonValueReader.doubleScalar(json['temperature']) ?? 1.0,
      topP: JsonValueReader.doubleScalar(json['top_p']) ?? 0.95,
      frequencyPenalty:
          JsonValueReader.doubleScalar(json['frequency_penalty']) ?? 0.0,
      presencePenalty:
          JsonValueReader.doubleScalar(json['presence_penalty']) ?? 0.0,
      maxTokens: JsonValueReader.intScalar(json['max_tokens']) ?? 4096,
      enableThinking:
          JsonValueReader.boolScalar(json['enable_thinking']) ?? false,
      reasoningEffort:
          JsonValueReader.stringScalar(json['reasoning_effort']) ?? 'high',
      responseFormat: JsonValueReader.object(json['response_format']),
    );
  }

  @override
  List<Object?> get props => [
        temperature,
        topP,
        frequencyPenalty,
        presencePenalty,
        maxTokens,
        enableThinking,
        reasoningEffort,
        responseFormat,
      ];

  CompletionParams copyWith({
    double? temperature,
    double? topP,
    double? frequencyPenalty,
    double? presencePenalty,
    int? maxTokens,
    bool? enableThinking,
    String? reasoningEffort,
    Map<String, dynamic>? responseFormat,
  }) {
    return CompletionParams(
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      frequencyPenalty: frequencyPenalty ?? this.frequencyPenalty,
      presencePenalty: presencePenalty ?? this.presencePenalty,
      maxTokens: maxTokens ?? this.maxTokens,
      enableThinking: enableThinking ?? this.enableThinking,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      responseFormat: responseFormat ?? this.responseFormat,
    );
  }

  static const presets = <String, CompletionParams>{
    '深度思考 (V4.1 复杂推演)': CompletionParams(
      enableThinking: true,
      reasoningEffort: 'high',
      temperature: 1.0,
      topP: 0.95,
      maxTokens: 8192,
    ),
    '极速叙事 (默认体验)': CompletionParams(
      enableThinking: false,
      temperature: 1.1,
      topP: 0.95,
      frequencyPenalty: 0.1,
      presencePenalty: 0.15,
      maxTokens: 4096,
    ),
    '极限推理 (长考解谜)': CompletionParams(
      enableThinking: true,
      reasoningEffort: 'max',
      temperature: 1.0,
      topP: 0.95,
      maxTokens: 16384,
    ),
    '轻量日常 (极速低延迟)': CompletionParams(
      enableThinking: false,
      temperature: 0.7,
      topP: 0.9,
      maxTokens: 2048,
    ),
  };
}
