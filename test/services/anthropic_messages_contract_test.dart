import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/models/llm_message.dart';
import 'package:lt_dialogue/services/api_error.dart';
import 'package:lt_dialogue/services/llm_service.dart';

/// Anthropic Messages API contract.
///
/// Drives the real production streaming path for [LLMProvider.anthropic]
/// through a fake [http.Client]; no network and no wall-clock waits.

final class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      handler;
  http.BaseRequest? lastRequest;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    lastRequest = request;
    return handler(request);
  }

  @override
  void close() => closed = true;
}

http.StreamedResponse _sse(StreamController<List<int>> controller,
        {int status = 200}) =>
    http.StreamedResponse(controller.stream, status);

void _line(StreamController<List<int>> controller, String line) =>
    controller.add(utf8.encode('$line\n'));

LLMService _service(
  _FakeClient client, {
  LLMStreamTimeoutPolicy timeoutPolicy = const LLMStreamTimeoutPolicy(
    connect: Duration(seconds: 5),
    firstEvent: Duration(seconds: 5),
    idle: Duration(seconds: 5),
    overall: Duration(seconds: 30),
  ),
}) {
  return LLMService(
    const LLMConfig(
      provider: LLMProvider.anthropic,
      apiKey: 'sk-ant-contract',
      baseUrl: 'https://api.anthropic.com',
      model: 'claude-sonnet-4-5',
    ),
    timeoutPolicy: timeoutPolicy,
    clientFactory: () => client,
    retryDelay: (_) async {},
  );
}

void main() {
  test('posts to /v1/messages with Anthropic headers and a system prompt',
      () async {
    late Map<String, dynamic> body;
    final client = _FakeClient((request) async {
      body = jsonDecode((request as http.Request).body) as Map<String, dynamic>;
      final controller = StreamController<List<int>>();
      scheduleMicrotask(() async {
        _line(controller, 'event: message_stop');
        _line(controller, 'data: {"type":"message_stop"}');
        _line(controller, '');
        await controller.close();
      });
      return _sse(controller);
    });
    final service = _service(client);

    await service.sendMessageStreamDetailedTyped(
      [
        LlmMessage.system('你是叙事助手'),
        LlmMessage.user('继续'),
      ],
      (_) {},
      () {},
      params: const CompletionParams(maxTokens: 512, temperature: 0.7),
    );

    final request = client.lastRequest!;
    expect(request.method, 'POST');
    expect(request.url.toString(), 'https://api.anthropic.com/v1/messages');
    expect(request.headers['x-api-key'], 'sk-ant-contract');
    expect(request.headers['anthropic-version'], '2023-06-01');
    expect(request.headers.containsKey('Authorization'), isFalse);

    expect(body['model'], 'claude-sonnet-4-5');
    expect(body['system'], '你是叙事助手');
    expect(body['max_tokens'], 512);
    expect(body['stream'], isTrue);
    final messages = body['messages'] as List<dynamic>;
    expect(messages, hasLength(1));
    expect((messages.single as Map<String, dynamic>)['role'], 'user');
  });

  test('streams text deltas, finish reason and usage', () async {
    final client = _FakeClient((request) async {
      final controller = StreamController<List<int>>();
      scheduleMicrotask(() async {
        _line(controller, 'event: message_start');
        _line(controller,
            'data: {"type":"message_start","message":{"usage":{"input_tokens":12,"output_tokens":1}}}');
        _line(controller, '');
        _line(controller, 'event: content_block_delta');
        _line(controller,
            'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"银月城"}}');
        _line(controller, '');
        _line(controller, 'event: content_block_delta');
        _line(controller,
            'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"的夜"}}');
        _line(controller, '');
        _line(controller, 'event: message_delta');
        _line(controller,
            'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":7}}');
        _line(controller, '');
        _line(controller, 'event: message_stop');
        _line(controller, 'data: {"type":"message_stop"}');
        _line(controller, '');
        await controller.close();
      });
      return _sse(controller);
    });
    final service = _service(client);
    final chunks = <String>[];
    var done = false;

    final result = await service.sendMessageStreamDetailedTyped(
      [LlmMessage.user('继续')],
      chunks.add,
      () => done = true,
    );

    expect(chunks.join(), '银月城的夜');
    expect(done, isTrue);
    expect(result.responseCompleted, isTrue);
    expect(result.promptTokens, 12);
    expect(result.completionTokens, 7);
    expect(result.content, '银月城的夜');
  });

  for (final (status, type) in [
    (401, ApiErrorType.unauthorized),
    (429, ApiErrorType.rateLimited),
    (500, ApiErrorType.serverError),
  ]) {
    test('maps HTTP $status to $type', () async {
      final client = _FakeClient((request) async {
        final controller = StreamController<List<int>>();
        scheduleMicrotask(() async {
          await controller.close();
        });
        return _sse(controller, status: status);
      });
      final service = _service(client);

      await expectLater(
        service.sendMessageStreamDetailedTyped(
          [LlmMessage.user('hi')],
          (_) {},
          () {},
        ),
        throwsA(isA<ApiError>().having((e) => e.type, 'type', type)),
      );
    });
  }

  test('a stalled connect hits the shared connect timeout', () async {
    final client = _FakeClient(
      (request) => Completer<http.StreamedResponse>().future,
    );
    final service = _service(
      client,
      timeoutPolicy: const LLMStreamTimeoutPolicy(
        connect: Duration(milliseconds: 30),
        firstEvent: Duration(seconds: 5),
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
      throwsA(isA<LLMStreamTimeoutException>().having(
        (e) => e.phase,
        'phase',
        LLMStreamTimeoutPhase.connect,
      )),
    );
    expect(client.closed, isTrue);
  });

  test('cancellation aborts the request with GenerationCancelledException',
      () async {
    final client =
        _FakeClient((request) => Completer<http.StreamedResponse>().future);
    final service = _service(client);
    final handle = GenerationTaskHandle();

    final pending = service.sendMessageStreamDetailedTyped(
      [LlmMessage.user('hi')],
      (_) {},
      () {},
      taskHandle: handle,
    );
    unawaited(handle.cancel());

    await expectLater(
      pending,
      throwsA(isA<GenerationCancelledException>()),
    );
    expect(client.closed, isTrue);
  });
}
