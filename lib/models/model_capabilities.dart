import 'package:equatable/equatable.dart';

import 'model_context_capability.dart';

/// How a provider/model expects "thinking" to be expressed on the wire.
///
/// This replaces scattered `model.contains('deepseek')` checks: the transport
/// asks the capability object what shape to emit instead of guessing from the
/// model name.
enum ThinkingWireStyle {
  /// Plain OpenAI-compatible sampling: no thinking field at all.
  none,

  /// DeepSeek V4.1: `thinking:{type:enabled|disabled}` plus optional
  /// `reasoning_effort`. Non-thinking requests send only `temperature`
  /// (V4.1 fixes `top_p` at 1.0 and ignores penalty knobs).
  deepSeekV41,
}

/// Unified, per-model capability description.
///
/// This is the single source of truth for "what can this model do" and "how do
/// I express thinking for it". Business code must query this object rather than
/// compare model-name strings. It deliberately does **not** import
/// `llm_provider.dart` to avoid a dependency cycle.
///
/// Note: [contextWindow] / [maximumOutputTokens] describe the model's physical
/// limits. They are *not* the business soft budget — the runtime context budget
/// stays conservative until it is benchmarked (see docs).
class ModelCapabilities with Equatable {
  final String modelId;

  /// Physical maximum context window in tokens.
  final int contextWindow;

  /// Physical maximum single-response output in tokens.
  final int maximumOutputTokens;

  final bool supportsThinking;
  final bool supportsReasoningEffort;
  final bool supportsVision;
  final bool supportsJsonOutput;
  final bool supportsToolCalls;
  final bool supportsResponsesApi;
  final bool supportsFIM;
  final bool supportsPromptCaching;
  final bool supportsFilesApi;

  /// Discriminator for the request-body thinking shape.
  final ThinkingWireStyle thinkingWireStyle;

  final String tokenizerType;
  final ReasoningTokenPolicy reasoningTokenPolicy;
  final ModelCapabilitySource capabilitySource;

  /// Whether this model may be offered as a new selection in the picker.
  /// Legacy/deprecated models stay resolvable but are hidden.
  final bool selectableInPicker;

  /// True for models users should migrate away from.
  final bool isDeprecated;

  /// Short descriptor shown under the model name in the picker.
  final String? pickerSubtitle;

  const ModelCapabilities({
    required this.modelId,
    required this.contextWindow,
    required this.maximumOutputTokens,
    required this.supportsThinking,
    required this.supportsReasoningEffort,
    required this.supportsVision,
    required this.supportsJsonOutput,
    required this.supportsToolCalls,
    required this.supportsResponsesApi,
    required this.supportsFIM,
    required this.supportsPromptCaching,
    required this.supportsFilesApi,
    required this.thinkingWireStyle,
    this.tokenizerType = 'conservative',
    this.reasoningTokenPolicy = ReasoningTokenPolicy.unknown,
    this.capabilitySource = ModelCapabilitySource.builtIn,
    this.selectableInPicker = true,
    this.isDeprecated = false,
    this.pickerSubtitle,
  });

  /// Projects this capability onto the engine-facing context-budget record.
  ///
  /// The engine only needs token limits and a few flags; keeping it a
  /// projection means the budget path is unchanged while the richer transport
  /// semantics live here.
  ModelContextCapability toContextCapability({String providerId = 'deepseek'}) {
    return ModelContextCapability(
      providerId: providerId,
      modelId: modelId,
      maximumContextTokens: contextWindow,
      maximumOutputTokens: maximumOutputTokens,
      supportsPromptCaching: supportsPromptCaching,
      supportsStructuredOutput: supportsJsonOutput,
      supportsToolCalling: supportsToolCalls,
      tokenizerType: tokenizerType,
      reasoningTokenPolicy: reasoningTokenPolicy,
      capabilitySource: capabilitySource,
    );
  }

  @override
  List<Object?> get props => [
        modelId,
        contextWindow,
        maximumOutputTokens,
        supportsThinking,
        supportsReasoningEffort,
        supportsVision,
        supportsJsonOutput,
        supportsToolCalls,
        supportsResponsesApi,
        supportsFIM,
        supportsPromptCaching,
        supportsFilesApi,
        thinkingWireStyle,
      ];
}

/// Built-in model catalog.
///
/// Keep this the only place where concrete model ids, limits and aliases are
/// declared. UI and transport read from here instead of hardcoding strings.
class ModelCapabilityRegistry {
  ModelCapabilityRegistry._();

  /// DeepSeek V4.1 Flash — the current recommended model.
  static const ModelCapabilities deepSeekFlash = ModelCapabilities(
    modelId: 'deepseek-flash',
    contextWindow: 1000000,
    maximumOutputTokens: 384000,
    supportsThinking: true,
    supportsReasoningEffort: true,
    supportsVision: true,
    supportsJsonOutput: true,
    supportsToolCalls: true,
    supportsResponsesApi: true,
    supportsFIM: true,
    supportsPromptCaching: true,
    supportsFilesApi: false,
    thinkingWireStyle: ThinkingWireStyle.deepSeekV41,
    tokenizerType: 'deepseek',
    reasoningTokenPolicy: ReasoningTokenPolicy.includedInOutput,
    capabilitySource: ModelCapabilitySource.builtIn,
    pickerSubtitle: 'DeepSeek V4.1 Flash 最新推荐 · 多模态 · 支持深度思考',
  );

  /// Legacy/deprecated V4 Pro. Resolvable so saved configs keep working, but
  /// hidden from the picker.
  ///
  /// Limits are conservative placeholders: this model is deprecated and its
  /// exact published numbers are not relied upon.
  static const ModelCapabilities deepSeekV4Pro = ModelCapabilities(
    modelId: 'deepseek-v4-pro',
    contextWindow: 128000,
    maximumOutputTokens: 65536,
    supportsThinking: true,
    supportsReasoningEffort: true,
    supportsVision: false,
    supportsJsonOutput: true,
    supportsToolCalls: true,
    supportsResponsesApi: false,
    supportsFIM: true,
    supportsPromptCaching: true,
    supportsFilesApi: false,
    thinkingWireStyle: ThinkingWireStyle.deepSeekV41,
    tokenizerType: 'deepseek',
    reasoningTokenPolicy: ReasoningTokenPolicy.includedInOutput,
    capabilitySource: ModelCapabilitySource.providerMetadata,
    selectableInPicker: false,
    isDeprecated: true,
    pickerSubtitle: '旧版模型，建议迁移到 DeepSeek V4.1 Flash',
  );

  /// Conservative fallback for unknown/custom models: no thinking protocol and
  /// no advanced capabilities until proven otherwise.
  static const ModelCapabilities _conservative = ModelCapabilities(
    modelId: 'unknown',
    contextWindow: 8192,
    maximumOutputTokens: 1024,
    supportsThinking: false,
    supportsReasoningEffort: false,
    supportsVision: false,
    supportsJsonOutput: false,
    supportsToolCalls: false,
    supportsResponsesApi: false,
    supportsFIM: false,
    supportsPromptCaching: false,
    supportsFilesApi: false,
    thinkingWireStyle: ThinkingWireStyle.none,
    capabilitySource: ModelCapabilitySource.conservativeFallback,
    selectableInPicker: false,
  );

  /// Legacy ids that route to their canonical model. They remain callable for
  /// compatibility but are never offered as selections.
  static const Map<String, String> _aliases = {
    'deepseek-v4-flash': 'deepseek-flash',
    'deepseek-v4-flash-vision-exp': 'deepseek-flash',
  };

  static const Map<String, ModelCapabilities> _byId = {
    'deepseek-flash': deepSeekFlash,
    'deepseek-v4-pro': deepSeekV4Pro,
  };

  /// Resolves any stored/wire model id to its capabilities.
  ///
  /// Unknown ids get the conservative fallback (which keeps custom providers on
  /// plain OpenAI-compatible sampling) but keep their own [modelId] so logs and
  /// the picker remain accurate.
  static ModelCapabilities resolve(String modelId) {
    final trimmed = modelId.trim();
    return _byId[canonicalizeAlias(trimmed)] ?? _conservativeFor(trimmed);
  }

  static ModelCapabilities _conservativeFor(String modelId) {
    final id = modelId.isEmpty ? _conservative.modelId : modelId;
    if (id == _conservative.modelId) return _conservative;
    return ModelCapabilities(
      modelId: id,
      contextWindow: _conservative.contextWindow,
      maximumOutputTokens: _conservative.maximumOutputTokens,
      supportsThinking: false,
      supportsReasoningEffort: false,
      supportsVision: false,
      supportsJsonOutput: false,
      supportsToolCalls: false,
      supportsResponsesApi: false,
      supportsFIM: false,
      supportsPromptCaching: false,
      supportsFilesApi: false,
      thinkingWireStyle: ThinkingWireStyle.none,
      capabilitySource: ModelCapabilitySource.conservativeFallback,
      selectableInPicker: false,
    );
  }

  /// Maps a legacy alias to its canonical model id; other ids are unchanged.
  static String canonicalizeAlias(String modelId) {
    final trimmed = modelId.trim();
    return _aliases[trimmed] ?? trimmed;
  }

  /// True when [modelId] is a legacy alias that would be rewritten.
  static bool isLegacyAlias(String modelId) =>
      canonicalizeAlias(modelId) != modelId.trim();

  /// True for any built-in model id, including hidden/deprecated ones.
  /// Used to preserve a saved legacy selection instead of resetting it.
  static bool isKnownBuiltIn(String modelId) =>
      _byId.containsKey(modelId.trim());

  /// Models that may be offered as a new selection.
  static List<ModelCapabilities> pickerModels() {
    final seen = <String>{};
    final result = <ModelCapabilities>[];
    for (final caps in _byId.values) {
      if (caps.selectableInPicker && seen.add(caps.modelId)) {
        result.add(caps);
      }
    }
    return result;
  }

  /// Every built-in id, including hidden ones.
  static List<String> knownModelIds() => _byId.keys.toList(growable: false);
}
