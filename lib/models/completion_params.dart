import 'package:equatable/equatable.dart';

class CompletionParams with Equatable {
  final double temperature;
  final double topP;
  final double frequencyPenalty;
  final double presencePenalty;
  final int maxTokens;
  final bool enableThinking;
  final String reasoningEffort;

  const CompletionParams({
    this.temperature = 1.0, // 场景叙事与角色扮演官方推荐 1.0 ~ 1.3
    this.topP = 0.95,
    this.frequencyPenalty = 0.0,
    this.presencePenalty = 0.0,
    this.maxTokens = 4096, // 官方常用输出范围
    this.enableThinking = true, // DeepSeek 思考模式
    this.reasoningEffort = 'high', // low, medium, high, max
  });

  Map<String, dynamic> toRequestMap({bool isDeepSeek = false, String? model}) {
    final map = <String, dynamic>{
      'max_tokens': maxTokens,
    };
    final isThinkingActive = isDeepSeek && enableThinking;

    if (isThinkingActive) {
      // 深度思考模式：依照官方规范传递 extra_body 及 reasoning_effort
      map['extra_body'] = {
        'thinking': {'type': 'enabled'}
      };
      map['reasoning_effort'] = reasoningEffort;
      // 官方文档：在思考模式下温度等采样由模型自适应管理
    } else {
      map['temperature'] = temperature;
      map['top_p'] = topP;
      if (frequencyPenalty != 0.0) map['frequency_penalty'] = frequencyPenalty;
      if (presencePenalty != 0.0) map['presence_penalty'] = presencePenalty;
      if (isDeepSeek) {
        map['extra_body'] = {
          'thinking': {'type': 'disabled'}
        };
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
      };

  factory CompletionParams.fromJson(Map<String, dynamic> json) {
    return CompletionParams(
      temperature: (json['temperature'] as num?)?.toDouble() ?? 1.0,
      topP: (json['top_p'] as num?)?.toDouble() ?? 0.95,
      frequencyPenalty: (json['frequency_penalty'] as num?)?.toDouble() ?? 0.0,
      presencePenalty: (json['presence_penalty'] as num?)?.toDouble() ?? 0.0,
      maxTokens: json['max_tokens'] as int? ?? 4096,
      enableThinking: json['enable_thinking'] as bool? ?? true,
      reasoningEffort: json['reasoning_effort'] as String? ?? 'high',
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
      ];

  CompletionParams copyWith({
    double? temperature,
    double? topP,
    double? frequencyPenalty,
    double? presencePenalty,
    int? maxTokens,
    bool? enableThinking,
    String? reasoningEffort,
  }) {
    return CompletionParams(
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      frequencyPenalty: frequencyPenalty ?? this.frequencyPenalty,
      presencePenalty: presencePenalty ?? this.presencePenalty,
      maxTokens: maxTokens ?? this.maxTokens,
      enableThinking: enableThinking ?? this.enableThinking,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
    );
  }

  static const presets = <String, CompletionParams>{
    '深度思考 (官方推荐)': CompletionParams(
      enableThinking: true,
      reasoningEffort: 'high',
      temperature: 1.0,
      topP: 0.95,
      maxTokens: 8192,
    ),
    '跑团叙事 (创意角色)': CompletionParams(
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
      maxTokens: 8192,
    ),
    '极速日常 (通用会话)': CompletionParams(
      enableThinking: false,
      temperature: 0.7,
      topP: 0.9,
      maxTokens: 2048,
    ),
  };
}
