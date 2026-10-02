import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'api_error.dart';
import '../core/debug/generation_diagnostics.dart';
import 'generation_request_scheduler.dart';
import '../models/completion_params.dart';
import '../models/generation_task_handle.dart';
import '../models/llm_message.dart';
import '../models/llm_provider.dart';
import '../models/model_capabilities.dart';
import '../utils/ai_adventure_utils.dart';

export '../models/llm_provider.dart' show LLMProvider;
export '../models/generation_task_handle.dart';

class GenerationCancelledException implements Exception {
  const GenerationCancelledException();

  @override
  String toString() => '生成任务已取消';
}

enum LLMFinishReason {
  stop('stop'),
  completed('completed'),
  length('length'),
  maxTokens('maxTokens'),
  contentFilter('contentFilter'),
  toolCall('toolCall'),
  cancelled('cancelled'),
  interrupted('interrupted'),
  error('error'),
  unknown('unknown');

  const LLMFinishReason(this.stableValue);

  final String stableValue;

  bool get allowsParsing => this == stop || this == completed;

  bool get isTruncated => this == length || this == maxTokens;

  static LLMFinishReason fromProvider(Object? value) {
    return switch (value?.toString().trim().toLowerCase()) {
      'stop' => stop,
      'completed' || 'complete' => completed,
      'end_turn' || 'endturn' => completed,
      'length' => length,
      'max_tokens' || 'maxtokens' || 'max_output_tokens' => maxTokens,
      'stop_sequence' => stop,
      'content_filter' || 'contentfilter' || 'safety' => contentFilter,
      'tool_calls' || 'tool_call' || 'function_call' => toolCall,
      'cancelled' || 'canceled' => cancelled,
      'interrupted' => interrupted,
      'error' => error,
      _ => unknown,
    };
  }
}

class LLMStreamResult {
  final String content;
  final String? reasoningContent;
  final LLMFinishReason finishReason;
  final bool responseCompleted;
  final int? promptTokens;
  final int? completionTokens;
  final int? promptCacheHitTokens;
  final int? promptCacheMissTokens;
  final int malformedEventCount;

  const LLMStreamResult({
    required this.content,
    this.reasoningContent,
    required this.finishReason,
    required this.responseCompleted,
    this.promptTokens,
    this.completionTokens,
    this.promptCacheHitTokens,
    this.promptCacheMissTokens,
    this.malformedEventCount = 0,
  });
}

/// A response ended without a usable completion contract.
///
/// Extending StateError preserves the legacy text API's rejection contract;
/// the typed marker lets chat distinguish protocol failure from processing.
class LLMResponseIncompleteException extends StateError {
  LLMResponseIncompleteException(this.result)
      : super('Model response did not complete');

  final LLMStreamResult result;
}

/// A completed response contains reasoning but no narrative output.
final class ReasoningOnlyResponseException implements Exception {
  const ReasoningOnlyResponseException(this.result);

  final LLMStreamResult result;

  static bool matches(LLMStreamResult result) =>
      result.responseCompleted &&
      (result.finishReason == LLMFinishReason.stop ||
          result.finishReason == LLMFinishReason.length ||
          result.finishReason == LLMFinishReason.maxTokens) &&
      (result.reasoningContent?.trim().isNotEmpty ?? false) &&
      result.content.trim().isEmpty;

  @override
  String toString() =>
      'ReasoningOnlyResponseException(${result.finishReason.stableValue})';
}

class LLMStreamRetryPolicy {
  const LLMStreamRetryPolicy._();

  static bool shouldRetry(Object error, {required bool receivedAnyDelta}) {
    if (error is GenerationCancelledException || receivedAnyDelta) return false;
    return error is ApiError && error.shouldRetry;
  }
}

/// Payload-free metadata for one actual HTTP attempt.
final class _LLMAttemptTrace {
  _LLMAttemptTrace(this.details);

  final Map<String, Object?> details;
  int contentChars = 0;
  int reasoningChars = 0;
  int contentDeltas = 0;
  int reasoningDeltas = 0;
  bool firstEvent = false;
  bool doneMarker = false;
  LLMFinishReason finishReason = LLMFinishReason.unknown;
  final Stopwatch clock = Stopwatch()..start();
  int? firstReasoningMs;
  int? lastReasoningMs;
  int? firstContentMs;
  int? lastContentMs;
  int wireContentChars = 0;
  int wireReasoningChars = 0;
  int messageContentChars = 0;
  final Set<String> contentValueTypes = {};
  final Set<String> reasoningValueTypes = {};
  bool? streamClosedNormally;

  void providerChoice(Map<String, dynamic> choice) {
    final delta = choice['delta'];
    if (delta is Map<String, dynamic>) {
      final content = delta['content'];
      final reasoning = delta['reasoning_content'] ?? delta['reasoning'];
      if (content != null) {
        contentValueTypes.add(content.runtimeType.toString());
      }
      if (reasoning != null) {
        reasoningValueTypes.add(reasoning.runtimeType.toString());
      }
      if (content is String) wireContentChars += content.length;
      if (reasoning is String) wireReasoningChars += reasoning.length;
    }
    final message = choice['message'];
    if (message is Map<String, dynamic>) {
      final content = message['content'];
      if (content is String) messageContentChars += content.length;
    }
  }

  void mark(String event, [Map<String, Object?> extra = const {}]) {
    GenerationDiagnostics.instance.mark('[LLM][$event]', {
      ...details,
      'elapsedMs': clock.elapsedMilliseconds,
      ...extra,
    });
  }

  void delta(String chunk, {required bool reasoning}) {
    final now = clock.elapsedMilliseconds;
    if (reasoning) {
      if (reasoningDeltas++ == 0) mark('FIRST_REASONING');
      firstReasoningMs ??= now;
      lastReasoningMs = now;
      reasoningChars += chunk.length;
    } else {
      if (contentDeltas++ == 0) mark('FIRST_CONTENT');
      firstContentMs ??= now;
      lastContentMs = now;
      contentChars += chunk.length;
    }
  }

  Map<String, Object?> snapshot() => {
        'contentDeltas': contentDeltas,
        'reasoningDeltas': reasoningDeltas,
        'contentChars': contentChars,
        'reasoningChars': reasoningChars,
        'firstReasoningMs': firstReasoningMs,
        'lastReasoningMs': lastReasoningMs,
        'firstContentMs': firstContentMs,
        'lastContentMs': lastContentMs,
        'finishReason': finishReason.stableValue,
        'doneMarker': doneMarker,
        'wireContentChars': wireContentChars,
        'wireReasoningChars': wireReasoningChars,
        'messageContentChars': messageContentChars,
        'contentValueTypes': contentValueTypes.toList(),
        'reasoningValueTypes': reasoningValueTypes.toList(),
        'streamClosedNormally': streamClosedNormally,
      };
}

/// Which phase of the streaming request produced a timeout (R04-A).
enum LLMStreamTimeoutPhase {
  /// `client.send(request)` did not return in time.
  connect,

  /// HTTP headers returned but the SSE stream produced no event in time.
  firstEvent,

  /// The stream started but stopped producing transport events.
  idle,

  /// The whole request exceeded its maximum lifetime - this is what
  /// terminates a stream a server keeps alive forever.
  overall;

  String get displayLabel => switch (this) {
        LLMStreamTimeoutPhase.connect => '连接',
        LLMStreamTimeoutPhase.firstEvent => '首事件',
        LLMStreamTimeoutPhase.idle => '流空闲',
        LLMStreamTimeoutPhase.overall => '整体',
      };
}

/// Typed transport timeout (R04-A). Extends [ApiError] as a network timeout so
/// the pre-delta retry policy keeps working, while carrying the phase for
/// diagnostics and tests.
class LLMStreamTimeoutException extends ApiError {
  LLMStreamTimeoutException(this.phase)
      : super(
          type: ApiErrorType.networkTimeout,
          message: 'LLM 流式请求超时（${phase.displayLabel}）',
        );

  final LLMStreamTimeoutPhase phase;
}

/// A provider event whose JSON could not be decoded or whose shape does not
/// match the provider contract. Internal marker: the streaming loops translate
/// it into `malformedEventCount++` - never into a swallowed consumer error.
class _MalformedProviderEvent implements Exception {
  const _MalformedProviderEvent();
}

/// Marks an exception thrown by a consumer callback (onChunk /
/// onReasoningChunk / downstream parser / validator) so the streaming error
/// boundary rethrows it VERBATIM instead of wrapping it into an ApiError as if
/// it were a transport failure (R04-C / M10).
class _ConsumerException implements Exception {
  _ConsumerException(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

void _runConsumer(void Function() callback) {
  try {
    callback();
  } catch (error, stackTrace) {
    Error.throwWithStackTrace(
        _ConsumerException(error, stackTrace), stackTrace);
  }
}

/// SSE gate instrumentation (P0): the `eventGate` StreamController between the
/// upstream SSE listener and the `await for` consumer is a producer/consumer
/// pair with no backpressure visibility. These counters make any sustained
/// "SSE producer >>> Dart consumer" backlog measurable on a real device.
mixin _SseGateTrace {
  int _sseReceived = 0;
  int _sseProcessed = 0;

  void traceSseReceived() {
    if (!GenerationDiagnostics.enabled) return;
    _sseReceived++;
    GenerationDiagnostics.instance
      ..runtimeHeartbeat('llm.sseLine')
      ..counter('sse.received')
      ..observeMax('sse.maxPending', _sseReceived - _sseProcessed);
  }

  void traceSseProcessed() {
    if (!GenerationDiagnostics.enabled) return;
    _sseProcessed++;
    GenerationDiagnostics.instance.counter('sse.processed');
  }
}

/// One decoded OpenAI-compatible SSE `data:` payload, with everything the
/// streaming loop needs to run its consumer callbacks outside any decode
/// error handling.
final class _OpenAiSseEvent {
  const _OpenAiSseEvent({
    this.promptTokens,
    this.completionTokens,
    this.promptCacheHitTokens,
    this.promptCacheMissTokens,
    this.finishReason,
    this.reasoningDelta,
    this.content,
  });

  final int? promptTokens;
  final int? completionTokens;
  final int? promptCacheHitTokens;
  final int? promptCacheMissTokens;
  final LLMFinishReason? finishReason;
  final String? reasoningDelta;
  final String? content;
}

/// Transport timeout policy for one streaming request (R04-A).
///
/// The LLM transport layer is the single owner of streaming timeouts: neither
/// the UI, the coordinator nor AiGeneratorService maintains its own. The four
/// windows cover every hang shape: never-connecting send, headers-without-
/// events, a stalled stream and a server that keeps the connection alive
/// forever. Durations are constructor-injectable so tests can drive timeouts
/// deterministically without wall-clock waits on production values.
class LLMStreamTimeoutPolicy {
  const LLMStreamTimeoutPolicy({
    this.connect = const Duration(seconds: 30),
    this.firstEvent = const Duration(seconds: 90),
    this.idle = const Duration(seconds: 120),
    this.overall = const Duration(minutes: 10),
  });

  static const standard = LLMStreamTimeoutPolicy();

  /// Time allowed for `client.send(request)` to return response headers.
  final Duration connect;

  /// Time allowed for the first SSE event after the headers arrived.
  final Duration firstEvent;

  /// Maximum gap between two transport events once the stream has started.
  final Duration idle;

  /// Maximum lifetime of the whole request, keepalives included.
  final Duration overall;
}

class LLMConfig {
  final LLMProvider provider;
  final String apiKey;
  final String baseUrl;
  final String model;

  const LLMConfig({
    required this.provider,
    required this.apiKey,
    required this.baseUrl,
    required this.model,
  });
}

class LLMService with _SseGateTrace {
  LLMService(
    this.config, {
    this.timeoutPolicy = LLMStreamTimeoutPolicy.standard,
    http.Client Function()? clientFactory,
    @visibleForTesting Future<void> Function(Duration duration)? retryDelay,
    @visibleForTesting bool? forceAnthropicMessagesApi,
  })  : _clientFactory = clientFactory ?? http.Client.new,
        _retryDelay = retryDelay,
        anthropicMessagesApiOverride = forceAnthropicMessagesApi;

  final LLMConfig config;

  /// Transport timeout ownership (R04-A). Injected so tests can use very short
  /// deterministic windows instead of production wall-clock values.
  final LLMStreamTimeoutPolicy timeoutPolicy;

  /// Seam for tests to install a fake [http.Client] against the real
  /// streaming code path.
  final http.Client Function() _clientFactory;

  /// Test seam for the transport retry backoff; production uses real delays.
  final Future<void> Function(Duration duration)? _retryDelay;

  /// Test seam for the Anthropic messages branch: no built-in provider
  /// selects it today, but its failure semantics must stay symmetric with
  /// the OpenAI-compatible branch (R04-C).
  final bool? anthropicMessagesApiOverride;

  /// Request shaping (thinking protocol, sampling rules) is driven by the
  /// model capability, not by comparing model-name strings.
  late final ModelCapabilities _capabilities =
      ModelCapabilityRegistry.resolve(config.model);

  /// 设置页在保存前使用的临时连接测试入口。界面层不直接管理 HTTP
  /// 客户端或端点拼接，全部委托给 LLM 通信模块。
  static Future<bool> testConfiguration(LLMConfig config) =>
      LLMService(config).testConnection();

  /// 自定义兼容接口既常见填写根地址，也常见直接填写 `/v1`。内置服务
  /// 商的 [LLMProvider.defaultBaseUrl] 已包含其官方版本路径，绝不能在
  /// 这里再拼接或替换。
  Uri _apiUri(String path) {
    var base = config.baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (config.provider == LLMProvider.custom &&
        base.isNotEmpty &&
        !base.endsWith('/v1')) {
      base = '$base/v1';
    }
    return Uri.parse('$base$path');
  }

  Future<String> sendMessageStream(
    List<Map<String, String>> messages,
    void Function(String chunk) onChunk,
    void Function() onDone, {
    void Function(String reasoningChunk)? onReasoningChunk,
    CompletionParams params = const CompletionParams(),
    GenerationTaskHandle? taskHandle,
  }) async {
    // Delegate through the legacy detailed seam so existing subclasses that
    // override `sendMessageStreamDetailed` keep intercepting text callers.
    final result = await sendMessageStreamDetailed(
      messages,
      onChunk,
      onDone,
      onReasoningChunk: onReasoningChunk,
      params: params,
      taskHandle: taskHandle,
    );
    // An incomplete response must never be handed back as if it were complete.
    // The previous code salvaged a repairable JSON prefix here, but a closing
    // brace only proves the prefix is syntactically recoverable, not that the
    // model emitted every field. Structured callers resolve through
    // AiGeneratorService._resolveContent, which rejects truncated output at the
    // stage boundary; this generic text API now rejects it outright instead of
    // leaking a half-written object to the caller.
    if (!result.responseCompleted ||
        !result.finishReason.allowsParsing ||
        result.finishReason.isTruncated) {
      throw LLMResponseIncompleteException(result);
    }
    return result.content;
  }

  /// Typed counterpart of [sendMessageStream]. Prefer this for new call sites:
  /// it can express reasoning, tool calls and image blocks directly.
  Future<String> sendMessageStreamTyped(
    List<LlmMessage> messages,
    void Function(String chunk) onChunk,
    void Function() onDone, {
    void Function(String reasoningChunk)? onReasoningChunk,
    CompletionParams params = const CompletionParams(),
    GenerationTaskHandle? taskHandle,
  }) async {
    final result = await sendMessageStreamDetailedTyped(
      messages,
      onChunk,
      onDone,
      onReasoningChunk: onReasoningChunk,
      params: params,
      taskHandle: taskHandle,
    );
    if (!result.responseCompleted ||
        !result.finishReason.allowsParsing ||
        result.finishReason.isTruncated) {
      throw LLMResponseIncompleteException(result);
    }
    return result.content;
  }

  Future<LLMStreamResult> sendMessageStreamDetailed(
    List<Map<String, String>> messages,
    void Function(String chunk) onChunk,
    void Function() onDone, {
    void Function(String reasoningChunk)? onReasoningChunk,
    CompletionParams params = const CompletionParams(),
    GenerationTaskHandle? taskHandle,
  }) {
    return sendMessageStreamDetailedTyped(
      LlmMessageAdapter.fromLegacy(messages),
      onChunk,
      onDone,
      onReasoningChunk: onReasoningChunk,
      params: params,
      taskHandle: taskHandle,
    );
  }

  Future<LLMStreamResult> sendMessageStreamDetailedTyped(
    List<LlmMessage> messages,
    void Function(String chunk) onChunk,
    void Function() onDone, {
    void Function(String reasoningChunk)? onReasoningChunk,
    CompletionParams params = const CompletionParams(),
    GenerationTaskHandle? taskHandle,
  }) {
    var acceptedContent = false;
    var acceptedReasoning = false;
    var consumerFailed = false;
    void acceptConsumer(void Function() callback) {
      try {
        callback();
      } catch (_) {
        consumerFailed = true;
        rethrow;
      }
    }

    var attempt = 0;
    return RetryManager.withRetry(
      () => GenerationRequestScheduler.shared.schedule(
        providerId: config.provider.name,
        request: () async {
          final trace = _LLMAttemptTrace({
            'turnRequest': taskHandle?.taskId,
            'subRequest': taskHandle?.requestId,
            'generation': taskHandle?.generationEpoch,
            'attempt': ++attempt,
            'maximumAttempts': RetryManager.maximumAttempts,
            'provider': config.provider.name,
            'model': config.model,
          });
          trace.mark('ATTEMPT_START');
          try {
            final result = await _doSendMessageStreamDetailed(
              messages,
              (chunk) {
                // R04-B: the flag flips only AFTER the consumer accepted the
                // delta. A consumer/parser exception must propagate as an error,
                // never be misreported as "content was already received".
                // Consumer failures are independently excluded from retries.
                acceptConsumer(() => onChunk(chunk));
                acceptedContent = true;
              },
              () => acceptConsumer(onDone),
              onReasoningChunk: onReasoningChunk == null
                  ? null
                  : (chunk) {
                      acceptConsumer(() => onReasoningChunk(chunk));
                      acceptedReasoning = true;
                    },
              params: params,
              taskHandle: taskHandle,
              trace: trace,
            );
            trace.mark('ATTEMPT_DONE', {
              ...trace.snapshot(),
              'responseCompleted': result.responseCompleted,
              'resultFinishReason': result.finishReason.stableValue,
              'malformedEvents': result.malformedEventCount,
              'promptTokens': result.promptTokens,
              'completionTokens': result.completionTokens,
            });
            return result;
          } catch (error, stackTrace) {
            final retry = !consumerFailed &&
                attempt < RetryManager.maximumAttempts &&
                taskHandle?.isCancelled != true &&
                LLMStreamRetryPolicy.shouldRetry(error,
                    receivedAnyDelta: acceptedContent || acceptedReasoning);
            trace.mark('ATTEMPT_FAILED', {
              ...trace.snapshot(),
              'runtimeType': error.runtimeType.toString(),
              if (error is ApiError && error.cause != null)
                'causeType': error.cause.runtimeType.toString(),
              'failureClass': consumerFailed
                  ? 'internal'
                  : error is ApiError
                      ? error.code.name
                      : error is GenerationCancelledException
                          ? 'cancelled'
                          : 'internal',
              'acceptedContent': acceptedContent,
              'acceptedReasoning': acceptedReasoning,
              'retryDecision': retry,
              'retryReason': consumerFailed
                  ? 'consumer-failed'
                  : taskHandle?.isCancelled == true
                      ? 'cancelled'
                      : acceptedContent
                          ? 'content-already-emitted'
                          : acceptedReasoning
                              ? 'visible-reasoning-already-emitted'
                              : attempt >= RetryManager.maximumAttempts
                                  ? 'max-attempts'
                                  : retry
                                      ? 'no-visible-output'
                                      : 'non-retryable-error',
              'stackTrace': stackTrace,
            });
            rethrow;
          }
        },
      ),
      shouldRetry: (error) =>
          !consumerFailed &&
          taskHandle?.isCancelled != true &&
          LLMStreamRetryPolicy.shouldRetry(
            error,
            receivedAnyDelta: acceptedContent || acceptedReasoning,
          ),
      delay: _retryDelay,
    );
  }

  Future<LLMStreamResult> _doSendMessageStreamDetailed(
    List<LlmMessage> messages,
    void Function(String chunk) onChunk,
    void Function() onDone, {
    void Function(String reasoningChunk)? onReasoningChunk,
    CompletionParams params = const CompletionParams(),
    GenerationTaskHandle? taskHandle,
    required _LLMAttemptTrace trace,
  }) async {
    final useAnthropicMessagesApi = anthropicMessagesApiOverride ??
        config.provider.usesAnthropicMessagesApi;
    return useAnthropicMessagesApi
        ? _doSendAnthropicStreamDetailed(
            messages,
            onChunk,
            onDone,
            params: params,
            taskHandle: taskHandle,
            trace: trace,
          )
        : _doSendOpenAICompatibleStreamDetailed(
            messages,
            onChunk,
            onDone,
            onReasoningChunk: onReasoningChunk,
            params: params,
            taskHandle: taskHandle,
            trace: trace,
          );
  }

  Future<bool> testConnection() async {
    final result = await sendMessageStreamDetailed(
      const [
        {'role': 'user', 'content': 'Hi'},
      ],
      (_) {},
      () {},
      params: const CompletionParams(
        maxTokens: 16,
        enableThinking: false,
      ),
    );
    if (!result.responseCompleted &&
        !result.finishReason.allowsParsing &&
        result.finishReason != LLMFinishReason.length) {
      throw StateError('模型连接未完整完成');
    }
    return true;
  }

  Map<String, String> _buildHeaders({required bool includeJson}) {
    final headers = <String, String>{};
    if (includeJson) headers['Content-Type'] = 'application/json';
    if (config.provider.usesAnthropicMessagesApi) {
      headers['x-api-key'] = config.apiKey;
      headers['anthropic-version'] = '2023-06-01';
    } else {
      headers['Authorization'] = 'Bearer ${config.apiKey}';
    }
    return headers;
  }

  Future<LLMStreamResult> _doSendOpenAICompatibleStreamDetailed(
    List<LlmMessage> messages,
    void Function(String chunk) onChunk,
    void Function() onDone, {
    void Function(String reasoningChunk)? onReasoningChunk,
    CompletionParams params = const CompletionParams(),
    GenerationTaskHandle? taskHandle,
    required _LLMAttemptTrace trace,
  }) async {
    final uri = _apiUri(config.provider.chatCompletionsPath);
    final request = http.Request('POST', uri);
    request.headers.addAll(_buildHeaders(includeJson: true));

    final sanitized = messages.map(_toOpenAiWireMessage).toList();
    final wireParams = params.toRequestMap(capabilities: _capabilities);
    final thinking = wireParams['thinking'];
    trace.mark('REQUEST_SHAPE', {
      'model': config.model,
      'max_tokens': wireParams['max_tokens'],
      'thinking.type':
          thinking is Map<String, dynamic> ? thinking['type'] : null,
      'reasoning_effort': wireParams['reasoning_effort'],
      'response_format_present': wireParams.containsKey('response_format'),
      'temperature_present': wireParams.containsKey('temperature'),
      'top_p_present': wireParams.containsKey('top_p'),
    });

    try {
      request.body = jsonEncode({
        'model': config.model,
        'messages': sanitized,
        ...wireParams,
        'stream': true,
      });
    } catch (_) {
      throw const ApiError(
          type: ApiErrorType.invalidRequest, message: '消息包含无法编码的字符');
    }

    return _sendOpenAICompatibleStream(request, onChunk, onDone,
        onReasoningChunk: onReasoningChunk,
        taskHandle: taskHandle,
        trace: trace);
  }

  /// Builds the OpenAI-compatible wire message, sanitizing text content while
  /// leaving image parts untouched.
  Map<String, dynamic> _toOpenAiWireMessage(LlmMessage message) {
    final map = message.toWireMap();
    final content = map['content'];
    if (content is String) {
      map['content'] = AiAdventureUtils.sanitizeForJson(content);
    } else if (content is List) {
      map['content'] = [
        for (final part in content)
          if (part is Map<String, dynamic> && part['type'] == 'text')
            {
              ...part,
              'text': AiAdventureUtils.sanitizeForJson(
                  part['text']?.toString() ?? ''),
            }
          else
            part,
      ];
    }
    return map;
  }

  /// Decodes one OpenAI-compatible SSE `data:` payload. Throws
  /// [_MalformedProviderEvent] for undecodable JSON or an unexpected shape -
  /// provider problems only, never consumer failures. Returns null for
  /// keepalive/usage-only events that carry no choices.
  _OpenAiSseEvent? _parseOpenAiSseEvent(String data, _LLMAttemptTrace trace) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(data);
    } catch (_) {
      throw const _MalformedProviderEvent();
    }
    if (decoded is! Map<String, dynamic>) {
      throw const _MalformedProviderEvent();
    }

    int? usageField(Map<Object?, Object?> usage, String key) =>
        int.tryParse(usage[key]?.toString() ?? '');

    int? promptTokens;
    int? completionTokens;
    int? promptCacheHitTokens;
    int? promptCacheMissTokens;
    final usage = decoded['usage'];
    if (usage is Map) {
      promptTokens = usageField(usage, 'prompt_tokens');
      completionTokens = usageField(usage, 'completion_tokens');
      promptCacheHitTokens = usageField(usage, 'prompt_cache_hit_tokens');
      promptCacheMissTokens = usageField(usage, 'prompt_cache_miss_tokens');
    }

    final choices = decoded['choices'];
    // Usage-only / keepalive shaped events legitimately carry no choices.
    if (choices == null || (choices is List && choices.isEmpty)) return null;
    if (choices is! List) throw const _MalformedProviderEvent();
    final choice = choices.first;
    if (choice is! Map<String, dynamic>) throw const _MalformedProviderEvent();
    trace.providerChoice(choice);

    final providerReason = choice['finish_reason'];
    final delta = choice['delta'];
    String? reasoningDelta;
    String? content;
    if (delta != null) {
      if (delta is! Map<String, dynamic>) throw const _MalformedProviderEvent();
      final rawReasoning = delta['reasoning_content'] ?? delta['reasoning'];
      final rawContent = delta['content'];
      if ((rawReasoning != null && rawReasoning is! String) ||
          (rawContent != null && rawContent is! String)) {
        throw const _MalformedProviderEvent();
      }
      reasoningDelta = rawReasoning;
      content = rawContent;
    }
    return _OpenAiSseEvent(
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      promptCacheHitTokens: promptCacheHitTokens,
      promptCacheMissTokens: promptCacheMissTokens,
      finishReason: providerReason == null
          ? null
          : LLMFinishReason.fromProvider(providerReason),
      reasoningDelta: reasoningDelta,
      content: content,
    );
  }

  Future<LLMStreamResult> _sendOpenAICompatibleStream(
    http.Request request,
    void Function(String chunk) onChunk,
    void Function() onDone, {
    void Function(String reasoningChunk)? onReasoningChunk,
    GenerationTaskHandle? taskHandle,
    required _LLMAttemptTrace trace,
  }) async {
    trace.mark('ENDPOINT',
        {'endpointHost': request.url.host, 'endpointPath': request.url.path});
    final client = _clientFactory();
    final policy = timeoutPolicy;
    final cancelled = Completer<void>();
    final cancellation = taskHandle?.registerCancel(() {
      client.close();
      if (!cancelled.isCompleted) cancelled.complete();
    });
    if (taskHandle?.isCancelled == true) {
      client.close();
      throw const GenerationCancelledException();
    }
    final startedAt = DateTime.now();
    try {
      http.StreamedResponse streamedResponse;
      try {
        // R04-A: the connect phase can never hang forever.
        streamedResponse = await Future.any<http.StreamedResponse>([
          client.send(request).timeout(policy.connect),
          cancelled.future.then<http.StreamedResponse>(
              (_) => throw const GenerationCancelledException()),
        ]);
      } on TimeoutException {
        // A cancellation closes the client mid-send; report that instead of
        // masquerading it as a timeout.
        if (taskHandle?.isCancelled == true) {
          throw const GenerationCancelledException();
        }
        throw LLMStreamTimeoutException(LLMStreamTimeoutPhase.connect);
      } catch (e, st) {
        if (taskHandle?.isCancelled == true) {
          throw const GenerationCancelledException();
        }
        Error.throwWithStackTrace(ApiError.fromException(e), st);
      }
      trace.mark('HEADERS', {'httpStatus': streamedResponse.statusCode});
      if (streamedResponse.statusCode != 200) {
        final errorBody = await streamedResponse.stream.bytesToString();
        String? detailMsg;
        try {
          final errJson = jsonDecode(errorBody);
          if (errJson is Map && errJson['error'] is Map) {
            detailMsg = errJson['error']['message']?.toString();
          } else if (errJson is Map && errJson['message'] != null) {
            detailMsg = errJson['message']?.toString();
          }
        } catch (_) {
          if (errorBody.isNotEmpty && errorBody.length < 300) {
            detailMsg = errorBody;
          }
        }
        throw ApiError.fromHttpStatus(streamedResponse.statusCode, detailMsg);
      }

      final buffer = StringBuffer();
      final reasoningBuffer = StringBuffer();
      var finishReason = LLMFinishReason.unknown;
      var responseCompleted = false;
      var malformedEventCount = 0;
      var receivedFirstEvent = false;
      int? promptTokens;
      int? completionTokens;
      int? promptCacheHitTokens;
      int? promptCacheMissTokens;

      // R04-A: idle/first-event ownership. The timeout watches transport
      // activity only - any event (keepalive included) resets it - while the
      // overall deadline below is what terminates a stream a server keeps
      // alive forever.
      final eventGate = StreamController<String>();
      final streamCancellation = taskHandle?.registerCancel(() {
        if (!eventGate.isClosed) {
          eventGate.addError(const GenerationCancelledException());
        }
      });
      final remainingOverall =
          policy.overall - DateTime.now().difference(startedAt);
      final overallDeadline = Timer(
          remainingOverall.isNegative ? Duration.zero : remainingOverall, () {
        if (!eventGate.isClosed) {
          eventGate.addError(
              LLMStreamTimeoutException(LLMStreamTimeoutPhase.overall));
        }
      });
      Timer? watchdog;
      void resetWatchdog() {
        watchdog?.cancel();
        watchdog = Timer(
          receivedFirstEvent ? policy.idle : policy.firstEvent,
          () {
            if (taskHandle?.isCancelled == true) {
              eventGate.addError(const GenerationCancelledException());
              return;
            }
            if (DateTime.now().difference(startedAt) >= policy.overall) {
              eventGate.addError(
                  LLMStreamTimeoutException(LLMStreamTimeoutPhase.overall));
              return;
            }
            eventGate.addError(LLMStreamTimeoutException(
              receivedFirstEvent
                  ? LLMStreamTimeoutPhase.idle
                  : LLMStreamTimeoutPhase.firstEvent,
            ));
          },
        );
      }

      final upstreamSubscription = streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (!trace.firstEvent) {
            trace.firstEvent = true;
            trace.mark('FIRST_EVENT');
          }
          receivedFirstEvent = true;
          resetWatchdog();
          traceSseReceived();
          eventGate.add(line);
        },
        onError: (Object error, StackTrace stackTrace) {
          trace.streamClosedNormally = false;
          watchdog?.cancel();
          eventGate.addError(error, stackTrace);
        },
        onDone: () {
          trace.streamClosedNormally ??= taskHandle?.isCancelled != true;
          watchdog?.cancel();
          trace.mark('STREAM_CLOSED', trace.snapshot());
          eventGate.close();
        },
      );
      resetWatchdog();

      try {
        await for (final chunk in eventGate.stream) {
          traceSseProcessed();
          if (taskHandle?.isCancelled == true) {
            throw const GenerationCancelledException();
          }
          receivedFirstEvent = true;
          if (DateTime.now().difference(startedAt) >= policy.overall) {
            throw LLMStreamTimeoutException(LLMStreamTimeoutPhase.overall);
          }
          if (!chunk.startsWith('data: ')) continue;
          final data = chunk.substring(6);
          if (data == '[DONE]') {
            trace.doneMarker = true;
            trace.mark('DONE');
            responseCompleted = true;
            break;
          }

          // R04-C: provider decode/shape problems end here as a counted,
          // skipped malformed event. The consumer callbacks below live
          // OUTSIDE this catch: an exception thrown by onChunk, a downstream
          // parser or a validator propagates to the caller instead of being
          // misreported as provider noise.
          final _OpenAiSseEvent? event;
          try {
            event = _parseOpenAiSseEvent(data, trace);
          } on _MalformedProviderEvent {
            malformedEventCount++;
            continue;
          }
          // Usage-only / keepalive event: never a content delta.
          if (event == null) continue;
          if (event.promptTokens != null) promptTokens = event.promptTokens;
          if (event.completionTokens != null) {
            completionTokens = event.completionTokens;
          }
          if (event.promptCacheHitTokens != null) {
            promptCacheHitTokens = event.promptCacheHitTokens;
          }
          if (event.promptCacheMissTokens != null) {
            promptCacheMissTokens = event.promptCacheMissTokens;
          }
          if (event.finishReason != null) {
            finishReason = event.finishReason!;
            trace.finishReason = finishReason;
          }
          final reasoningDelta = event.reasoningDelta;
          if (reasoningDelta != null && reasoningDelta.isNotEmpty) {
            reasoningBuffer.write(reasoningDelta);
            trace.delta(reasoningDelta, reasoning: true);
            if (taskHandle?.isCancelled != true) {
              final callback = onReasoningChunk;
              if (callback != null) {
                _runConsumer(() => callback(reasoningDelta));
              }
            }
          }
          final content = event.content;
          if (content != null &&
              content.isNotEmpty &&
              taskHandle?.isCancelled != true) {
            buffer.write(content);
            trace.delta(content, reasoning: false);
            _runConsumer(() => onChunk(content));
          }
        }
      } catch (e, st) {
        if (e is _ConsumerException) {
          // R04-C: a consumer/parser/validator failure reaches the caller
          // exactly as thrown - never rebranded as a transport error and
          // never counted as a malformed provider event.
          Error.throwWithStackTrace(e.error, e.stackTrace);
        }
        if (e is GenerationCancelledException ||
            e is LLMStreamTimeoutException) {
          rethrow;
        }
        if (taskHandle?.isCancelled == true) {
          throw const GenerationCancelledException();
        }
        Error.throwWithStackTrace(ApiError.fromException(e), st);
      } finally {
        streamCancellation?.dispose();
        overallDeadline.cancel();
        watchdog?.cancel();
        unawaited(upstreamSubscription.cancel());
        unawaited(eventGate.close());
      }

      if (taskHandle?.isCancelled == true) {
        throw const GenerationCancelledException();
      }
      if (finishReason == LLMFinishReason.stop ||
          finishReason == LLMFinishReason.completed ||
          finishReason == LLMFinishReason.length ||
          finishReason == LLMFinishReason.maxTokens) {
        responseCompleted = true;
      }
      if (responseCompleted) onDone();
      if (!responseCompleted) {
        finishReason = taskHandle?.isCancelled == true
            ? LLMFinishReason.cancelled
            : LLMFinishReason.interrupted;
      }
      if (finishReason == LLMFinishReason.unknown) {
        finishReason = responseCompleted
            ? LLMFinishReason.completed
            : LLMFinishReason.interrupted;
      }
      return LLMStreamResult(
        content: buffer.toString(),
        reasoningContent:
            reasoningBuffer.isNotEmpty ? reasoningBuffer.toString() : null,
        finishReason: finishReason,
        responseCompleted: responseCompleted,
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        promptCacheHitTokens: promptCacheHitTokens,
        promptCacheMissTokens: promptCacheMissTokens,
        malformedEventCount: malformedEventCount,
      );
    } finally {
      cancellation?.dispose();
      client.close();
    }
  }

  Future<LLMStreamResult> _doSendAnthropicStreamDetailed(
    List<LlmMessage> messages,
    void Function(String chunk) onChunk,
    void Function() onDone, {
    CompletionParams params = const CompletionParams(),
    GenerationTaskHandle? taskHandle,
    required _LLMAttemptTrace trace,
  }) async {
    final uri = _apiUri(config.provider.chatCompletionsPath);
    final request = http.Request('POST', uri);
    request.headers.addAll(_buildHeaders(includeJson: true));

    final systemPrompt = _extractAnthropicSystemPrompt(messages);
    final anthropicMessages = messages
        .where((message) => message.role != LlmRole.system)
        .map((message) => {
              'role': message.role == LlmRole.assistant ? 'assistant' : 'user',
              'content': message.joinedText,
            })
        .toList();

    try {
      request.body = jsonEncode({
        'model': config.model,
        'messages': anthropicMessages,
        'max_tokens': params.maxTokens,
        if (systemPrompt != null && systemPrompt.isNotEmpty)
          'system': systemPrompt,
        'temperature': params.temperature,
        'top_p': params.topP,
        'stream': true,
      });
    } catch (_) {
      throw const ApiError(
          type: ApiErrorType.invalidRequest, message: '消息包含无法编码的字符');
    }

    trace.mark('ENDPOINT',
        {'endpointHost': request.url.host, 'endpointPath': request.url.path});
    final client = _clientFactory();
    final policy = timeoutPolicy;
    final cancelled = Completer<void>();
    final cancellation = taskHandle?.registerCancel(() {
      client.close();
      if (!cancelled.isCompleted) cancelled.complete();
    });
    if (taskHandle?.isCancelled == true) {
      client.close();
      throw const GenerationCancelledException();
    }
    final startedAt = DateTime.now();

    try {
      http.StreamedResponse streamedResponse;
      try {
        // R04-A: connect timeout, symmetric with the OpenAI branch.
        streamedResponse = await Future.any<http.StreamedResponse>([
          client.send(request).timeout(policy.connect),
          cancelled.future.then<http.StreamedResponse>(
              (_) => throw const GenerationCancelledException()),
        ]);
      } on TimeoutException {
        if (taskHandle?.isCancelled == true) {
          throw const GenerationCancelledException();
        }
        throw LLMStreamTimeoutException(LLMStreamTimeoutPhase.connect);
      } catch (e, st) {
        if (taskHandle?.isCancelled == true) {
          throw const GenerationCancelledException();
        }
        Error.throwWithStackTrace(ApiError.fromException(e), st);
      }
      trace.mark('HEADERS', {'httpStatus': streamedResponse.statusCode});
      if (streamedResponse.statusCode != 200) {
        throw ApiError.fromHttpStatus(streamedResponse.statusCode);
      }

      final buffer = StringBuffer();
      var finishReason = LLMFinishReason.unknown;
      var responseCompleted = false;
      var malformedEventCount = 0;
      var receivedFirstEvent = false;
      int? promptTokens;
      int? completionTokens;
      String? currentEvent;
      final dataBuffer = StringBuffer();

      /// Decodes one buffered SSE event into its outcome. Throws
      /// [_MalformedProviderEvent] for provider decode/shape problems only -
      /// the consumer callback below runs outside that error ownership.
      ({
        String? contentDelta,
        LLMFinishReason? finishReason,
        int? inputTokens,
        int? outputTokens,
        bool completed,
      })? decodeAnthropicEvent(String eventName, String data) {
        final dynamic decoded;
        try {
          decoded = jsonDecode(data);
        } catch (_) {
          throw const _MalformedProviderEvent();
        }
        if (decoded is! Map<String, dynamic>) {
          throw const _MalformedProviderEvent();
        }
        if (eventName == 'content_block_delta') {
          final delta = decoded['delta'];
          if (delta is! Map<String, dynamic>) {
            throw const _MalformedProviderEvent();
          }
          if (delta['type']?.toString() == 'text_delta') {
            return (
              contentDelta: delta['text']?.toString() ?? '',
              finishReason: null,
              inputTokens: null,
              outputTokens: null,
              completed: false,
            );
          }
          return (
            contentDelta: null,
            finishReason: null,
            inputTokens: null,
            outputTokens: null,
            completed: false,
          );
        }
        if (eventName == 'message_delta') {
          final delta = decoded['delta'];
          final providerReason = delta is Map
              ? (delta['stop_reason'] ?? decoded['stop_reason'])
              : decoded['stop_reason'];
          int? inputTokens;
          int? outputTokens;
          final usage = decoded['usage'];
          if (usage is Map) {
            inputTokens = int.tryParse(usage['input_tokens']?.toString() ?? '');
            outputTokens =
                int.tryParse(usage['output_tokens']?.toString() ?? '');
          }
          return (
            contentDelta: null,
            finishReason: providerReason == null
                ? null
                : LLMFinishReason.fromProvider(providerReason),
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            completed: false,
          );
        }
        if (eventName == 'message_stop') {
          return (
            contentDelta: null,
            finishReason: null,
            inputTokens: null,
            outputTokens: null,
            completed: true,
          );
        }
        return null;
      }

      /// decodeAnthropicEvent plus the malformed-event policy: provider
      /// decode/shape problems are counted and skipped, never propagated as
      /// transport failures (R04-C).
      ({
        String? contentDelta,
        LLMFinishReason? finishReason,
        int? inputTokens,
        int? outputTokens,
        bool completed
      })? decodeAnthropicEventWithPolicy(String eventName, String data) {
        try {
          return decodeAnthropicEvent(eventName, data);
        } on _MalformedProviderEvent {
          malformedEventCount++;
          return null;
        }
      }

      void flushEvent() {
        if (currentEvent == null || dataBuffer.isEmpty) return;
        final eventName = currentEvent!;
        final data = dataBuffer.toString();
        currentEvent = null;
        dataBuffer.clear();

        final decodedEvent = decodeAnthropicEventWithPolicy(eventName, data);
        if (decodedEvent == null) return;

        // Consumer/finish handling lives outside the decode error ownership.
        final contentDelta = decodedEvent.contentDelta;
        if (contentDelta != null &&
            contentDelta.isNotEmpty &&
            taskHandle?.isCancelled != true) {
          buffer.write(contentDelta);
          trace.delta(contentDelta, reasoning: false);
          _runConsumer(() => onChunk(contentDelta));
        }
        if (decodedEvent.finishReason != null) {
          finishReason = decodedEvent.finishReason!;
          trace.finishReason = finishReason;
        }
        if (decodedEvent.inputTokens != null) {
          promptTokens ??= decodedEvent.inputTokens;
        }
        if (decodedEvent.outputTokens != null) {
          completionTokens ??= decodedEvent.outputTokens;
        }
        if (decodedEvent.completed) {
          responseCompleted = true;
          trace.doneMarker = true;
          trace.mark('DONE');
        }
      }

      final eventGate = StreamController<String>();
      final streamCancellation = taskHandle?.registerCancel(() {
        if (!eventGate.isClosed) {
          eventGate.addError(const GenerationCancelledException());
        }
      });
      final remainingOverall =
          policy.overall - DateTime.now().difference(startedAt);
      final overallDeadline = Timer(
          remainingOverall.isNegative ? Duration.zero : remainingOverall, () {
        if (!eventGate.isClosed) {
          eventGate.addError(
              LLMStreamTimeoutException(LLMStreamTimeoutPhase.overall));
        }
      });
      Timer? watchdog;
      void resetWatchdog() {
        watchdog?.cancel();
        watchdog = Timer(
          receivedFirstEvent ? policy.idle : policy.firstEvent,
          () {
            if (taskHandle?.isCancelled == true) {
              eventGate.addError(const GenerationCancelledException());
              return;
            }
            if (DateTime.now().difference(startedAt) >= policy.overall) {
              eventGate.addError(
                  LLMStreamTimeoutException(LLMStreamTimeoutPhase.overall));
              return;
            }
            eventGate.addError(LLMStreamTimeoutException(
              receivedFirstEvent
                  ? LLMStreamTimeoutPhase.idle
                  : LLMStreamTimeoutPhase.firstEvent,
            ));
          },
        );
      }

      final upstreamSubscription = streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (!trace.firstEvent) {
            trace.firstEvent = true;
            trace.mark('FIRST_EVENT');
          }
          receivedFirstEvent = true;
          resetWatchdog();
          traceSseReceived();
          eventGate.add(line);
        },
        onError: (Object error, StackTrace stackTrace) {
          watchdog?.cancel();
          eventGate.addError(error, stackTrace);
        },
        onDone: () {
          watchdog?.cancel();
          trace.mark('STREAM_CLOSED', trace.snapshot());
          eventGate.close();
        },
      );
      resetWatchdog();

      try {
        await for (final line in eventGate.stream) {
          traceSseProcessed();
          if (taskHandle?.isCancelled == true) {
            throw const GenerationCancelledException();
          }
          receivedFirstEvent = true;
          if (DateTime.now().difference(startedAt) >= policy.overall) {
            throw LLMStreamTimeoutException(LLMStreamTimeoutPhase.overall);
          }
          if (line.isEmpty) {
            flushEvent();
            continue;
          }
          if (line.startsWith('event:')) {
            flushEvent();
            currentEvent = line.substring(6).trim();
            continue;
          }
          if (line.startsWith('data:')) {
            dataBuffer.write(dataBuffer.isEmpty
                ? line.substring(5).trimLeft()
                : '\n${line.substring(5).trimLeft()}');
          }
        }
        flushEvent();
      } catch (e, st) {
        if (e is _ConsumerException) {
          Error.throwWithStackTrace(e.error, e.stackTrace);
        }
        if (e is GenerationCancelledException ||
            e is LLMStreamTimeoutException) {
          rethrow;
        }
        if (taskHandle?.isCancelled == true) {
          throw const GenerationCancelledException();
        }
        Error.throwWithStackTrace(ApiError.fromException(e), st);
      } finally {
        streamCancellation?.dispose();
        overallDeadline.cancel();
        watchdog?.cancel();
        unawaited(upstreamSubscription.cancel());
        unawaited(eventGate.close());
      }

      if (taskHandle?.isCancelled == true) {
        throw const GenerationCancelledException();
      }
      if (finishReason == LLMFinishReason.stop ||
          finishReason == LLMFinishReason.completed ||
          finishReason == LLMFinishReason.length ||
          finishReason == LLMFinishReason.maxTokens) {
        responseCompleted = true;
      }
      if (responseCompleted) onDone();
      if (!responseCompleted) {
        finishReason = taskHandle?.isCancelled == true
            ? LLMFinishReason.cancelled
            : LLMFinishReason.interrupted;
      }
      if (finishReason == LLMFinishReason.unknown) {
        finishReason = responseCompleted
            ? LLMFinishReason.completed
            : LLMFinishReason.interrupted;
      }
      return LLMStreamResult(
        content: buffer.toString(),
        finishReason: finishReason,
        responseCompleted: responseCompleted,
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        malformedEventCount: malformedEventCount,
      );
    } finally {
      cancellation?.dispose();
      client.close();
    }
  }

  String? _extractAnthropicSystemPrompt(List<LlmMessage> messages) {
    final systemMessages = messages
        .where((message) => message.role == LlmRole.system)
        .map((message) => message.joinedText.trim())
        .where((content) => content.isNotEmpty)
        .toList();
    if (systemMessages.isEmpty) return null;
    return systemMessages.join('\n\n');
  }
}
