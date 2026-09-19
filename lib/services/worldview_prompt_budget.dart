import '../utils/token_estimator.dart';

/// Hard input budget for worldview source text injected into creation and
/// extraction prompts (R05-C, finding M13).
///
/// Creation paths used to interpolate the raw worldview string into prompts,
/// so a 60000-character worldview could consume an unbounded share of the
/// request window. Every injection goes through [bound], which trims at line
/// boundaries with the shared [TokenEstimator] contract instead of a blind
/// substring, and never splits a surrogate pair.
abstract final class WorldviewPromptBudget {
  /// Default injection budget. Generous enough for necessary world facts,
  /// small enough that a huge worldview cannot dominate the request.
  static const int maximumTokens = 2048;

  /// Bounds [worldview] to [maximumTokens] estimated tokens.
  ///
  /// Whole lines are kept while they fit; the first line that would overflow
  /// is token-truncated (never mid-surrogate) and the rest is dropped. The
  /// result is deterministic for the same input.
  static String bound(
    String worldview, {
    int maximumTokens = maximumTokens,
  }) {
    final text = worldview.trim();
    if (text.isEmpty) return '';
    if (TokenEstimator(text).tokens <= maximumTokens) return text;

    final lines = text.split(RegExp(r'\r?\n'));
    final buffer = StringBuffer();
    var used = 0;
    for (final line in lines) {
      final lineTokens = TokenEstimator(line).tokens + 1;
      if (used + lineTokens > maximumTokens) {
        final remaining = maximumTokens - used;
        if (remaining > 32) {
          final truncated = truncateToTokens(line, remaining);
          if (truncated.isNotEmpty) buffer.writeln(truncated);
        }
        break;
      }
      buffer.writeln(line);
      used += lineTokens;
    }
    return buffer.toString().trimRight();
  }
}
