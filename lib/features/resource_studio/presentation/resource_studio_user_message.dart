import '../../../core/localization/app_error_localizer.dart';
import '../../../domain/errors/app_error.dart';
import '../../../l10n/generated/app_localizations.dart';

/// Converts a typed Studio failure to safe user-facing copy.
///
/// Legacy persisted strings are treated as historical diagnostics and are not
/// parsed as protocol errors.
String resourceStudioUserMessage(Object error, [AppLocalizations? l10n]) {
  if (l10n == null) return 'Operation failed. Please try again.';
  final typed = switch (error) {
    AppDomainError value => value,
    String value => _fromStableCode(value),
    _ => const AppDomainError(code: AppErrorCode.unknown),
  };
  return localizeAppError(l10n, typed);
}

AppDomainError _fromStableCode(String value) {
  final matches = AppErrorCode.values.where((item) => item.name == value);
  return AppDomainError(
    code: matches.isEmpty ? AppErrorCode.unknown : matches.first,
  );
}
