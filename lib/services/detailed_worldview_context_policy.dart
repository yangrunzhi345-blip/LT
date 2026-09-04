import '../core/config/generation_limits.dart';

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
  static const int approximateCharactersPerToken = 4;
  static const int maximumSourceCharacters =
      (maximumContextTokens - reservedPromptTokens) *
          approximateCharactersPerToken;

  const DetailedWorldviewContextPolicy();

  String briefSource(String source) {
    if (source.length <= maximumSourceCharacters) return source;
    final head = (maximumSourceCharacters * .75).floor();
    final tail = maximumSourceCharacters - head;
    return '${source.substring(0, head)}\n\n'
        '【原文过长：中段保留在数据库，当前问题上下文仅取首尾】\n\n'
        '${source.substring(source.length - tail)}';
  }

  Map<String, dynamic> toJson() => {
        'maximum_context_tokens': maximumContextTokens,
        'reserved_prompt_tokens': reservedPromptTokens,
        'approximate_characters_per_token': approximateCharactersPerToken,
        'maximum_source_characters': maximumSourceCharacters,
      };
}
