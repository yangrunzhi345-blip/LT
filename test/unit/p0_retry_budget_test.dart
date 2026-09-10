import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/services/ai_generator_service.dart';
import 'package:lt_dialogue/services/api_error.dart';
import 'package:lt_dialogue/services/llm_service.dart';

String _long(String text, {int times = 12}) =>
    List<String>.filled(times, text).join();

ApiError _retryable({int retryAfterMs = 0}) => ApiError(
      type: ApiErrorType.serverError,
      message: 'server down',
      httpStatus: 500,
      retryAfterMs: retryAfterMs,
    );

class _FakeLlmService extends LLMService {
  _FakeLlmService(this.respond)
      : super(const LLMConfig(
          provider: LLMProvider.deepseek,
          apiKey: 'test-key',
          baseUrl: 'https://example.invalid',
          model: 'test',
        ));

  final Future<String> Function(String prompt) respond;
  final List<String> prompts = [];

  @override
  Future<LLMStreamResult> sendMessageStreamDetailed(
    List<Map<String, String>> messages,
    void Function(String chunk) onChunk,
    void Function() onDone, {
    void Function(String reasoningChunk)? onReasoningChunk,
    CompletionParams params = const CompletionParams(),
    GenerationTaskHandle? taskHandle,
  }) async {
    final prompt = messages.last['content'] ?? '';
    prompts.add(prompt);
    final response = await respond(prompt);
    onChunk(response);
    return LLMStreamResult(
      content: response,
      finishReason: LLMFinishReason.stop,
      responseCompleted: true,
    );
  }
}

const _identityMarker = '提炼或设计角色的核心身份定位';

void main() {
  group('RetryManager attempts semantics', () {
    test('maximumAttempts counts the first call (1 attempt, no retry)',
        () async {
      var calls = 0;
      await expectLater(
        RetryManager.withRetry<void>(
          () async {
            calls++;
            throw _retryable();
          },
          maximumAttempts: 1,
          shouldRetry: (error) => TransportRetryPolicy.shouldRetry(error),
          delay: (_) async {},
        ),
        throwsA(isA<ApiError>()),
      );
      expect(calls, 1);
    });

    test('maximumAttempts: 2 performs exactly one retry', () async {
      var calls = 0;
      final delays = <Duration>[];
      await expectLater(
        RetryManager.withRetry<void>(
          () async {
            calls++;
            throw _retryable();
          },
          maximumAttempts: 2,
          shouldRetry: (error) => TransportRetryPolicy.shouldRetry(error),
          delay: (duration) async => delays.add(duration),
        ),
        throwsA(isA<ApiError>()),
      );
      expect(calls, 2);
      expect(delays, [const Duration(milliseconds: 1000)]);
    });

    test('recovers on the third attempt with capped exponential backoff',
        () async {
      var calls = 0;
      final delays = <Duration>[];
      final value = await RetryManager.withRetry<int>(
        () async {
          calls++;
          if (calls < 3) throw _retryable();
          return 7;
        },
        maximumAttempts: 3,
        shouldRetry: (error) => TransportRetryPolicy.shouldRetry(error),
        delay: (duration) async => delays.add(duration),
      );
      expect(value, 7);
      expect(calls, 3);
      expect(delays, [
        const Duration(milliseconds: 1000),
        const Duration(milliseconds: 2000),
      ]);
    });

    test('honours retryAfterMs for a 429', () async {
      final delays = <Duration>[];
      var calls = 0;
      await expectLater(
        RetryManager.withRetry<void>(
          () async {
            calls++;
            throw const ApiError(
              type: ApiErrorType.rateLimited,
              message: 'slow down',
              httpStatus: 429,
              retryAfterMs: 5000,
            );
          },
          maximumAttempts: 2,
          delay: (duration) async => delays.add(duration),
        ),
        throwsA(isA<ApiError>()),
      );
      expect(calls, 2);
      expect(delays, [const Duration(milliseconds: 6000)]);
    });

    test('does not retry a non-retryable 4xx', () async {
      var calls = 0;
      await expectLater(
        RetryManager.withRetry<void>(
          () async {
            calls++;
            throw ApiError.fromHttpStatus(400, 'bad request');
          },
          maximumAttempts: 3,
          delay: (_) async {},
        ),
        throwsA(isA<ApiError>()),
      );
      expect(calls, 1);
    });
  });

  group('TransportRetryPolicy classification', () {
    test('retries transient transport failures only', () {
      expect(
          TransportRetryPolicy.shouldRetry(ApiError.networkTimeout()), isTrue);
      expect(
        TransportRetryPolicy.shouldRetry(ApiError.fromHttpStatus(429, null)),
        isTrue,
      );
      expect(
        TransportRetryPolicy.shouldRetry(ApiError.fromHttpStatus(503, null)),
        isTrue,
      );
      expect(
        TransportRetryPolicy.shouldRetry(ApiError.fromHttpStatus(400, null)),
        isFalse,
      );
      expect(
        TransportRetryPolicy.shouldRetry(ApiError.fromHttpStatus(401, null)),
        isFalse,
      );
    });

    test('never treats content failures or cancellation as transport', () {
      expect(
        TransportRetryPolicy.shouldRetry(
          StateError(AiGeneratorService.structuredJsonFailureMessage),
        ),
        isFalse,
      );
      expect(
        TransportRetryPolicy.shouldRetry(const GenerationCancelledException()),
        isFalse,
      );
      expect(
        TransportRetryPolicy.shouldRetry(
          const StructuredOutputIncompleteException(),
        ),
        isFalse,
      );
    });
  });

  group('Stage budgets', () {
    test('structuredJson budget is transport=2, content=3', () {
      expect(RetryBudget.structuredJson.transportAttempts, 2);
      expect(RetryBudget.structuredJson.contentStageAttempts, 3);
      expect(RetryManager.maximumAttempts, 3);
    });

    test('a schema-invalid stage uses exactly three content attempts',
        () async {
      final fake = _FakeLlmService((prompt) async {
        // Valid JSON, but missing every required identity field.
        return jsonEncode({'unrelated': 'value'});
      });

      await expectLater(
        AiGeneratorService(fake).textToDetailedCharacterCard('艾莉诺亚'),
        throwsA(isA<FormatException>()),
      );
      expect(fake.prompts.where((p) => p.contains(_identityMarker)).length, 3);
    });

    test('a transient transport error is retried within one content attempt',
        () async {
      var identityCalls = 0;
      final fake = _FakeLlmService((prompt) async {
        if (prompt.contains(_identityMarker)) {
          identityCalls++;
          if (identityCalls == 1) throw _retryable();
          return jsonEncode({
            'name': '艾莉诺亚',
            'gender': '女',
            'age': '22',
            'profession': '学者',
            'personality': _long('她克制而执着。'),
          });
        }
        if (prompt.contains('外貌肖像与身材体格特征')) {
          return jsonEncode({
            'appearance': _long('银色长发。'),
            'bodyDescription': _long('高挑。'),
          });
        }
        return jsonEncode({
          'description': _long('生平。'),
          'faction': '遗民会',
          'home_location': '档案库',
          'public_goal': _long('目标。'),
          'hidden_motivation': _long('动机。'),
        });
      });

      final result = await AiGeneratorService(fake)
          .textToDetailedCharacterCard('艾莉诺亚，叛逃学者');

      expect(identityCalls, 2);
      expect(result['name'], '艾莉诺亚');
    });
  });
}
