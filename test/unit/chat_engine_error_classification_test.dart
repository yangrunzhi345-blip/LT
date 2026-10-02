import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lt_dialogue/models/chat_failure.dart';
import 'package:lt_dialogue/services/api_error.dart';
import 'package:lt_dialogue/services/llm_service.dart';

void main() {
  final cases = <(Object, ChatFailureClass)>[
    (const SocketException('reset'), ChatFailureClass.transport),
    (const HandshakeException('TLS failed'), ChatFailureClass.transport),
    (http.ClientException('reset'), ChatFailureClass.transport),
    (TimeoutException('deadline'), ChatFailureClass.timeout),
    (
      LLMStreamTimeoutException(LLMStreamTimeoutPhase.idle),
      ChatFailureClass.timeout
    ),
    (ApiError.fromHttpStatus(401), ChatFailureClass.authentication),
    (ApiError.fromHttpStatus(429), ChatFailureClass.rateLimit),
    (ApiError.fromHttpStatus(503), ChatFailureClass.server),
    (ApiError.fromHttpStatus(504), ChatFailureClass.server),
    (ApiError.fromHttpStatus(501), ChatFailureClass.server),
    (ApiError.fromHttpStatus(422), ChatFailureClass.invalidRequest),
    (ApiError.fromHttpStatus(400), ChatFailureClass.invalidRequest),
    (ApiError.fromHttpStatus(403), ChatFailureClass.invalidRequest),
    (ApiError.fromHttpStatus(404), ChatFailureClass.invalidRequest),
    (StateError('connection timeout in consumer'), ChatFailureClass.internal),
    (RangeError('internal'), ChatFailureClass.internal),
    (const FormatException('decode'), ChatFailureClass.contentInvalid),
    (const GenerationCancelledException(), ChatFailureClass.cancelled),
    (
      LLMResponseIncompleteException(const LLMStreamResult(
          content: '',
          finishReason: LLMFinishReason.unknown,
          responseCompleted: false)),
      ChatFailureClass.protocolIncomplete
    ),
  ];
  for (final (error, expected) in cases) {
    test('${error.runtimeType} maps to ${expected.name}', () {
      expect(ChatFailureClass.classify(error), expected);
      if (expected != ChatFailureClass.transport) {
        expect(ChatFailureClass.classify(error).presentationType,
            isNot('network'));
      }
    });
  }
  test(
      'exception wrapping preserves transport cause and refuses internal retry',
      () {
    const socket = SocketException('reset');
    final wrapped = ApiError.fromException(socket);
    expect(wrapped.cause, same(socket));
    expect(wrapped.type, ApiErrorType.networkUnavailable);
    expect(wrapped.shouldRetry, isTrue);
    final internal = StateError('connection timeout');
    final failure = ApiError.fromException(internal);
    expect(failure.cause, same(internal));
    expect(failure.shouldRetry, isFalse);
    expect(ChatFailureClass.classify(failure), ChatFailureClass.internal);
  });
  test('subrequests share one cancellation authority without sharing identity',
      () async {
    final turn = GenerationTaskHandle(taskId: 'scene-1', generationEpoch: 1);
    final stage = turn.forRequest('scene-1:stage2');
    final settlement = turn.forRequest('scene-1:settlement');
    var cancelled = 0;
    stage.registerCancel(() => cancelled++);
    settlement.registerCancel(() => cancelled++);
    expect(stage.taskId, turn.taskId);
    expect(stage.requestId, 'scene-1:stage2');
    expect(settlement.requestId, 'scene-1:settlement');
    await turn.cancel();
    expect(cancelled, 2);
    expect(stage.isCancelled, isTrue);
    expect(settlement.activeCancelRequestCount, 0);
    expect(GenerationTaskHandle().requestId, isNotEmpty);
  });
}
