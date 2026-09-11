import 'package:equatable/equatable.dart';

/// Semantic task a request is trying to accomplish.
///
/// Callers declare *what they are doing*; [LlmTaskResolver] turns that into
/// concrete [CompletionParams]. This keeps thinking/JSON/output decisions out
/// of individual services and off model-name comparisons.
enum LlmTask {
  /// Interactive Adventure roleplay narrative (prose + structured payload).
  adventureNarrative,

  /// Adventure/worldview preset planning (multi-step reasoning).
  adventurePlanning,

  /// Quick worldview generation (creation library, simple import).
  worldviewFast,

  /// Detailed multi-stage worldview generation.
  worldviewDeep,

  /// Quick character-card generation.
  characterFast,

  /// Detailed multi-stage character-card generation.
  characterDeep,

  /// Import of an external conversation/transcript.
  importExtraction,

  /// Pure structured extraction (NPCs, opening options, scene batch, names).
  structuredExtraction,

  /// Conversation timeline summary.
  summary,

  /// Translation / language transform.
  translation,

  /// Native image understanding / OCR-style extraction.
  visionExtraction,

  /// Runtime state analysis (reserved for the Agent Runtime).
  runtimeStateAnalysis,

  /// Narrative length supplement / continuation.
  narrativeSupplement,
}

/// How a task decides whether thinking is enabled.
enum ThinkingPolicy {
  /// Always non-thinking (low latency helpers).
  disabled,

  /// Always thinking (only where the model supports it).
  enabled,

  /// Follow the user's persisted deep-thinking toggle.
  followUserSetting,
}

/// Declarative policy for one [LlmTask].
class LlmTaskPolicy with Equatable {
  final LlmTask task;
  final ThinkingPolicy thinking;
  final String reasoningEffort;

  /// Whether this task produces a pure structured object and should request
  /// JSON output when the model supports it.
  final bool preferJsonOutput;

  /// Optional temperature override; null keeps the caller/user value so we do
  /// not silently change creative output.
  final double? temperature;

  /// Optional output budget override; null keeps the caller/user value.
  final int? maxTokens;

  /// Optional image detail hint for vision tasks.
  final String? visionDetail;

  const LlmTaskPolicy({
    required this.task,
    required this.thinking,
    this.reasoningEffort = 'high',
    this.preferJsonOutput = false,
    this.temperature,
    this.maxTokens,
    this.visionDetail,
  });

  @override
  List<Object?> get props => [
        task,
        thinking,
        reasoningEffort,
        preferJsonOutput,
        temperature,
        maxTokens,
        visionDetail,
      ];
}
