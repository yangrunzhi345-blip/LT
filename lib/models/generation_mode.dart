/// Controls whether a feature-specific generation request may use reasoning.
enum LlmGenerationMode {
  /// Use the provider's normal, lowest-latency generation mode.
  fast,

  /// Allow the provider's reasoning mode when it supports one.
  deepThinking,
}
