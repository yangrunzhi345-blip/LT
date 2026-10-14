import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../../domain/errors/app_error.dart';
import '../../domain/errors/diagnostic_envelope.dart';
import '../../domain/resources/generation_budget_allocation.dart';
import '../../services/api_error.dart';
import '../../services/llm_service.dart';
import '../../services/repositories/resource_tree_repository.dart';
import 'generation_patch_parser.dart';
import 'part_generation_parser.dart';
import 'part_generation_validator.dart';

/// The operation owning a failure, rather than a guess based on its text.
enum ResourceGenerationFailureStage { unknown, parsing, persistence, lifecycle }

/// Projects known failures to safe, stable codes without retaining payloads.
///
/// Two failures that used to collapse into one code are now distinct so the UI
/// and the retry policy can tell them apart:
/// - [AppErrorCode.resourceGenerationBudgetInfeasible]: the frozen budget can
///   never satisfy this Part; no model request must be made until constraints
///   change (carries safe budget numbers).
/// - [AppErrorCode.resourceGenerationBudgetExceeded]: this output exceeded the
///   authorized maximum; a bounded corrective retry is allowed.
/// - [AppErrorCode.resourceContentIncomplete]: the body failed its confirmed
///   content contract (minimum / required sections / required fields).
///
/// Only safe, structured numbers are attached as [AppDomainError.parameters];
/// prompts, bodies, credentials and provider payloads are never retained.
AppDomainError resourceGenerationError(
  Object error, {
  ResourceGenerationFailureStage stage = ResourceGenerationFailureStage.unknown,
}) {
  switch (error) {
    case AppDomainError value:
      return value;
    case ApiError value:
      return AppDomainError(code: value.code);
    case LLMResponseIncompleteException() || ReasoningOnlyResponseException():
      return const AppDomainError(
          code: AppErrorCode.resourceProviderIncomplete);
    case PartGenerationParseException() || GenerationPatchParseException():
      return const AppDomainError(code: AppErrorCode.resourceParseFailed);
    case PartGenerationBudgetInfeasibleException value:
      return AppDomainError(
        code: AppErrorCode.resourceGenerationBudgetInfeasible,
        parameters: _budgetDiagnostic(value.allocation),
      );
    case PartGenerationValidationException value:
      return AppDomainError(
        code: _validationCode(value),
        parameters: value.parameters,
      );
    case PatchSequenceGapException() ||
          PatchSequenceConflictException() ||
          PatchCursorMismatchException():
      return const AppDomainError(code: AppErrorCode.resourceParseFailed);
    case ResourceTreeConflictException():
      return const AppDomainError(code: AppErrorCode.resourceConflict);
    case DatabaseException():
      return const AppDomainError(code: AppErrorCode.resourcePersistenceFailed);
    case TimeoutException():
      return const AppDomainError(code: AppErrorCode.timeout);
    case SocketException() || TlsException() || http.ClientException():
      return const AppDomainError(code: AppErrorCode.networkUnavailable);
    case String value:
      return resourceGenerationErrorFromCode(value);
    default:
      return AppDomainError(
        code: switch (stage) {
          ResourceGenerationFailureStage.parsing =>
            AppErrorCode.resourceParseFailed,
          ResourceGenerationFailureStage.persistence =>
            AppErrorCode.resourcePersistenceFailed,
          ResourceGenerationFailureStage.lifecycle =>
            AppErrorCode.resourceLifecycleFailed,
          ResourceGenerationFailureStage.unknown => AppErrorCode.unknown,
        },
      );
  }
}

/// The code for a validation failure, by the field it rejected.
///
/// Content-contract completeness, an over-budget output and any other invalid
/// content are deliberately separate codes so they get different copy and a
/// different retry disposition.
AppErrorCode _validationCode(PartGenerationValidationException error) =>
    switch (error.field) {
      'generation_budget' => AppErrorCode.resourceGenerationBudgetExceeded,
      'content_requirements' => AppErrorCode.resourceContentIncomplete,
      _ => AppErrorCode.resourceContentInvalid,
    };

/// Safe numeric context for an infeasible dispatch. No prose, no secrets.
Map<String, Object?> _budgetDiagnostic(PartGenerationBudgetAllocation value) =>
    {
      if (value.ceiling != null) 'ceiling': value.ceiling,
      'saved': value.savedOther,
      'remaining': value.remaining,
      'reserve': value.futureReserve,
      'minimum': value.minimumCharacters,
      'allowed': value.dispatchableMaximum,
      'unfinished': value.unfinishedRequiredCount,
    };

/// Encodes a generation failure for a legacy text column or an event field.
///
/// Returns the plain stable code when there is nothing extra to carry, or a
/// [DiagnosticEnvelope] when safe numeric parameters exist. This is the single
/// encoding the coordinator persists (`error_message`) and passes to failure
/// callbacks, so the exact same safe numbers survive a restart.
String encodeGenerationDiagnostic(
  Object error, {
  ResourceGenerationFailureStage stage = ResourceGenerationFailureStage.unknown,
}) {
  final domain = resourceGenerationError(error, stage: stage);
  if (domain.parameters.isEmpty) return domain.code.name;
  return DiagnosticEnvelope(
          code: domain.code.name, parameters: domain.parameters)
      .encode();
}

/// Decodes a persisted code, or a [DiagnosticEnvelope] carrying safe numbers.
/// Historical diagnostics and unrecognized codes remain explicitly unknown.
AppDomainError resourceGenerationErrorFromCode(String value) {
  final envelope = DiagnosticEnvelope.tryDecode(value);
  if (envelope != null) {
    return AppDomainError(
      code: _codeByName(envelope.code),
      parameters: envelope.parameters,
    );
  }
  return AppDomainError(code: _codeByName(value));
}

AppErrorCode _codeByName(String value) {
  for (final code in AppErrorCode.values) {
    if (code.name == value) return code;
  }
  return AppErrorCode.unknown;
}
