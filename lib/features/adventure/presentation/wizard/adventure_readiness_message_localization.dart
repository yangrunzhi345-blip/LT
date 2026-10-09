import '../../../../core/localization/app_error_localizer.dart';
import '../../../../domain/errors/app_error.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../application/adventure/adventure_readiness_gate.dart';

/// Converts a launch failure into the safe typed error the UI localizes.
///
/// A readiness gate refusal is a well-defined, actionable condition — not an
/// unknown crash. Unwrap the gate's typed `error` when it carries one (a
/// missing/unparseable assembly card), otherwise report the stable readiness
/// category, so the start boundary never shows 「未知错误」 for a resource that
/// simply is not assembled/ready yet.
AppDomainError adventureLaunchError(Object error) {
  if (error is AdventureReadinessGateException) {
    return error.error ??
        const AppDomainError(code: AppErrorCode.adventureReadinessFailed);
  }
  return asAppDomainError(error);
}

/// Keeps per-resource issues at both assembly launch presentation boundaries.
String localizeAdventureLaunchFailure(Object error, AppLocalizations l10n) {
  if (error is AdventureReadinessGateException) {
    if (error.issues.isNotEmpty) {
      return error.issues
          .map((issue) => '${localizeAdventureReadiness(issue, l10n)} '
              '[${issue.assetId}; ${issue.status.name}]')
          .join('\n');
    }
    if (error.messages.isNotEmpty) {
      return error.messages
          .map((message) => localizeAdventureReadinessMessage(message, l10n))
          .join('\n');
    }
  }
  return localizeAppError(l10n, adventureLaunchError(error));
}

/// Localizes a typed readiness result without comparing localized sentences.
String localizeAdventureReadiness(
  AdventureAssetReadiness readiness,
  AppLocalizations l10n,
) {
  final name = readiness.parameters['name']?.toString() ?? '';
  final details = readiness.parameters['details']?.toString() ?? '';
  final diagnosticCode = readiness.parameters['diagnosticCode']?.toString();
  final diagnosticDetails = diagnosticCode == null
      ? ''
      : localizeReadinessDiagnostic(
          diagnosticCode,
          readiness.parameters,
          l10n,
        );
  switch (readiness.effectiveIssueCode) {
    case AdventureReadinessIssueCode.notManaged:
      return l10n.adventureAssetNotManaged;
    case AdventureReadinessIssueCode.noSavedRevision:
      return l10n.adventureAssetNoSavedRevision(name);
    case AdventureReadinessIssueCode.preparing:
      final resolved =
          diagnosticDetails.isNotEmpty ? diagnosticDetails : details;
      return resolved.isEmpty
          ? l10n.adventureAssetPreparing(name)
          : l10n.adventureAssetPreparingWithDetails(name, resolved);
    case AdventureReadinessIssueCode.preparationFailed:
      final resolved =
          diagnosticDetails.isNotEmpty ? diagnosticDetails : details;
      final context = [
        readiness.parameters['stage'],
        readiness.parameters['exceptionType'],
      ].whereType<String>().join(' / ');
      return l10n.adventureAssetPreparationFailed(
        name,
        '${resolved.isEmpty ? l10n.readinessDiagnosticPreparationFailed : resolved}'
        '${context.isEmpty ? '' : ' ($context)'}',
      );
    case AdventureReadinessIssueCode.ready:
      return l10n.adventureAssetReady(name);
    case AdventureReadinessIssueCode.noAssemblyRevision:
      return l10n.adventureAssetNoAssemblyRevision(name);
    case AdventureReadinessIssueCode.staleWithPreviousReady:
      return l10n.adventureAssetStaleWithPrevious(name);
  }
}

/// Maps a readiness diagnostic code to localized detail text.
String localizeReadinessDiagnostic(
  String code,
  Map<String, Object?> parameters,
  AppLocalizations l10n,
) =>
    switch (code) {
      'resourceMissing' => l10n.readinessDiagnosticResourceMissing,
      'noSavedRevision' => l10n.readinessDiagnosticNoSavedRevision,
      'compressionUnavailable' =>
        l10n.readinessDiagnosticCompressionUnavailable,
      'compressionPending' => l10n.readinessDiagnosticCompressionPending,
      'staleResource' => l10n.readinessDiagnosticStaleResource,
      'assemblyRevisionMissing' =>
        l10n.readinessDiagnosticAssemblyRevisionMissing,
      'revisionHashMismatch' => l10n.readinessDiagnosticRevisionHashMismatch,
      'assemblyValidationFailed' =>
        l10n.readinessDiagnosticAssemblyValidationFailed,
      'preparationFailed' => l10n.readinessDiagnosticPreparationFailed,
      'interruptedPreparation' =>
        l10n.readinessDiagnosticInterruptedPreparation,
      _ => l10n.readinessDiagnosticUnknown,
    };

/// Localizes the stable readiness message templates produced by the gate.
///
/// Readiness details remain diagnostic text from assembly validation; this
/// maps only the gate's user-facing framing and resource name.
String localizeAdventureReadinessMessage(
  String message,
  AppLocalizations l10n,
) {
  if (message == '该资源不属于统一资源库，不参与版本就绪检查') {
    return l10n.adventureAssetNotManaged;
  }
  if (message == '组装版本缺少角色卡，无法开始冒险') {
    return l10n.adventureAssemblyMissingCharacterCard;
  }
  if (message == '组装版本角色卡无法解析，无法开始冒险') {
    return l10n.adventureAssemblyInvalidCharacterCard;
  }

  final noSavedRevision =
      RegExp(r'^「(.*)」还没有已保存的版本，无法开始冒险$').firstMatch(message);
  if (noSavedRevision != null) {
    return l10n.adventureAssetNoSavedRevision(noSavedRevision.group(1)!);
  }

  final preparingWithDetails = RegExp(r'^「(.*)」准备中：(.+)$').firstMatch(message);
  if (preparingWithDetails != null) {
    return l10n.adventureAssetPreparingWithDetails(
      preparingWithDetails.group(1)!,
      preparingWithDetails.group(2)!,
    );
  }

  final preparing = RegExp(r'^「(.*)」正在组装准备，请稍候$').firstMatch(message);
  if (preparing != null) {
    return l10n.adventureAssetPreparing(preparing.group(1)!);
  }

  final failed = RegExp(r'^「(.*)」准备失败：(.+)$').firstMatch(message);
  if (failed != null) {
    return l10n.adventureAssetPreparationFailed(
      failed.group(1)!,
      failed.group(2)!,
    );
  }

  final ready = RegExp(r'^「(.*)」已就绪$').firstMatch(message);
  if (ready != null) return l10n.adventureAssetReady(ready.group(1)!);

  final noAssemblyRevision =
      RegExp(r'^「(.*)」尚无可用版本，请先完成资源组装准备$').firstMatch(message);
  if (noAssemblyRevision != null) {
    return l10n.adventureAssetNoAssemblyRevision(
      noAssemblyRevision.group(1)!,
    );
  }

  final stale = RegExp(r'^「(.*)」已修改，可使用上一个已就绪版本$').firstMatch(message);
  if (stale != null) {
    return l10n.adventureAssetStaleWithPrevious(stale.group(1)!);
  }

  return message;
}
