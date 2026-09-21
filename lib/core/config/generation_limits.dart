import '../../domain/resources/resource_limits.dart' show ResourceLimits;

/// Shared limits for detailed-worldview generation and editing.
abstract final class GenerationLimits {
  static const int detailedCharacterMinimumCharacters =
      ResourceLimits.minimumGenerationTargetCharacters;
  static const int detailedCharacterDefaultCharacters = 3000;
  static const int detailedCharacterMaximumCharacters =
      ResourceLimits.characterNominalCharacters;
  static const int detailedCharacterMaximumSupplementRounds = 8;

  /// Divisions for the detailed-character target slider.
  ///
  /// Derived from the shared generation step so the control always spans the
  /// full 1,000–20,000 range instead of a hard-coded tick count.
  static const int detailedCharacterTargetDivisions =
      (detailedCharacterMaximumCharacters -
              detailedCharacterMinimumCharacters) ~/
          ResourceLimits.generationTargetStepCharacters;

  static const int detailedWorldviewMinimumCharacters = 1000;
  static const int detailedWorldviewMaximumCharacters = 50000;
  static const int detailedWorldviewContextTokens = 102400;
  static const int detailedWorldviewReservedPromptTokens = 4096;
  static const int detailedWorldviewRetriesPerQuestion = 2;
  static const int detailedWorldviewConcurrentQuestions = 3;

  /// Minimum interval for publishing a streaming preview to Flutter widgets.
  static const Duration streamingUiTick = Duration(milliseconds: 30);
  static const Duration streamingPreviewThrottle = Duration(milliseconds: 180);
}
