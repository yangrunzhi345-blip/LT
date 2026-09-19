import '../core/config/generation_limits.dart';
import '../utils/token_estimator.dart';

/// Context policy for the detailed-worldview interviewer.
///
/// The database keeps the complete source and answers. This policy only
/// limits what is rendered into one model request so a long source cannot
/// consume the whole request window.
class DetailedWorldviewContextPolicy {
  static const int maximumContextTokens =
      GenerationLimits.detailedWorldviewContextTokens;
  static const int reservedPromptTokens =
      GenerationLimits.detailedWorldviewReservedPromptTokens;

  /// Token budget available for the source text itself.
  static const int maximumSourceTokens =
      maximumContextTokens - reservedPromptTokens;

  const DetailedWorldviewContextPolicy();

  /// Bounds the rendered source to [maximumSourceTokens] estimated tokens.
  ///
  /// R05-C (N20): the budget decision now uses the shared [TokenEstimator]
  /// instead of an approximate characters-per-token constant, so the same
  /// deterministic estimator contract decides every prompt trim. Trimming is
  /// structured: whole paragraphs are kept (head first, then tail) until the
  /// budget is exhausted, with a marker paragraph in between; a boundary
  /// paragraph is token-truncated rather than split blindly.
  String briefSource(String source) {
    if (TokenEstimator(source).tokens <= maximumSourceTokens) return source;

    final paragraphs =
        source.split(RegExp(r'\n\s*\n')).where((p) => p.isNotEmpty).toList();
    const marker = '\n\n【原文过长：中段保留在数据库，当前问题上下文仅取首尾】\n\n';
    final markerTokens = TokenEstimator(marker).tokens;
    var remaining = maximumSourceTokens - markerTokens;
    if (remaining <= 0) return truncateToTokens(source, maximumSourceTokens);

    final keptHead = <String>[];
    final keptTail = <String>[];
    var low = 0;
    var high = paragraphs.length - 1;
    var takeHead = true;
    while (low <= high) {
      final candidate = paragraphs[takeHead ? low : high];
      final candidateTokens = TokenEstimator(candidate).tokens + 2;
      if (candidateTokens > remaining) break;
      if (takeHead) {
        keptHead.add(candidate);
        low += 1;
      } else {
        keptTail.insert(0, candidate);
        high -= 1;
      }
      remaining -= candidateTokens;
      takeHead = !takeHead;
    }
    // A boundary paragraph that did not fit whole is partially rendered.
    if (low <= high && remaining > 32) {
      final boundary = truncateToTokens(
        paragraphs[takeHead ? low : high],
        remaining,
      );
      if (takeHead) {
        keptHead.add(boundary);
      } else {
        keptTail.insert(0, boundary);
      }
    }

    return '${keptHead.join('\n\n')}$marker${keptTail.join('\n\n')}';
  }

  Map<String, dynamic> toJson() => {
        'maximum_context_tokens': maximumContextTokens,
        'reserved_prompt_tokens': reservedPromptTokens,
        'maximum_source_tokens': maximumSourceTokens,
      };
}
