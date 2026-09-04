import 'package:equatable/equatable.dart';

class CompletionParams with Equatable {
  final double temperature;
  final double topP;
  final double frequencyPenalty;
  final double presencePenalty;
  final int maxTokens;

  const CompletionParams({
    this.temperature = 0.8, // 较高温度促进长篇输出（0.6 以下输出明显变短）
    this.topP = 0.9,
    this.frequencyPenalty = 0.15, // 轻微降低重复，鼓励新内容
    this.presencePenalty = 0.15, // 轻微降低重复，鼓励新内容
    this.maxTokens = 32768, // DeepSeek 最大输出，给模型足够空间
  });

  Map<String, dynamic> toRequestMap() => {
        'temperature': temperature,
        'top_p': topP,
        'frequency_penalty': frequencyPenalty,
        'presence_penalty': presencePenalty,
        'max_tokens': maxTokens,
      };

  Map<String, dynamic> toJson() => {
        'temperature': temperature,
        'top_p': topP,
        'frequency_penalty': frequencyPenalty,
        'presence_penalty': presencePenalty,
        'max_tokens': maxTokens,
      };

  factory CompletionParams.fromJson(Map<String, dynamic> json) {
    return CompletionParams(
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
      topP: (json['top_p'] as num?)?.toDouble() ?? 0.95,
      frequencyPenalty: (json['frequency_penalty'] as num?)?.toDouble() ?? 0.0,
      presencePenalty: (json['presence_penalty'] as num?)?.toDouble() ?? 0.0,
      maxTokens: json['max_tokens'] as int? ?? 8192,
    );
  }

  @override
  List<Object?> get props =>
      [temperature, topP, frequencyPenalty, presencePenalty, maxTokens];

  CompletionParams copyWith({
    double? temperature,
    double? topP,
    double? frequencyPenalty,
    double? presencePenalty,
    int? maxTokens,
  }) {
    return CompletionParams(
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      frequencyPenalty: frequencyPenalty ?? this.frequencyPenalty,
      presencePenalty: presencePenalty ?? this.presencePenalty,
      maxTokens: maxTokens ?? this.maxTokens,
    );
  }

  static const presets = <String, CompletionParams>{
    '剧情模式': CompletionParams(
      temperature: 0.85,
      topP: 0.92,
      frequencyPenalty: 0.15,
      presencePenalty: 0.2,
      maxTokens: 32768,
    ),
    '创意模式': CompletionParams(
      temperature: 1.2,
      topP: 0.95,
      frequencyPenalty: 0.1,
      presencePenalty: 0.15,
      maxTokens: 32768,
    ),
    '严谨模式': CompletionParams(
      temperature: 0.5,
      topP: 0.8,
      frequencyPenalty: 0.0,
      presencePenalty: 0.0,
      maxTokens: 8192,
    ),
    '简洁模式': CompletionParams(
      temperature: 0.6,
      topP: 0.85,
      frequencyPenalty: 0.3,
      presencePenalty: 0.0,
      maxTokens: 4096,
    ),
  };
}
