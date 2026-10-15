import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:lt_dialogue/models/llm_task.dart';
import 'package:http/http.dart' as http;
import 'package:lt_dialogue/core/debug/generation_diagnostics.dart';
import 'package:lt_dialogue/application/resources/generation_patch_parser.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_protocol.dart';
import 'package:lt_dialogue/models/llm_message.dart';
import 'package:lt_dialogue/models/chat_failure.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/services/api_error.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/generation_request_scheduler.dart';

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
  String model = 'test-model',
}) {
  return LLMService(
    LLMConfig(
      provider: LLMProvider.deepseek,
      apiKey: 'test-key',
      baseUrl: 'https://example.invalid',
      model: model,
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

    for (final duringConnect in [false, true]) {
      test(
          'cancellation interrupts ${duringConnect ? "connect" : "silent reasoning stream"} without waiting for timeout',
          () async {
        final handle = GenerationTaskHandle(taskId: 'cancel-turn');
        final visible = Completer<void>();
        final client = _FakeStreamedClient((request) async {
          if (duringConnect) {
            visible.complete();
            return Completer<http.StreamedResponse>().future;
          }
          final controller = StreamController<List<int>>();
          scheduleMicrotask(() => _emitLine(controller,
              'data: {"choices":[{"delta":{"reasoning_content":"thinking"}}]}'));
          return _sseResponse(controller);
        });
        final service = _service(client: client);
        final result = service.sendMessageStreamDetailedTyped(
          [LlmMessage.user('hi')],
          (_) {},
          () {},
          onReasoningChunk: (_) => visible.complete(),
          taskHandle: handle,
        );
        final expectation = expectLater(
            result.timeout(const Duration(milliseconds: 250)),
            throwsA(isA<GenerationCancelledException>()));
        await visible.future;
        await handle.cancel();
        await expectation;
        expect(client.sendCalls, 1);
        expect(client.closed, isTrue);
        expect(handle.activeCancelRequestCount, 0);
        expect(GenerationRequestScheduler.shared.activeRequests('deepseek'), 0);
        expect(GenerationRequestScheduler.shared.activeRequestsGlobally, 0);
      });
    }

    test('A6 a healthy stream is never killed by the timeouts', () async {
      final chunks = <String>[];
      final client = _FakeStreamedClient((request) async {
        final controller = StreamController<List<int>>();
        // Events arrive slower than the first-event window but faster than
        // the idle window: only a watchdog that RESETS on every transport
        // event can keep this stream alive (acceptance probe MUT-ACC-3).
        unawaited(Stream<void>.periodic(const Duration(milliseconds: 300))
            .take(3)
            .forEach((_) {
          if (!controller.isClosed) {
            _emitOpenAiDelta(controller, '片段，');
          }
        }));
        Future<void>.delayed(const Duration(milliseconds: 1100), () {
          _emitOpenAiDelta(controller, '结尾。', finishReason: 'stop');
          _emitLine(controller, 'data: [DONE]');
          controller.close();
        });
        return _sseResponse(controller);
      });
      final service = _service(
        client: client,
        policy: const LLMStreamTimeoutPolicy(
          connect: Duration(seconds: 5),
          firstEvent: Duration(milliseconds: 500),
          idle: Duration(milliseconds: 500),
          overall: Duration(seconds: 5),
        ),
      );

      final result = await service.sendMessageStreamDetailedTyped(
        [LlmMessage.user('hi')],
        chunks.add,
        () {},
      );

      expect(chunks.join(), '片段，片段，片段，结尾。');
      expect(result.content, '片段，片段，片段，结尾。');
      expect(result.responseCompleted, isTrue);
      expect(result.finishReason, LLMFinishReason.stop);
    });
  });

  group('P0 transport matrix', () {
    for (final thinking in [false, true]) {
      test('safe wire shape reflects DeepSeek thinking=$thinking', () async {
        GenerationDiagnostics.instance.resetForTesting();
        Map<String, dynamic>? wire;
        final client = _FakeStreamedClient((request) async {
          wire = jsonDecode((request as http.Request).body)
              as Map<String, dynamic>;
          final controller = StreamController<List<int>>();
          scheduleMicrotask(() {
            _emitOpenAiDelta(controller, 'private narrative',
                finishReason: 'stop');
            _emitLine(controller, 'data: [DONE]');
            unawaited(controller.close());
          });
          return _sseResponse(controller);
        });
        await _service(client: client, model: 'deepseek-flash')
            .sendMessageStreamDetailedTyped(
          [LlmMessage.user('private prompt')],
          (_) {},
          () {},
          params: CompletionParams(
              enableThinking: thinking,
              reasoningEffort: 'max',
              maxTokens: 13904),
        );
        expect(wire!['thinking'], {'type': thinking ? 'enabled' : 'disabled'});
        expect(wire!['max_tokens'], 13904);
        expect(wire!.containsKey('response_format'), isFalse);
        final markers = GenerationDiagnostics.instance.markerTail();
        final shape =
            markers.lastWhere((m) => m.contains('[LLM][REQUEST_SHAPE]'));
        expect(shape, contains('model: deepseek-flash'));
        expect(shape, contains('max_tokens: 13904'));
        expect(shape,
            contains('thinking.type: ${thinking ? 'enabled' : 'disabled'}'));
        expect(shape, contains('response_format_present: false'));
        expect(shape, contains('temperature_present: ${!thinking}'));
        expect(shape, contains('top_p_present: false'));
        expect(
            shape, contains('reasoning_effort: ${thinking ? 'max' : 'null'}'));
        expect(markers.join(), isNot(contains('private narrative')));
        expect(markers.join(), isNot(contains('private prompt')));
        expect(markers.join(), isNot(contains('test-key')));
        expect(client.sendCalls, 1);
      });
    }
    for (final malformedReasoning in [false, true]) {
      test(
          'wire trace distinguishes discarded provider data: $malformedReasoning',
          () async {
        GenerationDiagnostics.instance.resetForTesting();
        const firstContent = 'private narrative';
        const reasoning = 'private reasoning';
        const validContent = 'valid';
        final chunks = <String>[];
        final client = _FakeStreamedClient((_) async {
          final controller = StreamController<List<int>>();
          scheduleMicrotask(() {
            _emitLine(
                controller,
                'data: ${jsonEncode({
                      'choices': [
                        {
                          'delta': {
                            'content': firstContent,
                            'reasoning_content':
                                malformedReasoning ? 123 : reasoning,
                          }
                        }
                      ],
                    })}');
            _emitOpenAiDelta(controller, validContent, finishReason: 'stop');
            _emitLine(controller, 'data: [DONE]');
            unawaited(controller.close());
          });
          return _sseResponse(controller);
        });
        final result = await _service(client: client)
            .sendMessageStreamDetailedTyped(
                [LlmMessage.user('private prompt')], chunks.add, () {},
                onReasoningChunk: (_) {});
        expect(result.content,
            '${malformedReasoning ? '' : firstContent}$validContent');
        expect(chunks.join(), result.content);
        expect(result.malformedEventCount, malformedReasoning ? 1 : 0);
        expect(client.sendCalls, 1);
        final marker = GenerationDiagnostics.instance
            .markerTail()
            .lastWhere((m) => m.contains('[LLM][ATTEMPT_DONE]'));
        expect(
            marker,
            contains(
                'wireContentChars: ${firstContent.length + validContent.length}'));
        expect(marker, contains('contentChars: ${result.content.length}'));
        expect(marker, contains('messageContentChars: 0'));
        expect(marker, isNot(contains(firstContent)));
        expect(marker, isNot(contains(reasoning)));
        expect(marker, isNot(contains('private prompt')));
      });
    }
    for (final (error, classification, attempts)
        in <(Object, ChatFailureClass, int)>[
      (const SocketException('offline'), ChatFailureClass.transport, 3),
      (const HandshakeException('TLS'), ChatFailureClass.transport, 3),
      (ApiError.fromHttpStatus(401), ChatFailureClass.authentication, 1),
      (ApiError.fromHttpStatus(429), ChatFailureClass.rateLimit, 3),
      (ApiError.fromHttpStatus(503), ChatFailureClass.server, 3),
    ]) {
      test('before output: ${classification.name}', () async {
        final client = _FakeStreamedClient((_) async => throw error);
        var reasoningCallbacks = 0;
        var contentCallbacks = 0;
        await expectLater(
            _service(client: client).sendMessageStreamDetailedTyped(
                [LlmMessage.user('hi')], (_) => contentCallbacks++, () {},
                onReasoningChunk: (_) => reasoningCallbacks++),
            throwsA(predicate<Object>(
                (e) => ChatFailureClass.classify(e) == classification)));
        expect(client.sendCalls, attempts);
        expect(reasoningCallbacks, 0);
        expect(contentCallbacks, 0);
        final scheduler = GenerationRequestScheduler.shared;
        expect(scheduler.activeRequests('deepseek'), 0);
        expect(scheduler.waiterCount('deepseek'), 0);
        expect(scheduler.activeRequestsGlobally, 0);
        expect(scheduler.globalWaiterCount, 0);
      });
    }
    for (final emitContent in [false, true]) {
      test(
          'reasoning plus ${emitContent ? "content reset" : "idle timeout"} cannot replay',
          () async {
        final reasoning = <String>[];
        final content = <String>[];
        final client = _FakeStreamedClient((_) async {
          final controller = StreamController<List<int>>();
          scheduleMicrotask(() {
            _emitLine(controller,
                'data: {"choices":[{"delta":{"reasoning_content":"analysis"}}]}');
            if (emitContent) {
              _emitOpenAiDelta(controller, '正文');
              controller.addError(const SocketException('reset'));
              unawaited(controller.close());
            }
          });
          return _sseResponse(controller);
        });
        final service = _service(
            client: client,
            policy: const LLMStreamTimeoutPolicy(
                connect: Duration(seconds: 1),
                firstEvent: Duration(seconds: 1),
                idle: Duration(milliseconds: 40),
                overall: Duration(seconds: 1)));
        await expectLater(
            service.sendMessageStreamDetailedTyped(
                [LlmMessage.user('hi')], content.add, () {},
                onReasoningChunk: reasoning.add),
            throwsA(predicate<Object>((e) =>
                ChatFailureClass.classify(e) ==
                (emitContent
                    ? ChatFailureClass.transport
                    : ChatFailureClass.timeout))));
        expect(client.sendCalls, 1);
        expect(reasoning, ['analysis']);
        expect(content, emitContent ? ['正文'] : isEmpty);
        expect(GenerationRequestScheduler.shared.activeRequestsGlobally, 0);
      });
    }
    for (final finish in [null, 'length']) {
      test('500 chars with finish $finish retains exact completion evidence',
          () async {
        final text = '文' * 500;
        final chunks = <String>[];
        final client = _FakeStreamedClient((_) async {
          final controller = StreamController<List<int>>();
          scheduleMicrotask(() {
            _emitOpenAiDelta(controller, text, finishReason: finish);
            unawaited(controller.close());
          });
          return _sseResponse(controller);
        });
        final result = await _service(client: client)
            .sendMessageStreamDetailedTyped(
                [LlmMessage.user('hi')], chunks.add, () {});
        expect(client.sendCalls, 1);
        expect(chunks, [text]);
        expect(result.responseCompleted, finish != null);
        expect(
            result.finishReason,
            finish == null
                ? LLMFinishReason.interrupted
                : LLMFinishReason.length);
        expect(GenerationRequestScheduler.shared.activeRequestsGlobally, 0);
      });
    }
  });

  group('P0 consumer boundary', () {
    for (final callback in ['content', 'reasoning', 'done']) {
      for (final sentinel in [
        const SocketException('consumer failed'),
        ApiError.fromHttpStatus(503)
      ]) {
        test(
            '$callback consumer ${sentinel.runtimeType} is preserved and never retried',
            () async {
          final client = _FakeStreamedClient((_) async {
            final controller = StreamController<List<int>>();
            scheduleMicrotask(() {
              if (callback == 'content') _emitOpenAiDelta(controller, 'text');
              if (callback == 'reasoning') {
                _emitLine(controller,
                    'data: {"choices":[{"delta":{"reasoning_content":"analysis"}}]}');
              }
              _emitOpenAiDelta(controller, '', finishReason: 'stop');
              _emitLine(controller, 'data: [DONE]');
              unawaited(controller.close());
            });
            return _sseResponse(controller);
          });
          await expectLater(
              _service(client: client).sendMessageStreamDetailedTyped(
                [LlmMessage.user('hi')],
                (_) {
                  if (callback == 'content') throw sentinel;
                },
                () {
                  if (callback == 'done') throw sentinel;
                },
                onReasoningChunk: (_) {
                  if (callback == 'reasoning') throw sentinel;
                },
              ),
              throwsA(same(sentinel)));
          expect(client.sendCalls, 1);
          expect(GenerationRequestScheduler.shared.activeRequestsGlobally, 0);
        });
      }
    }
    test('non-string provider delta is malformed input, not a consumer failure',
        () async {
      final chunks = <String>[];
      final client = _FakeStreamedClient((_) async {
        final controller = StreamController<List<int>>();
        scheduleMicrotask(() {
          _emitLine(
              controller, 'data: {"choices":[{"delta":{"content":123}}]}');
          _emitOpenAiDelta(controller, 'valid', finishReason: 'stop');
          _emitLine(controller, 'data: [DONE]');
          unawaited(controller.close());
        });
        return _sseResponse(controller);
      });
      final result = await _service(client: client)
          .sendMessageStreamDetailedTyped(
              [LlmMessage.user('hi')], chunks.add, () {});
      expect(chunks, ['valid']);
      expect(result.malformedEventCount, 1);
      expect(client.sendCalls, 1);
    });
  });

  group('R04-B retry budget', () {
    test('should not replay a reasoning-only stream after visible output',
        () async {
      final reasoning = <String>[];
      final content = <String>[];
      final client = _FakeStreamedClient((request) async {
        final controller = StreamController<List<int>>();
        scheduleMicrotask(() {
          for (final part in ['analysis part 1', 'analysis part 2']) {
            _emitLine(
                controller,
                'data: ${jsonEncode({
                      'choices': [
                        {
                          'delta': {'reasoning_content': part}
                        },
                      ],
                    })}');
          }
          controller.addError(const SocketException('stream reset'));
          unawaited(controller.close());
        });
        return _sseResponse(controller);
      });

      await expectLater(
        _service(client: client).sendMessageStreamDetailedTyped(
          [LlmMessage.user('hi')],
          content.add,
          () {},
          onReasoningChunk: reasoning.add,
        ),
        throwsA(isA<ApiError>()),
      );
      expect(client.sendCalls, 1,
          reason: 'visible reasoning is accepted output, just like narrative');
      expect(reasoning, ['analysis part 1', 'analysis part 2']);
      expect(content, isEmpty);
      final scheduler = GenerationRequestScheduler.shared;
      expect(scheduler.activeRequests('deepseek'), 0);
      expect(scheduler.waiterCount('deepseek'), 0);
      expect(scheduler.activeRequestsGlobally, 0);
      expect(scheduler.globalWaiterCount, 0);
    });

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

  group('LLMService safe diagnostics', () {
    late DebugPrintCallback previousPrinter;
    late bool previousPrinting;
    final output = <String>[];
    setUp(() {
      output.clear();
      previousPrinter = debugPrint;
      previousPrinting = GenerationDiagnostics.printingEnabled;
      GenerationDiagnostics.printingEnabled = false;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) output.add(message);
      };
    });
    tearDown(() {
      debugPrint = previousPrinter;
      GenerationDiagnostics.printingEnabled = previousPrinting;
    });
    List<Map<String, dynamic>> records() => output
        .map((line) => jsonDecode(line.substring('[lt-safe-llm] '.length))
            as Map<String, dynamic>)
        .toList();

    test('should expose safe metadata without payloads, credentials or IDs',
        () async {
      Map<String, dynamic>? wire;
      final client = _FakeStreamedClient((request) async {
        wire =
            jsonDecode((request as http.Request).body) as Map<String, dynamic>;
        return http.StreamedResponse(
            Stream.value(utf8.encode(
                'data: {"choices":[{"delta":{"content":"private-body","reasoning_content":"private-reasoning"},"finish_reason":"stop"}]}\n'
                'data: {"choices":[],"usage":{"prompt_tokens":13,"completion_tokens":21,"prompt_cache_hit_tokens":8,"prompt_cache_miss_tokens":5}}\n'
                'data: [DONE]\n')),
            200);
      });
      final service = LLMService(
        const LLMConfig(
          provider: LLMProvider.deepseek,
          apiKey: 'private-key',
          baseUrl: 'https://private-user:private-password@example.invalid/'
              'private-path?private-query=1',
          model: 'deepseek-flash',
        ),
        clientFactory: () => client,
      );
      final result = await service.sendMessageStreamDetailedTyped(
        [LlmMessage.user('private-prompt')],
        (_) {},
        () {},
        onReasoningChunk: (_) {},
        taskHandle: GenerationTaskHandle(taskId: 'private-task')
            .forRequest('private-request'),
        params: const CompletionParams(
            diagnosticTask: LlmTask.resourceBlueprintPlanning),
      );
      expect(result.content, 'private-body');
      expect(wire!.containsKey('diagnosticTask'), isFalse);
      expect(wire.toString(), isNot(contains('resourceBlueprintPlanning')));
      for (final secret in [
        'private-key',
        'private-user',
        'private-password',
        'private-path',
        'private-query',
        'private-body',
        'private-reasoning',
        'private-prompt',
        'private-task',
        'private-request',
        'Authorization',
        'stackTrace',
      ]) {
        expect(output.join(), isNot(contains(secret)));
      }
      if (!GenerationDiagnostics.safeLlmEnabled) {
        expect(output, isEmpty);
        return;
      }
      final events = records();
      expect(events.map((event) => event['attemptSequence']).toSet(),
          hasLength(1));
      expect(
          events.every((event) => event['task'] == 'resourceBlueprintPlanning'),
          isTrue);
      expect(events.first['provider'], 'deepseek');
      expect(events.first['model'], 'deepseek-flash');
      expect(events.first['platform'], defaultTargetPlatform.name);
      expect(events.first['buildMode'], 'debug');
      expect(events.first['gitSha'], 'unknown');
      expect(events.first['version'], 'unknown');
      expect(
          events.singleWhere((e) => e['event'] == 'ENDPOINT')['endpointHost'],
          'example.invalid');
      expect(events.singleWhere((e) => e['event'] == 'HEADERS')['httpStatus'],
          200);
      final shape = events.singleWhere((e) => e['event'] == 'REQUEST_SHAPE');
      expect(shape['max_tokens'], 4096);
      expect(shape['thinking.type'], 'disabled');
      expect(shape['response_format_present'], isFalse);
      final done = events.singleWhere((e) => e['event'] == 'ATTEMPT_DONE');
      expect(done['resultFinishReason'], 'stop');
      expect(done['responseCompleted'], isTrue);
      expect(done['doneMarker'], isTrue);
      expect(done['contentChars'], 'private-body'.length);
      expect(done['reasoningChars'], 'private-reasoning'.length);
      expect(done['promptTokens'], 13);
      expect(done['completionTokens'], 21);
      expect(done['promptCacheHitTokens'], 8);
      expect(done['promptCacheMissTokens'], 5);
      expect(done['malformedEvents'], 0);
    });

    test('should distinguish retries and retain HTTP failure classification',
        () async {
      var attempts = 0;
      final client = _FakeStreamedClient((_) async {
        if (++attempts == 1) {
          return http.StreamedResponse(
              Stream.value(
                  utf8.encode('{"error":{"message":"private-error"}}')),
              503);
        }
        return http.StreamedResponse(
            Stream.value(utf8.encode(
                'data: {"choices":[{"delta":{"content":"ok"},"finish_reason":"stop"}]}\n')),
            200);
      });
      expect(
          await _service(client: client)
              .sendMessageStreamTyped([LlmMessage.user('hi')], (_) {}, () {}),
          'ok');
      expect(client.sendCalls, 2);
      expect(output.join(), isNot(contains('private-error')));
      if (!GenerationDiagnostics.safeLlmEnabled) {
        expect(output, isEmpty);
        return;
      }
      final events = records();
      final starts =
          events.where((e) => e['event'] == 'ATTEMPT_START').toList();
      expect(starts, hasLength(2));
      expect(starts[1]['attemptSequence'],
          greaterThan(starts[0]['attemptSequence'] as int));
      final failure = events.singleWhere((e) => e['event'] == 'ATTEMPT_FAILED');
      expect(failure['attemptSequence'], starts[0]['attemptSequence']);
      expect(failure['failureClass'], 'serverError');
      expect(failure['retryDecision'], isTrue);
      expect(failure['retryReason'], 'no-visible-output');
      expect(
          events
              .where((e) => e['event'] == 'HEADERS')
              .map((e) => e['httpStatus']),
          [503, 200]);
    });

    for (final finish in ['length', null]) {
      test('should retain rejection evidence for finish=$finish', () async {
        final client = _FakeStreamedClient((_) async => http.StreamedResponse(
              Stream.value(utf8.encode('data: ${jsonEncode({
                    'choices': [
                      {
                        'delta': {'content': 'private-body'},
                        if (finish != null) 'finish_reason': finish,
                      },
                    ],
                  })}\n')),
              200,
            ));
        await expectLater(
            _service(client: client)
                .sendMessageStreamTyped([LlmMessage.user('hi')], (_) {}, () {}),
            throwsA(isA<LLMResponseIncompleteException>()));
        expect(output.join(), isNot(contains('private-body')));
        if (!GenerationDiagnostics.safeLlmEnabled) {
          expect(output, isEmpty);
          return;
        }
        final done = records().singleWhere((e) => e['event'] == 'ATTEMPT_DONE');
        expect(done['resultFinishReason'], finish ?? 'interrupted');
        expect(done['responseCompleted'], finish != null);
        expect(done['doneMarker'], isFalse);
      });
    }

    test('should record timeout phase without exception details', () async {
      final client = _FakeStreamedClient(_neverCompletes);
      await expectLater(
        _service(
                client: client,
                policy: const LLMStreamTimeoutPolicy(
                    connect: Duration(milliseconds: 10),
                    firstEvent: Duration(seconds: 1),
                    idle: Duration(seconds: 1),
                    overall: Duration(seconds: 1)))
            .sendMessageStreamDetailedTyped(
                [LlmMessage.user('hi')], (_) {}, () {}),
        throwsA(isA<LLMStreamTimeoutException>()),
      );
      expect(client.sendCalls, 3);
      if (!GenerationDiagnostics.safeLlmEnabled) {
        expect(output, isEmpty);
        return;
      }
      final failures =
          records().where((e) => e['event'] == 'ATTEMPT_FAILED').toList();
      expect(failures, hasLength(3));
      expect(
          failures.every((e) =>
              e['timeoutPhase'] == 'connect' && e['failureClass'] == 'timeout'),
          isTrue);
      expect(failures.last['retryDecision'], isFalse);
      expect(failures.last['retryReason'], 'max-attempts');
    });

    for (final cancel in [false, true]) {
      test(
          'should classify ${cancel ? 'cancellation' : 'consumer failure'} safely',
          () async {
        final handle = GenerationTaskHandle();
        final client = _FakeStreamedClient((_) async => http.StreamedResponse(
            Stream.value(utf8
                .encode('data: {"choices":[{"delta":{"content":"ok"}}]}\n')),
            200));
        await expectLater(
            _service(client: client).sendMessageStreamDetailedTyped(
              [LlmMessage.user('hi')],
              (_) {
                if (cancel) {
                  unawaited(handle.cancel());
                } else {
                  throw StateError('private-exception');
                }
              },
              () {},
              taskHandle: handle,
            ),
            cancel
                ? throwsA(isA<GenerationCancelledException>())
                : throwsStateError);
        expect(client.sendCalls, 1);
        expect(output.join(), isNot(contains('private-exception')));
        expect(output.join(), isNot(contains('stackTrace')));
        if (!GenerationDiagnostics.safeLlmEnabled) {
          expect(output, isEmpty);
          return;
        }
        final failure =
            records().singleWhere((e) => e['event'] == 'ATTEMPT_FAILED');
        expect(failure['failureClass'], cancel ? 'cancelled' : 'internal');
        expect(failure['retryDecision'], isFalse);
        expect(
            failure['retryReason'], cancel ? 'cancelled' : 'consumer-failed');
      });
    }
  });

  group('LLMService P0-SSE regression', () {
    _FakeStreamedClient clientFor(String wire, {bool fragmentBytes = false}) {
      final bytes = utf8.encode(wire);
      return _FakeStreamedClient((_) async => http.StreamedResponse(
            Stream<List<int>>.fromIterable(
                fragmentBytes ? bytes.map((byte) => [byte]) : [bytes]),
            200,
          ));
    }

    for (final prefix in ['data:', 'data: ']) {
      test('should accept $prefix with CRLF and fragmented UTF-8 through DONE',
          () async {
        const content = '{"world":"银月城"}';
        final payload = jsonEncode({
          'choices': [
            {
              'delta': {'content': content},
            },
          ],
        });
        final client = clientFor(
          ': keepalive\r\n'
          'metadata:$payload\r\n'
          'data :$payload\r\n'
          '$prefix$payload\r\n\r\n'
          '$prefix[DONE]\r\n\r\n',
          fragmentBytes: true,
        );
        final chunks = <String>[];
        var doneCalls = 0;
        final result = await _service(client: client)
            .sendMessageStreamDetailedTyped(
                [LlmMessage.user('hi')], chunks.add, () => doneCalls++);

        expect(result.content, content);
        expect(chunks, [content]);
        expect(result.responseCompleted, isTrue);
        expect(result.finishReason, LLMFinishReason.completed);
        expect(result.malformedEventCount, 0);
        expect(doneCalls, 1);
        expect(client.sendCalls, 1);
      });

      for (final finish in ['stop', 'length', null]) {
        test(
            'should preserve strict completion with $prefix and finish=$finish',
            () async {
          const content = '{"world":"银月城"}';
          final payload = jsonEncode({
            'choices': [
              {
                'delta': {'content': content},
                if (finish != null) 'finish_reason': finish,
              },
            ],
          });
          final client = clientFor('$prefix$payload\n\n'
              '${finish == 'length' ? '$prefix[DONE]\n\n' : ''}');
          final chunks = <String>[];
          var doneCalls = 0;
          final response = _service(client: client).sendMessageStreamTyped(
              [LlmMessage.user('hi')], chunks.add, () => doneCalls++);

          if (finish == 'stop') {
            expect(await response, content,
                reason: 'an explicit stop completes even without DONE');
          } else {
            await expectLater(
              response,
              throwsA(isA<LLMResponseIncompleteException>()
                  .having((e) => e.result.content, 'content', content)
                  .having(
                      (e) => e.result.finishReason,
                      'finishReason',
                      finish == 'length'
                          ? LLMFinishReason.length
                          : LLMFinishReason.interrupted)
                  .having((e) => e.result.responseCompleted,
                      'responseCompleted', finish == 'length')),
            );
          }
          expect(chunks, [content]);
          expect(doneCalls, finish == null ? 0 : 1);
          expect(client.sendCalls, 1);
        });
      }
    }

    for (final includeChoices in [false, true]) {
      for (final finish in ['stop', 'length', null]) {
        test(
            'should retain usage-only tail with choices=$includeChoices '
            'without changing finish=$finish', () async {
          const content = '{"world":"银月城"}';
          final payload = jsonEncode({
            'choices': [
              {
                'delta': {'content': content},
                if (finish != null) 'finish_reason': finish,
              },
            ],
          });
          final usage = jsonEncode({
            if (includeChoices) 'choices': <Object>[],
            'usage': {
              'prompt_tokens': 13,
              'completion_tokens': 21,
              'prompt_cache_hit_tokens': 8,
              'prompt_cache_miss_tokens': 5,
            },
          });
          final client = clientFor('data: $payload\n\n'
              'data: $usage\n\n');
          final chunks = <String>[];
          var doneCalls = 0;
          final result = await _service(client: client)
              .sendMessageStreamDetailedTyped(
                  [LlmMessage.user('hi')], chunks.add, () => doneCalls++);

          expect(result.promptTokens, 13);
          expect(result.completionTokens, 21);
          expect(result.promptCacheHitTokens, 8);
          expect(result.promptCacheMissTokens, 5);
          expect(result.content, content);
          expect(chunks, [content]);
          expect(result.reasoningContent, isNull);
          expect(
              result.finishReason,
              finish == null
                  ? LLMFinishReason.interrupted
                  : LLMFinishReason.fromProvider(finish));
          expect(result.responseCompleted, finish != null);
          expect(result.malformedEventCount, 0);
          expect(doneCalls, finish == null ? 0 : 1);
          expect(client.sendCalls, 1);
        });
      }
    }

    for (final choices in <Object>[
      'invalid',
      [42],
      [
        {'delta': 42},
      ],
    ]) {
      test('should reject malformed choices with usage: $choices', () async {
        final malformed = jsonEncode({
          'choices': choices,
          'usage': {'completion_tokens': 99},
        });
        final client = clientFor('data: $malformed\n\n'
            'data: {}\n\n'
            'data: {"choices":[]}\n\n'
            'data: {"choices":[{"delta":{"content":"valid"},"finish_reason":"stop"}]}\n\n');
        final chunks = <String>[];
        final result = await _service(client: client)
            .sendMessageStreamDetailedTyped(
                [LlmMessage.user('hi')], chunks.add, () {});

        expect(result.malformedEventCount, 1);
        expect(result.completionTokens, isNull);
        expect(result.content, 'valid');
        expect(chunks, ['valid']);
        expect(result.finishReason, LLMFinishReason.stop);
        expect(result.responseCompleted, isTrue);
      });
    }
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
