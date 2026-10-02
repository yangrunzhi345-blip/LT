import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/services/llm_service.dart';

void main() {
  for (final finish in LLMFinishReason.values) {
    test('reasoning-only eligibility requires an allowed finish: $finish', () {
      final result = LLMStreamResult(
        content: ' \n',
        reasoningContent: 'analysis',
        finishReason: finish,
        responseCompleted: true,
      );
      expect(
          ReasoningOnlyResponseException.matches(result),
          [
            LLMFinishReason.stop,
            LLMFinishReason.length,
            LLMFinishReason.maxTokens
          ].contains(finish));
    });
  }
  for (final (completed, content, reasoning) in [
    (false, '', 'analysis'),
    (true, 'prose', 'analysis'),
    (true, '', ''),
    (true, '', ' \n'),
  ]) {
    test(
        'reasoning-only excludes incomplete, prose and empty reasoning: '
        '$completed/${content.length}/${reasoning.length}', () {
      final result = LLMStreamResult(
          content: content,
          reasoningContent: reasoning,
          finishReason: LLMFinishReason.stop,
          responseCompleted: completed);
      expect(ReasoningOnlyResponseException.matches(result), isFalse);
    });
  }
  test('typed marker does not expose reasoning in diagnostic text', () {
    const error = ReasoningOnlyResponseException(LLMStreamResult(
        content: '',
        reasoningContent: 'private reasoning',
        finishReason: LLMFinishReason.stop,
        responseCompleted: true));
    expect(error.toString(), contains('stop'));
    expect(error.toString(), isNot(contains('private reasoning')));
  });
}
