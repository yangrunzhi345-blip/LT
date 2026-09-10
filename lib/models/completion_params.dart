import 'package:equatable/equatable.dart';

import '../core/utils/json_value_reader.dart';

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
    this.enableThinking = true,
    this.reasoningEffort = 'high', // low, medium, high, max
    this.responseFormat,
  });

  Map<String, dynamic> toRequestMap({
    bool isDeepSeek = false,
    bool supportsThinking = true,
    String? model,
  }) {
    final map = <String, dynamic>{
      'max_tokens': maxTokens,
    };

    if (responseFormat != null) {
      map['response_format'] = responseFormat;
    }

    final isDs = isDeepSeek ||
        (model != null && model.toLowerCase().contains('deepseek'));

    if (isDs && supportsThinking) {
      // DeepSeek 官方思考模式规范：
      // extra_body: {"thinking": {"type": "enabled"|"disabled"}}, reasoning_effort: "low"|"medium"|"high"|"max"
      map['thinking'] = {
        'type': enableThinking ? 'enabled' : 'disabled',
      };
      if (enableThinking) {
        map['reasoning_effort'] = reasoningEffort;
      } else {
        // 官方规范：思考模式下采样参数由模型自适应管理；
        // 非思考模式下采样与惩罚参数全面生效
        map['temperature'] = temperature;
        map['top_p'] = topP;
        if (frequencyPenalty != 0.0) {
          map['frequency_penalty'] = frequencyPenalty;
        }
        if (presencePenalty != 0.0) {
          map['presence_penalty'] = presencePenalty;
        }
      }
    } else {
      map['temperature'] = temperature;
      map['top_p'] = topP;
      if (frequencyPenalty != 0.0) {
        map['frequency_penalty'] = frequencyPenalty;
      }
      if (presencePenalty != 0.0) {
        map['presence_penalty'] = presencePenalty;
      }
      if (enableThinking && supportsThinking) {
        map['reasoning_effort'] = reasoningEffort;
      }
    }
    return map;
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
          JsonValueReader.boolScalar(json['enable_thinking']) ?? true,
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
    '深度思考 (V4 官方推荐)': CompletionParams(
      enableThinking: true,
      reasoningEffort: 'high',
      temperature: 1.0,
      topP: 0.95,
      maxTokens: 8192,
    ),
    '极速叙事 (创意角色)': CompletionParams(
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
