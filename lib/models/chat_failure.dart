import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../services/api_error.dart';
import '../services/llm_service.dart';

/// Stable failure classes for a logical chat turn and its subrequests.
enum ChatFailureClass {
  transport,
  timeout,
  authentication,
  rateLimit,
  server,
  invalidRequest,
  protocolIncomplete,
  contentInvalid,
  internal,
  cancelled,
  stale;

  String get presentationType => switch (this) {
        transport => 'network',
        timeout => 'timeout',
        authentication => 'auth',
        rateLimit => 'rate',
        server || invalidRequest => 'api',
        protocolIncomplete || contentInvalid => 'generation',
        internal => 'internal',
        cancelled || stale => 'cancelled',
      };

  static ChatFailureClass classify(Object error) => switch (error) {
        GenerationCancelledException() => cancelled,
        LLMResponseIncompleteException() => protocolIncomplete,
        TimeoutException() => timeout,
        SocketException() ||
        TlsException() ||
        http.ClientException() =>
          transport,
        ApiError(:final type) => switch (type) {
            ApiErrorType.networkUnavailable => transport,
            ApiErrorType.networkTimeout => timeout,
            ApiErrorType.unauthorized => authentication,
            ApiErrorType.rateLimited => rateLimit,
            ApiErrorType.serverError => server,
            ApiErrorType.paymentRequired ||
            ApiErrorType.forbidden ||
            ApiErrorType.notFound ||
            ApiErrorType.invalidRequest =>
              invalidRequest,
            ApiErrorType.unknown => internal,
          },
        FormatException() => contentInvalid,
        _ => internal,
      };
}
