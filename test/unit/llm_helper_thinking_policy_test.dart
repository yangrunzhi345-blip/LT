import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lt_dialogue/application/llm/ai_generator_llm_gateway.dart';
import 'package:lt_dialogue/engines/chat_engine_host.dart';
import 'package:lt_dialogue/engines/chat_engine_internals/summary_service.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/models/llm_message.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/services/ai_generator_service.dart';
import 'package:lt_dialogue/services/ai_import_service.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository.dart';
import 'package:lt_dialogue/services/translation_service.dart';
import 'package:lt_dialogue/services/tts_service.dart';

class _MockLLMService extends Mock implements LLMService {}

class _MockAdventureRepository extends Mock implements IAdventureRepository {}

class _MockChatEngineHost extends Mock implements ChatEngineHost {}

/// 先为 `sendMessageStream` 注册返回 [response] 的桩，执行 [action]，再返回
/// 该调用实际使用的 [CompletionParams]。
Future<CompletionParams> _runAndCaptureParams(
  _MockLLMService llm,
  String response,
  Future<void> Function() action,
) async {
  when(
    () => llm.sendMessageStream(
      any(),
      any(),
      any(),
      onReasoningChunk: any(named: 'onReasoningChunk'),
      params: any(named: 'params'),
      taskHandle: any(named: 'taskHandle'),
    ),
  ).thenAnswer((invocation) async {
    // Buffer-style callers (`_callText`, import) read the streamed chunks
    // rather than the return value, so emit the response as a chunk too.
    final onChunk = invocation.positionalArguments[1] as void Function(String);
    onChunk(response);
    return response;
  });

  await action();

  final captured = verify(
    () => llm.sendMessageStream(
      any(),
      any(),
      any(),
      onReasoningChunk: any(named: 'onReasoningChunk'),
      params: captureAny(named: 'params'),
      taskHandle: any(named: 'taskHandle'),
    ),
  ).captured;
  return captured.last as CompletionParams;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerFallbackValue(const CompletionParams());
    registerFallbackValue(<LlmMessage>[]);
    registerFallbackValue((String _) {});
    registerFallbackValue(() {});
  });

  test('translation helper passes non-thinking params', () async {
    final llm = _MockLLMService();
    final service = TranslationService();

    final params = await _runAndCaptureParams(llm, '你好', () async {
      await service.translate(
        llmService: llm,
        text: 'hello',
        fromLang: 'en',
        toLang: 'zh',
      );
    });

    expect(params.enableThinking, isFalse);
  });

  test('TTS cleanup helper passes non-thinking params', () async {
    final llm = _MockLLMService();
    final service = TtsService();

    final params = await _runAndCaptureParams(llm, '正文', () async {
      await service.synthesizeWithLLM(llmService: llm, text: '正文');
    });

    expect(params.enableThinking, isFalse);
  });

  test('raw JSON completion helper passes non-thinking params', () async {
    final llm = _MockLLMService();
    final gateway = AiGeneratorLlmGateway(
      () => throw UnimplementedError(),
      llmResolver: () => llm,
    );

    final params = await _runAndCaptureParams(llm, '{}', () async {
      await gateway.rawCompletion(
        systemPrompt: 'extract json',
        instruction: 'data',
      );
    });

    expect(params.enableThinking, isFalse);
  });

  test('adventure timeline summary helper passes non-thinking params',
      () async {
    final llm = _MockLLMService();
    final repo = _MockAdventureRepository();
    final host = _MockChatEngineHost();
    when(() => host.llmService).thenReturn(llm);
    when(() => repo.getLatestSummary(any(), branchId: any(named: 'branchId')))
        .thenAnswer((_) async => null);
    when(
      () => repo.saveSummary(
        any(),
        any(),
        any(),
        branchId: any(named: 'branchId'),
        stateSnapshot: any(named: 'stateSnapshot'),
      ),
    ).thenAnswer((_) async => 1);
    when(() =>
            repo.cleanupOldSummaries(any(), branchId: any(named: 'branchId')))
        .thenAnswer((_) async {});

    final service = SummaryService(adventureRepo: repo, host: host);
    final params = await _runAndCaptureParams(llm, '时间线', () async {
      await service.generateSummary(
        msgs: [
          Message(id: 'u', content: '前进', isUser: true),
          Message(id: 'a', content: '你走进白港', isUser: false),
        ],
        upToIndex: 2,
        host: host,
        adventureId: 1,
        branchId: 0,
        generation: 1,
        isCurrent: (_, __, ___) => true,
        onSuccess: (_) {},
        onNotify: () {},
      );
    });

    expect(params.enableThinking, isFalse);
  });

  test('import extraction helper passes non-thinking params', () async {
    final llm = _MockLLMService();
    final service = AiImportService(llm);

    final params = await _runAndCaptureParams(
      llm,
      '{"messages":[{"role":"user","content":"hi"}]}',
      () async {
        await service.importChat(rawContent: 'hi', fileType: 'txt');
      },
    );

    expect(params.enableThinking, isFalse);
  });

  test('vision extraction helper passes non-thinking params', () async {
    final llm = _MockLLMService();
    final service = AiGeneratorService(llm);

    // Vision is the first producer on the typed transport.
    when(
      () => llm.sendMessageStreamTyped(
        any(),
        any(),
        any(),
        onReasoningChunk: any(named: 'onReasoningChunk'),
        params: any(named: 'params'),
        taskHandle: any(named: 'taskHandle'),
      ),
    ).thenAnswer((invocation) async {
      const response = '{"name":"北境","description":"寒冷边境"}';
      final onChunk =
          invocation.positionalArguments[1] as void Function(String);
      onChunk(response);
      return response;
    });

    await service.imageToWorldview('AAAA');

    final captured = verify(
      () => llm.sendMessageStreamTyped(
        any(),
        any(),
        any(),
        onReasoningChunk: any(named: 'onReasoningChunk'),
        params: captureAny(named: 'params'),
        taskHandle: any(named: 'taskHandle'),
      ),
    ).captured;
    expect((captured.last as CompletionParams).enableThinking, isFalse);
  });

  test('low-level CompletionParams default stays thinking-enabled', () {
    // Documented product decision: interactive chat relies on the default
    // remaining opt-out. Changing this default requires a product decision and
    // updating this guard plus the helper call sites above.
    expect(const CompletionParams().enableThinking, isTrue);
    expect(const CompletionParams().reasoningEffort, 'high');
  });
}
