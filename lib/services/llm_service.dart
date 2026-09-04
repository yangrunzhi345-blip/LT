import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_error.dart';
import 'generation_request_scheduler.dart';
import '../models/completion_params.dart';
import '../models/generation_task_handle.dart';
import '../models/llm_provider.dart';
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
  final int malformedEventCount;

  const LLMStreamResult({
    required this.content,
    this.reasoningContent,
    required this.finishReason,
    required this.responseCompleted,
    this.promptTokens,
    this.completionTokens,
    this.malformedEventCount = 0,
  });
}

class LLMStreamRetryPolicy {
  const LLMStreamRetryPolicy._();

  static bool shouldRetry(Object error, {required bool receivedAnyDelta}) {
    if (error is GenerationCancelledException || receivedAnyDelta) return false;
    return error is ApiError && error.shouldRetry;
  }
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

class LLMService {
  final LLMConfig config;

  LLMService(this.config);

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
    final result = await sendMessageStreamDetailed(
      messages,
      onChunk,
      onDone,
      onReasoningChunk: onReasoningChunk,
      params: params,
      taskHandle: taskHandle,
    );
    if (!result.responseCompleted || !result.finishReason.allowsParsing) {
      throw StateError('模型响应未完整完成，不能使用部分结果');
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
    var receivedAnyDelta = false;
    return RetryManager.withRetry(
      () => GenerationRequestScheduler.shared.schedule(
        providerId: config.provider.name,
        request: () => _doSendMessageStreamDetailed(
          messages,
          (chunk) {
            receivedAnyDelta = true;
            onChunk(chunk);
          },
          onDone,
          onReasoningChunk: onReasoningChunk,
          params: params,
          taskHandle: taskHandle,
        ),
      ),
      shouldRetry: (error) => LLMStreamRetryPolicy.shouldRetry(
        error,
        receivedAnyDelta: receivedAnyDelta,
      ),
    );
  }

  Future<LLMStreamResult> _doSendMessageStreamDetailed(
    List<Map<String, String>> messages,
    void Function(String chunk) onChunk,
    void Function() onDone, {
    void Function(String reasoningChunk)? onReasoningChunk,
    CompletionParams params = const CompletionParams(),
    GenerationTaskHandle? taskHandle,
  }) async {
    return config.provider.usesAnthropicMessagesApi
        ? _doSendAnthropicStreamDetailed(
            messages,
            onChunk,
            onDone,
            params: params,
            taskHandle: taskHandle,
          )
        : _doSendOpenAICompatibleStreamDetailed(
            messages,
            onChunk,
            onDone,
            onReasoningChunk: onReasoningChunk,
            params: params,
            taskHandle: taskHandle,
          );
  }

  Future<bool> testConnection() async {
    final result = await sendMessageStreamDetailed(
      const [
        {'role': 'user', 'content': 'Reply with OK.'},
      ],
      (_) {},
      () {},
      params: const CompletionParams(maxTokens: 8, temperature: 0),
    );
    if (!result.responseCompleted || !result.finishReason.allowsParsing) {
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
    List<Map<String, String>> messages,
    void Function(String chunk) onChunk,
    void Function() onDone, {
    void Function(String reasoningChunk)? onReasoningChunk,
    CompletionParams params = const CompletionParams(),
    GenerationTaskHandle? taskHandle,
  }) async {
    final uri = _apiUri(config.provider.chatCompletionsPath);
    final request = http.Request('POST', uri);
    request.headers.addAll(_buildHeaders(includeJson: true));

    final sanitized = messages.map((m) {
      final role = m['role'];
      final content = m['content'] ?? '';
      if (content.trim().startsWith('[')) {
        try {
          final parsed = jsonDecode(content);
          return {'role': role, 'content': parsed};
        } catch (_) {}
      }
      return {
        'role': role,
        'content': AiAdventureUtils.sanitizeForJson(content),
      };
    }).toList();

    final isDeepSeek = config.provider == LLMProvider.deepseek;
    try {
      request.body = jsonEncode({
        'model': config.model,
        'messages': sanitized,
        ...params.toRequestMap(isDeepSeek: isDeepSeek, model: config.model),
        'stream': true,
      });
    } catch (_) {
      throw const ApiError(
          type: ApiErrorType.invalidRequest, message: '消息包含无法编码的字符');
    }

    return _sendOpenAICompatibleStream(request, onChunk, onDone,
        onReasoningChunk: onReasoningChunk,
        taskHandle: taskHandle);
  }

  Future<LLMStreamResult> _sendOpenAICompatibleStream(
    http.Request request,
    void Function(String chunk) onChunk,
    void Function() onDone, {
    void Function(String reasoningChunk)? onReasoningChunk,
    GenerationTaskHandle? taskHandle,
  }) async {
    final client = http.Client();
    final cancellation = taskHandle?.registerCancel(client.close);
    if (taskHandle?.isCancelled == true) {
      client.close();
      throw const GenerationCancelledException();
    }
    try {
      final streamedResponse = await client.send(request);
      if (streamedResponse.statusCode != 200) {
        throw ApiError.fromHttpStatus(streamedResponse.statusCode);
      }

      final buffer = StringBuffer();
      final reasoningBuffer = StringBuffer();
      var finishReason = LLMFinishReason.unknown;
      var responseCompleted = false;
      var malformedEventCount = 0;
      int? promptTokens;
      int? completionTokens;
      try {
        await for (final chunk in streamedResponse.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          if (taskHandle?.isCancelled == true) {
            throw const GenerationCancelledException();
          }
          if (!chunk.startsWith('data: ')) continue;
          final data = chunk.substring(6);
          if (data == '[DONE]') {
            responseCompleted = true;
            break;
          }
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final usage = json['usage'];
            if (usage is Map) {
              promptTokens =
                  int.tryParse(usage['prompt_tokens']?.toString() ?? '');
              completionTokens =
                  int.tryParse(usage['completion_tokens']?.toString() ?? '');
            }
            final choices = json['choices'] as List<dynamic>?;
            if (choices == null || choices.isEmpty) continue;
            final choice = choices[0] as Map<String, dynamic>?;
            final providerReason = choice?['finish_reason'];
            if (providerReason != null) {
              finishReason = LLMFinishReason.fromProvider(providerReason);
            }
            final delta = choice?['delta'] as Map<String, dynamic>?;
            // 抓取 DeepSeek 官方思考模式思维链 delta
            final reasoningDelta =
                (delta?['reasoning_content'] ?? delta?['reasoning']) as String?;
            if (reasoningDelta != null && reasoningDelta.isNotEmpty) {
              reasoningBuffer.write(reasoningDelta);
              if (taskHandle?.isCancelled != true) {
                onReasoningChunk?.call(reasoningDelta);
              }
            }
            final content = delta?['content'] as String?;
            if (content != null &&
                content.isNotEmpty &&
                taskHandle?.isCancelled != true) {
              buffer.write(content);
              onChunk(content);
            }
          } catch (_) {
            malformedEventCount++;
          }
        }
      } catch (e) {
        if (e is GenerationCancelledException) rethrow;
        throw ApiError.fromException(e);
      }

      if (taskHandle?.isCancelled == true) {
        throw const GenerationCancelledException();
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
        malformedEventCount: malformedEventCount,
      );
    } finally {
      cancellation?.dispose();
      client.close();
    }
  }

  Future<LLMStreamResult> _doSendAnthropicStreamDetailed(
    List<Map<String, String>> messages,
    void Function(String chunk) onChunk,
    void Function() onDone, {
    CompletionParams params = const CompletionParams(),
    GenerationTaskHandle? taskHandle,
  }) async {
    final uri = _apiUri(config.provider.chatCompletionsPath);
    final request = http.Request('POST', uri);
    request.headers.addAll(_buildHeaders(includeJson: true));

    final systemPrompt = _extractAnthropicSystemPrompt(messages);
    final anthropicMessages = messages
        .where((m) => (m['role'] ?? '').trim() != 'system')
        .map((message) => {
              'role': message['role'] == 'assistant' ? 'assistant' : 'user',
              'content': message['content'] ?? '',
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

    final client = http.Client();
    final cancellation = taskHandle?.registerCancel(client.close);
    if (taskHandle?.isCancelled == true) {
      client.close();
      throw const GenerationCancelledException();
    }

    try {
      final streamedResponse = await client.send(request);
      if (streamedResponse.statusCode != 200) {
        throw ApiError.fromHttpStatus(streamedResponse.statusCode);
      }

      final buffer = StringBuffer();
      var finishReason = LLMFinishReason.unknown;
      var responseCompleted = false;
      var malformedEventCount = 0;
      int? promptTokens;
      int? completionTokens;
      String? currentEvent;
      final dataBuffer = StringBuffer();

      void flushEvent() {
        if (currentEvent == null || dataBuffer.isEmpty) return;
        final data = dataBuffer.toString();
        dataBuffer.clear();
        final event = currentEvent;
        currentEvent = null;
        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          if (event == 'content_block_delta') {
            final delta = json['delta'] as Map<String, dynamic>?;
            final deltaType = delta?['type']?.toString();
            if (deltaType == 'text_delta') {
              final content = delta?['text']?.toString() ?? '';
              if (content.isNotEmpty && taskHandle?.isCancelled != true) {
                buffer.write(content);
                onChunk(content);
              }
            }
            return;
          }
          if (event == 'message_delta') {
            final delta = json['delta'] as Map<String, dynamic>?;
            final providerReason = delta?['stop_reason'] ?? json['stop_reason'];
            if (providerReason != null) {
              finishReason = LLMFinishReason.fromProvider(providerReason);
            }
            final usage = json['usage'];
            if (usage is Map) {
              promptTokens ??=
                  int.tryParse(usage['input_tokens']?.toString() ?? '');
              completionTokens ??=
                  int.tryParse(usage['output_tokens']?.toString() ?? '');
            }
            return;
          }
          if (event == 'message_stop') {
            responseCompleted = true;
          }
        } catch (_) {
          malformedEventCount++;
        }
      }

      try {
        await for (final line in streamedResponse.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          if (taskHandle?.isCancelled == true) {
            throw const GenerationCancelledException();
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
      } catch (e) {
        if (e is GenerationCancelledException) rethrow;
        throw ApiError.fromException(e);
      }

      if (taskHandle?.isCancelled == true) {
        throw const GenerationCancelledException();
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

  String? _extractAnthropicSystemPrompt(List<Map<String, String>> messages) {
    final systemMessages = messages
        .where((m) => (m['role'] ?? '').trim() == 'system')
        .map((m) => m['content']?.trim() ?? '')
        .where((content) => content.isNotEmpty)
        .toList();
    if (systemMessages.isEmpty) return null;
    return systemMessages.join('\n\n');
  }
}
