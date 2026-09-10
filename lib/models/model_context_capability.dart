import '../core/utils/json_value_reader.dart';

enum ModelCapabilitySource {
  builtIn,
  providerMetadata,
  userConfigured,
  conservativeFallback,
  runtimeObserved,
}

enum ReasoningTokenPolicy { includedInOutput, separateReserve, unknown }

class ModelContextCapability {
  final String providerId;
  final String modelId;
  final int maximumContextTokens;
  final int maximumOutputTokens;
  final bool supportsPromptCaching;
  final bool supportsStructuredOutput;
  final bool supportsToolCalling;
  final String tokenizerType;
  final ReasoningTokenPolicy reasoningTokenPolicy;
  final ModelCapabilitySource capabilitySource;

  const ModelContextCapability({
    required this.providerId,
    required this.modelId,
    required this.maximumContextTokens,
    required this.maximumOutputTokens,
    this.supportsPromptCaching = false,
    this.supportsStructuredOutput = false,
    this.supportsToolCalling = false,
    this.tokenizerType = 'conservative',
    this.reasoningTokenPolicy = ReasoningTokenPolicy.unknown,
    this.capabilitySource = ModelCapabilitySource.conservativeFallback,
  });

  const ModelContextCapability.conservative({
    this.providerId = 'unknown',
    this.modelId = 'unknown',
  })  : maximumContextTokens = 8192,
        maximumOutputTokens = 1024,
        supportsPromptCaching = false,
        supportsStructuredOutput = false,
        supportsToolCalling = false,
        tokenizerType = 'conservative',
        reasoningTokenPolicy = ReasoningTokenPolicy.unknown,
        capabilitySource = ModelCapabilitySource.conservativeFallback;

  int get contextWindowTokens => maximumContextTokens;
  int get maxOutputTokens => maximumOutputTokens;

  Map<String, Object?> toJson() => {
        'provider_id': providerId,
        'model_id': modelId,
        'context_window_tokens': maximumContextTokens,
        'max_output_tokens': maximumOutputTokens,
        'supports_prompt_caching': supportsPromptCaching,
        'supports_structured_output': supportsStructuredOutput,
        'supports_tool_calling': supportsToolCalling,
        'tokenizer_type': tokenizerType,
        'reasoning_token_policy': reasoningTokenPolicy.name,
        'capability_source': capabilitySource.name,
      };

  factory ModelContextCapability.fromJson(Map<String, dynamic> json) {
    return ModelContextCapability(
      providerId: json['provider_id']?.toString() ?? 'unknown',
      modelId: json['model_id']?.toString() ?? 'unknown',
      maximumContextTokens:
          JsonValueReader.intScalar(json['context_window_tokens']) ?? 8192,
      maximumOutputTokens:
          JsonValueReader.intScalar(json['max_output_tokens']) ?? 1024,
      supportsPromptCaching:
          JsonValueReader.boolScalar(json['supports_prompt_caching']) ?? false,
      supportsStructuredOutput:
          JsonValueReader.boolScalar(json['supports_structured_output']) ??
              false,
      supportsToolCalling:
          JsonValueReader.boolScalar(json['supports_tool_calling']) ?? false,
      tokenizerType: json['tokenizer_type']?.toString() ?? 'conservative',
      reasoningTokenPolicy: ReasoningTokenPolicy.values.firstWhere(
        (e) => e.name == json['reasoning_token_policy'],
        orElse: () => ReasoningTokenPolicy.unknown,
      ),
      capabilitySource: ModelCapabilitySource.values.firstWhere(
        (e) => e.name == json['capability_source'],
        orElse: () => ModelCapabilitySource.conservativeFallback,
      ),
    );
  }
}
