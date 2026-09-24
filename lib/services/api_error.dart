import '../domain/errors/app_error.dart';

enum ApiErrorType {
  networkTimeout,
  rateLimited,
  unauthorized,
  paymentRequired,
  forbidden,
  notFound,
  serverError,
  invalidRequest,
  unknown,
}

class ApiError implements Exception {
  final ApiErrorType type;

  /// Legacy diagnostic accessor. Never use this value as UI copy.
  final String message;
  final int? httpStatus;
  final int retryAfterMs;

  const ApiError({
    required this.type,
    required this.message,
    this.httpStatus,
    this.retryAfterMs = 2000,
  });

  AppErrorCode get code => switch (type) {
        ApiErrorType.networkTimeout => AppErrorCode.timeout,
        ApiErrorType.rateLimited => AppErrorCode.rateLimited,
        ApiErrorType.unauthorized => AppErrorCode.unauthorized,
        ApiErrorType.paymentRequired => AppErrorCode.paymentRequired,
        ApiErrorType.forbidden => AppErrorCode.forbidden,
        ApiErrorType.notFound => AppErrorCode.notFound,
        ApiErrorType.serverError => AppErrorCode.serverError,
        ApiErrorType.invalidRequest => AppErrorCode.invalidRequest,
        ApiErrorType.unknown => AppErrorCode.unknown,
      };

  AppDomainError toDomainError() => AppDomainError(
        code: code,
        parameters: <String, Object?>{
          if (httpStatus != null) 'httpStatus': httpStatus,
          'retryAfterMs': retryAfterMs,
        },
        debugMessage: message,
        cause: this,
      );

  factory ApiError.fromHttpStatus(int status, [String? detailMessage]) {
    final detail = detailMessage != null && detailMessage.trim().isNotEmpty
        ? detailMessage.trim()
        : null;
    switch (status) {
      case 401:
        return ApiError(
            type: ApiErrorType.unauthorized,
            message:
                detail != null ? 'API Key 无效或未授权 ($detail)' : 'API Key 无效或已过期',
            httpStatus: status);
      case 402:
        return ApiError(
            type: ApiErrorType.paymentRequired,
            message: detail != null
                ? 'API 账户余额不足 ($detail)'
                : 'API 账户余额不足 (Insufficient Balance)，请前往开放平台充值',
            httpStatus: status);
      case 404:
        return ApiError(
            type: ApiErrorType.notFound,
            message: detail != null
                ? '请求的模型或接口端点不存在 ($detail)'
                : '请求的模型或接口端点不存在 (HTTP 404)',
            httpStatus: status);
      case 429:
        return ApiError(
            type: ApiErrorType.rateLimited,
            message: detail != null ? '请求过于频繁 ($detail)' : '请求过于频繁，请稍后再试',
            httpStatus: status,
            retryAfterMs: 5000);
      case 403:
        return ApiError(
            type: ApiErrorType.forbidden,
            message: detail != null ? 'access denied' : 'access denied',
            httpStatus: status);
      case 500:
      case 502:
      case 503:
        return ApiError(
            type: ApiErrorType.serverError,
            message: detail != null ? '服务暂时不可用 ($detail)' : '服务器暂时不可用',
            httpStatus: status,
            retryAfterMs: 3000);
      case 400:
        return ApiError(
            type: ApiErrorType.invalidRequest,
            message: detail != null ? '请求参数有误 ($detail)' : '请求参数有误',
            httpStatus: status);
      default:
        return ApiError(
            type: ApiErrorType.unknown,
            message: detail != null
                ? 'HTTP $status 错误 ($detail)'
                : '未知错误 HTTP $status',
            httpStatus: status);
    }
  }

  factory ApiError.networkTimeout() {
    return const ApiError(type: ApiErrorType.networkTimeout, message: '网络请求超时');
  }

  factory ApiError.fromException(Object e) {
    if (e is ApiError) return e;
    final msg = e.toString();
    if (msg.contains('timeout') || msg.contains('Timeout')) {
      return ApiError.networkTimeout();
    }
    // SocketException, HttpException, TlsException 等网络异常应视为可重试
    if (msg.contains('SocketException') ||
        msg.contains('Connection') ||
        msg.contains('HttpException') ||
        msg.contains('TlsException') ||
        msg.contains('HandshakeException')) {
      return const ApiError(
          type: ApiErrorType.networkTimeout,
          message: 'network transport failure');
    }
    return const ApiError(
        type: ApiErrorType.unknown, message: 'unclassified API failure');
  }

  bool get shouldRetry =>
      type == ApiErrorType.networkTimeout ||
      type == ApiErrorType.serverError ||
      type == ApiErrorType.rateLimited;

  /// Legacy compatibility value. Presentation must use [toDomainError].
  @Deprecated('Use toDomainError and localizeAppError in presentation.')
  String get userMessage => message;

  @override
  String toString() => '$type: $message';
}

/// Bounded retry budget for one structured (JSON) generation stage.
///
/// R04-B: transport retry has a single owner - the LLM streaming layer
/// (`LLMService`, maximum 3 attempts including the first, suppressed once a
/// content delta was accepted). This budget therefore only counts the
/// content-stage re-requests. The worst case per stage stays auditable:
/// `contentStageAttempts x LLMService transport attempts` = 3 x 3 = 9 HTTP
/// requests, never a hidden multiplication of nested retry loops.
class RetryBudget {
  /// Total content attempts at the stage layer, including the first (>= 1).
  final int contentStageAttempts;

  const RetryBudget({required this.contentStageAttempts})
      : assert(contentStageAttempts >= 1);

  /// Budget for the detailed-character structured JSON stages.
  static const structuredJson = RetryBudget(
    contentStageAttempts: 3,
  );
}

class RetryManager {
  /// Total attempts, **including the first call**.
  ///
  /// This is deliberately not called `maxRetries`: the previous name implied
  /// "extra retries", but the loop counted the first call as an attempt, so
  /// `maxRetries: 1` silently meant "no retries at all". Callers must now read
  /// and pass attempt counts explicitly.
  static const maximumAttempts = 3;
  static const baseDelayMs = 1000;

  static Future<T> withRetry<T>(
    Future<T> Function() operation, {
    int maximumAttempts = maximumAttempts,
    bool Function(dynamic error)? shouldRetry,
    // Test seam for the backoff wait; production uses Future.delayed.
    Future<void> Function(Duration duration)? delay,
  }) async {
    final wait =
        delay ?? ((Duration duration) => Future<void>.delayed(duration));
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        return await operation();
      } catch (e) {
        if (attempt >= maximumAttempts) rethrow;
        final err = e is ApiError ? e : ApiError.fromException(e);
        final retry = shouldRetry?.call(e) ?? err.shouldRetry;
        if (!retry) rethrow;
        await wait(
            Duration(milliseconds: baseDelayMs * attempt + err.retryAfterMs));
      }
    }
  }
}

/// Classifies whether an error is a transient **transport** failure.
///
/// Only timeouts, 429, 5xx, connection resets and handshake failures qualify.
/// Content failures (empty / invalid / truncated JSON, schema or semantic
/// violations) are deliberately excluded so they are never retried as if they
/// were a network blip; they are handled by the caller's own content budget.
/// Cancellation is excluded by the caller, which knows the generation handle.
abstract final class TransportRetryPolicy {
  static bool shouldRetry(Object error) {
    if (error is ApiError) return error.shouldRetry;
    return ApiError.fromException(error).shouldRetry;
  }
}
