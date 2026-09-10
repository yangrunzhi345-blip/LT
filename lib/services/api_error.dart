enum ApiErrorType {
  networkTimeout,
  rateLimited,
  unauthorized,
  serverError,
  invalidRequest,
  unknown,
}

class ApiError implements Exception {
  final ApiErrorType type;
  final String message;
  final int? httpStatus;
  final int retryAfterMs;

  const ApiError({
    required this.type,
    required this.message,
    this.httpStatus,
    this.retryAfterMs = 2000,
  });

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
            type: ApiErrorType.invalidRequest,
            message: detail != null
                ? 'API 账户余额不足 ($detail)'
                : 'API 账户余额不足 (Insufficient Balance)，请前往开放平台充值',
            httpStatus: status);
      case 404:
        return ApiError(
            type: ApiErrorType.invalidRequest,
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

  factory ApiError.fromException(dynamic e) {
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
      return ApiError(
          type: ApiErrorType.networkTimeout,
          message: msg.length > 200 ? msg.substring(0, 200) : msg);
    }
    return ApiError(
        type: ApiErrorType.unknown,
        message: msg.length > 200 ? msg.substring(0, 200) : msg);
  }

  bool get shouldRetry =>
      type == ApiErrorType.networkTimeout ||
      type == ApiErrorType.serverError ||
      type == ApiErrorType.rateLimited;

  String get userMessage => switch (type) {
        ApiErrorType.networkTimeout => '网络超时，正在重试...',
        ApiErrorType.rateLimited => '请求频繁，${retryAfterMs ~/ 1000}秒后重试',
        ApiErrorType.unauthorized => 'API Key 无效，请在设置中重新配置',
        ApiErrorType.serverError => '服务器错误，正在重试...',
        ApiErrorType.invalidRequest => '请求格式错误',
        ApiErrorType.unknown => message,
      };

  @override
  String toString() => '$type: $message';
}

/// Bounded retry budget for one structured (JSON) generation stage.
///
/// Both counts **include the first call**, so `transportAttempts: 2` means the
/// transport may be tried twice (exactly one real retry) and
/// `contentStageAttempts: 3` means the stage runner may re-request up to three
/// times. Keeping the two budgets separate makes the worst case auditable
/// instead of hiding it behind an ambiguous `maxRetries` constant.
class RetryBudget {
  /// Total transport attempts for a single request (>= 1).
  final int transportAttempts;

  /// Total content attempts at the stage layer, including the first (>= 1).
  final int contentStageAttempts;

  const RetryBudget({
    required this.transportAttempts,
    required this.contentStageAttempts,
  })  : assert(transportAttempts >= 1),
        assert(contentStageAttempts >= 1);

  /// Budget for the detailed-character structured JSON stages.
  static const structuredJson = RetryBudget(
    transportAttempts: 2,
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
