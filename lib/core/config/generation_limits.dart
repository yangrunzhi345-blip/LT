/// Shared limits for detailed-worldview generation and editing.
abstract final class GenerationLimits {
  static const int detailedCharacterMinimumCharacters = 1000;
  static const int detailedCharacterDefaultCharacters = 3000;
  static const int detailedCharacterMaximumCharacters = 5000;
  static const int detailedCharacterMaximumSupplementRounds = 8;

  static const int detailedWorldviewMinimumCharacters = 1000;
  static const int detailedWorldviewMaximumCharacters = 50000;
  static const int detailedWorldviewContextTokens = 102400;
  static const int detailedWorldviewReservedPromptTokens = 4096;
  static const int detailedWorldviewRetriesPerQuestion = 2;
  static const int detailedWorldviewConcurrentQuestions = 3;
  static const Duration streamingPreviewThrottle = Duration(milliseconds: 180);
}
