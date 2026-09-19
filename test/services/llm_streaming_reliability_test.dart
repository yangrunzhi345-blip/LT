import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lt_dialogue/application/resources/generation_patch_parser.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_protocol.dart';
import 'package:lt_dialogue/models/llm_message.dart';
import 'package:lt_dialogue/services/api_error.dart';
import 'package:lt_dialogue/services/llm_service.dart';

/// R04 - LLM transport & streaming protocol reliability.
///
/// Every scenario drives the REAL production streaming path through a fake
/// [http.Client] with a controlled byte stream: no network, no wall-clock
/// waits (the timeout policy and retry backoff are injected with
/// millisecond-scale values), no sleeps.

class _SentinelException implements Exception {
  const _SentinelException();
}

/// Fake [http.Client] whose `send` is driven by the test.
final class _FakeStreamedClient extends http.BaseClient {
  _FakeStreamedClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      handler;

  int sendCalls = 0;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sendCalls++;
    return handler(request);
  }

  @override
  void close() => closed = true;
}

/// A never-completing send, used for connect-timeout scenarios.
Future<http.StreamedResponse> _neverCompletes(http.BaseRequest request) =>
    Completer<http.StreamedResponse>().future;

http.StreamedResponse _sseResponse(StreamController<List<int>> controller) =>
    http.StreamedResponse(controller.stream, 200);

void _emitLine(StreamController<List<int>> controller, String line) {
  controller.add(utf8.encode('$line\n'));
}

void _emitOpenAiDelta(
  StreamController<List<int>> controller,
  String content, {
  String? finishReason,
}) {
  final payload = jsonEncode({
    'choices': [
      {
        'delta': {'content': content},
        if (finishReason != null) 'finish_reason': finishReason,
      },
    ],
  });
  _emitLine(controller, 'data: $payload');
}

LLMService _service({
  required _FakeStreamedClient client,
  LLMStreamTimeoutPolicy policy = LLMStreamTimeoutPolicy.standard,
  bool forceAnthropic = false,
}) {
  return LLMService(
    const LLMConfig(
      provider: LLMProvider.deepseek,
      apiKey: 'test-key',
      baseUrl: 'https://example.invalid',
      model: 'test-model',
    ),
    timeoutPolicy: policy,
    clientFactory: () => client,
    retryDelay: (_) async {},
    forceAnthropicMessagesApi: forceAnthropic,
  );
}

void main() {
  group('R04-A transport timeout ownership', () {
    test('A1 a send that never completes hits the connect timeout', () async {
      final client = _FakeStreamedClient(_neverCompletes);
      final service = _service(
        client: client,
        policy: const LLMStreamTimeoutPolicy(
          connect: Duration(milliseconds: 50),
          firstEvent: Duration(seconds: 5),
          idle: Duration(seconds: 5),
          overall: Duration(seconds: 5),
        ),
      );

      await expectLater(
        service.sendMessageStreamDetailedTyped(
          [
            LlmMessage.user('hi'),
          ],
          (_) {},
          () {},
        ),
        throwsA(isA<LLMStreamTimeoutException>()
            .having((e) => e.phase, 'phase', LLMStreamTimeoutPhase.connect)),
      );
      expect(
        client.sendCalls,
        3,
        reason: 'a connect timeout before any delta is a transient transport '
            'failure and stays inside the bounded retry budget',
      );
      expect(client.closed, isTrue);
    });

    test('A2 headers without any SSE event hit the first-event timeout',
        () async {
      final client = _FakeStreamedClient((request) async {
        final controller = StreamController<List<int>>();
        return _sseResponse(controller);
      });
      final service = _service(
        client: client,
        policy: const LLMStreamTimeoutPolicy(
          connect: Duration(seconds: 5),
          firstEvent: Duration(milliseconds: 60),
          idle: Duration(seconds: 5),
          overall: Duration(seconds: 5),
        ),
      );

      await expectLater(
        service.sendMessageStreamDetailedTyped(
          [LlmMessage.user('hi')],
          (_) {},
          () {},
        ),
        throwsA(isA<LLMStreamTimeoutException>()
            .having((e) => e.phase, 'phase', LLMStreamTimeoutPhase.firstEvent)),
      );
      expect(client.closed, isTrue);
    });

    test(
        'A3 a stalled stream after a valid delta hits the idle timeout and '
        'is never transparently replayed', () async {
      final chunks = <String>[];
      final client = _FakeStreamedClient((request) async {
        final controller = StreamController<List<int>>();
        scheduleMicrotask(() {
          _emitOpenAiDelta(controller, '第一段');
        });
        return _sseResponse(controller);
      });
      final service = _service(
        client: client,
        policy: const LLMStreamTimeoutPolicy(
          connect: Duration(seconds: 5),
          firstEvent: Duration(seconds: 5),
          idle: Duration(milliseconds: 80),
          overall: Duration(seconds: 5),
        ),
      );

      await expectLater(
        service.sendMessageStreamDetailedTyped(
          [LlmMessage.user('hi')],
          chunks.add,
          () {},
        ),
        throwsA(isA<LLMStreamTimeoutException>()
            .having((e) => e.phase, 'phase', LLMStreamTimeoutPhase.idle)),
      );
      expect(chunks, ['第一段'],
          reason: 'the accepted delta is the only content the consumer saw');
      expect(client.sendCalls, 1,
          reason: 'after a delta was accepted the transport must never '
              'replay the request');
      expect(client.closed, isTrue);
    });

    test(
        'A4 continuous keepalives cannot keep the request alive past the '
        'overall deadline', () async {
      final client = _FakeStreamedClient((request) async {
        final controller = StreamController<List<int>>();
        // A keepalive comment line every 20ms: transport activity keeps
        // resetting the idle window, which is exactly why the overall
        // deadline exists.
        Timer.periodic(
          const Duration(milliseconds: 20),
          (_) => controller.add(utf8.encode(': keepalive\n\n')),
        );
        controller.onCancel = () {};
        return _sseResponse(controller);
      });
      final service = _service(
        client: client,
        policy: const LLMStreamTimeoutPolicy(
          connect: Duration(seconds: 5),
          firstEvent: Duration(seconds: 5),
          idle: Duration(seconds: 5),
          overall: Duration(milliseconds: 250),
        ),
      );

      await expectLater(
        service.sendMessageStreamDetailedTyped(
          [LlmMessage.user('hi')],
          (_) {},
          () {},
        ),
        throwsA(isA<LLMStreamTimeoutException>()
            .having((e) => e.phase, 'phase', LLMStreamTimeoutPhase.overall)),
      );
      expect(client.closed, isTrue);
    });

    test(
        'A5 user cancellation surfaces as GenerationCancelledException and '
        'closes the client, never as a timeout', () async {
      final handle = GenerationTaskHandle();
      final chunks = <String>[];
      final client = _FakeStreamedClient((request) async {
        final controller = StreamController<List<int>>();
        scheduleMicrotask(() {
          _emitOpenAiDelta(controller, '已收到的一段');
        });
        return _sseResponse(controller);
      });
      final service = _service(
        client: client,
        policy: const LLMStreamTimeoutPolicy(
          connect: Duration(seconds: 5),
          firstEvent: Duration(seconds: 5),
          idle: Duration(milliseconds: 80),
          overall: Duration(seconds: 5),
        ),
      );

      await expectLater(
        service.sendMessageStreamDetailedTyped(
          [LlmMessage.user('hi')],
          (chunk) {
            chunks.add(chunk);
            handle.cancel();
          },
          () {},
          taskHandle: handle,
        ),
        throwsA(isA<GenerationCancelledException>()),
      );
      expect(chunks, ['已收到的一段']);
      expect(client.closed, isTrue,
          reason: 'cancellation must close the client immediately');
    });

    test('A6 a healthy stream is never killed by the timeouts', () async {
      final chunks = <String>[];
      final client = _FakeStreamedClient((request) async {
        final controller = StreamController<List<int>>();
        scheduleMicrotask(() {
          _emitOpenAiDelta(controller, '第一段，');
          _emitOpenAiDelta(controller, '第二段。', finishReason: 'stop');
          _emitLine(controller, 'data: [DONE]');
          controller.close();
        });
        return _sseResponse(controller);
      });
      final service = _service(
        client: client,
        policy: const LLMStreamTimeoutPolicy(
          connect: Duration(seconds: 5),
          firstEvent: Duration(seconds: 5),
          idle: Duration(milliseconds: 500),
          overall: Duration(seconds: 5),
        ),
      );

      final result = await service.sendMessageStreamDetailedTyped(
        [LlmMessage.user('hi')],
        chunks.add,
        () {},
      );

      expect(chunks.join(), '第一段，第二段。');
      expect(result.content, '第一段，第二段。');
      expect(result.responseCompleted, isTrue);
      expect(result.finishReason, LLMFinishReason.stop);
    });
  });

  group('R04-B retry budget', () {
    test('B1 a 429 before any delta is retried inside the bounded budget',
        () async {
      var calls = 0;
      final client = _FakeStreamedClient((request) async {
        calls++;
        if (calls <= 2) {
          throw ApiError.fromHttpStatus(429);
        }
        final controller = StreamController<List<int>>();
        scheduleMicrotask(() {
          _emitOpenAiDelta(controller, '内容', finishReason: 'stop');
          _emitLine(controller, 'data: [DONE]');
          controller.close();
        });
        return _sseResponse(controller);
      });
      final service = _service(client: client);

      final result = await service.sendMessageStreamDetailedTyped(
        [LlmMessage.user('hi')],
        (_) {},
        () {},
      );

      expect(result.responseCompleted, isTrue);
      expect(client.sendCalls, 3);
      expect(client.sendCalls, lessThanOrEqualTo(RetryManager.maximumAttempts));
    });

    test('B2 a 5xx before any delta is retried inside the bounded budget',
        () async {
      var calls = 0;
      final client = _FakeStreamedClient((request) async {
        calls++;
        if (calls == 1) throw ApiError.fromHttpStatus(503);
        final controller = StreamController<List<int>>();
        scheduleMicrotask(() {
          _emitOpenAiDelta(controller, 'ok', finishReason: 'stop');
          _emitLine(controller, 'data: [DONE]');
          controller.close();
        });
        return _sseResponse(controller);
      });
      final service = _service(client: client);

      final result = await service.sendMessageStreamDetailedTyped(
        [LlmMessage.user('hi')],
        (_) {},
        () {},
      );

      expect(result.responseCompleted, isTrue);
      expect(client.sendCalls, 2);
    });

    test('B4 a 400 is never retried', () async {
      final client = _FakeStreamedClient((request) async {
        throw ApiError.fromHttpStatus(400);
      });
      final service = _service(client: client);

      await expectLater(
        service.sendMessageStreamDetailedTyped(
          [LlmMessage.user('hi')],
          (_) {},
          () {},
        ),
        throwsA(isA<ApiError>()
            .having((e) => e.type, 'type', ApiErrorType.invalidRequest)),
      );
      expect(client.sendCalls, 1);
    });

    test('B5 an authentication failure is never retried', () async {
      final client = _FakeStreamedClient((request) async {
        throw ApiError.fromHttpStatus(401);
      });
      final service = _service(client: client);

      await expectLater(
        service.sendMessageStreamDetailedTyped(
          [LlmMessage.user('hi')],
          (_) {},
          () {},
        ),
        throwsA(isA<ApiError>()
            .having((e) => e.type, 'type', ApiErrorType.unauthorized)),
      );
      expect(client.sendCalls, 1);
    });

    test('B6 an already-cancelled request is never even sent', () async {
      final handle = GenerationTaskHandle()..cancel();
      final client = _FakeStreamedClient((request) async {
        final controller = StreamController<List<int>>();
        return _sseResponse(controller);
      });
      final service = _service(client: client);

      await expectLater(
        service.sendMessageStreamDetailedTyped(
          [LlmMessage.user('hi')],
          (_) {},
          () {},
          taskHandle: handle,
        ),
        throwsA(isA<GenerationCancelledException>()),
      );
      expect(client.sendCalls, 0);
    });

    test('B7 a transport failure after an accepted delta is not replayed',
        () async {
      final chunks = <String>[];
      final client = _FakeStreamedClient((request) async {
        final controller = StreamController<List<int>>();
        scheduleMicrotask(() {
          _emitOpenAiDelta(controller, '第一段正文');
          // A retryable transport failure: the mutation probe (MUT-R04-2)
          // relies on this being retryable BEFORE any delta, so the only
          // thing that must stop the replay is the accepted delta itself.
          controller.addError(http.ClientException('Connection closed'));
        });
        return _sseResponse(controller);
      });
      final service = _service(client: client);

      await expectLater(
        service.sendMessageStreamDetailedTyped(
          [LlmMessage.user('hi')],
          chunks.add,
          () {},
        ),
        throwsA(isA<ApiError>()),
      );
      expect(chunks, ['第一段正文'],
          reason: 'exactly one delivery: no duplicate content from a replay');
      expect(client.sendCalls, 1,
          reason: 'a request that already streamed content to the consumer '
              'must never be transparently re-requested (double body, double '
              'billing)');
    });

    test('B8 usage/keepalive/malformed events never count as accepted deltas',
        () async {
      final chunks = <String>[];
      final client = _FakeStreamedClient((request) async {
        final controller = StreamController<List<int>>();
        scheduleMicrotask(() {
          // usage-only event
          _emitLine(controller,
              'data: {"choices":[],"usage":{"prompt_tokens":1,"completion_tokens":2}}');
          // malformed JSON
          _emitLine(controller, 'data: {not json');
          // keepalive comment
          _emitLine(controller, ': keepalive');
          // empty data payload
          _emitLine(controller, 'data: ');
          // A retryable transport failure: connection dropped before any
          // content delta reached the consumer.
          controller.addError(http.ClientException('Connection closed'));
        });
        return _sseResponse(controller);
      });
      final service = _service(client: client);

      await expectLater(
        service.sendMessageStreamDetailedTyped(
          [LlmMessage.user('hi')],
          chunks.add,
          () {},
        ),
        throwsA(isA<ApiError>()),
      );
      expect(chunks, isEmpty,
          reason: 'no content delta was ever accepted, so receivedAnyDelta '
              'stays false');
      expect(client.sendCalls, RetryManager.maximumAttempts,
          reason: 'without an accepted delta the transport failure is still '
              'within the bounded retry budget');
    });

    test(
        'B9 the worst case attempt count per operation is bounded and '
        'auditable', () {
      // Single owner: the LLM streaming layer. 3 attempts including the first.
      expect(RetryManager.maximumAttempts, 3);
      // Structured stages add a content budget of 3 whole attempts; each
      // attempt contains at most the single transport budget above.
      expect(
        RetryBudget.structuredJson.contentStageAttempts *
            RetryManager.maximumAttempts,
        9,
        reason: 'maximum HTTP requests per structured stage operation: '
            '3 content attempts x 3 transport attempts, never a deeper '
            'multiplication',
      );
    });
  });

  group('R04-C decode vs consumer error ownership', () {
    test('C1 an exception thrown by onChunk reaches the caller verbatim',
        () async {
      final client = _FakeStreamedClient((request) async {
        final controller = StreamController<List<int>>();
        scheduleMicrotask(() {
          _emitOpenAiDelta(controller, '正常内容');
          controller.close();
        });
        return _sseResponse(controller);
      });
      final service = _service(client: client);

      await expectLater(
        service.sendMessageStreamDetailedTyped(
          [LlmMessage.user('hi')],
          (_) => throw const _SentinelException(),
          () {},
        ),
        throwsA(isA<_SentinelException>()),
        reason: 'the consumer exception must not be swallowed as a malformed '
            'provider event (M10)',
      );
    });

    test(
        'C2 a consumer exception is not reported as provider noise and does '
        'not let the stream continue', () async {
      var onChunkCalls = 0;
      final client = _FakeStreamedClient((request) async {
        final controller = StreamController<List<int>>();
        scheduleMicrotask(() {
          _emitOpenAiDelta(controller, '第一段');
          _emitOpenAiDelta(controller, '第二段');
          _emitLine(controller, 'data: [DONE]');
          controller.close();
        });
        return _sseResponse(controller);
      });
      final service = _service(client: client);

      await expectLater(
        service.sendMessageStreamDetailedTyped(
          [LlmMessage.user('hi')],
          (_) {
            onChunkCalls++;
            throw const _SentinelException();
          },
          () {},
        ),
        throwsA(isA<_SentinelException>()),
      );
      expect(onChunkCalls, 1,
          reason: 'the subscription stops at the consumer failure; the '
              'following events are never delivered');
    });

    test(
        'C3 malformed provider JSON is counted and never reaches the '
        'consumer', () async {
      final chunks = <String>[];
      final client = _FakeStreamedClient((request) async {
        final controller = StreamController<List<int>>();
        scheduleMicrotask(() {
          _emitLine(controller, 'data: {broken json');
          _emitLine(controller, 'data: [DONE]');
          controller.close();
        });
        return _sseResponse(controller);
      });
      final service = _service(client: client);

      final result = await service.sendMessageStreamDetailedTyped(
        [LlmMessage.user('hi')],
        chunks.add,
        () {},
      );

      expect(chunks, isEmpty);
      expect(result.malformedEventCount, 1);
    });

    test('C4 a malformed event followed by a valid one recovers by policy',
        () async {
      final chunks = <String>[];
      final client = _FakeStreamedClient((request) async {
        final controller = StreamController<List<int>>();
        scheduleMicrotask(() {
          _emitLine(controller, 'data: {broken');
          _emitOpenAiDelta(controller, '恢复后的正文', finishReason: 'stop');
          _emitLine(controller, 'data: [DONE]');
          controller.close();
        });
        return _sseResponse(controller);
      });
      final service = _service(client: client);

      final result = await service.sendMessageStreamDetailedTyped(
        [LlmMessage.user('hi')],
        chunks.add,
        () {},
      );

      expect(result.malformedEventCount, 1);
      expect(result.content, '恢复后的正文');
      expect(result.responseCompleted, isTrue);
    });

    test('C5 a stream that never completes cannot report success', () async {
      final chunks = <String>[];
      final client = _FakeStreamedClient((request) async {
        final controller = StreamController<List<int>>();
        scheduleMicrotask(() {
          _emitOpenAiDelta(controller, '有内容但没有结束标记');
          controller.close();
        });
        return _sseResponse(controller);
      });
      final service = _service(client: client);

      final result = await service.sendMessageStreamDetailedTyped(
        [LlmMessage.user('hi')],
        chunks.add,
        () {},
      );

      expect(result.responseCompleted, isFalse,
          reason: 'malformed/incomplete streams must not masquerade as '
              'success even when deltas were received');
      expect(result.finishReason, LLMFinishReason.interrupted);

      // The typed text API refuses the partial result outright.
      await expectLater(
        service.sendMessageStream(
          const [
            {'role': 'user', 'content': 'hi'}
          ],
          chunks.add,
          () {},
        ),
        throwsA(isA<StateError>()),
      );
    });

    test(
        'C6 the Anthropic branch propagates consumer exceptions with the '
        'same contract', () async {
      final client = _FakeStreamedClient((request) async {
        final controller = StreamController<List<int>>();
        scheduleMicrotask(() {
          _emitLine(controller, 'event: content_block_delta');
          _emitLine(
              controller,
              'data: {"type":"content_block_delta","delta":'
              '{"type":"text_delta","text":"Anthropic 正文"}}');
          _emitLine(controller, '');
          controller.close();
        });
        return _sseResponse(controller);
      });
      final service = _service(client: client, forceAnthropic: true);

      await expectLater(
        service.sendMessageStreamDetailedTyped(
          [LlmMessage.user('hi')],
          (_) => throw const _SentinelException(),
          () {},
        ),
        throwsA(isA<_SentinelException>()),
      );
    });
  });

  group('R04-D wire protocol handling (shared by streaming and fallback)', () {
    test('D2 an SSE line split across network chunks is reassembled', () async {
      final chunks = <String>[];
      final client = _FakeStreamedClient((request) async {
        final controller = StreamController<List<int>>();
        scheduleMicrotask(() {
          const event =
              'data: {"choices":[{"delta":{"content":"被拆开的内容"}}]}\n\n';
          final bytes = utf8.encode(event);
          // Split in the middle of the JSON body.
          controller.add(bytes.sublist(0, 20));
          controller.add(bytes.sublist(20));
          controller.close();
        });
        return _sseResponse(controller);
      });
      final service = _service(client: client);

      final result = await service.sendMessageStreamDetailedTyped(
        [LlmMessage.user('hi')],
        chunks.add,
        () {},
      );

      expect(result.content, '被拆开的内容');
      expect(result.malformedEventCount, 0);
    });

    test('D3 a final event without a trailing newline is not dropped',
        () async {
      // ignore: prefer_const_declarations
      final chunks = <String>[];
      final client = _FakeStreamedClient((request) async {
        final controller = StreamController<List<int>>();
        scheduleMicrotask(() {
          controller.add(
              utf8.encode('data: {"choices":[{"delta":{"content":"前半"}}]}\n'));
          // No trailing newline on the last line; the decoder must flush it.
          controller.add(utf8.encode(
              'data: {"choices":[{"delta":{"content":"无换行结尾"},"finish_reason":"stop"}]}'));
          controller.close();
        });
        return _sseResponse(controller);
      });
      final service = _service(client: client);

      final result = await service.sendMessageStreamDetailedTyped(
        [LlmMessage.user('hi')],
        chunks.add,
        () {},
      );

      expect(result.content, '前半无换行结尾');
      expect(result.responseCompleted, isTrue);
    });

    test('D4 empty chunks and keepalives never create content deltas',
        () async {
      final chunks = <String>[];
      final client = _FakeStreamedClient((request) async {
        final controller = StreamController<List<int>>();
        scheduleMicrotask(() {
          controller.add(utf8.encode('\n\n'));
          _emitLine(controller, ': keepalive');
          _emitLine(controller, 'data: ');
          _emitOpenAiDelta(controller, '真实内容', finishReason: 'stop');
          _emitLine(controller, 'data: [DONE]');
          controller.close();
        });
        return _sseResponse(controller);
      });
      final service = _service(client: client);

      final result = await service.sendMessageStreamDetailedTyped(
        [LlmMessage.user('hi')],
        chunks.add,
        () {},
      );

      expect(chunks, ['真实内容']);
      expect(result.content, '真实内容');
    });

    test(
        'D11 the fallback path produces the exact same protocol contract as '
        'the streaming path', () {
      // Both paths converge on the same canonical patch sequence, the same
      // accumulator (sequence/cursor/identity validation) and the same
      // validator. This pins the equivalence contract the fallback relies on:
      // a full response is translated into the same 3-patch protocol the
      // streaming parser enforces - it cannot bypass the whitelist, the
      // sequence check or completion semantics.
      const response = PartGenerationResponse(
        protocolVersion: 1,
        generationId: 'gen',
        resourceId: ResourceId('res'),
        sectionId: SectionId('sec'),
        partId: PartId('part'),
        attemptId: 'att',
        content: '正文内容',
        summary: '摘要',
      );
      final patches = GenerationPatchParser.responseToPatches(response);

      expect(patches.map((p) => p.op.name).toList(),
          ['startPart', 'appendText', 'completePart']);
      expect(patches.map((p) => p.sequence).toList(), [0, 1, 2]);
      expect(patches.last.cursor, '正文内容'.length);
    });
  });
}
