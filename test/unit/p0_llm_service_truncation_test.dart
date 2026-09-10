import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/services/llm_service.dart';

/// Drives the generic text API with a scripted [LLMStreamResult] so the
/// truncation contract can be tested without a real network transport.
class _ScriptedLlmService extends LLMService {
  _ScriptedLlmService(this.result)
      : super(const LLMConfig(
          provider: LLMProvider.deepseek,
          apiKey: 'test-key',
          baseUrl: 'https://example.invalid',
          model: 'test',
        ));

  final LLMStreamResult result;
  final List<String> streamedChunks = [];

  @override
  Future<LLMStreamResult> sendMessageStreamDetailed(
    List<Map<String, String>> messages,
    void Function(String chunk) onChunk,
    void Function() onDone, {
    void Function(String reasoningChunk)? onReasoningChunk,
    CompletionParams params = const CompletionParams(),
    GenerationTaskHandle? taskHandle,
  }) async {
    if (result.content.isNotEmpty) {
      onChunk(result.content);
      streamedChunks.add(result.content);
    }
    return result;
  }
}

Future<String> _collect(_ScriptedLlmService service) {
  return service.sendMessageStream(
    const [
      {'role': 'user', 'content': 'test'},
    ],
    (_) {},
    () {},
  );
}

LLMStreamResult _incomplete(String content, LLMFinishReason reason) =>
    LLMStreamResult(
      content: content,
      finishReason: reason,
      responseCompleted: false,
    );

LLMStreamResult _completed(String content, LLMFinishReason reason) =>
    LLMStreamResult(
      content: content,
      finishReason: reason,
      responseCompleted: true,
    );

void main() {
  // A repairable JSON prefix: closing the brace would yield a valid object, so
  // the previous implementation returned this damaged string as if complete.
  const repairablePrefix = '{"name":"Aria","tags":["mage"]';

  group('LLMService.sendMessageStream rejects incomplete responses', () {
    for (final reason in const [
      LLMFinishReason.length,
      LLMFinishReason.maxTokens,
      LLMFinishReason.interrupted,
    ]) {
      test('$reason never returns the damaged JSON prefix', () async {
        final service =
            _ScriptedLlmService(_incomplete(repairablePrefix, reason));

        String? escaped;
        await expectLater(
          _collect(service).then((value) => escaped = value),
          throwsA(isA<StateError>()),
        );

        expect(escaped, isNull,
            reason:
                'incomplete structured content must not escape as a result');
        // The network/streaming layer is untouched: chunks were delivered.
        expect(service.streamedChunks, [repairablePrefix]);
      });
    }

    test('stop finish reason with responseCompleted=false still throws',
        () async {
      final service = _ScriptedLlmService(
        _incomplete('{"name":"Aria"}', LLMFinishReason.stop),
      );
      await expectLater(_collect(service), throwsA(isA<StateError>()));
    });
  });

  group('LLMService.sendMessageStream keeps completed responses', () {
    test('returns a completed JSON object unchanged', () async {
      final service = _ScriptedLlmService(
          _completed('{"name":"Aria"}', LLMFinishReason.stop));
      expect(await _collect(service), '{"name":"Aria"}');
    });

    test('returns completed prose unchanged', () async {
      final service = _ScriptedLlmService(
        _completed('一段用于朗读的旁白。', LLMFinishReason.completed),
      );
      expect(await _collect(service), '一段用于朗读的旁白。');
    });
  });
}
