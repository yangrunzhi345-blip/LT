import '../../../core/localization/app_error_localizer.dart';
import '../../../domain/errors/app_error.dart';
import '../../../application/resources/resource_autosave_service.dart';
import '../../../l10n/generated/app_localizations.dart';

/// Converts a typed Studio failure to safe user-facing copy.
///
/// Legacy persisted strings are treated as historical diagnostics and are not
/// parsed as protocol errors.
String resourceStudioUserMessage(Object error, [AppLocalizations? l10n]) {
  if (l10n == null) return 'Operation failed. Please try again.';
  if (error is String &&
      !AppErrorCode.values.any((code) => code.name == error)) {
    // Strings are legacy persisted/result diagnostics. New runtime failures
    // arrive as typed errors and never use this compatibility branch.
    return legacyResourceStudioDiagnostic(error);
  }
  final typed = resourceStudioError(error);
  return localizeAppError(l10n, typed);
}

String localizeAutosaveOutcome(
  AutosaveWriteOutcome outcome,
  AppLocalizations l10n,
) {
  if (outcome.code == AutosaveOutcomeCode.applied &&
      outcome.message.isNotEmpty) {
    return legacyResourceStudioDiagnostic(outcome.message);
  }
  return switch (outcome.code) {
      AutosaveOutcomeCode.sessionClosed => l10n.partEditorResolveConflictFailed(
          l10n.errorUnknown,
        ),
      AutosaveOutcomeCode.localDiscarded => l10n.partEditorDiscardedRemoteText,
      AutosaveOutcomeCode.conflictDetected => l10n.partEditorConflictOtherSaved,
      AutosaveOutcomeCode.missingTarget => l10n.partEditorTargetPartMissing,
      AutosaveOutcomeCode.writeFailed => l10n.resourceErrorGenerationFailed,
      AutosaveOutcomeCode.applied => l10n.partEditorAutoSaved(
          l10n.autosaveTriggerManual,
        ),
    };
}

/// Classifies a runtime failure without parsing its human-facing text.
/// Unknown and legacy persisted diagnostics intentionally become generic.
AppDomainError resourceStudioError(Object error) => switch (error) {
      AppDomainError value => value,
      String value => _fromStableCode(value),
      _ => const AppDomainError(code: AppErrorCode.unknown),
    };

/// Legacy diagnostic projection retained only for old state getters/tests.
/// Production widgets must render the typed [resourceStudioError] instead.
@Deprecated('Use resourceStudioError and localizeAppError for presentation.')
String legacyResourceStudioDiagnostic(Object error) {
  var message = error.toString().trim().replaceFirst(
        RegExp(r'^(?:Bad state|StateError|Exception):\s*'),
        '',
      );
  const replacements = <String, String>{
    r'\bResourceTree\b': '资源内容',
    r'\bsections?\b': '章节',
    r'\brevision\s+ID\b': '历史版本标识',
    r'\brevisionId\b': '历史版本标识',
    r'\bJSON\b': '数据格式',
    r'\babsolute\s+limit\b': '容量上限',
    r'\bcompression\s+jobs?\b': '优化任务',
    r'\bassembly\s+revision\b': '资源版本',
    r'\bsectionId\b': '章节标识',
    r'\bgenerationId\b': '生成任务标识',
    r'\bresourceId\b': '资源标识',
    r'\btaskId\b': '任务标识',
    r'\battemptId\b': '尝试标识',
    r'\bpart[_ ]?id\b': '段落标识',
    r'\bparts?\b': '段落',
  };
  for (final replacement in replacements.entries) {
    message = message.replaceAll(
      RegExp(replacement.key, caseSensitive: false),
      replacement.value,
    );
  }
  return message;
}

AppDomainError _fromStableCode(String value) {
  final matches = AppErrorCode.values.where((item) => item.name == value);
  return AppDomainError(
    code: matches.isEmpty ? AppErrorCode.unknown : matches.first,
  );
}
