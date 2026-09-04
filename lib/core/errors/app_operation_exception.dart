import '../../utils/sensitive_data_sanitizer.dart';

/// 跨 Repository/Service/UI 的安全失败契约。
class AppOperationException implements Exception {
  final String code;
  final String userMessage;
  final bool recoverable;
  final String diagnostic;

  AppOperationException({
    required this.code,
    required this.userMessage,
    required this.recoverable,
    required String diagnostic,
  }) : diagnostic = sanitizeSensitiveText(diagnostic);

  factory AppOperationException.wrap(
    Object error, {
    required String code,
    required String userMessage,
    bool recoverable = true,
  }) {
    if (error is AppOperationException) return error;
    return AppOperationException(
      code: code,
      userMessage: userMessage,
      recoverable: recoverable,
      diagnostic: error.toString(),
    );
  }

  @override
  String toString() => '$code: $diagnostic';
}
